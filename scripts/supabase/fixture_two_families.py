#!/usr/bin/env python3
"""Seed de prueba de 2 familias para verificar RLS (AC4): usuarios Auth A/B en familias distintas
(conjuntos de calendario disjuntos, como define Person::VISIBLE) y datos marcados por familia en las
15 tablas. Idempotente: dos ejecuciones dejan las filas idénticas (timestamps fijos, upsert por id).

Variables de entorno: SUPABASE_URL y SUPABASE_SERVICE_ROLE_KEY (service_role + admin API).
Uso: python3 scripts/supabase/fixture_two_families.py
"""
import json
import os
import sys
import urllib.error
import urllib.request

URL = os.environ.get("SUPABASE_URL", "").rstrip("/")
KEY = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
TS = "2026-01-01 00:00:00"  # timestamps fijos: re-ejecutar no cambia nada

if not URL or not KEY:
    sys.exit("Faltan SUPABASE_URL y/o SUPABASE_SERVICE_ROLE_KEY")


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


def auth_user(base, name, email, password):
    """auth_uid del usuario Auth, creándolo si hace falta (ya registrado → se reutiliza)."""
    row = call("GET", f"/rest/v1/app_user?id=eq.{base}&select=auth_uid")
    if row and row[0]["auth_uid"]:
        return row[0]["auth_uid"]
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


def app_user(base, uid, name, email):
    """Fila app_user con id fijo. Elimina antes la que hubiera creado el trigger 0004 para ese
    auth_uid si lleva otro id (doble defensa de R1-04) y fija la fila con timestamps constantes."""
    rows = call("GET", f"/rest/v1/app_user?auth_uid=eq.{uid}&select=id")
    if rows and rows[0]["id"] != base:
        call("DELETE", f"/rest/v1/app_user?auth_uid=eq.{uid}")
    upsert("app_user", [{"id": base, "auth_uid": uid, "name": name, "email": email,
                         "created_at": TS, "updated_at": TS}], "id")


def family(base, letra, email, password):
    name = f"Familia {letra}"
    uid = auth_user(base, name, email, password)
    app_user(base, uid, name, email)
    upsert("calendar", [{"id": base, "name": f"Calendario {letra}", "color": "#6923E2",
                         "token": f"fixture-cal-{letra.lower()}", "created_at": TS, "updated_at": TS}], "id")
    upsert("person", [{"id": base, "user_id": base, "name": f"Persona {letra}", "color": "#2563EB",
                       "created_at": TS, "updated_at": TS}], "id")
    upsert("task_list", [{"id": base, "name": f"Lista {letra}", "color": "#F59E0B",
                          "token": f"fixture-list-{letra.lower()}", "sort": "updated_at",
                          "created_at": TS, "updated_at": TS}], "id")
    upsert("calendar_user", [{"id": base, "calendar_id": base, "user_id": base, "role": "owner",
                              "created_at": TS, "widget": True, "dashboard": True}], "id")
    upsert("task_list_user", [{"id": base, "task_list_id": base, "user_id": base, "role": "owner",
                               "created_at": TS, "widget": True, "dashboard": True}], "id")
    upsert("event", [{"id": base, "calendar_id": base, "title": f"Evento {letra} uno",
                      "date_at": "2026-06-01 10:00:00", "created_at": TS, "updated_at": TS},
                     {"id": base + 1, "calendar_id": base, "title": f"Evento {letra} dos",
                      "date_at": "2026-06-02 10:00:00", "created_at": TS, "updated_at": TS}], "id")
    upsert("event_user", [{"id": base, "event_id": base, "user_id": base, "alarm": 10,
                           "created_at": TS, "updated_at": TS}], "id")
    upsert("routine", [{"id": base, "calendar_id": base, "title": f"Rutina {letra}", "days": [1, 3],
                        "time": "09:00", "start_date": "2026-06-01", "end_date": "2026-06-30",
                        "active": True, "available_from": "2026-06-01 00:00:00",
                        "frequency": "weekly", "interval": 1, "created_at": TS, "updated_at": TS}], "id")
    upsert("routine_user", [{"routine_id": base, "user_id": base, "alarm": 20}], "routine_id,user_id")
    upsert("routine_exception", [{"routine_id": base, "routine_date": "2026-06-08",
                                  "title": f"Rutina {letra} (excepción)",
                                  "date_at": "2026-06-08 11:00:00", "cancelled": False}],
           "routine_id,routine_date")
    upsert("routine_event_alarm", [{"routine_id": base, "routine_date": "2026-06-08",
                                    "user_id": base, "alarm": 30}], "routine_id,routine_date,user_id")
    upsert("event_person", [{"event_id": base, "person_id": base}], "event_id,person_id")
    upsert("routine_person", [{"routine_id": base, "person_id": base}], "routine_id,person_id")
    upsert("task", [{"id": base, "task_list_id": base, "title": f"Tarea {letra} uno",
                     "completed_at": None, "order": 1, "created_at": TS, "updated_at": TS},
                    {"id": base + 1, "task_list_id": base, "title": f"Tarea {letra} dos",
                     "completed_at": None, "order": 2, "created_at": TS, "updated_at": TS}], "id")


family(900001, "A", "a@fixture.homita.example", "fixtureA1234")
family(910001, "B", "b@fixture.homita.example", "fixtureB1234")
print("ok: familias A (a@fixture.homita.example) y B (b@fixture.homita.example)")
