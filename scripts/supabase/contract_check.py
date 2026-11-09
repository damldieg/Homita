#!/usr/bin/env python3
"""Smoke del contrato (a) de la Edge Function `api` (D-008), sin oráculo: aserciones de
estado/valor/forma esperada por ruta contra la Edge local.

El backend legacy se retiró del repo (tag `legacy-php-final`, change remove-php-legacy): ya no hay
segundo lado con el que comparar. Este script fija el comportamiento documentado del contrato
(inventario archivado en `.dorch/archive/control-api/contract-inventory.md`, desviaciones en
`docs/ARCHITECTURE.md`) y falla listando las rutas con regresión.

* Cobertura: las 43 rutas del contrato (tabla ROUTES de `supabase/functions/api/index.ts`),
  incluidas `GET /config` y `PATCH /user/update` (no cubiertas por el antiguo oráculo). El resumen
  final exige 43/43 y exit 0 solo si todos los casos pasan.
* Forma: plantillas con claves EXACTAS — `"<ts>"` (`Y-m-d H:i:s`), `"<token>"` (string no vacío),
  `"<id>"`/`"<int>"`, `"<str>"`, `"<bool>"`, `"<01>"` (entero 0/1 del contrato), sufijo `?` =
  nullable (`"<int?>"`), `[t]` = todo elemento cumple `t`, literal = igualdad exacta. El sufijo de
  traza `called in <ruta>/fichero…` se normaliza a fichero+línea antes de comparar.
* Desviaciones documentadas fijadas como valor esperado de la Edge: `401 {"error":"Invalid
  credentials"}` (email inexistente y token inválido), owner-only `403 {"error":"Not Allowed"}`,
  self-remove `400 {"error":"User cannot remove themselves"}`, `refresh_token` aditivo en
  user/auth, text-only `400` en event/create, TypeError de `calendar/create` sin color.
* Guard (R1): `--fn` solo acepta hosts locales (127.0.0.1/localhost), sin flag de override — el
  script escribe y borra filas CC-% vía service_role y jamás debe tocar el proyecto alojado.
* `SUPABASE_SERVICE_ROLE_KEY` (reset de restos CC-%, R1-01): del entorno, de `.demo/functions.env`
  o de `supabase status -o env`; toda fuente con indicios de producción (`supabase.co`) se rechaza.

Datos: `scripts/demo.sh up` deja la Edge local servida y sembrada con `scripts/demo/seed.py`
(ids 1..N). El bloque viewer necesita `ALLOW_REGISTRATION=true` en la Edge local.

Uso: python3 scripts/supabase/contract_check.py [--fn URL] [--timezone TZ]
Variables de entorno (equivalentes a las opciones): SUPABASE_FUNCTIONS_URL y
SUPABASE_SERVICE_ROLE_KEY.
"""
import argparse
import datetime
import json
import os
import re
import shutil
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request

TS_RE = re.compile(r"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$")
# Sufijo de traza de TypeError ("called in <ruta>/fichero… on line <n>"): la ruta es la del
# despliegue; se compara fichero+línea, no la ruta (desviación documentada).
TRACE_RE = re.compile(r"called in \S*/([^/\s]+ on line \d+)")
REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

parser = argparse.ArgumentParser(description="Smoke del contrato de la Edge (ver docstring)")
parser.add_argument("--fn", default=os.environ.get("SUPABASE_FUNCTIONS_URL",
                                                   "http://127.0.0.1:54321/functions/v1/api"),
                    help="Edge Function api (stack local o $SUPABASE_FUNCTIONS_URL)")
parser.add_argument("--email", default="demo@homita.example")
parser.add_argument("--password", default="demo1234")
parser.add_argument("--timezone", default="Europe/Madrid")
args = parser.parse_args()
FN = args.fn.rstrip("/")


def assert_local(url, what):
    if urllib.parse.urlparse(url).hostname not in ("127.0.0.1", "localhost"):
        sys.exit(f"{what} solo acepta hosts locales (127.0.0.1/localhost), llega {url!r}: "
                 "este script escribe y borra datos y jamás debe tocar el proyecto alojado")


assert_local(FN, "--fn")


def request(method, path, body=None, token=None):
    """(status, texto) — también para 4xx/5xx (HTTPError), que son casos del contrato."""
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = "Bearer " + token
    req = urllib.request.Request(FN + path, data=json.dumps(body).encode() if body is not None else None,
                                 method=method, headers=headers)
    try:
        with urllib.request.urlopen(req) as r:
            return r.status, r.read().decode()
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()


def parse(text):
    try:
        return json.loads(text)
    except ValueError:
        return text


def trace_norm(value):
    """Rutas de traza TypeError → fichero+línea (comparable entre despliegues)."""
    if isinstance(value, dict):
        return {k: trace_norm(v) for k, v in value.items()}
    if isinstance(value, list):
        return [trace_norm(v) for v in value]
    if isinstance(value, str):
        return TRACE_RE.sub(r"called in \1", value)
    return value


# ── plantillas de forma ──

