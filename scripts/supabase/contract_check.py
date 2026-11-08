#!/usr/bin/env python3
"""Comprueba el contrato HTTP de la app gestora: oráculo PHP local vs Edge Function de Supabase.

Contrato (a) PHP-compat (D-008): mismas rutas/shapes/errores. Compara JSON PARSEADO (el orden de
claves es irrelevante) con normalización acordada (plan §4, R1-05):

* `token` (user/auth, calendar, task_list): NO se descarta. Se valida string no vacío en ambos
  lados y se sustituye por "<token>" antes de comparar.
* `refresh_token` (solo Edge, POST /user/auth, aditivo): se valida string no vacío y se elimina de
  la copia Edge (PHP no lo tiene: no se compara).
* `created_at`/`updated_at`: validados por formato `YYYY-MM-DD HH:MM:SS` (TS_RE), valor irrelevante.
* ids (claves de ID_KEYS): normalizados por clave de negocio (título/nombre/email) SOLO si la entidad
  fue coleccionada en el transcript del lado (los ids de identidad pueden diferir entre PHP y Edge
  tras escrituras, A4). Si el id NO está en el mapa (entidad no coleccionada, p.ej. `calendar_id` de
  un evento sembrado) se compara CRUDO: los seeds mantienen los ids 1..N alineados, así que un FK
  real divergente falla la comparación en vez de enmascararse con "<id>" (R1-06).
* mensajes de TypeError (`called in <ruta>/fichero.php on line <n>`): se compara fichero+línea; la
  ruta del sufijo se descarta (PHP imprime la absoluta de su despliegue, la Edge la canónica del
  repo — desviación documentada, R1-01).
* eventos materializados: `--no-reset-events` desactiva el reset previo (reset_events) y el filtro
  de ventana frágil (scrub, ±90s) deja fuera ocurrencias que caen entre ambas lecturas.
* restos de ejecuciones anteriores (filas CC-% de escenarios y del bloque viewer): se borran al
  inicio (reset_leftovers) para poder re-ejecutar el script sin re-sembrar las bases.

Casos: auth (200/400/401 + desviación de email inexistente); lecturas del dashboard (9 casos
existentes) + calendar/detail, calendar/user, person, routine, routine/detail, task-list,
task-list/detail, task/detail, event/detail, caso `q` ignorado (T3) y errores exactos (TypeError de
calendar/create sin color R1-01, alarm negativo 400 R1-02, task_list_id en body de GET R1-03 como
desviación de plataforma);
escenarios de escritura create→read→update→delete (person, calendar, task-list+task, routine+alarm+events,
event — este con alarm negativo en update/alarm) con ids normalizados; caso viewer con deviation()
(PHP 200 vs Edge 403 {"error":"Not Allowed"}, matriz §3) y self-remove 400.

Desviaciones documentadas (contract-inventory.md): 401 vs 500 (token/credenciales, R1-08),
owner-only 403 (Q5), refresh_token aditivo (§4), text-only 400 en event/create (T14, sin oracle:
expected-shape en scripts/supabase/tests/).

Oráculo PHP: `scripts/demo.sh up` (en macOS falta `setsid` en PATH: export PATH con
/opt/homebrew/opt/util-linux/bin, o arrancar `php -S` a mano, ver supabase/README.md).
Datos: scripts/demo/seed.py en PHP y scripts/demo/seed_supabase.py en Supabase (ids 1..N iguales).
Para el caso viewer hace falta ALLOW_REGISTRATION=true en la Edge (user/create) y registrar
user/create en el oracle PHP (allow_registration=true en su config de demo).

Uso: python3 scripts/supabase/contract_check.py [--php URL] [--fn URL] [--timezone TZ]
Variables de entorno (equivalentes a las opciones): CONTRACT_PHP_URL y SUPABASE_FUNCTIONS_URL.
"""
import argparse
import datetime
import json
import os
import re
import sqlite3
import sys
import urllib.error
import urllib.request

