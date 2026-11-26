-- meal_profile_countries_check.sql — change menus-paises-hogar (0046): países del hogar en meal_profile.
-- Solo BD local. Cada bloque DO emite 'ok MCx: …' o aborta con 'meal_profile_countries MCx: …'.
-- MC1 defaults y guardado (AC1): countries = [] en un hogar nuevo; se guarda y se recupera; la lista
--     vacía es válida; guardar otra clave no toca los países; los repetidos se colapsan.
-- MC2 rechazo (AC2): minúsculas, códigos fuera de lista, no array, elementos no textuales, null y claves
--     desconocidas → 'Invalid meal profile'; el estado no cambia; el check de tabla rechaza lo mismo.
-- MC3 cross-tenant (AC3): Y no lee ni escribe los países de H (SELECT vacío, RPC Not Found, sin escritura).
-- MC4 permisos: sin menu.profile.edit no escribe; el audit_log solo guarda nombres de campo; grants cerrados.
-- MC5 0 filas scratch al terminar.

\set ON_ERROR_STOP 1
do $$
begin
    if inet_server_addr() is not null and host(inet_server_addr()) not in ('127.0.0.1', '::1') then
        raise exception 'meal_profile_countries_check: solo BD local (socket o loopback); servidor %', host(inet_server_addr());
    end if;
end $$;

create function pg_temp.clean() returns void
language plpgsql as $$
begin
    set local session_replication_role = replica;
    delete from meal_slot_setting where home_id in (982001, 982002);
    delete from meal_profile where home_id in (982001, 982002);
    delete from membership_permission where home_membership_id between 982001 and 982003;
    delete from audit_log where home_id in (982001, 982002);
    delete from home_member where home_id in (982001, 982002);
    delete from home_membership where home_id in (982001, 982002);
    update app_user set default_home_id = null where id between 982001 and 982003;
    delete from home where id in (982001, 982002);
    delete from app_user where id between 982001 and 982003;
    delete from auth.users where id::text like '00000000-0000-4000-8000-0000000d000_';
end $$;

create function pg_temp.fails(p_label text, p_sql text, p_state text, p_msg text) returns void
language plpgsql as $$
begin
    execute p_sql;
    raise exception 'meal_profile_countries %: no falló: %', p_label, p_sql;
exception when others then
    if sqlstate <> p_state or sqlerrm <> p_msg then
        raise exception 'meal_profile_countries %: % % (esperado % %)', p_label, sqlstate, sqlerrm, p_state, p_msg;
    end if;
end $$;

create function pg_temp.as_user(p_n int, p_home bigint default null) returns void
language plpgsql as $$
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000d000' || p_n, true);
    perform set_config('request.headers',
                       case when p_home is null then '' else json_build_object('x-home-id', p_home::text)::text end,
                       true);
end $$;

select pg_temp.clean();

-- ── Fixture: H (982001) con admin A y miembro B sin menu.profile.edit; G (982002) con Y ──
set session_replication_role = replica;
insert into auth.users (id, email, raw_user_meta_data) values
    ('00000000-0000-4000-8000-0000000d0001', 'mc-a@check.homita.example', '{"name":"MC-A"}'),
    ('00000000-0000-4000-8000-0000000d0002', 'mc-b@check.homita.example', '{"name":"MC-B"}'),
    ('00000000-0000-4000-8000-0000000d0003', 'mc-y@check.homita.example', '{"name":"MC-Y"}');
insert into app_user (id, auth_uid, name, email) values
    (982001, '00000000-0000-4000-8000-0000000d0001', 'MC-A', 'mc-a@check.homita.example'),
    (982002, '00000000-0000-4000-8000-0000000d0002', 'MC-B', 'mc-b@check.homita.example'),
    (982003, '00000000-0000-4000-8000-0000000d0003', 'MC-Y', 'mc-y@check.homita.example');
set session_replication_role = default;