def shape(value, tmpl, where, issues):
    if isinstance(tmpl, dict):
        if not isinstance(value, dict):
            issues.append(f"{where}: objeto esperado, llega {value!r}"[:300])
            return
        for k in tmpl:
            if k not in value:
                issues.append(f"{where}: falta la clave {k!r}")
        for k in value:
            if k not in tmpl:
                issues.append(f"{where}: clave inesperada {k!r}")
        for k, t in tmpl.items():
            if k in value:
                shape(value[k], t, f"{where}.{k}", issues)
        return
    if isinstance(tmpl, list):
        if not isinstance(value, list):
            issues.append(f"{where}: lista esperada, llega {value!r}"[:300])
            return
        for i, item in enumerate(value):
            if tmpl:
                shape(item, tmpl[0], f"{where}[{i}]", issues)
        return
    if isinstance(tmpl, str) and tmpl.startswith("<") and tmpl.endswith(">"):
        base, nullable = tmpl[1:-1], tmpl[1:-1].endswith("?")
        if nullable:
            base = base[:-1]
        if value is None:
            if not nullable:
                issues.append(f"{where}: null no esperado ({tmpl})")
            return
        ok = {
            "ts": lambda v: isinstance(v, str) and bool(TS_RE.match(v)),
            "token": lambda v: isinstance(v, str) and v != "",
            "id": lambda v: isinstance(v, int) and not isinstance(v, bool) and v >= 1,
            "int": lambda v: isinstance(v, int) and not isinstance(v, bool),
            "str": lambda v: isinstance(v, str) and v != "",
            "bool": lambda v: isinstance(v, bool),
            "01": lambda v: v in (0, 1) and not isinstance(v, bool),
        }[base](value)
        if not ok:
            issues.append(f"{where}: {value!r} no cumple {tmpl}")
        return
    if value != tmpl:
        issues.append(f"{where}: {value!r} (esperado {tmpl!r})"[:300])


# ── resultados y cobertura ──

results = []
covered = set()
regressed = []


def record(route, name, ok, detail=""):
    covered.add(route)
    results.append(bool(ok))
    print(("ok   " if ok else "FAIL ") + name)
    if not ok:
        if route not in regressed:
            regressed.append(route)
        if detail:
            print("     " + detail)


def check(route, name, res, status, expect=None):
    """Aserción de estado/valor/forma esperada de la Edge. `expect`: texto exacto, plantilla de
    forma (dict/list) o None (solo status). Devuelve el body parseado (para encadenar escenarios)."""
    got_status, text = res
    issues = []
    if got_status != status:
        issues.append(f"status: {got_status} (esperado {status}) — {text[:200]}")
    body = trace_norm(parse(text))
    if isinstance(expect, str):
        if trace_norm(text) != expect:
            issues.append(f"body: {trace_norm(text)[:300]}")
            issues.append(f"esperado: {expect[:300]}")
    elif expect is not None:
        shape(body, expect, "body", issues)
    record(route, name, not issues, "\n     ".join(issues))
    return body


def value(route, name, ok, detail=""):
    record(route, name, bool(ok), detail)


PERSON = {"id": "<id>", "user_id": "<int>", "name": "<str>", "color": "<str>",
          "created_at": "<ts>", "updated_at": "<ts>", "editable": "<bool>"}
PERSON_REF = {"id": "<id>", "user_id": "<int>", "name": "<str>", "color": "<str>"}
CAL_ITEM = {"id": "<id>", "name": "<str>", "color": "<str>", "token": "<token>",
            "created_at": "<ts>", "updated_at": "<ts>", "widget": "<01>", "dashboard": "<01>",
            "upcoming_event_count": "<int>"}
CAL_DETAIL = {"id": "<id>", "name": "<str>", "color": "<str>", "token": "<token>",
              "created_at": "<ts>", "updated_at": "<ts>"}
CAL_USER = {"cu_id": "<id>", "user_id": "<id>", "name": "<str>", "email": "<str>", "role": "<str>"}
USER = {"id": "<id>", "name": "<str>", "email": "<str>", "created_at": "<ts>", "updated_at": "<ts>"}
USER_CREATE = {"id": "<id>", "name": "<str>", "email": "<str>", "token": "<token>",
               "created_at": "<ts>", "updated_at": "<ts>"}
USER_AUTH = {"id": "<id>", "name": "<str>", "email": "<str>", "token": "<token>",
             "refresh_token": "<token>", "created_at": "<ts>", "updated_at": "<ts>"}
ROUTINE = {"id": "<id>", "calendar_id": "<id>", "title": "<str>", "days": ["<int>"], "time": "<str>",
           "start_date": "<str>", "end_date": "<str?>", "active": "<bool>", "available_from": "<ts>",
           "frequency": "<str>", "interval": "<int>", "created_at": "<ts>", "updated_at": "<ts>",
           "calendar_name": "<str>", "calendar_color": "<str>", "alarm": "<int?>",
           "persons": [PERSON_REF]}
EVENT_ITEM = {"id": "<id>", "calendar_id": "<id>", "title": "<str>", "date_at": "<ts>",
              "created_at": "<ts>", "updated_at": "<ts>", "routine_id": "<int?>",
              "routine_date": "<str?>", "calendar_color": "<str>", "calendar_name": "<str>",
              "alarm": "<int?>", "persons": [PERSON_REF]}
