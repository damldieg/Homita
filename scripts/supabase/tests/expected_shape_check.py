#!/usr/bin/env python3
"""Forma esperada de las rutas SIN oráculo PHP (plan §4, T14): contratos nuevos o desviados donde
PHP no es comparable (Gemini diferido, `refresh_token`, `config` con flag, registro).

Casos:
* `POST /user/auth` → claves exactas {id,name,email,token,refresh_token,created_at,updated_at};
  `refresh_token` aditivo (Q8): string no vacío; timestamps con forma TS.
* `POST /user/auth` sin campos → 400 `{"error":"Email and password are required"}`.
* `GET /config` → exactamente `{"allow_registration": bool}` igual al flag esperado (T4/Q3).
* `POST /event/create` con `text` y sin `title`+`date_at` (cada combinación) → 400 con el mensaje
  PHP exacto `Title and date_at are required if text is not provided` (T14: Gemini diferido;
  PHP solo lo emitiría si Gemini falla → desviación documentada, sin oráculo).
* `POST /event/create` manual (title+date_at) → 200 con la forma de evento (10 claves).
* registro (`POST /user/create`): con flag true → crea usuario y `user/auth` confirma el `app_user`
  del trigger 0004; con flag false → 403 `{"error":"Not Allowed"}` (UserCreate.php:13, verbatim).

Se ejecuta DOS veces, una por configuración de la Edge servida (`functions serve --env-file`):
`--expect-allow-registration true` con ALLOW_REGISTRATION=true y `false` con ALLOW_REGISTRATION=false.

Variables de entorno: SUPABASE_FUNCTIONS_URL (default = stack local). Python stdlib.
Uso: python3 scripts/supabase/tests/expected_shape_check.py --expect-allow-registration true
"""
import argparse
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request

TS_RE = re.compile(r"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$")
EVENT_KEYS = {"id", "calendar_id", "title", "date_at", "created_at", "updated_at",
              "routine_id", "routine_date", "alarm", "persons"}

parser = argparse.ArgumentParser(description="Forma esperada sin oráculo (ver docstring)")
parser.add_argument("--expect-allow-registration", required=True, choices=["true", "false"],
                    help="valor esperado de /config y del comportamiento de user/create")
parser.add_argument("--fn", default=os.environ.get("SUPABASE_FUNCTIONS_URL",
                                                   "http://127.0.0.1:54321/functions/v1/api"))
args = parser.parse_args()
FN = args.fn.rstrip("/")
EXPECT_FLAG = args.expect_allow_registration == "true"


def request(method, path, body=None, token=None):
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
    except urllib.error.URLError:
        sys.exit(f"No responde {FN}: arranca la Edge (functions serve --env-file …)")


results = []


def check(name, ok, detail=""):
    results.append(bool(ok))
    print(("ok   " if ok else "FAIL ") + name)
    if not ok and detail:
        print("     " + detail)


def body(res):
    try:
        return json.loads(res[1])
    except ValueError:
        return res[1]


# ── user/auth: forma exacta + refresh_token aditivo (Q8) ──
auth = request("POST", "/user/auth", {"email": "demo@homita.example", "password": "demo1234"})
ab = body(auth)
keys_ok = auth[0] == 200 and isinstance(ab, dict) and set(ab) == {
    "id", "name", "email", "token", "refresh_token", "created_at", "updated_at"}
check("POST /user/auth → claves exactas (refresh_token aditivo)", keys_ok, repr(auth)[:300])
if keys_ok:
    check("POST /user/auth → id int, token/refresh_token no vacíos, timestamps con forma TS",
          isinstance(ab["id"], int)
          and isinstance(ab["token"], str) and ab["token"] != ""
          and isinstance(ab["refresh_token"], str) and ab["refresh_token"] != ""
          and TS_RE.match(ab["created_at"]) and TS_RE.match(ab["updated_at"]),
          repr({k: ab[k] for k in ("id", "created_at", "updated_at")})[:300])
tok = ab.get("token", "")

check("POST /user/auth sin campos → 400 exacto",
      request("POST", "/user/auth", {}) == (400, '{"error":"Email and password are required"}'),
      repr(request("POST", "/user/auth", {})))

# ── config: exactamente {allow_registration: bool} = flag esperado (T4/Q3) ──
cfg = request("GET", "/config")
check("GET /config → {allow_registration: bool} = flag esperado",
      cfg[0] == 200 and body(cfg) == {"allow_registration": EXPECT_FLAG}, repr(cfg)[:300])

# ── event/create: text-only → 400 mensaje PHP exacto (T14, Gemini diferido) ──
TEXT_ONLY = (400, '{"error":"Title and date_at are required if text is not provided"}')
for name, payload in [
    ("solo text", {"calendar_id": 1, "text": "mañana comprar pan"}),
    ("text + title sin date_at", {"calendar_id": 1, "text": "mañana comprar pan", "title": "Compra"}),
    ("text + date_at sin title", {"calendar_id": 1, "text": "mañana comprar pan", "date_at": "2026-12-01 10:00:00"}),
]:
    res = request("POST", "/event/create?timezone=Europe/Madrid", payload, tok)
    check(f"POST /event/create {name} → 400 mensaje PHP exacto (desviación Gemini)", res == TEXT_ONLY,
          repr(res)[:300])

# ── event/create manual: forma de evento (10 claves) ──
ev = request("POST", "/event/create?timezone=Europe/Madrid",
             {"calendar_id": 1, "title": "ES-Evento", "date_at": "2026-12-15 10:00:00", "alarm": 5}, tok)
eb = body(ev)
ev_ok = ev[0] == 200 and isinstance(eb, dict) and set(eb) == EVENT_KEYS
check("POST /event/create manual → 200 con la forma de evento", ev_ok, repr(ev)[:300])
if ev_ok:
    check("POST /event/create manual → tipos (id/calendar_id int, date_at TS, persons lista)",
          isinstance(eb["id"], int) and isinstance(eb["calendar_id"], int)
          and TS_RE.match(eb["date_at"]) and TS_RE.match(eb["created_at"])
          and eb["routine_id"] is None and eb["routine_date"] is None
          and isinstance(eb["persons"], list), repr(eb)[:300])
    check("DELETE /event/delete del evento de prueba",
          request("DELETE", "/event/delete?timezone=Europe/Madrid", {"id": eb["id"]}, tok)[0] == 200)

# ── registro según flag: user/create (T4) + trigger on_auth_user_created (0004) ──
email = f"es-{int(time.time())}@homita.example"
reg = request("POST", "/user/create", {"name": "ES Test", "email": email, "password": "test12345"})
if not EXPECT_FLAG:
    check("POST /user/create con ALLOW_REGISTRATION=false → 403 exacto (UserCreate.php:13)",
          reg == (403, '{"error":"Not Allowed"}'), repr(reg)[:300])
else:
    rb = body(reg)
    check("POST /user/create con ALLOW_REGISTRATION=true → 201 con la forma PHP de UserCreate",
          reg[0] == 201 and isinstance(rb, dict) and set(rb) == {
              "id", "name", "email", "token", "created_at", "updated_at"},
          repr(reg)[:300])
    reg_auth = request("POST", "/user/auth", {"email": email, "password": "test12345"})
    check("el signup crea app_user (trigger 0004): user/auth del nuevo usuario → 200",
          reg_auth[0] == 200 and body(reg_auth).get("email") == email, repr(reg_auth)[:300])

fails = results.count(False)
print(f"\n{len(results) - fails}/{len(results)} casos ok")
sys.exit(1 if fails else 0)
