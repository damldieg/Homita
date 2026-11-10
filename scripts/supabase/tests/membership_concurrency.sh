#!/bin/bash
# membership_concurrency.sh — T5 del plan §6.1 (fase 1.6, T4): concurrencia determinista de
# 0018_home_membership_admin.sql. Dos admins degradándose a la vez sobre el mismo hogar: con el
# lock FOR UPDATE de fn_home_mutation_guard como primera sentencia, exactamente una de las dos
# llamadas falla (42501 'Not Allowed') y el hogar queda con 1 admin (§3.2). Tercera carrera (C):
# el mismo usuario saliendo de dos hogares activos a la vez (conteo D13, R1-01).
#
# Sub-escenarios (una pasada = los tres):
#   A (principal, §3.2 tabla): S1 = A degrada a B (transacción abierta, retiene el lock);
#   S2 = A se degrada a sí mismo → 'Not Allowed' (último admin: B ya es member tras S1).
#   B (variante): S1 = A degrada a B; S2 = B degrada a A → 'Not Allowed' por no admin (B ya member).
#   C (cross-home D13, R1-01 del code-review ronda 1): U con exactamente 2 hogares activos;
#   S1 = U sale de H1 (transacción abierta); S2 = U sale de H2 → 'Not Allowed' (D13: el lock de
#   app_user que retiene S1 serializa la salida y el conteo de S2 ve 1 hogar) y U conserva
#   1 membresía activa. PRE-fix (0018 sin `for update` de app_user) el repro FALLA: S2 no se
#   bloquea en ningún lock (el de home es por hogar y las filas tocadas son distintas) → ambas
#   salidas con éxito → U con 0 hogares activos, D13 violado (demostrado por ejecución antes del
#   fix: logs/repro-d13-prefix.log, s1_rc=0 s2_rc=0 membresías=0). Con el fix, el poll de Lock
#   observa la espera de S2 en app_user y el test pasa.
#
# Coordinación (§6.1 T5): S1 es un psql en background leyendo de un FIFO (mkfifo en mktemp -d); se
# le escribe `begin;` + la RPC sin `commit`. Para que la carrera sea determinista (S1 debe retener
# el lock ANTES de que S2 ejecute: sin esto, la primera sentencia de S2 gana la carrera y el test
# queda ruidoso), se hace poll (≤10 s, intervalo 0.2 s) hasta ver a S1 en 'idle in transaction'
# (su RPC ya devolvió con el lock tomado). Después S2 (application_name='mc_s2',
# statement_timeout='15s') se bloquea en el lock de home y el poll (≤10 s, 0.2 s) observa
# application_name='mc_s2' AND wait_event_type='Lock' = 1 en pg_stat_activity; si no se observa, el
# test falla (sin reintentos ni sleeps fijos). Por último se escribe `commit;` al FIFO y se cierra.
#
# Esperado: S1 exit 0 sin ERROR; S2 contiene 42501 'Not Allowed'; admins = 1 (A/B) y U con
# 1 membresía activa (C). Datos scratch 995xxx (auth_uid 00000000-0000-4000-8000-000000000981–0985)
# borrados al final; la limpieza
# también corre al inicio (idempotente tras un fallo). Alta scratch con
# session_replication_role = replica para saltarse la FK app_user→auth.users (patrón de 1.5).
#
# Variables de entorno: PSQL = comando psql completo (default: psql). Para el stack local:
#   PSQL="docker exec -i supabase_db_homita-api psql -U postgres -d postgres"
# Uso: bash scripts/supabase/tests/membership_concurrency.sh   (2 pasadas seguidas = T4 del plan)
set -euo pipefail

# shellcheck disable=SC2086  # $PSQL se separa en palabras a propósito (comando + argumentos)
PSQL_CMD=${PSQL:-psql}

run_sql() {  # SQL por stdin; falla el script si psql falla
    $PSQL_CMD -X -q -v ON_ERROR_STOP=1
}

psql_val() {  # SQL por stdin; devuelve una fila (-t -A)
    $PSQL_CMD -X -q -t -A -v ON_ERROR_STOP=1
}

SCRATCH_SQL=$(cat <<'SQL'
begin;
delete from membership_permission where home_membership_id between 995101 and 995108;
delete from home_membership where id between 995101 and 995108;
delete from home where id in (995001, 995002, 995003, 995004);
delete from app_user where id between 995001 and 995005;
delete from auth.users where id between '00000000-0000-4000-8000-000000000981'
                                   and '00000000-0000-4000-8000-000000000985';
commit;
SQL
)

