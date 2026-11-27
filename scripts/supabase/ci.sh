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
#      red; asistente con --allow-env porque importa los casos de uso de `api`) y el test de
#      PATCH /task-list/order de `api` (0040, con --allow-env).
#   5. SQL (invitaciones_check N1-N22, home_checks_compat, acl_can_edit_check K1-K8,
#      permisos_matriz_check, client_request_check C1-C9 (0035), assistant_usage_check U1-U7 (0036),
#      task_priority_check P1-P10 (0037), task_person_access_check A1-A9 (0038),
#      get_persons_home_id_check GP1-GP4 (0038, home_id en get_persons),
#      task_hidden_check H1-H12 (0039, ocultar completadas a los 3 días),
#      task_list_position_check TP1-TP8 (0040), task_due_check DN1-DN9 (0041/0042, fecha límite),
#      G5-md5 (solo ADVERTENCIA, no falla: md5 del gate G5 de DEPLOY_0039.md = stack local),
#      feedback_trello_check B1-B8 (0033) y feedback_trigger_check F1-F12 (0031/0034); trigger inerte en
#      local: sin feedback_webhook_url en Vault no se encola ninguna petición),
#      meal_profile_check MP1-MP11 (0043) y menu_semana_check MS1-MS17 (0044, con la semilla
#      supabase/seed/food_es.sql cargada justo tras aplicar las migraciones),
#      task_priority_rollback_guard_check G0-G3 (guardas LIFO de rollback_0035/0029 con 0037 aplicada),
#      task_person_access_rollback_guard_check G38-1 (guarda LIFO de rollback_0037 con 0038 aplicada),
#      task_hidden_rollback_guard_check G39-1 (guarda LIFO de rollback_0038 con 0039 aplicada),
#      contract_check.py (502 + prioridad + ocultas + orden de listas) y cross_tenant_check.py.
#   5c. Ida y vuelta 0048 → rollback_0048_menus_kito → [rollbacks de 0047, 0046, 0045 y 0044] → 0048 (kito-menus): RK1-RK3 y, tras
#      reaplicar, RK4 y kito_menus_check MK1-MK7 otra vez (MK1-MK7 también corre en el paso 5). La más exterior de menús (LIFO).
#   5-0047. recetas_seed.py --check, seed de recetas precargadas (dos cargas, la segunda INSERT 0 0), recetas_precargadas_check
#      RP1-RP5 (0047) e ida y vuelta 0047 → rollback_0047 → 0047 + seed (RR1-RR3, RA5; la más externa, orden LIFO).
#   5a. Ida y vuelta 0044 → rollback_0044_menus_semana → 0044 + semilla (menus-semana): RM4-RM6, RA3-RA4 y
#      menu_semana_check MS1-MS17 otra vez. Va ANTES de la de 0043 (orden LIFO: 0044 usa lo de 0043).
#   5b. Ida y vuelta exterior 0039 → rollback_0039 → [paso 6] → 0039 (ocultar-completadas-3-dias):
#      task_hidden_rollback_check RBH1-5; sobre el esquema sin 0039: task_priority_check,
#      task_person_access_check, client_request_check, acl_can_edit_check y contract_check en modo
#      CONTRACT_SCHEMA=pre-0039 (549/549); al salir del paso 6, task_hidden_reapply_check RAH1-3
#      (backfill real), task_hidden_check H1-H12 y contract_check completo otra vez. Va por fuera de la
#      de 0038 porque la anidada revierte y reaplica get_tasks, get_task_detail y update_task (orden
#      LIFO de rollbacks 0039 → 0038 → 0037 → 0035).
#   6. Ida y vuelta 0038 → rollback_0038 → [paso 7] → 0038 (asignar-alta-lista):
#      task_person_access_rollback_check RB38-1..5; sobre el esquema sin 0038: client_request_check,
#      acl_can_edit_check y task_priority_check; al salir del paso 7, task_person_access_reapply_check
#      RA38-1, task_person_access_check A1-A9, get_persons_home_id_check GP1-GP4 y contract_check
#      en modo pre-0039 (549/549; 0039 todavía revertida). Va por fuera de la de
#      0037 porque reaplicar 0037 restaura create_task sin la guarda de 0038 (orden LIFO de rollbacks
#      0038 → 0037 → 0035).
#   7. Ida y vuelta anidada 0037 → rollback_0037 → (0035 → rollback_0035 → 0035) → 0037:
#      a. task_priority_rollback_check PR1-PR4; sobre el esquema sin 0037: home_checks_compat,
#         acl_can_edit_check, permisos_matriz_check y contract_check en modo CONTRACT_SCHEMA=pre-0037
#         (519/519: la Edge nueva sin parámetros nuevos funciona sobre la BD revertida).
#      b. Dentro, la ida y vuelta 0035 de siempre (rollback_0035 borra create_task(…,uuid), que con
#         0037 aplicada ya no existe; por eso va anidada): client_request_rollback_check RB1-RB4, los
#         mismos checks y contract_check (pre-0037) sobre el esquema revertido,
#         event_end_date_rollback_guard_check E0-E2 (guarda LIFO de rollback_0029 con 0030 aplicada), y
#         client_request_reapply_check RA1-RA2 más client_request_check C1-C9 otra vez.
#      c. task_priority_reapply_check PA1-PA3 y, sobre 0037 reaplicada, task_priority_check P1-P10,
#         client_request_check C1-C9 y contract_check completo otra vez con CONTRACT_SCHEMA=pre-0038
#         (549/549; get_persons aún sin home_id porque 0038 no está reaplicada).
#      Si un rollback no queda en verde no se sigue con lo que depende de él (la BD local queda a
#      medias: repetir ci.sh). Se ejecutan todas aunque una falle; el exit final es != 0 si alguna falló.
#   9. Ida y vuelta 0041 → rollback_0041.sql → 0041 + 0042 (fecha-limite-vencimiento), en serie tras la 0040.
#   8. Ida y vuelta 0040 → rollback_0040.sql → 0040 (lista-prioritaria-inicio), en serie tras las anteriores
#      (0040 solo toca get_task_lists y reorder_task_lists, sin funciones comunes con 0035-0039):
#      task_list_position_rollback_check TR1-TR3, después home_checks_compat, acl_can_edit_check,
#      permisos_matriz_check y contract_check (CONTRACT_POSITION=0: 564/564, sin `position`) sobre el
#      esquema revertido, y task_list_position_reapply_check TA1-TA2 más task_list_position_check TP1-TP8.
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
    SUPABASE_FUNCTIONS_URL CONTRACT_ONLY CONTRACT_SCHEMA CONTRACT_POSITION XT_ONLY PSQL

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

