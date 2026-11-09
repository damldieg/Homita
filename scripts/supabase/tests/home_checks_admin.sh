#!/bin/bash
# home_checks_admin.sh — V5h del plan 1.3 (CA-11 de 1.1 + R1-06): trigger anti-hogar-sin-admin
# diferido de 0015_home_constraints.sql. Los casos negativos exigen un COMMIT que falla con
# 'Not Allowed' SQLSTATE 42501 — imposible de atrapar dentro de un bloque DO de SQL — por eso este
# script ejecuta cada escenario como su propia transacción psql y analiza la salida (VERBOSITY
# verbose muestra el SQLSTATE).
#
# Escenarios: hogar active con un único admin → degradar/borrar la membresía/borrar el app_user
# (cascade) deja el COMMIT en 42501 (S1–S3); dos admins y degradar uno → COMMIT correcto (S4);
# hogar archived sin admin → COMMIT correcto (S5). Los fallidos hacen rollback completo (sin
# residuos); los correctos limpian sus filas scratch (ids 992xxx, app_user sin auth_uid).
#
# Variables de entorno: PSQL = comando psql completo (default: psql). Para el stack local:
#   PSQL="docker exec -i supabase_db_homita-api psql -U postgres -d postgres"
# Uso: bash scripts/supabase/tests/home_checks_admin.sh
set -euo pipefail

# shellcheck disable=SC2086  # $PSQL se separa en palabras a propósito (comando + argumentos)
PSQL_CMD=${PSQL:-psql}

run_sql() {  # SQL por stdin; falla el script si psql falla
    $PSQL_CMD -X -q -v ON_ERROR_STOP=1
}

expect_commit_fail() {  # $1 = nombre; SQL por stdin; espera 42501 'Not Allowed' en COMMIT
    local name=$1 out rc
    set +e
    out=$($PSQL_CMD -X -q -v ON_ERROR_STOP=1 -v VERBOSITY=verbose 2>&1)
    rc=$?
    set -e
    if [ "$rc" -eq 0 ]; then
        echo "FAIL $name: el COMMIT no falló (se esperaba 'Not Allowed' 42501)"
        exit 1
    fi
    if ! grep -q "42501" <<<"$out" || ! grep -q "Not Allowed" <<<"$out"; then
        echo "FAIL $name: la salida no contiene 42501 'Not Allowed':"
        echo "$out"
        exit 1
    fi
    echo "ok   $name"
}

expect_commit_ok() {  # $1 = nombre; SQL por stdin; espera COMMIT correcto
    local name=$1
    if run_sql >/dev/null; then
        echo "ok   $name"
    else
        echo "FAIL $name: el COMMIT falló y debía ser correcto"
        exit 1
    fi
}

# ── S1: degradar al único admin de un hogar active → COMMIT falla ──
expect_commit_fail "V5h S1: degradar al único admin → Not Allowed 42501" <<'SQL'
begin;
insert into app_user (id, name, email) values (992001, 'V5h-Admin', 'v5h-a@check.homita.example');
insert into home (id, name, status, is_personal, created_by)
    values (992001, 'V5h Hogar Uno', 'active', false, 992001);
insert into home_membership (home_id, app_user_id, role) values (992001, 992001, 'admin');
update home_membership set role = 'member' where home_id = 992001 and app_user_id = 992001;
commit;
SQL

# ── S2: borrar la membresía del único admin → COMMIT falla ──
expect_commit_fail "V5h S2: borrar la membresía del único admin → Not Allowed 42501" <<'SQL'
begin;
insert into app_user (id, name, email) values (992002, 'V5h-Admin', 'v5h-b@check.homita.example');
insert into home (id, name, status, is_personal, created_by)
    values (992002, 'V5h Hogar Dos', 'active', false, 992002);
insert into home_membership (home_id, app_user_id, role) values (992002, 992002, 'admin');
delete from home_membership where home_id = 992002 and app_user_id = 992002;
commit;
SQL

# ── S3: borrar el app_user del único admin (cascade) → COMMIT falla ──
expect_commit_fail "V5h S3: borrar el app_user del único admin → Not Allowed 42501" <<'SQL'
begin;
insert into app_user (id, name, email) values (992003, 'V5h-Admin', 'v5h-c@check.homita.example');
insert into home (id, name, status, is_personal, created_by)
    values (992003, 'V5h Hogar Tres', 'active', false, 992003);
insert into home_membership (home_id, app_user_id, role) values (992003, 992003, 'admin');
delete from app_user where id = 992003;
commit;
SQL

# ── S4: dos admins, degradar uno → COMMIT correcto ──
expect_commit_ok "V5h S4: dos admins, degradar uno → COMMIT correcto" <<'SQL'
begin;
insert into app_user (id, name, email) values (992004, 'V5h-Admin', 'v5h-d@check.homita.example');
insert into app_user (id, name, email) values (992005, 'V5h-Admin', 'v5h-e@check.homita.example');
insert into home (id, name, status, is_personal, created_by)
    values (992004, 'V5h Hogar Cuatro', 'active', false, 992004);
insert into home_membership (home_id, app_user_id, role) values (992004, 992004, 'admin');
insert into home_membership (home_id, app_user_id, role) values (992004, 992005, 'admin');
update home_membership set role = 'member' where home_id = 992004 and app_user_id = 992005;
commit;
SQL

# ── S5: hogar archived sin admin → COMMIT correcto ──
expect_commit_ok "V5h S5: hogar archived sin admin → COMMIT correcto" <<'SQL'
begin;
insert into app_user (id, name, email) values (992006, 'V5h-Admin', 'v5h-f@check.homita.example');
insert into home (id, name, status, is_personal, created_by)
    values (992005, 'V5h Hogar Cinco', 'archived', false, 992006);
insert into home_membership (home_id, app_user_id, role) values (992005, 992006, 'admin');
delete from home_membership where home_id = 992005 and app_user_id = 992006;
commit;
SQL

# ── Limpieza de los escenarios S4/S5 (los S1–S3 revierten solos) ──
run_sql >/dev/null <<'SQL'
begin;
delete from membership_permission where home_membership_id in
    (select id from home_membership where home_id in (992004, 992005));
delete from home_membership where home_id in (992004, 992005);
delete from home where id in (992004, 992005);
delete from app_user where id in (992004, 992005, 992006);
commit;
SQL

echo "V5h: 5 escenarios anti-admin verdes (3 COMMIT 42501, 2 COMMIT correcto)"
