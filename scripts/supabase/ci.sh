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
#   4. Deno: `deno check` y `deno test` de procesar-feedback y de asistente (Kito, fase 1; mocks, sin
#      red; asistente con --allow-env porque importa los casos de uso de `api`).
#   5. SQL (invitaciones_check N1-N22, home_checks_compat, acl_can_edit_check K1-K8,
#      permisos_matriz_check, client_request_check C1-C9 (0035), assistant_usage_check U1-U7 (0036),
#      task_priority_check P1-P10 (0037), task_person_access_check A1-A9 (0038),
#      get_persons_home_id_check GP1-GP4 (0038, home_id en get_persons),
#      feedback_trello_check B1-B8 (0033) y feedback_trigger_check F1-F12 (0031/0034); trigger inerte en
#      local: sin feedback_webhook_url en Vault no se encola ninguna petición),
#      task_priority_rollback_guard_check G0-G3 (guardas LIFO de rollback_0035/0029 con 0037 aplicada),
#      task_person_access_rollback_guard_check G38-1 (guarda LIFO de rollback_0037 con 0038 aplicada),
#      contract_check.py (502 + prioridad) y cross_tenant_check.py.
#   6. Ida y vuelta exterior 0038 → rollback_0038 → [paso 7] → 0038 (asignar-alta-lista):
#      task_person_access_rollback_check RB38-1..5; sobre el esquema sin 0038: client_request_check,
#      acl_can_edit_check y task_priority_check; al salir del paso 7, task_person_access_reapply_check
#      RA38-1, task_person_access_check A1-A9, get_persons_home_id_check GP1-GP4 y contract_check
#      completo otra vez. Va por fuera de la de
#      0037 porque reaplicar 0037 restaura create_task sin la guarda de 0038 (orden LIFO de rollbacks
#      0038 → 0037 → 0035).
#   7. Ida y vuelta anidada 0037 → rollback_0037 → (0035 → rollback_0035 → 0035) → 0037:
#      a. task_priority_rollback_check PR1-PR4; sobre el esquema sin 0037: home_checks_compat,
#         acl_can_edit_check, permisos_matriz_check y contract_check en modo CONTRACT_SCHEMA=pre-0037
#         (502/502: la Edge nueva sin parámetros nuevos funciona sobre la BD revertida).
#      b. Dentro, la ida y vuelta 0035 de siempre (rollback_0035 borra create_task(…,uuid), que con
#         0037 aplicada ya no existe; por eso va anidada): client_request_rollback_check RB1-RB4, los
#         mismos checks y contract_check (pre-0037) sobre el esquema revertido,
#         event_end_date_rollback_guard_check E0-E2 (guarda LIFO de rollback_0029 con 0030 aplicada), y
#         client_request_reapply_check RA1-RA2 más client_request_check C1-C9 otra vez.
#      c. task_priority_reapply_check PA1-PA3 y, sobre 0037 reaplicada, task_priority_check P1-P10,
#         client_request_check C1-C9 y contract_check completo otra vez con CONTRACT_SCHEMA=pre-0038
#         (532/532; get_persons aún sin home_id porque 0038 no está reaplicada).
#      Si un rollback no queda en verde no se sigue con lo que depende de él (la BD local queda a
#      medias: repetir ci.sh). Se ejecutan todas aunque una falle; el exit final es != 0 si alguna falló.
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
    SUPABASE_FUNCTIONS_URL CONTRACT_ONLY CONTRACT_SCHEMA XT_ONLY PSQL

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

# Edge Function asistente (Kito, fase 1): núcleo, handler y skill consulta con fetch y casos de uso falsos.
# --allow-env: la skill consulta importa los casos de uso de `api`, que leen el entorno al cargar.
ASIST_FN="$HERE/supabase/functions/asistente"
run "deno check asistente" deno-check-asistente env NO_COLOR=1 deno check "$ASIST_FN/index.ts"
run "deno test asistente" deno-test-asistente env NO_COLOR=1 deno test --no-prompt --allow-env "$ASIST_FN/tests/"
expect_log "deno test asistente" deno-test-asistente '^ok \| [0-9]+ passed \| 0 failed'

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