# Catálogo común de alimentos (0044): el seed NO va en la migración. Se carga dos veces: la segunda no
# inserta nada (idempotente, on conflict contra food_common_name_uq).
run "SQL seed food_es" sql-seed-food sql "$HERE/supabase/seed/food_es.sql"
expect_log "SQL seed food_es" sql-seed-food '^INSERT 0 [1-9][0-9]*'
run "SQL seed food_es (segunda carga)" sql-seed-food2 sql "$HERE/supabase/seed/food_es.sql"
expect_log "SQL seed food_es (segunda carga)" sql-seed-food2 '^INSERT 0 0$'

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

# Test de PATCH /task-list/order (0040): fetch falso, solo validación local y paso de errores de la RPC.
API_FN="$HERE/supabase/functions/api"
run "deno test api task-list/order" deno-test-api-order env NO_COLOR=1 deno test --no-prompt --allow-env "$API_FN/tests/task_list_order_test.ts"
expect_log "deno test api task-list/order" deno-test-api-order '^ok \| [0-9]+ passed \| 0 failed'

# Test de PATCH /task/update con due_at (0041): fetch falso, mapeo a p_due_at / p_clear_due y 400 local.
run "deno test api task-due" deno-test-api-due env NO_COLOR=1 deno test --no-prompt --allow-env "$API_FN/tests/task_due_test.ts"
expect_log "deno test api task-due" deno-test-api-due '^ok \| [0-9]+ passed \| 0 failed'

# dashboard-sesion: POST /user/refresh con fetch falso (refresh_token grant, errores 400/401/5xx).
run "deno test api user/refresh" deno-test-api-refresh env NO_COLOR=1 deno test --no-prompt --allow-env "$API_FN/tests/user_refresh_test.ts"
expect_log "deno test api user/refresh" deno-test-api-refresh '^ok \| [0-9]+ passed \| 0 failed'
# Tests de /meal/* (0043): fetch falso; forma de la petición, args de cada RPC, mapeo de errores y X-Home-Id.
run "deno test api meals" deno-test-api-meals env NO_COLOR=1 deno test --no-prompt --allow-env "$API_FN/tests/meals_test.ts"
expect_log "deno test api meals" deno-test-api-meals '^ok \| [0-9]+ passed \| 0 failed'
# Tests de /recipe*, /food* y /meal/plan* (0044): fetch falso; forma, args de cada RPC, 409 de revisión y de semana ocupada.
run "deno test api recipes" deno-test-api-recipes env NO_COLOR=1 deno test --no-prompt --allow-env "$API_FN/tests/recipes_test.ts"
expect_log "deno test api recipes" deno-test-api-recipes '^ok \| [0-9]+ passed \| 0 failed'
run "deno test api shopping" deno-test-api-shopping env NO_COLOR=1 deno test --no-prompt --allow-env --allow-read "$API_FN/tests/shopping_test.ts"
expect_log "deno test api shopping" deno-test-api-shopping '^ok \| [0-9]+ passed \| 0 failed'
run "deno check api" deno-check-api env NO_COLOR=1 deno check "$API_FN/index.ts"

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

# 0043 (menus-perfil-hogar): perfil de hogar y franjas; defaults, mascotas, RLS entre hogares, matriz menu.*, backfill, bloque C.
run "SQL meal_profile_check" sql-meal-profile sql "$HERE/scripts/supabase/tests/meal_profile_check.sql"
mp_pat=(); for i in $(seq 1 11); do mp_pat+=("ok MP$i([^0-9a-z]|\$)"); done
expect_log "SQL meal_profile_check" sql-meal-profile "${mp_pat[@]}"

# 0044 (menus-semana): catálogo, recetas y menú semanal; RLS entre hogares, revisión, ciclo del plan, check y comidas de hoy.
run "SQL menu_semana_check" sql-menu-semana sql "$HERE/scripts/supabase/tests/menu_semana_check.sql"
ms_pat=(); for i in $(seq 1 17); do ms_pat+=("ok MS$i([^0-9a-z]|\$)"); done
expect_log "SQL menu_semana_check" sql-menu-semana "${ms_pat[@]}"

# 0045 (menus-compra): suma de ingredientes, sincronización con el menú, artículos, permisos, RLS y kinds de client_request.
run "SQL shopping_check" sql-shopping sql "$HERE/scripts/supabase/tests/shopping_check.sql"
sh_pat=(); for i in $(seq 1 11); do sh_pat+=("ok SH$i([^0-9a-z]|\$)"); done
expect_log "SQL shopping_check" sql-shopping "${sh_pat[@]}"

# 0048 (kito-menus): origin, estado de casilla, client_request_id en plan y receta, reglas de Kito, aislamiento y grants.
run "SQL kito_menus_check" sql-kito-menus sql "$HERE/scripts/supabase/tests/kito_menus_check.sql"
mk_pat=(); for i in $(seq 1 7); do mk_pat+=("ok MK$i([^0-9a-z]|\$)"); done
expect_log "SQL kito_menus_check" sql-kito-menus "${mk_pat[@]}"

# 0049 (dashboard-pantalla-hogar): pantalla del hogar (cuenta técnica, vinculación de un solo uso, límites, selección,
# revocación y grants). Ida y vuelta: rollback_0049 → comprobaciones de ausencia → reaplicar 0049 → de nuevo la suite.
run "SQL home_display_check" sql-home-display sql "$HERE/scripts/supabase/tests/home_display_check.sql"
expect_log "SQL home_display_check" sql-home-display 'ok D1([^0-9]|$)' 'ok D2([^0-9]|$)' 'ok D5([^0-9]|$)' 'ok D6([^0-9]|$)' 'ok D8([^0-9]|$)' 'ok D10([^0-9]|$)' 'ok D12([^0-9]|$)' 'ok D-clean'
run "SQL home_display_rollback (rollback_0049)" sql-rb0049 sql "$HERE/scripts/supabase/rollback/rollback_0049_home_display.sql"
run "SQL home_display_rollback_check" sql-rb0049-check sql "$HERE/scripts/supabase/tests/home_display_rollback_check.sql"
expect_log "SQL home_display_rollback_check" sql-rb0049-check 'ok R1([^0-9]|$)' 'ok R2([^0-9]|$)' 'ok R3([^0-9]|$)'
run "SQL 0049 reaplicada" sql-ra0049 sql "$HERE/supabase/migrations/0049_home_display.sql"
run "SQL home_display_check (tras reaplicar 0049)" sql-ra0049-check sql "$HERE/scripts/supabase/tests/home_display_check.sql"
expect_log "SQL home_display_check (tras reaplicar 0049)" sql-ra0049-check 'ok D-clean'
run "deno test api displays" deno-test-api-displays env NO_COLOR=1 deno test --no-prompt --allow-env "$API_FN/tests/displays_test.ts"
expect_log "deno test api displays" deno-test-api-displays '^ok \| [0-9]+ passed \| 0 failed'
# La reaplicación de 0049 recrea fn_display_link_complete sin task.complete: se reaplica 0050 encima (cross_tenant DM1 lo necesita).
run "SQL 0050 reaplicada (tras 0049)" sql-ra0050-tras0049 sql "$HERE/supabase/migrations/0050_marcar_hecho.sql"