TS_RE = re.compile(r"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$")
# Sufijo de traza de TypeError PHP ("called in <ruta>/fichero.php on line <n>"): la ruta es la del
# despliegue (R1-01) — se compara fichero+línea, no la ruta.
TRACE_RE = re.compile(r"called in \S*/([^/\s]+ on line \d+)")
# Valores asignados con "ahora al escribir" por cada sistema (PHP CURRENT_TIMESTAMP / PG now()):
# se validan por formato, no por valor (los seeds/escenarios se ejecutan en momentos distintos).
# created_at/updated_at según plan §4; available_from y completed_at son de la misma clase
# (documentado en builder-1.md).
TS_KEYS = {"created_at", "updated_at", "available_from", "completed_at"}
ID_KEYS = {
    "id": "self", "cu_id": "cu", "tlu_id": "tlu", "calendar_id": "calendar",
    "task_list_id": "task_list", "event_id": "event", "routine_id": "routine",
    "person_id": "person", "user_id": "user",
}

parser = argparse.ArgumentParser(description="Contrato PHP vs Edge (ver docstring del script)")
parser.add_argument("--php", default=os.environ.get("CONTRACT_PHP_URL", "http://127.0.0.1:3001"),
                    help="oráculo PHP (scripts/demo.sh up)")
parser.add_argument("--fn", default=os.environ.get("SUPABASE_FUNCTIONS_URL", "http://127.0.0.1:54321/functions/v1/api"),
                    help="Edge Function api (stack local o $SUPABASE_FUNCTIONS_URL)")
parser.add_argument("--email", default="demo@homita.example")
parser.add_argument("--password", default="demo1234")
parser.add_argument("--timezone", default="Europe/Madrid")
parser.add_argument("--no-reset-events", action="store_true",
                    help="no normalizar eventos materializados (ver reset_events; posible divergencia de reloj)")
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
    except urllib.error.URLError:
        raise


def parse(text):
    try:
        return json.loads(text)
    except ValueError:
        return text


def normalize(value, issues, where):
    """token → "<token>" (validando no vacío); refresh_token se elimina (assert no vacío si está);
    created_at/updated_at → "<ts>" validando formato. El resto de valores idénticos."""
    if isinstance(value, dict):
        out = {}
        for k, v in value.items():
            if k == "refresh_token":
                if not (isinstance(v, str) and v):
                    issues.append(f"{where}: refresh_token vacío o no string: {v!r}")
                continue
            if k == "token":
                if not (isinstance(v, str) and v):
                    issues.append(f"{where}: token vacío o no string: {v!r}")
                out[k] = "<token>"
            elif k in TS_KEYS:
                # null es válido (p.ej. tarea pendiente: completed_at=null) y es paridad
                if v is not None and not (isinstance(v, str) and TS_RE.match(v)):
                    issues.append(f"{where}: {k} con formato inesperado: {v!r}")
                out[k] = "<ts>"
            else:
                out[k] = normalize(v, issues, where)
        return out
    if isinstance(value, list):
        return [normalize(v, issues, where) for v in value]
    if isinstance(value, str):
        return TRACE_RE.sub(r"called in \1", value)  # ruta del despliegue en TypeError (R1-01)
    return value


# ── ids por clave de negocio (A4): los ids de identidad pueden diferir entre PHP y Edge ──

def biz_kind(obj):
    if not isinstance(obj, dict):
        return None
    if "cu_id" in obj:
        return "cu", obj.get("email")
    if "tlu_id" in obj:
        return "tlu", obj.get("email")
    if "date_at" in obj and "title" in obj:
        return "event", f'{obj.get("title")}@{obj.get("date_at")}'
    if "completed_at" in obj and "title" in obj:
        return "task", obj.get("title")
    if "days" in obj and "time" in obj:
        return "routine", obj.get("title")
    if "token" in obj and "sort" in obj:
        return "task_list", obj.get("name")
    if "email" in obj and "name" in obj and "created_at" in obj:
        return "user", obj.get("email")
    if "token" in obj:
        return "calendar", obj.get("name")
    if "user_id" in obj and "color" in obj and "name" in obj:
        return "person", obj.get("name")
    return None


