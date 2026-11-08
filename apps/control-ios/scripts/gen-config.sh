#!/bin/bash
# gen-config.sh — genera apps/control-ios/Config.xcconfig desde ~/.homita/supabase.env.
# Nunca imprime valores (sin set -x ni echo de credenciales); salida con permisos 600.
# El fichero generado es git-ignorado: la URL/clave solo entran por aquí (AppConfig).
set -euo pipefail

ENV_FILE="${HOME}/.homita/supabase.env"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT="${SCRIPT_DIR}/../Config.xcconfig"

if [ ! -f "$ENV_FILE" ]; then
    echo "error: falta $ENV_FILE" >&2
    exit 1
fi

# shellcheck disable=SC1090
set -a
. "$ENV_FILE"
set +a

for var in SUPABASE_URL SUPABASE_ANON_KEY SUPABASE_PROJECT_REF; do
    if [ -z "${!var:-}" ]; then
        echo "error: falta $var en $ENV_FILE" >&2
        exit 1
    fi
done

case "$SUPABASE_URL" in
    https://*) ;;
    *) echo "error: SUPABASE_URL debe empezar por https://" >&2; exit 1 ;;
esac

# En xcconfig `//` inicia comentario: `https:/$()/…` expande a `https://…` en Info.plist.
# El literal `$()` se escribe entre comillas simples para que bash no lo ejecute.
safe_supabase='https:/$()/'"${SUPABASE_URL#https://}"
safe_api="${safe_supabase}/functions/v1/api"

umask 077
{
    printf '// Generado por scripts/gen-config.sh — NO commitear (git-ignorado).\n'
    printf '// Regenerar tras cambiar ~/.homita/supabase.env.\n'
    printf 'PLANIFY_BASE_URL = %s\n' "$safe_api"
    printf 'SUPABASE_URL = %s\n' "$safe_supabase"
    printf 'SUPABASE_ANON_KEY = %s\n' "$SUPABASE_ANON_KEY"
} > "$OUT"
chmod 600 "$OUT"

echo "OK: $OUT generado (valores no mostrados)."
