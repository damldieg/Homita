#!/usr/bin/env python3
"""Suite de lectura del contrato iOS contra la Edge de Supabase (solo consultas GET).

Recorre las rutas de lectura del contrato (`supabase/migrations/0005_read_rpcs.sql` y
`supabase/functions/api/usecases/*.ts`)
y valida HTTP 200, JSON y los shapes de §8 (claves, flags 0/1, fechas `Y-m-d H:i:s`).
Solo stdlib (`urllib`); sin dependencias y sin verbos de escritura en este fichero
(`grep -E '"(GET|POST|PATCH|DELETE)"|-X (POST|PATCH|DELETE)'` debe dar vacío).

Uso (creds SIEMPRE por variables de entorno, nunca en el fichero):

    export SUPABASE_FUNCTIONS_URL=https://<ref>.supabase.co/functions/v1/api
    export PLANIFY_IOS_ACCESS_TOKEN="<jwt de POST /user/auth con la cuenta de prueba>"
    python3 apps/control-ios/scripts/ios_read_suite.py

Imprime un resumen por ruta y sale con código distinto de 0 ante cualquier fallo.
No imprime payloads completos (evita datos personales en la consola).
"""

import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request

DATE_TIME_RE = re.compile(r"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$")
DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")

# Tipos de las validaciones de shape (§8 del inventario).
INT = "int"
STR = "str"
BOOL = "bool"          # bool JSON (active/editable/allow_registration)
BOOL01 = "bool01"      # flag SQLite 0/1 (widget/dashboard)
DATETIME = "datetime"  # `Y-m-d H:i:s`
DATE = "date"          # `Y-m-d`
LIST = "list"


def fail(message):
    return [message]


def check_value(value, kind, key):
    """Valida un valor contra su tipo de contrato; devuelve lista de problemas."""
    if value is None:
        return ["%s es null" % key]
    if kind == INT:
        return [] if isinstance(value, int) and not isinstance(value, bool) else ["%s no es int" % key]
    if kind == STR:
        return [] if isinstance(value, str) and value != "" else ["%s no es string no vacío" % key]
    if kind == BOOL:
        return [] if isinstance(value, bool) else ["%s no es bool" % key]
    if kind == BOOL01:
        return [] if value in (0, 1) else ["%s no es 0/1 (llega %r)" % (key, value)]
    if kind == DATETIME:
        return [] if isinstance(value, str) and DATE_TIME_RE.match(value) else ["%s no es Y-m-d H:i:s (llega %r)" % (key, value)]
    if kind == DATE:
        return [] if isinstance(value, str) and DATE_RE.match(value) else ["%s no es Y-m-d (llega %r)" % (key, value)]
    if kind == LIST:
        return [] if isinstance(value, list) else ["%s no es lista" % key]
    return ["tipo de validación desconocido: %s" % kind]


def check_entry(route, item, spec, optional):
    """Valida las claves de un elemento de la respuesta; `optional` permite null."""
    problems = []
    if not isinstance(item, dict):
        return ["%s: elemento que no es objeto" % route]
    for key, kind in spec.items():
        if key not in item:
            problems.append("%s: falta la clave %s" % (route, key))
            continue
        if item[key] is None and key in optional:
            continue
        problems.extend("%s: %s" % (route, p) for p in check_value(item[key], kind, key))
    return problems


