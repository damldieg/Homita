#!/usr/bin/env python3
"""Migra una base SQLite de Planify-Backend a Supabase (Postgres) vía PostgREST.

Crea los usuarios en Supabase Auth (admin API; hash bcrypt $2y$ normalizado a $2a$, mismo bcrypt) e
inserta las filas con sus ids originales en orden de claves foráneas. Idempotente: re-ejecutar no
cambia nada (upsert `Prefer: resolution=merge-duplicates` por id o por PK compuesta; las 5 tablas de
PK compuesta no tienen id, igual que en SQLite).

Interacción trigger/ids (R1-04): si el trigger de 0004 ya creó una fila app_user para el auth_uid del
usuario, se ELIMINA antes de insertar la fila con el id legado (sin colisión de UNIQUE(auth_uid) ni
de PK). Al final, admin_bump_sequences() avanza las secuencias para que los ids futuros continúen
tras max(id).

Fallback documentado: si GoTrue rechaza el hash, el usuario se crea sin contraseña y se imprime la
lista de reseteo.

Variables de entorno: SUPABASE_URL y SUPABASE_SERVICE_ROLE_KEY.
Uso: python3 scripts/supabase/migrate_sqlite.py [ruta-al.sqlite]   (por defecto api/db/database.sqlite)
"""
import json
import os
import sqlite3
import sys
import urllib.error
import urllib.parse
import urllib.request

URL = os.environ.get("SUPABASE_URL", "").rstrip("/")
KEY = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
DB = sys.argv[1] if len(sys.argv) > 1 else "api/db/database.sqlite"

if not URL or not KEY:
    sys.exit("Faltan SUPABASE_URL y/o SUPABASE_SERVICE_ROLE_KEY")

# Orden de claves foráneas (el plan: app_user se gestiona aparte por Auth)
TABLES = [
    ("calendar", "id", ["id", "name", "color", "token", "created_at", "updated_at"], [], []),
    ("routine", "id", ["id", "calendar_id", "title", "days", "time", "start_date", "end_date",
                       "active", "available_from", "frequency", "interval", "created_at", "updated_at"],
     ["active"], ["days"]),
    ("task_list", "id", ["id", "name", "color", "token", "sort", "created_at", "updated_at"], [], []),
    ("person", "id", ["id", "user_id", "name", "color", "created_at", "updated_at"], [], []),
    ("calendar_user", "id", ["id", "calendar_id", "user_id", "role", "created_at", "widget", "dashboard"],
     ["widget", "dashboard"], []),
    ("task_list_user", "id", ["id", "task_list_id", "user_id", "role", "created_at", "widget", "dashboard"],
     ["widget", "dashboard"], []),
    ("task", "id", ["id", "task_list_id", "title", "completed_at", "created_at", "updated_at", "order"], [], []),
    ("event", "id", ["id", "calendar_id", "title", "date_at", "created_at", "updated_at", "routine_id", "routine_date"], [], []),
    ("event_user", "id", ["id", "event_id", "user_id", "alarm", "created_at", "updated_at"], [], []),
    ("routine_user", "routine_id,user_id", ["routine_id", "user_id", "alarm"], [], []),
    ("routine_exception", "routine_id,routine_date", ["routine_id", "routine_date", "title", "date_at", "cancelled"],
     ["cancelled"], []),
    ("routine_event_alarm", "routine_id,routine_date,user_id", ["routine_id", "routine_date", "user_id", "alarm"], [], []),
    ("event_person", "event_id,person_id", ["event_id", "person_id"], [], []),
    ("routine_person", "routine_id,person_id", ["routine_id", "person_id"], [], []),
]


def call(method, path, body=None, prefer=None, raw_error=False):
    headers = {"apikey": KEY, "Authorization": "Bearer " + KEY, "Content-Type": "application/json"}
    if prefer:
        headers["Prefer"] = prefer
    req = urllib.request.Request(URL + path, data=json.dumps(body).encode() if body is not None else None,
                                 method=method, headers=headers)
    try:
        with urllib.request.urlopen(req) as r:
            text = r.read().decode()
            return (r.status, text) if raw_error else (json.loads(text) if text else None)
    except urllib.error.HTTPError as e:
        text = e.read().decode()
        if raw_error:
            return e.code, text
        sys.exit(f"{method} {path} → {e.code}: {text[:300]}")