# 0050 (dashboard-marcar-hecho): la pantalla completa y descompleta tareas de sus listas (y nada más), auditado e
# idempotente con client_request. Ida y vuelta: rollback_0050 → comprobaciones → reaplicar 0050 → de nuevo la suite.
run "SQL marcar_hecho_check" sql-marcar-hecho sql "$HERE/scripts/supabase/tests/marcar_hecho_check.sql"
expect_log "SQL marcar_hecho_check" sql-marcar-hecho 'ok MH1([^0-9]|$)' 'ok MH5([^0-9]|$)' 'ok MH7([^0-9]|$)' 'ok MH-clean'
run "deno test api tasks (complete)" deno-test-api-tasks-complete env NO_COLOR=1 deno test --no-prompt --allow-env "$API_FN/tests/tasks_complete_test.ts"
expect_log "deno test api tasks (complete)" deno-test-api-tasks-complete '^ok \| [0-9]+ passed \| 0 failed'

# 0046 (menus-paises-hogar): países del hogar en meal_profile; guardado, rechazo, cross-tenant, permisos y grants.
run "SQL meal_profile_countries_check" sql-mp-countries sql "$HERE/scripts/supabase/tests/meal_profile_countries_check.sql"
mc_pat=(); for i in $(seq 1 5); do mc_pat+=("ok MC$i([^0-9a-z]|\$)"); done
expect_log "SQL meal_profile_countries_check" sql-mp-countries "${mc_pat[@]}"

# 0047 (menus-recetas-precargadas): el lote de recetas comunes se valida (scripts/menus/recetas_seed.py --check: formato y
# SQL generado al día) y se carga dos veces (la segunda no inserta nada: on conflict contra recipe_common_name_country_uq).
# Va DESPUÉS de menu_semana_check y shopping_check, que esperan listas de recetas vacías para un hogar sin recetas.
run "recetas_seed.py --check" recetas-seed-check python3 "$HERE/scripts/menus/recetas_seed.py" --check
expect_log "recetas_seed.py --check" recetas-seed-check '^recetas_seed: 20 recetas válidas'
run "SQL seed recetas_precargadas" sql-seed-recetas sql "$HERE/supabase/seed/recetas_precargadas.sql"
expect_log "SQL seed recetas_precargadas" sql-seed-recetas '^INSERT 0 [1-9][0-9]*'
run "SQL seed recetas_precargadas (segunda carga)" sql-seed-recetas2 sql "$HERE/supabase/seed/recetas_precargadas.sql"
expect_log "SQL seed recetas_precargadas (segunda carga)" sql-seed-recetas2 '^INSERT 0 0$'
if grep -Eq '^INSERT 0 [1-9]' "$OUT/sql-seed-recetas2.log"; then
    FAILED+=("SQL seed recetas_precargadas (segunda carga): insertó filas, no es idempotente")
fi
run "SQL recetas_precargadas_check" sql-recetas sql "$HERE/scripts/supabase/tests/recetas_precargadas_check.sql"
rp_pat=(); for i in $(seq 1 5); do rp_pat+=("ok RP$i([^0-9a-z]|\$)"); done
expect_log "SQL recetas_precargadas_check" sql-recetas "${rp_pat[@]}"

run "SQL client_request_check" sql-client-request sql "$HERE/scripts/supabase/tests/client_request_check.sql"
c_pat=(); for i in $(seq 1 9); do c_pat+=("ok C$i([^0-9a-z]|\$)"); done
expect_log "SQL client_request_check" sql-client-request "${c_pat[@]}"

run "SQL task_list_position_check" sql-task-list-position sql "$HERE/scripts/supabase/tests/task_list_position_check.sql"
tp_pat=(); for i in $(seq 1 8); do tp_pat+=("ok TP$i([^0-9a-z]|\$)"); done
expect_log "SQL task_list_position_check" sql-task-list-position "${tp_pat[@]}"

# 0041 (fecha-limite-vencimiento): fecha límite de tareas sobre la BD con 0041 aplicada.
run "SQL task_due_check" sql-task-due sql "$HERE/scripts/supabase/tests/task_due_check.sql"
dn_pat=(); for i in $(seq 1 9); do dn_pat+=("ok DN$i([^0-9a-z]|\$)"); done
expect_log "SQL task_due_check" sql-task-due "${dn_pat[@]}"

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

run "SQL task_hidden_check" sql-task-hidden sql "$HERE/scripts/supabase/tests/task_hidden_check.sql"
h_pat=('ok H-clean'); for i in $(seq 1 12); do h_pat+=("ok H$i([^0-9a-z]|\$)"); done
expect_log "SQL task_hidden_check" sql-task-hidden "${h_pat[@]}"

# G5-md5 (solo ADVERTENCIA, nunca falla): los md5 que supabase/DEPLOY_0039.md pide comparar en el gate
# G5 (7 funciones de 0039 y la policy task_select) se leen del propio documento (bloque «-- G5.» hasta
# «-- G6.») y se comparan con los del stack local, con 0039 aplicada. Si difieren imprime «ADVERTENCIA md5»
# y sigue: la versión menor de PostgreSQL de prod puede no ser la del CI y cambiar pg_get_functiondef o
# pg_get_expr. Sirve para detectar una constante mal transcrita antes de ir a prod. No toca FAILED.
g5_md5_check() {
    local doc="$HERE/supabase/DEPLOY_0039.md" want got
    want="$(awk '/^-- G5\./{f=1; next} /^-- G6\./{f=0} f' "$doc" \
        | sed -nE -e 's/^--   ([a-z_]+\([a-z,]*\)) +([0-9a-f]{32})$/\1 \2/p' \
                  -e 's/^-- Esperado: ([0-9a-f]{32})\.$/policy:task_select \1/p' | LC_ALL=C sort)"
    got="$("${PSQL_CMD[@]}" -At -F ' ' -c \
        "select p.oid::regprocedure::text, md5(pg_get_functiondef(p.oid)) from pg_proc p
          where p.pronamespace = 'public'::regnamespace
            and p.proname in ('get_tasks', 'get_task_detail', 'complete_task', 'update_task', 'task_order',
                              'delete_task', 'fn_reorder_tasks')
         union all
         select 'policy:task_select', md5(pg_get_expr(polqual, polrelid)) from pg_policy
          where polrelid = 'public.task'::regclass and polname = 'task_select' and polcmd = 'r'" 2>&1 \
        | LC_ALL=C sort)" || true
    if [ "$(printf '%s\n' "$want" | grep -c .)" -ne 8 ]; then
        echo "ADVERTENCIA md5: G5 de DEPLOY_0039.md no tiene 8 constantes legibles (7 funciones + task_select):"
        printf '%s\n' "$want"
    elif [ "$want" != "$got" ]; then
        echo "ADVERTENCIA md5: G5 de DEPLOY_0039.md ≠ stack local (no corta ci.sh; revisar antes del gate G5):"
        diff <(printf '%s\n' "$want") <(printf '%s\n' "$got") | sed 's/^</  DEPLOY_0039:/; s/^>/  local:/' || true
    else
        echo "ok G5-md5: las 7 funciones y task_select del stack local = constantes de G5 en DEPLOY_0039.md"
    fi
}
step "G5-md5 DEPLOY_0039 (advertencia)"
g5_md5_check 2>&1 | tee "$OUT/g5-md5.log" || true

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