fail() {
    set +e
    exec 3>&- 2>/dev/null  # EOF al FIFO: S1 sale y revierte su transacción abierta
    echo "FAIL $1"
    echo "$SCRATCH_SQL" | run_sql >/dev/null 2>&1
    exit 1
}

# ── scratch: usuarios/hogares/membresías de los tres sub-escenarios (limpieza + alta) ──
echo "$SCRATCH_SQL" | run_sql >/dev/null
run_sql >/dev/null <<'SQL'
begin;
set session_replication_role = replica;
insert into auth.users (id, email, raw_user_meta_data) values
    ('00000000-0000-4000-8000-000000000981', 'mc-c1@check.homita.example', '{"name": "MC-C1"}'),
    ('00000000-0000-4000-8000-000000000982', 'mc-c2@check.homita.example', '{"name": "MC-C2"}'),
    ('00000000-0000-4000-8000-000000000983', 'mc-c3@check.homita.example', '{"name": "MC-C3"}'),
    ('00000000-0000-4000-8000-000000000984', 'mc-c4@check.homita.example', '{"name": "MC-C4"}'),
    ('00000000-0000-4000-8000-000000000985', 'mc-c5@check.homita.example', '{"name": "MC-C5"}')
on conflict (id) do nothing;
insert into app_user (id, auth_uid, name, email) values
    (995001, '00000000-0000-4000-8000-000000000981', 'MC-C1', 'mc-c1@check.homita.example'),
    (995002, '00000000-0000-4000-8000-000000000982', 'MC-C2', 'mc-c2@check.homita.example'),
    (995003, '00000000-0000-4000-8000-000000000983', 'MC-C3', 'mc-c3@check.homita.example'),
    (995004, '00000000-0000-4000-8000-000000000984', 'MC-C4', 'mc-c4@check.homita.example'),
    (995005, '00000000-0000-4000-8000-000000000985', 'MC-C5', 'mc-c5@check.homita.example')
on conflict (id) do nothing;
set session_replication_role = default;
insert into home (id, name, status, is_personal, created_by) values
    (995001, 'MC Concurrencia A', 'active', false, 995001),
    (995002, 'MC Concurrencia B', 'active', false, 995003),
    (995003, 'MC D13 A', 'active', false, 995001),
    (995004, 'MC D13 B', 'active', false, 995001);
insert into home_membership (id, home_id, app_user_id, role) values
    (995101, 995001, 995001, 'admin'),
    (995102, 995001, 995002, 'admin'),
    (995103, 995002, 995003, 'admin'),
    (995104, 995002, 995004, 'admin'),
    (995107, 995003, 995001, 'admin'),
    (995108, 995004, 995001, 'admin'),
    (995105, 995003, 995005, 'member'),
    (995106, 995004, 995005, 'member');
commit;
SQL