run "SQL task_priority_check" sql-task-priority sql "$HERE/scripts/supabase/tests/task_priority_check.sql"
p_pat=(); for i in $(seq 1 10); do p_pat+=("ok P$i([^0-9a-z]|\$)"); done
expect_log "SQL task_priority_check" sql-task-priority "${p_pat[@]}"

run "SQL task_person_access_check" sql-task-person-access sql "$HERE/scripts/supabase/tests/task_person_access_check.sql"
a_pat=('ok A-clean'); for i in $(seq 1 9); do a_pat+=("ok A$i([^0-9a-z]|\$)"); done
expect_log "SQL task_person_access_check" sql-task-person-access "${a_pat[@]}"

run "SQL get_persons_home_id_check" sql-get-persons-home sql "$HERE/scripts/supabase/tests/get_persons_home_id_check.sql"
gp_pat=('ok GP-clean'); for i in $(seq 1 4); do gp_pat+=("ok GP$i([^0-9a-z]|\$)"); done
expect_log "SQL get_persons_home_id_check" sql-get-persons-home "${gp_pat[@]}"

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

# Guardas LIFO (R1-02): con 0037 aplicada, rollback_0035 y rollback_0029 abortan sin tocar nada y
# las llamadas por nombre de la Edge a create_task/update_task siguen resolviendo. contract_check, justo
# después, confirma por la Edge que POST /task/create (201) y PATCH /task/update (200) no dan 500.
run "SQL task_priority_rollback_guard_check" sql-rbguard sql_expanded "$HERE/scripts/supabase/tests/task_priority_rollback_guard_check.sql"
expect_log "SQL task_priority_rollback_guard_check" sql-rbguard 'ok G0([^0-9]|$)' 'ok G1([^0-9]|$)' 'ok G2([^0-9]|$)' 'ok G3([^0-9]|$)' 'ok G-clean' \
    'rollback_0035: 0037 está aplicada' 'rollback_0029: 0037 está aplicada'

# Guarda LIFO de rollback_0037 con 0038 aplicada (A-8, asignar-alta-lista): aborta sin tocar nada; el
# esquema sigue con la firma, la guarda de personas y priority de 0038.
run "SQL task_person_access_rollback_guard_check" sql-rbguard0038 sql_expanded "$HERE/scripts/supabase/tests/task_person_access_rollback_guard_check.sql"
expect_log "SQL task_person_access_rollback_guard_check" sql-rbguard0038 'ok G38-1([^0-9]|$)' 'ok G38-clean' \
    'rollback_0037: 0038 está aplicada'

# contract_check: 502 casos del contrato previo + 30 de prioridad (0037: CASES_PRIORITY); en modo
# CONTRACT_SCHEMA=pre-0037 (BD revertida por rollback_0037) sin el bloque de prioridad, 502.
CONTRACT_PY="$HERE/scripts/supabase/contract_check.py"
contract_full=532
contract_pre=502
run "contract_check.py" contract python3 "$CONTRACT_PY"
expect_log "contract_check.py" contract "^${contract_full}/${contract_full} casos ok"

run "cross_tenant_check.py" cross-tenant python3 "$HERE/scripts/supabase/tests/cross_tenant_check.py"
# N/N con N == EXPECTED_CASES (el propio script sale 1 si difiere; aquí se exige además el formato).
expected="$(sed -n 's/^EXPECTED_CASES = \([0-9]*\).*/\1/p' "$HERE/scripts/supabase/tests/cross_tenant_check.py")"
[ -n "$expected" ] || FAILED+=("cross_tenant_check.py (sin EXPECTED_CASES)")
expect_log "cross_tenant_check.py" cross-tenant "^${expected}/${expected} casos ok"