EVENT_DETAIL = {"id": "<id>", "calendar_id": "<id>", "title": "<str>", "date_at": "<ts>",
                "created_at": "<ts>", "updated_at": "<ts>", "routine_id": "<int?>",
                "routine_date": "<str?>", "alarm": "<int?>", "persons": [PERSON_REF]}
TASK_ITEM = {"id": "<id>", "task_list_id": "<id>", "title": "<str>", "completed_at": "<ts?>",
             "created_at": "<ts>", "updated_at": "<ts>", "order": "<int>",
             "task_list_color": "<str>", "task_list_name": "<str>"}
TL_ITEM = {"id": "<id>", "name": "<str>", "color": "<str>", "token": "<token>", "sort": "<str>",
           "created_at": "<ts>", "updated_at": "<ts>", "widget": "<01>", "dashboard": "<01>",
           "pending_task_count": "<int>"}
TL_DETAIL = {"id": "<id>", "name": "<str>", "color": "<str>", "token": "<token>", "sort": "<str>",
             "created_at": "<ts>", "updated_at": "<ts>"}
TL_USER = {"tlu_id": "<id>", "user_id": "<id>", "name": "<str>", "email": "<str>", "role": "<str>"}
SUCCESS = {"success": True}
CONFIG = {"allow_registration": "<bool>"}
ERR_INVALID_CREDS = '{"error":"Invalid credentials"}'
ERR_EMAIL_EXISTS = '{"error":"Email already exists"}'
ERR_SELF_REMOVE = '{"error":"User cannot remove themselves"}'
ERR_NOT_ALLOWED = '{"error":"Not Allowed"}'
ERR_NOT_FOUND = '{"error":"Not Found"}'
ERR_ALARM = '{"error":"Alarm must be nonnegative minutes or null"}'
# TypeError del motor, mensaje exacto del contrato (sufijo de traza normalizado a fichero+línea)
ERR_CAL_NO_COLOR = (r'App\Models\Calendar::create(): Argument #2 ($color) must be of '
                    r'type string, null given, called in CalendarCreate.php on line 21')

ROUTES = [
    "GET /config", "POST /user/create", "POST /user/auth", "PATCH /user/update",
    "GET /calendar", "GET /calendar/detail", "POST /calendar/create", "PATCH /calendar/update",
    "DELETE /calendar/delete", "GET /calendar/user", "POST /calendar/user", "DELETE /calendar/user",
    "GET /person", "POST /person/create", "PATCH /person/update", "DELETE /person/delete",
    "GET /routine", "GET /routine/detail", "POST /routine/create", "PATCH /routine/update",
    "PATCH /routine/alarm", "DELETE /routine/delete",
    "GET /event", "GET /event/detail", "POST /event/create", "PATCH /event/update",
    "DELETE /event/delete", "PATCH /event/alarm",
    "GET /task-list", "GET /task-list/detail", "POST /task-list/create", "PATCH /task-list/update",
    "DELETE /task-list/delete", "GET /task-list/user", "POST /task-list/user", "DELETE /task-list/user",
    "GET /task", "GET /task/detail", "POST /task/create", "PATCH /task/update",
    "PATCH /task/complete", "PATCH /task/order", "DELETE /task/delete",
]


def epoch(local_date):
    """Hora local enviada como segundos epoch en UTC (igual que la app, ContentRepository.kt:30)."""
    return int(datetime.datetime.combine(local_date, datetime.time())
               .replace(tzinfo=datetime.timezone.utc).timestamp())


today = datetime.date.today()
month_start = today.replace(day=1)
for _ in range(12):  # today.withDayOfMonth(1).minusMonths(12)
    month_start = (month_start - datetime.timedelta(days=1)).replace(day=1)
monday = today - datetime.timedelta(days=today.weekday())
next_monday = monday + datetime.timedelta(days=7)
week_end = epoch(monday + datetime.timedelta(days=7)) - 1        # monday.plusDays(7) 00:00 − 1
next_week_end = epoch(next_monday + datetime.timedelta(days=7)) - 1
content_end = epoch(today + datetime.timedelta(days=7)) - 1      # today.plusDays(ROUTINE_DAYS) − 1
tz = args.timezone


# ── entorno local y reset de restos (R1-01) ──

def parse_env(text):
    env = {}
    for line in text.splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            key, val = line.split("=", 1)
            env[key.strip()] = val.strip().strip('"').strip("'")
    return env


def read_env_file(path):
    with open(path) as f:
        return parse_env(f.read())