begin;
insert into home (id, name, status, is_personal, created_by) values
    (982001, 'MC-Hogar H', 'active', false, 982001),
    (982002, 'MC-Hogar G', 'active', false, 982003);
insert into home_membership (id, home_id, app_user_id, role) values
    (982001, 982001, 982001, 'admin'),
    (982002, 982001, 982002, 'member'),
    (982003, 982002, 982003, 'admin');
insert into home_member (id, home_id, kind, name, app_user_id) values
    (982001, 982001, 'adult', 'MC-A', 982001),
    (982002, 982001, 'child', 'MC-B', 982002),
    (982003, 982002, 'adult', 'MC-Y', 982003);
update app_user set default_home_id = 982001 where id in (982001, 982002);
update app_user set default_home_id = 982002 where id = 982003;
select fn_seed_kind_permissions(982002, 'child');
commit;

-- ── MC1: defaults y guardado (AC1) ──
do $$
declare
    v json;
begin
    perform pg_temp.as_user(1);
    v := get_meal_profile();
    if (v->'profile'->'countries')::jsonb is distinct from '[]'::jsonb then
        raise exception 'meal_profile_countries MC1: no empieza en [] %', v->'profile';
    end if;
    perform update_meal_profile('{"countries":["AR","ES"]}'::jsonb);
    v := get_meal_profile();
    if (v->'profile'->'countries')::jsonb is distinct from '["AR","ES"]'::jsonb then
        raise exception 'meal_profile_countries MC1: no recupera la lista %', v->'profile'->'countries';
    end if;
    perform update_meal_profile('{"shopping_day":2}'::jsonb);
    if (get_meal_profile()->'profile'->'countries')::jsonb is distinct from '["AR","ES"]'::jsonb then
        raise exception 'meal_profile_countries MC1: otra clave tocó los países';
    end if;
    perform update_meal_profile('{"countries":["IT","IT","FR","IT"]}'::jsonb);
    if (get_meal_profile()->'profile'->'countries')::jsonb is distinct from '["IT","FR"]'::jsonb then
        raise exception 'meal_profile_countries MC1: repetidos no colapsados';
    end if;
    perform update_meal_profile('{"countries":[]}'::jsonb);
    if (get_meal_profile()->'profile'->'countries')::jsonb is distinct from '[]'::jsonb then
        raise exception 'meal_profile_countries MC1: la lista vacía no se guardó';
    end if;
    perform update_meal_profile('{"countries":["AR","ES"]}'::jsonb);
    raise notice 'ok MC1: [] por defecto; guarda, recupera, vacía y colapsa repetidos';
end $$;

-- ── MC2: rechazo (AC2) ──
do $$
declare
    v text;
begin
    perform pg_temp.as_user(1);
    foreach v in array array['{"countries":["es"]}', '{"countries":["XX"]}', '{"countries":["ESP"]}', '{"countries":["ES",""]}',
                             '{"countries":"ES"}', '{"countries":null}', '{"countries":[1]}', '{"countries":[null]}',
                             '{"countries":[["ES"]]}', '{"countries":{"a":"ES"}}', '{"countries":["ES"],"pais":"ES"}'] loop
        perform pg_temp.fails('MC2 ' || v, format('select update_meal_profile(%L::jsonb)', v), 'P0001', 'Invalid meal profile');
    end loop;
    if (get_meal_profile()->'profile'->'countries')::jsonb is distinct from '["AR","ES"]'::jsonb then
        raise exception 'meal_profile_countries MC2: un rechazo cambió el estado';
    end if;
    -- el check de la tabla, por sí solo (superusuario: sin RPC)
    perform pg_temp.fails('MC2 check minúscula', $q$update meal_profile set countries = array['es'] where home_id = 982001$q$,
        '23514', 'new row for relation "meal_profile" violates check constraint "meal_profile_countries_check"');
    perform pg_temp.fails('MC2 check duplicado', $q$update meal_profile set countries = array['ES','ES'] where home_id = 982001$q$,
        '23514', 'new row for relation "meal_profile" violates check constraint "meal_profile_countries_check"');
    perform pg_temp.fails('MC2 check nulo', $q$update meal_profile set countries = null where home_id = 982001$q$,
        '23502', 'null value in column "countries" of relation "meal_profile" violates not-null constraint');
    raise notice 'ok MC2: formas inválidas, minúsculas, fuera de lista y repetidos por el check → Invalid meal profile';
