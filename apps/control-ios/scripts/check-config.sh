#!/bin/bash
# check-config.sh — fail-fast (equivalente de `checkPlanifyBaseUrl` del dashboard):
# exige Config.xcconfig con PLANIFY_BASE_URL/SUPABASE_URL/SUPABASE_ANON_KEY reales
# (sin placeholders del .example y sin vacíos). Úsalo como Run Script del target de la app.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONF="${SCRIPT_DIR}/../Config.xcconfig"

if [ ! -f "$CONF" ]; then
    echo "error: falta Config.xcconfig (ejecuta apps/control-ios/scripts/gen-config.sh)" >&2
    exit 1
fi

if grep -q '<' "$CONF"; then
    echo "error: Config.xcconfig contiene placeholders (ejecuta apps/control-ios/scripts/gen-config.sh)" >&2
    exit 1
fi

for key in PLANIFY_BASE_URL SUPABASE_URL SUPABASE_ANON_KEY; do
    value="$(sed -n "s/^${key}[[:space:]]*=[[:space:]]*//p" "$CONF" | tr -d '[:space:]')"
    if [ -z "$value" ]; then
        echo "error: $key vacío en Config.xcconfig (ejecuta apps/control-ios/scripts/gen-config.sh)" >&2
        exit 1
    fi
done

echo "OK: Config.xcconfig presente y completo."