def upsert(table, rows, conflict):
    for i in range(0, len(rows), 500):
        call("POST", f"/rest/v1/{table}?on_conflict={conflict}", rows[i:i + 500],
             prefer="resolution=merge-duplicates")


def find_auth_user(email):
    for page in range(1, 50):
        users = call("GET", f"/auth/v1/admin/users?per_page=500&page={page}")
        users = users["users"] if isinstance(users, dict) else users
        found = [u for u in users if u.get("email") == email]
        if found:
            return found[0]["id"]
        if len(users) < 500:
            break
    return None


def auth_user(name, email, password, sin_password):
    """auth_uid del usuario Auth. $2y$ → $2a$ (mismo bcrypt); si GoTrue lo rechaza, sin contraseña."""
    rows = call("GET", "/rest/v1/app_user?email=eq." + urllib.parse.quote(email) + "&select=auth_uid")
    if rows and rows[0]["auth_uid"]:
        return rows[0]["auth_uid"]
    hashed = password.replace("$2y$", "$2a$", 1) if password else None
    attempts = []
    if hashed:
        attempts.append({"email": email, "password_hash": {"hash": hashed, "alg": "bcrypt"},
                         "email_confirm": True, "user_metadata": {"name": name}})
        attempts.append({"email": email, "password_hash": hashed, "hasher": "bcrypt",
                         "email_confirm": True, "user_metadata": {"name": name}})
    attempts.append({"email": email, "email_confirm": True, "user_metadata": {"name": name}})
    for n, attempt in enumerate(attempts):
        status, text = call("POST", "/auth/v1/admin/users", attempt, raw_error=True)
        if status in (200, 201):
            if "password_hash" not in attempt:
                sin_password.append(email)
            return json.loads(text)["id"]
        if "already" in text.lower():
            uid = find_auth_user(email)
            if uid:
                return uid
            sys.exit(f"No encuentro el usuario Auth ya registrado: {email}")
        if n == len(attempts) - 1:
            sys.exit(f"POST /auth/v1/admin/users → {status}: {text[:300]}")
    return None


def app_user(row, uid):
    """Fila app_user con el id legado. Elimina antes la que hubiera creado el trigger 0004 para ese
    auth_uid si lleva otro id (doble defensa de R1-04) e inserta/actualiza la fila legada."""
    rows = call("GET", f"/rest/v1/app_user?auth_uid=eq.{uid}&select=id")
    if rows and rows[0]["id"] != row["id"]:
        call("DELETE", f"/rest/v1/app_user?auth_uid=eq.{uid}")
    upsert("app_user", [{"id": row["id"], "auth_uid": uid, "name": row["name"], "email": row["email"],
                         "created_at": row["created_at"], "updated_at": row["updated_at"]}], "id")


def convert(row, cols, bools, jsons):
    out = {}
    for c in cols:
        v = row[c]
        if c in bools:
            v = bool(v)
        elif c in jsons:
            v = json.loads(v)
        out[c] = v
    return out


if not os.path.exists(DB):
    sys.exit(f"No está la base SQLite: {DB}")

con = sqlite3.connect(DB)
con.row_factory = sqlite3.Row

sin_password = []
for u in con.execute("select * from user order by id"):
    uid = auth_user(u["name"], u["email"], u["password"], sin_password)
    app_user(u, uid)

total = {"user": con.execute("select count(*) from user").fetchone()[0]}
for table, conflict, cols, bools, jsons in TABLES:
    rows = [convert(r, cols, bools, jsons) for r in con.execute(f"select * from {table}")]
    upsert(table, rows, conflict)
    total[table] = len(rows)

call("POST", "/rest/v1/rpc/admin_bump_sequences", {})

for table, n in total.items():
    print(f"{table}: {n}")
if sin_password:
    print("\nFallback sin contraseña (enviar reseteo a): " + ", ".join(sin_password))
print("ok: migración aplicada (secuencias avanzadas)")
