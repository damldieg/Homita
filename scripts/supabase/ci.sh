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
#   4. Deno: `deno check` y `deno test` de procesar-feedback (mocks, sin red ni permisos).
#   5. SQL (invitaciones_check, home_checks_compat, acl_can_edit_check, permisos_matriz_check,
#      client_request_check C1-C9 (0035),
#      feedback_trello_check B1-B8 (0033) y feedback_trigger_check F1-F12 (0031/0034); trigger inerte en
#      local: sin feedback_webhook_url en Vault no se encola ninguna petición),
#      contract_check.py y cross_tenant_check.py.
#   6. Ida y vuelta 0035 → rollback_0035.sql → 0035: client_request_rollback_check RB1-RB4, después
#      home_checks_compat, acl_can_edit_check, permisos_matriz_check y contract_check sobre el esquema
#      revertido, y client_request_reapply_check RA1-RA2 más client_request_check C1-C9 otra vez.
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
command -v deno >/dev/null 2>&1 || fail "falta deno"
step "Supabase CLI $(supabase --version 2>/dev/null | head -1)"
step "$(deno --version | head -1)"
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

# Edge Function procesar-feedback: tipado del cableado (index.ts, db.ts) y tests con mocks.
FEEDBACK_FN="$HERE/supabase/functions/procesar-feedback"
run "deno check procesar-feedback" deno-check env NO_COLOR=1 deno check "$FEEDBACK_FN/index.ts"
run "deno test procesar-feedback" deno-test env NO_COLOR=1 deno test --no-prompt "$FEEDBACK_FN/tests/"
expect_log "deno test procesar-feedback" deno-test '^ok \| [0-9]+ passed \| 0 failed'

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

run "SQL client_request_check" sql-client-request sql "$HERE/scripts/supabase/tests/client_request_check.sql"
c_pat=(); for i in $(seq 1 9); do c_pat+=("ok C$i([^0-9a-z]|\$)"); done
expect_log "SQL client_request_check" sql-client-request "${c_pat[@]}"

run "SQL assistant_usage_check" sql-assistant-usage sql "$HERE/scripts/supabase/tests/assistant_usage_check.sql"
u_pat=(); for i in $(seq 1 7); do u_pat+=("ok U$i([^0-9a-z]|\$)"); done
expect_log "SQL assistant_usage_check" sql-assistant-usage "${u_pat[@]}"

# Checks de feedback: psql corre dentro del contenedor y no ve el host, así que se expanden los marcadores
# `-- @MIGRATION:<fichero>@` (supabase/migrations/<fichero>) y `-- @ROLLBACK:<fichero>@`
# (scripts/supabase/rollback/<fichero>) y el resultado va por stdin. Un marcador desconocido o un
# fichero ausente o vacío aborta.
expand_sql() {
    awk -v root="$HERE" '
        function include(path,    line, n) {
            n = 0
            while ((getline line < path) > 0) { print line; n++ }
            close(path)
            if (n == 0) { print "expand_sql: no existe o está vacío: " path > "/dev/stderr"; exit 2 }
        }
        /^-- @MIGRATION:[A-Za-z0-9_.-]+@$/ { f = $0; sub(/^-- @MIGRATION:/, "", f); sub(/@$/, "", f); include(root "/supabase/migrations/" f); next }
        /^-- @ROLLBACK:[A-Za-z0-9_.-]+@$/ { f = $0; sub(/^-- @ROLLBACK:/, "", f); sub(/@$/, "", f); include(root "/scripts/supabase/rollback/" f); next }
        /^-- @/ { print "expand_sql: marcador no reconocido: " $0 > "/dev/stderr"; exit 2 }
        { print }
    ' "$1"
}
sql_expanded() {
    local expanded
    expanded="$(expand_sql "$1")" || return 1
    printf '%s\n' "$expanded" | "${PSQL_CMD[@]}" -v ON_ERROR_STOP=1
}

run "SQL feedback_trello_check" sql-feedback-trello sql_expanded "$HERE/scripts/supabase/tests/feedback_trello_check.sql"
b_pat=(); for i in $(seq 1 8); do b_pat+=("ok B$i([^0-9a-z]|\$)"); done
expect_log "SQL feedback_trello_check" sql-feedback-trello "${b_pat[@]}"

run "SQL feedback_trigger_check" sql-feedback-trigger sql_expanded "$HERE/scripts/supabase/tests/feedback_trigger_check.sql"
f_pat=(); for i in $(seq 1 12); do f_pat+=("ok F$i([^0-9a-z]|\$)"); done
expect_log "SQL feedback_trigger_check" sql-feedback-trigger "${f_pat[@]}"

