#!/usr/bin/env python3
"""Aislamiento entre tenants (T15/T10, criterio global 3 + modelo Home 1.3): el usuario B no lee ni
escribe entidades de A — ids de A → `500 {"error":"Not Found"}` (paridad PHP `TaskListUser::check`
→ selectOneOrFail, `Database.php:56`), las RPC directas `/rest/v1/rpc/*` con el JWT de B devuelven
0 filas de A (o `Not Found`), `materialize_routine` con rutina ajena → `Not Found`, y el rol viewer
solo cambia sus flags propias (403 `{"error":"Not Allowed"}` en lo compartido, matriz §3).

Modelo Home (1.3, plan 1.3 §Suites): `xt-a` y `xt-b` por `/user/create` → hogares personales
distintos (0014a). Fase 2 en el orden nuevo: owner invita a B (no miembro del hogar del recurso) →
403 `Not Allowed` (Q3) y sin filas; psql (replica) crea la membresía de B en home(A) con el snapshot
legacy de 17 permisos y mueve `home_member`+`person` de `b_per` a home(A); las invitaciones repiten
→ 200 con ACL `viewer` y `home_id` de A; viewer sigue viendo su calendario; P1 asigna `b_per` al
evento de A → 200 (trigger 0015 iv válido). R1 reescrito: el insert directo cross-home en modo
normal → `Invalid person` `P0001` y `update_event` por RPC → 400 `Invalid person`; la contaminación
heredada se prepara en replica (preparación, no caso de éxito) y el filtro de lectura la oculta.

Regresión H0 (h0-hotfix-fuga-rpc): F1–F4 fuga cross-tenant de personas por escritura RPC directa
con `p_person_ids` de B, V1–V4/V1b/V2b validación de título/fecha en la RPC, P1/N1 positivos (persona
de co-miembro y `p_person_ids = null` sin cambios).

Setup/limpieza: usuarios xt-a/xt-b vía user/create (requiere ALLOW_REGISTRATION=true en la Edge o
usuarios preexistentes) y `clean_xt()` completo (filas XT-%, membresías y hogares personales de xt y
sus cuentas auth — se recrean en cada pasada: sin hogar, `create_calendar` fallaría con `Home header
required`). Nunca contra producción.

Variables de entorno: SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY (limpieza),
SUPABASE_FUNCTIONS_URL (defaults = stack local) y PSQL (comando psql contra la BD local; para el
stack local `docker exec`: `PSQL="docker exec -i supabase_db_homita-api psql -U postgres -d postgres"`).
Python stdlib. Uso: python3 scripts/supabase/tests/cross_tenant_check.py
"""
import datetime
import json
import os
import shlex
import subprocess
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
# Snapshot member legacy (Q-B, plan 1.2 §5): 17 permisos del viewer de antes del modelo Home
LEGACY17 = ("('home.view'), ('calendar.view'), ('task.view'), ('routine.view'), "
            "('task.create'), ('task.edit'), ('task.complete'), ('task.assign'), ('task.delete'), "
            "('event.create'), ('event.edit'), ('event.delete'), ('event.assign'), "
            "('routine.create'), ('routine.edit'), ('routine.delete'), ('routine.assign')")

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


def psql_run(sql, verbose=False):
    """SQL por psql local (variable PSQL: comando completo). Devuelve (rc, salida+errores)."""
    cmd = shlex.split(os.environ.get("PSQL", "psql"))
    args = cmd + ["-X", "-q", "-v", "ON_ERROR_STOP=1", "-t", "-A"]
    if verbose:
        args += ["-v", "VERBOSITY=verbose"]
    r = subprocess.run(args, input=sql, capture_output=True, text=True)
    return r.returncode, (r.stdout + r.stderr).strip()


def psql(sql):
    """SQL por psql local; aborta el script si falla. Devuelve la salida (una fila, -t -A)."""
    rc, out = psql_run(sql)
    if rc != 0:
        sys.exit(f"psql falló ({rc}): {out[:300]}")
    return out


