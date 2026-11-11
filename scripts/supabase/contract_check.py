#!/usr/bin/env python3
"""Smoke del contrato (a) de la Edge Function `api` (D-008), sin oráculo: aserciones de
estado/valor/forma esperada por ruta contra la Edge local.

El backend legacy se retiró del repo (tag `legacy-php-final`, change remove-php-legacy): ya no hay
segundo lado con el que comparar. Este script fija el comportamiento documentado del contrato
(inventario archivado en `.dorch/archive/control-api/contract-inventory.md`, desviaciones en
`docs/ARCHITECTURE.md`) y falla listando las rutas con regresión.

* Cobertura: las 43 rutas del contrato (tabla ROUTES de `supabase/functions/api/index.ts`),
  incluidas `GET /config` y `PATCH /user/update` (no cubiertas por el antiguo oráculo), más las
  19 rutas `/home/*` de 1.4/1.5/1.6/1.9/1.15 (`HOME_ROUTES`, contrato nuevo sin oráculo PHP; las
  3 de 1.9: `GET /home/permission`, `PATCH /home/permission`, `GET /home/audit`; las 4 de 1.15:
  `GET /home/invitation`, `POST /home/invitation/create|accept|revoke`). El resumen final exige
  43/43 legacy, 19/19 home y exit 0 solo si todos los casos pasan.
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
* Bloque viewer (A-7, 108/108 = 106 + 2): el alta externa de owner (invitado no miembro del hogar
  del recurso) → `403 {"error":"Not Allowed"}` (Q3); tras dar la membresía por psql repite las
  invitaciones → 200 (+2 casos). `reset_leftovers` borra esa membresía (CASCADE a
  membership_permission y ACL) para que el caso 403 sea determinista en cada ejecución.
* Bloque M (1.6, §6.2–6.3): `/home/membership/*` sobre el hogar CC-Membresias y el usuario de
  prueba cc-mem (su cuenta/hogares/membresías los borra `reset_leftovers`): happy promote/demote/
  transfer/salir, 400 (role inválido, `Invalid membership`, ids), 403 (no admin, último admin,
  owner único, último hogar) y 404 (no miembro, cabecera ajena, membresía ajena, hogar archived).
  C2 (§6.2): 3 carreras A/B de demote en paralelo → exactamente una 200 y una 403, admins = 1.
  El usuario demo no abandona su hogar original: la salida feliz la hace el viewer.
* Bloque permisos por kind (1.7, §6.2): `fn_seed_kind_permissions` de 0019 por psql sobre la
  membresía member de cc-mem → `GET /home/membership` devuelve `permissions` = el conjunto exacto
  del kind (child 6, adult 18; collate "C"); admin = 23 del catálogo (A4, sin snapshot). R1-02:
  el helper rechaza una membresía admin (`'Not Allowed'`, sin filas). Sin rutas nuevas (D-008).
* Bloque 1.10 (contratos de /home/*, 34 casos = 15 + 15 + 4; `docs/CONTRATOS_HOME.md`): por cada
  ruta home un caso sin Bearer → `401 Unauthorized` y otro con `X-Home-Id: abc` → `400 Invalid
  home`; más `GET /home/detail` sin `home.view` → 403, `PATCH /home/default` sin `home_id` → 400,
  `PATCH /home/member/update` con `status` no string → 400 `Invalid member` y `GET /home` con
  `X-Home-Id` vacía → 200 (A9). El total esperado pasa de 351 a 385 y el resumen imprime los casos
  por ruta home; el exit code falla si alguna ruta home tiene menos de 3 casos (`MIN_HOME_CASES`).
* Bloque 1.15 (invitaciones, 69 casos = 3 + 8 + 19 + 7 + 19 + 11 + 2; `docs/CONTRATOS_HOME.md`
  §Invitaciones): altas cc-inv/cc-inv2/cc-inv3, 401/400 de las 4 rutas nuevas, create (código de
  32 hex mostrado una vez, sha256 en BD calculado en Python sin enviar el código a psql, +7 días,
  reglas de member_id, D-017: solo admin crea adult), listado sin código, accept (genérico, con
  miembro, Already member sin consumir, 404 sin oráculo, cabecera ignorada, hogar archived),
  revoke y el 403 de `/calendar/user` y `/task-list/user` con email externo (Q2 a). Los códigos
  nunca se imprimen.
* `SUPABASE_SERVICE_ROLE_KEY` (reset de restos CC-%, R1-01): del entorno, de `.demo/functions.env`
  o de `supabase status -o env`; toda fuente con indicios de producción (`supabase.co`) se rechaza.
* `PSQL` (membresía del bloque viewer): comando psql completo contra la BD local; para el stack
  local `docker exec`: `PSQL="docker exec -i supabase_db_homita-api psql -U postgres -d postgres"`.

Datos: `scripts/demo.sh up` deja la Edge local servida y sembrada con `scripts/demo/seed.py`
(ids 1..N). El bloque viewer necesita `ALLOW_REGISTRATION=true` en la Edge local.

Uso: python3 scripts/supabase/contract_check.py [--fn URL] [--timezone TZ]
Variables de entorno (equivalentes a las opciones): SUPABASE_FUNCTIONS_URL y
SUPABASE_SERVICE_ROLE_KEY.
"""
import argparse
import collections
import datetime
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import threading
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


def request(method, path, body=None, token=None, home=None):
    """(status, texto) — también para 4xx/5xx (HTTPError), que son casos del contrato. `home`:
    X-Home-Id opcional (contexto §2.2; "" = sin cabecera, A9)."""
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = "Bearer " + token
    if home is not None:
        headers["X-Home-Id"] = str(home)
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
            "obj": lambda v: isinstance(v, dict),
        }[base](value)
        if not ok:
            issues.append(f"{where}: {value!r} no cumple {tmpl}")
        return
    if value != tmpl:
        issues.append(f"{where}: {value!r} (esperado {tmpl!r})"[:300])


# ── resultados y cobertura ──

results = []
covered = collections.Counter()  # casos por ruta: `route in covered` sigue siendo la cobertura binaria
regressed = []
MIN_HOME_CASES = 3  # 1.10: umbral de casos por ruta /home/* (la cobertura binaria no prueba completitud)
CASES_BASE = 351    # 312 de 1.5/1.6/1.7/1.8 (207 + 59 M/C2 + 6 permisos kind + 40 matriz §3.4.1)
                    # + 39 del bloque 1.9 de configuración de permisos (desglose 3+8+15+7+6:
                    # PX0–PX2 setup 3, PG1–PG8 GET 8, PP1–PP15 PATCH 15, PA1–PA7 audit 7,
                    # PK1–PK6 kind 6).
CASES_110 = 15 + 15 + 4  # bloque 1.10: 15 sin Bearer → 401, 15 X-Home-Id abc → 400 Invalid home
                         # y 4 específicos (detail 403, default 400, member/update status no
                         # string 400, GET /home con X-Home-Id vacía 200)
CASES_115 = 3 + 8 + 19 + 7 + 19 + 11 + 2  # bloque 1.15 de invitaciones: IX1–IX3 altas, IH1–IH8
                                          # 401/400 de las 4 rutas, IC1–IC19 create (+ IR7),
                                          # IL1–IL7 listado, IA1–IA19 accept, IR1–IR11 revoke
                                          # (IR7 va con create) e IQ1–IQ2 email externo 403
EXPECTED_CASES = CASES_BASE + CASES_110 + CASES_115  # 351 + 34 + 69 = 454


def record(route, name, ok, detail=""):
    covered[route] += 1
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
          "created_at": "<ts>", "updated_at": "<ts>", "editable": "<bool>",
          "home_member_id": "<id>", "kind": "<str>"}
PERSON_REF = {"id": "<id>", "user_id": "<int>", "name": "<str>", "color": "<str>"}
CAL_ITEM = {"id": "<id>", "name": "<str>", "color": "<str>", "token": "<token>",
            "created_at": "<ts>", "updated_at": "<ts>", "widget": "<01>", "dashboard": "<01>",
            "upcoming_event_count": "<int>", "home_id": "<id>"}
CAL_DETAIL = {"id": "<id>", "name": "<str>", "color": "<str>", "token": "<token>",
              "created_at": "<ts>", "updated_at": "<ts>", "home_id": "<id>"}
CAL_USER = {"cu_id": "<id>", "user_id": "<id>", "name": "<str>", "email": "<str>", "role": "<str>",
            "home_role": "<str>"}
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
           "pending_task_count": "<int>", "home_id": "<id>"}
TL_DETAIL = {"id": "<id>", "name": "<str>", "color": "<str>", "token": "<token>", "sort": "<str>",
             "created_at": "<ts>", "updated_at": "<ts>", "home_id": "<id>"}
TL_USER = {"tlu_id": "<id>", "user_id": "<id>", "name": "<str>", "email": "<str>", "role": "<str>",
           "home_role": "<str>"}
# Contrato nuevo de 1.4 (§2, sin oráculo PHP). R1-03: role es "<str>" (shape() no conoce
# "<admin|member>"); el dominio admin|member se valida con value() en el escenario.
HOME_ITEM = {"home_id": "<id>", "name": "<str>", "role": "<str>", "is_default": "<bool>",
             "is_personal": "<bool>"}
HOME_DETAIL = {"id": "<id>", "name": "<str>", "timezone": "<str>", "is_personal": "<bool>",
               "created_at": "<ts>", "updated_at": "<ts>"}
MEMBERSHIP_ITEM = {"membership_id": "<id>", "app_user_id": "<id>", "name": "<str>",
                   "email": "<str>", "role": "<str>", "permissions": ["<str>"]}
# Contrato nuevo de 1.9 (§4.2): GET/PATCH /home/permission y GET /home/audit (plantillas
# aditivas PERMISSION_*/AUDIT_ITEM; kind nullable = sin home_member vinculado)
PERMISSION_CATALOG = {"code": "<str>", "domain": "<str>", "description": "<str>"}
PERMISSION_DEFAULT = {"kind": "<str>", "permissions": ["<str>"]}
PERMISSION_ITEM = {"membership_id": "<id>", "app_user_id": "<id>", "name": "<str>", "email": "<str>",
                   "role": "<str>", "kind": "<str?>", "editable": "<bool>", "permissions": ["<str>"]}
PERMISSION_GET = {"catalog": [PERMISSION_CATALOG], "defaults": [PERMISSION_DEFAULT],
                  "memberships": [PERMISSION_ITEM]}
PERMISSION_STATE = {"membership_id": "<id>", "home_id": "<id>", "permissions": ["<str>"],
                    "granted": ["<str>"], "revoked": ["<str>"]}
AUDIT_ITEM = {"id": "<id>", "action": "<str>", "target_type": "<str>", "target_id": "<int?>",
              "actor_app_user_id": "<int?>", "actor_name": "<str?>", "payload": "<obj>",
              "created_at": "<ts>"}
# Contrato nuevo de 1.6 (§3.4/§4): respuesta de /home/membership/* (CAL_USER/TL_USER con
# 'home_role' solo en GET; USER de add_*_user sin cambio, D-008)
MEMBERSHIP_STATE = {"membership_id": "<id>", "home_id": "<id>", "app_user_id": "<id>", "role": "<str>"}
TRANSFER_STATE = {"from_membership_id": "<id>", "to_membership_id": "<id>"}
# Contrato nuevo de 1.5 (§6.1): miembros del hogar (sin app_user_id ni email, §3.3)
HOME_MEMBER = {"id": "<id>", "home_id": "<id>", "kind": "<str>", "name": "<str>", "color": "<str>",
               "status": "<str>", "linked": "<bool>", "created_at": "<ts>", "updated_at": "<ts>"}
# Contrato nuevo de 1.15 (diseño §5.2): invitaciones. INVITATION_ITEM nunca lleva code ni
# code_hash; el código en claro solo sale en INVITATION_CREATED (una vez).
INVITATION_ITEM = {"id": "<id>", "home_id": "<id>", "kind": "<str>", "member_id": "<int?>",
                   "member_name": "<str?>", "status": "<str>", "expires_at": "<ts>",
                   "created_by": "<int?>", "created_at": "<ts>"}
INVITATION_CREATED = dict(INVITATION_ITEM, code="<str>")
INVITATION_ACCEPTED = {"home_id": "<id>", "membership_id": "<id>", "member_id": "<id>",
                       "role": "member", "kind": "<str>"}
SUCCESS = {"success": True}
CONFIG = {"allow_registration": "<bool>"}
ERR_INVALID_CREDS = '{"error":"Invalid credentials"}'
ERR_EMAIL_EXISTS = '{"error":"Email already exists"}'
ERR_SELF_REMOVE = '{"error":"User cannot remove themselves"}'
ERR_NOT_ALLOWED = '{"error":"Not Allowed"}'
ERR_NOT_FOUND = '{"error":"Not Found"}'
ERR_ALARM = '{"error":"Alarm must be nonnegative minutes or null"}'
ERR_NAME_REQUIRED = '{"error":"Name is required"}'
ERR_INVALID_TZ = '{"error":"Invalid timezone"}'
ERR_HOME_ID_REQUIRED = '{"error":"Home ID is required"}'
ERR_INVALID_HOME = '{"error":"Invalid home"}'
# 1.5 (/home/member/* y personas, §6.1)
ERR_INVALID_MEMBER = '{"error":"Invalid member"}'
ERR_MEMBER_ID_REQUIRED = '{"error":"Member ID is required"}'
ERR_PERSON_NAME_REQUIRED = '{"error":"Name is required (max 50 characters)"}'
ERR_COLOR_INVALID = '{"error":"Color must be #RRGGBB"}'
# 1.6 (/home/membership/*, §3.5/§4)
ERR_INVALID_ROLE = '{"error":"Invalid role"}'
ERR_INVALID_MEMBERSHIP = '{"error":"Invalid membership"}'
ERR_MEMBERSHIP_ID_REQUIRED = '{"error":"Membership ID is required"}'
# 1.9 (/home/permission, §4.3): código fuera del catálogo o shape de permissions inválido
ERR_INVALID_PERMISSION = '{"error":"Invalid permission"}'
# 1.15 (/home/invitation/*): membresía existente (sin consumir) y entrada vacía
ERR_ALREADY_MEMBER = '{"error":"Already member"}'
ERR_INVITATION_CODE_REQUIRED = '{"error":"Invitation code is required"}'
ERR_INVITATION_ID_REQUIRED = '{"error":"Invitation ID is required"}'
ERR_UNAUTHORIZED = '{"error":"Unauthorized"}'
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

