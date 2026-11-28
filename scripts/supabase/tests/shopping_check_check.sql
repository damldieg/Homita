-- shopping_check_check.sql — La pantalla marca la compra (0055, dashboard-menu-compra fase B).
-- Solo BD local, tras aplicar 0055:  psql -v ON_ERROR_STOP=1 -f shopping_check_check.sql
-- Cada bloque emite 'ok Sx' o aborta con 'shopping_check Sx: …'.
--
-- Fixture (ids 995xxx, auth_uid …0951–…0954): hogar H (995001) con A admin (995001), B adulto con menu.shopping.edit
-- (995002), D pantalla (995003, member con menu.view y menu.shopping.check). Hogar O (995002) con C admin (995004).
-- Artículos: H (995001 HS-Leche, 995002 HS-Pan) y O (995003 OS-Huevos).
--
-- S1 la pantalla marca como comprado (checked) y audita con source display.
-- S2 la pantalla desmarca (pending).
-- S3 la pantalla no puede poner «ya lo tengo» (skipped) → 42501.
-- S4 la pantalla no toca un artículo de otro hogar → Not Found.
-- S5 la pantalla no cambia cantidades ni borra → 42501.
-- S6 idempotencia: misma clave y mismo artículo no repiten el cambio; la clave de otro artículo → Invalid client_request_id.
-- S7 auditoría: una fila por cambio real de la pantalla (S1, S2 y S6; el replay de S6 no añade ninguna).
-- S8 adulto con edición sí puede «ya lo tengo» (regresión).
-- S9 usuario de otro hogar (C) no marca artículos de H → Not Found.
-- S10 grants: authenticated puede ejecutar la RPC nueva; anon, no.
-- Al final, limpieza y 'ok S-clean'.

\set ON_ERROR_STOP 1
do $$
begin
    if inet_server_addr() is not null and host(inet_server_addr()) not in ('127.0.0.1', '::1') then
        raise exception 'shopping_check: solo BD local (socket o loopback); servidor %', host(inet_server_addr());
    end if;
    if to_regprocedure('public.set_shopping_item_state(bigint,text,uuid)') is null then
        raise exception 'shopping_check: 0055 no está aplicada';
    end if;
end $$;

create function pg_temp.clean() returns void
language plpgsql as $$
begin
    set local session_replication_role = replica;
    delete from audit_log where home_id in (995001, 995002);
    delete from client_request where app_user_id between 995001 and 995005;
    delete from shopping_item where home_id in (995001, 995002);
    delete from home_display where home_id in (995001, 995002);
    delete from membership_permission where home_membership_id between 995001 and 995009;
    delete from home_member where home_id in (995001, 995002);
    delete from home_membership where home_id in (995001, 995002);
    update app_user set default_home_id = null where id between 995001 and 995005;
    delete from home where id in (995001, 995002);
    delete from app_user where id between 995001 and 995005;
    delete from auth.users where id::text like '00000000-0000-4000-8000-00000000095%';
end $$;

-- Ejecuta p_sql y exige el sqlstate p_state (y el mensaje, si se pasa).
create function pg_temp.fails(p_label text, p_sql text, p_state text, p_msg text default null) returns void
language plpgsql as $$
begin
    execute p_sql;
    raise exception 'shopping_check %: no falló: %', p_label, p_sql;
exception when others then
    if sqlstate <> p_state or (p_msg is not null and sqlerrm <> p_msg) then
        raise exception 'shopping_check %: % % (esperado % %)', p_label, sqlstate, sqlerrm, p_state, coalesce(p_msg, '');
    end if;
end $$;

-- Compara lo devuelto con lo esperado.
create function pg_temp.want(p_label text, p_got text, p_want text) returns void
language plpgsql as $$
begin
    if p_got is distinct from p_want then
        raise exception 'shopping_check %: obtenido % (esperado %)', p_label, p_got, p_want;
    end if;
end $$;

create function pg_temp.as_user(p_n int) returns void
language sql as $$
    select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-00000000095' || p_n, true)
$$;

select pg_temp.clean();

-- ── Fixture ──
set session_replication_role = replica;
insert into auth.users (id, email, raw_user_meta_data) values
    ('00000000-0000-4000-8000-000000000951', 'sc-a@check.homita.example', '{"name":"SC-A"}'),
    ('00000000-0000-4000-8000-000000000952', 'sc-b@check.homita.example', '{"name":"SC-B"}'),
    ('00000000-0000-4000-8000-000000000953', 'sc-d@check.homita.example', '{"name":"SC-D"}'),
    ('00000000-0000-4000-8000-000000000954', 'sc-c@check.homita.example', '{"name":"SC-C"}');
insert into app_user (id, auth_uid, name, email) values
    (995001, '00000000-0000-4000-8000-000000000951', 'SC-A', 'sc-a@check.homita.example'),
    (995002, '00000000-0000-4000-8000-000000000952', 'SC-B', 'sc-b@check.homita.example'),
    (995003, '00000000-0000-4000-8000-000000000953', 'SC-D', 'sc-d@check.homita.example'),
    (995004, '00000000-0000-4000-8000-000000000954', 'SC-C', 'sc-c@check.homita.example');