def load_service_key():
    """SUPABASE_SERVICE_ROLE_KEY para reset_leftovers: entorno → .demo/functions.env →
    `supabase status -o env`. Toda fuente con indicios de producción se rechaza (R1)."""
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY")
    if key:
        return key
    path = os.path.join(REPO, ".demo", "functions.env")
    if os.path.exists(path):
        env = read_env_file(path)
        if any("supabase.co" in v for v in env.values()):
            sys.exit(f"{path}: contiene credenciales de producción; la demo local no lo usa")
        key = env.get("SUPABASE_SERVICE_ROLE_KEY") or env.get("SERVICE_ROLE_KEY")
        if key:
            return key
    cmds = [["supabase"]] if shutil.which("supabase") else \
        ([["npx", "--no-install", "supabase"], ["npx", "supabase@latest"]] if shutil.which("npx") else [])
    for cmd in cmds:
        try:
            out = subprocess.run(cmd + ["status", "-o", "env"], capture_output=True,
                                 text=True, timeout=30).stdout
        except (OSError, subprocess.SubprocessError):
            continue
        env = parse_env(out)
        api, key = env.get("API_URL", ""), env.get("SERVICE_ROLE_KEY", "")
        if key:
            if "supabase.co" in api:
                sys.exit(f"{' '.join(cmd)} status: API_URL de producción ({api}); no se usa aquí")
            assert_local(api, "supabase status")
            return key
    return None


def reset_leftovers():
    """Higiene entre ejecuciones: borra los restos con prefijo CC-% (escenarios y bloque viewer —
    la Edge no llega a borrar el calendario del viewer: 403) para poder re-ejecutar sin re-sembrar.
    DELETE REST vía service_role contra el REST local derivado de --fn (local por el guard). Padre
    basta (cascade); los eventos van antes que las rutinas (`event.routine_id` es set null)."""
    key = load_service_key()
    if not key:
        print("aviso: sin SUPABASE_SERVICE_ROLE_KEY local: reset_leftovers omitido "
              "(la 2ª ejecución puede fallar por restos)")
        return
    rest = FN.split("/functions/")[0] + "/rest/v1"
    for table, column in (("event", "title"), ("routine", "title"), ("task", "title"),
                          ("task_list", "name"), ("calendar", "name"), ("person", "name")):
        req = urllib.request.Request(f"{rest}/{table}?{column}=like.CC-*", method="DELETE",
                                     headers={"apikey": key, "Authorization": "Bearer " + key})
        try:
            urllib.request.urlopen(req).read()
        except urllib.error.HTTPError as e:
            print(f"aviso: reset_leftovers {table} falló ({e.code}): {e.read().decode()[:120]}")


# ── config, auth y reset ──

try:
    cfg = request("GET", "/config")
except OSError as e:
    sys.exit(f"No responde {FN}: {e}\nLevanta la Edge local: supabase start && scripts/demo.sh up")
check("GET /config", "GET /config → {allow_registration: bool}", cfg, 200, CONFIG)
value("GET /config", "GET /config → registro abierto para la demo",
      isinstance(cfg_body := trace_norm(parse(cfg[1])), dict) and cfg_body.get("allow_registration") is True,
      "el smoke necesita ALLOW_REGISTRATION=true en la Edge local (scripts/demo.sh up)")

auth = request("POST", "/user/auth", {"email": args.email, "password": args.password})
check("POST /user/auth", "POST /user/auth (login de la demo)", auth, 200, USER_AUTH)
if auth[0] != 200:
    sys.exit("login falló: no se puede seguir (¿scripts/demo.sh up con seed?)")
tok = parse(auth[1])["token"]
aid = parse(auth[1])["id"]

reset_leftovers()

# ── Lecturas del dashboard (escenarios de ContentRepository y CalendarRepository) ──

cases = [
    ("ContentRepository /event routine=false (día 1 del mes −12, sin end_date)",
     f"/event?start_date={epoch(month_start)}&routine=false&timezone={tz}&dashboard=true"),
    ("ContentRepository /event routine=true (hoy..+7)",
     f"/event?start_date={epoch(today)}&end_date={content_end}&routine=true&timezone={tz}&dashboard=true"),
    ("CalendarRepository /event semana actual routine=false (lunes–domingo)",
     f"/event?start_date={epoch(monday)}&end_date={week_end}&routine=false&timezone={tz}&dashboard=true"),
    ("CalendarRepository /event semana actual routine=true",
     f"/event?start_date={epoch(monday)}&end_date={week_end}&routine=true&timezone={tz}&dashboard=true"),
    ("CalendarRepository /event semana siguiente routine=false",
     f"/event?start_date={epoch(next_monday)}&end_date={next_week_end}&routine=false&timezone={tz}&dashboard=true"),
    ("CalendarRepository /event semana siguiente routine=true",
     f"/event?start_date={epoch(next_monday)}&end_date={next_week_end}&routine=true&timezone={tz}&dashboard=true"),
    ("ContentRepository /task dashboard=true", "/task?dashboard=true"),
    ("GET /event con q= ignorado (T3)", f"/event?q=leche&start_date={epoch(today)}&timezone={tz}"),
]
for name, path in cases:
    check("GET /event" if "/event" in path else "GET /task", name,
          request("GET", path, None, tok), 200, [EVENT_ITEM] if "/event" in path else [TASK_ITEM])

# ── Lecturas de la app gestora ──