# Guarda LIFO de rollback_0038 con 0039 aplicada (ocultar-completadas-3-dias): aborta sin tocar nada; el
# esquema sigue con task.hidden_at, su CHECK y las funciones de 0039.
run "SQL task_hidden_rollback_guard_check" sql-rbguard0039 sql_expanded "$HERE/scripts/supabase/tests/task_hidden_rollback_guard_check.sql"
expect_log "SQL task_hidden_rollback_guard_check" sql-rbguard0039 'ok G39-1([^0-9]|$)' 'ok G39-clean' \
    'rollback_0038: 0039 está aplicada'

# contract_check: 502 casos del contrato previo + 30 de prioridad (0037: CASES_PRIORITY) + 32 de ocultas
# (0039: CASES_HIDDEN) + 17 de orden de listas (0040: CASES_POSITION); en modo CONTRACT_SCHEMA=pre-0039 o
# pre-0038 (sin el bloque de ocultas), 549; en pre-0037 (BD revertida por rollback_0037) sin el bloque de
# prioridad, 519. Con CONTRACT_POSITION=0 (esquema sin 0040) se restan los 17 (contract_nopos).
CONTRACT_PY="$HERE/scripts/supabase/contract_check.py"
contract_full=595
contract_nopos=578
contract_pre39=563
contract_pre=533
run "contract_check.py" contract python3 "$CONTRACT_PY"
expect_log "contract_check.py" contract "^${contract_full}/${contract_full} casos ok"

run "cross_tenant_check.py" cross-tenant python3 "$HERE/scripts/supabase/tests/cross_tenant_check.py"
# N/N con N == EXPECTED_CASES (el propio script sale 1 si difiere; aquí se exige además el formato).
expected="$(sed -n 's/^EXPECTED_CASES = \([0-9]*\).*/\1/p' "$HERE/scripts/supabase/tests/cross_tenant_check.py")"
[ -n "$expected" ] || FAILED+=("cross_tenant_check.py (sin EXPECTED_CASES)")
expect_log "cross_tenant_check.py" cross-tenant "^${expected}/${expected} casos ok"

# 0050 (marcar-hecho) es la más nueva: su rollback va ANTES de las de 0039..0035, que redefinen complete_task, y su
# reaplicación va al final (orden LIFO). Mientras está revertida, complete_task es la de 0039.
run "SQL marcar_hecho (rollback_0050, LIFO antes de 0039)" sql-rb0050 sql "$HERE/scripts/supabase/rollback/rollback_0050_marcar_hecho.sql"
run "SQL marcar_hecho_rollback_check" sql-rb0050-check sql "$HERE/scripts/supabase/tests/marcar_hecho_rollback_check.sql"
expect_log "SQL marcar_hecho_rollback_check" sql-rb0050-check 'ok MR1([^0-9]|$)' 'ok MR2([^0-9]|$)' 'ok MR3([^0-9]|$)'

# Ida y vuelta exterior 0039 → rollback_0039 → [ida y vuelta 0038] → 0039 (ocultar-completadas-3-dias).
# rollback_0039 restaura los 7 cuerpos vigentes antes de 0039 y quita task.hidden_at. Va por fuera de la
# de 0038 porque la anidada 0038 → 0037 → 0035 revierte y reaplica get_tasks, get_task_detail y
# update_task, lo que borraría el filtro de 0039 (orden LIFO 0039 → 0038 → 0037 → 0035). Sobre el
# esquema sin 0039 se repasan los checks de las RPC de tarea y contract_check en modo pre-0039; al salir
# de la de 0038 se reaplica 0039 (task_hidden_reapply_check, backfill real), se repite H1-H12 y
# contract_check completo, así el esquema final de CI tiene hidden_at. cross_tenant no se ejecuta sobre
# el esquema revertido (sus casos XH dependen de 0039).
run "SQL task_hidden_rollback_check" sql-rb0039 sql_expanded "$HERE/scripts/supabase/tests/task_hidden_rollback_check.sql"
rb39_ok=1
for i in 1 2 3 4 5; do grep -Eq "ok RBH$i([^0-9]|\$)" "$OUT/sql-rb0039.log" || rb39_ok=0; done
expect_log "SQL task_hidden_rollback_check" sql-rb0039 'ok RBH1([^0-9]|$)' 'ok RBH2([^0-9]|$)' 'ok RBH3([^0-9]|$)' 'ok RBH4([^0-9]|$)' 'ok RBH5([^0-9]|$)'
ra38_ok=0
if [ "$rb39_ok" = 1 ]; then
    sleep 1 # notify pgrst del rollback
    run "SQL task_priority_check (tras rollback_0039)" sql-rb0039-tp sql "$HERE/scripts/supabase/tests/task_priority_check.sql"
    expect_log "SQL task_priority_check (tras rollback_0039)" sql-rb0039-tp "${p_pat[@]}"
    run "SQL task_person_access_check (tras rollback_0039)" sql-rb0039-tpa sql "$HERE/scripts/supabase/tests/task_person_access_check.sql"
    expect_log "SQL task_person_access_check (tras rollback_0039)" sql-rb0039-tpa "${a_pat[@]}"
    run "SQL client_request_check (tras rollback_0039)" sql-rb0039-cr sql "$HERE/scripts/supabase/tests/client_request_check.sql"
    expect_log "SQL client_request_check (tras rollback_0039)" sql-rb0039-cr "${c_pat[@]}"
    run "SQL acl_can_edit_check (tras rollback_0039)" sql-rb0039-acl sql "$HERE/scripts/supabase/tests/acl_can_edit_check.sql"
    expect_log "SQL acl_can_edit_check (tras rollback_0039)" sql-rb0039-acl "${k_pat[@]}"
    # La pasada principal de contract_check dejó la client_request_id fija del replay de prioridad
    # apuntando a una tarea borrada (ver la limpieza tras reaplicar 0038). Solo BD local.
    run "SQL limpieza de client_request huérfanas (tras rollback_0039)" sql-rb0039-crclean "${PSQL_CMD[@]}" -v ON_ERROR_STOP=1 -c \
        "delete from client_request cr where cr.kind = 'task' and not exists (select 1 from task t where t.id = cr.resource_id)"
    run "contract_check.py (pre-0039, tras rollback_0039)" sql-rb0039-contract env CONTRACT_SCHEMA=pre-0039 python3 "$CONTRACT_PY"
    expect_log "contract_check.py (pre-0039, tras rollback_0039)" sql-rb0039-contract "^${contract_pre39}/${contract_pre39} casos ok"

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
                expect_log "contract_check.py (tras reaplicar 0037, sin 0038)" sql-ra0037-contract "^${contract_pre39}/${contract_pre39} casos ok"
            else
                FAILED+=("ida y vuelta 0037 (sin 0035 reaplicada no se reaplica 0037: la BD local queda a medias, repetir ci.sh)")
            fi
        else
            FAILED+=("ida y vuelta 0037 (rollback_0037 no quedó en verde; no se sigue: la BD local queda a medias, repetir ci.sh)")
        fi

        if [ "$ra37_ok" = 1 ]; then
            run "SQL task_person_access_reapply_check" sql-ra0038 sql_expanded "$HERE/scripts/supabase/tests/task_person_access_reapply_check.sql"
            expect_log "SQL task_person_access_reapply_check" sql-ra0038 'ok RA38-1([^0-9]|$)'
            # 0039: solo se reaplica sobre 0038 reaplicada (RA38-1 en verde).
            if grep -Eq 'ok RA38-1([^0-9]|$)' "$OUT/sql-ra0038.log"; then ra38_ok=1; fi
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
            run "contract_check.py (pre-0039, tras reaplicar 0038)" sql-ra0038-contract env CONTRACT_SCHEMA=pre-0039 python3 "$CONTRACT_PY"
            expect_log "contract_check.py (pre-0039, tras reaplicar 0038)" sql-ra0038-contract "^${contract_pre39}/${contract_pre39} casos ok"
        else
            FAILED+=("ida y vuelta 0038 (sin 0037 reaplicada no se reaplica 0038: la BD local queda a medias, repetir ci.sh)")
        fi
    else
        FAILED+=("ida y vuelta 0038 (rollback_0038 no quedó en verde; no se sigue: la BD local queda a medias, repetir ci.sh)")
    fi

    if [ "$ra38_ok" = 1 ]; then
        run "SQL task_hidden_reapply_check" sql-ra0039 sql_expanded "$HERE/scripts/supabase/tests/task_hidden_reapply_check.sql"
        expect_log "SQL task_hidden_reapply_check" sql-ra0039 'ok RAH1([^0-9]|$)' 'ok RAH2([^0-9]|$)' 'ok RAH3([^0-9]|$)'
        sleep 1 # notify pgrst de 0039 antes de contract_check
        run "SQL task_hidden_check (tras reaplicar 0039)" sql-ra0039-th sql "$HERE/scripts/supabase/tests/task_hidden_check.sql"
        expect_log "SQL task_hidden_check (tras reaplicar 0039)" sql-ra0039-th "${h_pat[@]}"
        # Misma limpieza que antes de la pasada pre-0039: la pasada anterior dejó la client_request_id fija
        # del replay de prioridad apuntando a una tarea borrada. Solo BD local.
        run "SQL limpieza de client_request huérfanas (tras reaplicar 0039)" sql-ra0039-crclean "${PSQL_CMD[@]}" -v ON_ERROR_STOP=1 -c \
            "delete from client_request cr where cr.kind = 'task' and not exists (select 1 from task t where t.id = cr.resource_id)"
        run "contract_check.py (tras reaplicar 0039)" sql-ra0039-contract python3 "$CONTRACT_PY"
        expect_log "contract_check.py (tras reaplicar 0039)" sql-ra0039-contract "^${contract_full}/${contract_full} casos ok"
    else
        FAILED+=("ida y vuelta 0039 (sin 0038 reaplicada no se reaplica 0039: la BD local queda a medias, repetir ci.sh)")
    fi