def clean_xt():
    """Filas XT-% de ejecuciones anteriores (hijos primero: cascade PG cubre las uniones) y, en una
    transacción psql, las membresías de los usuarios xt o de sus hogares (CASCADE limpia ACL y
    membership_permission), los home_member sobrantes, sus hogares personales y sus cuentas auth.
    La transacción es única a propósito: el trigger anti-admin diferido de 0015 rechazaría un COMMIT
    que dejara hogares active sin admin. Las cuentas auth se borran para que cada pasada cree los
    usuarios con /user/create y 0014a les asigne hogar (sin hogar, create_calendar fallaría con
    'Home header required'). Verifica al final: sin filas XT-% ni membresías ni hogares de xt — así
    3 ejecuciones seguidas son verdes."""
    for table, column in (("event", "title"), ("routine", "title"), ("task", "title"),
                          ("task_list", "name"), ("calendar", "name"), ("person", "name")):
        status, text = request(URL, "DELETE", f"/rest/v1/{table}?{column}=like.XT-*", None, None, apikey=SVC)
        if status not in (200, 204):
            sys.exit(f"clean_xt: DELETE {table} → {status}: {text[:200]}")
    psql(f"""
begin;
delete from home_membership
    where app_user_id in (select id from app_user where email in ('{A_EMAIL}', '{B_EMAIL}'))
       or home_id in (select default_home_id from app_user where email in ('{A_EMAIL}', '{B_EMAIL}'));
delete from home_member
    where home_id in (select default_home_id from app_user where email in ('{A_EMAIL}', '{B_EMAIL}'));
delete from home
    where is_personal and created_by in (select id from app_user where email in ('{A_EMAIL}', '{B_EMAIL}'));
delete from auth.users
    where id in (select auth_uid from app_user where email in ('{A_EMAIL}', '{B_EMAIL}'));
commit;
""")
    for table, column in (("event", "title"), ("routine", "title"), ("task", "title"),
                          ("task_list", "name"), ("calendar", "name"), ("person", "name")):
        status, text = request(URL, "GET", f"/rest/v1/{table}?{column}=like.XT-*&select=id", None, None, apikey=SVC)
        if status != 200 or parse(text):
            sys.exit(f"clean_xt: quedan filas XT-% en {table}: {text[:200]}")
    left = psql(f"select count(*) from home_membership hm join app_user u on u.id = hm.app_user_id "
                f"where u.email in ('{A_EMAIL}', '{B_EMAIL}')")
    if left != "0":
        sys.exit(f"clean_xt: quedan membresías de xt ({left})")
    left = psql(f"select count(*) from home h join app_user u on u.id = h.created_by "
                f"where u.email in ('{A_EMAIL}', '{B_EMAIL}')")
    if left != "0":
        sys.exit(f"clean_xt: quedan hogares de xt ({left})")


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

# ── usuarios A (owner) y B (viewer): user/create + user/auth (0014a crea sus hogares) ──
for email, password, name in ((A_EMAIL, A_PASSWORD, A_NAME), (B_EMAIL, B_PASSWORD, B_NAME)):
    edge("POST", "/user/create", {"name": name, "email": email, "password": password})  # si ya existe, auth basta
a_auth = edge("POST", "/user/auth", {"email": A_EMAIL, "password": A_PASSWORD})
b_auth = edge("POST", "/user/auth", {"email": B_EMAIL, "password": B_PASSWORD})
if a_auth[0] != 200 or b_auth[0] != 200:
    sys.exit("no se pudo autenticar xt-a/xt-b (¿ALLOW_REGISTRATION=true en la Edge para el alta?)")
a_tok, b_tok = parse(a_auth[1])["token"], parse(b_auth[1])["token"]
a_id, b_id = parse(a_auth[1])["id"], parse(b_auth[1])["id"]

home_a = psql(f"select default_home_id from app_user where email = '{A_EMAIL}'")
home_b = psql(f"select default_home_id from app_user where email = '{B_EMAIL}'")
check("xt-a y xt-b por /user/create → dos hogares personales distintos (home(A) ≠ home(B))",
      home_a not in ("", None) and home_b not in ("", None) and home_a != home_b,
      f"home(A)={home_a} home(B)={home_b}")
home_a, home_b = int(home_a or 0), int(home_b or 0)

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

# ── H0 (h0-hotfix-fuga-rpc): personas cross-tenant por RPC directa y validación título/fecha ──
# Casos F1–F4/V1–V4/R1 con las familias de A y B aún disjuntas (A invita a B en la fase 2); los
# positivos P1/N1 van al final. Regresión de la fuga reproducida en
# `.dorch/archive/fase-0-auditorias/validacion-fuga-cross-tenant.md` (4/4).


def person_leak(res):
    """A1: la respuesta no contiene id/user_id/name/color/persons de la persona ajena."""
    body = parse(res[1])
    return isinstance(body, dict) and not any(k in body for k in ("id", "user_id", "name", "color", "persons"))


def svc_title(table, row_id):
    rows = parse(request(URL, "GET", f"/rest/v1/{table}?id=eq.{row_id}&select=title", None, None, apikey=SVC)[1])
    return rows[0]["title"] if isinstance(rows, list) and rows else None


