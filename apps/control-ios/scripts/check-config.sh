#!/bin/bash
# check-config.sh — fail-fast (equivalente de `checkPlanifyBaseUrl` del dashboard).
#
# Elige el xcconfig según la configuración de build que Xcode pasa en $CONFIGURATION:
#   Debug   → Config.local.xcconfig  (debe apuntar a 127.0.0.1 o localhost)
#   Release → Config.prod.xcconfig   (debe ser https y NO apuntar a local)
# Exige PLANIFY_BASE_URL, SUPABASE_URL y SUPABASE_ANON_KEY reales (sin placeholders ni vacíos).
# Úsalo como Run Script del target de la app.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="${SCRIPT_DIR}/.."

case "${CONFIGURATION:-}" in
    Debug)   CONF="${APP_DIR}/Config.local.xcconfig"; ENV_KIND=local ;;
    Release) CONF="${APP_DIR}/Config.prod.xcconfig";  ENV_KIND=prod ;;
    *)
        echo "error: CONFIGURATION='${CONFIGURATION:-}' sin xcconfig asignado (esperado Debug o Release)" >&2
        exit 1
        ;;
esac
NAME="$(basename "$CONF")"
HINT="ejecuta apps/control-ios/scripts/gen-config.sh $ENV_KIND"

if [ ! -f "$CONF" ]; then
    echo "error: falta $NAME ($HINT)" >&2
    exit 1
fi

if grep -q '<' "$CONF"; then
    echo "error: $NAME contiene placeholders ($HINT)" >&2
    exit 1
fi

for key in PLANIFY_BASE_URL SUPABASE_URL SUPABASE_ANON_KEY; do
    value="$(sed -n "s/^${key}[[:space:]]*=[[:space:]]*//p" "$CONF" | tr -d '[:space:]')"
    if [ -z "$value" ]; then
        echo "error: $key vacío en $NAME ($HINT)" >&2
        exit 1
    fi
done

# Misma guarda para las dos URLs: PLANIFY_BASE_URL y SUPABASE_URL no pueden apuntar a hosts distintos del entorno.
for key in PLANIFY_BASE_URL SUPABASE_URL; do
    url="$(sed -n "s/^${key}[[:space:]]*=[[:space:]]*//p" "$CONF" | tr -d '[:space:]')"
    case "$ENV_KIND" in
        local)
            case "$url" in
                http:/\$\(\)/127.0.0.1:*|http:/\$\(\)/localhost:*) ;;
                *) echo "error: Debug debe apuntar al stack local, pero $key en $NAME apunta a otro host ($HINT)" >&2; exit 1 ;;
            esac
            ;;
        prod)
            case "$url" in
                https:/\$\(\)/*) ;;
                *) echo "error: Release exige https, pero $key en $NAME no lo cumple ($HINT)" >&2; exit 1 ;;
            esac
            case "$url" in
                *127.0.0.1*|*localhost*) echo "error: Release no puede apuntar a un host local ($key en $NAME)" >&2; exit 1 ;;
            esac
            ;;
    esac
done

echo "OK: $NAME presente, completo y coherente con $CONFIGURATION."