end $$;

-- ── MC3: cross-tenant (AC3) ──
do $$
begin
    perform pg_temp.as_user(3);
    set local role authenticated;
    if exists (select 1 from meal_profile where home_id = 982001) then
        raise exception 'meal_profile_countries MC3: Y lee meal_profile de H';
    end if;
    if (get_meal_profile()->>'home_id')::bigint <> 982002
       or (get_meal_profile()->'profile'->'countries')::jsonb is distinct from '[]'::jsonb then
        raise exception 'meal_profile_countries MC3: Y sin cabecera ve algo de H';
    end if;
    perform pg_temp.as_user(3, 982001);
    perform pg_temp.fails('MC3 get con X-Home-Id ajeno', $q$select get_meal_profile()$q$, 'P0002', 'Not Found');
    perform pg_temp.fails('MC3 update con X-Home-Id ajeno', $q$select update_meal_profile('{"countries":["US"]}'::jsonb)$q$,
        'P0002', 'Not Found');
    perform pg_temp.as_user(3);
    -- escritura directa: authenticated no tiene privilegio
    perform pg_temp.fails('MC3 update directo', $q$update meal_profile set countries = array['US'] where home_id = 982001$q$,
        '42501', 'permission denied for table meal_profile');
    reset role;
    if (select countries from meal_profile where home_id = 982001) is distinct from array['AR','ES'] then
        raise exception 'meal_profile_countries MC3: los países de H cambiaron';
    end if;
    raise notice 'ok MC3: otro hogar no lee ni escribe los países (RLS, RPC y privilegios)';
end $$;

-- ── MC4: permisos, audit y grants ──
do $$
begin
    perform pg_temp.as_user(2);
    if (get_meal_profile()->'profile'->'countries')::jsonb is distinct from '["AR","ES"]'::jsonb then
        raise exception 'meal_profile_countries MC4: B (menu.view) no lee los países';
    end if;
    perform pg_temp.fails('MC4 sin permiso', $q$select update_meal_profile('{"countries":["US"]}'::jsonb)$q$,
        '42501', 'Not Allowed');
    if exists (select 1 from audit_log where home_id = 982001 and action = 'meal.profile.update'
               and payload::text like '%AR%') then
        raise exception 'meal_profile_countries MC4: el audit_log guarda los códigos';
    end if;
    if has_function_privilege('anon', 'fn_meal_countries_valid(text[])', 'execute')
       or has_function_privilege('authenticated', 'fn_meal_countries_valid(text[])', 'execute')
       or has_function_privilege('authenticated', 'fn_meal_countries_normalize(jsonb)', 'execute')
       or has_function_privilege('anon', 'update_meal_profile(jsonb)', 'execute')
       or not has_function_privilege('authenticated', 'update_meal_profile(jsonb)', 'execute') then
        raise exception 'meal_profile_countries MC4: EXECUTE incorrecto';
    end if;
    raise notice 'ok MC4: lectura con menu.view, escritura con menu.profile.edit, audit sin códigos, grants cerrados';
end $$;

-- ── MC5: limpieza ──
select pg_temp.clean();
do $$
begin
    if exists (select 1 from app_user where id between 982001 and 982003)
       or exists (select 1 from home where id in (982001, 982002))
       or exists (select 1 from meal_profile where home_id in (982001, 982002)) then
        raise exception 'meal_profile_countries MC5: quedaron filas scratch';
    end if;
    raise notice 'ok MC5: 0 filas scratch';
end $$;