run "contract_check.py" contract python3 "$HERE/scripts/supabase/contract_check.py"
expect_log "contract_check.py" contract '^502/502 casos ok'

run "cross_tenant_check.py" cross-tenant python3 "$HERE/scripts/supabase/tests/cross_tenant_check.py"
# N/N con N == EXPECTED_CASES (el propio script sale 1 si difiere; aquí se exige además el formato).
expected="$(sed -n 's/^EXPECTED_CASES = \([0-9]*\).*/\1/p' "$HERE/scripts/supabase/tests/cross_tenant_check.py")"
[ -n "$expected" ] || FAILED+=("cross_tenant_check.py (sin EXPECTED_CASES)")
expect_log "cross_tenant_check.py" cross-tenant "^${expected}/${expected} casos ok"

# Ida y vuelta 0035 → rollback_0035.sql → 0035 (R1-01): el rollback se confirma de verdad, se repasan los
# checks que tocan create_task/create_task_list sobre el esquema revertido y se vuelve a aplicar 0035
# con C1-C9 otra vez. Si el rollback falla no se sigue (los checks no dirían nada del esquema revertido).
run "SQL client_request_rollback_check" sql-rb0035 sql_expanded "$HERE/scripts/supabase/tests/client_request_rollback_check.sql"
rb_ok=1
for i in 1 2 3 4; do grep -Eq "ok RB$i([^0-9]|\$)" "$OUT/sql-rb0035.log" || rb_ok=0; done
expect_log "SQL client_request_rollback_check" sql-rb0035 'ok RB1([^0-9]|$)' 'ok RB2([^0-9]|$)' 'ok RB3([^0-9]|$)' 'ok RB4([^0-9]|$)'
if [ "$rb_ok" = 1 ]; then
    sleep 1 # notify pgrst del rollback: PostgREST recarga el esquema antes de contract_check
    run "SQL home_checks_compat (tras rollback_0035)" sql-rb0035-compat sql "$HERE/scripts/supabase/tests/home_checks_compat.sql"
    expect_log "SQL home_checks_compat (tras rollback_0035)" sql-rb0035-compat "${v_pat[@]}"
    run "SQL acl_can_edit_check (tras rollback_0035)" sql-rb0035-acl sql "$HERE/scripts/supabase/tests/acl_can_edit_check.sql"
    expect_log "SQL acl_can_edit_check (tras rollback_0035)" sql-rb0035-acl "${k_pat[@]}"
    run "SQL permisos_matriz_check (tras rollback_0035)" sql-rb0035-matriz sql "$HERE/scripts/supabase/tests/permisos_matriz_check.sql"
    expect_log "SQL permisos_matriz_check (tras rollback_0035)" sql-rb0035-matriz "${m_pat[@]}"
    run "contract_check.py (tras rollback_0035)" sql-rb0035-contract python3 "$HERE/scripts/supabase/contract_check.py"
    expect_log "contract_check.py (tras rollback_0035)" sql-rb0035-contract '^502/502 casos ok'

    run "SQL client_request_reapply_check" sql-ra0035 sql_expanded "$HERE/scripts/supabase/tests/client_request_reapply_check.sql"
    expect_log "SQL client_request_reapply_check" sql-ra0035 'ok RA1([^0-9]|$)' 'ok RA2([^0-9]|$)'
    run "SQL client_request_check (tras reaplicar 0035)" sql-ra0035-cr sql "$HERE/scripts/supabase/tests/client_request_check.sql"
    expect_log "SQL client_request_check (tras reaplicar 0035)" sql-ra0035-cr "${c_pat[@]}"
else
    FAILED+=("ida y vuelta 0035 (rollback_0035 no quedó en verde; no se reaplica 0035: la BD local queda a medias, repetir ci.sh)")
fi

if [ "${#FAILED[@]}" -gt 0 ]; then
    echo
    echo "FALLARON ${#FAILED[@]} paso(s):"
    printf '  - %s\n' "${FAILED[@]}"
    exit 1
fi
echo
echo "ci.sh: todo ok (deno check/test procesar-feedback, SQL incl. client_request C1-C9 y feedback B1-B8 y F1-F12, contract_check 502/502, cross_tenant ${expected}/${expected}; ida y vuelta 0035 → rollback → 0035 con RB1-RB4, RA1-RA2 y C1-C9)"