b_per = parse(edge("POST", "/person/create", {"name": "XT-Persona-B", "color": "#ABCDEF"}, b_tok)[1])["id"]

# F1–F4 (fuga): escritura RPC directa con el JWT de A y p_person_ids = [persona de B]
f1 = rpc_direct("create_event", {"p_calendar_id": cal, "p_title": "XT-Fuga-F1", "p_date_at": "2026-12-30 10:00:00",
                                 "p_alarm": None, "p_person_ids": [b_per]}, a_tok)
check("F1 rpc create_event con persona de B → 400 Invalid person, sin datos de B",
      f1[0] == 400 and parse(f1[1]).get("message") == "Invalid person" and person_leak(f1), repr(f1)[:200])
f2 = rpc_direct("update_event", {"p_id": evt, "p_title": "XT-Fuga-F2", "p_date_at": "2026-12-20 12:00:00",
                                 "p_alarm": 15, "p_person_ids": [b_per], "p_timezone": TZ}, a_tok)
check("F2 rpc update_event con persona de B → 400 Invalid person, sin datos de B y título intacto",
      f2[0] == 400 and parse(f2[1]).get("message") == "Invalid person" and person_leak(f2)
      and svc_title("event", evt) == "XT-Evento", repr(f2)[:200])
f3 = rpc_direct("create_routine", {"p_calendar_id": cal, "p_title": "XT-Fuga-F3", "p_frequency": "weekly",
                                   "p_interval": 1, "p_days": [2], "p_time": "10:00", "p_start_date": start,
                                   "p_end_date": None, "p_active": True, "p_alarm": None,
                                   "p_person_ids": [b_per], "p_timezone": TZ}, a_tok)
check("F3 rpc create_routine con persona de B → 400 Invalid person, sin datos de B",
      f3[0] == 400 and parse(f3[1]).get("message") == "Invalid person" and person_leak(f3), repr(f3)[:200])
f4 = rpc_direct("update_routine", {"p_id": rou, "p_title": "XT-Fuga-F4", "p_frequency": "weekly",
                                   "p_interval": 1, "p_days": [1, 3], "p_time": "09:30", "p_start_date": start,
                                   "p_end_date": None, "p_active": True, "p_person_ids": [b_per],
                                   "p_timezone": TZ}, a_tok)
check("F4 rpc update_routine con persona de B → 400 Invalid person, sin datos de B y título intacto",
      f4[0] == 400 and parse(f4[1]).get("message") == "Invalid person" and person_leak(f4)
      and svc_title("routine", rou) == "XT-Rutina", repr(f4)[:200])
for name, table, param in (("F1-F4 sin filas nuevas en event_person para la persona de B", "event_person", "event_id"),
                           ("F1-F4 sin filas nuevas en routine_person para la persona de B", "routine_person", "routine_id")):
    rows = parse(request(URL, "GET", f"/rest/v1/{table}?person_id=eq.{b_per}&select={param}", None, None, apikey=SVC)[1])
    check(name, rows == [], repr(rows)[:200])

# V1–V4 (validación): mensajes exactos de la Edge (usecases/tasks.ts:56,65 y usecases/events.ts:91,116)
v1 = rpc_direct("create_task", {"p_task_list_id": lst, "p_title": ""}, a_tok)
check("V1 rpc create_task con título '' → 400 task_list_id and title are required",
      v1[0] == 400 and parse(v1[1]).get("message") == "task_list_id and title are required", repr(v1)[:200])
v1b = rpc_direct("create_task", {"p_task_list_id": lst, "p_title": "0"}, a_tok)
check("V1b rpc create_task con título '0' → 400 task_list_id and title are required",
      v1b[0] == 400 and parse(v1b[1]).get("message") == "task_list_id and title are required", repr(v1b)[:200])
v2 = rpc_direct("update_task", {"p_id": tsk, "p_title": ""}, a_tok)
check("V2 rpc update_task con título '' → 400 Task ID and title are required",
      v2[0] == 400 and parse(v2[1]).get("message") == "Task ID and title are required", repr(v2)[:200])
v2b = rpc_direct("update_task", {"p_id": tsk, "p_title": "0"}, a_tok)
check("V2b rpc update_task con título '0' → 400 Task ID and title are required",
      v2b[0] == 400 and parse(v2b[1]).get("message") == "Task ID and title are required", repr(v2b)[:200])
v3 = rpc_direct("create_event", {"p_calendar_id": cal, "p_title": "", "p_date_at": "2026-12-30 11:00:00",
                                 "p_alarm": None, "p_person_ids": None}, a_tok)