class IdMap:
    """Registro id → etiqueta por tipo, construido por lado; las etiquetas son de negocio."""

    def __init__(self):
        self.maps = {k: {} for k in ID_KEYS.values() if k != "self"}
        self.self_labels = {}

    def collect(self, value, path=""):
        if isinstance(value, dict):
            bk = biz_kind(value)
            if bk and isinstance(value.get("id"), int):
                kind, label = bk
                self.maps.setdefault(kind, {})[value["id"]] = f"<{kind}:{label}>"
            if isinstance(value.get("cu_id"), int):
                self.maps["cu"][value["cu_id"]] = f'<cu:{value.get("email")}>'
            if isinstance(value.get("tlu_id"), int):
                self.maps["tlu"][value["tlu_id"]] = f'<tlu:{value.get("email")}>'
            for k, v in value.items():
                self.collect(v, path + "/" + k)
        elif isinstance(value, list):
            for v in value:
                self.collect(v, path)

    def apply(self, value):
        """Ids NO coleccionados (entidades sembradas/ajenas al transcript) → id CRUDO, no "<id>":
        los seeds alinean ids 1..N, así un FK divergente real falla en vez de enmascararse (R1-06)."""
        if isinstance(value, dict):
            out = {}
            for k, v in value.items():
                kind = ID_KEYS.get(k)
                if kind and isinstance(v, int):
                    if k == "id":
                        bk = biz_kind(value)
                        out[k] = f"<{bk[0]}:{bk[1]}>" if bk else v
                    else:
                        out[k] = self.maps.get(kind, {}).get(v, v)
                else:
                    out[k] = self.apply(v)
            return out
        if isinstance(value, list):
            return [self.apply(v) for v in value]
        return value


FRAGILE_SECONDS = 90


def scrub(value):
    """Ventana frágil (harness, no contrato): PHP y Edge materializan con 'ahora' en cada GET
    /event; una ocurrencia que cae entre la lectura PHP y la Edge existiría solo en un lado.
    Se descartan ocurrencias materializadas a ±90s de la comparación (simétrico)."""
    now = datetime.datetime.now()

    def fragile(obj):
        if not isinstance(obj, dict) or obj.get("routine_id") is None:
            return False
        try:
            at = datetime.datetime.strptime(str(obj.get("date_at", "")), "%Y-%m-%d %H:%M:%S")
        except ValueError:
            return False
        return abs((at - now).total_seconds()) <= FRAGILE_SECONDS

    if isinstance(value, list):
        return [scrub(v) for v in value if not fragile(v)]
    if isinstance(value, dict):
        return {k: scrub(v) for k, v in value.items()}
    return value


def compare(name, php, fn, php_ids=None, fn_ids=None):
    """php/fn = (status, texto). True si ambos lados coinciden tras normalizar."""
    issues = []
    ps, pt = php
    fs, ft = fn
    if ps != fs:
        issues.append(f"status: PHP {ps} vs Edge {fs}")
    pn = normalize(scrub(parse(pt)), issues, f"{name} [PHP]")
    fnorm = normalize(scrub(parse(ft)), issues, f"{name} [Edge]")
    if php_ids and fn_ids:
        pn = php_ids.apply(pn)
        fnorm = fn_ids.apply(fnorm)
    if pn != fnorm:
        issues.append(f"PHP : {json.dumps(pn, sort_keys=True, ensure_ascii=False)[:400]}")
        issues.append(f"Edge: {json.dumps(fnorm, sort_keys=True, ensure_ascii=False)[:400]}")
    ok = not issues
    print(("ok   " if ok else "FAIL ") + name)
    for line in issues:
        print("     " + line)
    return ok


def deviation(name, php, fn, php_expect, fn_expect):
    """Desviación documentada: cada lado debe dar exactamente su comportamiento esperado (R1-08).
    Los expect pueden ser (status, texto) o un predicado(status, texto) → bool."""
    def hit(res, expect):
        return expect(res[0], res[1]) if callable(expect) else res == expect

    ok = hit(php, php_expect) and hit(fn, fn_expect)
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
    ("GET /event con q= ignorado (T3: PHP ignora q; Edge ignora q)", "GET",
     f"/event?q=leche&start_date={epoch(today)}&timezone={tz}", None),
]

results = []
for base in (PHP, FN):
    try:
        request(base, "GET", "/task")
    except OSError as e:
        sys.exit(f"No responde {base}: {e}\nOráculo PHP: scripts/demo.sh up (macOS sin setsid en "
                 "PATH: export PATH=/opt/homebrew/opt/util-linux/bin:$PATH, ver supabase/README.md)")

