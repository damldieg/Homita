#!/usr/bin/env python3
"""Comprueba el contrato HTTP del dashboard: oráculo PHP local vs Edge Function de Supabase.

Compara JSON PARSEADO (el orden de claves es irrelevante): `json_encode` de PHP emite el orden de
propiedades de las clases (evento: id, calendar_id, routine_id, routine_date, calendar_color,
calendar_name, title, date_at, alarm, persons, created_at, updated_at; tarea: id, task_list_id,
task_list_color, task_list_name, title, order, completed_at, created_at, updated_at — ver builder-1),
pero el plan define la comparación normalizada; la Edge respeta ese orden igualmente.

Normalización: el `token` se ignora (token de sesión PHP vs JWT) y `created_at`/`updated_at` se
validan por formato `YYYY-MM-DD HH:MM:SS` en lugar de por valor (los seeds se crean en momentos
distintos); el resto de valores debe ser idéntico.

Escenarios: POST /user/auth (200, 400 sin campos, 401 contraseña errónea) y el email inexistente
codificado como desviación documentada (PHP 500 {"error":"Not Found"} vs Edge 401 {"error":"Invalid
credentials"}, R1-08); GET /event con los rangos de ContentRepository (eventos desde el día 1 del mes
−12 sin end_date; sesiones hoy..+7) y de CalendarRepository (semanas lunes–domingo, routine=false y
routine=true); GET /task?dashboard=true.

Oráculo PHP: `scripts/demo.sh up` (en macOS falta `setsid`: arrancar `php -S` a mano, ver
supabase/README.md). Origen de los datos: seed.py en PHP y seed_supabase.py en la Edge (AC3).

Uso: python3 scripts/supabase/contract_check.py [--php URL] [--fn URL] [--timezone TZ]
Variables de entorno (equivalentes a las opciones): CONTRACT_PHP_URL y SUPABASE_FUNCTIONS_URL.
"""
import argparse
import datetime
import json
import os
import re
import sys
import urllib.error
import urllib.request

TS_RE = re.compile(r"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$")
TS_KEYS = {"created_at", "updated_at"}

parser = argparse.ArgumentParser(description="Contrato PHP vs Edge (ver docstring del script)")
parser.add_argument("--php", default=os.environ.get("CONTRACT_PHP_URL", "http://127.0.0.1:3001"),
                    help="oráculo PHP (scripts/demo.sh up)")
parser.add_argument("--fn", default=os.environ.get("SUPABASE_FUNCTIONS_URL", "http://127.0.0.1:54321/functions/v1/api"),
                    help="Edge Function api (stack local o $SUPABASE_FUNCTIONS_URL)")
parser.add_argument("--email", default="demo@homita.example")
parser.add_argument("--password", default="demo1234")
parser.add_argument("--timezone", default="Europe/Madrid")
args = parser.parse_args()
PHP = args.php.rstrip("/")
FN = args.fn.rstrip("/")