read_lists = [
    ("GET /calendar", "/calendar", [CAL_ITEM]),
    ("GET /calendar/user", "/calendar/user?calendar_id=1", [CAL_USER]),
    ("GET /person", "/person", [PERSON]),
    ("GET /routine", f"/routine?timezone={tz}", [ROUTINE]),
    ("GET /task-list", "/task-list", [TL_ITEM]),
    ("GET /task-list/user", "/task-list/user?task_list_id=1", [TL_USER]),
    ("GET /task", "/task", [TASK_ITEM]),
]
for name, path, tmpl in read_lists:
    check(name, name, request("GET", path, None, tok), 200, tmpl)

read_details = [
    ("GET /calendar/detail", "/calendar/detail?id=1", CAL_DETAIL),
    ("GET /routine/detail", f"/routine/detail?id=1&timezone={tz}", ROUTINE),
    ("GET /task-list/detail", "/task-list/detail?id=1", TL_DETAIL),
    ("GET /task/detail", "/task/detail?id=1", TASK_ITEM),
    ("GET /event/detail", f"/event/detail?id=1&timezone={tz}", EVENT_DETAIL),
]
for name, path, tmpl in read_details:
    check(name, name, request("GET", path, None, tok), 200, tmpl)

# ── Errores exactos del contrato ──

check("POST /user/auth", "POST /user/auth sin campos (400)",
      request("POST", "/user/auth", {}), 400, '{"error":"Email and password are required"}')
check("POST /user/auth", "POST /user/auth contraseña errónea (401)",
      request("POST", "/user/auth", {"email": args.email, "password": "mala"}), 401, ERR_INVALID_CREDS)
check("POST /user/auth", "POST /user/auth email inexistente (401, desviación documentada)",
      request("POST", "/user/auth", {"email": "noexiste@homita.example", "password": args.password}),
      401, ERR_INVALID_CREDS)
check("GET /calendar/detail", "GET /calendar/detail sin id (400)",
      request("GET", "/calendar/detail", None, tok), 400, '{"error":"Calendar ID is required"}')
check("GET /event/detail", "GET /event/detail id inexistente (500 Not Found)",
      request("GET", f"/event/detail?id=999999&timezone={tz}", None, tok), 500, ERR_NOT_FOUND)
check("GET /task/detail", "GET /task/detail id inexistente (500 Not Found)",
      request("GET", "/task/detail?id=999999", None, tok), 500, ERR_NOT_FOUND)
check("GET /event", "GET /event timezone inválido (400)",
      request("GET", "/event?timezone=No/Zona", None, tok), 400, '{"error":"Invalid timezone"}')
check("GET /task-list/user", "GET /task-list/user sin task_list_id (400)",
      request("GET", "/task-list/user", None, tok), 400, '{"error":"task_list_id is required"}')
check("POST /calendar/create", "POST /calendar/create sin color (500 TypeError)",
      request("POST", "/calendar/create", {"name": "CC-Sin-Color"}, tok), 500,
      {"error": ERR_CAL_NO_COLOR})
check("POST /event/create", "POST /event/create alarm negativo (400; precedencia ante person_ids)",
      request("POST", f"/event/create?timezone={tz}",
              {"calendar_id": 1, "title": "CC-Neg", "date_at": "2026-12-01 10:00:00", "alarm": -5,
               "person_ids": "no-lista"}, tok), 400, ERR_ALARM)
# Desviación de plataforma documentada: el runtime de Edge descarta el body de GET (fetch spec),
# así que task_list_id en body no filtra (el backend legacy, con body+query, daba 500 Not Found con
# id ajeno). Si la plataforma empieza a entregar el body, ESTE CASO FALLA y obliga a retirar la
# desviación.
check("GET /task", "GET /task con task_list_id en body (desviación de plataforma: 200 sin filtro)",
      request("GET", "/task", {"task_list_id": 999999}, tok), 200, [TASK_ITEM])


# ── Escenarios de escritura create→read→update→delete ──

def scenario_person():
    b = check("POST /person/create", "escenario person/create",
              request("POST", "/person/create", {"name": "CC-Persona", "color": "#AABBCC"}, tok),
              200, PERSON)
    value("POST /person/create", "escenario person/create → editable=true",
          isinstance(b, dict) and b.get("editable") is True)
    pid = b.get("id") if isinstance(b, dict) else None
    b = check("PATCH /person/update", "escenario person/update",
              request("PATCH", "/person/update", {"id": pid, "name": "CC-Persona 2", "color": "#112233"}, tok),
              200, PERSON)
    value("PATCH /person/update", "escenario person/update → nombre nuevo",
          isinstance(b, dict) and b.get("name") == "CC-Persona 2")
    b = check("GET /person", "escenario GET /person tras update",
              request("GET", "/person", None, tok), 200, [PERSON])
    value("GET /person", "escenario GET /person contiene la renombrada",
          isinstance(b, list) and any(x.get("id") == pid and x.get("name") == "CC-Persona 2" for x in b))
    check("DELETE /person/delete", "escenario person/delete",
          request("DELETE", "/person/delete", {"id": pid}, tok), 200, SUCCESS)
    b = check("GET /person", "escenario GET /person tras delete",
              request("GET", "/person", None, tok), 200, [PERSON])
    value("GET /person", "escenario GET /person ya sin la borrada",
          isinstance(b, list) and all(x.get("id") != pid for x in b))