# ── Auth: 200 (los tokens de aquí autentican el resto), 400, 401 y desviación de email inexistente ──
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

def reset_events():
    """Normaliza el materializado antes de comparar: borra los eventos de rutina de cada base
    (son derivables: GET /event routine=true los regenera) y re-materializa en ambos lados en el
    mismo instante. Sin él, una ocurrencia materializada por PHP antes de su hora y por Edge
    después diverge para siempre (PHP no tiene cleanup)."""
    repo = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    db = os.environ.get("CONTRACT_PHP_DB", os.path.join(repo, ".demo", "backend", "db", "database.sqlite"))
    if os.path.exists(db):
        con = sqlite3.connect(db)
        con.execute("delete from event where routine_id is not null")
        con.commit()
        con.close()
    else:
        print(f"aviso: sin base PHP en {db}: reset omitido (ventana frágil posible)")
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY")
    if key:
        rest = FN.split("/functions/")[0] + "/rest/v1/event?routine_id=not.is.null"
        req = urllib.request.Request(rest, method="DELETE",
                                     headers={"apikey": key, "Authorization": "Bearer " + key})
        try:
            urllib.request.urlopen(req).read()
        except urllib.error.HTTPError as e:
            print(f"aviso: reset Edge falló ({e.code}): {e.read().decode()[:120]}")
    else:
        print("aviso: sin SUPABASE_SERVICE_ROLE_KEY: reset Edge omitido (ventana frágil posible)")
    path = f"/event?start_date={epoch(today)}&routine=true&timezone={args.timezone}"
    request(PHP, "GET", path, None, php_tok)
    request(FN, "GET", path, None, fn_tok)


if not args.no_reset_events:
    reset_events()


def reset_leftovers():
    """Higiene entre ejecuciones: borra los restos con prefijo CC-% (escenarios y bloque viewer —
    Edge no llega a borrar el calendario del viewer: 403) para poder re-ejecutar sin re-sembrar.
    Hijos primero en SQLite (sin PRAGMA no hay cascade); en PG basta con los padres (cascade,
    aunque `event.routine_id` es `on delete set null`: los eventos van antes que las rutinas)."""
    repo = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    db = os.environ.get("CONTRACT_PHP_DB", os.path.join(repo, ".demo", "backend", "db", "database.sqlite"))
    if os.path.exists(db):
        con = sqlite3.connect(db)
        for sql in [
            "delete from event_person where event_id in (select id from event where title like 'CC-%')",
            "delete from event_user where event_id in (select id from event where title like 'CC-%')",
            "delete from event_person where person_id in (select id from person where name like 'CC-%')",
            "delete from routine_person where person_id in (select id from person where name like 'CC-%')",
            "delete from routine_person where routine_id in (select id from routine where title like 'CC-%')",
            "delete from routine_event_alarm where routine_id in (select id from routine where title like 'CC-%')",
            "delete from routine_exception where routine_id in (select id from routine where title like 'CC-%')",
            "delete from routine_user where routine_id in (select id from routine where title like 'CC-%')",
            "delete from event where title like 'CC-%'",
            "delete from routine where title like 'CC-%'",
            "delete from task where title like 'CC-%'",
            "delete from task_list_user where task_list_id in (select id from task_list where name like 'CC-%')",
            "delete from task_list where name like 'CC-%'",
            "delete from calendar_user where calendar_id in (select id from calendar where name like 'CC-%')",
            "delete from calendar where name like 'CC-%'",
            "delete from person where name like 'CC-%'",
        ]:
            con.execute(sql)
        con.commit()
        con.close()
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY")
    if key:
        rest = FN.split("/functions/")[0] + "/rest/v1"
        for table, column in (("event", "title"), ("routine", "title"), ("task", "title"),
                              ("task_list", "name"), ("calendar", "name"), ("person", "name")):
            req = urllib.request.Request(f"{rest}/{table}?{column}=like.CC-*", method="DELETE",
                                         headers={"apikey": key, "Authorization": "Bearer " + key})
            try:
                urllib.request.urlopen(req).read()
            except urllib.error.HTTPError as e:
                print(f"aviso: reset_leftovers {table} falló ({e.code}): {e.read().decode()[:120]}")
    else:
        print("aviso: sin SUPABASE_SERVICE_ROLE_KEY: reset_leftovers Edge omitido")