else
    FAILED+=("ida y vuelta 0039 (rollback_0039 no quedó en verde; no se sigue: la BD local queda a medias, repetir ci.sh)")
fi

# Ida y vuelta 0040 → rollback_0040.sql → 0040 (lista-prioritaria-inicio): igual que la de 0035, pero sobre el
# esquema revertido contract_check corre con CONTRACT_POSITION=0 (sin `position` ni escenario de orden: 564).
# Si el rollback falla no se sigue (la BD local queda a medias: repetir ci.sh).
run "SQL task_list_position_rollback_check" sql-rb0040 sql_expanded "$HERE/scripts/supabase/tests/task_list_position_rollback_check.sql"
expect_log "SQL task_list_position_rollback_check" sql-rb0040 'ok TR1([^0-9]|$)' 'ok TR2([^0-9]|$)' 'ok TR3([^0-9]|$)'
if grep -Eq 'ok TR1([^0-9]|$)' "$OUT/sql-rb0040.log" && grep -Eq 'ok TR2([^0-9]|$)' "$OUT/sql-rb0040.log" \
    && grep -Eq 'ok TR3([^0-9]|$)' "$OUT/sql-rb0040.log"; then
    sleep 1 # notify pgrst del rollback: PostgREST recarga el esquema antes de contract_check
    run "SQL home_checks_compat (tras rollback_0040)" sql-rb0040-compat sql "$HERE/scripts/supabase/tests/home_checks_compat.sql"
    expect_log "SQL home_checks_compat (tras rollback_0040)" sql-rb0040-compat "${v_pat[@]}"
    run "SQL acl_can_edit_check (tras rollback_0040)" sql-rb0040-acl sql "$HERE/scripts/supabase/tests/acl_can_edit_check.sql"
    expect_log "SQL acl_can_edit_check (tras rollback_0040)" sql-rb0040-acl "${k_pat[@]}"
    run "SQL permisos_matriz_check (tras rollback_0040)" sql-rb0040-matriz sql "$HERE/scripts/supabase/tests/permisos_matriz_check.sql"
    expect_log "SQL permisos_matriz_check (tras rollback_0040)" sql-rb0040-matriz "${m_pat[@]}"
    # Misma limpieza que antes de las pasadas pre-0039: la pasada anterior dejó la client_request_id fija
    # del replay de prioridad apuntando a una tarea borrada. Solo BD local.
    run "SQL limpieza de client_request huérfanas (tras rollback_0040)" sql-rb0040-crclean "${PSQL_CMD[@]}" -v ON_ERROR_STOP=1 -c \
        "delete from client_request cr where cr.kind = 'task' and not exists (select 1 from task t where t.id = cr.resource_id)"
    run "contract_check.py (tras rollback_0040)" sql-rb0040-contract env CONTRACT_POSITION=0 python3 "$CONTRACT_PY"
    expect_log "contract_check.py (tras rollback_0040)" sql-rb0040-contract "^${contract_nopos}/${contract_nopos} casos ok"

    run "SQL task_list_position_reapply_check" sql-ra0040 sql_expanded "$HERE/scripts/supabase/tests/task_list_position_reapply_check.sql"
    expect_log "SQL task_list_position_reapply_check" sql-ra0040 'ok TA1([^0-9]|$)' 'ok TA2([^0-9]|$)'
    run "SQL task_list_position_check (tras reaplicar 0040)" sql-ra0040-tp sql "$HERE/scripts/supabase/tests/task_list_position_check.sql"
    expect_log "SQL task_list_position_check (tras reaplicar 0040)" sql-ra0040-tp "${tp_pat[@]}"