set session_replication_role = default;

-- El hogar y su administrador van en la misma transacción (fn_check_home_has_admin).
begin;
insert into home (id, name, status, is_personal, created_by) values
    (995001, 'SC-Hogar H', 'active', false, 995001),
    (995002, 'SC-Hogar O', 'active', false, 995004);
insert into home_membership (id, home_id, app_user_id, role) values
    (995001, 995001, 995001, 'admin'),
    (995002, 995001, 995002, 'member'),
    (995003, 995001, 995003, 'member'),
    (995004, 995002, 995004, 'admin');
update app_user set default_home_id = 995001 where id in (995001, 995002, 995003);
update app_user set default_home_id = 995002 where id = 995004;
insert into membership_permission (home_membership_id, permission_code) values
    (995002, 'menu.shopping.edit'), (995003, 'menu.view'), (995003, 'menu.shopping.check');
insert into home_member (id, home_id, kind, name, app_user_id) values
    (995001, 995001, 'display', 'SC-Pantalla', 995003);
insert into home_display (id, home_id, app_user_id, home_member_id, name, linked_by) values
    (995001, 995001, 995003, 995001, 'SC-Pantalla', 995001);
insert into shopping_item (id, home_id, label, unit, section, origin, sources, qty_overridden, state, cleared, created_at, updated_at) values
    (995001, 995001, 'HS-Leche', 'l', 'lacteos', 'manual', '[]', false, 'pending', false, now(), now()),
    (995002, 995001, 'HS-Pan', 'ud', 'panaderia', 'manual', '[]', false, 'pending', false, now(), now()),
    (995003, 995002, 'OS-Huevos', 'ud', 'huevos', 'manual', '[]', false, 'pending', false, now(), now());
commit;

-- ── S1 ──
begin;
select pg_temp.as_user(3);
select pg_temp.want('S1', set_shopping_item_state(995001, 'checked') ->> 'state', 'checked');
commit;
\echo ok S1

-- ── S2 ──
begin;
select pg_temp.as_user(3);
select pg_temp.want('S2', set_shopping_item_state(995001, 'pending') ->> 'state', 'pending');
commit;
\echo ok S2

-- ── S3, S4, S5 ──
begin;
select pg_temp.as_user(3);
select pg_temp.fails('S3', $q$select set_shopping_item_state(995002, 'skipped')$q$, '42501');
commit;
\echo ok S3

begin;
select pg_temp.as_user(3);
select pg_temp.fails('S4', $q$select set_shopping_item_state(995003, 'checked')$q$, 'P0002', 'Not Found');
commit;
\echo ok S4

begin;
select pg_temp.as_user(3);
select pg_temp.fails('S5a', $q$select update_shopping_item_qty(995001, 2, 'ud')$q$, '42501');
select pg_temp.fails('S5b', $q$select delete_shopping_item(995001)$q$, '42501');
commit;
\echo ok S5

-- ── S6, S7 ──
begin;
select pg_temp.as_user(3);
select pg_temp.want('S6a', set_shopping_item_state(995002, 'checked', '11111111-1111-4111-8111-111111111111') ->> 'state', 'checked');
select pg_temp.want('S6b', set_shopping_item_state(995002, 'checked', '11111111-1111-4111-8111-111111111111') ->> 'state', 'checked');
select pg_temp.fails('S6c', $q$select set_shopping_item_state(995001, 'checked', '11111111-1111-4111-8111-111111111111')$q$, 'P0001', 'Invalid client_request_id');
commit;
\echo ok S6

select pg_temp.want('S7', (select count(*)::text from audit_log where actor_app_user_id = 995003 and home_id = 995001), '3');
\echo ok S7

-- ── S8 ──
begin;
select pg_temp.as_user(2);
select pg_temp.want('S8', set_shopping_item_state(995002, 'skipped') ->> 'state', 'skipped');
commit;
\echo ok S8

-- ── S9 ──
begin;
select pg_temp.as_user(4);
select pg_temp.fails('S9', $q$select set_shopping_item_state(995001, 'checked')$q$, 'P0002', 'Not Found');
commit;
\echo ok S9

-- ── S10 ──
do $$
begin
    if not has_function_privilege('authenticated', 'public.set_shopping_item_state(bigint,text,uuid)', 'EXECUTE') then
        raise exception 'shopping_check S10: authenticated sin EXECUTE';
    end if;
    if has_function_privilege('anon', 'public.set_shopping_item_state(bigint,text,uuid)', 'EXECUTE') then
        raise exception 'shopping_check S10: anon con EXECUTE';
    end if;
end $$;
\echo ok S10

-- ── Limpieza ──
select pg_temp.clean();
\echo ok S-clean