reset_leftovers()

for name, method, path, body in CASES:
    php_case, fn_case = request(PHP, method, path, body, php_tok), request(FN, method, path, body, fn_tok)
    php_cids, fn_cids = IdMap(), IdMap()  # ids materializados difieren (A4): mapas por lado
    php_cids.collect(parse(php_case[1]))
    fn_cids.collect(parse(fn_case[1]))
    results.append(compare(name, php_case, fn_case, php_cids, fn_cids))


# ── Lecturas de la app gestora (plan §4) + errores exactos ──
def both(method, path, body=None):
    return request(PHP, method, path, body, php_tok), request(FN, method, path, body, fn_tok)


read_lists = [
    ("GET /calendar", "/calendar"),
    ("GET /calendar/user", "/calendar/user?calendar_id=1"),
    ("GET /person", "/person"),
    ("GET /routine", f"/routine?timezone={tz}"),
    ("GET /task-list", "/task-list"),
    ("GET /task-list/user", "/task-list/user?task_list_id=1"),
    ("GET /task", "/task"),
]
for name, path in read_lists:
    results.append(compare(name, *both("GET", path)))

read_details = [
    ("GET /calendar/detail", "/calendar/detail?id=1"),
    ("GET /routine/detail", f"/routine/detail?id=1&timezone={tz}"),
    ("GET /task-list/detail", "/task-list/detail?id=1"),
    ("GET /task/detail", "/task/detail?id=1"),
    ("GET /event/detail", f"/event/detail?id=1&timezone={tz}"),
]
for name, path in read_details:
    results.append(compare(name, *both("GET", path)))

# R1-03: task_list_id en el body de GET — PHP lo honra (body gana, ControllerAbstract.php:31 →
# M-check → 500 Not Found con id ajeno); el runtime de la Edge descarta el body de GET/HEAD (fetch
# spec, req.body === null, medido contra edge_runtime directo) → solo ve el query → 200 sin filtro.
# Desviación de plataforma documentada (contract-inventory desviación 9). El código Edge ya honra
# body+query con precedencia del body: si la plataforma entrega el body, este caso FALLA y obliga a
# retirar la desviación.
any_200 = lambda status, text: status == 200  # noqa: E731
results.append(deviation("GET /task con task_list_id en el body (R1-03, desviación plataforma)",
                         request(PHP, "GET", "/task", {"task_list_id": 999999}, php_tok),
                         request(FN, "GET", "/task", {"task_list_id": 999999}, fn_tok),
                         (500, '{"error":"Not Found"}'), any_200))

error_cases = [
    ("GET /calendar/detail sin id (400)", "GET", "/calendar/detail", None),
    ("GET /event/detail id inexistente (500 Not Found)", "GET", f"/event/detail?id=999999&timezone={tz}", None),
    ("GET /task/detail id inexistente (500 Not Found)", "GET", "/task/detail?id=999999", None),
    ("GET /event timezone inválido (400)", "GET", "/event?timezone=No/Zona", None),
    ("GET /task-list/user sin task_list_id (400)", "GET", "/task-list/user", None),
    # R1-01: color ausente → TypeError 500 (default de la firma no aplica); se compara fichero+línea
    ("POST /calendar/create sin color (500 TypeError, R1-01)", "POST", "/calendar/create",
     {"name": "CC-Sin-Color"}),
    # R1-02: alarm negativo → 400 ANTES que person_ids (precedencia EventCreate.php:20-22)
    ("POST /event/create alarm negativo (400, R1-02; precedencia ante person_ids)", "POST",
     f"/event/create?timezone={tz}",
     {"calendar_id": 1, "title": "CC-Neg", "date_at": "2026-12-01 10:00:00", "alarm": -5,
      "person_ids": "no-lista"}),
]
for name, method, path, body in error_cases:
    results.append(compare(name, *both(method, path, body)))


