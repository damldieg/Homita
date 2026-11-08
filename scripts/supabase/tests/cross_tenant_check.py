#!/usr/bin/env python3
"""Aislamiento entre tenants (T15, criterio global 3): el usuario B no lee ni escribe entidades de
A — ids de A → `500 {"error":"Not Found"}` (paridad PHP `TaskListUser::check` → selectOneOrFail,
`Database.php:56`), las RPC directas `/rest/v1/rpc/*` con el JWT de B devuelven 0 filas de A (o
`Not Found`), `materialize_routine` con rutina ajena → `Not Found`, y el rol viewer solo cambia
sus flags propias (403 `{"error":"Not Allowed"}` en lo compartido, matriz §3).

Casos (~55): 8 lecturas Edge, 23 escrituras Edge, 11 RPC directas PostgREST con JWT de B
(incl. `get_task_list_users`, `get_calendar_users`, `get_user_me`, `materialize_routine`) y 15
owner-vs-viewer. Criterio de fuga: cualquier dato de A donde la matriz/paridad PHP no lo permite.

Setup/limpieza solo con service_role (stack local): usuarios xt-a/xt-b vía user/create (requiere
ALLOW_REGISTRATION=true en la Edge o usuarios preexistentes) y filas XT-% borradas al inicio y al
final para que el script sea repetible. Nunca contra producción.

Variables de entorno: SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY (limpieza),
SUPABASE_FUNCTIONS_URL (defaults = stack local). Python stdlib.
Uso: python3 scripts/supabase/tests/cross_tenant_check.py
"""
import datetime
import json
import os
import sys
import urllib.error
import urllib.request

URL = os.environ.get("SUPABASE_URL", "http://127.0.0.1:54321").rstrip("/")
FN = os.environ.get("SUPABASE_FUNCTIONS_URL", URL + "/functions/v1/api").rstrip("/")
ANON = os.environ.get("SUPABASE_ANON_KEY", "")
SVC = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
TZ = "Europe/Madrid"
A_EMAIL, A_PASSWORD, A_NAME = "xt-a@homita.example", "xt-a-12345", "XT Owner"
B_EMAIL, B_PASSWORD, B_NAME = "xt-b@homita.example", "xt-b-12345", "XT Viewer"
NOT_FOUND = (500, '{"error":"Not Found"}')
NOT_ALLOWED = (403, '{"error":"Not Allowed"}')

if not ANON or not SVC:
    sys.exit("Faltan SUPABASE_ANON_KEY y/o SUPABASE_SERVICE_ROLE_KEY")


def request(base, method, path, body=None, token=None, apikey=None):
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = "Bearer " + token
    if apikey:
        headers["apikey"] = apikey
        headers.setdefault("Authorization", "Bearer " + apikey)  # service_role también autoriza
    req = urllib.request.Request(base + path, data=json.dumps(body).encode() if body is not None else None,
                                 method=method, headers=headers)
    try:
        with urllib.request.urlopen(req) as r:
            return r.status, r.read().decode()
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()
    except urllib.error.URLError:
        sys.exit(f"No responde {base}: arranca el stack local (supabase start + functions serve)")


def edge(method, path, body=None, token=None):
    return request(FN, method, path, body, token)


def rpc_direct(name, args, token):
    """RPC PostgREST directa con el JWT del usuario (sin pasar por la Edge)."""
    return request(URL, "POST", "/rest/v1/rpc/" + name, args, token, apikey=ANON)


def parse(text):
    try:
        return json.loads(text)
    except ValueError:
        return text


def clean_xt():
    """Filas XT-% de ejecuciones anteriores (hijos primero: cascade PG cubre las uniones, pero se
    borran también explícitas por si acaso). Verifica al final: si queda alguna fila, aborta (un
    resto silencioso contamina las aserciones de la fase 1)."""
    for table, column in (("event", "title"), ("routine", "title"), ("task", "title"),
                          ("task_list", "name"), ("calendar", "name"), ("person", "name")):
        status, text = request(URL, "DELETE", f"/rest/v1/{table}?{column}=like.XT-*", None, None, apikey=SVC)
        if status not in (200, 204):
            sys.exit(f"clean_xt: DELETE {table} → {status}: {text[:200]}")
    for table, column in (("event", "title"), ("routine", "title"), ("task", "title"),
                          ("task_list", "name"), ("calendar", "name"), ("person", "name")):
        status, text = request(URL, "GET", f"/rest/v1/{table}?{column}=like.XT-*&select=id", None, None, apikey=SVC)
        if status != 200 or parse(text):
            sys.exit(f"clean_xt: quedan filas XT-% en {table}: {text[:200]}")