def scenario_calendar():
    b = check("POST /calendar/create", "escenario calendar/create",
              request("POST", "/calendar/create", {"name": "CC-Cal", "color": "#123456"}, tok),
              201, CAL_DETAIL)
    cid = b.get("id") if isinstance(b, dict) else None
    check("GET /calendar/detail", "escenario calendar/detail",
          request("GET", f"/calendar/detail?id={cid}", None, tok), 200, CAL_DETAIL)
    b = check("PATCH /calendar/update", "escenario calendar/update",
              request("PATCH", "/calendar/update", {"id": cid, "name": "CC-Cal 2", "color": "#654321",
                                                    "widget": False, "dashboard": True}, tok),
              200, CAL_DETAIL)
    value("PATCH /calendar/update", "escenario calendar/update → nombre nuevo",
          isinstance(b, dict) and b.get("name") == "CC-Cal 2")
    b = check("GET /calendar", "escenario GET /calendar tras update",
              request("GET", "/calendar", None, tok), 200, [CAL_ITEM])
    value("GET /calendar", "escenario GET /calendar contiene la renombrada",
          isinstance(b, list) and any(x.get("id") == cid and x.get("name") == "CC-Cal 2" for x in b))
    check("DELETE /calendar/delete", "escenario calendar/delete",
          request("DELETE", "/calendar/delete", {"id": cid}, tok), 200, SUCCESS)
    b = check("GET /calendar", "escenario GET /calendar tras delete",
              request("GET", "/calendar", None, tok), 200, [CAL_ITEM])
    value("GET /calendar", "escenario GET /calendar ya sin la borrada",
          isinstance(b, list) and all(x.get("id") != cid for x in b))


def scenario_task_list():
    b = check("POST /task-list/create", "escenario task-list/create",
              request("POST", "/task-list/create", {"name": "CC-Lista", "color": "#222222", "sort": "title"}, tok),
              201, TL_DETAIL)
    lid = b.get("id") if isinstance(b, dict) else None
    b = check("POST /task/create", "escenario task/create",
              request("POST", "/task/create", {"task_list_id": lid, "title": "CC-Tarea"}, tok),
              201, TASK_ITEM)
    tid = b.get("id") if isinstance(b, dict) else None
    b = check("POST /task/create", "escenario task/create 2",
              request("POST", "/task/create", {"task_list_id": lid, "title": "CC-Tarea 2"}, tok),
              201, TASK_ITEM)
    tid2 = b.get("id") if isinstance(b, dict) else None
    b = check("PATCH /task/update", "escenario task/update",
              request("PATCH", "/task/update", {"id": tid, "title": "CC-Tarea B"}, tok), 200, TASK_ITEM)
    value("PATCH /task/update", "escenario task/update → título nuevo",
          isinstance(b, dict) and b.get("title") == "CC-Tarea B")
    b = check("PATCH /task/complete", "escenario task/complete",
              request("PATCH", "/task/complete", {"id": tid, "completed": True}, tok), 200, TASK_ITEM)
    value("PATCH /task/complete", "escenario task/complete → completed_at con forma TS",
          isinstance(b, dict) and isinstance(b.get("completed_at"), str) and bool(TS_RE.match(b["completed_at"])))
    check("PATCH /task/order", "escenario task/order",
          request("PATCH", "/task/order", {"id": tid, "position": 1}, tok), 200, TASK_ITEM)
    check("GET /task", "escenario GET /task de la lista",
          request("GET", f"/task?task_list_id={lid}", None, tok), 200, [TASK_ITEM])
    b = check("PATCH /task-list/update", "escenario task-list/update",
              request("PATCH", "/task-list/update", {"id": lid, "name": "CC-Lista 2", "color": "#333333",
                                                     "sort": "updated_at"}, tok), 200, TL_DETAIL)
    value("PATCH /task-list/update", "escenario task-list/update → nombre nuevo",
          isinstance(b, dict) and b.get("name") == "CC-Lista 2")
    check("DELETE /task/delete", "escenario task/delete",
          request("DELETE", "/task/delete", {"id": tid2}, tok), 200, SUCCESS)
    check("DELETE /task-list/delete", "escenario task-list/delete",
          request("DELETE", "/task-list/delete", {"id": lid}, tok), 200, SUCCESS)
    b = check("GET /task-list", "escenario GET /task-list tras delete",
              request("GET", "/task-list", None, tok), 200, [TL_ITEM])
    value("GET /task-list", "escenario GET /task-list ya sin la borrada",
          isinstance(b, list) and all(x.get("id") != lid for x in b))