# ── Escenarios de escritura create→read→update→delete (ids normalizados por clave de negocio) ──
def scenario(fn_run):
    """Ejecuta fn_run(base, token, ids) contra PHP y Edge y compara cada paso normalizado."""
    php_out, fn_out = fn_run(PHP, php_tok, {}), fn_run(FN, fn_tok, {})
    php_ids, fn_ids = IdMap(), IdMap()
    for transcript in (php_out, fn_out):
        for _, res in transcript:
            (php_ids if transcript is php_out else fn_ids).collect(parse(res[1]))
    ok = True
    for (pname, pres), (fname, fres) in zip(php_out, fn_out):
        ok = compare(f"escenario {pname}", pres, fres, php_ids, fn_ids) and ok
    return ok


def scenario_person(base, token, ids):
    out = []
    out.append(("person/create", request(base, "POST", "/person/create",
                                         {"name": "CC-Persona", "color": "#AABBCC"}, token)))
    ids["person"] = parse(out[-1][1][1])["id"]
    out.append(("person/update", request(base, "PATCH", "/person/update",
                                         {"id": ids["person"], "name": "CC-Persona 2", "color": "#112233"}, token)))
    out.append(("person tras update", request(base, "GET", "/person", None, token)))
    out.append(("person/delete", request(base, "DELETE", "/person/delete", {"id": ids["person"]}, token)))
    out.append(("person tras delete", request(base, "GET", "/person", None, token)))
    return out


def scenario_calendar(base, token, ids):
    out = []
    out.append(("calendar/create", request(base, "POST", "/calendar/create",
                                           {"name": "CC-Cal", "color": "#123456"}, token)))
    ids["calendar"] = parse(out[-1][1][1])["id"]
    out.append(("calendar/detail", request(base, "GET", f'/calendar/detail?id={ids["calendar"]}', None, token)))
    out.append(("calendar/update", request(base, "PATCH", "/calendar/update",
                                           {"id": ids["calendar"], "name": "CC-Cal 2", "color": "#654321",
                                            "widget": False, "dashboard": True}, token)))
    out.append(("calendar tras update", request(base, "GET", "/calendar", None, token)))
    out.append(("calendar/delete", request(base, "DELETE", "/calendar/delete", {"id": ids["calendar"]}, token)))
    out.append(("calendar tras delete", request(base, "GET", "/calendar", None, token)))
    return out


def scenario_task_list(base, token, ids):
    out = []
    out.append(("task-list/create", request(base, "POST", "/task-list/create",
                                            {"name": "CC-Lista", "color": "#222222", "sort": "title"}, token)))
    ids["task_list"] = parse(out[-1][1][1])["id"]
    out.append(("task/create", request(base, "POST", "/task/create",
                                       {"task_list_id": ids["task_list"], "title": "CC-Tarea"}, token)))
    ids["task"] = parse(out[-1][1][1])["id"]
    out.append(("task/create 2", request(base, "POST", "/task/create",
                                         {"task_list_id": ids["task_list"], "title": "CC-Tarea 2"}, token)))
    out.append(("task/update", request(base, "PATCH", "/task/update",
                                       {"id": ids["task"], "title": "CC-Tarea B"}, token)))
    out.append(("task/complete", request(base, "PATCH", "/task/complete",
                                         {"id": ids["task"], "completed": True}, token)))
    out.append(("task/order", request(base, "PATCH", "/task/order",
                                      {"id": ids["task"], "position": 1}, token)))
    out.append(("tasks de la lista", request(base, "GET", f'/task?task_list_id={ids["task_list"]}', None, token)))
    out.append(("task-list/update", request(base, "PATCH", "/task-list/update",
                                            {"id": ids["task_list"], "name": "CC-Lista 2", "color": "#333333",
                                             "sort": "updated_at"}, token)))
    out.append(("task-list/delete", request(base, "DELETE", "/task-list/delete", {"id": ids["task_list"]}, token)))
    out.append(("task-list tras delete", request(base, "GET", "/task-list", None, token)))
    return out