results = []


def check(name, ok, detail=""):
    results.append(bool(ok))
    print(("ok   " if ok else "FAIL ") + name)
    if not ok and detail:
        print("     " + detail)


def expect(name, res, expected):
    """(status, cuerpo-exacto) como contract_check."""
    check(name, res == expected, f"obtenido {res!r} ≠ esperado {expected!r}")


def expect_err(name, res, message):
    """RPC PostgREST: no 2xx y message exacto (p.ej. 'Not Found')."""
    body = parse(res[1])
    ok = res[0] not in (200, 201, 204) and isinstance(body, dict) and body.get("message") == message
    check(name, ok, f"obtenido {res!r}")


clean_xt()

# ── usuarios A (owner) y B (viewer): user/create + user/auth ──
for email, password, name in ((A_EMAIL, A_PASSWORD, A_NAME), (B_EMAIL, B_PASSWORD, B_NAME)):
    edge("POST", "/user/create", {"name": name, "email": email, "password": password})  # si ya existe, auth basta
a_auth = edge("POST", "/user/auth", {"email": A_EMAIL, "password": A_PASSWORD})
b_auth = edge("POST", "/user/auth", {"email": B_EMAIL, "password": B_PASSWORD})
if a_auth[0] != 200 or b_auth[0] != 200:
    sys.exit("no se pudo autenticar xt-a/xt-b (¿ALLOW_REGISTRATION=true en la Edge para el alta?)")
a_tok, b_tok = parse(a_auth[1])["token"], parse(b_auth[1])["token"]
a_id, b_id = parse(a_auth[1])["id"], parse(b_auth[1])["id"]

# ── datos de A: calendario (+ privado), lista, persona, rutina, evento, tarea ──
cal = parse(edge("POST", "/calendar/create", {"name": "XT-Cal", "color": "#123456"}, a_tok)[1])["id"]
priv = parse(edge("POST", "/calendar/create", {"name": "XT-Privado", "color": "#654321"}, a_tok)[1])["id"]
lst = parse(edge("POST", "/task-list/create",
                 {"name": "XT-Lista", "color": "#222222", "sort": "title"}, a_tok)[1])["id"]
per = parse(edge("POST", "/person/create", {"name": "XT-Persona", "color": "#AABBCC"}, a_tok)[1])["id"]
start = (datetime.date.today() - datetime.timedelta(days=7)).isoformat()
rou = parse(edge("POST", f"/routine/create?timezone={TZ}", {
    "calendar_id": cal, "title": "XT-Rutina", "frequency": "weekly", "interval": 1,
    "days": [1, 3], "time": "09:30", "start_date": start, "end_date": None,
    "active": True, "alarm": 10}, a_tok)[1])["id"]
evt = parse(edge("POST", f"/event/create?timezone={TZ}",
                 {"calendar_id": cal, "title": "XT-Evento", "date_at": "2026-12-20 12:00:00",
                  "alarm": 15}, a_tok)[1])["id"]
tsk = parse(edge("POST", "/task/create", {"task_list_id": lst, "title": "XT-Tarea"}, a_tok)[1])["id"]

# ── Fase 1: B aislado — lecturas Edge de ids de A → 500 Not Found ──
for name, method, path, body in [
    ("B GET /calendar/detail de A → Not Found", "GET", f"/calendar/detail?id={cal}", None),
    ("B GET /calendar/detail del privado de A → Not Found", "GET", f"/calendar/detail?id={priv}", None),
    ("B GET /task-list/detail de A → Not Found", "GET", f"/task-list/detail?id={lst}", None),
    ("B GET /task/detail de A → Not Found", "GET", f"/task/detail?id={tsk}", None),
    ("B GET /event/detail de A → Not Found", "GET", f"/event/detail?id={evt}&timezone={TZ}", None),
    ("B GET /routine/detail de A → Not Found", "GET", f"/routine/detail?id={rou}&timezone={TZ}", None),
    ("B GET /calendar/user de A → Not Found", "GET", f"/calendar/user?calendar_id={cal}", None),
    ("B GET /task-list/user de A → Not Found", "GET", f"/task-list/user?task_list_id={lst}", None),
]:
    expect(name, edge(method, path, body, b_tok), NOT_FOUND)