def scenario_routine():
    start = (monday - datetime.timedelta(days=7)).isoformat()
    b = check("POST /routine/create", "escenario routine/create",
              request("POST", f"/routine/create?timezone={tz}", {
                  "calendar_id": 1, "title": "CC-Rutina", "frequency": "weekly", "interval": 1,
                  "days": [1, 3], "time": "09:30", "start_date": start, "end_date": None,
                  "active": True, "alarm": 10}, tok), 200, ROUTINE)
    rid = b.get("id") if isinstance(b, dict) else None
    check("GET /event", "escenario eventos de CC-Rutina",
          request("GET", f"/event?routine=true&start_date={epoch(monday)}&end_date={week_end}&timezone={tz}",
                  None, tok), 200, [EVENT_ITEM])
    b = check("PATCH /routine/alarm", "escenario routine/alarm",
              request("PATCH", f"/routine/alarm?timezone={tz}", {"id": rid, "alarm": 20}, tok),
              200, ROUTINE)
    value("PATCH /routine/alarm", "escenario routine/alarm → alarm=20",
          isinstance(b, dict) and b.get("alarm") == 20)
    b = check("PATCH /routine/update", "escenario routine/update (hora)",
              request("PATCH", f"/routine/update?timezone={tz}", {
                  "id": rid, "title": "CC-Rutina", "frequency": "weekly", "interval": 1,
                  "days": [1, 3], "time": "10:15", "start_date": start, "end_date": None,
                  "active": True}, tok), 200, ROUTINE)
    value("PATCH /routine/update", "escenario routine/update → hora nueva",
          isinstance(b, dict) and b.get("time") == "10:15")
    check("GET /event", "escenario eventos tras reconcile",
          request("GET", f"/event?routine=true&start_date={epoch(monday)}&end_date={week_end}&timezone={tz}",
                  None, tok), 200, [EVENT_ITEM])
    check("DELETE /routine/delete", "escenario routine/delete",
          request("DELETE", f"/routine/delete?timezone={tz}", {"id": rid}, tok), 200, SUCCESS)
    b = check("GET /event", "escenario eventos tras delete",
              request("GET", f"/event?routine=true&start_date={epoch(monday)}&end_date={week_end}&timezone={tz}",
                      None, tok), 200, [EVENT_ITEM])
    value("GET /event", "escenario eventos ya sin sesiones de la rutina borrada",
          isinstance(b, list) and all(x.get("routine_id") != rid for x in b))


def scenario_event():
    b = check("POST /event/create", "escenario event/create",
              request("POST", f"/event/create?timezone={tz}", {
                  "calendar_id": 1, "title": "CC-Evento", "date_at": "2026-12-01 12:00:00",
                  "alarm": 15}, tok), 200, EVENT_DETAIL)
    eid = b.get("id") if isinstance(b, dict) else None
    b = check("PATCH /event/update", "escenario event/update",
              request("PATCH", f"/event/update?timezone={tz}", {
                  "id": eid, "title": "CC-Evento 2", "date_at": "2026-12-02 13:30:00",
                  "alarm": 15}, tok), 200, EVENT_DETAIL)
    value("PATCH /event/update", "escenario event/update → título nuevo",
          isinstance(b, dict) and b.get("title") == "CC-Evento 2")
    b = check("PATCH /event/alarm", "escenario event/alarm",
              request("PATCH", f"/event/alarm?timezone={tz}", {"event_id": eid, "alarm": 30}, tok),
              200, EVENT_DETAIL)
    value("PATCH /event/alarm", "escenario event/alarm → alarm=30",
          isinstance(b, dict) and b.get("alarm") == 30)
    check("PATCH /event/update", "escenario event/update alarm negativo (400)",
          request("PATCH", f"/event/update?timezone={tz}", {
              "id": eid, "title": "CC-Evento 2", "date_at": "2026-12-02 13:30:00",
              "alarm": -5}, tok), 400, ERR_ALARM)
    check("PATCH /event/alarm", "escenario event/alarm negativo (400)",
          request("PATCH", f"/event/alarm?timezone={tz}", {"event_id": eid, "alarm": -5}, tok),
          400, ERR_ALARM)
    check("GET /event/detail", "escenario event/detail",
          request("GET", f"/event/detail?id={eid}&timezone={tz}", None, tok), 200, EVENT_DETAIL)
    check("DELETE /event/delete", "escenario event/delete",
          request("DELETE", f"/event/delete?timezone={tz}", {"id": eid}, tok), 200, SUCCESS)
    check("GET /event/detail", "escenario event/detail tras delete (500 Not Found)",
          request("GET", f"/event/detail?id={eid}&timezone={tz}", None, tok), 500, ERR_NOT_FOUND)


def scenario_profile():
    """PATCH /user/update (S): perfil propio; el nombre se recupera al terminar."""
    orig = parse(auth[1]).get("name")
    b = check("PATCH /user/update", "escenario user/update",
              request("PATCH", "/user/update", {"name": "CC Perfil"}, tok), 200, USER)
    value("PATCH /user/update", "escenario user/update → nombre nuevo",
          isinstance(b, dict) and b.get("name") == "CC Perfil")
    check("PATCH /user/update", "escenario user/update restaura el nombre",
          request("PATCH", "/user/update", {"name": orig}, tok), 200, USER)


scenario_profile()
scenario_person()
scenario_calendar()
scenario_task_list()
scenario_routine()
scenario_event()


# ── Viewer (matriz de autorización): owner-only 403 y self-remove 400 (desviaciones) ──

B_EMAIL, B_PASSWORD, B_NAME = "viewer@homita.example", "viewer1234", "CC Viewer"

