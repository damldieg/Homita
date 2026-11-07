"""Datos ficticios para la demo de Supabase (scripts/demo.sh con DEMO_BASE_URL): el MISMO dataset que
scripts/demo/seed.py — una familia con 4 personas, 2 calendarios, eventos alrededor de hoy, rutinas de
lunes a viernes y 2 listas de tareas — insertado con service_role + admin API y con ids deterministas
(1..N en el mismo orden de creación que seed.py) para poder comparar contratos. Las fechas son
relativas al día en que se ejecuta. Al final llama a materialize_routines_for (como hace
Routine::create al insertar cada rutina en el PHP) para materializar las sesiones igual que el backend.

Variables de entorno: SUPABASE_URL y SUPABASE_SERVICE_ROLE_KEY.
Uso: python3 scripts/demo/seed_supabase.py
"""
import datetime
import json
import os
import sys
import urllib.error
import urllib.request
import zoneinfo

URL = os.environ.get("SUPABASE_URL", "").rstrip("/")
KEY = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
T = datetime.date.today()
TS = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d %H:%M:%S")
AVAILABLE_FROM = datetime.datetime.now(zoneinfo.ZoneInfo("Europe/Madrid")).strftime("%Y-%m-%d %H:%M:%S")
TZ = "Europe/Madrid"

if not URL or not KEY:
    sys.exit("Faltan SUPABASE_URL y/o SUPABASE_SERVICE_ROLE_KEY")


def d(n, hm):
    return f"{T + datetime.timedelta(days=n)} {hm}:00"


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
    call("POST", f"/rest/v1/{table}?on_conflict={conflict}", rows, prefer="resolution=merge-duplicates")


def auth_user(name, email, password):
    """auth_uid del usuario Auth, creándolo si hace falta (ya registrado → se reutiliza)."""
    rows = call("GET", "/rest/v1/app_user?id=eq.1&select=auth_uid")
    if rows and rows[0]["auth_uid"]:
        return rows[0]["auth_uid"]
    status, text = call("POST", "/auth/v1/admin/users",
                        {"email": email, "password": password, "email_confirm": True,
                         "user_metadata": {"name": name}}, raw_error=True)
    if status in (200, 201):
        return json.loads(text)["id"]
    if "already" not in text.lower():
        sys.exit(f"POST /auth/v1/admin/users → {status}: {text[:300]}")
    for page in range(1, 50):
        users = call("GET", f"/auth/v1/admin/users?per_page=500&page={page}")
        users = users["users"] if isinstance(users, dict) else users
        found = [u for u in users if u.get("email") == email]
        if found:
            return found[0]["id"]
        if len(users) < 500:
            break
    sys.exit(f"No encuentro el usuario Auth ya registrado: {email}")


uid = auth_user("Familia Demo", "demo@homita.example", "demo1234")

# app_user con id legado (R1-04): eliminar antes la fila que hubiera creado el trigger 0004 si
# lleva otro id, y fijar la fila legada (id, auth_uid, name, email, timestamps)
rows = call("GET", f"/rest/v1/app_user?auth_uid=eq.{uid}&select=id")
if rows and rows[0]["id"] != 1:
    call("DELETE", f"/rest/v1/app_user?auth_uid=eq.{uid}")
upsert("app_user", [{"id": 1, "auth_uid": uid, "name": "Familia Demo",
                     "email": "demo@homita.example", "created_at": TS, "updated_at": TS}], "id")

upsert("calendar", [{"id": 1, "name": "Familia", "color": "#6923E2", "token": "demo-cal-familia",
                     "created_at": TS, "updated_at": TS},
                    {"id": 2, "name": "Colegio", "color": "#0EA5E9", "token": "demo-cal-colegio",
                     "created_at": TS, "updated_at": TS}], "id")

P = {}
for pid, (n, c) in enumerate([("Ana", "#2563EB"), ("Marcos", "#16A34A"), ("Lucía", "#9333EA"), ("Pablo", "#EA580C")], 1):
    P[n] = pid
upsert("person", [{"id": pid, "user_id": 1, "name": n, "color": c, "created_at": TS, "updated_at": TS}
                  for pid, (n, c) in enumerate([("Ana", "#2563EB"), ("Marcos", "#16A34A"),
                                                ("Lucía", "#9333EA"), ("Pablo", "#EA580C")], 1)], "id")

upsert("task_list", [{"id": 1, "name": "Compra", "color": "#F59E0B", "token": "demo-list-compra",
                      "sort": "updated_at", "created_at": TS, "updated_at": TS},
                     {"id": 2, "name": "Casa", "color": "#10B981", "token": "demo-list-casa",
                      "sort": "updated_at", "created_at": TS, "updated_at": TS}], "id")

upsert("calendar_user", [{"id": 1, "calendar_id": 1, "user_id": 1, "role": "owner", "created_at": TS,
                          "widget": True, "dashboard": True},
                         {"id": 2, "calendar_id": 2, "user_id": 1, "role": "owner", "created_at": TS,
                          "widget": True, "dashboard": True}], "id")