# ── run_pair: S1 (FIFO, transacción abierta) + S2 (bloqueada) + polls + commit de S1 ──
# $1 = hogar; $2 = uuid de S2; $3 = membresía objetivo de S1; $4 = membresía objetivo de S2;
# $5 = uuid de S1; $6 = nombre del sub-escenario
run_pair() {
    local home=$1 s2_uuid=$2 s1_target=$3 s2_target=$4 s1_uuid=$5 name=$6
    local tmp fifo s1_pid s2_pid n s1_rc s2_rc admin ready locked
    tmp=$(mktemp -d)
    fifo="$tmp/s1.sql"
    mkfifo "$fifo"

    # S1: psql en background leyendo del FIFO (set +e: el rc se captura en fichero)
    ( set +e; $PSQL_CMD -X -q > "$tmp/s1.out" 2>&1 < "$fifo"; echo $? > "$tmp/s1.rc" ) &
    s1_pid=$!
    exec 3>"$fifo"  # bloquea hasta que S1 abre el FIFO para lectura
    printf "set application_name = 'mc_s1';\nbegin;\n" >&3
    printf "select set_config('request.jwt.claim.sub', '%s', true);\n" "$s1_uuid" >&3
    printf "select set_home_membership_role(%s, %s, 'member');\n" "$home" "$s1_target" >&3

    # Poll previo: S1 debe haber ejecutado su RPC (lock retenido, transacción abierta) antes de
    # lanzar S2 — sin esto la primera sentencia de S2 gana la carrera y el test queda ruidoso.
    ready=0
    for n in $(seq 1 50); do
        if [ "$(psql_val <<SQL
select count(*) from pg_stat_activity
 where application_name = 'mc_s1' and state = 'idle in transaction';
SQL
)" = "1" ]; then
            ready=1
            break
        fi
        sleep 0.2
    done
    if [ "$ready" -ne 1 ]; then
        cat "$tmp/s1.out" 2>/dev/null || true
        fail "$name: S1 no llegó a 'idle in transaction' (¿falló la RPC?) en 10 s"
    fi

    # S2: se bloquea en el lock de home (fn_home_mutation_guard)
    ( set +e; $PSQL_CMD -X -q -v ON_ERROR_STOP=1 -v VERBOSITY=verbose > "$tmp/s2.out" 2>&1 <<SQL
set application_name = 'mc_s2';
set statement_timeout = '15s';
select set_config('request.jwt.claim.sub', '$s2_uuid', false);
select set_home_membership_role($home, $s2_target, 'member');
SQL
        echo $? > "$tmp/s2.rc" ) &
    s2_pid=$!

    # Poll (§6.1 T5): S2 con wait_event_type='Lock' (≤10 s, intervalo 0.2 s; sin sleep fijo previo)
    locked=0
    for n in $(seq 1 50); do
        if [ "$(psql_val <<SQL
select count(*) from pg_stat_activity
 where application_name = 'mc_s2' and wait_event_type = 'Lock';
SQL
)" = "1" ]; then
            locked=1
            break
        fi
        sleep 0.2
    done
    if [ "$locked" -ne 1 ]; then
        cat "$tmp/s2.out" 2>/dev/null || true
        fail "$name: S2 no apareció bloqueada en pg_stat_activity (wait_event_type='Lock') en 10 s"
    fi

    # S1: commit y cierre del FIFO
    printf 'commit;\n' >&3
    exec 3>&-
    set +e
    wait "$s1_pid"
    s1_rc=$(cat "$tmp/s1.rc")
    wait "$s2_pid"
    s2_rc=$(cat "$tmp/s2.rc")
    set -e

    if [ "$s1_rc" -ne 0 ] || grep -q "ERROR" "$tmp/s1.out"; then
        cat "$tmp/s1.out"
        fail "$name: S1 falló (rc=$s1_rc; esperado 0 sin ERROR)"
    fi
    if [ "$s2_rc" -eq 0 ]; then
        cat "$tmp/s2.out"
        fail "$name: S2 terminó bien (esperaba 42501 'Not Allowed')"
    fi
    if ! grep -q "42501" "$tmp/s2.out" || ! grep -q "Not Allowed" "$tmp/s2.out"; then
        cat "$tmp/s2.out"
        fail "$name: la salida de S2 no contiene 42501 'Not Allowed'"
    fi
    admin=$(psql_val <<SQL
select count(*) from home_membership where home_id = $home and role = 'admin';
SQL
)
    if [ "$admin" != "1" ]; then
        fail "$name: admins = $admin tras la carrera (esperado 1)"
    fi
    echo "ok   $name: S2 bloqueada en Lock → 42501 Not Allowed; admins = 1 (S1 rc=0)"
    rm -rf "$tmp"
}