check("V3 rpc create_event con título '' → 400 Title and date_at are required if text is not provided",
      v3[0] == 400 and parse(v3[1]).get("message") == "Title and date_at are required if text is not provided",
      repr(v3)[:200])
v4 = rpc_direct("update_event", {"p_id": evt, "p_title": "XT-Evento", "p_date_at": "2026-13-45",
                                 "p_alarm": 15, "p_person_ids": None, "p_timezone": TZ}, a_tok)
check("V4 rpc update_event con date_at inválida → 400 Event ID, title, and date_at are required",
      v4[0] == 400 and parse(v4[1]).get("message") == "Event ID, title, and date_at are required", repr(v4)[:200])
tasks = parse(request(URL, "GET", f"/rest/v1/task?task_list_id=eq.{lst}&select=title", None, None, apikey=SVC)[1])
check("V1-V4 nada se escribe: la lista de A solo tiene su tarea", tasks == [{"title": "XT-Tarea"}], repr(tasks)[:200])

# ── R1 (reescrito, 0015 iv): el trigger persona↔recurso rechaza la asignación cross-home ──
# (i) insert directo en modo normal → 'Invalid person' P0001 (la inserción en replica solo prepara
# datos, nunca es caso de éxito); (ii) update_event por RPC con esa persona → 400 Invalid person.
rc, out = psql_run(f"insert into event_person (event_id, person_id) values ({evt}, {b_per});", verbose=True)
check("R1(i) insert event_person cross-home en modo normal → Invalid person P0001",
      rc != 0 and "P0001" in out and "Invalid person" in out, out[:200])
r1ii = rpc_direct("update_event", {"p_id": evt, "p_title": "XT-Evento", "p_date_at": "2026-12-20 12:00:00",
                                   "p_alarm": 15, "p_person_ids": [b_per], "p_timezone": TZ}, a_tok)
check("R1(ii) update_event por RPC con persona de home(B) → 400 Invalid person",
      r1ii[0] == 400 and parse(r1ii[1]).get("message") == "Invalid person" and person_leak(r1ii),
      repr(r1ii)[:200])

# R1 (contaminación heredada): filas de una era anterior preparadas en replica (solo preparación);
# el filtro de lectura (fn_event_persons/fn_routine_persons) las oculta para A.
request(URL, "POST", "/rest/v1/event",
        {"calendar_id": cal, "title": "XT-R1-Evento", "date_at": "2026-12-26 10:00:00"}, None, apikey=SVC)
r1_evt = parse(request(URL, "GET", "/rest/v1/event?title=eq.XT-R1-Evento&select=id", None, None, apikey=SVC)[1])[0]["id"]
request(URL, "POST", "/rest/v1/routine",
        {"calendar_id": cal, "title": "XT-R1-Rutina", "days": [1], "time": "09:30", "start_date": "2026-11-03",
         "end_date": None, "active": True, "available_from": "2026-11-09 00:00:00", "frequency": "weekly",
         "interval": 1}, None, apikey=SVC)
r1_rou = parse(request(URL, "GET", "/rest/v1/routine?title=eq.XT-R1-Rutina&select=id", None, None, apikey=SVC)[1])[0]["id"]
psql(f"""
set session_replication_role = replica;
insert into event_person (event_id, person_id) values ({r1_evt}, {b_per});
insert into routine_person (routine_id, person_id) values ({r1_rou}, {b_per});
set session_replication_role = default;
""")
r1e = rpc_direct("get_event_detail", {"p_id": r1_evt}, a_tok)
check("R1 get_event_detail de A no incluye la persona de B (contaminación heredada)",
      r1e[0] == 200 and all(p.get("id") != b_per for p in parse(r1e[1]).get("persons") or []), repr(r1e)[:200])
r1r = rpc_direct("get_routine_detail", {"p_id": r1_rou}, a_tok)
check("R1 get_routine_detail de A no incluye la persona de B (contaminación heredada)",
      r1r[0] == 200 and all(p.get("id") != b_per for p in parse(r1r[1]).get("persons") or []), repr(r1r)[:200])

# ── Fase 2 (orden nuevo, Q3): el invitado debe ser miembro del hogar del recurso ──
# (1) owner invita a B (no miembro) → 403 Not Allowed y sin filas nuevas
expect("owner POST /calendar/user invita a B → 403 Not Allowed (Q3)",
       edge("POST", "/calendar/user", {"calendar_id": cal, "email": B_EMAIL}, a_tok), NOT_ALLOWED)