def scenario_routine(base, token, ids):
    out = []
    start = (monday - datetime.timedelta(days=7)).isoformat()
    out.append(("routine/create", request(base, "POST", f"/routine/create?timezone={tz}", {
        "calendar_id": 1, "title": "CC-Rutina", "frequency": "weekly", "interval": 1,
        "days": [1, 3], "time": "09:30", "start_date": start, "end_date": None,
        "active": True, "alarm": 10}, token)))
    ids["routine"] = parse(out[-1][1][1])["id"]
    out.append(("eventos de CC-Rutina", request(base, "GET",
                                                f"/event?routine=true&start_date={epoch(monday)}&end_date={week_end}&timezone={tz}", None, token)))
    out.append(("routine/alarm", request(base, "PATCH", f"/routine/alarm?timezone={tz}",
                                         {"id": ids["routine"], "alarm": 20}, token)))
    out.append(("routine/update (hora)", request(base, "PATCH", f"/routine/update?timezone={tz}", {
        "id": ids["routine"], "title": "CC-Rutina", "frequency": "weekly", "interval": 1,
        "days": [1, 3], "time": "10:15", "start_date": start, "end_date": None, "active": True}, token)))
    out.append(("eventos tras reconcile", request(base, "GET",
                                                  f"/event?routine=true&start_date={epoch(monday)}&end_date={week_end}&timezone={tz}", None, token)))
    out.append(("routine/delete", request(base, "DELETE", f"/routine/delete?timezone={tz}",
                                          {"id": ids["routine"]}, token)))
    out.append(("eventos tras delete", request(base, "GET",
                                               f"/event?routine=true&start_date={epoch(monday)}&end_date={week_end}&timezone={tz}", None, token)))
    return out


def scenario_event(base, token, ids):
    out = []
    out.append(("event/create", request(base, "POST", f"/event/create?timezone={tz}", {
        "calendar_id": 1, "title": "CC-Evento", "date_at": "2026-12-01 12:00:00", "alarm": 15}, token)))
    ids["event"] = parse(out[-1][1][1])["id"]
    out.append(("event/update", request(base, "PATCH", f"/event/update?timezone={tz}", {
        "id": ids["event"], "title": "CC-Evento 2", "date_at": "2026-12-02 13:30:00", "alarm": 15}, token)))
    out.append(("event/alarm", request(base, "PATCH", f"/event/alarm?timezone={tz}",
                                       {"event_id": ids["event"], "alarm": 30}, token)))
    # R1-02: alarm negativo → 400 en update (validateAlarm EventUpdate.php:19-20) y en alarm
    # (EventUser::apply:18 dentro de la RPC, tras el M-check)
    out.append(("event/update alarm negativo (400, R1-02)", request(base, "PATCH", f"/event/update?timezone={tz}", {
        "id": ids["event"], "title": "CC-Evento 2", "date_at": "2026-12-02 13:30:00", "alarm": -5}, token)))
    out.append(("event/alarm negativo (400, R1-02)", request(base, "PATCH", f"/event/alarm?timezone={tz}",
                                                            {"event_id": ids["event"], "alarm": -5}, token)))
    out.append(("event/detail", request(base, "GET", f"/event/detail?id={ids['event']}&timezone={tz}", None, token)))
    out.append(("event/delete", request(base, "DELETE", f"/event/delete?timezone={tz}",
                                        {"id": ids["event"]}, token)))
    out.append(("event/detail tras delete", request(base, "GET",
                                                    f"/event/detail?id={ids['event']}&timezone={tz}", None, token)))
    return out


results.append(scenario(scenario_person))
results.append(scenario(scenario_calendar))
results.append(scenario(scenario_task_list))
results.append(scenario(scenario_routine))
results.append(scenario(scenario_event))


# ── Viewer (matriz §3): PHP 200 sin check de rol vs Edge 403 {"error":"Not Allowed"} (desviación) ──
B_EMAIL, B_PASSWORD, B_NAME = "viewer@homita.example", "viewer1234", "CC Viewer"

for base in (PHP, FN):
    request(base, "POST", "/user/create", {"name": B_NAME, "email": B_EMAIL, "password": B_PASSWORD})
php_b = request(PHP, "POST", "/user/auth", {"email": B_EMAIL, "password": B_PASSWORD})
fn_b = request(FN, "POST", "/user/auth", {"email": B_EMAIL, "password": B_PASSWORD})
if php_b[0] != 200 or fn_b[0] != 200:
    sys.exit("no se pudo crear/autenticar el usuario viewer (¿ALLOW_REGISTRATION=true en la Edge?)")
