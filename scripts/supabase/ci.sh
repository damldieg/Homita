#!/bin/bash
# Pruebas de contrato de la Edge Function `api` sobre un stack Supabase LOCAL y efímero.
# Es la misma secuencia que corre .github/workflows/edge-tests.yml, así se reproduce en local:
#
#   scripts/supabase/ci.sh
#
# Pasos:
#   1. Stack local (`supabase start`, sin studio/imgproxy/vector/logflare/mailpit) si no está levantado.
#   2. Guardas: API_URL local y la BD es `supabase/postgres:17.*`.
#   3. `scripts/demo.sh up`: db reset (migraciones) + `functions serve api` + seed. Es el único reset.
#   4. SQL (invitaciones_check, home_checks_compat, acl_can_edit_check, permisos_matriz_check),
#      contract_check.py y cross_tenant_check.py.
#      Se ejecutan todas aunque una falle; el exit final es != 0 si alguna falló.
#
# Nunca usa ~/.homita/supabase.env ni secretos: las claves son las del stack local
# (`supabase status -o env`). psql va por `docker exec` (socket Unix dentro del contenedor), que es
# lo único que aceptan las guardas de host de los tests.
#
# Variables: CI_OUT (carpeta de logs; por defecto .demo/ci), CI_SKIP_START=1 (no arranca el stack).
set -euo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$HERE"
OUT="${CI_OUT:-$HERE/.demo/ci}"
DB_CONTAINER=supabase_db_homita-api
EXCLUDE=studio,imgproxy,vector,logflare,mailpit

# Entorno heredado que podría apuntar a otra BD o alterar la ejecución: fuera.
unset PGHOST PGHOSTADDR PGSERVICE PGSERVICEFILE PGPASSFILE PGOPTIONS PGSYSCONFDIR PGPORT PGUSER \
    PGPASSWORD PGDATABASE DATABASE_URL SUPABASE_URL SUPABASE_ANON_KEY SUPABASE_SERVICE_ROLE_KEY \
    SUPABASE_FUNCTIONS_URL CONTRACT_ONLY XT_ONLY PSQL

step() { echo "==> $*"; }
fail() { echo "ci.sh: $*" >&2; exit 1; }

mkdir -p "$OUT"
rm -f "$OUT"/*.log

command -v docker >/dev/null 2>&1 || fail "falta docker"
command -v supabase >/dev/null 2>&1 || fail "falta la Supabase CLI (supabase)"
command -v python3 >/dev/null 2>&1 || fail "falta python3"
step "Supabase CLI $(supabase --version 2>/dev/null | head -1)"
if command -v psql >/dev/null 2>&1; then step "$(psql --version)"; fi

status_env() { supabase status -o env 2>/dev/null || true; }
env_value() { sed -n "s/^$1=//p" | tr -d '"' | head -1; }

if [ "${CI_SKIP_START:-}" != 1 ] && ! status_env | grep -q '^API_URL='; then
    step "supabase start -x $EXCLUDE"
    supabase start -x "$EXCLUDE"
fi

STATUS="$(status_env)"
API_URL="$(printf '%s\n' "$STATUS" | env_value API_URL)"
case "$API_URL" in
    http://127.0.0.1:*|http://localhost:*) ;;
    *) fail "API_URL no es local ('$API_URL'): no se prueba contra nada que no sea el stack local" ;;
esac

IMAGE="$(docker inspect --format '{{.Config.Image}}' "$DB_CONTAINER" 2>/dev/null)" \
    || fail "no existe el contenedor $DB_CONTAINER (¿stack levantado?)"
step "Imagen de la BD: $IMAGE"
case "$IMAGE" in
    */postgres:17.*|postgres:17.*) ;;
    *) fail "la imagen de la BD no es supabase/postgres:17.* ($IMAGE)" ;;
esac

step "scripts/demo.sh up (db reset + Edge + seed)"
# Al salir (también si una guarda aborta): logs de la Edge y estado del stack a $OUT, y se para la Edge.
collect_logs() {
    cp "$HERE/.demo/serve.log" "$OUT/serve.log" 2>/dev/null || true
    supabase status > "$OUT/supabase-status.txt" 2>&1 || true
    "$HERE/scripts/demo.sh" down >/dev/null 2>&1 || true
}
trap collect_logs EXIT
"$HERE/scripts/demo.sh" up