else
    FAILED+=("ida y vuelta 0040 (rollback_0040 no quedó en verde; no se reaplica 0040: la BD local queda a medias, repetir ci.sh)")
fi

# Ida y vuelta 0041 → rollback_0041.sql → 0041 (fecha-limite-vencimiento): el último cambio, en serie tras 0040.
# Tras revertir: task_due_set no existe y la columna due_at tampoco; el contrato corre sin due_at (clave
# opcional). Luego se reaplican 0041 y 0042 y se repite task_due_check DN1-DN9. Si el rollback falla no se sigue.
run "SQL rollback_0041" sql-rb0041 sql "$HERE/scripts/supabase/rollback/rollback_0041.sql"
if ! printf '%s\n' ${FAILED[@]+"${FAILED[@]}"} | grep -qx "SQL rollback_0041"; then
    sleep 1 # notify pgrst del rollback: PostgREST recarga el esquema antes de contract_check
    run "SQL 0041 revertida (sin task_due_set ni task.due_at)" sql-rb0041-ok "${PSQL_CMD[@]}" -v ON_ERROR_STOP=1 -c \
        "do \$\$ begin if to_regprocedure('public.task_due_set(bigint,text,boolean)') is not null or exists (select 1 from information_schema.columns where table_name='task' and column_name='due_at') then raise exception 'rollback_0041 incompleto'; end if; end \$\$"
    # Misma limpieza que tras rollback_0040: client_request de tareas borradas por la pasada anterior.
    run "SQL limpieza de client_request huérfanas (tras rollback_0041)" sql-rb0041-crclean "${PSQL_CMD[@]}" -v ON_ERROR_STOP=1 -c \
        "delete from client_request cr where cr.kind = 'task' and not exists (select 1 from task t where t.id = cr.resource_id)"
    run "contract_check.py (tras rollback_0041)" sql-rb0041-contract python3 "$CONTRACT_PY"
    expect_log "contract_check.py (tras rollback_0041)" sql-rb0041-contract "^${contract_full}/${contract_full} casos ok"
    run "SQL 0041 reaplicada" sql-ra0041 sql "$HERE/supabase/migrations/0041_task_due_at.sql"
    # 0042 reescribe task_due_set (guarda de p_due_at nulo, DN9): rollback_0041 la quitó, así que se reaplica tras 0041.
    run "SQL 0042 reaplicada" sql-ra0042 sql "$HERE/supabase/migrations/0042_task_due_set_null.sql"
    sleep 1
    run "SQL task_due_check (tras reaplicar 0041)" sql-ra0041-td sql "$HERE/scripts/supabase/tests/task_due_check.sql"
    expect_log "SQL task_due_check (tras reaplicar 0041)" sql-ra0041-td "${dn_pat[@]}"
else
    FAILED+=("ida y vuelta 0041 (rollback_0041 no quedó en verde; repetir ci.sh)")
fi

# Ida y vuelta 0048 → rollback_0048_menus_kito.sql → 0048 (kito-menus), la más exterior de las de menús (orden LIFO:
# 0048 redefine upsert_meal_plan_items sobre el cuerpo de 0045 y toca meal_plan y recipe, así que se revierte ANTES que
# 0045 y 0044 y se reaplica DESPUÉS de ellas). El rollback quita origin, state y las firmas nuevas. Si no queda en
# verde no se reaplica: la BD local queda a medias, repetir ci.sh.
run "SQL kito_menus_rollback_check" sql-rb0048 sql_expanded "$HERE/scripts/supabase/tests/kito_menus_rollback_check.sql"
expect_log "SQL kito_menus_rollback_check" sql-rb0048 'ok RK1([^0-9]|$)' 'ok RK2([^0-9]|$)' 'ok RK3([^0-9]|$)'
RB0048_OK=0
if grep -Eq 'ok RK1([^0-9]|$)' "$OUT/sql-rb0048.log" && grep -Eq 'ok RK2([^0-9]|$)' "$OUT/sql-rb0048.log" \
    && grep -Eq 'ok RK3([^0-9]|$)' "$OUT/sql-rb0048.log"; then
    RB0048_OK=1
else
    FAILED+=("ida y vuelta 0048 (rollback_0048 no quedó en verde; no se reaplica 0048: la BD local queda a medias, repetir ci.sh)")
fi

# Ida y vuelta 0047 → rollback_0047_menus_recetas_precargadas.sql → 0047 + seed (menus-recetas-precargadas): la más externa
# (orden LIFO: rollback_0045 restaura fn_meal_recipe_json de 0044 y rollback_0047 restaura la de 0045). El rollback borra
# las recetas comunes y la columna country; la reaplicación va tras reaplicar 0045 (más abajo). Si el rollback no queda en
# verde no se reaplica: la BD local queda a medias, repetir ci.sh.
run "SQL recetas_precargadas_rollback_check" sql-rb0047 sql_expanded "$HERE/scripts/supabase/tests/recetas_precargadas_rollback_check.sql"
expect_log "SQL recetas_precargadas_rollback_check" sql-rb0047 'ok RR1([^0-9]|$)' 'ok RR2([^0-9]|$)' 'ok RR3([^0-9]|$)'
RB0047_OK=0
if grep -Eq 'ok RR1([^0-9]|$)' "$OUT/sql-rb0047.log" && grep -Eq 'ok RR2([^0-9]|$)' "$OUT/sql-rb0047.log" \
    && grep -Eq 'ok RR3([^0-9]|$)' "$OUT/sql-rb0047.log"; then
    RB0047_OK=1
else
    FAILED+=("ida y vuelta 0047 (rollback_0047 no quedó en verde; no se reaplica 0047: la BD local queda a medias, repetir ci.sh)")
fi

# Ida y vuelta 0046 → rollback_0046_menus_paises_hogar.sql → 0046 (menus-paises-hogar), la más externa (orden LIFO: 0046
# redefine get/update_meal_profile de 0043 y rollback_0043 borra meal_profile, así que se revierte la primera y se
# reaplica la última, tras reaplicar 0043). Si el rollback no queda en verde no se reaplica: repetir ci.sh.
run "SQL meal_profile_countries_rollback_check" sql-rb0046 sql_expanded "$HERE/scripts/supabase/tests/meal_profile_countries_rollback_check.sql"
expect_log "SQL meal_profile_countries_rollback_check" sql-rb0046 'ok RC1([^0-9]|$)' 'ok RC2([^0-9]|$)' 'ok RC3([^0-9]|$)'
RB0046_OK=0
if grep -Eq 'ok RC1([^0-9]|$)' "$OUT/sql-rb0046.log" && grep -Eq 'ok RC2([^0-9]|$)' "$OUT/sql-rb0046.log" \
    && grep -Eq 'ok RC3([^0-9]|$)' "$OUT/sql-rb0046.log"; then
    RB0046_OK=1