def request(base, method, path, body=None, token=None):
    """(status, texto) — también para 4xx/5xx (HTTPError), que son casos del contrato."""
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = "Bearer " + token
    req = urllib.request.Request(base + path, data=json.dumps(body).encode() if body is not None else None,
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


def normalize(value, issues, where):
    """Quita `token`, sustituye created_at/updated_at por un marcador validando su formato."""
    if isinstance(value, dict):
        out = {}
        for k, v in value.items():
            if k == "token":
                continue
            if k in TS_KEYS:
                if not (isinstance(v, str) and TS_RE.match(v)):
                    issues.append(f"{where}: {k} con formato inesperado: {v!r}")
                out[k] = "<ts>"
            else:
                out[k] = normalize(v, issues, where)
        return out
    if isinstance(value, list):
        return [normalize(v, issues, where) for v in value]
    return value


def compare(name, php, fn):
    """php/fn = (status, texto). True si ambos lados coinciden tras normalizar."""
    issues = []
    ps, pt = php
    fs, ft = fn
    if ps != fs:
        issues.append(f"status: PHP {ps} vs Edge {fs}")
    pn = normalize(parse(pt), issues, f"{name} [PHP]")
    fnorm = normalize(parse(ft), issues, f"{name} [Edge]")
    if pn != fnorm:
        issues.append(f"PHP : {json.dumps(pn, sort_keys=True, ensure_ascii=False)[:400]}")
        issues.append(f"Edge: {json.dumps(fnorm, sort_keys=True, ensure_ascii=False)[:400]}")
    ok = not issues
    print(("ok   " if ok else "FAIL ") + name)
    for line in issues:
        print("     " + line)
    return ok


def deviation(name, php, fn, php_expect, fn_expect):
    """Desviación documentada: cada lado debe dar exactamente su comportamiento esperado (R1-08)."""
    ok = php == php_expect and fn == fn_expect
    print(("ok   " if ok else "FAIL ") + name + " (desviación documentada)")
    if not ok:
        print(f"     PHP : {php!r} (esperado {php_expect!r})")
        print(f"     Edge: {fn!r} (esperado {fn_expect!r})")
    return ok


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

AUTH = "POST", "/user/auth", {"email": args.email, "password": args.password}
CASES = [
    ("ContentRepository /event routine=false (día 1 del mes −12, sin end_date)", "GET",
     f"/event?start_date={epoch(month_start)}&routine=false&timezone={tz}&dashboard=true", None),
    ("ContentRepository /event routine=true (hoy..+7)", "GET",
     f"/event?start_date={epoch(today)}&end_date={content_end}&routine=true&timezone={tz}&dashboard=true", None),
    ("CalendarRepository /event semana actual routine=false (lunes–domingo)", "GET",
     f"/event?start_date={epoch(monday)}&end_date={week_end}&routine=false&timezone={tz}&dashboard=true", None),
    ("CalendarRepository /event semana actual routine=true", "GET",
     f"/event?start_date={epoch(monday)}&end_date={week_end}&routine=true&timezone={tz}&dashboard=true", None),
    ("CalendarRepository /event semana siguiente routine=false", "GET",
     f"/event?start_date={epoch(next_monday)}&end_date={next_week_end}&routine=false&timezone={tz}&dashboard=true", None),
    ("CalendarRepository /event semana siguiente routine=true", "GET",
     f"/event?start_date={epoch(next_monday)}&end_date={next_week_end}&routine=true&timezone={tz}&dashboard=true", None),
    ("ContentRepository /task dashboard=true", "GET", "/task?dashboard=true", None),
]

for base in (PHP, FN):
    try:
        request(base, "GET", "/task")
    except OSError as e:
        sys.exit(f"No responde {base}: {e}\nOráculo PHP: scripts/demo.sh up (macOS sin setsid: "
                 "arrancar php -S a mano, ver supabase/README.md)")

results = []
# Auth: 200 (los tokens de aquí autentican las lecturas), 400, 401 y la desviación de email inexistente
php_auth = request(PHP, *AUTH)
fn_auth = request(FN, *AUTH)
results.append(compare("POST /user/auth", php_auth, fn_auth))
if php_auth[0] != 200 or fn_auth[0] != 200:
    sys.exit("login falló en PHP o Edge: no se puede seguir")
php_tok = parse(php_auth[1])["token"]
fn_tok = parse(fn_auth[1])["token"]

results.append(compare("POST /user/auth sin campos (400)", request(PHP, "POST", "/user/auth", {}),
                       request(FN, "POST", "/user/auth", {})))
results.append(compare("POST /user/auth contraseña errónea (401)",
                       request(PHP, "POST", "/user/auth", {"email": args.email, "password": "mala"}),
                       request(FN, "POST", "/user/auth", {"email": args.email, "password": "mala"})))
results.append(deviation("POST /user/auth email inexistente",
                         request(PHP, "POST", "/user/auth",
                                 {"email": "noexiste@homita.example", "password": args.password}),
                         request(FN, "POST", "/user/auth",
                                 {"email": "noexiste@homita.example", "password": args.password}),
                         (500, '{"error":"Not Found"}'), (401, '{"error":"Invalid credentials"}')))

for name, method, path, body in CASES:
    results.append(compare(name, request(PHP, method, path, body, php_tok),
                           request(FN, method, path, body, fn_tok)))

fails = results.count(False)
print(f"\n{len(results) - fails}/{len(results)} casos ok")
sys.exit(1 if fails else 0)