php_bt, fn_bt = parse(php_b[1])["token"], parse(fn_b[1])["token"]

# Calendario de A con B de viewer (invita A, owner)
php_vcal = parse(request(PHP, "POST", "/calendar/create", {"name": "CC-Viewer-Cal", "color": "#445566"}, php_tok)[1])["id"]
fn_vcal = parse(request(FN, "POST", "/calendar/create", {"name": "CC-Viewer-Cal", "color": "#445566"}, fn_tok)[1])["id"]
request(PHP, "POST", "/calendar/user", {"calendar_id": php_vcal, "email": B_EMAIL}, php_tok)
request(FN, "POST", "/calendar/user", {"calendar_id": fn_vcal, "email": B_EMAIL}, fn_tok)

php_shared = {"id": php_vcal, "name": "CC-Viewer-Cal RENOMBRADO", "color": "#445566"}
fn_shared = {"id": fn_vcal, "name": "CC-Viewer-Cal RENOMBRADO", "color": "#445566"}
any_ok = lambda status, text: status == 200  # noqa: E731

results.append(deviation("viewer PATCH /calendar/update cambia name (matriz §3)",
                         request(PHP, "PATCH", "/calendar/update", php_shared, php_bt),
                         request(FN, "PATCH", "/calendar/update", fn_shared, fn_bt),
                         any_ok, (403, '{"error":"Not Allowed"}')))
results.append(deviation("viewer POST /calendar/user invita (matriz §3)",
                         request(PHP, "POST", "/calendar/user", {"calendar_id": php_vcal, "email": args.email}, php_bt),
                         request(FN, "POST", "/calendar/user", {"calendar_id": fn_vcal, "email": args.email}, fn_bt),
                         any_ok, (403, '{"error":"Not Allowed"}')))
results.append(deviation("viewer DELETE /calendar/user saca al owner (matriz §3)",
                         request(PHP, "DELETE", "/calendar/user", {"calendar_id": php_vcal, "user_id": 1}, php_bt),
                         request(FN, "DELETE", "/calendar/user", {"calendar_id": fn_vcal, "user_id": 1}, fn_bt),
                         any_ok, (403, '{"error":"Not Allowed"}')))
# self-remove: M → S (400) → O — mismo comportamiento en ambos
results.append(compare("self-remove DELETE /calendar/user (400)",
                       request(PHP, "DELETE", "/calendar/user", {"calendar_id": php_vcal, "user_id": parse(php_b[1])["id"]}, php_bt),
                       request(FN, "DELETE", "/calendar/user", {"calendar_id": fn_vcal, "user_id": parse(fn_b[1])["id"]}, fn_bt)))
# viewer actualizando SOLO sus flags propias (compartidos sin cambiar) → 200 en ambos.
# El nombre se envía igual al actual en Edge (PHP puede tenerlo renombrado por el caso anterior:
# su respuesta se normaliza con ids de negocio).
php_flags = request(PHP, "PATCH", "/calendar/update",
                    {"id": php_vcal, "name": "CC-Viewer-Cal", "color": "#445566", "widget": False}, php_bt)
fn_flags = request(FN, "PATCH", "/calendar/update",
                   {"id": fn_vcal, "name": "CC-Viewer-Cal", "color": "#445566", "widget": False}, fn_bt)
php_fids, fn_fids = IdMap(), IdMap()
php_fids.collect(parse(php_flags[1]))
fn_fids.collect(parse(fn_flags[1]))
results.append(compare("viewer PATCH /calendar/update solo flags propias", php_flags, fn_flags, php_fids, fn_fids))
# delete-cal al final: PHP (sin check de rol) destruye su calendario; Edge 403 (desviación)
results.append(deviation("viewer DELETE /calendar/delete (matriz §3)",
                         request(PHP, "DELETE", "/calendar/delete", {"id": php_vcal}, php_bt),
                         request(FN, "DELETE", "/calendar/delete", {"id": fn_vcal}, fn_bt),
                         any_ok, (403, '{"error":"Not Allowed"}')))

fails = results.count(False)
print(f"\n{len(results) - fails}/{len(results)} casos ok")
sys.exit(1 if fails else 0)