# ── Fase 1: B aislado — escrituras Edge sobre ids de A → 500 Not Found ──
for name, method, path, body in [
    ("B PATCH /calendar/update de A → Not Found", "PATCH", "/calendar/update",
     {"id": cal, "name": "XT-Cal B", "color": "#123456", "widget": False, "dashboard": True}),
    ("B DELETE /calendar/delete de A → Not Found", "DELETE", "/calendar/delete", {"id": cal}),
    ("B POST /calendar/user invita en calendario de A → Not Found", "POST", "/calendar/user",
     {"calendar_id": cal, "email": A_EMAIL}),
    ("B DELETE /calendar/user saca a A → Not Found", "DELETE", "/calendar/user",
     {"calendar_id": cal, "user_id": a_id}),
    ("B PATCH /task-list/update de A → Not Found", "PATCH", "/task-list/update",
     {"id": lst, "name": "XT-Lista B", "color": "#222222", "sort": "title"}),
    ("B DELETE /task-list/delete de A → Not Found", "DELETE", "/task-list/delete", {"id": lst}),
    ("B POST /task-list/user invita en lista de A → Not Found", "POST", "/task-list/user",
     {"task_list_id": lst, "email": A_EMAIL}),
    ("B DELETE /task-list/user saca a A → Not Found", "DELETE", "/task-list/user",
     {"task_list_id": lst, "user_id": a_id}),
    ("B PATCH /person/update de A → Not Found (A7)", "PATCH", "/person/update",
     {"id": per, "name": "XT-Persona B", "color": "#AABBCC"}),
    ("B DELETE /person/delete de A → Not Found (A7)", "DELETE", "/person/delete", {"id": per}),
    ("B POST /task/create en lista de A → Not Found", "POST", "/task/create",
     {"task_list_id": lst, "title": "XT-Intruso"}),
    ("B PATCH /task/update de A → Not Found", "PATCH", "/task/update", {"id": tsk, "title": "XT-Tarea B"}),
    ("B PATCH /task/complete de A → Not Found", "PATCH", "/task/complete", {"id": tsk, "completed": True}),
    ("B PATCH /task/order de A → Not Found", "PATCH", "/task/order", {"id": tsk, "position": 0}),
    ("B DELETE /task/delete de A → Not Found", "DELETE", "/task/delete", {"id": tsk}),
    ("B POST /routine/create en calendario de A → Not Found", "POST", f"/routine/create?timezone={TZ}",
     {"calendar_id": cal, "title": "XT-Intrusa", "frequency": "weekly", "interval": 1,
      "days": [2], "time": "10:00", "start_date": start, "end_date": None, "active": True}),
    ("B PATCH /routine/update de A → Not Found", "PATCH", f"/routine/update?timezone={TZ}",
     {"id": rou, "title": "XT-Rutina B", "frequency": "weekly", "interval": 1,
      "days": [1, 3], "time": "10:00", "start_date": start, "end_date": None, "active": True}),
    ("B PATCH /routine/alarm de A → Not Found", "PATCH", f"/routine/alarm?timezone={TZ}",
     {"id": rou, "alarm": 20}),
    ("B DELETE /routine/delete de A → Not Found", "DELETE", f"/routine/delete?timezone={TZ}", {"id": rou}),
    ("B POST /event/create en calendario de A → Not Found", "POST", f"/event/create?timezone={TZ}",
     {"calendar_id": cal, "title": "XT-Intruso", "date_at": "2026-12-21 12:00:00"}),
    ("B PATCH /event/update de A → Not Found", "PATCH", f"/event/update?timezone={TZ}",
     {"id": evt, "title": "XT-Evento B", "date_at": "2026-12-22 12:00:00", "alarm": 15}),
    ("B PATCH /event/alarm de A → Not Found", "PATCH", f"/event/alarm?timezone={TZ}",
     {"event_id": evt, "alarm": 30}),
    ("B DELETE /event/delete de A → Not Found", "DELETE", f"/event/delete?timezone={TZ}", {"id": evt}),
]:
    expect(name, edge(method, path, body, b_tok), NOT_FOUND)

# ── Fase 1: RPC directas PostgREST con JWT de B — 0 filas de A ──
for name, rpc_name in [
    ("B rpc get_calendars → []", "get_calendars"),
    ("B rpc get_task_lists → []", "get_task_lists"),
    ("B rpc get_persons → []", "get_persons"),
    ("B rpc get_routines → []", "get_routines"),
]:
    res = rpc_direct(rpc_name, {}, b_tok)
    check(name, res[0] == 200 and parse(res[1]) == [], repr(res)[:200])