upsert("task_list_user", [{"id": 1, "task_list_id": 1, "user_id": 1, "role": "owner", "created_at": TS,
                           "widget": True, "dashboard": True},
                          {"id": 2, "task_list_id": 2, "user_id": 1, "role": "owner", "created_at": TS,
                           "widget": True, "dashboard": True}], "id")

for tid, (lid, t) in enumerate([(1, "Leche"), (1, "Pan"), (1, "Huevos"), (1, "Fruta"), (1, "Café"),
                                (2, "Cambiar la bombilla del pasillo"), (2, "Llamar al fontanero"),
                                (2, "Regar las plantas")], 1):
    pass  # se insertan abajo con su `order` por lista

tasks = []
order = {}
for lid, t in [(1, "Leche"), (1, "Pan"), (1, "Huevos"), (1, "Fruta"), (1, "Café"),
               (2, "Cambiar la bombilla del pasillo"), (2, "Llamar al fontanero"), (2, "Regar las plantas")]:
    order[lid] = order.get(lid, 0) + 1
    tasks.append({"id": len(tasks) + 1, "task_list_id": lid, "title": t, "completed_at": None,
                  "order": order[lid], "created_at": TS, "updated_at": TS})
upsert("task", tasks, "id")

EVENTS = [
    (1, "Revisión médica", d(-12, "10:00"), ["Marcos"]),
    (2, "Tutoría", d(-8, "17:00"), ["Ana"]),
    (1, "Cumpleaños del abuelo", d(-5, "13:30"), []),
    (1, "Mercadillo", d(-2, "11:00"), ["Lucía", "Pablo"]),
    (1, "Desayuno con la vecina", d(0, "09:00"), ["Ana"]),
    (1, "Cena con los abuelos", d(0, "20:30"), ["Ana", "Marcos"]),
    (1, "Dentista", d(1, "17:00"), ["Lucía"]),
    (1, "Partido de fútbol", d(2, "10:30"), ["Pablo"]),
    (1, "Comida familiar", d(3, "14:00"), []),
    (1, "Revisión del coche", d(5, "09:00"), ["Marcos"]),
    (2, "Reunión de padres", d(6, "18:00"), ["Ana"]),
    (1, "Cumpleaños de Lucía", d(7, "17:30"), ["Lucía"]),
    (2, "Excursión al museo", d(8, "09:30"), ["Pablo"]),
    (1, "Cine en familia", d(9, "19:00"), []),
]
upsert("event", [{"id": i, "calendar_id": cal, "title": title, "date_at": at,
                  "created_at": TS, "updated_at": TS}
                 for i, (cal, title, at, _) in enumerate(EVENTS, 1)], "id")
upsert("event_person", [{"event_id": i, "person_id": P[w]} for i, (_, _, _, who) in enumerate(EVENTS, 1)
                        for w in who], "event_id,person_id")

ROUTINES = [
    ("Recoger a los niños", [1, 2, 3, 4, 5], "16:00", ["Ana"]),
    ("Piano", [4], "16:45", ["Lucía"]),
    ("Natación", [2, 4], "18:00", ["Pablo"]),
    ("Inglés", [1, 3], "17:30", ["Lucía"]),
    ("Fútbol", [5], "17:00", ["Pablo"]),
    ("Sacar al perro", [1, 2, 3, 4, 5, 6, 7], "19:30", ["Marcos"]),
    ("Paseo en bici", [6, 7], "11:00", ["Pablo"]),
]
upsert("routine", [{"id": i, "calendar_id": 2, "title": title, "days": days, "time": time,
                    "start_date": str(T - datetime.timedelta(days=30)), "end_date": None,
                    "active": True, "available_from": AVAILABLE_FROM,
                    "frequency": "weekly", "interval": 1, "created_at": TS, "updated_at": TS}
                   for i, (title, days, time, _) in enumerate(ROUTINES, 1)], "id")
upsert("routine_user", [{"routine_id": i, "user_id": 1, "alarm": None} for i in range(1, len(ROUTINES) + 1)],
       "routine_id,user_id")
upsert("routine_person", [{"routine_id": i, "person_id": P[w]} for i, (_, _, _, who) in enumerate(ROUTINES, 1)
                          for w in who], "routine_id,person_id")

# Cierre de la importación (igual que migrate_sqlite.py): avanzar las secuencias tras los ids
# explícitos y materializar las sesiones, igual que Routine::create en el PHP
call("POST", "/rest/v1/rpc/admin_bump_sequences", {})
call("POST", "/rest/v1/rpc/materialize_routines_for", {"p_user_id": 1, "p_timezone": TZ})

n = call("GET", "/rest/v1/event?select=id&routine_id=is.null")
print("ok", len(n), "eventos")
