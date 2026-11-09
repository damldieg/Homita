#!/usr/bin/env python3
"""Seed de prueba de 2 familias para verificar RLS (AC4): usuarios Auth A/B en familias distintas
(conjuntos de calendario disjuntos, como define Person::VISIBLE) y datos marcados por familia.

Modelo Home (1.3, A-15): los usuarios se dan de alta por la API (`/user/create`; el trigger 0014(a)
crea su hogar personal, membresía admin y default_home_id) y el fixture reutiliza su id y hogar —
sin DELETE de `app_user` ni upsert de usuarios con ids fijos. El contenido sí usa ids fijos (upsert
por id, timestamps constantes): dos ejecuciones dejan las filas idénticas.

Guard de seguridad (R1): SUPABASE_URL y SUPABASE_FUNCTIONS_URL deben ser locales
(127.0.0.1/localhost) o el script aborta — escribe datos marcados y jamás debe tocar el proyecto
alojado. Requiere ALLOW_REGISTRATION=true en la Edge (o usuarios preexistentes).

Variables de entorno: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, SUPABASE_FUNCTIONS_URL (defaults =
stack local). Uso: python3 scripts/supabase/fixture_two_families.py
"""
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

URL = os.environ.get("SUPABASE_URL", "http://127.0.0.1:54321").rstrip("/")
FN = os.environ.get("SUPABASE_FUNCTIONS_URL", URL + "/functions/v1/api").rstrip("/")
KEY = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
TS = "2026-01-01 00:00:00"  # timestamps fijos: re-ejecutar no cambia nada

if not KEY:
    sys.exit("Falta SUPABASE_SERVICE_ROLE_KEY")


def assert_local(url, what):
    if urllib.parse.urlparse(url).hostname not in ("127.0.0.1", "localhost"):
        sys.exit(f"{what} solo acepta hosts locales (127.0.0.1/localhost), llega {url!r}: "
                 "este fixture escribe datos marcados y jamás debe tocar el proyecto alojado")


assert_local(URL, "SUPABASE_URL")
assert_local(FN, "SUPABASE_FUNCTIONS_URL")


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


def edge(method, path, body=None):
    req = urllib.request.Request(FN + path, data=json.dumps(body).encode() if body is not None else None,
                                 method=method, headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as r:
            return r.status, json.loads(r.read().decode() or "{}")
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read().decode() or "{}")


def upsert(table, rows, conflict):
    call("POST", f"/rest/v1/{table}?on_conflict={conflict}", rows, prefer="resolution=merge-duplicates")


def api_user(name, email, password):
    """(id, home_id) del usuario por la API: /user/create (0014(a) crea su hogar) o /user/auth si
    ya existe. Sin DELETE de app_user ni ids fijos (A-15)."""
    status, body = edge("POST", "/user/create", {"name": name, "email": email, "password": password})
    if status not in (200, 201):
        status, body = edge("POST", "/user/auth", {"email": email, "password": password})
    if status not in (200, 201) or not isinstance(body, dict) or "id" not in body:
        sys.exit(f"alta/login de {email} → {status}: {str(body)[:200]} "
                 "(¿ALLOW_REGISTRATION=true en la Edge o usuario preexistente?)")
    uid = body["id"]
    rows = call("GET", f"/rest/v1/app_user?id=eq.{uid}&select=default_home_id")
    home = rows[0]["default_home_id"] if rows and rows[0].get("default_home_id") else None
    if not home:
        sys.exit(f"{email}: sin hogar personal (el trigger 0014(a) debió crearlo)")
    return uid, home


def family(base, letra, email, password):
    name = f"Familia {letra}"
    uid, home = api_user(name, email, password)
    upsert("calendar", [{"id": base, "name": f"Calendario {letra}", "color": "#6923E2",
                         "token": f"fixture-cal-{letra.lower()}", "home_id": home,
                         "created_at": TS, "updated_at": TS}], "id")
    upsert("task_list", [{"id": base, "name": f"Lista {letra}", "color": "#F59E0B",
                          "token": f"fixture-list-{letra.lower()}", "sort": "updated_at",
                          "home_id": home, "created_at": TS, "updated_at": TS}], "id")
    upsert("home_member", [{"id": base, "home_id": home, "kind": "adult", "name": f"Persona {letra}",
                            "color": "#2563EB", "app_user_id": None, "status": "active",
                            "created_by": uid, "created_at": TS, "updated_at": TS}], "id")
    upsert("person", [{"id": base, "user_id": uid, "name": f"Persona {letra}", "color": "#2563EB",
                       "home_id": home, "home_member_id": base, "created_at": TS, "updated_at": TS}],
           "id")
    upsert("calendar_user", [{"id": base, "calendar_id": base, "user_id": uid, "role": "owner",
                              "home_id": home, "created_at": TS, "widget": True, "dashboard": True}],
           "id")
    upsert("task_list_user", [{"id": base, "task_list_id": base, "user_id": uid, "role": "owner",
                               "home_id": home, "created_at": TS, "widget": True, "dashboard": True}],
           "id")
    upsert("event", [{"id": base, "calendar_id": base, "title": f"Evento {letra} uno",
                      "date_at": "2026-06-01 10:00:00", "created_at": TS, "updated_at": TS},
                     {"id": base + 1, "calendar_id": base, "title": f"Evento {letra} dos",
                      "date_at": "2026-06-02 10:00:00", "created_at": TS, "updated_at": TS}], "id")
    upsert("event_user", [{"id": base, "event_id": base, "user_id": uid, "alarm": 10,
                           "created_at": TS, "updated_at": TS}], "id")
    upsert("routine", [{"id": base, "calendar_id": base, "title": f"Rutina {letra}", "days": [1, 3],
                        "time": "09:00", "start_date": "2026-06-01", "end_date": "2026-06-30",
                        "active": True, "available_from": "2026-06-01 00:00:00",
                        "frequency": "weekly", "interval": 1, "created_at": TS, "updated_at": TS}],
           "id")
    upsert("routine_user", [{"routine_id": base, "user_id": uid, "alarm": 20}], "routine_id,user_id")
    upsert("routine_exception", [{"routine_id": base, "routine_date": "2026-06-08",
                                  "title": f"Rutina {letra} (excepción)",
                                  "date_at": "2026-06-08 11:00:00", "cancelled": False}],
           "routine_id,routine_date")
    upsert("routine_event_alarm", [{"routine_id": base, "routine_date": "2026-06-08",
                                    "user_id": uid, "alarm": 30}], "routine_id,routine_date,user_id")
    upsert("event_person", [{"event_id": base, "person_id": base}], "event_id,person_id")
    upsert("routine_person", [{"routine_id": base, "person_id": base}], "routine_id,person_id")
    upsert("task", [{"id": base, "task_list_id": base, "title": f"Tarea {letra} uno",
                     "completed_at": None, "order": 1, "created_at": TS, "updated_at": TS},
                    {"id": base + 1, "task_list_id": base, "title": f"Tarea {letra} dos",
                     "completed_at": None, "order": 2, "created_at": TS, "updated_at": TS}], "id")
    return uid, home


uid_a, home_a = family(900001, "A", "a@fixture.homita.example", "fixtureA1234")
uid_b, home_b = family(910001, "B", "b@fixture.homita.example", "fixtureB1234")
if home_a == home_b:
    sys.exit(f"los hogares de A y B coinciden ({home_a}); deben ser familias distintas")
print(f"ok: familias A (a@fixture.homita.example, home {home_a}) y B (b@fixture.homita.example, home {home_b})")