for name, rpc_name, args in [
    ("B rpc get_calendar_users de A → Not Found", "get_calendar_users", {"p_calendar_id": cal}),
    ("B rpc get_task_list_users de A → Not Found", "get_task_list_users", {"p_task_list_id": lst}),
    ("B rpc get_routine_detail de A → Not Found", "get_routine_detail", {"p_id": rou}),
    ("B rpc get_event_detail de A → Not Found", "get_event_detail", {"p_id": evt}),
    ("B rpc get_task_detail de A → Not Found", "get_task_detail", {"p_id": tsk}),
    ("B rpc materialize_routine de A → Not Found", "materialize_routine",
     {"p_routine_id": rou, "p_timezone": TZ, "p_reconcile": False}),
]:
    expect_err(name, rpc_direct(rpc_name, args, b_tok), "Not Found")
me = rpc_direct("get_user_me", {}, b_tok)
check("B rpc get_user_me → solo lo propio (sin datos de A)",
      me[0] == 200 and parse(me[1]).get("email") == B_EMAIL and parse(me[1]).get("id") != a_id,
      repr(me)[:200])

# ── Fase 2: B viewer en el calendario de A (matriz §3: owner vs viewer) ──
check("owner POST /calendar/user invita a B → 200 (control positivo)",
      edge("POST", "/calendar/user", {"calendar_id": cal, "email": B_EMAIL}, a_tok)[0] == 200)
check("viewer GET /calendar/detail del compartido → 200",
      edge("GET", f"/calendar/detail?id={cal}", None, b_tok)[0] == 200)
expect("viewer PATCH /calendar/update cambia name → 403",
       edge("PATCH", "/calendar/update", {"id": cal, "name": "XT-Cal B", "color": "#123456",
                                          "widget": False, "dashboard": True}, b_tok), NOT_ALLOWED)
expect("viewer DELETE /calendar/delete → 403",
       edge("DELETE", "/calendar/delete", {"id": cal}, b_tok), NOT_ALLOWED)
expect("viewer POST /calendar/user invita → 403",
       edge("POST", "/calendar/user", {"calendar_id": cal, "email": A_EMAIL}, b_tok), NOT_ALLOWED)
expect("viewer DELETE /calendar/user saca a A → 403",
       edge("DELETE", "/calendar/user", {"calendar_id": cal, "user_id": a_id}, b_tok), NOT_ALLOWED)
res = edge("PATCH", "/calendar/update", {"id": cal, "name": "XT-Cal", "color": "#123456",
                                        "widget": False}, b_tok)
check("viewer PATCH /calendar/update solo flags propias → 200", res[0] == 200, repr(res)[:200])
cals = rpc_direct("get_calendars", {}, b_tok)
names = sorted(c.get("name") for c in parse(cals[1])) if cals[0] == 200 else None
check("B rpc get_calendars → SOLO el compartido (sin XT-Privado de A)", names == ["XT-Cal"], repr(cals)[:200])
expect("viewer GET /calendar/detail del privado de A → Not Found (0 fugas)",
       edge("GET", f"/calendar/detail?id={priv}", None, b_tok), NOT_FOUND)
cu = rpc_direct("get_calendar_users", {"p_calendar_id": cal}, b_tok)
emails = sorted(m.get("email") for m in parse(cu[1])) if cu[0] == 200 else None
check("B rpc get_calendar_users del compartido → A y B (paridad PHP, no fuga)",
      emails == sorted([A_EMAIL, B_EMAIL]), repr(cu)[:200])
check("owner POST /task-list/user invita a B → 200 (control positivo)",
      edge("POST", "/task-list/user", {"task_list_id": lst, "email": B_EMAIL}, a_tok)[0] == 200)
expect("viewer PATCH /task-list/update cambia name → 403",
       edge("PATCH", "/task-list/update", {"id": lst, "name": "XT-Lista B", "color": "#222222",
                                           "sort": "title"}, b_tok), NOT_ALLOWED)
res = edge("PATCH", "/task-list/update", {"id": lst, "name": "XT-Lista", "color": "#222222",
                                         "sort": "title", "widget": False}, b_tok)
check("viewer PATCH /task-list/update solo flags propias → 200", res[0] == 200, repr(res)[:200])
check("viewer POST /task/create en la lista compartida → 200 (A8: escribe contenido)",
      edge("POST", "/task/create", {"task_list_id": lst, "title": "XT-Tarea B"}, b_tok)[0] in (200, 201))
check("viewer GET /task-list/detail del compartido → 200",
      edge("GET", f"/task-list/detail?id={lst}", None, b_tok)[0] == 200)

clean_xt()
fugas = results.count(False)
print(f"\n{len(results) - fugas}/{len(results)} casos ok — {fugas} fugas")
sys.exit(1 if fugas else 0)
