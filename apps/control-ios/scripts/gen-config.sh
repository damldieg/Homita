#!/bin/bash
# gen-config.sh <prod|local> — genera el xcconfig de Control iOS para ese entorno.
#
#   prod   → apps/control-ios/Config.prod.xcconfig, desde ~/.homita/supabase.env (producción).
#            Lo usa Release (archive).
#   local  → apps/control-ios/Config.local.xcconfig, desde `supabase status` del stack local
#            (127.0.0.1:54321). Lo usa Debug (simulador y pruebas).
#
# Nunca imprime valores (sin set -x ni echo de credenciales); salida con permisos 600.
# Ambos ficheros generados están git-ignorados: la URL y la clave solo entran por aquí.
set -euo pipefail

MODE="${1:-}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="${SCRIPT_DIR}/.."

case "$MODE" in
    prod)
        ENV_FILE="${HOME}/.homita/supabase.env"
        OUT="${APP_DIR}/Config.prod.xcconfig"

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
            *) echo "error: prod exige SUPABASE_URL https://" >&2; exit 1 ;;
        esac
        supabase_url="$SUPABASE_URL"
        anon_key="$SUPABASE_ANON_KEY"
        ;;

    local)
        OUT="${APP_DIR}/Config.local.xcconfig"

        if ! command -v supabase >/dev/null 2>&1; then
            echo "error: falta la CLI de Supabase (brew install supabase/tap/supabase)" >&2
            exit 1
        fi

        status="$(supabase status -o env 2>/dev/null)" || {
            echo "error: el stack local no responde (ejecuta supabase start)" >&2
            exit 1
        }
        # `|| true`: con pipefail, un grep sin coincidencias mataría el script sin mensaje.
        supabase_url="$(printf '%s\n' "$status" | grep '^API_URL=' | cut -d= -f2- | tr -d '"' || true)"
        anon_key="$(printf '%s\n' "$status" | grep '^ANON_KEY=' | cut -d= -f2- | tr -d '"' || true)"

        if [ -z "$supabase_url" ] || [ -z "$anon_key" ]; then
            echo "error: supabase status no devolvió API_URL o ANON_KEY" >&2
            exit 1
        fi

        case "$supabase_url" in
            http://127.0.0.1:*|http://localhost:*) ;;
            *) echo "error: local exige API_URL en 127.0.0.1 o localhost" >&2; exit 1 ;;
        esac
        ;;

    *)
        echo "uso: $0 <prod|local>" >&2
        exit 2
        ;;
esac

# En xcconfig `//` inicia comentario: `https:/$()/…` expande a `https://…` en Info.plist.
# El literal `$()` se escribe entre comillas simples para que bash no lo ejecute.
scheme="${supabase_url%%://*}"
safe_supabase="${scheme}:/\$()/${supabase_url#*://}"
safe_api="${safe_supabase}/functions/v1/api"

umask 077
{
    printf '// Generado por scripts/gen-config.sh %s — NO commitear (git-ignorado).\n' "$MODE"
    printf '// Regenerar tras cambiar el origen (%s).\n' "$([ "$MODE" = prod ] && echo '~/.homita/supabase.env' || echo 'supabase status')"
    printf 'PLANIFY_BASE_URL = %s\n' "$safe_api"
    printf 'SUPABASE_URL = %s\n' "$safe_supabase"
    printf 'SUPABASE_ANON_KEY = %s\n' "$anon_key"
} > "$OUT"
chmod 600 "$OUT"

echo "OK: $OUT generado ($MODE; valores no mostrados)."