# Claves locales del stack (nunca de secrets ni de ~/.homita); se enmascaran en los logs de GitHub.
ANON="$(printf '%s\n' "$STATUS" | env_value ANON_KEY)"
SERVICE="$(printf '%s\n' "$STATUS" | env_value SERVICE_ROLE_KEY)"
[ -n "$ANON" ] && [ -n "$SERVICE" ] || fail "supabase status no devolvió ANON_KEY/SERVICE_ROLE_KEY"
if [ "${GITHUB_ACTIONS:-}" = true ]; then
    echo "::add-mask::$ANON"
    echo "::add-mask::$SERVICE"
fi
export SUPABASE_URL="$API_URL"
export SUPABASE_ANON_KEY="$ANON"
export SUPABASE_SERVICE_ROLE_KEY="$SERVICE"
export SUPABASE_FUNCTIONS_URL="$API_URL/functions/v1/api"
PSQL_CMD=(docker exec -i "$DB_CONTAINER" psql -U postgres -d postgres)
export PSQL="${PSQL_CMD[*]}"

FAILED=()

# run <nombre> <log> <comando…>: ejecuta, guarda la salida y anota el fallo sin cortar.
run() {
    local name="$1" log="$OUT/$2.log"
    shift 2
    step "$name"
    if ! "$@" 2>&1 | tee "$log"; then
        FAILED+=("$name")
        return 0
    fi
}

# expect_log <nombre> <log> <patrón…>: exige que cada patrón (grep -E) aparezca en el log.
expect_log() {
    local name="$1" log="$OUT/$2.log" pattern
    shift 2
    for pattern in "$@"; do
        grep -Eq -- "$pattern" "$log" || { echo "FALTA en $name: /$pattern/"; FAILED+=("$name (salida sin '$pattern')"); }
    done
}

sql() { "${PSQL_CMD[@]}" -v ON_ERROR_STOP=1 < "$1"; }

run "SQL invitaciones_check" sql-invitaciones sql "$HERE/scripts/supabase/tests/invitaciones_check.sql"
n_pat=(); for i in $(seq 1 22); do n_pat+=("ok N$i([^0-9]|\$)"); done
expect_log "SQL invitaciones_check" sql-invitaciones "${n_pat[@]}"

run "SQL home_checks_compat" sql-compat sql "$HERE/scripts/supabase/tests/home_checks_compat.sql"
v_pat=(); for v in j k l m n o p; do v_pat+=("ok V5$v([^a-z]|\$)"); done
expect_log "SQL home_checks_compat" sql-compat "${v_pat[@]}"

run "SQL acl_can_edit_check" sql-acl-can-edit sql "$HERE/scripts/supabase/tests/acl_can_edit_check.sql"
k_pat=(); for i in $(seq 1 8); do k_pat+=("ok K$i([^0-9a-z]|\$)"); done
expect_log "SQL acl_can_edit_check" sql-acl-can-edit "${k_pat[@]}"

run "SQL permisos_matriz_check" sql-permisos-matriz sql "$HERE/scripts/supabase/tests/permisos_matriz_check.sql"
# M1, M1b, M2..M27 y M8b (29 avisos): el cierre ([^0-9a-z]|$) evita que M1 case con M10 o M1b.
m_pat=("ok M1([^0-9a-z]|\$)" "ok M1b([^0-9a-z]|\$)" "ok M8b([^0-9a-z]|\$)"); for i in $(seq 2 27); do m_pat+=("ok M$i([^0-9a-z]|\$)"); done
expect_log "SQL permisos_matriz_check" sql-permisos-matriz "${m_pat[@]}"

run "contract_check.py" contract python3 "$HERE/scripts/supabase/contract_check.py"
expect_log "contract_check.py" contract '^473/473 casos ok'

run "cross_tenant_check.py" cross-tenant python3 "$HERE/scripts/supabase/tests/cross_tenant_check.py"
# N/N con N == EXPECTED_CASES (el propio script sale 1 si difiere; aquí se exige además el formato).
expected="$(sed -n 's/^EXPECTED_CASES = \([0-9]*\).*/\1/p' "$HERE/scripts/supabase/tests/cross_tenant_check.py")"
[ -n "$expected" ] || FAILED+=("cross_tenant_check.py (sin EXPECTED_CASES)")
expect_log "cross_tenant_check.py" cross-tenant "^${expected}/${expected} casos ok"

if [ "${#FAILED[@]}" -gt 0 ]; then
    echo
    echo "FALLARON ${#FAILED[@]} paso(s):"
    printf '  - %s\n' "${FAILED[@]}"
    exit 1
fi
echo
echo "ci.sh: todo ok (SQL, contract_check 473/473, cross_tenant ${expected}/${expected})"