else
    FAILED+=("ida y vuelta 0046 (rollback_0046 no quedó en verde; no se reaplica 0046: la BD local queda a medias, repetir ci.sh)")
fi

# Ida y vuelta 0045 → rollback_0045_menus_compra.sql → 0045 (menus-compra), anidada alrededor de la de 0044 (orden LIFO:
# shopping_item referencia meal_plan y food, y rollback_0044 los borra). El rollback quita la Compra y restaura
# accept_meal_plan y upsert_meal_plan_items de 0044; la reaplicación va después de reaplicar 0044 y la semilla. Si el
# rollback no queda en verde no se reaplica: la BD local queda a medias, repetir ci.sh.
run "SQL shopping_rollback_check" sql-rb0045 sql_expanded "$HERE/scripts/supabase/tests/shopping_rollback_check.sql"
expect_log "SQL shopping_rollback_check" sql-rb0045 'ok RS1([^0-9]|$)' 'ok RS2([^0-9]|$)' 'ok RS3([^0-9]|$)'
RB0045_OK=0
if grep -Eq 'ok RS1([^0-9]|$)' "$OUT/sql-rb0045.log" && grep -Eq 'ok RS2([^0-9]|$)' "$OUT/sql-rb0045.log" \
    && grep -Eq 'ok RS3([^0-9]|$)' "$OUT/sql-rb0045.log"; then
    RB0045_OK=1
else
    FAILED+=("ida y vuelta 0045 (rollback_0045 no quedó en verde; no se reaplica 0045: la BD local queda a medias, repetir ci.sh)")
fi

# Ida y vuelta 0044 → rollback_0044_menus_semana.sql → 0044 + semilla (menus-semana): ANTES que la de 0043 (orden
# LIFO: 0044 usa meal_profile, meal_schedule y las funciones de 0043, y rollback_0043 las borra). El rollback borra las
# tablas de menús y el catálogo; luego se reaplica 0044, se recarga la semilla y se repite menu_semana_check. Si el
# rollback no queda en verde no se reaplica: la BD local queda a medias, repetir ci.sh.
run "SQL menu_semana_rollback_check" sql-rb0044 sql_expanded "$HERE/scripts/supabase/tests/menu_semana_rollback_check.sql"
expect_log "SQL menu_semana_rollback_check" sql-rb0044 'ok RM4([^0-9]|$)' 'ok RM5([^0-9]|$)' 'ok RM6([^0-9]|$)'
if grep -Eq 'ok RM4([^0-9]|$)' "$OUT/sql-rb0044.log" && grep -Eq 'ok RM5([^0-9]|$)' "$OUT/sql-rb0044.log" \
    && grep -Eq 'ok RM6([^0-9]|$)' "$OUT/sql-rb0044.log"; then
    run "SQL 0044 reaplicada" sql-ra0044 sql "$HERE/supabase/migrations/0044_menus_semana.sql"
    run "SQL seed food_es (tras reaplicar 0044)" sql-ra0044-seed sql "$HERE/supabase/seed/food_es.sql"
    sleep 1 # notify pgrst: PostgREST recarga el esquema
    run "SQL menu_semana_reapply_check" sql-ra0044-chk sql "$HERE/scripts/supabase/tests/menu_semana_reapply_check.sql"
    expect_log "SQL menu_semana_reapply_check" sql-ra0044-chk 'ok RA3([^0-9]|$)' 'ok RA4([^0-9]|$)'
    run "SQL menu_semana_check (tras reaplicar 0044)" sql-ra0044-ms sql "$HERE/scripts/supabase/tests/menu_semana_check.sql"
    expect_log "SQL menu_semana_check (tras reaplicar 0044)" sql-ra0044-ms "${ms_pat[@]}"
else
    FAILED+=("ida y vuelta 0044 (rollback_0044 no quedó en verde; no se reaplica 0044: la BD local queda a medias, repetir ci.sh)")
fi

# Reaplicación de 0045 (cierra la ida y vuelta anidada de arriba, con 0044 y la semilla ya reaplicadas).
if [ "$RB0045_OK" = 1 ]; then
    run "SQL 0045 reaplicada" sql-ra0045 sql "$HERE/supabase/migrations/0045_menus_compra.sql"
    sleep 1 # notify pgrst: PostgREST recarga el esquema
    run "SQL shopping_reapply_check" sql-ra0045-chk sql "$HERE/scripts/supabase/tests/shopping_reapply_check.sql"
    expect_log "SQL shopping_reapply_check" sql-ra0045-chk 'ok RS4([^0-9]|$)'
    run "SQL shopping_check (tras reaplicar 0045)" sql-ra0045-sh sql "$HERE/scripts/supabase/tests/shopping_check.sql"
    expect_log "SQL shopping_check (tras reaplicar 0045)" sql-ra0045-sh "${sh_pat[@]}"
fi

# Ida y vuelta 0043 → rollback_0043_meal_profile.sql → 0043 (menus-perfil-hogar): el último cambio, en serie tras 0041/0042.
# El rollback borra las tablas meal_* y deja el catálogo en 23/37; luego se reaplica 0043 (el backfill vuelve a dar los
# menu.* a las membresías existentes) y se repiten meal_profile_check y contract_check. contract_check no corre sobre el
# esquema revertido (cuenta 28/47). Si el rollback falla no se sigue: la BD local queda a medias, repetir ci.sh.
run "SQL meal_profile_rollback_check" sql-rb0043 sql_expanded "$HERE/scripts/supabase/tests/meal_profile_rollback_check.sql"
expect_log "SQL meal_profile_rollback_check" sql-rb0043 'ok RM1([^0-9]|$)' 'ok RM2([^0-9]|$)' 'ok RM3([^0-9]|$)'
if grep -Eq 'ok RM1([^0-9]|$)' "$OUT/sql-rb0043.log" && grep -Eq 'ok RM2([^0-9]|$)' "$OUT/sql-rb0043.log" \
    && grep -Eq 'ok RM3([^0-9]|$)' "$OUT/sql-rb0043.log"; then
    run "SQL 0043 reaplicada" sql-ra0043 sql "$HERE/supabase/migrations/0043_meal_profile.sql"
    sleep 1 # notify pgrst: PostgREST recarga el esquema antes de contract_check
    run "SQL meal_profile_reapply_check" sql-ra0043-chk sql "$HERE/scripts/supabase/tests/meal_profile_reapply_check.sql"
    expect_log "SQL meal_profile_reapply_check" sql-ra0043-chk 'ok RA1([^0-9]|$)' 'ok RA2([^0-9]|$)'
    run "SQL meal_profile_check (tras reaplicar 0043)" sql-ra0043-mp sql "$HERE/scripts/supabase/tests/meal_profile_check.sql"
    expect_log "SQL meal_profile_check (tras reaplicar 0043)" sql-ra0043-mp "${mp_pat[@]}"
    run "SQL limpieza de client_request huérfanas (tras reaplicar 0043)" sql-ra0043-crclean "${PSQL_CMD[@]}" -v ON_ERROR_STOP=1 -c \
        "delete from client_request cr where cr.kind = 'task' and not exists (select 1 from task t where t.id = cr.resource_id)"
    run "contract_check.py (tras reaplicar 0043)" sql-ra0043-contract python3 "$CONTRACT_PY"
    expect_log "contract_check.py (tras reaplicar 0043)" sql-ra0043-contract "^${contract_full}/${contract_full} casos ok"