rows = psql(f"select (select count(*) from calendar_user where calendar_id = {cal} and user_id = {b_id}) + "
            f"(select count(*) from home_membership where home_id = {home_a} and app_user_id = {b_id})")
check("tras el 403 no hay fila de B en calendar_user ni en home_membership de home(A)", rows == "0", f"filas={rows}")
expect("owner POST /task-list/user invita a B → 403 Not Allowed (Q3)",
       edge("POST", "/task-list/user", {"task_list_id": lst, "email": B_EMAIL}, a_tok), NOT_ALLOWED)
rows = psql(f"select (select count(*) from task_list_user where task_list_id = {lst} and user_id = {b_id}) + "
            f"(select count(*) from home_membership where home_id = {home_a} and app_user_id = {b_id})")
check("tras el 403 no hay fila de B en task_list_user ni en home_membership de home(A)", rows == "0", f"filas={rows}")

# (2) psql (replica): membresía de B en home(A) + snapshot legacy de 17 permisos y se mueven
# home_member + person de b_per a home(A) (mismo home_id en ambos; replica: el FK compuesto
# person↔home_member prohíbe moverlos en dos statements en modo normal)
psql(f"""
set session_replication_role = replica;
begin;
insert into home_membership (home_id, app_user_id, role) values ({home_a}, {b_id}, 'member');
insert into membership_permission (home_membership_id, permission_code)
select hm.id, c.code from home_membership hm
cross join (values {LEGACY17}) as c(code)
where hm.home_id = {home_a} and hm.app_user_id = {b_id};
update home_member set home_id = {home_a} where id = (select home_member_id from person where id = {b_per});
update person set home_id = {home_a} where id = {b_per};
commit;
set session_replication_role = default;
""")

# (3) repetir las invitaciones → 200 y ACL viewer con home_id de A (control positivo)
check("owner POST /calendar/user invita a B → 200 (tras membresía)",
      edge("POST", "/calendar/user", {"calendar_id": cal, "email": B_EMAIL}, a_tok)[0] == 200)
row = psql(f"select role || ' ' || home_id from calendar_user where calendar_id = {cal} and user_id = {b_id}")
check("ACL viewer con home_id de A (calendar_user)", row == f"viewer {home_a}", f"fila={row!r}")
check("owner POST /task-list/user invita a B → 200 (tras membresía)",
      edge("POST", "/task-list/user", {"task_list_id": lst, "email": B_EMAIL}, a_tok)[0] == 200)
row = psql(f"select role || ' ' || home_id from task_list_user where task_list_id = {lst} and user_id = {b_id}")
check("ACL viewer con home_id de A (task_list_user)", row == f"viewer {home_a}", f"fila={row!r}")

# (4) viewer B sigue viendo su calendario (matriz §3: owner vs viewer)
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

# ── H0: positivos — el filtro no rompe el uso legítimo ──
# P1 (co-miembro): b_per ya está en home(A) (movido en la fase 2) y B es co-miembro → asignable
# vía RPC; el trigger 0015(iv) la valida (misma home, activa)
p1 = rpc_direct("create_event", {"p_calendar_id": cal, "p_title": "XT-Positivo-P1", "p_date_at": "2026-12-28 12:00:00",
                                 "p_alarm": None, "p_person_ids": [b_per]}, a_tok)
check("P1 create_event de A con persona del co-miembro B → 200 y la persona aparece en persons",
      p1[0] == 200 and any(p.get("id") == b_per for p in parse(p1[1]).get("persons") or []), repr(p1)[:200])
# N1 (caso null): p_person_ids = null no cambia las asignaciones (comportamiento idéntico a pre-H0)
n1 = rpc_direct("create_event", {"p_calendar_id": cal, "p_title": "XT-Positivo-N1", "p_date_at": "2026-12-29 12:00:00",
                                 "p_alarm": None, "p_person_ids": [per]}, a_tok)
n1_id = parse(n1[1]).get("id") if n1[0] == 200 else None
n1u = rpc_direct("update_event", {"p_id": n1_id, "p_title": "XT-Positivo-N1", "p_date_at": "2026-12-29 12:00:00",
                                  "p_alarm": None, "p_person_ids": None, "p_timezone": TZ}, a_tok)
check("N1 update_event con p_person_ids=null conserva las asignaciones propias",
      n1u[0] == 200 and any(p.get("id") == per for p in parse(n1u[1]).get("persons") or []), repr(n1u)[:200])

clean_xt()
fugas = results.count(False)
print(f"\n{len(results) - fugas}/{len(results)} casos ok — {fugas} fugas")
sys.exit(1 if fugas else 0)