reg = request("POST", "/user/create", {"name": B_NAME, "email": B_EMAIL, "password": B_PASSWORD})
if reg == (400, ERR_EMAIL_EXISTS):  # usuario viewer de una ejecución previa
    check("POST /user/create", "viewer POST /user/create (ya registrado en una ejecución previa)",
          reg, 400, ERR_EMAIL_EXISTS)
else:
    check("POST /user/create", "viewer POST /user/create (registro abierto en la demo)",
          reg, 201, USER_CREATE)
    value("POST /user/create", "viewer POST /user/create (¿ALLOW_REGISTRATION=true?)",
          reg[0] == 201, repr(reg)[:300])
vauth = request("POST", "/user/auth", {"email": B_EMAIL, "password": B_PASSWORD})
check("POST /user/auth", "viewer POST /user/auth", vauth, 200, USER_AUTH)
if vauth[0] != 200:
    sys.exit("no se pudo crear/autenticar el usuario viewer (¿ALLOW_REGISTRATION=true en la Edge?)")
vtok = parse(vauth[1])["token"]
vid = parse(vauth[1])["id"]

# Calendario de A con B de viewer (invita A, owner)
b = check("POST /calendar/create", "viewer: owner crea CC-Viewer-Cal",
          request("POST", "/calendar/create", {"name": "CC-Viewer-Cal", "color": "#445566"}, tok),
          201, CAL_DETAIL)
vcal = b.get("id") if isinstance(b, dict) else None
check("POST /calendar/user", "owner invita al viewer (POST /calendar/user)",
      request("POST", "/calendar/user", {"calendar_id": vcal, "email": B_EMAIL}, tok), 200, USER)

check("PATCH /calendar/update", "viewer PATCH /calendar/update cambia name (403, desviación documentada)",
      request("PATCH", "/calendar/update", {"id": vcal, "name": "CC-Viewer-Cal RENOMBRADO",
                                            "color": "#445566"}, vtok), 403, ERR_NOT_ALLOWED)
check("POST /calendar/user", "viewer POST /calendar/user invita (403, desviación documentada)",
      request("POST", "/calendar/user", {"calendar_id": vcal, "email": args.email}, vtok),
      403, ERR_NOT_ALLOWED)
check("DELETE /calendar/user", "viewer DELETE /calendar/user saca al owner (403, desviación documentada)",
      request("DELETE", "/calendar/user", {"calendar_id": vcal, "user_id": aid}, vtok), 403, ERR_NOT_ALLOWED)
check("DELETE /calendar/user", "self-remove DELETE /calendar/user (400)",
      request("DELETE", "/calendar/user", {"calendar_id": vcal, "user_id": vid}, vtok),
      400, ERR_SELF_REMOVE)
# Viewer actualizando SOLO sus flags propias (compartidos sin cambiar) → 200 (fila propia, S)
check("PATCH /calendar/update", "viewer PATCH /calendar/update solo flags propias",
      request("PATCH", "/calendar/update", {"id": vcal, "name": "CC-Viewer-Cal", "color": "#445566",
                                            "widget": False}, vtok), 200, CAL_DETAIL)
check("DELETE /calendar/delete", "viewer DELETE /calendar/delete (403, desviación documentada)",
      request("DELETE", "/calendar/delete", {"id": vcal}, vtok), 403, ERR_NOT_ALLOWED)

# Misma matriz con task-list: invitación y retirada de miembros
b = check("POST /task-list/create", "viewer: owner crea CC-Viewer-Lista",
          request("POST", "/task-list/create", {"name": "CC-Viewer-Lista", "color": "#445566"}, tok),
          201, TL_DETAIL)
vlist = b.get("id") if isinstance(b, dict) else None
check("POST /task-list/user", "owner invita al viewer (POST /task-list/user)",
      request("POST", "/task-list/user", {"task_list_id": vlist, "email": B_EMAIL}, tok), 200, USER)
check("DELETE /task-list/user", "viewer DELETE /task-list/user saca al owner (403, desviación documentada)",
      request("DELETE", "/task-list/user", {"task_list_id": vlist, "user_id": aid}, vtok),
      403, ERR_NOT_ALLOWED)
check("DELETE /task-list/user", "self-remove DELETE /task-list/user (400)",
      request("DELETE", "/task-list/user", {"task_list_id": vlist, "user_id": vid}, vtok),
      400, ERR_SELF_REMOVE)
check("DELETE /task-list/delete", "owner borra la lista de prueba (DELETE /task-list/delete)",
      request("DELETE", "/task-list/delete", {"id": vlist}, tok), 200, SUCCESS)

# ── Resumen: cobertura de las 43 rutas y rutas con regresión ──

missing = [r for r in ROUTES if r not in covered]
fails = results.count(False)
print(f"\n{len(results) - fails}/{len(results)} casos ok · {len(covered)}/{len(ROUTES)} rutas cubiertas")
if missing:
    print("Rutas sin cubrir: " + ", ".join(missing))
if regressed:
    print("Rutas con regresión: " + ", ".join(regressed))
sys.exit(1 if fails or missing else 0)
