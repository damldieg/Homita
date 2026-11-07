#!/usr/bin/env python3
"""Orden de inserción de la materialización con `routine_exception` (R1-12): PHP inserta las fechas
coincidentes ascendentes y las claves NUEVAS de `routine_exception` AL FINAL (`Routine.php:150-160,
190-192`); el port debe dar el mismo orden o los `event.id` materializados divergen del contrato.

Escenario (API PHP como oráculo): rutina weekly [1,3,5] → se mueve una ocurrencia (crea
`routine_exception`) → se desactiva la rutina (borra sus eventos futuros; la excepción sobrevive) →
se reactiva con days [6,7]: la `routine_date` de la excepción ya no coincide y PHP la inserta la
última. El port replica el estado final copiando routine/routine_user/routine_exception al Supabase
y llamando a `materialize_routines_for`; se compara el orden de inserción (fechas ordenadas por
`event.id`) y los valores de las filas.

Variables de entorno: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, CONTRACT_PHP_URL y
SUPABASE_FUNCTIONS_URL (defaults = stack local). Requiere el backend PHP de demo en marcha con
`scripts/demo/seed.py` y el dataset `seed_supabase.py` en Supabase (usuario 1, calendario 1).
Se lee la BD SQLite del demo en solo lectura; ejecutar desde la raíz del repo.

Uso: python3 scripts/supabase/fixture_exception_order.py
"""
import datetime
import json
import os
import sqlite3
import sys
import urllib.request

PHP = os.environ.get("CONTRACT_PHP_URL", "http://127.0.0.1:3001").rstrip("/")
FN = os.environ.get("SUPABASE_FUNCTIONS_URL", "http://127.0.0.1:54321/functions/v1/api").rstrip("/")
URL = os.environ.get("SUPABASE_URL", "http://127.0.0.1:54321").rstrip("/")
KEY = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
AUTH = {"email": "demo@homita.example", "password": "demo1234"}
TZ = "Europe/Madrid"
T = datetime.date.today()
WIN1 = int(datetime.datetime(T.year, T.month, T.day, 0, 0, 0).replace(tzinfo=datetime.timezone.utc).timestamp()) - 10 * 86400
WIN2 = WIN1 + 110 * 86400

if not KEY:
    sys.exit("Falta SUPABASE_SERVICE_ROLE_KEY")


def php_call(method, path, data=None, tok=None):
    req = urllib.request.Request(PHP + path, data=json.dumps(data or {}).encode(), method=method,
                                 headers={"Content-Type": "application/json", **({"Authorization": "Bearer " + tok} if tok else {})})
    with urllib.request.urlopen(req) as r:
        return json.load(r)


def svc_call(method, path, body=None):
    req = urllib.request.Request(URL + path, data=json.dumps(body).encode() if body is not None else None, method=method,
                                 headers={"apikey": KEY, "Authorization": "Bearer " + KEY, "Content-Type": "application/json"})
    with urllib.request.urlopen(req) as r:
        text = r.read()
        return json.loads(text) if text else None


def fn_call(method, path, tok=None, body=None):
    req = urllib.request.Request(FN + path, data=json.dumps(body).encode() if body is not None else None, method=method,
                                 headers={"Content-Type": "application/json", **({"Authorization": "Bearer " + tok} if tok else {})})
    with urllib.request.urlopen(req) as r:
        return json.load(r)


# --- PHP (oráculo): rutina weekly [1,3,5] con una excepción movida, borrado por desactivación y
# reactivación con days [6,7] → la clave de la excepción se inserta AL FINAL en PHP -----------------
tok = php_call("POST", "/user/auth", AUTH)["token"]
start = str(T - datetime.timedelta(days=40))
rid = php_call("POST", f"/routine/create?timezone={TZ}", {
    "calendar_id": 1, "title": "Orden excepción", "days": [1, 3, 5], "time": "23:59",
    "start_date": start, "active": True, "frequency": "weekly", "interval": 1}, tok)["id"]
evs = [e for e in php_call("GET", f"/event?start_date={WIN1}&end_date={WIN2}&routine=true&timezone={TZ}&dashboard=true", tok=tok)
       if e["routine_id"] == rid]
evs.sort(key=lambda e: e["date_at"])
moved = evs[0]
new_at = (datetime.date.fromisoformat(moved["routine_date"]) + datetime.timedelta(days=1)).isoformat() + " 08:00:00"
php_call("PATCH", "/event/update", {"id": moved["id"], "title": "Sesión movida", "date_at": new_at}, tok)
update = {"id": rid, "title": "Orden excepción", "frequency": "weekly", "interval": 1,
          "time": "23:59", "start_date": start, "active": True}
php_call("PATCH", f"/routine/update?timezone={TZ}", {**update, "days": [1, 3, 5], "active": False}, tok)
php_call("PATCH", f"/routine/update?timezone={TZ}", {**update, "days": [6, 7], "active": True}, tok)
php_rows = [e for e in php_call("GET", f"/event?start_date={WIN1}&end_date={WIN2}&routine=true&timezone={TZ}&dashboard=true", tok=tok)
            if e["routine_id"] == rid]
print(f"rutina PHP id={rid} excepción: {moved['routine_date']} → {new_at}")

# --- Supabase (port): mismo estado final copiado de la BD del demo y materialización propia --------
con = sqlite3.connect("file:.demo/backend/db/database.sqlite?mode=ro", uri=True)
con.row_factory = sqlite3.Row
routine = dict(con.execute("select * from routine where id = ?", (rid,)).fetchone())
routine["days"] = json.loads(routine["days"])
routine["active"] = bool(routine["active"])
rusers = [dict(r) for r in con.execute("select * from routine_user where routine_id = ?", (rid,))]
rex = [dict(r) for r in con.execute("select * from routine_exception where routine_id = ?", (rid,))]
for r in rex:
    r["cancelled"] = bool(r["cancelled"])
con.close()
svc_call("POST", "/rest/v1/routine", [routine])
svc_call("POST", "/rest/v1/routine_user", rusers)
svc_call("POST", "/rest/v1/routine_exception", rex)
svc_call("POST", "/rest/v1/rpc/materialize_routines_for", {"p_user_id": 1, "p_timezone": TZ})
fn_tok = fn_call("POST", "/user/auth", None, AUTH)["token"]
sb_rows = [e for e in fn_call("GET", f"/event?start_date={WIN1}&end_date={WIN2}&routine=true&timezone={TZ}&dashboard=true", fn_tok)
           if e["routine_id"] == rid]

# --- Comparación: orden de inserción (fechas según event.id) y valores -----------------------------
order_php = [e["routine_date"] for e in sorted(php_rows, key=lambda e: e["id"])]
order_sb = [e["routine_date"] for e in sorted(sb_rows, key=lambda e: e["id"])]
values = lambda rows: sorted((e["title"], e["date_at"], e["routine_date"], e["alarm"]) for e in rows)
ok_values = values(php_rows) == values(sb_rows)
ok_order = order_php == order_sb
print("PHP  (por id):", order_php)
print("SB   (por id):", order_sb)
print(f"PHP: {len(php_rows)} filas | Supabase: {len(sb_rows)} filas")
if ok_values and ok_order:
    print("EXCEPCION-ORDEN-OK (claves de excepción al final, ids materializados en orden PHP)")
    sys.exit(0)
if not ok_values:
    for x in sorted(set(map(str, values(php_rows))) ^ set(map(str, values(sb_rows)))):
        print("  diff valor:", x)
if not ok_order:
    print("  diff orden: PHP", order_php, "≠ Supabase", order_sb)
sys.exit(1)
