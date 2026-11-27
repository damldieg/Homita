#!/bin/bash
# Genera web/oauth/consent/config.js con la URL y la anon key del stack Supabase LOCAL (`supabase status -o env`),
# para servir la página de consentimiento del MCP en local:
#
#   scripts/oauth/local-config.sh
#   python3 -m http.server 3000 --bind 127.0.0.1 --directory web
#
# Solo claves locales y públicas (anon key): se niega si la URL no es local. config.js está en .gitignore.
set -euo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="$HERE/web/oauth/consent/config.js"

command -v supabase >/dev/null 2>&1 || { echo "local-config.sh: falta la Supabase CLI (supabase)" >&2; exit 1; }
STATUS="$(supabase status -o env 2>/dev/null || true)"
env_value() { printf '%s\n' "$STATUS" | sed -n "s/^$1=//p" | tr -d '"' | head -1; }
API_URL="$(env_value API_URL)"
ANON_KEY="$(env_value ANON_KEY)"

[ -n "$API_URL" ] && [ -n "$ANON_KEY" ] || { echo "local-config.sh: el stack local no está levantado (supabase start)" >&2; exit 1; }
case "$API_URL" in
    http://127.0.0.1:*|http://localhost:*) ;;
    *) echo "local-config.sh: API_URL no es local ('$API_URL'): no se genera config.js" >&2; exit 1 ;;
esac
# La anon key es un JWT: solo letras, cifras, '-', '_' y '.'.
case "$ANON_KEY" in
    *[!A-Za-z0-9._-]*) echo "local-config.sh: ANON_KEY con caracteres inesperados" >&2; exit 1 ;;
esac

umask 022
cat > "$OUT" <<JS
// Generado por scripts/oauth/local-config.sh con las claves del stack LOCAL. No se sube a git.
window.HOMITA_CONFIG = {
  SUPABASE_URL: "$API_URL",
  SUPABASE_ANON_KEY: "$ANON_KEY",
};
JS
echo "Escrito $OUT ($API_URL)"