# Ida y vuelta exterior 0038 → rollback_0038 → [ida y vuelta 0037] → 0038 (asignar-alta-lista).
# rollback_0038 restaura el create_task de 0037 (misma firma de 5 argumentos, sin la guarda); sobre ese
# esquema se repasan los checks de las RPC de tarea y se entra en la ida y vuelta 0037 sin cambios
# internos. Va por fuera porque reaplicar 0037 deja create_task sin la guarda de 0038: al salir se
# reaplica 0038 y se repiten A1-A9 y contract_check, así el esquema final de CI tiene la guarda.
# Si rollback_0038 no queda en verde no se entra en el bloque 0037.
run "SQL task_person_access_rollback_check" sql-rb0038 sql_expanded "$HERE/scripts/supabase/tests/task_person_access_rollback_check.sql"
rb38_ok=1
for i in 1 2 3 4 5; do grep -Eq "ok RB38-$i([^0-9]|\$)" "$OUT/sql-rb0038.log" || rb38_ok=0; done
expect_log "SQL task_person_access_rollback_check" sql-rb0038 'ok RB38-1([^0-9]|$)' 'ok RB38-2([^0-9]|$)' 'ok RB38-3([^0-9]|$)' 'ok RB38-4([^0-9]|$)' 'ok RB38-5([^0-9]|$)'
ra37_ok=0
if [ "$rb38_ok" = 1 ]; then
    sleep 1 # notify pgrst del rollback
    run "SQL client_request_check (tras rollback_0038)" sql-rb0038-cr sql "$HERE/scripts/supabase/tests/client_request_check.sql"
    expect_log "SQL client_request_check (tras rollback_0038)" sql-rb0038-cr "${c_pat[@]}"
    run "SQL acl_can_edit_check (tras rollback_0038)" sql-rb0038-acl sql "$HERE/scripts/supabase/tests/acl_can_edit_check.sql"
    expect_log "SQL acl_can_edit_check (tras rollback_0038)" sql-rb0038-acl "${k_pat[@]}"
    run "SQL task_priority_check (tras rollback_0038)" sql-rb0038-tp sql "$HERE/scripts/supabase/tests/task_priority_check.sql"
    expect_log "SQL task_priority_check (tras rollback_0038)" sql-rb0038-tp "${p_pat[@]}"

    # Ida y vuelta anidada 0037 → rollback_0037 → (0035 → rollback_0035 → 0035) → 0037. Los rollbacks se
    # confirman de verdad; sobre cada esquema revertido se repasan los checks que tocan las RPC de tarea y
    # contract_check en modo pre-0037 (la Edge nueva no manda parámetros nuevos si el cliente no los
    # envía). rollback_0035 borra create_task(bigint,text,jsonb,uuid), que solo existe sin 0037: por eso la
    # vuelta de 0035 va dentro de la de 0037. Si un rollback falla no se sigue con lo que depende de él.
    run "SQL task_priority_rollback_check" sql-rb0037 sql_expanded "$HERE/scripts/supabase/tests/task_priority_rollback_check.sql"
    pr_ok=1
    for i in 1 2 3 4; do grep -Eq "ok PR$i([^0-9]|\$)" "$OUT/sql-rb0037.log" || pr_ok=0; done
    expect_log "SQL task_priority_rollback_check" sql-rb0037 'ok PR1([^0-9]|$)' 'ok PR2([^0-9]|$)' 'ok PR3([^0-9]|$)' 'ok PR4([^0-9]|$)'
    if [ "$pr_ok" = 1 ]; then
        sleep 1 # notify pgrst del rollback: PostgREST recarga el esquema antes de contract_check
        run "SQL home_checks_compat (tras rollback_0037)" sql-rb0037-compat sql "$HERE/scripts/supabase/tests/home_checks_compat.sql"
        expect_log "SQL home_checks_compat (tras rollback_0037)" sql-rb0037-compat "${v_pat[@]}"
        run "SQL acl_can_edit_check (tras rollback_0037)" sql-rb0037-acl sql "$HERE/scripts/supabase/tests/acl_can_edit_check.sql"
        expect_log "SQL acl_can_edit_check (tras rollback_0037)" sql-rb0037-acl "${k_pat[@]}"
        run "SQL permisos_matriz_check (tras rollback_0037)" sql-rb0037-matriz sql "$HERE/scripts/supabase/tests/permisos_matriz_check.sql"
        expect_log "SQL permisos_matriz_check (tras rollback_0037)" sql-rb0037-matriz "${m_pat[@]}"
        run "contract_check.py (pre-0037, tras rollback_0037)" sql-rb0037-contract env CONTRACT_SCHEMA=pre-0037 python3 "$CONTRACT_PY"
        expect_log "contract_check.py (pre-0037, tras rollback_0037)" sql-rb0037-contract "^${contract_pre}/${contract_pre} casos ok"

        # Ida y vuelta 0035 → rollback_0035.sql → 0035 (R1-01), sobre el esquema sin 0037.
        run "SQL client_request_rollback_check" sql-rb0035 sql_expanded "$HERE/scripts/supabase/tests/client_request_rollback_check.sql"
        rb_ok=1
        for i in 1 2 3 4; do grep -Eq "ok RB$i([^0-9]|\$)" "$OUT/sql-rb0035.log" || rb_ok=0; done
        expect_log "SQL client_request_rollback_check" sql-rb0035 'ok RB1([^0-9]|$)' 'ok RB2([^0-9]|$)' 'ok RB3([^0-9]|$)' 'ok RB4([^0-9]|$)'
        if [ "$rb_ok" = 1 ]; then
            sleep 1
            run "SQL home_checks_compat (tras rollback_0035)" sql-rb0035-compat sql "$HERE/scripts/supabase/tests/home_checks_compat.sql"
            expect_log "SQL home_checks_compat (tras rollback_0035)" sql-rb0035-compat "${v_pat[@]}"
            run "SQL acl_can_edit_check (tras rollback_0035)" sql-rb0035-acl sql "$HERE/scripts/supabase/tests/acl_can_edit_check.sql"
            expect_log "SQL acl_can_edit_check (tras rollback_0035)" sql-rb0035-acl "${k_pat[@]}"
            run "SQL permisos_matriz_check (tras rollback_0035)" sql-rb0035-matriz sql "$HERE/scripts/supabase/tests/permisos_matriz_check.sql"
            expect_log "SQL permisos_matriz_check (tras rollback_0035)" sql-rb0035-matriz "${m_pat[@]}"
            run "contract_check.py (pre-0037, tras rollback_0035)" sql-rb0035-contract env CONTRACT_SCHEMA=pre-0037 python3 "$CONTRACT_PY"
            expect_log "contract_check.py (pre-0037, tras rollback_0035)" sql-rb0035-contract "^${contract_pre}/${contract_pre} casos ok"

            # Guarda LIFO de rollback_0029 con 0030 aplicada (R2-02): aquí 0037 y 0035 están revertidas,
            # así que la guarda que salta es la de 0030; el esquema no cambia.
            run "SQL event_end_date_rollback_guard_check" sql-rbguard0030 sql_expanded "$HERE/scripts/supabase/tests/event_end_date_rollback_guard_check.sql"
            expect_log "SQL event_end_date_rollback_guard_check" sql-rbguard0030 'ok E0([^0-9]|$)' 'ok E1([^0-9]|$)' 'ok E2([^0-9]|$)' \
                'rollback_0029: 0030 está aplicada'

            run "SQL client_request_reapply_check" sql-ra0035 sql_expanded "$HERE/scripts/supabase/tests/client_request_reapply_check.sql"
            expect_log "SQL client_request_reapply_check" sql-ra0035 'ok RA1([^0-9]|$)' 'ok RA2([^0-9]|$)'
            run "SQL client_request_check (tras reaplicar 0035)" sql-ra0035-cr sql "$HERE/scripts/supabase/tests/client_request_check.sql"
            expect_log "SQL client_request_check (tras reaplicar 0035)" sql-ra0035-cr "${c_pat[@]}"
        else
            FAILED+=("ida y vuelta 0035 (rollback_0035 no quedó en verde; no se reaplica 0035: la BD local queda a medias, repetir ci.sh)")
        fi

        if [ "$rb_ok" = 1 ]; then
            run "SQL task_priority_reapply_check" sql-ra0037 sql_expanded "$HERE/scripts/supabase/tests/task_priority_reapply_check.sql"
            expect_log "SQL task_priority_reapply_check" sql-ra0037 'ok PA1([^0-9]|$)' 'ok PA2([^0-9]|$)' 'ok PA3([^0-9]|$)'
            # 0038: solo se reaplica sobre 0037 reaplicada (PA3: una firma nueva por RPC).
            if grep -Eq 'ok PA3([^0-9]|$)' "$OUT/sql-ra0037.log"; then ra37_ok=1; fi
            sleep 1 # notify pgrst de 0037 antes de contract_check
            run "SQL task_priority_check (tras reaplicar 0037)" sql-ra0037-tp sql "$HERE/scripts/supabase/tests/task_priority_check.sql"
            expect_log "SQL task_priority_check (tras reaplicar 0037)" sql-ra0037-tp "${p_pat[@]}"
            run "SQL client_request_check (tras reaplicar 0037)" sql-ra0037-cr sql "$HERE/scripts/supabase/tests/client_request_check.sql"
            expect_log "SQL client_request_check (tras reaplicar 0037)" sql-ra0037-cr "${c_pat[@]}"
            run "contract_check.py (tras reaplicar 0037, sin 0038)" sql-ra0037-contract env CONTRACT_SCHEMA=pre-0038 python3 "$CONTRACT_PY"
            expect_log "contract_check.py (tras reaplicar 0037, sin 0038)" sql-ra0037-contract "^${contract_full}/${contract_full} casos ok"
        else
            FAILED+=("ida y vuelta 0037 (sin 0035 reaplicada no se reaplica 0037: la BD local queda a medias, repetir ci.sh)")
        fi
    else
        FAILED+=("ida y vuelta 0037 (rollback_0037 no quedó en verde; no se sigue: la BD local queda a medias, repetir ci.sh)")
    fi

    if [ "$ra37_ok" = 1 ]; then
        run "SQL task_person_access_reapply_check" sql-ra0038 sql_expanded "$HERE/scripts/supabase/tests/task_person_access_reapply_check.sql"
        expect_log "SQL task_person_access_reapply_check" sql-ra0038 'ok RA38-1([^0-9]|$)'
        sleep 1 # notify pgrst de 0038 antes de contract_check
        run "SQL task_person_access_check (tras reaplicar 0038)" sql-ra0038-tpa sql "$HERE/scripts/supabase/tests/task_person_access_check.sql"
        expect_log "SQL task_person_access_check (tras reaplicar 0038)" sql-ra0038-tpa "${a_pat[@]}"
        run "SQL get_persons_home_id_check (tras reaplicar 0038)" sql-ra0038-gp sql "$HERE/scripts/supabase/tests/get_persons_home_id_check.sql"
        expect_log "SQL get_persons_home_id_check (tras reaplicar 0038)" sql-ra0038-gp "${gp_pat[@]}"
        # contract_check usa una client_request_id fija en el replay de prioridad y borra sus tareas al
        # terminar: la pasada anterior (tras reaplicar 0037) dejó esa clave apuntando a una tarea borrada,
        # y el replay daría 'Not Found'. Antes no pasaba porque rollback_0035 borra client_request.
        # Solo BD local: se quitan las claves de tareas que ya no existen.
        run "SQL limpieza de client_request huérfanas" sql-ra0038-crclean "${PSQL_CMD[@]}" -v ON_ERROR_STOP=1 -c \
            "delete from client_request cr where cr.kind = 'task' and not exists (select 1 from task t where t.id = cr.resource_id)"
        run "contract_check.py (tras reaplicar 0038)" sql-ra0038-contract python3 "$CONTRACT_PY"
        expect_log "contract_check.py (tras reaplicar 0038)" sql-ra0038-contract "^${contract_full}/${contract_full} casos ok"
    else
        FAILED+=("ida y vuelta 0038 (sin 0037 reaplicada no se reaplica 0038: la BD local queda a medias, repetir ci.sh)")
    fi
else
    FAILED+=("ida y vuelta 0038 (rollback_0038 no quedó en verde; no se sigue: la BD local queda a medias, repetir ci.sh)")
fi

if [ "${#FAILED[@]}" -gt 0 ]; then
    echo
    echo "FALLARON ${#FAILED[@]} paso(s):"
    printf '  - %s\n' "${FAILED[@]}"
    exit 1
fi
echo
echo "ci.sh: todo ok (deno check/test procesar-feedback y asistente; SQL incl. invitaciones N1-N22, K1-K8, client_request C1-C9, assistant_usage U1-U7, task_priority P1-P10, task_person_access A1-A9, get_persons GP1-GP4, guardas de rollback G0-G3 y G38-1, feedback B1-B8 y F1-F12; contract_check ${contract_full}/${contract_full}, cross_tenant ${expected}/${expected}; ida y vuelta 0038 → rollback → [0037 → rollback → (0035 → rollback → 0035) → 0037] → 0038 con RB38-1..5, PR1-PR4, contract pre-0037 ${contract_pre}/${contract_pre}, RB1-RB4, guarda 0030 E0-E2, RA1-RA2, PA1-PA3, P1-P10, C1-C9, RA38-1, A1-A9 y GP1-GP4)"