class Suite:
    def __init__(self, base, token, timezone):
        self.base = base.rstrip("/")
        self.token = token
        self.timezone = timezone
        self.failures = 0

    def get(self, path, params=None):
        """GET al contrato con Bearer; devuelve (status, objeto JSON)."""
        url = self.base + "/" + path
        if params:
            url += "?" + urllib.parse.urlencode(params)
        request = urllib.request.Request(url, headers={
            "Accept": "application/json",
            "Authorization": "Bearer " + self.token,
        })
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                body = response.read()
                return response.status, json.loads(body)
        except urllib.error.HTTPError as error:
            try:
                payload = json.loads(error.read())
            except Exception:
                payload = {}
            return error.code, payload
        except Exception as error:
            return 0, {"error": str(error)}

    def check(self, label, path, params, spec, optional, expect_list):
        status, payload = self.get(path, params)
        problems = []
        if status != 200:
            problems.append("HTTP %s (%s)" % (status, payload.get("error", "sin error")))
        else:
            items = payload if isinstance(payload, list) else [payload]
            if expect_list and not isinstance(payload, list):
                problems.append("la respuesta no es lista")
            for item in items:
                problems.extend(check_entry(label, item, spec, optional))
        if problems:
            self.failures += 1
            print("FAIL %s — %s" % (label, "; ".join(problems[:5])))
        else:
            count = len(payload) if isinstance(payload, list) else 1
            print("OK   %s — %d elementos" % (label, count))

    def run(self):
        # Claves de §8 del inventario de contrato.
        self.check(
            "GET /config", "config", None,
            {"allow_registration": BOOL}, set(), False,
        )
        self.check(
            "GET /calendar", "calendar", None,
            {"id": INT, "name": STR, "color": STR, "widget": BOOL01, "dashboard": BOOL01,
             "upcoming_event_count": INT, "created_at": DATETIME, "updated_at": DATETIME},
            {"upcoming_event_count"}, True,
        )
        self.check(
            "GET /person", "person", None,
            {"id": INT, "user_id": INT, "name": STR, "color": STR, "editable": BOOL,
             "created_at": DATETIME},
            set(), True,
        )
        self.check(
            "GET /routine", "routine", {"timezone": self.timezone},
            {"id": INT, "calendar_id": INT, "title": STR, "days": LIST, "time": STR,
             "start_date": DATE, "end_date": DATE, "active": BOOL, "frequency": STR,
             "interval": INT, "alarm": INT, "persons": LIST, "created_at": DATETIME},
            {"end_date", "alarm"}, True,
        )
        self.check(
            "GET /event", "event", {"timezone": self.timezone},
            {"id": INT, "calendar_id": INT, "title": STR, "date_at": DATETIME,
             "routine_id": INT, "routine_date": DATE, "alarm": INT, "persons": LIST,
             "created_at": DATETIME},
            {"routine_id", "routine_date", "alarm"}, True,
        )
        self.check(
            "GET /event?routine=true", "event", {"timezone": self.timezone, "routine": "true"},
            {"id": INT, "calendar_id": INT, "title": STR, "date_at": DATETIME,
             "routine_id": INT, "routine_date": DATE, "alarm": INT},
            {"routine_id", "routine_date", "alarm"}, True,
        )
        self.check(
            "GET /task-list", "task-list", None,
            {"id": INT, "name": STR, "color": STR, "sort": STR, "widget": BOOL01,
             "dashboard": BOOL01, "pending_task_count": INT, "created_at": DATETIME},
            {"pending_task_count"}, True,
        )
        self.check(
            "GET /task", "task", None,
            {"id": INT, "task_list_id": INT, "title": STR, "completed_at": DATETIME,
             "order": INT, "created_at": DATETIME},
            {"completed_at", "order"}, True,
        )
        if self.failures:
            print("Resultado: %d rutas con fallo" % self.failures)
            return 1
        print("Resultado: todas las rutas OK")
        return 0


def main():
    base = os.environ.get("SUPABASE_FUNCTIONS_URL", "").strip()
    token = os.environ.get("PLANIFY_IOS_ACCESS_TOKEN", "").strip()
    timezone = os.environ.get("PLANIFY_IOS_TIMEZONE", "").strip()
    if not base:
        print("error: falta SUPABASE_FUNCTIONS_URL (…/functions/v1/api)", file=sys.stderr)
        return 2
    if not token:
        print("error: falta PLANIFY_IOS_ACCESS_TOKEN (jwt de user/auth)", file=sys.stderr)
        return 2
    if not timezone:
        import time as _time
        timezone = _time.tzname[0] if _time.tzname else "UTC"
        # Zona IANA por defecto: la del sistema si `tzname` no basta; se puede fijar por env.
        timezone = os.environ.get("TZ", timezone)
    return Suite(base, token, timezone).run()


if __name__ == "__main__":
    sys.exit(main())
