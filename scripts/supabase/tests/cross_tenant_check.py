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

Miembros (1.5, plan §8.2): K8 cabecera X-Home-Id ajena en PATCH /home/member/update → 404, K11 baja
soft conserva el histórico (update_event con la misma lista → 200) y K12 asignación nueva de un
inactivo → 400 Invalid person; K20 usuario C con snapshot `adult` de member_kind_default (18
códigos sin home.view, no LEGACY17) → 403 en GET /home/member; K21 cascada app_user → person →
home_member (trigger 0014c) e invariante I5 (§8.3) al final.

Administradores (1.6, plan §6.4): C antes de unirse en K20 → 404 en las 3 rutas
/home/membership/* sin cambios en home(A); B (member) → 403 en role/transfer; cabecera
X-Home-Id de home(B) en las 3 rutas → 404; B sale de home(A) (200) y entonces
GET /calendar/detail del compartido → 500 Not Found (sus ACL se borran en cascada).

Permisos por kind (1.7, plan §6.3): C no miembro → 404 también en GET /home/membership de A; el
seed de la membresía de B en home(B) (dance demote/restore vía psql — R1-02: el helper de 0019
rechaza admins con 'Not Allowed') no altera la membresía de B en home(A) ni sus ACL, y los
permisos sembrados en home(B) no aparecen en GET /home/membership de A (B sigue con legacy17).

Matriz §3.4.1 (1.8, plan §6.4 y §6.3): aislamiento con la guardia de 0020 — admin de B sobre
XT-Otro (H donde B no es miembro) → 500 Not Found en lectura (calendar/detail, event/detail,
task-list/detail) y escritura (calendar/update, event/create, task/delete); co-miembro C sin ACL →
500 en la lectura admin-only y en escritura; admin A con ACL → 200 en lectura de todos los
calendarios de H (incluido sin ACL propia); cabecera X-Home-Id ajena en ruta legacy → 500 (los
/home/* 404 los cubren M5–M9 y el (5) «ACL tras DELETE /home/membership» lo cubren M10/M11).
Concurrencia (§6.3, R1-01/R1-02/R1-09): T-C1 (degradación ∥ update_calendar: bloqueo en home con
pg_stat_activity.wait_event_type='Lock' y Not Allowed tras commit), T-C1b (baja ∥ set_event_alarm:
Not Found y 0 filas nuevas en event_user), T-C2 HTTP ×3 (PATCH solo widget ∥ DELETE /home/membership
del propio U: 200/200 o 500 Not Found; ACL de U = 0 al final) y T-DL (10 pares W×D, ≥20
iteraciones por par, orden invertido, 2 sesiones psql; 0×40P01 — el outcome de W es 200 o
Not Found/Not Allowed si la mutación de membresía commitea antes). Fixtures §6.3: hogar scratch
XT-Conc con admins A y B (sin owner único: XT-C1 con owners A y B) y hogar personal en los tres
usuarios (sin 403 de último hogar).

Setup/limpieza: usuarios xt-a/xt-b vía user/create (requiere ALLOW_REGISTRATION=true en la Edge o
usuarios preexistentes) y `clean_xt()` completo (filas XT-%, membresías y hogares de xt — personales
y no personales (R1-04) — y sus cuentas auth: se recrean en cada pasada: sin hogar, `create_calendar` fallaría con `Home header
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
import threading
import time
import urllib.error
import urllib.parse
import urllib.request

URL = os.environ.get("SUPABASE_URL", "http://127.0.0.1:54321").rstrip("/")
FN = os.environ.get("SUPABASE_FUNCTIONS_URL", URL + "/functions/v1/api").rstrip("/")


def assert_local(url, what):
    """Guarda: este script BORRA datos (clean_xt, DELETE con service_role). Solo acepta hosts locales;
    sin excepciones (mismo criterio que contract_check.py). Evita que un SUPABASE_URL de producción en
    el entorno —p. ej. cargando ~/.homita/supabase.env— ejecute el borrado contra el proyecto alojado."""
    if urllib.parse.urlparse(url).hostname not in ("127.0.0.1", "localhost"):
        sys.exit(f"{what} solo acepta hosts locales (127.0.0.1/localhost), llega {url!r}: "
                 "este script escribe y borra datos y jamás debe tocar el proyecto alojado")


assert_local(URL, "SUPABASE_URL")
assert_local(FN, "SUPABASE_FUNCTIONS_URL")
ANON = os.environ.get("SUPABASE_ANON_KEY", "")
SVC = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
TZ = "Europe/Madrid"
A_EMAIL, A_PASSWORD, A_NAME = "xt-a@homita.example", "xt-a-12345", "XT Owner"
B_EMAIL, B_PASSWORD, B_NAME = "xt-b@homita.example", "xt-b-12345", "XT Viewer"
C_EMAIL, C_PASSWORD, C_NAME = "xt-c@homita.example", "xt-c-12345", "XT Extra"  # K20: snapshot adult
NOT_FOUND = (500, '{"error":"Not Found"}')
NOT_ALLOWED = (403, '{"error":"Not Allowed"}')
HOME_NOT_FOUND = (404, '{"error":"Not Found"}')  # rutas /home/* (D16): no miembro → 404, no 500
# Snapshot member legacy (Q-B, plan 1.2 §5): 17 permisos del viewer de antes del modelo Home
LEGACY17 = ("('home.view'), ('calendar.view'), ('task.view'), ('routine.view'), "
            "('task.create'), ('task.edit'), ('task.complete'), ('task.assign'), ('task.delete'), "
            "('event.create'), ('event.edit'), ('event.delete'), ('event.assign'), "
            "('routine.create'), ('routine.edit'), ('routine.delete'), ('routine.assign')")
# Los mismos 17 códigos en orden collate "C" (forma en que get_home_memberships devuelve el
# snapshot: json_agg order by permission_code collate "C", 0016) — §6.3 de 1.7.
LEGACY17_C = ['calendar.view', 'event.assign', 'event.create', 'event.delete', 'event.edit',
              'home.view', 'routine.assign', 'routine.create', 'routine.delete', 'routine.edit',
              'routine.view', 'task.assign', 'task.complete', 'task.create', 'task.delete',
              'task.edit', 'task.view']

if not ANON or not SVC:
    sys.exit("Faltan SUPABASE_ANON_KEY y/o SUPABASE_SERVICE_ROLE_KEY")


def request(base, method, path, body=None, token=None, apikey=None, home=None):
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = "Bearer " + token
    if apikey:
        headers["apikey"] = apikey
        headers.setdefault("Authorization", "Bearer " + apikey)  # service_role también autoriza
    if home is not None:  # contexto X-Home-Id (1.4 §2.2)
        headers["X-Home-Id"] = str(home)
    req = urllib.request.Request(base + path, data=json.dumps(body).encode() if body is not None else None,
                                 method=method, headers=headers)
    try:
        with urllib.request.urlopen(req) as r:
            return r.status, r.read().decode()
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()
    except urllib.error.URLError:
        sys.exit(f"No responde {base}: arranca el stack local (supabase start + functions serve)")


def edge(method, path, body=None, token=None, home=None):
    return request(FN, method, path, body, token, home=home)


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
    membership_permission), sus `person` — XT-% por nombre y por hogar (1.5 §8.4/R1-02: antes que
    `home_member`, porque person_home_member_fk es ON DELETE RESTRICT y la baja soft ya no borra
    person; el trigger 0014c borra su home_member) — los home_member sobrantes, sus hogares —
    personales y no personales, creados por xt (R1-04: XT-Otro de X4) — y sus cuentas auth.
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
    where app_user_id in (select id from app_user where email in ('{A_EMAIL}', '{B_EMAIL}', '{C_EMAIL}'))
       or home_id in (select id from home
                      where created_by in (select id from app_user where email in ('{A_EMAIL}', '{B_EMAIL}', '{C_EMAIL}')));
delete from person
    where name like 'XT-%'
       or home_id in (select id from home
                      where created_by in (select id from app_user where email in ('{A_EMAIL}', '{B_EMAIL}', '{C_EMAIL}')));
delete from home_member
    where home_id in (select id from home
                      where created_by in (select id from app_user where email in ('{A_EMAIL}', '{B_EMAIL}', '{C_EMAIL}')));
delete from audit_log
    where home_id in (select id from home
                      where created_by in (select id from app_user where email in ('{A_EMAIL}', '{B_EMAIL}', '{C_EMAIL}')));
delete from home
    where created_by in (select id from app_user where email in ('{A_EMAIL}', '{B_EMAIL}', '{C_EMAIL}'));
delete from auth.users
    where id in (select auth_uid from app_user where email in ('{A_EMAIL}', '{B_EMAIL}', '{C_EMAIL}'));
commit;
""")
    for table, column in (("event", "title"), ("routine", "title"), ("task", "title"),
                          ("task_list", "name"), ("calendar", "name"), ("person", "name")):
        status, text = request(URL, "GET", f"/rest/v1/{table}?{column}=like.XT-*&select=id", None, None, apikey=SVC)
        if status != 200 or parse(text):
            sys.exit(f"clean_xt: quedan filas XT-% en {table}: {text[:200]}")
    left = psql(f"select count(*) from home_membership hm join app_user u on u.id = hm.app_user_id "
                f"where u.email in ('{A_EMAIL}', '{B_EMAIL}', '{C_EMAIL}')")
    if left != "0":
        sys.exit(f"clean_xt: quedan membresías de xt ({left})")
    left = psql(f"select count(*) from home h join app_user u on u.id = h.created_by "
                f"where u.email in ('{A_EMAIL}', '{B_EMAIL}', '{C_EMAIL}')")
    if left != "0":
        sys.exit(f"clean_xt: quedan hogares de xt ({left})")


# Selector de bloques (A-16, T17): XT_ONLY = ids de bloque separados por comas (F1..F12, X1..X5,
# TDL_A12 y BASE = fases legacy); vacío = todo. A12_ITERS controla las iteraciones del bloque
# TDL_A12 (por defecto 20; el builder usa 3). Sin variables, comportamiento idéntico al previo.
XT_ONLY = {x.strip().upper() for x in os.environ.get("XT_ONLY", "").split(",") if x.strip()}
A12_ITERS = int(os.environ.get("A12_ITERS", "20"))
# F1_ITERS: carreras de solape real por bloque F1/F2 (R1-06; el solape expone el 40P01 de 0020)
F1_ITERS = int(os.environ.get("F1_ITERS", "10"))
results = []
counts = {}
XT_BLOCK = "BASE"  # bloque actual para el selector (cada bloque nuevo lo fija al entrar)


def xt_on(block):
    return not XT_ONLY or block.upper() in XT_ONLY


def check(name, ok, detail=""):
    if not xt_on(XT_BLOCK):
        return
    counts[XT_BLOCK] = counts.get(XT_BLOCK, 0) + 1
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

# ── Fase 2b (1.4, plan §7.2 X1–X15): rutas /home/* y contexto X-Home-Id ──
# A crea un hogar propio extra (XT-Otro, POST /home/create) que B no debe ver: para B es
# indistinguible de un id inexistente (sin oráculo). X8/X9/X10 prueban la cabecera X-Home-Id
# (S10: la cabecera llega a SQL; el detalle filtra por el hogar activo). X12–X14 van por RPC
# directa PostgREST. No se prueba escritura con cabecera ≠ hogar del recurso (diferido a 1.8,
# D-2): gap documentado.
otro = edge("POST", "/home/create", {"name": "XT-Otro"}, a_tok)
otro_body = parse(otro[1])
otro_id = otro_body.get("id") if otro[0] == 201 and isinstance(otro_body, dict) else None
if otro_id is None:
    sys.exit(f"setup X: A no pudo crear XT-Otro → {otro!r}")

b = edge("GET", "/home", None, b_tok)
homes = parse(b[1]) if b[0] == 200 else None
check("X1 B GET /home → home(A) role=member, home(B) y sin XT-Otro",
      isinstance(homes, list)
      and any(h.get("home_id") == home_a and h.get("role") == "member" for h in homes)
      and any(h.get("home_id") == home_b for h in homes)
      and all(h.get("home_id") != otro_id for h in homes), repr(b)[:200])
check("X2 B GET /home/detail?id=homeA → 200 (home.view)",
      edge("GET", f"/home/detail?id={home_a}", None, b_tok)[0] == 200)
expect("X3 B PATCH /home/update homeA → 403 (sin home.settings.manage)",
       edge("PATCH", "/home/update", {"id": home_a, "name": "XT hack"}, b_tok), NOT_ALLOWED)
expect("X4 B GET /home/detail?id=XT-Otro → 404 (no miembro, sin oráculo)",
       edge("GET", f"/home/detail?id={otro_id}", None, b_tok), HOME_NOT_FOUND)
expect("X5 B PATCH /home/default {home_id:XT-Otro} → 404",
       edge("PATCH", "/home/default", {"home_id": otro_id}, b_tok), HOME_NOT_FOUND)
expect("X6 B GET /home/membership?id=XT-Otro → 404",
       edge("GET", f"/home/membership?id={otro_id}", None, b_tok), HOME_NOT_FOUND)
check("X7 B GET /home/membership?id=homeA → 200",
      edge("GET", f"/home/membership?id={home_a}", None, b_tok)[0] == 200)
check("X8 B GET /calendar/detail?id=calA con X-Home-Id: homeA → 200 (ACL viewer, S10)",
      edge("GET", f"/calendar/detail?id={cal}", None, b_tok, home=home_a)[0] == 200)
expect("X9 B GET /calendar/detail?id=calA con X-Home-Id: homeB → 500 (filtro de detalle)",
       edge("GET", f"/calendar/detail?id={cal}", None, b_tok, home=home_b), NOT_FOUND)
expect("X10 B GET /calendar con X-Home-Id: XT-Otro → 500 (no miembro, legacy)",
       edge("GET", "/calendar", None, b_tok, home=otro_id), NOT_FOUND)
x11 = rpc_direct("get_homes", {}, b_tok)
x11_homes = parse(x11[1]) if x11[0] == 200 else None
check("X11 B rpc get_homes → 200; sin XT-Otro",
      isinstance(x11_homes, list) and all(h.get("home_id") != otro_id for h in x11_homes)
      and any(h.get("home_id") == home_a for h in x11_homes), repr(x11)[:200])
expect_err("X12 B rpc set_default_home(XT-Otro) → Not Found",
           rpc_direct("set_default_home", {"p_home_id": otro_id}, b_tok), "Not Found")
expect_err("X13 B rpc get_home_memberships(XT-Otro) → Not Found",
           rpc_direct("get_home_memberships", {"p_home_id": otro_id}, b_tok), "Not Found")
expect_err("X14 B rpc update_home(homeA, …) → Not Allowed (sin home.settings.manage)",
           rpc_direct("update_home", {"p_home_id": home_a, "p_name": "XT", "p_timezone": None}, b_tok),
           "Not Allowed")
x15a = edge("PATCH", "/home/default", {"home_id": home_a}, b_tok)
x15b = edge("PATCH", "/home/default", {"home_id": home_b}, b_tok)
check("X15 B PATCH /home/default homeA y restaurar homeB → 200 + 200",
      x15a[0] == 200 and x15b[0] == 200, repr((x15a, x15b))[:200])

# ── Fase 2c (1.5, plan §8.2): /home/member/* — K8, K11, K12 ──
# A da de alta XT-Miembro (child, sin cuenta) en home(A) con su person 1:1. K8: PATCH con cabecera
# X-Home-Id de otro hogar → 404 (header ≠ hogar del miembro, §6.1). K11: la baja soft conserva el
# histórico — PATCH /event/update con la MISMA lista → 200 (personIdsOf con p_include_inactive) —
# y K12: no admite asignaciones nuevas (event/create → 400 Invalid person, trigger 0015 iv).
xres = edge("POST", "/home/member/create",
            {"home_id": home_a, "kind": "child", "name": "XT-Miembro", "color": "#A1B2C3"}, a_tok)
xmem = parse(xres[1]).get("id") if xres[0] == 201 else None
if xmem is None:
    sys.exit(f"setup K: A no pudo crear XT-Miembro → {xres!r}")
xper = int(psql(f"select id from person where home_member_id = {xmem}"))
check("K1 setup: create {child, XT-Miembro} → 201 HOME_MEMBER",
      xres[0] == 201 and parse(xres[1]).get("linked") is False, repr(xres)[:200])
expect("K8 B PATCH /home/member/update con X-Home-Id: homeB → 404 (cabecera ≠ hogar del miembro)",
       edge("PATCH", "/home/member/update", {"id": xmem, "name": "XT hack"}, b_tok, home=home_b),
       HOME_NOT_FOUND)
k11 = edge("POST", f"/event/create?timezone={TZ}",
           {"calendar_id": cal, "title": "XT-Evento-K11", "date_at": "2026-12-21 12:00:00",
            "person_ids": [xper]}, a_tok)
k11_id = parse(k11[1]).get("id") if k11[0] == 200 else None
check("K11 setup: event/create con XT-Miembro asignada → 200", k11[0] == 200, repr(k11)[:200])
k11d = edge("PATCH", "/home/member/update", {"id": xmem, "status": "inactive"}, a_tok)
check("K11 PATCH /home/member/update status inactive → 200 (baja soft)",
      k11d[0] == 200 and parse(k11d[1]).get("status") == "inactive", repr(k11d)[:200])
k11u = edge("PATCH", f"/event/update?timezone={TZ}",
            {"id": k11_id, "title": "XT-Evento-K11", "date_at": "2026-12-21 12:00:00",
             "person_ids": [xper]}, a_tok)
check("K11 update_event con la MISMA lista (inactiva ya asignada) → 200 y el histórico intacto",
      k11u[0] == 200 and any(p.get("id") == xper for p in parse(k11u[1]).get("persons") or []),
      repr(k11u)[:200])
expect("K12 POST /event/create con la persona inactiva → 400 Invalid person",
       edge("POST", f"/event/create?timezone={TZ}",
            {"calendar_id": cal, "title": "XT-Evento-K12", "date_at": "2026-12-22 12:00:00",
             "person_ids": [xper]}, a_tok), (400, '{"error":"Invalid person"}'))

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

# ── K20 (1.5, plan §8.2): usuario C con el snapshot por defecto de `adult` ──
# member_kind_default(kind='adult'): 18 códigos SIN home.view (NO LEGACY17, que sí lo incluye).
# C es miembro de home(A) pero sin home.view → GET /home/member 403 (R6, documentado).
c = edge("POST", "/user/create", {"name": C_NAME, "email": C_EMAIL, "password": C_PASSWORD})
c_auth = edge("POST", "/user/auth", {"email": C_EMAIL, "password": C_PASSWORD})
if c_auth[0] != 200:
    sys.exit(f"no se pudo autenticar xt-c (¿ALLOW_REGISTRATION=true en la Edge para el alta?) {c!r}")
c_tok = parse(c_auth[1])["token"]
c_id = parse(c_auth[1])["id"]

# ── 1.6 (plan §6.4): C, aún NO miembro de home(A) → 404 en las 3 rutas /home/membership/* ──
# (antes de unirse en K20). Sin cambios en A: membresías y roles idénticos antes/después.
a_membership = int(psql(f"select id from home_membership where home_id = {home_a} and app_user_id = {a_id}"))
roles_pre = psql(f"select string_agg(id || ':' || role::text, ',' order by id) "
                 f"from home_membership where home_id = {home_a}")
for name, method, path, body in [
    ("M1 C (no miembro) PATCH /home/membership/role sobre home(A) → 404", "PATCH",
     "/home/membership/role", {"home_id": home_a, "membership_id": a_membership, "role": "member"}),
    ("M2 C (no miembro) POST /home/membership/transfer sobre home(A) → 404", "POST",
     "/home/membership/transfer", {"home_id": home_a, "to_membership_id": a_membership}),
    ("M3 C (no miembro) DELETE /home/membership sobre home(A) → 404", "DELETE",
     "/home/membership", {"home_id": home_a, "membership_id": a_membership}),
]:
    expect(name, edge(method, path, body, c_tok), HOME_NOT_FOUND)
roles_post = psql(f"select string_agg(id || ':' || role::text, ',' order by id) "
                  f"from home_membership where home_id = {home_a}")
check("M4 los 404 de C no cambian home(A) (membresías y roles intactos)",
      roles_pre == roles_post, f"{roles_pre!r} ≠ {roles_post!r}")

# ── 1.7 (plan §6.3): C no miembro → GET /home/membership de A → 404 (sin cambio) ──
# fn_require_member (0012) → 'Not Found' P0002 antes de fn_require_permission: un no miembro no
# ve las membresías del hogar (mismo criterio de las 3 rutas de arriba).
expect("M4b C (no miembro) GET /home/membership?id=homeA → 404",
       edge("GET", f"/home/membership?id={home_a}", None, c_tok), HOME_NOT_FOUND)

psql(f"""
begin;
insert into home_membership (home_id, app_user_id, role) values ({home_a}, {c_id}, 'member');
insert into membership_permission (home_membership_id, permission_code)
select hm.id, mkd.permission_code from home_membership hm
join member_kind_default mkd on mkd.kind = 'adult'
where hm.home_id = {home_a} and hm.app_user_id = {c_id};
commit;
""")
n_adult = psql(f"select count(*) from membership_permission mp "
               f"join home_membership hm on hm.id = mp.home_membership_id "
               f"where hm.home_id = {home_a} and hm.app_user_id = {c_id}")
check("K20 setup: snapshot de adult = 18 códigos (member_kind_default, sin home.view)",
      n_adult == "18", f"n={n_adult}")
expect("K20 C GET /home/member?home_id=homeA → 403 Not Allowed (adult sin home.view)",
       edge("GET", f"/home/member?home_id={home_a}", None, c_tok), NOT_ALLOWED)
expect("K20b C POST /home/member/create → 403 (adult sin home.members.manage)",
       edge("POST", "/home/member/create", {"home_id": home_a, "kind": "adult", "name": "XT-C-Crea"},
            c_tok), NOT_ALLOWED)

# ── 1.6 (plan §6.4): /home/membership/* — B (member de home(A)) y cabecera ajena ──
# B → 403 en role/transfer (expulsión ajena la cubre contract_check); X-Home-Id de home(B) en las
# 3 rutas → 404 (cabecera ≠ home_id del body); B sale de home(A) (200) y pierde el acceso al
# calendario compartido (GET /calendar/detail → 500 Not Found: las ACL se borran en cascada).
b_membership = int(psql(f"select id from home_membership where home_id = {home_a} and app_user_id = {b_id}"))
expect("M5 B PATCH /home/membership/role sobre home(A) → 403 (no admin)",
       edge("PATCH", "/home/membership/role",
            {"home_id": home_a, "membership_id": b_membership, "role": "member"}, b_tok), NOT_ALLOWED)
expect("M6 B POST /home/membership/transfer sobre home(A) → 403 (no admin)",
       edge("POST", "/home/membership/transfer",
            {"home_id": home_a, "to_membership_id": b_membership}, b_tok), NOT_ALLOWED)
for name, method, path, body in [
    ("M7 B role sobre home(A) con X-Home-Id: homeB → 404", "PATCH", "/home/membership/role",
     {"home_id": home_a, "membership_id": b_membership, "role": "member"}),
    ("M8 B transfer sobre home(A) con X-Home-Id: homeB → 404", "POST", "/home/membership/transfer",
     {"home_id": home_a, "to_membership_id": b_membership}),
    ("M9 B DELETE sobre home(A) con X-Home-Id: homeB → 404", "DELETE", "/home/membership",
     {"home_id": home_a, "membership_id": b_membership}),
]:
    expect(name, edge(method, path, body, b_tok, home=home_b), HOME_NOT_FOUND)

# ── 1.7 (plan §6.3): seed por kind de la membresía de B en home(B) — sin efecto en home(A) ──
# R1-02: el helper de 0019 rechaza admins; B es admin de su hogar personal → dance
# demote/restore vía psql (session_replication_role = replica: el trigger anti-admin diferido de
# 0015 rechazaría dejar home(B) sin admin) + caso extra de rechazo 'Not Allowed' sobre admin.
# El seed no debe alterar la membresía de B en home(A) ni sus ACL, y los permisos sembrados en
# home(B) no deben aparecer en GET /home/membership de A.
b_home_m = int(psql(f"select id from home_membership where home_id = {home_b} and app_user_id = {b_id}"))
sig_pre = psql(f"""
select (select coalesce(string_agg(hm.id || ':' || hm.role::text, ',' order by hm.id), '')
          from home_membership hm where hm.home_id = {home_a} and hm.app_user_id = {b_id})
    || '|' || (select coalesce(string_agg(mp.permission_code, ',' order by mp.permission_code), '')
          from membership_permission mp
          join home_membership hm on hm.id = mp.home_membership_id
         where hm.home_id = {home_a} and hm.app_user_id = {b_id})""")
acl_pre = psql(f"""
select md5(coalesce((select string_agg(cu.calendar_id || ':' || cu.user_id || ':' || cu.role::text,
                                      ',' order by cu.calendar_id, cu.user_id)
                       from calendar_user cu where cu.user_id = {b_id}), ''))
    || ' ' || md5(coalesce((select string_agg(tu.task_list_id || ':' || tu.user_id || ':' || tu.role::text,
                                             ',' order by tu.task_list_id, tu.user_id)
                              from task_list_user tu where tu.user_id = {b_id}), ''))""")
out = psql(f"""
do $$ begin
    perform fn_seed_kind_permissions({b_home_m}, 'guest');
    raise exception 'el helper no rechazo a un admin';
exception
    when insufficient_privilege then
        if sqlerrm <> 'Not Allowed' then raise; end if;
end $$;
select 'rechazado';""")
check("PK1 el helper rechaza la membresía admin de B en home(B) → 'Not Allowed' (R1-02)",
      out == "rechazado", repr(out)[:200])
psql(f"set session_replication_role = replica; "
     f"update home_membership set role = 'member' where id = {b_home_m}; "
     f"set session_replication_role = default;")
psql(f"select fn_seed_kind_permissions({b_home_m}, 'guest')")
snap = psql(f"select count(*) || ' ' || coalesce(string_agg(mp.permission_code, ',' "
            f"order by mp.permission_code collate \"C\"), '') "
            f"from membership_permission mp where mp.home_membership_id = {b_home_m}")
check("PK2 seed guest sobre la membresía de B en home(B) = 3 claves de guest (collate \"C\")",
      snap == "3 calendar.view,task.complete,task.view", repr(snap)[:200])
psql(f"set session_replication_role = replica; "
     f"update home_membership set role = 'admin' where id = {b_home_m}; "
     f"set session_replication_role = default; "
     f"delete from membership_permission where home_membership_id = {b_home_m};")  # promote = A-6
sig_post = psql(f"""
select (select coalesce(string_agg(hm.id || ':' || hm.role::text, ',' order by hm.id), '')
          from home_membership hm where hm.home_id = {home_a} and hm.app_user_id = {b_id})
    || '|' || (select coalesce(string_agg(mp.permission_code, ',' order by mp.permission_code), '')
          from membership_permission mp
          join home_membership hm on hm.id = mp.home_membership_id
         where hm.home_id = {home_a} and hm.app_user_id = {b_id})""")
acl_post = psql(f"""
select md5(coalesce((select string_agg(cu.calendar_id || ':' || cu.user_id || ':' || cu.role::text,
                                      ',' order by cu.calendar_id, cu.user_id)
                       from calendar_user cu where cu.user_id = {b_id}), ''))
    || ' ' || md5(coalesce((select string_agg(tu.task_list_id || ':' || tu.user_id || ':' || tu.role::text,
                                             ',' order by tu.task_list_id, tu.user_id)
                              from task_list_user tu where tu.user_id = {b_id}), ''))""")
check("PK3 el seed de home(B) no altera la membresía de B en home(A) (id:rol + snapshot)",
      sig_post == sig_pre, f"{sig_pre!r} ≠ {sig_post!r}")
check("PK4 el seed de home(B) no altera las ACL de B (calendar_user/task_list_user)",
      acl_post == acl_pre, f"{acl_pre!r} ≠ {acl_post!r}")
bA = edge("GET", f"/home/membership?id={home_a}", None, a_tok)
perms_b = next((m.get("permissions") for m in parse(bA[1])
                if isinstance(m, dict) and m.get("app_user_id") == b_id), None) if bA[0] == 200 else None
check("PK5 los permisos de B en home(B) no aparecen en GET /home/membership de A (sigue legacy17)",
      perms_b == LEGACY17_C, repr(bA)[:300])

# ── 1.8 (plan §6.4): aislamiento con la matriz §3.4.1 (guardia de 0020) ──
# (1) admin de B (de home(B)) sobre XT-Otro (H donde B NO es miembro) → 500 Not Found en lectura y
# escritura; (2) co-miembro C de home(A) sin ACL → 500 en la lectura admin-only de cal y en
# escritura; (3) admin A de home(A) con ACL → 200 en lectura de todos los calendarios de H
# (incluido el de C, sin ACL propia); (4) cabecera X-Home-Id de home(B) en ruta legacy de H → 500.
o_cal = parse(edge("POST", "/calendar/create", {"name": "XT-CalOtro", "color": "#101010"},
                   a_tok, home=otro_id)[1])["id"]
o_lst = parse(edge("POST", "/task-list/create", {"name": "XT-ListaOtro", "color": "#202020",
                                                 "sort": "title"}, a_tok, home=otro_id)[1])["id"]
o_tsk = parse(edge("POST", "/task/create", {"task_list_id": o_lst, "title": "XT-TareaOtro"},
                   a_tok, home=otro_id)[1])["id"]
o_ev = parse(edge("POST", f"/event/create?timezone={TZ}",
                  {"calendar_id": o_cal, "title": "XT-EvOtro", "date_at": "2026-12-30 12:00:00"},
                  a_tok, home=otro_id)[1])["id"]
check("S64-0 setup: A crea calendario/lista/tarea/evento en XT-Otro → 201 ×4",
      all(isinstance(x, int) for x in (o_cal, o_lst, o_tsk, o_ev)), repr((o_cal, o_lst, o_tsk, o_ev))[:100])
for name, res in [
    ("S64-1a admin de B GET /calendar/detail de XT-Otro → 500",
     edge("GET", f"/calendar/detail?id={o_cal}", None, b_tok)),
    ("S64-1b admin de B GET /event/detail de XT-Otro → 500",
     edge("GET", f"/event/detail?id={o_ev}&timezone={TZ}", None, b_tok)),
    ("S64-1c admin de B GET /task-list/detail de XT-Otro → 500",
     edge("GET", f"/task-list/detail?id={o_lst}", None, b_tok)),
    ("S64-1d admin de B PATCH /calendar/update de XT-Otro → 500",
     edge("PATCH", "/calendar/update", {"id": o_cal, "name": "XT-CalOtro X", "color": "#101010"}, b_tok)),
    ("S64-1e admin de B POST /event/create en XT-Otro → 500",
     edge("POST", f"/event/create?timezone={TZ}",
          {"calendar_id": o_cal, "title": "XT-EvHack", "date_at": "2026-12-31 12:00:00"}, b_tok)),
    ("S64-1f admin de B DELETE /task/delete de XT-Otro → 500",
     edge("DELETE", "/task/delete", {"id": o_tsk}, b_tok)),
    ("S64-2a co-miembro C sin ACL GET /calendar/detail de cal → 500 (lectura admin-only)",
     edge("GET", f"/calendar/detail?id={cal}", None, c_tok)),
    ("S64-2b co-miembro C sin ACL PATCH /calendar/update de cal → 500",
     edge("PATCH", "/calendar/update", {"id": cal, "name": "XT-Cal X", "color": "#123456"},
          c_tok, home=home_a)),
]:
    expect(name, res, NOT_FOUND)
c_cal = parse(edge("POST", "/calendar/create", {"name": "XT-CalC", "color": "#303030"},
                   c_tok, home=home_a)[1])["id"]
s64_3a = edge("GET", "/calendar", None, a_tok, home=home_a)
check("S64-3a admin A GET /calendar incluye el calendario de C (sin ACL propia)",
      s64_3a[0] == 200 and any(isinstance(x, dict) and x.get("id") == c_cal
                               for x in parse(s64_3a[1])), repr(s64_3a)[:200])
check("S64-3b admin A GET /calendar/detail del calendario de C (sin ACL) → 200",
      edge("GET", f"/calendar/detail?id={c_cal}", None, a_tok, home=home_a)[0] == 200)
expect("S64-4 B PATCH /calendar/update de cal con X-Home-Id: home(B) → 500 (cabecera ajena)",
       edge("PATCH", "/calendar/update", {"id": cal, "name": "XT-Cal X", "color": "#123456"},
            b_tok, home=home_b), NOT_FOUND)

m10 = edge("DELETE", "/home/membership",
           {"home_id": home_a, "membership_id": b_membership}, b_tok)
check("M10 B DELETE /home/membership (sale de home(A), cualquiera puede salir) → 200 success",
      m10[0] == 200 and parse(m10[1]) == {"success": True}, repr(m10)[:200])
expect("M11 B GET /calendar/detail del compartido tras salir → 500 Not Found (ACL borradas)",
       edge("GET", f"/calendar/detail?id={cal}", None, b_tok), NOT_FOUND)

# ── 1.8 (plan §6.3): concurrencia — T-C1, T-C1b, T-C2 ×3 y T-DL ──
# Hogar scratch XT-Conc (998001) con admins A y B y member C; XT-C1 (998001) con owners A y B
# (sin owner único), XT-C2 (998002) owner B y XT-L1 (998001) owners A y B. Los tres usuarios
# conservan su hogar personal (sin 403 de último hogar). T-C1: S1 = set_home_membership_role que
# degrada a A (sin commit) ∥ S2 = update_calendar de A → debe bloquear en home
# (pg_stat_activity.wait_event_type = 'Lock'); commit → S2 'Not Allowed' (A member con legacy17,
# sin calendar.manage); variante solo widget → ok. T-C1b: S1 = remove_home_membership de A ∥
# S2 = set_event_alarm de A → bloquea → commit → 'Not Found' y 0 filas nuevas en event_user. T-C2
# HTTP ×3: PATCH solo widget ∥ DELETE /home/membership del propio U → 200 y 200, o 500 Not Found
# del PATCH tras la baja; nunca error distinto; calendar_user de U = 0 tras la baja. T-DL: 10 pares
# W×D, 20 iteraciones por par, orden invertido (iter par: W primero; impar: D primero), 2 sesiones
# psql con pg_sleep(0.3) intra-transacción para solapar; 0×40P01 (R1-01: el orden global
# hogar→membresía→ACL→contenido no cicla con 0018).

a_uid = psql(f"select auth_uid from app_user where id = {a_id}")
b_uid = psql(f"select auth_uid from app_user where id = {b_id}")
c_uid = psql(f"select auth_uid from app_user where id = {c_id}")
HC = 998001  # XT-Conc


def psql_async(sql):
    cmd = shlex.split(os.environ.get("PSQL", "psql"))
    p = subprocess.Popen(cmd + ["-X", "-q", "-v", "ON_ERROR_STOP=1", "-t", "-A"],
                         stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                         stderr=subprocess.STDOUT, text=True)
    p.stdin.write(sql)
    p.stdin.close()
    return p


def wait_locked(like, timeout=15):
    """True si alguna sesión está bloqueada en un lock con `like` en su query (pg_stat_activity)."""
    for _ in range(int(timeout * 10)):
        n = psql("select count(*) from pg_stat_activity "
                 f"where wait_event_type = 'Lock' and query ilike '%{like}%' "
                 "and query not ilike '%pg_stat_activity%'")
        if n != "0":
            return True
        time.sleep(0.1)
    return False


psql(f"""
set session_replication_role = replica;
begin;
delete from event_user where user_id in ({a_id}, {b_id}, {c_id}) and event_id between 998001 and 998002;
delete from event_person where event_id between 998001 and 998002;
delete from event where id between 998001 and 998002 or title like 'XT-Ev%' or title = 'XT-EvW';
delete from task where id = 998001 or title = 'XT-TareaW';
delete from task_list_user where task_list_id between 998001 and 998002;
delete from task_list where id between 998001 and 998002 or name like 'XT-LD%';
delete from calendar_user where calendar_id between 998001 and 998002;
delete from calendar where id between 998001 and 998002 or name like 'XT-CD%';
delete from membership_permission where home_membership_id between 998001 and 998003;
delete from home_membership where id between 998001 and 998003;
delete from home where id = {HC};
commit;
set session_replication_role = default;
""")
psql(f"""
begin;
insert into home (id, name, status, is_personal, created_by) values ({HC}, 'XT-Conc', 'active', false, {a_id});
insert into home_membership (id, home_id, app_user_id, role) values
    (998001, {HC}, {a_id}, 'admin'), (998002, {HC}, {b_id}, 'admin'), (998003, {HC}, {c_id}, 'member');
insert into calendar (id, name, color, token, home_id) values
    (998001, 'XT-C1', '#111111', 'xt-conc-1', {HC}), (998002, 'XT-C2', '#222222', 'xt-conc-2', {HC});
insert into calendar_user (calendar_id, user_id, role, widget, dashboard, home_id) values
    (998001, {a_id}, 'owner', true, true, {HC}), (998001, {b_id}, 'owner', true, true, {HC}),
    (998002, {b_id}, 'owner', true, true, {HC}), (998002, {a_id}, 'viewer', true, true, {HC});
insert into task_list (id, name, color, token, sort, home_id) values
    (998001, 'XT-L1', '#333333', 'xt-conc-3', 'title', {HC});
insert into task_list_user (task_list_id, user_id, role, widget, dashboard, home_id) values
    (998001, {a_id}, 'owner', true, true, {HC}), (998001, {b_id}, 'owner', true, true, {HC});
insert into event (id, calendar_id, title, date_at) values
    (998001, 998001, 'XT-EvW', '2026-12-25 12:00:00'), (998002, 998002, 'XT-EvC2', '2026-12-26 12:00:00');
commit;
select fn_seed_kind_permissions(998003, 'adult');
""")

# T-C1: degradación (set_home_membership_role) ∥ update_calendar de A
s1 = psql_async(f"begin;\nselect set_config('request.jwt.claim.sub', '{b_uid}', true);\n"
                f"select set_home_membership_role({HC}, 998001, 'member');\n"
                "select pg_sleep(6);\ncommit;\n")
time.sleep(1.5)
s2 = psql_async(f"begin;\nselect set_config('request.jwt.claim.sub', '{a_uid}', true);\n"
                f"select update_calendar(998001, 'XT-C1 X', '#111111', true, true);\ncommit;\n")
check("T-C1 S2 update_calendar de A bloquea en home (pg_stat_activity.wait_event_type='Lock')",
      wait_locked("update_calendar(998001"))
out1, _ = s1.communicate(timeout=60)
out2, _ = s2.communicate(timeout=60)
check("T-C1 S1 (degradación de A) commitea sin error", s1.returncode == 0, out1[:200])
check("T-C1 S2 tras el commit → Not Allowed (A member con legacy17 sin calendar.manage)",
      "Not Allowed" in out2 and "ERROR" in out2, out2[:200])
t_c1v = psql(f"begin;\nselect set_config('request.jwt.claim.sub', '{a_uid}', true);\n"
             f"select update_calendar(998001, 'XT-C1', '#111111', false, true);\ncommit;")
check("T-C1 variante: update_calendar solo widget de A (member) → ok (ACL propia)",
      '"id"' in t_c1v, t_c1v[:200])

# T-C1b: remove_home_membership de A ∥ set_event_alarm de A (ruta sin p_code)
psql(f"insert into calendar_user (calendar_id, user_id, role, widget, dashboard, home_id) "
     f"values (998001, {a_id}, 'owner', true, true, {HC}) on conflict do nothing")
n_eu_pre = psql(f"select count(*) from event_user where user_id = {a_id}")
s1 = psql_async(f"begin;\nselect set_config('request.jwt.claim.sub', '{b_uid}', true);\n"
                f"select remove_home_membership({HC}, 998001);\nselect pg_sleep(6);\ncommit;\n")
time.sleep(1.5)
s2 = psql_async(f"begin;\nselect set_config('request.jwt.claim.sub', '{a_uid}', true);\n"
                f"select set_event_alarm(998002, 5, '{TZ}');\ncommit;\n")
check("T-C1b S2 set_event_alarm de A bloquea en home (pg_stat_activity.wait_event_type='Lock')",
      wait_locked("set_event_alarm(998002"))
out1, _ = s1.communicate(timeout=60)
out2, _ = s2.communicate(timeout=60)
check("T-C1b S1 (baja de A) commitea sin error", s1.returncode == 0, out1[:200])
check("T-C1b S2 tras el commit → Not Found (ACL borrada en cascada; R1-02)",
      "Not Found" in out2 and "ERROR" in out2, out2[:200])
n_eu_post = psql(f"select count(*) from event_user where user_id = {a_id}")
check("T-C1b set_event_alarm no escribió filas event_user de A (R1-02)",
      n_eu_post == n_eu_pre, f"{n_eu_pre} → {n_eu_post}")

# T-C2 HTTP ×3: PATCH solo widget ∥ DELETE /home/membership del propio U (= C, viewer de XT-C2)
for rep in range(3):
    psql(f"insert into home_membership (id, home_id, app_user_id, role) "
         f"values (998003, {HC}, {c_id}, 'member') on conflict (id) do update set role = 'member'; "
         f"insert into calendar_user (calendar_id, user_id, role, widget, dashboard, home_id) "
         f"values (998002, {c_id}, 'viewer', true, true, {HC}) on conflict do nothing")
    res = {}
    tp = threading.Thread(target=lambda: res.update(
        patch=edge("PATCH", "/calendar/update", {"id": 998002, "name": "XT-C2", "color": "#222222",
                                                 "widget": False}, c_tok, home=HC)))
    td = threading.Thread(target=lambda: res.update(
        dele=edge("DELETE", "/home/membership", {"home_id": HC, "membership_id": 998003}, c_tok)))
    tp.start(); td.start(); tp.join(30); td.join(30)
    pr, dr = res.get("patch"), res.get("dele")
    check(f"T-C2 #{rep + 1} DELETE /home/membership de U → 200 success",
          dr is not None and dr[0] == 200 and parse(dr[1]) == {"success": True}, repr(dr)[:200])
    check(f"T-C2 #{rep + 1} PATCH solo widget → 200 antes de la baja o 500 Not Found tras ella",
          pr is not None and (pr[0] == 200 or pr == NOT_FOUND), repr(pr)[:200])
    left = psql(f"select count(*) from calendar_user where calendar_id = 998002 and user_id = {c_id}")
    check(f"T-C2 #{rep + 1} calendar_user de U en XT-C2 = 0 tras la baja", left == "0", f"filas={left}")

# T-C2 deja a C fuera de XT-Conc: se re-alta (member) para que W1/W2 de T-DL cumplan Q3
psql(f"insert into home_membership (id, home_id, app_user_id, role) "
     f"values (998003, {HC}, {c_id}, 'member') on conflict (id) do update set role = 'member'")

# T-DL: 10 pares W×D, 20 iteraciones por par, orden invertido; 0×40P01 (R1-01)
W_OPS = [
    ("add_calendar_user", f"select add_calendar_user(998001, '{C_EMAIL}')"),
    ("add_task_list_user", f"select add_task_list_user(998001, '{C_EMAIL}')"),
    ("create_task_list", "select create_task_list('XT-LD', '#444444', 'title', true, true)"),
    ("create_calendar", "select create_calendar('XT-CD', '#555555', true, true)"),
    ("update_event", f"select update_event(998001, 'XT-EvW', '2026-12-25 12:00:00', null, null, '{TZ}')"),
]
D_OPS = [
    ("remove_home_membership", f"select remove_home_membership({HC}, 998001)"),
    ("set_home_membership_role", f"select set_home_membership_role({HC}, 998001, 'admin')"),
]
tdl_deadlocks = 0
tdl_bad = 0
for wname, wsql in W_OPS:
    for dname, dsql in D_OPS:
        pair_bad = 0
        for i in range(20 if not XT_ONLY else 0):  # A-16: solo con XT_ONLY vacío (bloques sueltos rápidos)
            psql(f"""
begin;
delete from membership_permission where home_membership_id = 998001;
delete from home_membership where id = 998001;
delete from calendar_user where user_id = {c_id} and home_id = {HC};
delete from task_list_user where user_id = {c_id} and home_id = {HC};
insert into home_membership (id, home_id, app_user_id, role) values (998001, {HC}, {a_id}, 'admin');
insert into calendar_user (calendar_id, user_id, role, widget, dashboard, home_id)
    values (998001, {a_id}, 'owner', true, true, {HC}), (998001, {b_id}, 'owner', true, true, {HC})
    on conflict do nothing;
insert into task_list_user (task_list_id, user_id, role, widget, dashboard, home_id)
    values (998001, {a_id}, 'owner', true, true, {HC}), (998001, {b_id}, 'owner', true, true, {HC})
    on conflict do nothing;
commit;
""")
            sqlw = (f"begin;\nselect set_config('request.jwt.claim.sub', '{a_uid}', true);\n"
                    f"select pg_sleep(0.3);\n{wsql};\ncommit;\n")
            sqld = (f"begin;\nselect set_config('request.jwt.claim.sub', '{b_uid}', true);\n"
                    f"select pg_sleep(0.3);\n{dsql};\ncommit;\n")
            if i % 2 == 0:  # orden invertido: par → W primero; impar → D primero
                pw = psql_async(sqlw); time.sleep(0.1); pd = psql_async(sqld)
            else:
                pd = psql_async(sqld); time.sleep(0.1); pw = psql_async(sqlw)
            outw, _ = pw.communicate(timeout=120)
            outd, _ = pd.communicate(timeout=120)
            bad = ("deadlock" in (outw + outd).lower() or "40P01" in (outw + outd))
            if bad:
                tdl_deadlocks += 1
            for out in (outw, outd):
                if "ERROR" in out and not ("Not Found" in out or "Not Allowed" in out):
                    bad = True
            if bad:
                pair_bad += 1
                tdl_bad += 1
                print(f"  T-DL {wname} ∥ {dname} iter {i}: outW={outw[:120]!r} outD={outd[:120]!r}")
        check(f"T-DL {wname} ∥ {dname}: 20 iteraciones, 0×40P01, outcomes 200/Not Found(/Not Allowed)",
              pair_bad == 0, f"{pair_bad} iteraciones fuera de spec")
check("T-DL global: 200 iteraciones (10 pares × 20), 0 deadlocks 40P01",
      tdl_deadlocks == 0 and tdl_bad == 0, f"deadlocks={tdl_deadlocks} bad={tdl_bad}")

psql(f"""
set session_replication_role = replica;
begin;
delete from event_user where event_id in (998001, 998002);
delete from event_person where event_id in (998001, 998002);
delete from event where calendar_id between 998001 and 998002;
delete from task where task_list_id between 998001 and 998002;
delete from task_list_user where home_id = {HC};
delete from task_list where home_id = {HC};
delete from calendar_user where home_id = {HC};
delete from calendar where home_id = {HC};
delete from membership_permission where home_membership_id between 998001 and 998003;
delete from home_membership where home_id = {HC};
delete from home where id = {HC};
commit;
set session_replication_role = default;
""")

# ── 1.9 (plan §6.3/§6.4): A-12 funcional (F1–F6), permisos (F7–F12), cross-tenant (X1–X5) y
# T-DL-A12 (15 pares) — bloques seleccionables con XT_ONLY (A-16) ──
# Fixtures propias (ids fijos 9981xx; home 'XT-P19' created_by A): admins A y B, member M = C
# vinculado (home_member 998110) y pet sin vínculo (998111); calendario/lista 998120/998121 con
# owners A y B. Cada bloque resetea su fixture (p19_reset). T21: la limpieza final es p19_clean
# (session_replication_role = replica SOLO para borrado, como T-DL) y la query de residuos que
# anota clean_xt (0 filas XT-%, 0 membresías/hogares de xt) se verifica al final del script.

P19_MID_A, P19_MID_B, P19_MID_M = 998101, 998102, 998103
P19_HM_M, P19_HM_PET = 998110, 998111
P19_CAL, P19_LST = 998120, 998121
P19_Q = f"""
set session_replication_role = replica;
begin;
delete from membership_permission where home_membership_id between 998101 and 998103;
delete from home_membership where id between 998101 and 998103;
delete from calendar_user where calendar_id = 998120;
delete from task_list_user where task_list_id = 998121;
delete from calendar where id = 998120;
delete from task_list where id = 998121;
delete from home_member where id between 998110 and 998111;
delete from audit_log where home_id = 998100;
delete from home where id = 998100;
commit;
set session_replication_role = default;
"""


def out_json(out):
    for line in out.splitlines():
        line = line.strip()
        if line.startswith("{") and line.endswith("}"):
            try:
                return json.loads(line)
            except ValueError:
                pass
    return None


def outcome(out):
    """Clasifica la salida de psql de una RPC: ok | Not Found | Not Allowed | deadlock | otro."""
    if "40P01" in out or "deadlock" in out.lower():
        return "deadlock"
    if "ERROR" not in out:
        return "ok"
    for msg in ("Not Found", "Not Allowed"):
        if msg in out:
            return msg
    return "otro"


def p19_reset(kind_m="adult"):
    """Fixture del bloque 1.9 (kind_m = kind de M). Borra los ids fijos con replica (solo borrado)
    y los recrea en una transacción (el anti-admin de 0015 es diferido). El snapshot de M se siembra
    con fn_seed_kind_permissions del kind_m."""
    psql(P19_Q + f"""
begin;
insert into home (id, name, status, is_personal, created_by)
    values (998100, 'XT-P19', 'active', false, {a_id});
insert into home_membership (id, home_id, app_user_id, role) values
    (998101, 998100, {a_id}, 'admin'), (998102, 998100, {b_id}, 'admin'),
    (998103, 998100, {c_id}, 'member');
insert into home_member (id, home_id, kind, name, color, app_user_id) values
    (998110, 998100, '{kind_m}', 'XT-P19-M', '#123456', {c_id}),
    (998111, 998100, 'adult', 'XT-P19-Pet', '#654321', null);
insert into calendar (id, name, color, token, home_id)
    values (998120, 'XT-P19-C', '#111111', 'xt-p19-c', 998100);
insert into calendar_user (calendar_id, user_id, role, widget, dashboard, home_id) values
    (998120, {a_id}, 'owner', true, true, 998100), (998120, {b_id}, 'owner', true, true, 998100);
insert into task_list (id, name, color, token, sort, home_id)
    values (998121, 'XT-P19-L', '#222222', 'xt-p19-l', 'title', 998100);
insert into task_list_user (task_list_id, user_id, role, widget, dashboard, home_id) values
    (998121, {a_id}, 'owner', true, true, 998100), (998121, {b_id}, 'owner', true, true, 998100);
commit;
select fn_seed_kind_permissions(998103, '{kind_m}');
""")


def p19_race(sql1, sub1, sql2, sub2, wait_like=None, hold=6, stagger=1.5):
    """Patrón T-C1: S1 mantiene la transacción abierta con pg_sleep(hold) y S2 se lanza `stagger`
    después; con wait_like se comprueba que S2 queda bloqueado en pg_stat_activity.
    → (out1, out2, blocked|None)."""
    s1 = psql_async(f"begin;\nselect set_config('request.jwt.claim.sub', '{sub1}', true);\n"
                    f"{sql1};\nselect pg_sleep({hold});\ncommit;\n")
    time.sleep(stagger)
    s2 = psql_async(f"begin;\nselect set_config('request.jwt.claim.sub', '{sub2}', true);\n"
                    f"{sql2};\ncommit;\n")
    blocked = wait_locked(wait_like) if wait_like else None
    out1, _ = s1.communicate(timeout=120)
    out2, _ = s2.communicate(timeout=120)
    return out1, out2, blocked


def kind_change(where=""):
    return psql(f"select count(*) from audit_log where home_id = 998100 "
                f"and payload->>'source' = 'kind_change' {where}")


def m_perms():
    return psql("select coalesce(string_agg(permission_code, ',' order by permission_code), '') "
                "from membership_permission where home_membership_id = 998103")


def kind_defaults(kind):
    return psql("select coalesce(string_agg(permission_code, ',' order by permission_code), '') "
                f"from member_kind_default where kind = '{kind}'::member_kind")


def block_f1(sql_other, name):
    """F1/F2: O1 quita a O2 ∥ O2 quita a O1 en el mismo recurso (A-12) → exactamente 1 éxito +
    perdedor Not Found/Not Allowed, owners finales = 1 y 0×40P01 (R1-06). Carreras de solape real
    (estilo T-DL, F1_ITERS por bloque): ambas RPC se lanzan en sesiones psql que despiertan a la
    vez (pg_sleep hasta un instante común) y el orden de lanzamiento se alterna. El patrón T-C1
    serializado NO expone el bug de 0020 (FOR SHARE propio + DELETE cruzado = ciclo de mejora de
    lock entre dos removes → 40P01, plan §6.3 «remove ∥ remove»); contra 0021 el set-lock ACL en
    orden de id serializa y el invariante se cumple en todas las carreras (desviación documentada
    en build.md sobre plan §6.3 «patrón T-C1» para F1/F2)."""
    p19_reset()
    bad_out, bad_owners, deadlocks = [], [], []
    for i in range(F1_ITERS):
        if i:  # reseed ligero entre carreras: la anterior deja el recurso con 1 owner
            psql(f"begin;\ndelete from {sql_other[2]} where {sql_other[3]};\n"
                 f"{sql_other[4]};\ncommit;")
        until = (datetime.datetime.now(datetime.timezone.utc)
                 + datetime.timedelta(seconds=1)).strftime("%Y-%m-%d %H:%M:%S.%f+00")
        rendezvous = ("select pg_sleep(greatest(0::double precision, "
                      f"extract(epoch from (timestamptz '{until}' - now()))::double precision));")
        sa = (f"begin;\nselect set_config('request.jwt.claim.sub', '{a_uid}', true);\n"
              f"{rendezvous}\n{sql_other[0]};\ncommit;\n")
        sb = (f"begin;\nselect set_config('request.jwt.claim.sub', '{b_uid}', true);\n"
              f"{rendezvous}\n{sql_other[1]};\ncommit;\n")
        if i % 2 == 0:  # orden invertido (T-DL): par → S1 primero; impar → S2 primero
            p1 = psql_async(sa); time.sleep(0.1); p2 = psql_async(sb)
        else:
            p2 = psql_async(sb); time.sleep(0.1); p1 = psql_async(sa)
        out1, _ = p1.communicate(timeout=120)
        out2, _ = p2.communicate(timeout=120)
        outs = out1 + out2
        if "40P01" in outs or "deadlock" in outs.lower():
            deadlocks.append(i)
        o1, o2 = outcome(out1), outcome(out2)
        if not ((o1 == "ok" and o2 in ("Not Found", "Not Allowed"))
                or (o2 == "ok" and o1 in ("Not Found", "Not Allowed"))):
            bad_out.append(f"iter{i}:S1={o1} S2={o2}")
        owners = psql(f"select count(*) from {sql_other[2]} where {sql_other[3]} and role = 'owner'")
        if owners != "1":
            bad_owners.append(f"iter{i}={owners}")
    check(f"{name} carreras solapadas ({F1_ITERS}×): exactamente 1 éxito y perdedor "
          "Not Found/Not Allowed", not bad_out, "; ".join(bad_out)[:200])
    check(f"{name} owners finales del recurso = 1 tras cada carrera", not bad_owners,
          "; ".join(bad_owners)[:200])
    check(f"{name} 0×40P01 en las {F1_ITERS} carreras", not deadlocks,
          f"deadlocks en iters {deadlocks}")


def block_f3(sql_add, count_sql, name):
    """F3/F4: dos adds del mismo email (A-12) → 2 éxitos, 1 fila, sin 23505."""
    p19_reset()
    out1, out2, blocked = p19_race(sql_add, a_uid, sql_add, b_uid, sql_add.split("(")[0].split()[-1])
    check(f"{name} S2 (segundo add del mismo email) espera el índice único (pg_stat_activity)",
          blocked is True, f"S1={outcome(out1)} S2={outcome(out2)}")
    ok = outcome(out1) == "ok" and outcome(out2) == "ok" and "23505" not in out1 + out2
    check(f"{name} ambos adds → ok, sin 23505 (ON CONFLICT, A-12)", ok,
          f"S1={out1[:120]!r} S2={out2[:120]!r}")
    n = psql(count_sql)
    check(f"{name} 1 fila ACL de C tras los dos adds", n == "1", f"filas={n}")


def block_f5(sql_remove, count_sql, name):
    """F5/F6: remove_home_membership(O1) ∥ remove_*_user (O1 quita a O2) → owners ≥ 1 (A-5)."""
    p19_reset()
    out1, out2, blocked = p19_race("select remove_home_membership(998100, 998101)", b_uid,
                                   sql_remove, a_uid, sql_remove.split("(")[0].split()[-1])
    check(f"{name} S2 (O1 quita a O2) espera el lock de hogar de la baja", blocked is True,
          f"S1={outcome(out1)} S2={outcome(out2)}")
    ok = (outcome(out1) == "ok" and outcome(out2) in ("Not Found", "Not Allowed")
          and "40P01" not in out1 + out2)
    check(f"{name} baja de O1 → ok y S2 → Not Found/Not Allowed (ACL en cascada) sin 40P01", ok,
          f"S1={out1[:120]!r} S2={out2[:120]!r}")
    owners = psql(count_sql)
    check(f"{name} owners finales del recurso ≥ 1", int(owners) >= 1, f"owners={owners}")


XT_BLOCK = "F1"
if xt_on("F1"):
    block_f1((f"select remove_calendar_user({P19_CAL}, {b_id})",
              f"select remove_calendar_user({P19_CAL}, {a_id})",
              "calendar_user", f"calendar_id = {P19_CAL}",
              f"insert into calendar_user (calendar_id, user_id, role, widget, dashboard, home_id) "
              f"values ({P19_CAL}, {a_id}, 'owner', true, true, 998100), "
              f"({P19_CAL}, {b_id}, 'owner', true, true, 998100)"), "F1")
XT_BLOCK = "F2"
if xt_on("F2"):
    block_f1((f"select remove_task_list_user({P19_LST}, {b_id})",
              f"select remove_task_list_user({P19_LST}, {a_id})",
              "task_list_user", f"task_list_id = {P19_LST}",
              f"insert into task_list_user (task_list_id, user_id, role, widget, dashboard, "
              f"home_id) values ({P19_LST}, {a_id}, 'owner', true, true, 998100), "
              f"({P19_LST}, {b_id}, 'owner', true, true, 998100)"), "F2")
XT_BLOCK = "F3"
if xt_on("F3"):
    block_f3(f"select add_calendar_user({P19_CAL}, '{C_EMAIL}')",
             f"select count(*) from calendar_user where calendar_id = {P19_CAL} and user_id = {c_id}",
             "F3")
XT_BLOCK = "F4"
if xt_on("F4"):
    block_f3(f"select add_task_list_user({P19_LST}, '{C_EMAIL}')",
             f"select count(*) from task_list_user where task_list_id = {P19_LST} and user_id = {c_id}",
             "F4")
XT_BLOCK = "F5"
if xt_on("F5"):
    block_f5(f"select remove_calendar_user({P19_CAL}, {b_id})",
             f"select count(*) from calendar_user where calendar_id = {P19_CAL} and role = 'owner'",
             "F5")
XT_BLOCK = "F6"
if xt_on("F6"):
    block_f5(f"select remove_task_list_user({P19_LST}, {b_id})",
             f"select count(*) from task_list_user where task_list_id = {P19_LST} and role = 'owner'",
             "F6")

# F7: set_home_permissions ∥ promoción del target → 0 filas finales (A4)
XT_BLOCK = "F7"
if xt_on("F7"):
    p19_reset()
    out1, out2, blocked = p19_race(
        "select set_home_permissions(998100, 998103, '[\"home.view\"]'::jsonb)", a_uid,
        "select set_home_membership_role(998100, 998103, 'admin')", b_uid,
        "set_home_membership_role")
    check("F7 S2 (promoción del target) espera el lock de membresía del set", blocked is True,
          f"S1={outcome(out1)} S2={outcome(out2)}")
    ok = outcome(out1) == "ok" and outcome(out2) == "ok" and "40P01" not in out1 + out2
    check("F7 set y promoción → ambos ok sin 40P01", ok, f"S1={out1[:120]!r} S2={out2[:120]!r}")
    n = psql("select count(*) from membership_permission where home_membership_id = 998103")
    check("F7 target admin al final → 0 filas de snapshot (A4)", n == "0", f"filas={n}")

# F8: promoción primero → set posterior Not Allowed (A4)
XT_BLOCK = "F8"
if xt_on("F8"):
    p19_reset()
    out1 = psql_run(f"begin;\nselect set_config('request.jwt.claim.sub', '{b_uid}', true);\n"
                    "select set_home_membership_role(998100, 998103, 'admin');\ncommit;\n")[1]
    out2 = psql_run(f"begin;\nselect set_config('request.jwt.claim.sub', '{a_uid}', true);\n"
                    "select set_home_permissions(998100, 998103, '[\"home.view\"]'::jsonb);\n"
                    "commit;\n")[1]
    check("F8 promoción primero → ok y set posterior → Not Allowed",
          outcome(out1) == "ok" and outcome(out2) == "Not Allowed",
          f"promote={out1[:120]!r} set={out2[:120]!r}")
    n = psql("select count(*) from membership_permission where home_membership_id = 998103")
    check("F8 0 filas de snapshot tras la promoción y el set rechazado", n == "0", f"filas={n}")

# F9: dos set_home_permissions del mismo target → serializados, estado final = el segundo
XT_BLOCK = "F9"
if xt_on("F9"):
    p19_reset()
    out1, out2, blocked = p19_race(
        "select set_home_permissions(998100, 998103, '[\"home.view\"]'::jsonb)", a_uid,
        "select set_home_permissions(998100, 998103, '[\"calendar.view\"]'::jsonb)", b_uid,
        "set_home_permissions")
    check("F9 los dos sets del mismo target serializan (pg_stat_activity)", blocked is True,
          f"S1={outcome(out1)} S2={outcome(out2)}")
    check("F9 estado final = el segundo set ([calendar.view])", m_perms() == "calendar.view",
          f"perms={m_perms()}")
    rows = psql("select count(*) from audit_log where home_id = 998100 "
                "and payload->>'source' = 'set' and payload->>'permission_code' = 'home.view' "
                "and payload->>'after' = 'true'")
    rows2 = psql("select count(*) from audit_log where home_id = 998100 "
                 "and payload->>'source' = 'set' and payload->>'permission_code' = 'home.view' "
                 "and payload->>'after' = 'false'")
    rows3 = psql("select count(*) from audit_log where home_id = 998100 "
                 "and payload->>'source' = 'set' and payload->>'permission_code' = 'calendar.view' "
                 "and payload->>'after' = 'true'")
    check("F9 audit = deltas (grant y revoke de home.view, grant de calendar.view)",
          rows == "1" and rows2 == "1" and rows3 == "1", f"grant/revoke/grant={rows}/{rows2}/{rows3}")

# F10: update_home_member (kind) ∥ set_home_permissions → estado final coherente
XT_BLOCK = "F10"
if xt_on("F10"):
    p19_reset(kind_m="child")
    out1, out2, _ = p19_race(
        "select update_home_member(998110, 'adult', null, null, null)", a_uid,
        "select set_home_permissions(998100, 998103, '[\"home.view\"]'::jsonb)", a_uid)
    ok = outcome(out1) == "ok" and outcome(out2) == "ok" and "40P01" not in out1 + out2
    check("F10 update kind ∥ set_perms: ambos ok sin 40P01", ok,
          f"S1={out1[:120]!r} S2={out2[:120]!r}")
    kind = psql("select kind from home_member where id = 998110")
    check("F10 estado final coherente (kind=adult y snapshot = el set posterior al reset)",
          kind == "adult" and m_perms() == "home.view", f"kind={kind} perms={m_perms()}")

# F11 (R1-02, 4 checks): no-admin con home.members.manage reenvía el kind que leyó mientras el
# admin cambia el kind → Not Allowed (D-011), kind/snapshot coherentes y una sola tanda de audit
XT_BLOCK = "F11"
if xt_on("F11"):
    p19_reset(kind_m="child")
    psql(f"update home_membership set role = 'member' where id = {P19_MID_B}; "
         f"insert into membership_permission (home_membership_id, permission_code) values "
         f"({P19_MID_B}, 'home.members.manage'), ({P19_MID_B}, 'home.view')")
    out0, out1, blocked = p19_race(
        "select update_home_member(998110, 'adult', null, null, null)", a_uid,
        "select update_home_member(998110, 'child', null, null, null)", b_uid, "update_home_member")
    check("F11 S1 (no-admin con manage, kind leído = child) espera el lock de hogar", blocked is True,
          f"S0={outcome(out0)} S1={outcome(out1)}")
    ok = (outcome(out0) == "ok" and outcome(out1) == "Not Allowed" and "40P01" not in out0 + out1)
    check("F11 S0 (admin, child→adult) → ok y S1 → Not Allowed sin 40P01 (D-011, R1-02)", ok,
          f"S0={out0[:120]!r} S1={out1[:120]!r}")
    kind = psql("select kind from home_member where id = 998110")
    check("F11 finales: kind = adult y snapshot de M = defaults de adult",
          kind == "adult" and m_perms() == kind_defaults(kind) and m_perms() != "",
          f"kind={kind} perms={m_perms()}")
    n_all = kind_change()
    n_ok = kind_change(where="and payload->>'kind_from' = 'child' "
                             "and payload->>'kind_to' = 'adult'")
    n_child = kind_change(where="and payload->>'kind_to' = 'child'")
    check("F11 exactamente una tanda kind_change (la de S0; nada del intento de S1)",
          int(n_all) > 0 and n_all == n_ok and n_child == "0",
          f"tandas={n_all} child→adult={n_ok} a_child={n_child}")

# F12 (R1-02, 8 checks): (a) kinds distintos → encadenado, el segundo decide; (b) mismo kind →
# exactamente un reset; (c) rama 4a: baja de M en paralelo → 200 sin reset ni audit
XT_BLOCK = "F12"
if xt_on("F12"):
    p19_reset(kind_m="adult")
    out1, out2, _ = p19_race(
        "select update_home_member(998110, 'child', null, null, null)", a_uid,
        "select update_home_member(998110, 'relative', null, null, null)", a_uid,
        hold=0.3, stagger=0.1)
    check("F12(a) ambos 200 sin 40P01 (2 sesiones del admin)",
          outcome(out1) == "ok" and outcome(out2) == "ok" and "40P01" not in out1 + out2,
          f"S1={out1[:120]!r} S2={out2[:120]!r}")
    kind = psql("select kind from home_member where id = 998110")
    check("F12(a) kind final = el del segundo (relative)", kind == "relative", f"kind={kind}")
    check("F12(a) snapshot final = defaults de relative",
          m_perms() == kind_defaults(kind) and m_perms() != "", f"perms={m_perms()}")
    n1 = kind_change(where="and payload->>'kind_from' = 'adult' and payload->>'kind_to' = 'child'")
    n2 = kind_change(where="and payload->>'kind_from' = 'child' and payload->>'kind_to' = 'relative'")
    check("F12(a) audit encadenado (kind_from del segundo = kind_to del primero)",
          int(n1) > 0 and int(n2) > 0, f"adult→child={n1} child→relative={n2}")

    p19_reset(kind_m="adult")
    out1, out2, _ = p19_race(
        "select update_home_member(998110, 'child', null, null, null)", a_uid,
        "select update_home_member(998110, 'child', null, null, null)", a_uid,
        hold=0.3, stagger=0.1)
    n_all = kind_change()
    n_ok = kind_change(where="and payload->>'kind_from' = 'adult' and payload->>'kind_to' = 'child'")
    check("F12(b) ambos 200 sin 40P01 y exactamente un reset (una tanda kind_change)",
          outcome(out1) == "ok" and outcome(out2) == "ok" and "40P01" not in out1 + out2
          and int(n_all) > 0 and n_all == n_ok,
          f"S1={out1[:120]!r} S2={out2[:120]!r} tandas={n_all} adult→child={n_ok}")
    kind = psql("select kind from home_member where id = 998110")
    check("F12(b) snapshot final = defaults de child",
          kind == "child" and m_perms() == kind_defaults(kind) and m_perms() != "",
          f"kind={kind} perms={m_perms()}")

    p19_reset(kind_m="adult")
    n_pre = kind_change()
    out0, out1, blocked = p19_race(
        "select remove_home_membership(998100, 998103)", a_uid,
        "select update_home_member(998110, 'child', null, null, null)", a_uid, "update_home_member")
    body = out_json(out1)
    check("F12(c) S1 espera el lock de hogar y responde ok con kind = child (rama 4a)",
          blocked is True and outcome(out0) == "ok" and outcome(out1) == "ok"
          and isinstance(body, dict) and body.get("kind") == "child",
          f"blocked={blocked} S0={outcome(out0)} S1={outcome(out1)} body={str(body)[:120]}")
    n_mem = psql("select count(*) from home_membership where id = 998103")
    n_perm = psql("select count(*) from membership_permission where home_membership_id = 998103")
    check("F12(c) sin membresía, 0 filas de membership_permission y 0 audit nuevo para M",
          n_mem == "0" and n_perm == "0" and kind_change() == n_pre,
          f"membresias={n_mem} perms={n_perm} audit {n_pre}→{kind_change()}")

# X1–X5: cross-tenant de las rutas 1.9 — admin de B sobre hogar A y member de A sin permisos
# (C ya es miembro de home(A) desde K20: alta idempotente, on conflict no cambia su snapshot)
XT_BLOCK = "X0"
mid_x = int(psql(f"with x as (insert into home_membership (home_id, app_user_id, role) "
                 f"values ({home_a}, {c_id}, 'member') "
                 f"on conflict (home_id, app_user_id) do update set role = 'member' returning id) "
                 f"select id from x"))
for cid, sub, sqlcall, want, name in (
        ("X1", b_uid, f"select set_home_permissions({home_a}, {mid_x}, '[\"home.view\"]'::jsonb)",
         "Not Found", "X1 admin de B → set_home_permissions sobre hogar A → Not Found"),
        ("X2", b_uid, f"select get_home_permissions({home_a})", "Not Found",
         "X2 admin de B → get_home_permissions sobre hogar A → Not Found"),
        ("X3", b_uid, f"select get_home_audit({home_a}, null, null)", "Not Found",
         "X3 admin de B → get_home_audit sobre hogar A → Not Found"),
        ("X4", c_uid, f"select set_home_permissions({home_a}, {mid_x}, '[\"home.view\"]'::jsonb)",
         "Not Allowed", "X4 member de A sin manage → set_home_permissions → Not Allowed"),
        ("X5", c_uid, f"select get_home_audit({home_a}, null, null)", "Not Allowed",
         "X5 member de A no admin → get_home_audit → Not Allowed")):
    XT_BLOCK = cid
    if xt_on(cid):
        out = psql_run(f"begin;\nselect set_config('request.jwt.claim.sub', '{sub}', true);\n"
                       f"{sqlcall};\ncommit;\n")[1]
        check(name, outcome(out) == want and "40P01" not in out, f"out={out[:160]!r}")
XT_BLOCK = "BASE"

# T-DL-A12 (R1-03/R1-02, 16 checks): 15 pares con orden invertido (A12_ITERS por par; el builder
# usa 3, el verifier 20) y pg_sleep(0.3) intra-transacción. Criterio: 0×40P01 y outcomes solo ok /
# Not Found / Not Allowed. El check global cierra con los invariantes finales (owners ≥ 1, 0 filas
# de admin, snapshot de M = defaults de su kind final).
XT_BLOCK = "TDL_A12"
if xt_on("TDL_A12"):
    A12_PAIRS = [
        ("remove_cal ∥ remove_cal",
         f"select remove_calendar_user({P19_CAL}, {b_id})", f"select remove_calendar_user({P19_CAL}, {a_id})"),
        ("remove_tl ∥ remove_tl",
         f"select remove_task_list_user({P19_LST}, {b_id})", f"select remove_task_list_user({P19_LST}, {a_id})"),
        ("add_cal ∥ add_cal",
         f"select add_calendar_user({P19_CAL}, '{C_EMAIL}')", f"select add_calendar_user({P19_CAL}, '{C_EMAIL}')"),
        ("add_tl ∥ add_tl",
         f"select add_task_list_user({P19_LST}, '{C_EMAIL}')", f"select add_task_list_user({P19_LST}, '{C_EMAIL}')"),
        ("remove_cal ∥ remove_home_membership",
         f"select remove_calendar_user({P19_CAL}, {b_id})", "select remove_home_membership(998100, 998101)"),
        ("remove_tl ∥ remove_home_membership",
         f"select remove_task_list_user({P19_LST}, {b_id})", "select remove_home_membership(998100, 998101)"),
        ("remove_cal ∥ add_cal",
         f"select remove_calendar_user({P19_CAL}, {b_id})", f"select add_calendar_user({P19_CAL}, '{C_EMAIL}')"),
        ("delete_calendar ∥ remove_cal",
         "select delete_calendar(998120)", f"select remove_calendar_user({P19_CAL}, {a_id})"),
        ("delete_task_list ∥ remove_tl",
         "select delete_task_list(998121)", f"select remove_task_list_user({P19_LST}, {a_id})"),
        ("set_perms ∥ set_home_membership_role",
         "select set_home_permissions(998100, 998103, '[\"home.view\"]'::jsonb)",
         "select set_home_membership_role(998100, 998103, 'admin')"),
        ("set_perms ∥ set_perms",
         "select set_home_permissions(998100, 998103, '[\"home.view\"]'::jsonb)",
         "select set_home_permissions(998100, 998103, '[\"calendar.view\"]'::jsonb)"),
        ("set_perms ∥ remove_home_membership",
         "select set_home_permissions(998100, 998103, '[\"home.view\"]'::jsonb)",
         "select remove_home_membership(998100, 998103)"),
        ("update_home_member(kind) ∥ set_perms",
         "select update_home_member(998110, 'adult', null, null, null)",
         "select set_home_permissions(998100, 998103, '[\"home.view\"]'::jsonb)"),
        ("set_perms ∥ update_calendar",
         "select set_home_permissions(998100, 998103, '[\"home.view\"]'::jsonb)",
         "select update_calendar(998120, 'XT-P19-C', '#111111', true, true)"),
        ("update_home_member(kind=a) ∥ update_home_member(kind=b)",
         "select update_home_member(998110, 'child', null, null, null)",
         "select update_home_member(998110, 'relative', null, null, null)"),
    ]
    a12_deadlocks = 0
    a12_bad = 0
    for pname, sqla, sqlb in A12_PAIRS:
        pair_bad = 0
        for i in range(A12_ITERS):
            p19_reset()
            sa = (f"begin;\nselect set_config('request.jwt.claim.sub', '{a_uid}', true);\n"
                  f"select pg_sleep(0.3);\n{sqla};\ncommit;\n")
            sb = (f"begin;\nselect set_config('request.jwt.claim.sub', '{b_uid}', true);\n"
                  f"select pg_sleep(0.3);\n{sqlb};\ncommit;\n")
            if i % 2 == 0:  # orden invertido: par → A primero; impar → B primero
                pa = psql_async(sa); time.sleep(0.1); pb = psql_async(sb)
            else:
                pb = psql_async(sb); time.sleep(0.1); pa = psql_async(sa)
            outa, _ = pa.communicate(timeout=120)
            outb, _ = pb.communicate(timeout=120)
            outs = outa + outb
            dl = "40P01" in outs or "deadlock" in outs.lower()
            bad = dl or any(outcome(o) not in ("ok", "Not Found", "Not Allowed")
                            for o in (outa, outb))
            if dl:
                a12_deadlocks += 1
            if bad:
                pair_bad += 1
                a12_bad += 1
                print(f"  TDL-A12 {pname} iter {i}: A={outa[:120]!r} B={outb[:120]!r}")
        check(f"TDL-A12 {pname}: {A12_ITERS} iteraciones, 0×40P01, "
              "outcomes ok/Not Found(/Not Allowed)", pair_bad == 0,
              f"{pair_bad} iteraciones fuera de spec")
    kind = psql("select kind from home_member where id = 998110")
    owners = psql(f"select count(*) from calendar_user where calendar_id = {P19_CAL} "
                  "and role = 'owner'")
    admin_rows = psql("select count(*) from membership_permission mp "
                      "join home_membership hm on hm.id = mp.home_membership_id "
                      "where hm.role = 'admin'")
    check("TDL-A12 global: 0×40P01 y invariantes finales (owners ≥ 1, 0 filas de admin, "
          "snapshot de M = defaults de su kind final)",
          a12_deadlocks == 0 and a12_bad == 0 and int(owners) >= 1 and admin_rows == "0"
          and m_perms() == kind_defaults(kind) and m_perms() != "",
          f"deadlocks={a12_deadlocks} bad={a12_bad} owners={owners} admin_rows={admin_rows} "
          f"kind={kind} perms={m_perms()}")
XT_BLOCK = "BASE"

# T21: limpieza del bloque (replica solo para borrado) y query de residuos anotada: tras esta
# limpieza no quedan filas 9981xx; clean_xt() de más abajo verifica además 0 filas XT-% y 0
# membresías/hogares de xt, y aborta el script si queda algún residuo.
psql(P19_Q)

# ── K21 (1.5, plan §8.2) y §8.3: cascada app_user → person → home_member (trigger 0014c, I5) ──
# Usuario scratch 995999 sin home_membership (sin admin de ningún hogar): borrar su app_user borra
# sus person en cascada (0001: person.user_id ON DELETE CASCADE) y fn_person_deleted (0014c) borra
# su home_member → sin huérfanos I5. El alta scratch usa session_replication_role = replica SOLO
# para saltarse la FK app_user→auth.users (mismo patrón que 1.3).
psql("""
set session_replication_role = replica;
insert into auth.users (id, email, raw_user_meta_data)
    values ('00000000-0000-4000-8000-000000000999', 'xt-cascada@check.homita.example', '{"name":"XT-Cascada"}');
insert into app_user (id, auth_uid, name, email)
    values (995999, '00000000-0000-4000-8000-000000000999', 'XT-Cascada', 'xt-cascada@check.homita.example');
set session_replication_role = default;
""")
psql(f"""
begin;
insert into home_member (home_id, kind, name, color, status, created_by)
    values ({home_a}, 'adult', 'XT-Cascada-HM', '#112222', 'active', 995999);
insert into person (user_id, home_id, home_member_id, name, color)
    select 995999, {home_a}, id, 'XT-Cascada-HM', '#112222' from home_member where name = 'XT-Cascada-HM';
commit;
""")
psql("delete from app_user where id = 995999; "
     "delete from auth.users where id = '00000000-0000-4000-8000-000000000999';")
row = psql("select (select count(*) from app_user where id = 995999) || ' ' || "
           "(select count(*) from person where name = 'XT-Cascada-HM') || ' ' || "
           "(select count(*) from home_member where name = 'XT-Cascada-HM')")
check("K21 borrar app_user → person en cascada → home_member borrado por 0014c (I5)",
      row == "0 0 0", f"psql: {row!r}")

# ── §8.3: invariante I5 (person ↔ home_member 1:1, mismo home_id) tras K1–K21 ──
i5a = psql("select count(*) from person p left join home_member hm on hm.id = p.home_member_id "
           "where hm.id is null")
i5b = psql("select count(*) from home_member hm left join person p on p.home_member_id = hm.id "
           "where p.id is null")
i5c = psql("select count(*) from home_member hm join person p on p.home_member_id = hm.id "
           "where p.home_id <> hm.home_id")
check("I5: sin person huérfana de home_member", i5a == "0", f"n={i5a}")
check("I5: sin home_member huérfano de person (tras K1–K21)", i5b == "0", f"n={i5b}")
check("I5: todo home_member con person del mismo home_id", i5c == "0", f"n={i5c}")

clean_xt()
fugas = results.count(False)
print(f"\n{len(results) - fugas}/{len(results)} casos ok — {fugas} fugas"
      + (" · bloques: " + " ".join(f"{k}={v}" for k, v in counts.items()) if counts else ""))
sys.exit(1 if fugas else 0)