else
    FAILED+=("ida y vuelta 0043 (rollback_0043 no quedó en verde; no se reaplica 0043: la BD local queda a medias, repetir ci.sh)")
fi

# Reaplicación de 0046 (orden LIFO: rollback 0047 → 0046, reaplicación 0046 → 0047; con 0043–0045 ya reaplicadas).
if [ "$RB0046_OK" = 1 ]; then
    run "SQL 0046 reaplicada" sql-ra0046 sql "$HERE/supabase/migrations/0046_menus_paises_hogar.sql"
    sleep 1 # notify pgrst: PostgREST recarga el esquema
    run "SQL meal_profile_countries_reapply_check" sql-ra0046-chk sql "$HERE/scripts/supabase/tests/meal_profile_countries_reapply_check.sql"
    expect_log "SQL meal_profile_countries_reapply_check" sql-ra0046-chk 'ok RC4([^0-9]|$)'
    run "SQL meal_profile_countries_check (tras reaplicar 0046)" sql-ra0046-mc sql "$HERE/scripts/supabase/tests/meal_profile_countries_check.sql"
    expect_log "SQL meal_profile_countries_check (tras reaplicar 0046)" sql-ra0046-mc "${mc_pat[@]}"
    run "SQL meal_profile_check (tras reaplicar 0046)" sql-ra0046-mp sql "$HERE/scripts/supabase/tests/meal_profile_check.sql"
    expect_log "SQL meal_profile_check (tras reaplicar 0046)" sql-ra0046-mp "${mp_pat[@]}"
fi

# Reaplicación de 0047 y del seed de recetas (cierra la ida y vuelta de 0047, la última en reaplicarse, con 0043–0046 ya reaplicadas).
if [ "$RB0047_OK" = 1 ]; then
    run "SQL 0047 reaplicada" sql-ra0047 sql "$HERE/supabase/migrations/0047_menus_recetas_precargadas.sql"
    run "SQL seed recetas_precargadas (tras reaplicar 0047)" sql-ra0047-seed sql "$HERE/supabase/seed/recetas_precargadas.sql"
    expect_log "SQL seed recetas_precargadas (tras reaplicar 0047)" sql-ra0047-seed '^INSERT 0 [1-9][0-9]*'
    sleep 1 # notify pgrst: PostgREST recarga el esquema
    run "SQL recetas_precargadas_reapply_check" sql-ra0047-chk sql "$HERE/scripts/supabase/tests/recetas_precargadas_reapply_check.sql"
    expect_log "SQL recetas_precargadas_reapply_check" sql-ra0047-chk 'ok RA5([^0-9]|$)'
    run "SQL recetas_precargadas_check (tras reaplicar 0047)" sql-ra0047-rp sql "$HERE/scripts/supabase/tests/recetas_precargadas_check.sql"
    expect_log "SQL recetas_precargadas_check (tras reaplicar 0047)" sql-ra0047-rp "${rp_pat[@]}"
fi

# Reaplicación de 0048 (cierra la ida y vuelta exterior de kito-menus, la última en reaplicarse: con 0043–0047 y la semilla ya reaplicadas).
if [ "$RB0048_OK" = 1 ]; then
    run "SQL 0048 reaplicada" sql-ra0048 sql "$HERE/supabase/migrations/0048_menus_kito.sql"
    sleep 1 # notify pgrst: PostgREST recarga el esquema
    run "SQL kito_menus_reapply_check" sql-ra0048-chk sql "$HERE/scripts/supabase/tests/kito_menus_reapply_check.sql"
    expect_log "SQL kito_menus_reapply_check" sql-ra0048-chk 'ok RK4([^0-9]|$)'
    run "SQL kito_menus_check (tras reaplicar 0048)" sql-ra0048-mk sql "$HERE/scripts/supabase/tests/kito_menus_check.sql"
    expect_log "SQL kito_menus_check (tras reaplicar 0048)" sql-ra0048-mk "${mk_pat[@]}"
fi

# Reaplicación de 0050 (la más nueva) tras todas las ida y vueltas de migraciones anteriores.
run "SQL 0050 reaplicada (final)" sql-ra0050 sql "$HERE/supabase/migrations/0050_marcar_hecho.sql"
run "SQL marcar_hecho_check (tras reaplicar 0050, final)" sql-ra0050-check sql "$HERE/scripts/supabase/tests/marcar_hecho_check.sql"
expect_log "SQL marcar_hecho_check (tras reaplicar 0050, final)" sql-ra0050-check 'ok MH-clean'

if [ "${#FAILED[@]}" -gt 0 ]; then
    echo
    echo "FALLARON ${#FAILED[@]} paso(s):"
    printf '  - %s\n' "${FAILED[@]}"
    exit 1
fi
echo
echo "ci.sh: todo ok (deno check/test procesar-feedback y asistente; SQL incl. invitaciones N1-N22, K1-K8, client_request C1-C9, assistant_usage U1-U7, task_priority P1-P10, task_person_access A1-A9, get_persons GP1-GP4, task_hidden H1-H12, task_list_position TP1-TP8, meal_profile MP1-MP11, menu_semana MS1-MS17, guardas de rollback G0-G3, G38-1 y G39-1, feedback B1-B8 y F1-F12; contract_check ${contract_full}/${contract_full}, cross_tenant ${expected}/${expected}; ida y vuelta 0039 → rollback → [0038 → rollback → (0037 → rollback → (0035 → rollback → 0035) → 0037) → 0038] → 0039 con RBH1-5, contract pre-0039 ${contract_pre39}/${contract_pre39}, RB38-1..5, PR1-PR4, contract pre-0037 ${contract_pre}/${contract_pre}, RB1-RB4, guarda 0030 E0-E2, RA1-RA2, PA1-PA3, P1-P10, C1-C9, RA38-1, A1-A9, GP1-GP4, RAH1-3 y H1-H12; ida y vuelta 0040 con TR1-TR3, contract ${contract_nopos}/${contract_nopos} sin position, TA1-TA2 y TP1-TP8; ida y vuelta 0047 (la más externa) con RR1-RR3, RA5 y RP1-RP5; ida y vuelta 0045 (anidada en la de 0044) con RS1-RS4 y SH1-SH11; ida y vuelta 0044 con RM4-RM6, RA3-RA4 y MS1-MS17; shopping_check SH1-SH11; ida y vuelta 0043 con RM1-RM3, RA1-RA2 y MP1-MP11; meal_profile_countries_check MC1-MC5; ida y vuelta 0046 con RC1-RC4)"