# Rutas nuevas /home/* (1.4 §2 R1–R6; 1.5 §6.1 añade /home/member/*; 1.6 §4 añade
# /home/membership/*; 1.9 §4.1 añade /home/permission GET/PATCH y /home/audit; 1.15 añade
# /home/invitation*). ROUTES se mantiene en 43: "43/43" sigue siendo la métrica legacy
# (invariante D-008); la cobertura home se reporta aparte (19/19).
HOME_ROUTES = [
    "GET /home", "POST /home/create", "GET /home/detail", "PATCH /home/update",
    "PATCH /home/default", "GET /home/membership",
    "PATCH /home/membership/role", "POST /home/membership/transfer", "DELETE /home/membership",
    "GET /home/member", "POST /home/member/create", "PATCH /home/member/update",
    "GET /home/permission", "PATCH /home/permission", "GET /home/audit",
    "GET /home/invitation", "POST /home/invitation/create", "POST /home/invitation/accept",
    "POST /home/invitation/revoke",
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


def psql(sql):
    """SQL por psql local (variable PSQL: comando completo; default `psql`). Se usa para la
    membresía del bloque viewer y su limpieza (el REST service_role no altera los triggers
    diferidos de 0015)."""
    cmd = shlex.split(os.environ.get("PSQL", "psql"))
    r = subprocess.run(cmd + ["-X", "-q", "-v", "ON_ERROR_STOP=1", "-t", "-A"], input=sql,
                       capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit(f"psql falló ({r.returncode}): {r.stderr.strip()[:300]}")
    return r.stdout.strip()


def reset_leftovers():
    """Higiene entre ejecuciones: borra los restos con prefijo CC-% (escenarios y bloque viewer —
    la Edge no llega a borrar el calendario del viewer: 403) y XT-% (restos del suite de aislamiento)
    para poder re-ejecutar sin re-sembrar, la membresía de viewer en hogares ajenos (CASCADE a
    membership_permission y ACL) para que el caso 403 del alta externa sea determinista (A-7), y el
    usuario de prueba cc-mem del bloque M (1.6): sus membresías, sus hogares (personal incluido) y
    su cuenta auth (se recrea en cada pasada; CASCADE a app_user).
    DELETE REST vía service_role contra el REST local derivado de --fn (local por el guard); padre
    basta (cascade); los eventos van antes que las rutinas (`event.routine_id` es set null).
    En psql (una transacción, 1.4 §7.1/RK7): los hogares NO personales CC-% del usuario demo
    (membresías primero; el trigger anti-admin diferido de 0015 no ve hogares borrados) y la
    restauración de default_home_id al hogar original de demo si quedó NULL (R1-04: la FK compuesta
    (default_home_id, id) → home_membership hace SET NULL al borrarse la membresía de un hogar CC-%
    tras un fallo entre H9 y H10, y la siguiente ejecución rompería al insertar la membresía del
    viewer). 1.5 (§8.4/R1-02): `delete from person` (CC-% por nombre y por hogar de prueba) va
    ANTES de `delete from home_member` — person_home_member_fk es ON DELETE RESTRICT (0015:35) y
    delete_person/PATCH status ya no borran person (baja soft); el trigger 0014c borra su
    home_member al borrar la person."""
    key = load_service_key()
    if not key:
        print("aviso: sin SUPABASE_SERVICE_ROLE_KEY local: reset_leftovers omitido "
              "(la 2ª ejecución puede fallar por restos)")
        return
    rest = FN.split("/functions/")[0] + "/rest/v1"
    for prefix in ("CC-", "XT-"):
        for table, column in (("event", "title"), ("routine", "title"), ("task", "title"),
                              ("task_list", "name"), ("calendar", "name"), ("person", "name")):
            req = urllib.request.Request(f"{rest}/{table}?{column}=like.{prefix}*",
                                         method="DELETE",
                                         headers={"apikey": key, "Authorization": "Bearer " + key})
            try:
                urllib.request.urlopen(req).read()
            except urllib.error.HTTPError as e:
                print(f"aviso: reset_leftovers {table} falló ({e.code}): {e.read().decode()[:120]}")
    demo = args.email.replace("'", "''")
    viewer = "viewer@homita.example"
    mem = "cc-mem@homita.example"  # usuario de prueba del bloque M (1.6): cuenta/hogares/membresías
    psql(f"""
begin;
delete from membership_permission where home_membership_id in (
    select hm.id from home_membership hm
    where hm.home_id in (select id from home where name like 'CC-%'
                         and created_by = (select id from app_user where email = '{demo}'))
       or hm.app_user_id = (select id from app_user where email = '{mem}'));
delete from home_membership
    where home_id in (select id from home where name like 'CC-%'
                      and created_by = (select id from app_user where email = '{demo}'))
       or app_user_id = (select id from app_user where email = '{mem}')
       or (app_user_id = (select id from app_user where email = '{viewer}')
           and home_id in (select id from home
                           where created_by is distinct from (select id from app_user where email = '{viewer}')));
delete from person
    where name like 'CC-%'
       or home_id in (select id from home where name like 'CC-%'
                      and created_by = (select id from app_user where email = '{demo}'))
       or home_id in (select id from home
                      where created_by = (select id from app_user where email = '{mem}'));
delete from home_member
    where home_id in (select id from home where name like 'CC-%'
                      and created_by = (select id from app_user where email = '{demo}'))
       or home_id in (select id from home
                      where created_by = (select id from app_user where email = '{mem}'));
delete from audit_log
    where home_id in (select id from home where name like 'CC-%'
                      and created_by = (select id from app_user where email = '{demo}'))
       or home_id in (select id from home
                      where created_by = (select id from app_user where email = '{mem}'));
delete from home
    where (name like 'CC-%' and created_by = (select id from app_user where email = '{demo}'))
       or created_by = (select id from app_user where email = '{mem}');
-- Bloque 1.9 (cc-perm-*, hogares CC-Perm%): mismas tablas, cualquier creador (T16, higiene)
delete from membership_permission where home_membership_id in (
    select hm.id from home_membership hm
    where hm.home_id in (select id from home where name like 'CC-Perm%')
       or hm.app_user_id in (select id from app_user where email like 'cc-perm-%'));
delete from home_membership
    where home_id in (select id from home where name like 'CC-Perm%')
       or app_user_id in (select id from app_user where email like 'cc-perm-%');
delete from person
    where home_id in (select id from home where name like 'CC-Perm%')
       or home_id in (select id from home
                      where created_by in (select id from app_user where email like 'cc-perm-%'));
delete from home_member
    where home_id in (select id from home where name like 'CC-Perm%')
       or home_id in (select id from home
                      where created_by in (select id from app_user where email like 'cc-perm-%'))
       or app_user_id in (select id from app_user where email like 'cc-perm-%');
delete from audit_log
    where home_id in (select id from home where name like 'CC-Perm%')
       or home_id in (select id from home
                      where created_by in (select id from app_user where email like 'cc-perm-%'));
delete from home
    where name like 'CC-Perm%'
       or created_by in (select id from app_user where email like 'cc-perm-%');
delete from auth.users
    where id = (select auth_uid from app_user where email = '{mem}');
delete from auth.users where email like 'cc-perm-%';
-- Bloque 1.15 (cc-inv*): membresías, person/home_member de sus hogares (personales) y cuentas.
-- Sus filas en hogares CC-% del demo (CC-Membresias, CC-Inv-Arch) caen con los deletes de arriba;
-- home_invitation cae en cascada con el hogar (y con el home_member al que apunte).
delete from home_invitation
    where home_id in (select id from home
                      where created_by in (select id from app_user where email like 'cc-inv%'));
delete from membership_permission where home_membership_id in (
    select hm.id from home_membership hm
    where hm.app_user_id in (select id from app_user where email like 'cc-inv%')
       or hm.home_id in (select id from home
                         where created_by in (select id from app_user where email like 'cc-inv%')));
delete from home_membership
    where app_user_id in (select id from app_user where email like 'cc-inv%')
       or home_id in (select id from home
                      where created_by in (select id from app_user where email like 'cc-inv%'));
delete from person
    where user_id in (select id from app_user where email like 'cc-inv%')
       or home_id in (select id from home
                      where created_by in (select id from app_user where email like 'cc-inv%'));
delete from home_member
    where home_id in (select id from home
                      where created_by in (select id from app_user where email like 'cc-inv%'));
delete from audit_log
    where home_id in (select id from home
                      where created_by in (select id from app_user where email like 'cc-inv%'));
delete from home
    where created_by in (select id from app_user where email like 'cc-inv%');
delete from auth.users where email like 'cc-inv%';
update app_user u set default_home_id = coalesce(
    (select min(h.id) from home h where h.is_personal and h.created_by = u.id),
    (select min(hm.home_id) from home_membership hm where hm.app_user_id = u.id))
where u.email = '{demo}' and u.default_home_id is null;
commit;
""")


# ── Bloque 1.9 (configuración de permisos, plan §6.2 T15/T16): 39 casos ──
# Desglose: PX0–PX2 (3: altas, hogares+fixtures por psql, relogins), PG1–PG8 (8), PP1–PP15 (15),
# PA1–PA7 (7) y PK1–PK6 (6). Usuarios propios cc-perm-a/m/k/x y hogares CC-Perm/CC-Perm2 (X admin)
# para no interferir con los bloques legacy. Fixtures solo por psql (sin grants externos): A admin
# vinculado, M member adult con home.permissions.manage + home.members.manage, K member child con
# home.view y pet sin vínculo. Desviación 1.5 (D-011): PK4 (403 exacto + kind intacto) y PK6 (name
# o mismo kind sigue en 200: la desviación es estrecha).

PERMISOS_CASES = 39
PERM_ADULT = ['calendar.manage', 'calendar.view', 'event.assign', 'event.create', 'event.delete',
              'event.edit', 'routine.assign', 'routine.create', 'routine.delete', 'routine.edit',
              'routine.view', 'task.assign', 'task.complete', 'task.create', 'task.delete',
              'task.edit', 'task.view', 'tasklist.manage']
PERM_KIND_COUNTS = {'adult': 18, 'child': 6, 'guest': 3, 'relative': 10}
PERM_EMAIL = {'a': 'cc-perm-a@homita.example', 'm': 'cc-perm-m@homita.example',
              'k': 'cc-perm-k@homita.example', 'x': 'cc-perm-x@homita.example'}
PERM_PWD = 'ccperm1234'


def scenario_permisos_config():
    # PX0: altas de los 4 usuarios (registro abierto; V4 lo fija en la Edge local)
    oks = []
    for who, name in (('a', 'CC-Perm A'), ('m', 'CC-Perm M'), ('k', 'CC-Perm K'), ('x', 'CC-Perm X')):
        res = request("POST", "/user/create",
                      {"name": name, "email": PERM_EMAIL[who], "password": PERM_PWD})
        oks.append(res[0] in (200, 201))
    value("POST /user/create", "PX0 altas de cc-perm-a/m/k/x → 200/201", all(oks), repr(oks))

    # PX1: hogares CC-Perm/CC-Perm2 + fixtures por psql (snapshot por kind, manages a M). Home y
    # membresía admin en la misma sentencia (trigger anti-hogar-sin-admin diferido de 0015)
    uid = {w: int(psql(f"select id from app_user where email = '{PERM_EMAIL[w]}'")) for w in 'akmx'}
    row = psql("with h as (insert into home (name, created_by) values "
               f"('CC-Perm', {uid['a']}) returning id) "
               "insert into home_membership (home_id, app_user_id, role) "
               f"select h.id, {uid['a']}, 'admin' from h returning id, home_id")
    mid_a, hc = (int(x) for x in row.split('|'))
    row = psql("with h as (insert into home (name, created_by) values "
               f"('CC-Perm2', {uid['x']}) returning id) "
               "insert into home_membership (home_id, app_user_id, role) "
               f"select h.id, {uid['x']}, 'admin' from h returning id, home_id")
    mid_x, hc2 = (int(x) for x in row.split('|'))
    mid_m = int(psql("insert into home_membership (home_id, app_user_id, role) values "
                     f"({hc}, {uid['m']}, 'member') returning id"))
    mid_k = int(psql("insert into home_membership (home_id, app_user_id, role) values "
                     f"({hc}, {uid['k']}, 'member') returning id"))
    hmid_a = int(psql("insert into home_member (home_id, kind, name, color, app_user_id) values "
                      f"({hc}, 'adult', 'CC-Perm A', '#778899', {uid['a']}) returning id"))
    hmid_m = int(psql("insert into home_member (home_id, kind, name, color, app_user_id) values "
                      f"({hc}, 'adult', 'CC-Perm M', '#112233', {uid['m']}) returning id"))
    hmid_k = int(psql("insert into home_member (home_id, kind, name, color, app_user_id) values "
                      f"({hc}, 'child', 'CC-Perm K', '#445566', {uid['k']}) returning id"))
    hmid_pet = int(psql("insert into home_member (home_id, kind, name, color) values "
                        f"({hc}, 'adult', 'CC-Perm Pet', '#AABBCC') returning id"))
    # person emparejada 1:1 con cada home_member (invariante I5 de cross_tenant: sin home_member
    # huérfano de person; el bloque deja sus datos al terminar y V3 corre después de V2)
    psql(f"insert into person (user_id, home_id, home_member_id, name, color) values "
         f"({uid['a']}, {hc}, {hmid_a}, 'CC-Perm A', '#778899'), "
         f"({uid['a']}, {hc}, {hmid_m}, 'CC-Perm M', '#112233'), "
         f"({uid['a']}, {hc}, {hmid_k}, 'CC-Perm K', '#445566'), "
         f"({uid['a']}, {hc}, {hmid_pet}, 'CC-Perm Pet', '#AABBCC')")
    psql(f"select fn_seed_kind_permissions({mid_m}, 'adult'); "
         f"select fn_seed_kind_permissions({mid_k}, 'child')")
    psql(f"insert into membership_permission (home_membership_id, permission_code) values "
         f"({mid_m}, 'home.permissions.manage'), ({mid_m}, 'home.members.manage')")
    value("GET /home/permission",
          "PX1 CC-Perm/CC-Perm2 + fixtures psql (seed por kind, manages a M, pet sin vínculo)",
          min(hc, hc2, mid_a, mid_m, mid_k, mid_x, hmid_a, hmid_m, hmid_k, hmid_pet) > 0,
          f"hc={hc} hc2={hc2} mids={mid_a}/{mid_m}/{mid_k}/{mid_x}")

    # PX2: relogins de A/M/K/X
    toks = {}
    for w in 'akmx':
        res = request("POST", "/user/auth", {"email": PERM_EMAIL[w], "password": PERM_PWD})
        toks[w] = parse(res[1]).get("token") if res[0] == 200 else None
    value("POST /user/auth", "PX2 relogins de A/M/K/X → token no vacío", all(toks.values()),
          repr({k: bool(v) for k, v in toks.items()}))
    atok, mtok, ktok, xtok = toks['a'], toks['m'], toks['k'], toks['x']

    # PG1–PG3: GET admin → 200 PERMISSION_GET; catálogo 23, defaults 18/6/10/3 con home.view en
    # child/relative; fila admin editable=false/permissions=23 y fila member editable=true
    b = check("GET /home/permission", "PG1 GET /home/permission admin → 200 PERMISSION_GET",
              request("GET", f"/home/permission?home_id={hc}", None, atok), 200, PERMISSION_GET)
    cat = [c.get("code") for c in b.get("catalog", [])] if isinstance(b, dict) else []
    defs = ({d.get("kind"): d.get("permissions") for d in b.get("defaults", [])}
            if isinstance(b, dict) else {})
    counts = {k: len(v or []) for k, v in defs.items()}
    value("GET /home/permission",
          "PG2 catálogo 23 y defaults 18/6/10/3 con home.view en child/relative",
          len(cat) == 23 and counts == PERM_KIND_COUNTS
          and 'home.view' in (defs.get('child') or []) and 'home.view' in (defs.get('relative') or []),
          f"catalog={len(cat)} defaults={counts}")
    rows = {r.get("app_user_id"): r for r in b.get("memberships", [])} if isinstance(b, dict) else {}
    ra = rows.get(uid['a'], {})
    value("GET /home/permission",
          "PG3 admin editable=false/permissions=23 y member editable=true",
          ra.get("editable") is False and ra.get("permissions") == cat
          and len(ra.get("permissions") or []) == 23
          and rows.get(uid['m'], {}).get("editable") is True,
          repr(rows)[:300])

    # PG4–PG8: member con home.view 200 todo editable=false; sin home.view 403; no miembro 404;
    # sin home_id 400; cabecera X-Home-Id ajena 404
    res = request("GET", f"/home/permission?home_id={hc}", None, ktok)
    b4 = trace_norm(parse(res[1]))
    value("GET /home/permission", "PG4 member con home.view → 200 y todo editable=false",
          res[0] == 200 and isinstance(b4, dict) and b4.get("memberships")
          and all(r.get("editable") is False for r in b4.get("memberships", [])),
          f"status={res[0]} {res[1][:120]}")
    psql(f"delete from membership_permission where home_membership_id = {mid_k} "
         "and permission_code = 'home.view'")
    check("GET /home/permission", "PG5 member sin home.view → 403",
          request("GET", f"/home/permission?home_id={hc}", None, ktok), 403, ERR_NOT_ALLOWED)
    psql(f"select fn_seed_kind_permissions({mid_k}, 'child')")
    check("GET /home/permission", "PG6 no miembro (X) → 404",
          request("GET", f"/home/permission?home_id={hc}", None, xtok), 404, ERR_NOT_FOUND)
    check("GET /home/permission", "PG7 sin home_id → 400",
          request("GET", "/home/permission", None, atok), 400, ERR_HOME_ID_REQUIRED)
    check("GET /home/permission", "PG8 cabecera X-Home-Id ajena (CC-Perm2) → 404",
          request("GET", f"/home/permission?home_id={hc}", None, atok, home=hc2), 404, ERR_NOT_FOUND)

    # PP1–PP2: set con grant+revoke (granted/revoked exactos); reenvío idempotente = deltas vacíos
    s_m = PERM_ADULT + ['home.members.manage', 'home.permissions.manage']
    set1 = [c for c in s_m if c != 'calendar.manage'] + ['home.invite']
    res = request("PATCH", "/home/permission",
                  {"home_id": hc, "membership_id": mid_m, "permissions": set1}, atok)
    b1 = trace_norm(parse(res[1]))
    issues = []
    shape(b1, PERMISSION_STATE, "body", issues)
    value("PATCH /home/permission", "PP1 grant+revoke → 200 con granted/revoked exactos",
          res[0] == 200 and not issues and b1.get("granted") == ['home.invite']
          and b1.get("revoked") == ['calendar.manage'],
          f"status={res[0]} " + "\n     ".join(issues)[:300])
    res = request("PATCH", "/home/permission",
                  {"home_id": hc, "membership_id": mid_m, "permissions": set1}, atok)
    b2 = trace_norm(parse(res[1]))
    value("PATCH /home/permission", "PP2 idempotente → 200 granted=[] revoked=[]",
          res[0] == 200 and b2.get("granted") == [] and b2.get("revoked") == [],
          f"status={res[0]} {res[1][:120]}")

    # PP3: efecto observable — revocar home.view a K y GET /home/membership del member → 403
    child = defs.get('child') or []
    r1 = request("PATCH", "/home/permission",
                 {"home_id": hc, "membership_id": mid_k,
                  "permissions": [c for c in child if c != 'home.view']}, atok)
    r2 = request("GET", f"/home/membership?id={hc}", None, ktok)
    value("PATCH /home/permission",
          "PP3 revocar home.view → member GET /home/membership 403 (efecto observable)",
          r1[0] == 200 and r2[0] == 403 and trace_norm(r2[1]) == ERR_NOT_ALLOWED,
          f"patch={r1[0]} get={r2[0]} {r2[1][:80]}")
    psql(f"select fn_seed_kind_permissions({mid_k}, 'child')")

    # PP4–PP6: member con manage 403 (Q1); target admin 403 + 0 filas; membresía ajena 404
    check("PATCH /home/permission", "PP4 member con home.permissions.manage → 403 (Q1, sin escalada)",
          request("PATCH", "/home/permission",
                  {"home_id": hc, "membership_id": mid_k, "permissions": ['home.view']}, mtok),
          403, ERR_NOT_ALLOWED)
    res = request("PATCH", "/home/permission",
                  {"home_id": hc, "membership_id": mid_a, "permissions": []}, atok)
    n = psql(f"select count(*) from membership_permission where home_membership_id = {mid_a}")
    value("PATCH /home/permission", "PP5 target admin → 403 y 0 filas de snapshot",
          res[0] == 403 and trace_norm(res[1]) == ERR_NOT_ALLOWED and n == "0",
          f"status={res[0]} filas={n}")
    check("PATCH /home/permission", "PP6 membresía ajena (X en CC-Perm2) → 404",
          request("PATCH", "/home/permission",
                  {"home_id": hc, "membership_id": mid_x, "permissions": []}, atok),
          404, ERR_NOT_FOUND)

    # PP7–PP9: código fuera de catálogo 400 + snapshot intacto; permissions no array/ausente 400;
    # elemento no string 400
    before7 = psql(f"select coalesce(string_agg(permission_code, ',' order by permission_code), '') "
                   f"from membership_permission where home_membership_id = {mid_m}")
    res = request("PATCH", "/home/permission",
                  {"home_id": hc, "membership_id": mid_m, "permissions": ['no.existe']}, atok)
    after7 = psql(f"select coalesce(string_agg(permission_code, ',' order by permission_code), '') "
                  f"from membership_permission where home_membership_id = {mid_m}")
    value("PATCH /home/permission", "PP7 código fuera de catálogo → 400 y snapshot intacto",
          res[0] == 400 and trace_norm(res[1]) == ERR_INVALID_PERMISSION and before7 == after7,
          f"status={res[0]} snapshot={before7 == after7}")
    r1 = request("PATCH", "/home/permission",
                 {"home_id": hc, "membership_id": mid_m, "permissions": "home.view"}, atok)
    r2 = request("PATCH", "/home/permission", {"home_id": hc, "membership_id": mid_m}, atok)
    value("PATCH /home/permission", "PP8 permissions no array o ausente → 400",
          r1[0] == 400 and trace_norm(r1[1]) == ERR_INVALID_PERMISSION
          and r2[0] == 400 and trace_norm(r2[1]) == ERR_INVALID_PERMISSION,
          f"{r1[0]} {r1[1][:60]} / {r2[0]} {r2[1][:60]}")
    check("PATCH /home/permission", "PP9 elemento no string → 400",
          request("PATCH", "/home/permission",
                  {"home_id": hc, "membership_id": mid_m, "permissions": [123]}, atok),
          400, ERR_INVALID_PERMISSION)

    # PP10–PP12: sin home_id 400; sin membership_id 400; set [] → 200 (vaciado + restauración)
    check("PATCH /home/permission", "PP10 sin home_id → 400",
          request("PATCH", "/home/permission",
                  {"membership_id": mid_m, "permissions": []}, atok), 400, ERR_HOME_ID_REQUIRED)
    check("PATCH /home/permission", "PP11 sin membership_id → 400",
          request("PATCH", "/home/permission",
                  {"home_id": hc, "permissions": []}, atok), 400, ERR_MEMBERSHIP_ID_REQUIRED)
    check("PATCH /home/permission", "PP12 permissions [] → 200 PERMISSION_STATE",
          request("PATCH", "/home/permission",
                  {"home_id": hc, "membership_id": mid_m, "permissions": []}, atok),
          200, PERMISSION_STATE)
    psql(f"select fn_seed_kind_permissions({mid_m}, 'adult'); "
         f"insert into membership_permission (home_membership_id, permission_code) values "
         f"({mid_m}, 'home.permissions.manage'), ({mid_m}, 'home.members.manage')")

    # PP13: sin token → 401
    check("PATCH /home/permission", "PP13 sin token → 401",
          request("PATCH", "/home/permission",
                  {"home_id": hc, "membership_id": mid_m, "permissions": []}), 401, ERR_UNAUTHORIZED)

    # PP14–PP15: efecto observable de grant/revoke sobre la acción GET /home/permission (home.view)
    r0 = request("GET", f"/home/permission?home_id={hc}", None, mtok)
    r1 = request("PATCH", "/home/permission",
                 {"home_id": hc, "membership_id": mid_m, "permissions": sorted(s_m + ['home.view'])},
                 atok)
    r2 = request("GET", f"/home/permission?home_id={hc}", None, mtok)
    b1 = trace_norm(parse(r1[1]))
    value("PATCH /home/permission", "PP14 member recupera la acción tras grant (home.view)",
          r0[0] == 403 and r1[0] == 200 and b1.get("granted") == ['home.view'] and r2[0] == 200,
          f"pre={r0[0]} patch={r1[0]} post={r2[0]}")
    r3 = request("PATCH", "/home/permission",
                 {"home_id": hc, "membership_id": mid_m, "permissions": sorted(s_m)}, atok)
    r4 = request("GET", f"/home/permission?home_id={hc}", None, mtok)
    b3 = trace_norm(parse(r3[1]))
    value("PATCH /home/permission", "PP15 member pierde la acción tras revoke (home.view)",
          r3[0] == 200 and b3.get("revoked") == ['home.view'] and r4[0] == 403,
          f"patch={r3[0]} post={r4[0]}")

    # PA1–PA2: admin 200 [AUDIT_ITEM] con before/after en payload; PATCH idempotente = 0 filas
    res = request("GET", f"/home/audit?home_id={hc}", None, atok)
    body = trace_norm(parse(res[1]))
    issues = []
    shape(body, [AUDIT_ITEM], "body", issues)
    items = body if isinstance(body, list) else []
    value("GET /home/audit", "PA1 admin → 200 [AUDIT_ITEM] con before/after en payload",
          res[0] == 200 and not issues and items
          and all({'before', 'after'} <= set(i.get('payload') or {}) for i in items),
          f"status={res[0]} items={len(items)} " + "\n     ".join(issues)[:300])
    cur = psql(f"select coalesce(string_agg(permission_code, ',' order by permission_code), '') "
               f"from membership_permission where home_membership_id = {mid_m}")
    snap = psql(f"select count(*) from audit_log where home_id = {hc}")
    res = request("PATCH", "/home/permission",
                  {"home_id": hc, "membership_id": mid_m,
                   "permissions": cur.split(',') if cur else []}, atok)
    snap2 = psql(f"select count(*) from audit_log where home_id = {hc}")
    value("PATCH /home/permission", "PA2 PATCH idempotente = 0 filas nuevas en audit",
          res[0] == 200 and snap == snap2, f"audit {snap}→{snap2} status={res[0]}")

    # PA3–PA4: member 403; no miembro 404
    check("GET /home/audit", "PA3 member (M) → 403",
          request("GET", f"/home/audit?home_id={hc}", None, mtok), 403, ERR_NOT_ALLOWED)
    check("GET /home/audit", "PA4 no miembro (X) → 404",
          request("GET", f"/home/audit?home_id={hc}", None, xtok), 404, ERR_NOT_FOUND)

    # PA5: limit=1 + before_id → paginación por id sin repetir ni omitir
    full = trace_norm(parse(request("GET", f"/home/audit?home_id={hc}", None, atok)[1]))
    ids_full = [i.get("id") for i in full] if isinstance(full, list) else []
    walked, before = [], None
    while len(walked) <= len(ids_full):
        path = f"/home/audit?home_id={hc}&limit=1" + (f"&before_id={before}" if before else "")
        page = trace_norm(parse(request("GET", path, None, atok)[1]))
        if not isinstance(page, list) or not page:
            break
        walked.append(page[0].get("id"))
        before = page[0].get("id")
    value("GET /home/audit", "PA5 limit=1 + before_id: paginación por id sin repetir ni omitir",
          walked == ids_full and all(a > b for a, b in zip(walked, walked[1:])),
          f"paginas={len(walked)} total={len(ids_full)}")

    # PA6: admin de otro hogar → 404 en CC-Perm y sin filas ajenas en CC-Perm2
    r1 = request("GET", f"/home/audit?home_id={hc}", None, xtok)
    r2 = request("GET", f"/home/audit?home_id={hc2}", None, xtok)
    b2 = trace_norm(parse(r2[1]))
    value("GET /home/audit", "PA6 admin de otro hogar → 404 en CC-Perm y sin filas ajenas",
          r1[0] == 404 and trace_norm(r1[1]) == ERR_NOT_FOUND and r2[0] == 200
          and isinstance(b2, list)
          and not [i for i in b2 if i.get("target_id") in (mid_a, mid_m, mid_k)],
          f"r1={r1[0]} r2={r2[0]} items={len(b2) if isinstance(b2, list) else '?'}")

    # PA7 (R1-01): fila backfill.home.v1 en audit_log no se expone (filtro home.% incondicional)
    psql(f"insert into audit_log (home_id, actor_app_user_id, action, target_type, target_id, payload) "
         f"values ({hc}, null, 'backfill.home.v1', 'home', null, '{{\"counts\": 42}}')")
    n7 = psql(f"select count(*) from audit_log where home_id = {hc} and action like 'backfill.%'")
    res = request("GET", f"/home/audit?home_id={hc}", None, atok)
    body = trace_norm(parse(res[1]))
    leaked = ([i for i in body if str(i.get("action", "")).startswith("backfill.")]
              if isinstance(body, list) else ["?"])
    value("GET /home/audit", "PA7 fila backfill.home.v1 no se expone (filtro action like 'home.%')",
          n7 == "1" and res[0] == 200 and leaked == [],
          f"filas_backfill={n7} expuestas={len(leaked)}")

    # PK1–PK2: admin cambia kind de vinculado → snapshot = defaults del kind final (Q6) y
    # auditoría kind_change (grant+revoke con kind_from/kind_to)
    res = request("PATCH", "/home/member/update", {"id": hmid_k, "kind": "adult"}, atok)
    mb = trace_norm(parse(request("GET", f"/home/membership?id={hc}", None, atok)[1]))
    perms_k = (next((r.get("permissions") for r in mb
                     if isinstance(r, dict) and r.get("app_user_id") == uid['k']), None)
               if isinstance(mb, list) else None)
    value("PATCH /home/member/update",
          "PK1 cambio de kind (child→adult) → defaults de adult en GET /home/membership",
          res[0] == 200 and perms_k == PERM_ADULT, f"status={res[0]} perms={perms_k}")
    res = request("GET", f"/home/audit?home_id={hc}", None, atok)
    body = trace_norm(parse(res[1]))
    kc = [i for i in body if isinstance(i, dict)
          and (i.get("payload") or {}).get("source") == 'kind_change'
          and (i.get("payload") or {}).get("kind_from") == 'child'
          and (i.get("payload") or {}).get("kind_to") == 'adult']
    value("GET /home/audit", "PK2 audit del reset por kind_change (child→adult, grant+revoke)",
          res[0] == 200 and kc
          and {'home.permission.grant', 'home.permission.revoke'} <= {i.get("action") for i in kc},
          f"filas_kind_change={len(kc)}")

    # PK3: admin vinculado → kind cambia sin sembrar filas (A4, admin sin snapshot)
    res = request("PATCH", "/home/member/update", {"id": hmid_a, "kind": "child"}, atok)
    n = psql(f"select count(*) from membership_permission where home_membership_id = {mid_a}")
    value("PATCH /home/member/update", "PK3 admin vinculado: kind cambia sin sembrar filas (A4)",
          res[0] == 200 and n == "0", f"status={res[0]} filas={n}")

    # PK4 (D-011): no-admin con home.members.manage cambia kind de vinculado → 403 exacto, kind
    # intacto
    res = request("PATCH", "/home/member/update", {"id": hmid_k, "kind": "child"}, mtok)
    kind = psql(f"select kind from home_member where id = {hmid_k}")
    value("PATCH /home/member/update",
          "PK4 no-admin con manage cambia kind de vinculado → 403 exacto, kind intacto (D-011)",
          res[0] == 403 and trace_norm(res[1]) == ERR_NOT_ALLOWED and kind == "adult",
          f"status={res[0]} {res[1][:80]} kind={kind}")

    # PK5: sin vínculo (pet) → 200 sin reset ni audit (la desviación es solo para vinculados)
    n = psql(f"select count(*) from audit_log where home_id = {hc}")
    res = request("PATCH", "/home/member/update", {"id": hmid_pet, "kind": "child"}, mtok)
    n2 = psql(f"select count(*) from audit_log where home_id = {hc}")
    kind = psql(f"select kind from home_member where id = {hmid_pet}")
    value("PATCH /home/member/update", "PK5 no-admin con manage cambia kind de SIN vínculo → 200 sin audit",
          res[0] == 200 and kind == "child" and n == n2,
          f"status={res[0]} kind={kind} audit {n}→{n2}")

    # PK6 (D-011): no-admin con manage: name o mismo kind → 200 (desviación estrecha)
    r1 = request("PATCH", "/home/member/update", {"id": hmid_k, "name": "CC-Perm K2"}, mtok)
    r2 = request("PATCH", "/home/member/update", {"id": hmid_k, "kind": "adult"}, mtok)
    value("PATCH /home/member/update",
          "PK6 no-admin con manage: name o mismo kind → 200 (desviación estrecha)",
          r1[0] == 200 and r2[0] == 200, f"name={r1[0]} mismo_kind={r2[0]}")


# ── config, auth y reset ──

# Selector mínimo (T15): CONTRACT_ONLY=permisos ejecuta solo el bloque 1.9 (39 casos) tras el
# reset y sale; el resto de bloques no se toca (útil para carreras parciales del builder).
CONTRACT_ONLY = os.environ.get("CONTRACT_ONLY", "")
if CONTRACT_ONLY == "permisos":
    reset_leftovers()
    scenario_permisos_config()
    fails = results.count(False)
    print(f"\n{len(results) - fails}/{len(results)} casos ok · bloque 1.9 (CONTRACT_ONLY=permisos)")
    if regressed:
        print("Rutas con regresión: " + ", ".join(regressed))
    sys.exit(1 if fails or len(results) != PERMISOS_CASES else 0)

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
scenario_permisos_config()

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


def scenario_home():
    """Rutas /home/* (plan §7.1 H1–H18) + contexto X-Home-Id (R1-01: filtro positivo de listas y
    detalle con cabecera; R1-02: trim de name y timezone opcional). Hogar de prueba CC-Hogar y
    recursos CC-%: los limpia reset_leftovers() de la siguiente ejecución (que también restaura
    default_home_id, R1-04). Orden de validación id → name → timezone (§4.3): H7 lleva name para
    llegar a la validación de timezone."""
    # H1: índice de hogares (HOME_ITEM; role admin|member se valida como dominio, R1-03)
    b = check("GET /home", "H1 GET /home → [HOME_ITEM]",
              request("GET", "/home", None, tok), 200, [HOME_ITEM])
    value("GET /home", "H1 GET /home no vacío y roles admin|member",
          isinstance(b, list) and len(b) > 0
          and all(x.get("role") in ("admin", "member") for x in b), repr(b)[:300])
    orig_default = next((x["home_id"] for x in b if x.get("is_default")), None)
    # H2: alta con timezone por defecto (R1-02/A5: Europe/Madrid)
    b = check("POST /home/create", "H2 POST /home/create {CC-Hogar} → 201 HOME_DETAIL",
              request("POST", "/home/create", {"name": "CC-Hogar"}, tok), 201, HOME_DETAIL)
    h2 = b.get("id") if isinstance(b, dict) else None
    value("POST /home/create", "H2 is_personal=false y timezone por defecto Europe/Madrid",
          isinstance(b, dict) and b.get("is_personal") is False
          and b.get("timezone") == "Europe/Madrid", repr(b)[:300])
    # H3: validación de nombre (ausente, solo blancos — R1-02 — y timezone inválida en create)
    check("POST /home/create", "H3 POST /home/create sin name → 400 Name is required",
          request("POST", "/home/create", {}, tok), 400, ERR_NAME_REQUIRED)
    check("POST /home/create", "H3b POST /home/create name '   ' → 400 Name is required (R1-02)",
          request("POST", "/home/create", {"name": "   "}, tok), 400, ERR_NAME_REQUIRED)
    check("POST /home/create", "H3c POST /home/create timezone inválida → 400 Invalid timezone",
          request("POST", "/home/create", {"name": "CC-TZ-Mal", "timezone": "No/Zona"}, tok),
          400, ERR_INVALID_TZ)
    # H4–H5: detalle
    check("GET /home/detail", "H4 GET /home/detail?id=<H2> → 200 HOME_DETAIL",
          request("GET", f"/home/detail?id={h2}", None, tok), 200, HOME_DETAIL)
    check("GET /home/detail", "H5 GET /home/detail?id=999999 → 404 Not Found",
          request("GET", "/home/detail?id=999999", None, tok), 404, ERR_NOT_FOUND)
    # H6/H6b: update con timezone omitido/null conserva la zona (R1-02)
    b = check("PATCH /home/update", "H6 PATCH /home/update {CC-Hogar 2} sin timezone → 200",
              request("PATCH", "/home/update", {"id": h2, "name": "CC-Hogar 2"}, tok), 200, HOME_DETAIL)
    value("PATCH /home/update", "H6 nombre actualizado y timezone conservado",
          isinstance(b, dict) and b.get("name") == "CC-Hogar 2"
          and b.get("timezone") == "Europe/Madrid", repr(b)[:300])
    b = check("PATCH /home/update", "H6b PATCH /home/update timezone null → 200 (conserva zona)",
              request("PATCH", "/home/update", {"id": h2, "name": "CC-Hogar 2", "timezone": None}, tok),
              200, HOME_DETAIL)
    value("PATCH /home/update", "H6b timezone conservado con p_timezone null",
          isinstance(b, dict) and b.get("timezone") == "Europe/Madrid", repr(b)[:300])
    # H7–H8: validación (orden id → name → timezone)
    check("PATCH /home/update", "H7 PATCH /home/update timezone inválida → 400 Invalid timezone",
          request("PATCH", "/home/update", {"id": h2, "name": "x", "timezone": "No/Zona"}, tok),
          400, ERR_INVALID_TZ)
    check("PATCH /home/update", "H8 PATCH /home/update sin id → 400 Home ID is required",
          request("PATCH", "/home/update", {"name": "x"}, tok), 400, ERR_HOME_ID_REQUIRED)
    check("PATCH /home/update", "H8b PATCH /home/update name '   ' → 400 Name is required (R1-02)",
          request("PATCH", "/home/update", {"id": h2, "name": "   "}, tok), 400, ERR_NAME_REQUIRED)
    # H9–H11: hogar por defecto (H10 lo restaura; reset_leftovers cubre el fallo intermedio, R1-04)
    check("PATCH /home/default", "H9 PATCH /home/default {home_id:<H2>} → 200",
          request("PATCH", "/home/default", {"home_id": h2}, tok), 200, {"default_home_id": h2})
    check("PATCH /home/default", "H10 PATCH /home/default restaura el original → 200",
          request("PATCH", "/home/default", {"home_id": orig_default}, tok), 200,
          {"default_home_id": orig_default})
    check("PATCH /home/default", "H11 PATCH /home/default {home_id:999999} → 404 Not Found",
          request("PATCH", "/home/default", {"home_id": 999999}, tok), 404, ERR_NOT_FOUND)
    # H12–H13: membresías
    b = check("GET /home/membership", "H12 GET /home/membership?id=<H2> → [MEMBERSHIP_ITEM]",
              request("GET", f"/home/membership?id={h2}", None, tok), 200, [MEMBERSHIP_ITEM])
    value("GET /home/membership", "H12 1 fila role=admin con permissions no vacías",
          isinstance(b, list) and len(b) == 1 and b[0].get("role") == "admin"
          and isinstance(b[0].get("permissions"), list) and len(b[0]["permissions"]) > 0,
          repr(b)[:300])
    check("GET /home/membership", "H13 GET /home/membership?id=999999 → 404 Not Found",
          request("GET", "/home/membership?id=999999", None, tok), 404, ERR_NOT_FOUND)
    # H14–H15: cabecera de contexto en rutas legacy (§2.2: ajena → 500 legacy; mal formada → 400)
    check("GET /calendar", "H14 GET /calendar con X-Home-Id: 999999 → 500 Not Found (legacy)",
          request("GET", "/calendar", None, tok, home=999999), 500, ERR_NOT_FOUND)
    check("GET /home", "H14b GET /home con X-Home-Id: 999999 → 404 Not Found (home, D16)",
          request("GET", "/home", None, tok, home=999999), 404, ERR_NOT_FOUND)
    check("GET /calendar", "H15 GET /calendar con X-Home-Id: abc → 400 Invalid home",
          request("GET", "/calendar", None, tok, home="abc"), 400, ERR_INVALID_HOME)
    # H16: detalle con cabecera de otro hogar → filtro Edge (§4.4)
    check("GET /calendar/detail", "H16 GET /calendar/detail?id=1 con X-Home-Id: <H2> → 500 Not Found",
          request("GET", "/calendar/detail?id=1", None, tok, home=h2), 500, ERR_NOT_FOUND)
    # H17: S10 — la cabecera llega a SQL: el alta raíz usa el hogar activo
    b = check("POST /calendar/create", "H17 POST /calendar/create con X-Home-Id: <H2> → 201",
              request("POST", "/calendar/create", {"name": "CC-Cal-H2", "color": "#123456"}, tok, home=h2),
              201, CAL_DETAIL)
    h17cal = b.get("id") if isinstance(b, dict) else None
    value("POST /calendar/create", "H17 home_id = H2 (S10: la cabecera llega a SQL)",
          isinstance(b, dict) and b.get("home_id") == h2, repr(b)[:300])
    # H18: índice tras H10 (H2 presente y ya no es el default)
    b = check("GET /home", "H18 GET /home tras H10 → [HOME_ITEM]",
              request("GET", "/home", None, tok), 200, [HOME_ITEM])
    value("GET /home", "H18 H2 presente con is_default=false",
          isinstance(b, list)
          and any(x.get("home_id") == h2 and x.get("is_default") is False for x in b), repr(b)[:300])
    # H19–H20: filtro positivo de GET /calendar con cabecera válida (R1-01); vacía = sin cabecera
    b = check("GET /calendar", "H19 GET /calendar con X-Home-Id: <H2> → [CAL_ITEM]",
              request("GET", "/calendar", None, tok, home=h2), 200, [CAL_ITEM])
    value("GET /calendar", "H19 solo recursos de H2 (incluye el creado con cabecera)",
          isinstance(b, list) and len(b) >= 1
          and all(x.get("home_id") == h2 for x in b)
          and any(x.get("id") == h17cal for x in b), repr(b)[:300])
    b = check("GET /calendar", "H20 GET /calendar con X-Home-Id vacía = sin cabecera (A9)",
              request("GET", "/calendar", None, tok, home=""), 200, [CAL_ITEM])
    value("GET /calendar", "H20 sin cabecera → recursos de ambos hogares",
          isinstance(b, list)
          and any(x.get("home_id") == h2 for x in b)
          and any(x.get("home_id") == orig_default for x in b), repr(b)[:300])
    # H21–H23: ídem para /task-list (R1-01: filtro de lista y de detalle con cabecera)
    b = check("POST /task-list/create", "H21 POST /task-list/create con X-Home-Id: <H2> → 201",
              request("POST", "/task-list/create", {"name": "CC-Lista-H2", "color": "#222222"}, tok, home=h2),
              201, TL_DETAIL)
    h21list = b.get("id") if isinstance(b, dict) else None
    value("POST /task-list/create", "H21 home_id = H2 (S10)",
          isinstance(b, dict) and b.get("home_id") == h2, repr(b)[:300])
    b = check("GET /task-list", "H22 GET /task-list con X-Home-Id: <H2> → [TL_ITEM]",
              request("GET", "/task-list", None, tok, home=h2), 200, [TL_ITEM])
    value("GET /task-list", "H22 solo recursos de H2 (incluye la lista creada con cabecera)",
          isinstance(b, list) and len(b) >= 1
          and all(x.get("home_id") == h2 for x in b)
          and any(x.get("id") == h21list for x in b), repr(b)[:300])
    b = check("GET /task-list/detail", "H23 GET /task-list/detail con X-Home-Id: <H2> → 200",
              request("GET", f"/task-list/detail?id={h21list}", None, tok, home=h2), 200, TL_DETAIL)
    value("GET /task-list/detail", "H23 home_id = H2 en el detalle filtrado",
          isinstance(b, dict) and b.get("home_id") == h2, repr(b)[:300])
    check("GET /task-list/detail", "H24 GET /task-list/detail?id=1 con X-Home-Id: <H2> → 500",
          request("GET", "/task-list/detail?id=1", None, tok, home=h2), 500, ERR_NOT_FOUND)
    b = check("GET /task-list", "H25 GET /task-list sin cabecera → [TL_ITEM]",
              request("GET", "/task-list", None, tok), 200, [TL_ITEM])
    value("GET /task-list", "H25 sin cabecera → recursos de ambos hogares",
          isinstance(b, list)
          and any(x.get("home_id") == h2 for x in b)
          and any(x.get("home_id") == orig_default for x in b), repr(b)[:300])


scenario_profile()
scenario_person()
scenario_calendar()
scenario_task_list()
scenario_routine()
scenario_event()
scenario_home()


# ── Viewer (matriz de autorización): owner-only 403 y self-remove 400 (desviaciones) ──

B_EMAIL, B_PASSWORD, B_NAME = "viewer@homita.example", "viewer1234", "CC Viewer"

reg = request("POST", "/user/create", {"name": B_NAME, "email": B_EMAIL, "password": B_PASSWORD})
if reg == (400, ERR_EMAIL_EXISTS):  # usuario viewer de una ejecución previa
    check("POST /user/create", "viewer POST /user/create (ya registrado en una ejecución previa)",
          reg, 400, ERR_EMAIL_EXISTS)
    value("POST /user/create", "viewer POST /user/create (¿ALLOW_REGISTRATION=false o repetido?)",
          reg[0] == 400, repr(reg)[:300])
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

# Calendario y lista de A con B de viewer: el alta externa es 403 (Q3) mientras B no sea miembro
# del hogar del recurso (0014b/D-c); después se le da membresía por psql (snapshot legacy) y las
# invitaciones repiten en 200 (control positivo, A-7: 106 + 2 = 108)
b = check("POST /calendar/create", "viewer: owner crea CC-Viewer-Cal",
          request("POST", "/calendar/create", {"name": "CC-Viewer-Cal", "color": "#445566"}, tok),
          201, CAL_DETAIL)
vcal = b.get("id") if isinstance(b, dict) else None
check("POST /calendar/user", "owner invita al viewer (403: no miembro del hogar, Q3)",
      request("POST", "/calendar/user", {"calendar_id": vcal, "email": B_EMAIL}, tok),
      403, ERR_NOT_ALLOWED)
b = check("POST /task-list/create", "viewer: owner crea CC-Viewer-Lista",
          request("POST", "/task-list/create", {"name": "CC-Viewer-Lista", "color": "#445566"}, tok),
          201, TL_DETAIL)
vlist = b.get("id") if isinstance(b, dict) else None
check("POST /task-list/user", "owner invita al viewer (403: no miembro del hogar, Q3)",
      request("POST", "/task-list/user", {"task_list_id": vlist, "email": B_EMAIL}, tok),
      403, ERR_NOT_ALLOWED)

psql("insert into home_membership (home_id, app_user_id, role) "
     "select (select default_home_id from app_user where email = '" + args.email + "'), "
            "(select id from app_user where email = '" + B_EMAIL + "'), 'member' "
     "on conflict (home_id, app_user_id) do nothing")
check("POST /calendar/user", "owner invita al viewer (200 tras membresía, A-7)",
      request("POST", "/calendar/user", {"calendar_id": vcal, "email": B_EMAIL}, tok), 200, USER)
check("POST /task-list/user", "owner invita al viewer (200 tras membresía, A-7)",
      request("POST", "/task-list/user", {"task_list_id": vlist, "email": B_EMAIL}, tok), 200, USER)

# Matriz viewer del calendario (owner-only 403 y self-remove 400, desviaciones)
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

# Misma matriz con task-list: retirada de miembros
check("DELETE /task-list/user", "viewer DELETE /task-list/user saca al owner (403, desviación documentada)",
      request("DELETE", "/task-list/user", {"task_list_id": vlist, "user_id": aid}, vtok),
      403, ERR_NOT_ALLOWED)
check("DELETE /task-list/user", "self-remove DELETE /task-list/user (400)",
      request("DELETE", "/task-list/user", {"task_list_id": vlist, "user_id": vid}, vtok),
      400, ERR_SELF_REMOVE)
check("DELETE /task-list/delete", "owner borra la lista de prueba (DELETE /task-list/delete)",
      request("DELETE", "/task-list/delete", {"id": vlist}, tok), 200, SUCCESS)

# ── Miembros (1.5, plan §8.2 K1–K7, K9, K10, K13–K19, K22): /home/member/* y puente 0014 ──

def scenario_member():
    """Gestión de miembros sobre el hogar de prueba CC-Miembros (§8.2). El co-miembro es el
    viewer con el snapshot de `child` sembrado por psql (member_kind_default, sin
    home.members.manage): K6/K18. K7 y K19 corren ANTES de darle membresía (usuario de otro
    hogar). K15 vincula por psql (replica, §3.3) y prueba el 400 de `pet` vinculado. K13 fija
    `updated_at` en el pasado para verificar la guarda `is distinct from` (R1-01, determinista).
    Nombres con prefijo CC- (§8.4); los limpia reset_leftovers() (person antes que home_member).
    K22: las plantillas PERSON/HOME_MEMBER con claves exactas se aplican en cada check de este
    bloque (GET /person, POST /person/create, PATCH /person/update, /home/member/*)."""
    # K0 (setup): hogar de prueba
    b = check("POST /home/create", "K0 POST /home/create {CC-Miembros} → 201 HOME_DETAIL",
              request("POST", "/home/create", {"name": "CC-Miembros"}, tok), 201, HOME_DETAIL)
    hmem = b.get("id") if isinstance(b, dict) else None
    # K1: alta de miembro child sin cuenta; su person 1:1 aparece en GET /person (D12/I5)
    b = check("POST /home/member/create", "K1 create {child, CC-Miembro-Child} → 201 HOME_MEMBER",
              request("POST", "/home/member/create",
                      {"home_id": hmem, "kind": "child", "name": "CC-Miembro-Child", "color": "#A1B2C3"},
                      tok), 201, HOME_MEMBER)
    value("POST /home/member/create", "K1 linked=false, status=active, kind=child, home_id",
          isinstance(b, dict) and b.get("linked") is False and b.get("status") == "active"
          and b.get("kind") == "child" and b.get("home_id") == hmem, repr(b)[:300])
    m1 = b.get("id") if isinstance(b, dict) else None
    b = check("GET /person", "K1 GET /person lista la persona del miembro (home_member_id)",
              request("GET", "/person", None, tok), 200, [PERSON])
    p1 = next((x.get("id") for x in b if isinstance(x, dict) and x.get("home_member_id") == m1), None)
    value("GET /person", "K1 la persona nueva con home_member_id y kind=child",
          p1 is not None and any(x.get("id") == p1 and x.get("kind") == "child" for x in b),
          repr(b)[:300])
    # K2: pet sin cuenta — sin filas nuevas en home_membership ni membership_permission
    pre = psql("select (select count(*) from home_membership where home_id = %d) || ' ' || "
               "(select count(*) from membership_permission mp "
               " join home_membership hm on hm.id = mp.home_membership_id where hm.home_id = %d)"
               % (hmem, hmem))
    b = check("POST /home/member/create", "K2 create {pet, CC-Miembro-Pet} → 201",
              request("POST", "/home/member/create",
                      {"home_id": hmem, "kind": "pet", "name": "CC-Miembro-Pet", "color": "#B2C3D4"},
                      tok), 201, HOME_MEMBER)
    value("POST /home/member/create", "K2 pet con linked=false",
          isinstance(b, dict) and b.get("kind") == "pet" and b.get("linked") is False, repr(b)[:300])
    m2 = b.get("id") if isinstance(b, dict) else None
    post = psql("select (select count(*) from home_membership where home_id = %d) || ' ' || "
                "(select count(*) from membership_permission mp "
                " join home_membership hm on hm.id = mp.home_membership_id where hm.home_id = %d)"
                % (hmem, hmem))
    value("POST /home/member/create", "K2 sin filas nuevas en home_membership ni membership_permission",
          pre == post, f"antes={pre!r} después={post!r}")
    p2 = psql(f"select id from person where home_member_id = {m2}")
    # K3–K5: validación de entrada (la RPC es la fuente única: fn_validate_person_fields)
    check("POST /home/member/create", "K3 create kind robot → 400 Invalid member",
          request("POST", "/home/member/create",
                  {"home_id": hmem, "kind": "robot", "name": "CC-Miembro-Robot"}, tok),
          400, ERR_INVALID_MEMBER)
    check("POST /home/member/create", "K4 create name de 51 caracteres → 400 Name is required (max 50)",
          request("POST", "/home/member/create",
                  {"home_id": hmem, "kind": "adult", "name": "X" * 51}, tok),
          400, ERR_PERSON_NAME_REQUIRED)
    check("POST /home/member/create", "K4b create name '   ' → 400 Name is required (max 50)",
          request("POST", "/home/member/create",
                  {"home_id": hmem, "kind": "adult", "name": "   "}, tok),
          400, ERR_PERSON_NAME_REQUIRED)
    check("POST /home/member/create", "K5 create color 'red' → 400 Color must be #RRGGBB",
          request("POST", "/home/member/create",
                  {"home_id": hmem, "kind": "adult", "name": "CC-Miembro-Color", "color": "red"}, tok),
          400, ERR_COLOR_INVALID)
    # K7/K19: el viewer todavía NO es miembro de CC-Miembros (otro hogar) → 404 / 500 legacy
    check("GET /home/member", "K7 GET /home/member?home_id=<CC-Miembros> por no miembro → 404",
          request("GET", f"/home/member?home_id={hmem}", None, vtok), 404, ERR_NOT_FOUND)
    check("POST /home/member/create", "K7b create por no miembro → 404 (sin oráculo)",
          request("POST", "/home/member/create",
                  {"home_id": hmem, "kind": "adult", "name": "CC-Miembro-Ajeno"}, vtok),
          404, ERR_NOT_FOUND)
    check("PATCH /home/member/update", "K7c update de miembro ajeno por no miembro → 404",
          request("PATCH", "/home/member/update", {"id": m1, "name": "CC-Miembro-Ajeno"}, vtok),
          404, ERR_NOT_FOUND)
    check("PATCH /person/update", "K19 PATCH /person/update por usuario de otro hogar → 500 Not Found",
          request("PATCH", "/person/update", {"id": p1, "name": "CC-Ajeno", "color": "#111111"}, vtok),
          500, ERR_NOT_FOUND)
    # El viewer pasa a ser co-miembro de CC-Miembros con el snapshot de `child` (sin manage)
    psql("insert into home_membership (home_id, app_user_id, role) values (%d, %d, 'member') "
         "on conflict (home_id, app_user_id) do nothing; "
         "insert into membership_permission (home_membership_id, permission_code) "
         "select hm.id, mkd.permission_code from home_membership hm "
         "join member_kind_default mkd on mkd.kind = 'child' "
         "where hm.home_id = %d and hm.app_user_id = %d" % (hmem, vid, hmem, vid))
    # K6: miembro sin home.members.manage (snapshot child) → 403 en create/update
    check("POST /home/member/create", "K6 create por miembro sin home.members.manage → 403",
          request("POST", "/home/member/create",
                  {"home_id": hmem, "kind": "adult", "name": "CC-Miembro-Negado"}, vtok),
          403, ERR_NOT_ALLOWED)
    check("PATCH /home/member/update", "K6b update por miembro sin home.members.manage → 403",
          request("PATCH", "/home/member/update", {"id": m1, "name": "CC-Miembro-Negado"}, vtok),
          403, ERR_NOT_ALLOWED)
    # K9: edición de name/color (D12: person refleja el cambio)
    b = check("PATCH /home/member/update", "K9 PATCH name/color del miembro → 200 HOME_MEMBER",
              request("PATCH", "/home/member/update",
                      {"id": m1, "name": "CC-Miembro-Child 2", "color": "#112233"}, tok),
              200, HOME_MEMBER)
    value("PATCH /home/member/update", "K9 nombre/color nuevos y linked/status sin cambios",
          isinstance(b, dict) and b.get("name") == "CC-Miembro-Child 2" and b.get("color") == "#112233"
          and b.get("linked") is False and b.get("status") == "active", repr(b)[:300])
    b = check("GET /person", "K9 GET /person refleja el nombre nuevo (D12)",
              request("GET", "/person", None, tok), 200, [PERSON])
    value("GET /person", "K9 persona con nombre nuevo",
          isinstance(b, list) and any(x.get("id") == p1 and x.get("name") == "CC-Miembro-Child 2"
                                      for x in b), repr(b)[:300])
    # K10: baja soft conservando el histórico (evento con la persona asignada en CC-Miembros)
    b = check("POST /calendar/create", "K10 setup: calendario en CC-Miembros (X-Home-Id)",
              request("POST", "/calendar/create", {"name": "CC-Cal-Miembros", "color": "#222222"},
                      tok, home=hmem), 201, CAL_DETAIL)
    ccal = b.get("id") if isinstance(b, dict) else None
    b = check("POST /event/create", "K10 setup: evento con la persona asignada",
              request("POST", f"/event/create?timezone={tz}",
                      {"calendar_id": ccal, "title": "CC-Evento-Miembro",
                       "date_at": "2026-12-15 10:00:00", "person_ids": [p1]}, tok), 200, EVENT_DETAIL)
    e10 = b.get("id") if isinstance(b, dict) else None
    b = check("PATCH /home/member/update", "K10 PATCH status inactive → 200",
              request("PATCH", "/home/member/update", {"id": m1, "status": "inactive"}, tok),
              200, HOME_MEMBER)
    value("PATCH /home/member/update", "K10 status=inactive en la respuesta",
          isinstance(b, dict) and b.get("status") == "inactive", repr(b)[:300])
    b = check("GET /person", "K10 GET /person ya no lista la inactiva",
              request("GET", "/person", None, tok), 200, [PERSON])
    value("GET /person", "K10 persona oculta tras la baja (sin borrar filas)",
          isinstance(b, list) and all(x.get("id") != p1 for x in b), repr(b)[:300])
    b = check("GET /home/member", "K10 GET /home/member la lista con status inactive",
              request("GET", f"/home/member?home_id={hmem}", None, tok), 200, [HOME_MEMBER])
    value("GET /home/member", "K10 miembro con status=inactive",
          isinstance(b, list) and any(x.get("id") == m1 and x.get("status") == "inactive" for x in b),
          repr(b)[:300])
    b = check("GET /event/detail", "K10 GET /event/detail sigue mostrando la persona (histórico)",
              request("GET", f"/event/detail?id={e10}&timezone={tz}", None, tok), 200, EVENT_DETAIL)
    value("GET /event/detail", "K10 persona inactiva visible en el histórico",
          isinstance(b, dict) and any(p.get("id") == p1 for p in b.get("persons") or []), repr(b)[:300])
    # K13: idempotencia determinista (R1-01: updated_at solo si cambia; valor fijado en el pasado)
    psql("update home_member set updated_at = '2000-01-01 00:00:00' where id = %d; "
         "update person set updated_at = '2000-01-01 00:00:00' where id = %d" % (m1, p1))
    check("PATCH /home/member/update", "K13 PATCH status inactive sobre inactivo → 200 (sin cambios)",
          request("PATCH", "/home/member/update", {"id": m1, "status": "inactive"}, tok),
          200, HOME_MEMBER)
    b = check("GET /home/member", "K13 GET /home/member tras PATCH idempotente",
              request("GET", f"/home/member?home_id={hmem}", None, tok), 200, [HOME_MEMBER])
    value("GET /home/member", "K13 home_member.updated_at intacto (2000-01-01 00:00:00)",
          isinstance(b, list) and any(x.get("id") == m1 and x.get("status") == "inactive"
                                      and x.get("updated_at") == "2000-01-01 00:00:00" for x in b),
          repr(b)[:300])
    # K13b: PATCH con mismo name/color sobre miembro activo → person.updated_at intacto (K13)
    psql("update person set updated_at = '2000-01-01 00:00:00' where id = %s; "
         "update home_member set updated_at = '2000-01-01 00:00:00' where id = %s" % (p2, m2))
    check("PATCH /home/member/update", "K13b PATCH con mismo name/color → 200 (sin cambios)",
          request("PATCH", "/home/member/update",
                  {"id": m2, "name": "CC-Miembro-Pet", "color": "#B2C3D4"}, tok), 200, HOME_MEMBER)
    b = check("GET /person", "K13b GET /person tras PATCH sin cambios",
              request("GET", "/person", None, tok), 200, [PERSON])
    value("GET /person", "K13b person.updated_at intacto (2000-01-01 00:00:00)",
          isinstance(b, list) and any(x.get("id") == int(p2)
                                      and x.get("updated_at") == "2000-01-01 00:00:00" for x in b),
          repr(b)[:300])
    # K14: re-alta (§3.5) — mismo id, mismo person; vuelve a ser asignable
    b = check("PATCH /home/member/update", "K14 PATCH status active (re-alta) → 200",
              request("PATCH", "/home/member/update", {"id": m1, "status": "active"}, tok),
              200, HOME_MEMBER)
    value("PATCH /home/member/update", "K14 status=active",
          isinstance(b, dict) and b.get("status") == "active", repr(b)[:300])
    b = check("GET /person", "K14 GET /person vuelve a listarla",
              request("GET", "/person", None, tok), 200, [PERSON])
    value("GET /person", "K14 persona visible otra vez",
          isinstance(b, list) and any(x.get("id") == p1 for x in b), repr(b)[:300])
    check("POST /event/create", "K14 POST /event/create con la re-alta → 200",
          request("POST", f"/event/create?timezone={tz}",
                  {"calendar_id": ccal, "title": "CC-Evento-Realta",
                   "date_at": "2026-12-16 10:00:00", "person_ids": [p1]}, tok), 200, EVENT_DETAIL)
    # K15: vinculación por psql (replica, §3.3) + pet vinculado → Invalid member
    psql("set session_replication_role = replica; "
         "update home_member set app_user_id = %d where id = %d; "
         "set session_replication_role = default;" % (vid, m1))
    b = check("GET /home/member", "K15 GET /home/member → linked: true tras vincular por psql",
              request("GET", f"/home/member?home_id={hmem}", None, tok), 200, [HOME_MEMBER])
    value("GET /home/member", "K15 miembro vinculado con linked=true",
          isinstance(b, list) and any(x.get("id") == m1 and x.get("linked") is True for x in b),
          repr(b)[:300])
    check("PATCH /home/member/update", "K15 PATCH kind pet sobre vinculado → 400 Invalid member",
          request("PATCH", "/home/member/update", {"id": m1, "kind": "pet"}, tok), 400, ERR_INVALID_MEMBER)
    # K16: baja legacy DELETE /person/delete (soft + desasignación, Q1a) por el creador
    b = check("POST /home/member/create", "K16 setup: create {adult, CC-Miembro-K16} → 201",
              request("POST", "/home/member/create",
                      {"home_id": hmem, "kind": "adult", "name": "CC-Miembro-K16", "color": "#334455"},
                      tok), 201, HOME_MEMBER)
    m3 = b.get("id") if isinstance(b, dict) else None
    p3 = psql(f"select id from person where home_member_id = {m3}")
    check("POST /event/create", "K16 setup: evento con CC-Miembro-K16 asignada",
          request("POST", f"/event/create?timezone={tz}",
                  {"calendar_id": ccal, "title": "CC-Evento-K16",
                   "date_at": "2026-12-17 10:00:00", "person_ids": [int(p3)]}, tok), 200, EVENT_DETAIL)
    check("DELETE /person/delete", "K16 DELETE /person/delete por el creador → 200 success",
          request("DELETE", "/person/delete", {"id": int(p3)}, tok), 200, SUCCESS)
    row = psql("select (select status from home_member where id = %d) || ' ' || "
               "(select count(*) from person where id = %s) || ' ' || "
               "((select count(*) from event_person where person_id = %s) + "
               "(select count(*) from routine_person where person_id = %s))" % (m3, p3, p3, p3))
    value("DELETE /person/delete", "K16 home_member inactive, person existe, asignaciones borradas",
          row == "inactive 1 0", f"psql: {row!r}")
    b = check("GET /person", "K16 GET /person ya no la lista",
              request("GET", "/person", None, tok), 200, [PERSON])
    value("GET /person", "K16 persona oculta tras la baja legacy",
          isinstance(b, list) and all(x.get("id") != int(p3) for x in b), repr(b)[:300])
    # K17: PATCH /person/update por admin no creador → 200 (D15); la crea el viewer con cabecera
    b = check("POST /person/create", "K17 setup: viewer crea persona en CC-Miembros (X-Home-Id)",
              request("POST", "/person/create", {"name": "CC-Persona-Viewer", "color": "#445566"},
                      vtok, home=hmem), 200, PERSON)
    p17 = b.get("id") if isinstance(b, dict) else None
    b = check("PATCH /person/update", "K17 PATCH /person/update por admin no creador → 200 (D15)",
              request("PATCH", "/person/update",
                      {"id": p17, "name": "CC-Persona-Viewer 2", "color": "#556677"}, tok), 200, PERSON)
    value("PATCH /person/update", "K17 nombre nuevo editado por el admin no creador",
          isinstance(b, dict) and b.get("name") == "CC-Persona-Viewer 2", repr(b)[:300])
    # K18: PATCH /person/update por miembro child no creador → 403 (Q2a)
    check("PATCH /person/update", "K18 PATCH /person/update por miembro child no creador → 403",
          request("PATCH", "/person/update", {"id": p1, "name": "CC-Negado", "color": "#111111"}, vtok),
          403, ERR_NOT_ALLOWED)


scenario_member()


# ── Administradores (1.6, plan §6.2–6.3): /home/membership/* y C2 ──

MEM_EMAIL, MEM_PASSWORD, MEM_NAME = "cc-mem@homita.example", "ccmem1234", "CC Miembro"


def scenario_membership():
    """Bloque M (1.6, §6.2–6.3): /home/membership/* sobre el hogar de prueba CC-Membresias y el
    usuario cc-mem (su cuenta, hogares y membresías los borra reset_leftovers). El demo no abandona
    su hogar original: la salida feliz la hace el viewer (de su membresía en el hogar del demo) y
    los bloqueos de salida usan a cc-mem. Happy: promote/demote/transfer (+ vuelta)/salir; 400:
    role inválido, Invalid membership, ids faltantes; 403: no admin, último admin, owner único,
    último hogar; 404: no miembro, cabecera ajena, membresía ajena, hogar archived (A-5, psql).
    C2 (§6.2): 3 carreras A/B de demote en paralelo con dos admins → exactamente una 200 y una
    403 Not Allowed, admins = 1 (sin estados con 0 admins)."""
    # M0: setup — CC-Membresias (admin demo) + cc-mem (member por psql, como el viewer) con ids
    b = check("POST /home/create", "M0 POST /home/create {CC-Membresias} → 201 HOME_DETAIL",
              request("POST", "/home/create", {"name": "CC-Membresias"}, tok), 201, HOME_DETAIL)
    hM = b.get("id") if isinstance(b, dict) else None
    check("POST /user/create", "M0b POST /user/create cc-mem (registro abierto en la demo)",
          request("POST", "/user/create", {"name": MEM_NAME, "email": MEM_EMAIL,
                                           "password": MEM_PASSWORD}), 201, USER_CREATE)
    mauth = request("POST", "/user/auth", {"email": MEM_EMAIL, "password": MEM_PASSWORD})
    check("POST /user/auth", "M0c POST /user/auth cc-mem", mauth, 200, USER_AUTH)
    if mauth[0] != 200:
        sys.exit("no se pudo crear/autenticar cc-mem (¿ALLOW_REGISTRATION=true en la Edge?)")
    mtok = parse(mauth[1])["token"]
    mid = parse(mauth[1])["id"]
    psql("insert into home_membership (home_id, app_user_id, role) values (%d, %d, 'member') "
         "on conflict (home_id, app_user_id) do nothing" % (hM, mid))
    # 1.8 (§3.4.1): el enforcement de la matriz exige calendar.manage/tasklist.manage para
    # metadatos, borrar y compartir (M14b); el kind adult es el de la matriz con manage y se
    # siembra como fixture del bloque M (los casos sin manage van en el bloque de 1.8 abajo).
    psql("select fn_seed_kind_permissions((select id from home_membership where home_id = %d "
         "and app_user_id = %d), 'adult')" % (hM, mid))
    b = check("GET /home/membership", "M0d GET /home/membership?id=<CC-Membresias> → [MEMBERSHIP_ITEM]",
              request("GET", f"/home/membership?id={hM}", None, tok), 200, [MEMBERSHIP_ITEM])
    ids = {x.get("app_user_id"): x.get("membership_id") for x in b if isinstance(x, dict)}
    demo_m, mem_m = ids.get(aid), ids.get(mid)
    value("GET /home/membership", "M0e dos filas: demo admin y cc-mem member, con membership_id",
          isinstance(b, list) and len(b) == 2 and demo_m is not None and mem_m is not None
          and any(x.get("app_user_id") == aid and x.get("role") == "admin" for x in b)
          and any(x.get("app_user_id") == mid and x.get("role") == "member" for x in b),
          repr(b)[:300])
    # M1–M2: promote (borra snapshot) y demote (siembra legacy17, A-6) sobre la misma membresía
    b = check("PATCH /home/membership/role", "M1 promote cc-mem → 200 MEMBERSHIP_STATE",
              request("PATCH", "/home/membership/role",
                      {"home_id": hM, "membership_id": mem_m, "role": "admin"}, tok),
              200, MEMBERSHIP_STATE)
    value("PATCH /home/membership/role", "M1 role=admin con membership_id/home_id/app_user_id",
          isinstance(b, dict) and b.get("role") == "admin" and b.get("membership_id") == mem_m
          and b.get("home_id") == hM and b.get("app_user_id") == mid, repr(b)[:300])
    b = check("PATCH /home/membership/role", "M2 demote cc-mem → 200 MEMBERSHIP_STATE",
              request("PATCH", "/home/membership/role",
                      {"home_id": hM, "membership_id": mem_m, "role": "member"}, tok),
              200, MEMBERSHIP_STATE)
    value("PATCH /home/membership/role", "M2 role=member",
          isinstance(b, dict) and b.get("role") == "member", repr(b)[:300])
    # M3–M4: transfer atómica demo→cc-mem y vuelta cc-mem→demo (el caller queda member)
    b = check("POST /home/membership/transfer", "M3 transfer demo→cc-mem → 200 TRANSFER_STATE",
              request("POST", "/home/membership/transfer",
                      {"home_id": hM, "to_membership_id": mem_m}, tok), 200, TRANSFER_STATE)
    value("POST /home/membership/transfer", "M3 from=demo_m to=cc-mem_m",
          isinstance(b, dict) and b.get("from_membership_id") == demo_m
          and b.get("to_membership_id") == mem_m, repr(b)[:300])
    b = check("GET /home/membership", "M3 GET /home/membership tras transfer → [MEMBERSHIP_ITEM]",
              request("GET", f"/home/membership?id={hM}", None, tok), 200, [MEMBERSHIP_ITEM])
    value("GET /home/membership", "M3 cc-mem admin y demo member",
          isinstance(b, list)
          and any(x.get("app_user_id") == mid and x.get("role") == "admin" for x in b)
          and any(x.get("app_user_id") == aid and x.get("role") == "member" for x in b),
          repr(b)[:300])
    check("POST /home/membership/transfer", "M4 transfer cc-mem→demo (vuelta) → 200 TRANSFER_STATE",
          request("POST", "/home/membership/transfer",
                  {"home_id": hM, "to_membership_id": demo_m}, mtok), 200, TRANSFER_STATE)
    b = check("GET /home/membership", "M4 GET /home/membership restaurado → [MEMBERSHIP_ITEM]",
              request("GET", f"/home/membership?id={hM}", None, tok), 200, [MEMBERSHIP_ITEM])
    value("GET /home/membership", "M4 demo admin y cc-mem member otra vez",
          isinstance(b, list)
          and any(x.get("app_user_id") == aid and x.get("role") == "admin" for x in b)
          and any(x.get("app_user_id") == mid and x.get("role") == "member" for x in b),
          repr(b)[:300])
    # M6–M11: 400 de la Edge (role inválido, Invalid membership, ids faltantes)
    check("PATCH /home/membership/role", "M6 role 'owner' → 400 Invalid role",
          request("PATCH", "/home/membership/role",
                  {"home_id": hM, "membership_id": mem_m, "role": "owner"}, tok), 400, ERR_INVALID_ROLE)
    check("PATCH /home/membership/role", "M6b role no-string → 400 Invalid role",
          request("PATCH", "/home/membership/role",
                  {"home_id": hM, "membership_id": mem_m, "role": 123}, tok), 400, ERR_INVALID_ROLE)
    check("POST /home/membership/transfer", "M7 transfer a la propia membresía → 400 Invalid membership",
          request("POST", "/home/membership/transfer",
                  {"home_id": hM, "to_membership_id": demo_m}, tok), 400, ERR_INVALID_MEMBERSHIP)
    check("PATCH /home/membership/role", "M8 role sin membership_id → 400 Membership ID is required",
          request("PATCH", "/home/membership/role", {"home_id": hM, "role": "member"}, tok),
          400, ERR_MEMBERSHIP_ID_REQUIRED)
    check("POST /home/membership/transfer",
          "M9 transfer sin to_membership_id → 400 Membership ID is required",
          request("POST", "/home/membership/transfer", {"home_id": hM}, tok),
          400, ERR_MEMBERSHIP_ID_REQUIRED)
    check("DELETE /home/membership", "M10 DELETE sin membership_id → 400 Membership ID is required",
          request("DELETE", "/home/membership", {"home_id": hM}, tok),
          400, ERR_MEMBERSHIP_ID_REQUIRED)
    check("PATCH /home/membership/role", "M11 role sin home_id → 400 Home ID is required",
          request("PATCH", "/home/membership/role", {"membership_id": mem_m, "role": "member"}, tok),
          400, ERR_HOME_ID_REQUIRED)
    # M12: 403 no admin — cc-mem (member) en las 3 rutas
    check("PATCH /home/membership/role", "M12 member degrada a un admin → 403 Not Allowed",
          request("PATCH", "/home/membership/role",
                  {"home_id": hM, "membership_id": demo_m, "role": "member"}, mtok),
          403, ERR_NOT_ALLOWED)
    check("POST /home/membership/transfer", "M12b member transfiere la administración → 403 Not Allowed",
          request("POST", "/home/membership/transfer",
                  {"home_id": hM, "to_membership_id": demo_m}, mtok), 403, ERR_NOT_ALLOWED)
    check("DELETE /home/membership", "M12c member expulsa a otro → 403 Not Allowed",
          request("DELETE", "/home/membership", {"home_id": hM, "membership_id": demo_m}, mtok),
          403, ERR_NOT_ALLOWED)
    # M13: 403 último admin — demo es el único admin de CC-Membresias
    check("PATCH /home/membership/role", "M13 último admin se degrada a sí mismo → 403 Not Allowed",
          request("PATCH", "/home/membership/role",
                  {"home_id": hM, "membership_id": demo_m, "role": "member"}, tok), 403, ERR_NOT_ALLOWED)
    check("DELETE /home/membership", "M13b último admin sale → 403 Not Allowed",
          request("DELETE", "/home/membership", {"home_id": hM, "membership_id": demo_m}, tok),
          403, ERR_NOT_ALLOWED)
    # M14: 403 owner único — cc-mem es owner único de un calendario de CC-Membresias y no puede
    # salir hasta transferir la propiedad (§3.3); lo borra y el bloqueo desaparece
    # 1.8 (§3.4.1): el dance promote/demote de arriba dejó a cc-mem con legacy17 (promote borra el
    # snapshot A-6; demote siembra legacy17, sin calendar.manage). M14b exige owner + manage para
    # borrar: se siembra adult como fixture del bloque M (los casos sin manage van en el bloque de
    # 1.8; desviación documentada en el envelope).
    psql("select fn_seed_kind_permissions(%d, 'adult')" % mem_m)
    b = check("POST /calendar/create", "M14 setup: cc-mem crea CC-M-Cal en CC-Membresias (X-Home-Id)",
              request("POST", "/calendar/create", {"name": "CC-M-Cal", "color": "#123456"}, mtok, home=hM),
              201, CAL_DETAIL)
    m14cal = b.get("id") if isinstance(b, dict) else None
    check("DELETE /home/membership", "M14 owner único de un calendario sale → 403 Not Allowed",
          request("DELETE", "/home/membership", {"home_id": hM, "membership_id": mem_m}, mtok),
          403, ERR_NOT_ALLOWED)
    check("DELETE /calendar/delete", "M14b cc-mem borra su calendario (owner) → 200 success",
          request("DELETE", "/calendar/delete", {"id": m14cal}, mtok), 200, SUCCESS)
    # M15: 403 último hogar — a cc-mem se le borra su hogar personal (psql: home_membership.home_id
    # no cascades, membresía antes que hogar; el trigger anti-admin ve el hogar borrado y no
    # bloquea): CC-Membresias queda siendo su único hogar active y la salida se bloquea (D13)
    cc_home = int(psql("select default_home_id from app_user where id = %d" % mid))
    psql("begin; "
         "delete from membership_permission where home_membership_id in "
         "(select id from home_membership where home_id = %d); "
         "delete from home_membership where home_id = %d; "
         "delete from audit_log where home_id = %d; "
         "delete from home where id = %d; "
         "commit;" % (cc_home, cc_home, cc_home, cc_home))
    check("DELETE /home/membership", "M15 último hogar (cc-mem solo vive en CC-Membresias) → 403",
          request("DELETE", "/home/membership", {"home_id": hM, "membership_id": mem_m}, mtok),
          403, ERR_NOT_ALLOWED)
    # M5: salir (cualquier miembro, §4.1) — el viewer abandona su membresía en el hogar original
    # del demo (el demo no lo abandona en ningún escenario, §6.3)
    orig_home = int(psql("select default_home_id from app_user where id = %d" % aid))
    viewer_m = int(psql("select id from home_membership where home_id = %d and app_user_id = %d"
                        % (orig_home, vid)))
    check("DELETE /home/membership", "M5 viewer sale del hogar del demo → 200 success",
          request("DELETE", "/home/membership",
                  {"home_id": orig_home, "membership_id": viewer_m}, vtok), 200, SUCCESS)
    b = check("GET /home/membership", "M5b GET /home/membership tras la salida → [MEMBERSHIP_ITEM]",
              request("GET", f"/home/membership?id={orig_home}", None, tok), 200, [MEMBERSHIP_ITEM])
    value("GET /home/membership", "M5b la membresía del viewer ya no aparece",
          isinstance(b, list) and all(x.get("app_user_id") != vid for x in b), repr(b)[:300])
    # M16: 404 no miembro — el viewer no es miembro de CC-Membresias (guard fn_require_member)
    check("PATCH /home/membership/role", "M16 role por no miembro → 404 Not Found",
          request("PATCH", "/home/membership/role",
                  {"home_id": hM, "membership_id": mem_m, "role": "member"}, vtok), 404, ERR_NOT_FOUND)
    check("POST /home/membership/transfer", "M16b transfer por no miembro → 404 Not Found",
          request("POST", "/home/membership/transfer",
                  {"home_id": hM, "to_membership_id": mem_m}, vtok), 404, ERR_NOT_FOUND)
    check("DELETE /home/membership", "M16c DELETE por no miembro → 404 Not Found",
          request("DELETE", "/home/membership", {"home_id": hM, "membership_id": mem_m}, vtok),
          404, ERR_NOT_FOUND)
    # M17: 404 cabecera ajena — X-Home-Id del hogar original ≠ home_id del body (demo es miembro
    # de ambos: pasa el guard de la Edge y falla fn_home_mutation_guard de la RPC)
    for route, name, method, path, body in [
        ("PATCH /home/membership/role", "M17 role", "PATCH", "/home/membership/role",
         {"home_id": hM, "membership_id": mem_m, "role": "member"}),
        ("POST /home/membership/transfer", "M17b transfer", "POST", "/home/membership/transfer",
         {"home_id": hM, "to_membership_id": mem_m}),
        ("DELETE /home/membership", "M17c DELETE", "DELETE", "/home/membership",
         {"home_id": hM, "membership_id": mem_m}),
    ]:
        check(route, name + " con X-Home-Id ajena → 404 Not Found",
              request(method, path, body, tok, home=orig_home), 404, ERR_NOT_FOUND)
    # M18: 404 membresía ajena — membership_id de otro hogar (la del demo en su hogar original)
    other_m = int(psql("select id from home_membership where home_id = %d and app_user_id = %d"
                       % (orig_home, aid)))
    check("PATCH /home/membership/role", "M18 role con membership de otro hogar → 404 Not Found",
          request("PATCH", "/home/membership/role",
                  {"home_id": hM, "membership_id": other_m, "role": "member"}, tok), 404, ERR_NOT_FOUND)
    check("POST /home/membership/transfer", "M18b transfer a membership de otro hogar → 404 Not Found",
          request("POST", "/home/membership/transfer",
                  {"home_id": hM, "to_membership_id": other_m}, tok), 404, ERR_NOT_FOUND)
    check("DELETE /home/membership", "M18c DELETE con membership de otro hogar → 404 Not Found",
          request("DELETE", "/home/membership", {"home_id": hM, "membership_id": other_m}, tok),
          404, ERR_NOT_FOUND)
    # M19: 404 hogar archived (A-5) — la API no crea archived: alta por psql con membresía del demo
    # (si el guard no filtrara archived, la operación tendría éxito y el caso fallaría)
    arch_h = int(psql("insert into home (name, status, is_personal, created_by) "
                      "values ('CC-M-Archived', 'archived', false, %d) returning id" % aid))
    arch_m = int(psql("insert into home_membership (home_id, app_user_id, role) "
                      "values (%d, %d, 'admin') returning id" % (arch_h, aid)))
    check("PATCH /home/membership/role", "M19 role sobre hogar archived → 404 Not Found",
          request("PATCH", "/home/membership/role",
                  {"home_id": arch_h, "membership_id": arch_m, "role": "member"}, tok),
          404, ERR_NOT_FOUND)
    check("POST /home/membership/transfer", "M19b transfer sobre hogar archived → 404 Not Found",
          request("POST", "/home/membership/transfer",
                  {"home_id": arch_h, "to_membership_id": arch_m}, tok), 404, ERR_NOT_FOUND)
    check("DELETE /home/membership", "M19c DELETE sobre hogar archived → 404 Not Found",
          request("DELETE", "/home/membership", {"home_id": arch_h, "membership_id": arch_m}, tok),
          404, ERR_NOT_FOUND)
    # C2 (§6.2): dos admins se degradan en paralelo (A demote B, B demote A) — la carrera HTTP no
    # es determinista pero el resultado sí: exactamente una 200 y una 403, admins = 1. ×3.
    check("PATCH /home/membership/role", "C2 setup: cc-mem vuelve a admin (dos admins)",
          request("PATCH", "/home/membership/role",
                  {"home_id": hM, "membership_id": mem_m, "role": "admin"}, tok), 200, MEMBERSHIP_STATE)
    for i in (1, 2, 3):
        res = {}

        def demote(who, token, membership):
            res[who] = request("PATCH", "/home/membership/role",
                               {"home_id": hM, "membership_id": membership, "role": "member"}, token)

        threads = [threading.Thread(target=demote, args=("demo", tok, mem_m)),
                   threading.Thread(target=demote, args=("cc-mem", mtok, demo_m))]
        for t in threads:
            t.start()
        for t in threads:
            t.join()
        pair = sorted((res["demo"], res["cc-mem"]), key=lambda r: r[0])
        value("PATCH /home/membership/role",
              f"C2.{i} carrera A/B en paralelo: exactamente una 200 y una 403 Not Allowed",
              [r[0] for r in pair] == [200, 403] and pair[1][1] == ERR_NOT_ALLOWED, repr(res)[:300])
        b = check("GET /home/membership", f"C2.{i} GET /home/membership → [MEMBERSHIP_ITEM]",
                  request("GET", f"/home/membership?id={hM}", None, tok), 200, [MEMBERSHIP_ITEM])
        admins = [x for x in b if isinstance(x, dict) and x.get("role") == "admin"]
        value("GET /home/membership", f"C2.{i} admins = 1 (sin estados con 0 admins)",
              len(admins) == 1, repr(b)[:300])
        if i < 3:  # restaurar dos admins para la siguiente carrera
            surv = admins[0].get("app_user_id") if admins else None
            check("PATCH /home/membership/role",
                  f"C2.{i} el admin sobreviviente repromueve al degradado",
                  request("PATCH", "/home/membership/role",
                          {"home_id": hM, "membership_id": demo_m if surv == mid else mem_m,
                           "role": "admin"}, tok if surv == aid else mtok), 200, MEMBERSHIP_STATE)
    return hM, mem_m, demo_m, mid


hM, mem_m, demo_m, mid = scenario_membership()


# ── Permisos por kind (1.7, plan §6.2): fn_seed_kind_permissions por psql → GET /home/membership ──
# Sin rutas nuevas (D-008): el snapshot por kind se siembra con el helper de 0019 (sin grants
# externos: solo psql) y se observa en `permissions` de GET /home/membership (0016, collate "C").
# C2 deja exactamente un admin sin determinar cuál: se normaliza a demo=admin y cc-mem=member
# (R1-02: el helper rechaza admins) satisfaciendo el trigger anti-admin de 0015 (demo primero).

PERMS_CHILD = ['calendar.view', 'home.view', 'routine.view', 'task.complete', 'task.create',
               'task.view']
PERMS_ADULT = ['calendar.manage', 'calendar.view', 'event.assign', 'event.create', 'event.delete',
               'event.edit', 'routine.assign', 'routine.create', 'routine.delete', 'routine.edit',
               'routine.view', 'task.assign', 'task.complete', 'task.create', 'task.delete',
               'task.edit', 'task.view', 'tasklist.manage']
PERMS_CATALOG = ['calendar.manage', 'calendar.view', 'event.assign', 'event.create',
                 'event.delete', 'event.edit', 'home.invite', 'home.members.manage',
                 'home.permissions.manage', 'home.settings.manage', 'home.view', 'routine.assign',
                 'routine.create', 'routine.delete', 'routine.edit', 'routine.view', 'task.assign',
                 'task.complete', 'task.create', 'task.delete', 'task.edit', 'task.view',
                 'tasklist.manage']


def scenario_permisos_kind(hM, mem_m, demo_m, mid):
    # C2 deja exactamente un admin sin determinar cuál: se normaliza a demo=admin y cc-mem=member
    # (R1-02: el helper rechaza admins) satisfaciendo el trigger anti-admin de 0015 (demo primero).
    # La normalización imita el promote de 0018 (A-6): además del rol borra el snapshot — el update
    # crudo de psql no lo haría y dejaría un admin con las 17 filas legacy17 que sembró el demote
    # de C2 (estado que A4 prohíbe y que K6 detecta; el resultado de C2 es no-determinista).
    psql("begin; "
         "update home_membership set role = 'admin' where id = %d; "
         "delete from membership_permission where home_membership_id = %d; "
         "update home_membership set role = 'member' where id = %d; "
         "commit;" % (demo_m, demo_m, mem_m))
    # K1–K3: seed child (reemplaza el snapshot de cc-mem) → 6 claves de child (collate "C") y el
    # admin (demo) sigue con el catálogo entero (A4, sin filas)
    psql("select fn_seed_kind_permissions(%d, 'child')" % mem_m)
    b = check("GET /home/membership", "K1 seed child → GET /home/membership → [MEMBERSHIP_ITEM]",
              request("GET", f"/home/membership?id={hM}", None, tok), 200, [MEMBERSHIP_ITEM])
    value("GET /home/membership", 'K2 permissions de cc-mem = 6 claves de child (collate "C")',
          next((x.get("permissions") for x in b
                if isinstance(x, dict) and x.get("app_user_id") == mid), None) == PERMS_CHILD,
          repr(b)[:300])
    value("GET /home/membership", "K3 admin (demo) = 23 del catálogo (A4, sin snapshot)",
          next((x.get("permissions") for x in b
                if isinstance(x, dict) and x.get("app_user_id") == aid), None) == PERMS_CATALOG,
          repr(b)[:300])
    # K4–K5: seed adult reemplaza child → 18 claves de adult (reemplaza, no suma)
    psql("select fn_seed_kind_permissions(%d, 'adult')" % mem_m)
    b = check("GET /home/membership", "K4 seed adult reemplaza child → [MEMBERSHIP_ITEM]",
              request("GET", f"/home/membership?id={hM}", None, tok), 200, [MEMBERSHIP_ITEM])
    value("GET /home/membership", 'K5 permissions de cc-mem = 18 claves de adult (collate "C")',
          next((x.get("permissions") for x in b
                if isinstance(x, dict) and x.get("app_user_id") == mid), None) == PERMS_ADULT,
          repr(b)[:300])
    # K6: R1-02 — el helper rechaza la membresía admin de demo ('Not Allowed' 42501) y A4 aguanta:
    # el admin sigue con 0 filas en membership_permission (si el helper no fallara, psql abortaría)
    out = psql("do $$ begin "
               "perform fn_seed_kind_permissions(%d, 'guest'); "
               "raise exception 'el helper no rechazo a un admin'; "
               "exception when insufficient_privilege then "
               "if sqlerrm <> 'Not Allowed' then raise; end if; "
               "end $$; "
               "select count(*) from membership_permission mp "
               "join home_membership hm on hm.id = mp.home_membership_id where hm.role = 'admin';"
               % demo_m)
    value("GET /home/membership", "K6 el helper rechaza admin (Not Allowed) y admin = 0 filas (A4)",
          out == "0", repr(out)[:300])


scenario_permisos_kind(hM, mem_m, demo_m, mid)


# ── Matriz §3.4.1 (1.8, §4.1/§6.2): enforcement por kind sobre recursos de CC-Membresias ──
# Oracle = tabla §4.1 (sin rutas nuevas, D-008): admin sin ACL ve (widget/dashboard false) y no
# escribe; metadatos/borrar/compartir = owner + calendar.manage|tasklist.manage; contenido =
# ACL + permiso de la operación; *.assign solo si el conjunto de personas cambia (Q-C (a)).

ERR_PERSON_IDS = '{"error":"person_ids must be a list of IDs"}'
ERR_INVALID_PERSON = '{"error":"Invalid person"}'


def seed_kind(kind):
    psql("select fn_seed_kind_permissions(%d, '%s')" % (mem_m, kind))


def scenario_matriz(hM, mem_m, mid):
    mauth = request("POST", "/user/auth", {"email": MEM_EMAIL, "password": MEM_PASSWORD})
    check("POST /user/auth", "MX0 POST /user/auth cc-mem (relogin del bloque 1.8)", mauth, 200, USER_AUTH)
    if mauth[0] != 200:
        sys.exit("no se pudo reautenticar cc-mem para el bloque 1.8")
    mtok = parse(mauth[1])["token"]
    # viewer B se da de alta en CC-Membresias (kind guest) y se comparte CC-M-Cal con él
    psql("insert into home_membership (home_id, app_user_id, role) values (%d, %d, 'member') "
         "on conflict (home_id, app_user_id) do nothing" % (hM, vid))
    psql("select fn_seed_kind_permissions((select id from home_membership where home_id = %d "
         "and app_user_id = %d), 'guest')" % (hM, vid))
    seed_kind("adult")
    cal = check("POST /calendar/create", "MX1 cc-mem crea CC-M-Cal (owner adult)",
                request("POST", "/calendar/create", {"name": "CC-M-Cal", "color": "#112233"}, mtok),
                201, CAL_DETAIL).get("id")
    cal2 = check("POST /calendar/create", "MX2 cc-mem crea CC-M-Cal2 (sin compartir)",
                 request("POST", "/calendar/create", {"name": "CC-M-Cal2", "color": "#445566"}, mtok),
                 201, CAL_DETAIL).get("id")
    lst = check("POST /task-list/create", "MX3 cc-mem crea CC-M-Lista (owner adult)",
                request("POST", "/task-list/create", {"name": "CC-M-Lista", "color": "#778899",
                                                      "sort": "title"}, mtok), 201, TL_DETAIL).get("id")
    per = check("POST /person/create", "MX4 cc-mem crea CC-M-Persona (200 PHP, persons.ts:11)",
                request("POST", "/person/create", {"name": "CC-M-Persona", "color": "#AABBCC"}, mtok),
                200, PERSON).get("id")
    check("POST /calendar/user", "M13 owner + calendar.manage invita al viewer → 200 USER",
          request("POST", "/calendar/user", {"calendar_id": cal, "email": B_EMAIL}, mtok), 200, USER)

    # M1/M1b/M2: admin sin ACL ve y no escribe (Q1/A-5; detalle por PostgREST+RLS, A-15)
    b = check("GET /calendar", "M1 GET /calendar del admin → incluye CC-M-Cal (ACL de cc-mem)",
              request("GET", "/calendar", None, tok, home=hM), 200, [CAL_ITEM])
    item = next((x for x in b if isinstance(x, dict) and x.get("id") == cal), None) if isinstance(b, list) else None
    value("GET /calendar", "M1 CC-M-Cal con widget=0 y dashboard=0 (admin sin ACL, A-5)",
          isinstance(item, dict) and item.get("widget") == 0 and item.get("dashboard") == 0,
          repr(item)[:300])
    check("GET /calendar/detail", "M1b GET /calendar/detail del admin sin ACL → 200 (RLS, A-15)",
          request("GET", f"/calendar/detail?id={cal}", None, tok, home=hM), 200, CAL_DETAIL)
    check("PATCH /calendar/update", "M2 admin sin ACL rename → 500 Not Found",
          request("PATCH", "/calendar/update", {"id": cal, "name": "CC-M-Cal X", "color": "#112233"},
                  tok, home=hM), 500, ERR_NOT_FOUND)
    check("GET /calendar/detail", "M3 co-miembro sin ACL → 500 Not Found",
          request("GET", f"/calendar/detail?id={cal2}", None, vtok, home=hM), 500, ERR_NOT_FOUND)

    # M4/M5: metadatos = owner + manage; flags propios = solo ACL (§5.1)
    check("PATCH /calendar/update", "M4 owner adult rename → 200",
          request("PATCH", "/calendar/update", {"id": cal, "name": "CC-M-Cal", "color": "#112233"},
                  mtok, home=hM), 200, CAL_DETAIL)
    psql("delete from membership_permission where home_membership_id = %d "
         "and permission_code = 'calendar.manage'" % mem_m)
    check("PATCH /calendar/update", "M4b owner sin calendar.manage rename → 403",
          request("PATCH", "/calendar/update", {"id": cal, "name": "CC-M-Cal X", "color": "#112233"},
                  mtok, home=hM), 403, ERR_NOT_ALLOWED)
    seed_kind("adult")
    res = request("PATCH", "/calendar/update", {"id": cal, "name": "CC-M-Cal", "color": "#112233",
                                                "widget": False}, vtok, home=hM)
    check("PATCH /calendar/update", "M5 viewer solo flags propias → 200", res, 200, CAL_DETAIL)

    # M6–M8: contenido = ACL + permiso; *.assign solo si cambia el conjunto (Q-C (a))
    check("POST /event/create", "M6 guest sin event.create crea evento → 403",
          request("POST", "/event/create?timezone=Europe/Madrid",
                  {"calendar_id": cal, "title": "CC-M-EvG", "date_at": "2026-12-01 10:00:00",
                   "alarm": 5}, vtok, home=hM), 403, ERR_NOT_ALLOWED)
    seed_kind("relative")
    ev = check("POST /event/create", "M6b relative con event.create crea evento sin personas → 200",
               request("POST", "/event/create?timezone=Europe/Madrid",
                       {"calendar_id": cal, "title": "CC-M-EvR", "date_at": "2026-12-02 10:00:00",
                        "alarm": 5}, mtok, home=hM), 200, EVENT_DETAIL).get("id")
    check("POST /event/create", "M7 relative crea evento con personas (sin event.assign) → 403",
          request("POST", "/event/create?timezone=Europe/Madrid",
                  {"calendar_id": cal, "title": "CC-M-EvP", "date_at": "2026-12-03 10:00:00",
                   "alarm": 5, "person_ids": [per]}, mtok, home=hM), 403, ERR_NOT_ALLOWED)
    seed_kind("adult")
    evp = check("POST /event/create", "M7b adult crea evento con personas (event.assign) → 200",
                request("POST", "/event/create?timezone=Europe/Madrid",
                        {"calendar_id": cal, "title": "CC-M-EvA", "date_at": "2026-12-04 10:00:00",
                         "alarm": 5, "person_ids": [per]}, mtok, home=hM), 200, EVENT_DETAIL).get("id")
    seed_kind("relative")
    check("PATCH /event/update", "M8 relative reenvía el conjunto mostrado (sin cambio) → 200",
          request("PATCH", "/event/update?timezone=Europe/Madrid",
                  {"id": evp, "title": "CC-M-EvA", "date_at": "2026-12-04 10:00:00", "alarm": 5,
                   "person_ids": [per]}, mtok, home=hM), 200, EVENT_DETAIL)
    check("PATCH /event/update", "M8b relative quita una persona (cambia el conjunto) → 403",
          request("PATCH", "/event/update?timezone=Europe/Madrid",
                  {"id": evp, "title": "CC-M-EvA", "date_at": "2026-12-04 10:00:00", "alarm": 5,
                   "person_ids": []}, mtok, home=hM), 403, ERR_NOT_ALLOWED)
    check("DELETE /event/delete", "M10 relative borra evento (sin event.delete) → 403",
          request("DELETE", "/event/delete?timezone=Europe/Madrid", {"id": ev}, mtok, home=hM),
          403, ERR_NOT_ALLOWED)
    seed_kind("adult")
    check("DELETE /event/delete", "M10b adult borra evento → 200",
          request("DELETE", "/event/delete?timezone=Europe/Madrid", {"id": ev}, mtok, home=hM),
          200, SUCCESS)

    # M11: tareas por kind (child crea, no borra; guest completa pero no crea)
    seed_kind("child")
    check("POST /task-list/create", "M11 child crea task-list (Q2, miembro basta) → 201",
          request("POST", "/task-list/create", {"name": "CC-M-ListaK", "color": "#001122",
                                                "sort": "title"}, mtok, home=hM), 201, TL_DETAIL)
    tsk = check("POST /task/create", "M11b child crea tarea (task.create) → 201",
                request("POST", "/task/create", {"task_list_id": lst, "title": "CC-M-TareaK"}, mtok,
                        home=hM), 201, TASK_ITEM).get("id")
    check("PATCH /task-list/update", "M11c child renombra lista (sin tasklist.manage, S14) → 403",
          request("PATCH", "/task-list/update", {"id": lst, "name": "CC-M-Lista X", "color": "#778899",
                                                 "sort": "title"}, mtok, home=hM), 403, ERR_NOT_ALLOWED)
    check("DELETE /task/delete", "M11d child borra tarea (sin task.delete) → 403",
          request("DELETE", "/task/delete", {"id": tsk}, mtok, home=hM), 403, ERR_NOT_ALLOWED)
    seed_kind("guest")
    check("POST /task/create", "M11e guest crea tarea (sin task.create) → 403",
          request("POST", "/task/create", {"task_list_id": lst, "title": "CC-M-TareaG"}, mtok,
                  home=hM), 403, ERR_NOT_ALLOWED)
    check("PATCH /task/complete", "M11f guest completa tarea (task.complete) → 200",
          request("PATCH", "/task/complete", {"id": tsk, "completed": True}, mtok, home=hM),
          200, TASK_ITEM)

    # M12: sin ACL → Not Found (500 legacy) incluso con permisos
    seed_kind("adult")
    b = check("POST /task/create", "M12 setup: tarea en CC-M-Lista (adult)",
              request("POST", "/task/create", {"task_list_id": lst, "title": "CC-M-Tarea"}, mtok,
                      home=hM), 201, TASK_ITEM)
    tsk2 = b.get("id") if isinstance(b, dict) else None
    check("PATCH /task/complete", "M12 complete_task sin ACL → 500 Not Found",
          request("PATCH", "/task/complete", {"id": tsk2, "completed": True}, vtok, home=hM),
          500, ERR_NOT_FOUND)
    check("PATCH /task/order", "M12 task_order sin ACL → 500 Not Found",
          request("PATCH", "/task/order", {"id": tsk2, "position": 0}, vtok, home=hM),
          500, ERR_NOT_FOUND)
    ev2 = check("POST /event/create", "M12 setup: evento en CC-M-Cal2 (adult)",
                request("POST", "/event/create?timezone=Europe/Madrid",
                        {"calendar_id": cal2, "title": "CC-M-Ev2", "date_at": "2026-12-05 10:00:00",
                         "alarm": 5}, mtok, home=hM), 200, EVENT_DETAIL).get("id")
    check("PATCH /event/alarm", "M12 set_event_alarm sin ACL → 500 Not Found",
          request("PATCH", "/event/alarm?timezone=Europe/Madrid",
                  {"event_id": ev2, "alarm": 9}, vtok, home=hM), 500, ERR_NOT_FOUND)

    # M13/M14: compartir = owner + manage; Q3 no-miembro; último owner y self-remove (M14)
    reg = request("POST", "/user/create", {"name": "CC-M-Extra", "email": "cc-m-extra@homita.example",
                                           "password": "ccmextra1234"})
    value("POST /user/create", "MX5 alta del usuario externo de Q3 (registro abierto)", reg[0] in (201, 400),
          repr(reg)[:200])
    check("POST /calendar/user", "M13 email de no-miembro del hogar → 403 (Q3)",
          request("POST", "/calendar/user", {"calendar_id": cal2, "email": "cc-m-extra@homita.example"},
                  mtok, home=hM), 403, ERR_NOT_ALLOWED)
    psql("delete from membership_permission where home_membership_id = %d "
         "and permission_code = 'calendar.manage'" % mem_m)
    check("POST /calendar/user", "M13b owner sin calendar.manage invita → 403",
          request("POST", "/calendar/user", {"calendar_id": cal2, "email": B_EMAIL}, mtok, home=hM),
          403, ERR_NOT_ALLOWED)
    seed_kind("adult")
    check("DELETE /calendar/user", "M14 último owner se autoretira → 403 Not Allowed",
          request("DELETE", "/calendar/user", {"calendar_id": cal2, "user_id": mid}, mtok, home=hM),
          403, ERR_NOT_ALLOWED)
    psql("update calendar_user set role = 'owner' where calendar_id = %d and user_id = %d" % (cal, vid))
    check("DELETE /calendar/user", "M14b owner con reemplazo se autoretira → 400 self-remove",
          request("DELETE", "/calendar/user", {"calendar_id": cal, "user_id": mid}, mtok, home=hM),
          400, ERR_SELF_REMOVE)

    # M23 (HTTP): person_ids de persona de otro hogar → 400 Invalid person (pasada 2 por hogar;
    # la validación Edge de validate.ts solo rechaza listas malformadas, M22)
    foreign = int(psql("insert into home_member (home_id, kind, name, color, status, created_by) "
                       "values ((select default_home_id from app_user where email = '%s'), 'adult', "
                       "'CC-M-Ajena', '#FFEEDD', 'active', %d) returning id" % (args.email, aid)))
    psql("insert into person (user_id, home_id, home_member_id, name, color) values "
         "(%d, (select default_home_id from app_user where email = '%s'), %d, 'CC-M-Ajena', '#FFEEDD')"
         % (aid, args.email, foreign))
    check("POST /event/create", "M23 person_ids de persona de otro hogar → 400 Invalid person",
          request("POST", "/event/create?timezone=Europe/Madrid",
                  {"calendar_id": cal, "title": "CC-M-EvF", "date_at": "2026-12-06 10:00:00",
                   "alarm": 5, "person_ids": [foreign]}, mtok, home=hM), 400, ERR_INVALID_PERSON)
    check("POST /event/create", "M23b person_ids de persona del hogar sin lista compartida → 200",
          request("POST", "/event/create?timezone=Europe/Madrid",
                  {"calendar_id": cal, "title": "CC-M-EvH", "date_at": "2026-12-07 10:00:00",
                   "alarm": 5, "person_ids": [per]}, mtok, home=hM), 200, EVENT_DETAIL)


scenario_matriz(hM, mem_m, mid)


# ── Bloque 1.10 (contratos de /home/*): 34 casos ──
# Huecos de la superficie /home/* detectados al documentar `docs/CONTRATOS_HOME.md`: 401 sin Bearer
# y 400 Invalid home por ruta (el dispatcher los resuelve antes del handler: sin tocar datos) más 4
# casos específicos. Solo lectura/errores de validación; el único cambio de estado (snapshot de
# cc-mem para el 403 de detail) se restaura al terminar. Corre tras la matriz 1.8: usa cc-mem.

HOME_ROUTE_CALLS = [
    ("GET", "/home"), ("POST", "/home/create"), ("GET", "/home/detail"),
    ("PATCH", "/home/update"), ("PATCH", "/home/default"), ("GET", "/home/membership"),
    ("PATCH", "/home/membership/role"), ("POST", "/home/membership/transfer"),
    ("DELETE", "/home/membership"), ("GET", "/home/member"), ("POST", "/home/member/create"),
    ("PATCH", "/home/member/update"), ("GET", "/home/permission"), ("PATCH", "/home/permission"),
    ("GET", "/home/audit"),
]


def scenario_home_110(hM, mem_m):
    for method, path in HOME_ROUTE_CALLS:
        body = {} if method != "GET" else None
        check(f"{method} {path}", f"H110 {method} {path} sin Bearer → 401 Unauthorized",
              request(method, path, body), 401, ERR_UNAUTHORIZED)
    for method, path in HOME_ROUTE_CALLS:
        body = {} if method != "GET" else None
        check(f"{method} {path}", f"H110 {method} {path} con X-Home-Id: abc → 400 Invalid home",
              request(method, path, body, tok, home="abc"), 400, ERR_INVALID_HOME)
    # detail sin home.view: cc-mem (member) con snapshot child sin home.view → 403 Not Allowed
    mauth = request("POST", "/user/auth", {"email": MEM_EMAIL, "password": MEM_PASSWORD})
    mtok = parse(mauth[1]).get("token") if mauth[0] == 200 else None
    if mtok is None:
        sys.exit("no se pudo reautenticar cc-mem para el bloque 1.10")
    psql(f"select fn_seed_kind_permissions({mem_m}, 'child'); "
         f"delete from membership_permission where home_membership_id = {mem_m} "
         "and permission_code = 'home.view'")
    check("GET /home/detail", "H110 GET /home/detail member sin home.view → 403 Not Allowed",
          request("GET", f"/home/detail?id={hM}", None, mtok), 403, ERR_NOT_ALLOWED)
    psql(f"select fn_seed_kind_permissions({mem_m}, 'adult')")
    check("PATCH /home/default", "H110 PATCH /home/default sin home_id → 400 Home ID is required",
          request("PATCH", "/home/default", {}, tok), 400, ERR_HOME_ID_REQUIRED)
    check("PATCH /home/member/update", "H110 PATCH /home/member/update status no string → 400",
          request("PATCH", "/home/member/update", {"id": 1, "status": 1}, tok), 400, ERR_INVALID_MEMBER)
    check("GET /home", "H110 GET /home con X-Home-Id vacía = sin cabecera (A9) → 200",
          request("GET", "/home", None, tok, home=""), 200, [HOME_ITEM])


scenario_home_110(hM, mem_m)


# ── Bloque 1.15 (invitaciones, diseño §5.2; plan 1.15 §Pruebas): 69 casos ──
# Hogar CC-Membresias (hM, admin demo) y cc-mem (member adult sin home.invite). Usuarios propios
# cc-inv/cc-inv2/cc-inv3 (los borra reset_leftovers). Los miembros fixture (CC-Inv-*) se crean por
# psql con su person 1:1 (I5). El código en claro nunca se imprime ni viaja a psql: el sha256 se
# calcula en Python y se compara con code_hash. D-017: solo un admin crea invitaciones adult.

INV_PWD = "ccinv12345"
INV_EMAILS = ["cc-inv@homita.example", "cc-inv2@homita.example", "cc-inv3@homita.example"]


def inv_member(home, kind, name, status="active", linked=None):
    """home_member + person 1:1 por psql (fixture; sin grants externos)."""
    hm = int(psql("insert into home_member (home_id, kind, name, color, status, app_user_id, created_by) "
                  "values (%d, '%s', '%s', '#123456', '%s', %s, %d) returning id"
                  % (home, kind, name, status, "null" if linked is None else linked, aid)))
    psql("insert into person (user_id, home_id, home_member_id, name, color) "
         "values (%d, %d, %d, '%s', '#123456')" % (linked or aid, home, hm, name))
    return hm


def scenario_invitations(hM, mem_m, mid):
    import hashlib
    # IX1–IX3: altas (registro abierto en la demo) + login sin contar
    toks, ids = [], []
    for i, email in enumerate(INV_EMAILS, 1):
        check("POST /user/create", f"IX{i} POST /user/create {email.split('@')[0]} → 201 USER_CREATE",
              request("POST", "/user/create", {"name": f"CC-Inv-{i}", "email": email,
                                               "password": INV_PWD}), 201, USER_CREATE)
        a = request("POST", "/user/auth", {"email": email, "password": INV_PWD})
        if a[0] != 200:
            sys.exit(f"no se pudo autenticar {email} (¿ALLOW_REGISTRATION=true en la Edge?)")
        toks.append(parse(a[1])["token"])
        ids.append(parse(a[1])["id"])
    itok, itok2, itok3 = toks
    iid, iid2, iid3 = ids
    mauth = request("POST", "/user/auth", {"email": MEM_EMAIL, "password": MEM_PASSWORD})
    mtok = parse(mauth[1]).get("token") if mauth[0] == 200 else None
    if mtok is None:
        sys.exit("no se pudo reautenticar cc-mem para el bloque 1.15")
    psql(f"select fn_seed_kind_permissions({mem_m}, 'adult')")  # adult: sin home.invite
    demo_home = int(psql("select default_home_id from app_user where id = %d" % aid))
    # Fixtures: miembros de hM (relative, pet, vinculado, inactivo, adult) y uno de otro hogar
    abuela = inv_member(hM, "relative", "CC-Inv-Abuela")
    pet = inv_member(hM, "pet", "CC-Inv-Mascota")
    inactive = inv_member(hM, "child", "CC-Inv-Inactivo", status="inactive")
    adult = inv_member(hM, "adult", "CC-Inv-Adulto")
    linked = int(psql("select id from home_member where home_id = %d and app_user_id = %d" % (hM, mid))
                 or 0) or inv_member(hM, "adult", "CC-Inv-Vinculado", linked=mid)
    other = inv_member(demo_home, "adult", "CC-Inv-Otro")

    # IH1–IH8: las 4 rutas sin Bearer → 401 y con X-Home-Id: abc → 400 (dispatcher)
    calls = [("GET", "/home/invitation"), ("POST", "/home/invitation/create"),
             ("POST", "/home/invitation/accept"), ("POST", "/home/invitation/revoke")]
    for method, path in calls:
        body = {} if method != "GET" else None
        check(f"{method} {path}", f"IH {method} {path} sin Bearer → 401 Unauthorized",
              request(method, path, body), 401, ERR_UNAUTHORIZED)
    for method, path in calls:
        body = {} if method != "GET" else None
        check(f"{method} {path}", f"IH {method} {path} con X-Home-Id: abc → 400 Invalid home",
              request(method, path, body, tok, home="abc"), 400, ERR_INVALID_HOME)

    # ── Fase 1: create (IC1–IC19), IR7 y listado (IL1–IL7) ──
    C, R, A, L = ("POST /home/invitation/create", "POST /home/invitation/revoke",
                  "POST /home/invitation/accept", "GET /home/invitation")
    b = check(C, "IC1 admin crea guest → 201 INVITATION_CREATED",
              request("POST", "/home/invitation/create", {"home_id": hM, "kind": "guest"}, tok),
              201, INVITATION_CREATED)
    k1, id1 = (b.get("code"), b.get("id")) if isinstance(b, dict) else (None, None)
    row = psql("select code_hash || '|' || extract(epoch from (expires_at - created_at))::bigint "
               "|| '|' || row_to_json(i)::text from home_invitation i where id = %d" % (id1 or 0))
    parts = row.split("|", 2) if row else ["", "", ""]
    value(C, "IC2 código 32 hex, code_hash = sha256(código), +7 días y sin el código en claro en BD",
          isinstance(k1, str) and re.match(r"^[0-9a-f]{32}$", k1) is not None
          and parts[0] == hashlib.sha256(k1.encode()).hexdigest() and parts[1] == str(7 * 86400)
          and k1 not in parts[2], "fila de home_invitation no cumple (código no impreso)")
    for n, name, body in (
            ("IC3", "kind pet sin miembro", {"home_id": hM, "kind": "pet"}),
            ("IC4", "sin kind ni member_id", {"home_id": hM}),
            ("IC5", "kind 'boss'", {"home_id": hM, "kind": "boss"}),
            ("IC6", "miembro pet", {"home_id": hM, "member_id": pet}),
            ("IC7", "miembro vinculado", {"home_id": hM, "member_id": linked}),
            ("IC8", "miembro inactivo", {"home_id": hM, "member_id": inactive}),
            ("IC9", "miembro de otro hogar", {"home_id": hM, "member_id": other})):
        check(C, f"{n} {name} → 400 Invalid member",
              request("POST", "/home/invitation/create", body, tok), 400, ERR_INVALID_MEMBER)
    b = check(C, "IC10 miembro relative sin vincular (CC-Inv-Abuela) → 201 kind relative",
              request("POST", "/home/invitation/create", {"home_id": hM, "member_id": abuela}, tok),
              201, dict(INVITATION_CREATED, kind="relative", member_id=abuela,
                        member_name="CC-Inv-Abuela"))
    k10 = b.get("code") if isinstance(b, dict) else None
    check(C, "IC11 miembro + kind distinto → 400 Invalid member",
          request("POST", "/home/invitation/create", {"home_id": hM, "member_id": abuela,
                                                      "kind": "guest"}, tok), 400, ERR_INVALID_MEMBER)
    check(C, "IC12 cc-mem sin home.invite → 403 Not Allowed",
          request("POST", "/home/invitation/create", {"home_id": hM, "kind": "guest"}, mtok),
          403, ERR_NOT_ALLOWED)
    check(C, "IC13 cc-inv no miembro → 404 Not Found",
          request("POST", "/home/invitation/create", {"home_id": hM, "kind": "guest"}, itok),
          404, ERR_NOT_FOUND)
    check(C, "IC14 cabecera de otro hogar del admin → 404 Not Found",
          request("POST", "/home/invitation/create", {"home_id": hM, "kind": "guest"}, tok,
                  home=demo_home), 404, ERR_NOT_FOUND)
    check(C, "IC15 sin home_id → 400 Home ID is required",
          request("POST", "/home/invitation/create", {"kind": "guest"}, tok), 400, ERR_HOME_ID_REQUIRED)
    check(C, "IC16 member_id 'x' → 400 Invalid member",
          request("POST", "/home/invitation/create", {"home_id": hM, "member_id": "x"}, tok),
          400, ERR_INVALID_MEMBER)
    psql("insert into membership_permission (home_membership_id, permission_code) "
         "values (%d, 'home.invite') on conflict do nothing" % mem_m)
    b = check(C, "IC17 cc-mem con home.invite (psql) crea guest → 201",
              request("POST", "/home/invitation/create", {"home_id": hM, "kind": "guest"}, mtok),
              201, INVITATION_CREATED)
    id17 = b.get("id") if isinstance(b, dict) else 0
    check(C, "IC18 D-017: cc-mem (no admin) con home.invite crea adult → 403 Not Allowed",
          request("POST", "/home/invitation/create", {"home_id": hM, "kind": "adult"}, mtok),
          403, ERR_NOT_ALLOWED)
    check(C, "IC19 D-017: cc-mem (no admin) invita a un miembro adult → 403 Not Allowed",
          request("POST", "/home/invitation/create", {"home_id": hM, "member_id": adult}, mtok),
          403, ERR_NOT_ALLOWED)
    psql("delete from membership_permission where home_membership_id = %d "
         "and permission_code = 'home.invite'" % mem_m)
    check(R, "IR7 cc-inv no miembro revoca → 404 Not Found",
          request("POST", "/home/invitation/revoke", {"home_id": hM, "id": id1}, itok), 404, ERR_NOT_FOUND)
    b = check(L, "IL1 admin GET /home/invitation → 200 [INVITATION_ITEM] con IC1 e IC10",
              request("GET", f"/home/invitation?home_id={hM}", None, tok), 200, [INVITATION_ITEM])
    listed = [x.get("id") for x in b if isinstance(x, dict)] if isinstance(b, list) else []
    value(L, "IL2 ningún item lleva code ni code_hash (y están IC1 e IC10, id desc)",
          isinstance(b, list) and all("code" not in x and "code_hash" not in x for x in b)
          and id1 in listed and listed == sorted(listed, reverse=True), repr(listed)[:200])
    psql("update home_invitation set expires_at = (now() at time zone 'UTC') - interval '1 minute' "
         "where id = %d" % id17)
    b = request("GET", f"/home/invitation?home_id={hM}", None, tok)
    value(L, "IL3 una invitación caducada (psql) no aparece en el listado",
          b[0] == 200 and id17 not in [x.get("id") for x in parse(b[1])], b[1][:200])
    check(L, "IL4 cc-mem sin home.invite → 403 Not Allowed",
          request("GET", f"/home/invitation?home_id={hM}", None, mtok), 403, ERR_NOT_ALLOWED)
    check(L, "IL5 cc-inv no miembro → 404 Not Found",
          request("GET", f"/home/invitation?home_id={hM}", None, itok), 404, ERR_NOT_FOUND)
    check(L, "IL6 sin home_id → 400 Home ID is required",
          request("GET", "/home/invitation", None, tok), 400, ERR_HOME_ID_REQUIRED)
    check(L, "IL7 cabecera ajena → 404 Not Found",
          request("GET", f"/home/invitation?home_id={hM}", None, tok, home=demo_home), 404, ERR_NOT_FOUND)

    # ── Fase 2: accept (IA1–IA19), revoke (IR1–IR6, IR8–IR11) y email externo (IQ1–IQ2) ──
    b = check(A, "IA1 cc-inv acepta IC1 → 200 INVITATION_ACCEPTED (member, guest)",
              request("POST", "/home/invitation/accept", {"code": k1}, itok), 200,
              dict(INVITATION_ACCEPTED, kind="guest"))
    hm1 = b.get("member_id") if isinstance(b, dict) else 0
    homes = parse(request("GET", "/home", None, itok)[1])
    mships = parse(request("GET", f"/home/membership?id={hM}", None, tok)[1])
    perms = next((x.get("permissions") for x in mships if isinstance(x, dict)
                  and x.get("app_user_id") == iid), None) if isinstance(mships, list) else None
    value(A, "IA2 GET /home de cc-inv incluye hM como member y su snapshot es el de guest (3)",
          isinstance(homes, list) and any(h.get("home_id") == hM and h.get("role") == "member"
                                          for h in homes)
          and perms == ["calendar.view", "task.complete", "task.view"], repr(perms)[:200])
    row = psql("select hm.kind || '|' || hm.app_user_id || '|' || (select count(*) from person p "
               "where p.home_member_id = hm.id and p.home_id = hm.home_id) || '|' || i.status || '|' "
               "|| i.accepted_by from home_member hm, home_invitation i "
               "where hm.id = %d and i.id = %d" % (hm1 or 0, id1 or 0))
    value(A, "IA3 psql: home_member guest vinculado + person 1:1 e invitación accepted/accepted_by",
          row == f"guest|{iid}|1|accepted|{iid}", repr(row))
    check(A, "IA4 cc-inv2 reutiliza el código de IC1 → 404 Not Found",
          request("POST", "/home/invitation/accept", {"code": k1}, itok2), 404, ERR_NOT_FOUND)
    b = check(C, "IA5 admin crea K2 (guest) → 201",
              request("POST", "/home/invitation/create", {"home_id": hM, "kind": "guest"}, tok),
              201, INVITATION_CREATED)
    k2, id2 = (b.get("code"), b.get("id")) if isinstance(b, dict) else (None, 0)
    check(A, "IA6 cc-inv (ya miembro) acepta K2 → 400 Already member",
          request("POST", "/home/invitation/accept", {"code": k2}, itok), 400, ERR_ALREADY_MEMBER)
    value(A, "IA7 psql: K2 sigue pending (Already member no consume)",
          psql("select status from home_invitation where id = %d" % id2) == "pending")
    b = check(A, "IA8 cc-inv2 acepta IC10 → 200 con member_id de CC-Inv-Abuela (relative)",
              request("POST", "/home/invitation/accept", {"code": k10}, itok2), 200,
              dict(INVITATION_ACCEPTED, member_id=abuela, kind="relative"))
    members = parse(request("GET", f"/home/member?home_id={hM}", None, tok)[1])
    mships = parse(request("GET", f"/home/membership?id={hM}", None, tok)[1])
    perms2 = next((x.get("permissions") for x in mships if isinstance(x, dict)
                   and x.get("app_user_id") == iid2), None) if isinstance(mships, list) else None
    value(A, "IA9 GET /home/member: CC-Inv-Abuela linked = true y cc-inv2 con permisos de relative (10)",
          isinstance(members, list) and any(m.get("id") == abuela and m.get("linked") is True
                                            for m in members)
          and isinstance(perms2, list) and len(perms2) == 10, repr(perms2)[:200])
    check(A, "IA10 código inexistente de 32 hex → 404 Not Found",
          request("POST", "/home/invitation/accept", {"code": "0123456789abcdef" * 2}, itok3),
          404, ERR_NOT_FOUND)
    check(A, "IA11 código 'xyz' → 404 con el mismo cuerpo",
          request("POST", "/home/invitation/accept", {"code": "xyz"}, itok3), 404, ERR_NOT_FOUND)
    # IA12 (+ R1-01 review): sin code en el body → 400; el query string se ignora (un `?code=` no
    # se acepta: acabaría en logs de URL). Si la Edge leyera la query respondería 404, no 400.
    check(A, "IA12 sin body y con ?code= (32 hex) → 400 Invitation code is required (query ignorada)",
          request("POST", "/home/invitation/accept?code=" + "fedcba9876543210" * 2, None, itok3),
          400, ERR_INVITATION_CODE_REQUIRED)
    b = check(C, "IA13 admin crea K-exp (guest) → 201",
              request("POST", "/home/invitation/create", {"home_id": hM, "kind": "guest"}, tok),
              201, INVITATION_CREATED)
    kexp, idexp = (b.get("code"), b.get("id")) if isinstance(b, dict) else (None, 0)
    psql("update home_invitation set expires_at = (now() at time zone 'UTC') - interval '1 minute' "
         "where id = %d" % idexp)
    check(A, "IA14 K-exp caducada (psql) → 404 Not Found",
          request("POST", "/home/invitation/accept", {"code": kexp}, itok3), 404, ERR_NOT_FOUND)
    check(A, "IA15 cc-inv3 acepta K2 con X-Home-Id de hM (aún no miembro) → 200 (D-015)",
          request("POST", "/home/invitation/accept", {"code": k2}, itok3, home=hM), 200,
          dict(INVITATION_ACCEPTED, kind="guest"))
    b = check("POST /home/create", "IA16 admin POST /home/create CC-Inv-Arch → 201",
              request("POST", "/home/create", {"name": "CC-Inv-Arch"}, tok), 201, HOME_DETAIL)
    harch = b.get("id") if isinstance(b, dict) else 0
    b = check(C, "IA17 invitación en CC-Inv-Arch → 201",
              request("POST", "/home/invitation/create", {"home_id": harch, "kind": "guest"}, tok),
              201, INVITATION_CREATED)
    karch = b.get("code") if isinstance(b, dict) else None
    psql("update home set status = 'archived' where id = %d" % harch)
    check(A, "IA18 hogar archivado (psql) → accept 404 Not Found",
          request("POST", "/home/invitation/accept", {"code": karch}, itok), 404, ERR_NOT_FOUND)
    b = request("GET", f"/home/invitation?home_id={hM}", None, tok)
    listed = [x.get("id") for x in parse(b[1])] if b[0] == 200 else None
    value(L, "IA19 GET /home/invitation: sin IC1 ni K2 (aceptadas) y sin code",
          listed is not None and id1 not in listed and id2 not in listed and '"code"' not in b[1],
          repr(listed)[:200])
    b = check(C, "IR1 admin crea K3 → 201",
              request("POST", "/home/invitation/create", {"home_id": hM, "kind": "child"}, tok),
              201, INVITATION_CREATED)
    k3, id3 = (b.get("code"), b.get("id")) if isinstance(b, dict) else (None, 0)
    check(R, "IR2 revoke K3 → 200 INVITATION_ITEM con status revoked",
          request("POST", "/home/invitation/revoke", {"home_id": hM, "id": id3}, tok), 200,
          dict(INVITATION_ITEM, status="revoked"))
    check(A, "IR3 cc-inv (ya miembro) acepta K3 revocada → 404 (paso 1 antes que el 2)",
          request("POST", "/home/invitation/accept", {"code": k3}, itok), 404, ERR_NOT_FOUND)
    check(R, "IR4 revoke repetido → 404 Not Found",
          request("POST", "/home/invitation/revoke", {"home_id": hM, "id": id3}, tok), 404, ERR_NOT_FOUND)
    check(R, "IR5 revoke de IC1 aceptada → 404 Not Found",
          request("POST", "/home/invitation/revoke", {"home_id": hM, "id": id1}, tok), 404, ERR_NOT_FOUND)
    check(R, "IR6 cc-mem sin home.invite → 403 Not Allowed",
          request("POST", "/home/invitation/revoke", {"home_id": hM, "id": id3}, mtok), 403, ERR_NOT_ALLOWED)
    check(R, "IR8 id inexistente → 404 Not Found",
          request("POST", "/home/invitation/revoke", {"home_id": hM, "id": 999999999}, tok), 404, ERR_NOT_FOUND)
    check(R, "IR9 sin id → 400 Invitation ID is required",
          request("POST", "/home/invitation/revoke", {"home_id": hM}, tok), 400, ERR_INVITATION_ID_REQUIRED)
    check(R, "IR10 sin home_id → 400 Home ID is required",
          request("POST", "/home/invitation/revoke", {"id": id3}, tok), 400, ERR_HOME_ID_REQUIRED)
    check(R, "IR11 revoke de K-exp caducada → 404 Not Found",
          request("POST", "/home/invitation/revoke", {"home_id": hM, "id": idexp}, tok), 404, ERR_NOT_FOUND)
    # IQ1–IQ2 (Q2 a): email de cc-inv3 (miembro de hM, NO del hogar del recurso) → 403 y 0 filas
    cal = int(psql("select c.id from calendar c join calendar_user cu on cu.calendar_id = c.id "
                   "where cu.user_id = %d and cu.role = 'owner' and c.home_id = %d order by c.id limit 1"
                   % (aid, demo_home)) or 0)
    lst = int(psql("select t.id from task_list t join task_list_user tu on tu.task_list_id = t.id "
                   "where tu.user_id = %d and tu.role = 'owner' and t.home_id = %d order by t.id limit 1"
                   % (aid, demo_home)) or 0)
    r = request("POST", "/calendar/user", {"calendar_id": cal, "email": INV_EMAILS[2]}, tok)
    n = psql("select count(*) from calendar_user where calendar_id = %d and user_id = %d" % (cal, iid3))
    value("POST /calendar/user", "IQ1 email externo al hogar del calendario → 403 Not Allowed y 0 filas ACL",
          r == (403, ERR_NOT_ALLOWED) and n == "0", repr(r)[:200] + f" filas={n}")
    r = request("POST", "/task-list/user", {"task_list_id": lst, "email": INV_EMAILS[2]}, tok)
    n = psql("select count(*) from task_list_user where task_list_id = %d and user_id = %d" % (lst, iid3))
    value("POST /task-list/user", "IQ2 email externo al hogar de la lista → 403 Not Allowed y 0 filas ACL",
          r == (403, ERR_NOT_ALLOWED) and n == "0", repr(r)[:200] + f" filas={n}")


scenario_invitations(hM, mem_m, mid)


# ── Resumen: cobertura de las 43 rutas legacy + 19 rutas home y rutas con regresión ──

missing = [r for r in ROUTES + HOME_ROUTES if r not in covered]
fails = results.count(False)
legacy_cov = len([r for r in ROUTES if r in covered])
home_cov = len([r for r in HOME_ROUTES if r in covered])
print(f"\n{len(results) - fails}/{len(results)} casos ok · {legacy_cov}/{len(ROUTES)} rutas legacy"
      f" · {home_cov}/{len(HOME_ROUTES)} rutas home")
print("casos por ruta home: " + ", ".join(f"{r} {covered[r]}" for r in HOME_ROUTES))
thin = [r for r in HOME_ROUTES if covered[r] < MIN_HOME_CASES]
if missing:
    print("Rutas sin cubrir: " + ", ".join(missing))
if thin:
    print(f"Rutas home con menos de {MIN_HOME_CASES} casos: " + ", ".join(thin))
if regressed:
    print("Rutas con regresión: " + ", ".join(regressed))
if len(results) != EXPECTED_CASES:
    print(f"conteo de casos: {len(results)} (esperado {EXPECTED_CASES}: 207 de 1.5 + 59 del bloque "
          f"M/C2 de 1.6 + 6 del bloque de permisos por kind de 1.7 + 40 del bloque matriz §3.4.1 "
          f"de 1.8 + 39 del bloque 1.9 de configuración de permisos (3+8+15+7+6) + 34 del bloque "
          f"1.10 de contratos home (15+15+4) + 69 del bloque 1.15 de invitaciones "
          f"(3+8+19+7+19+11+2))")
sys.exit(1 if fails or missing or thin or len(results) != EXPECTED_CASES else 0)