# ── run_pair_d13: carrera cross-home sobre el conteo D13 de remove_home_membership (R1-01) ──
# Mismo patrón FIFO + pre-poll + Lock-poll que run_pair. $1 = hogar de S1; $2 = hogar de S2;
# $3 = membresía objetivo de S1; $4 = membresía objetivo de S2; $5 = uuid de U (ambas sesiones);
# $6 = app_user de U; $7 = nombre del sub-escenario. Esperado post-fix: S1 rc=0; S2 → 42501
# 'Not Allowed' (bloqueada en el lock de app_user, R1-01); U conserva 1 membresía activa.
run_pair_d13() {
    local home1=$1 home2=$2 s1_target=$3 s2_target=$4 uuid=$5 user=$6 name=$7
    local tmp fifo s1_pid s2_pid n s1_rc s2_rc left ready locked
    tmp=$(mktemp -d)
    fifo="$tmp/s1.sql"
    mkfifo "$fifo"

    ( set +e; $PSQL_CMD -X -q > "$tmp/s1.out" 2>&1 < "$fifo"; echo $? > "$tmp/s1.rc" ) &
    s1_pid=$!
    exec 3>"$fifo"  # bloquea hasta que S1 abre el FIFO para lectura
    printf "set application_name = 'mc_s1';\nbegin;\n" >&3
    printf "select set_config('request.jwt.claim.sub', '%s', true);\n" "$uuid" >&3
    printf "select remove_home_membership(%s, %s);\n" "$home1" "$s1_target" >&3

    ready=0
    for n in $(seq 1 50); do
        if [ "$(psql_val <<SQL
select count(*) from pg_stat_activity
 where application_name = 'mc_s1' and state = 'idle in transaction';
SQL
)" = "1" ]; then
            ready=1
            break
        fi
        sleep 0.2
    done
    if [ "$ready" -ne 1 ]; then
        cat "$tmp/s1.out" 2>/dev/null || true
        fail "$name: S1 no llegó a 'idle in transaction' (¿falló la RPC?) en 10 s"
    fi

    # S2: sale del OTRO hogar del mismo usuario. Post-fix se bloquea en el lock de app_user
    # (R1-01) que S1 retiene; pre-fix (sin ese lock) no se bloquearía en nada — los locks eran por
    # hogar y las filas tocadas, distintas — y este poll fallaría: ese es exactamente el repro
    # PRE-fix (demostrado por ejecución: logs/repro-d13-prefix.log, ambas salidas con éxito y
    # U con 0 hogares activos, D13 violado).
    ( set +e; $PSQL_CMD -X -q -v ON_ERROR_STOP=1 -v VERBOSITY=verbose > "$tmp/s2.out" 2>&1 <<SQL
set application_name = 'mc_s2';
set statement_timeout = '15s';
select set_config('request.jwt.claim.sub', '$uuid', false);
select remove_home_membership($home2, $s2_target);
SQL
        echo $? > "$tmp/s2.rc" ) &
    s2_pid=$!

    locked=0
    for n in $(seq 1 50); do
        if [ "$(psql_val <<SQL
select count(*) from pg_stat_activity
 where application_name = 'mc_s2' and wait_event_type = 'Lock';
SQL
)" = "1" ]; then
            locked=1
            break
        fi
        sleep 0.2
    done
    if [ "$locked" -ne 1 ]; then
        cat "$tmp/s2.out" 2>/dev/null || true
        fail "$name: S2 no apareció bloqueada en pg_stat_activity (wait_event_type='Lock') en 10 s (¿sin el lock de app_user de R1-01?)"
    fi

    printf 'commit;\n' >&3
    exec 3>&-
    set +e
    wait "$s1_pid"
    s1_rc=$(cat "$tmp/s1.rc")
    wait "$s2_pid"
    s2_rc=$(cat "$tmp/s2.rc")
    set -e

    if [ "$s1_rc" -ne 0 ] || grep -q "ERROR" "$tmp/s1.out"; then
        cat "$tmp/s1.out"
        fail "$name: S1 falló (rc=$s1_rc; esperado 0 sin ERROR)"
    fi
    if [ "$s2_rc" -eq 0 ]; then
        cat "$tmp/s2.out"
        fail "$name: S2 terminó bien (esperaba 42501 'Not Allowed')"
    fi
    if ! grep -q "42501" "$tmp/s2.out" || ! grep -q "Not Allowed" "$tmp/s2.out"; then
        cat "$tmp/s2.out"
        fail "$name: la salida de S2 no contiene 42501 'Not Allowed'"
    fi
    left=$(psql_val <<SQL
select count(*) from home_membership hm
join home h on h.id = hm.home_id and h.status = 'active'
where hm.app_user_id = $user;
SQL
)
    if [ "$left" != "1" ]; then
        fail "$name: U conserva $left membresías activas tras la carrera (esperado 1, D13)"
    fi
    echo "ok   $name: S2 bloqueada en Lock → 42501 Not Allowed; U conserva 1 membresía activa (S1 rc=0)"
    rm -rf "$tmp"
}

# ── A (principal): S1 = A degrada a B; S2 = A se degrada a sí mismo ──
run_pair 995001 '00000000-0000-4000-8000-000000000981' 995102 995101 \
    '00000000-0000-4000-8000-000000000981' "concurrencia A: A degrada a B y A se degrada a sí mismo"

# ── B (variante): S1 = A degrada a B; S2 = B degrada a A ('Not Allowed' por no admin) ──
run_pair 995002 '00000000-0000-4000-8000-000000000984' 995104 995103 \
    '00000000-0000-4000-8000-000000000983' "concurrencia B: A degrada a B y B degrada a A"

# ── C (cross-home D13, R1-01): S1 = U sale de H1; S2 = U sale de H2 (mismo usuario, hogares
# distintos: la carrera que el lock de app_user serializa) ──
run_pair_d13 995003 995004 995105 995106 \
    '00000000-0000-4000-8000-000000000985' 995005 \
    "concurrencia C: U sale de dos hogares activos a la vez (cross-home D13)"

# ── Limpieza de los datos scratch ──
echo "$SCRATCH_SQL" | run_sql >/dev/null

echo "membership_concurrency: 3 sub-escenarios verdes (exactamente una falla por carrera; A/B hogar con admin, C D13 con U en 1 hogar)"
