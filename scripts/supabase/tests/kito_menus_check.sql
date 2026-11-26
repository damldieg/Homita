-- kito_menus_check.sql — Soporte de la skill `menus` de Kito (0048_menus_kito.sql).
-- Solo BD local, tras el reset 0001–0048:
--   psql -v ON_ERROR_STOP=1 -f kito_menus_check.sql
-- Cada bloque DO emite 'ok MKx: …' o aborta con 'kito_menus MKx: …'.
--
-- Fixture (ids 994xxx, auth_uid …0e0001–…0e0003): hogar H (994001) con A admin (home_member 994001) y B adulto
-- (994002, permisos de fn_seed_kind_permissions); hogar G (994002) con Y admin. Semanas (lunes): W1 2030-01-07,
-- W2 2030-01-14. Todo lo creado lleva el prefijo 'ZZMK'.
--
-- MK1 plan de Kito: origin kito, reintento con la misma client_request_id sin duplicar ni exigir la revisión
--     de entonces, revisión vieja → Stale, kind ajeno → Invalid client_request_id, origin inválido.
-- MK2 un plan accepted no lo edita Kito; la persona sí (vuelve a draft) y origin queda como estaba.
-- MK3 estado de casilla: rejected se guarda y se limpia; Kito no bloquea ni toca/borra locked; la persona sí.
-- MK4 recetas de Kito: exigen pasos, idempotentes por client_request_id, origin en el JSON.
-- MK5 aislamiento entre hogares y entre personas (la clave es por usuario).
-- MK6 grants: sin firmas antiguas, anon sin ejecución, authenticated con ejecución.
-- MK7 0 filas scratch al terminar.

\set ON_ERROR_STOP 1
do $$
begin
    if inet_server_addr() is not null and host(inet_server_addr()) not in ('127.0.0.1', '::1') then
        raise exception 'kito_menus_check: solo BD local (socket o loopback); servidor %', host(inet_server_addr());
    end if;
    if not exists (select 1 from information_schema.columns where table_schema = 'public'
                   and table_name = 'meal_plan' and column_name = 'origin') then
        raise exception 'kito_menus_check: 0048 no está aplicada';
    end if;
end $$;

create function pg_temp.clean() returns void
language plpgsql as $$
begin
    set local session_replication_role = replica;
    delete from client_request where app_user_id between 994001 and 994003;
    delete from meal_plan_item_member where home_id in (994001, 994002);
    delete from meal_plan_item where home_id in (994001, 994002);
    delete from meal_plan where home_id in (994001, 994002);
    delete from recipe_ingredient where home_id in (994001, 994002);
    delete from recipe where home_id in (994001, 994002);
    delete from meal_schedule where home_id in (994001, 994002);
    delete from meal_profile_member where home_id in (994001, 994002);
    delete from meal_slot_setting where home_id in (994001, 994002);
    delete from meal_profile where home_id in (994001, 994002);
    delete from membership_permission where home_membership_id between 994001 and 994003;
    delete from audit_log where home_id in (994001, 994002);
    delete from home_member where home_id in (994001, 994002);
    delete from home_membership where home_id in (994001, 994002);
    update app_user set default_home_id = null where id between 994001 and 994003;
    delete from home where id in (994001, 994002);
    delete from app_user where id between 994001 and 994003;
    delete from auth.users where id::text like '00000000-0000-4000-8000-0000000e000_';
end $$;

create function pg_temp.fails(p_label text, p_sql text, p_state text, p_msg text) returns void
language plpgsql as $$
begin
    execute p_sql;
    raise exception 'kito_menus %: no falló: %', p_label, p_sql;
exception when others then
    if sqlstate <> p_state or sqlerrm <> p_msg then
        raise exception 'kito_menus %: % % (esperado % %)', p_label, sqlstate, sqlerrm, p_state, p_msg;
    end if;
end $$;

create function pg_temp.as_user(p_n int) returns void
language plpgsql as $$
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000e000' || p_n, true);
    perform set_config('request.headers', '', true);
end $$;

select pg_temp.clean();

set session_replication_role = replica;
insert into auth.users (id, email, raw_user_meta_data) values
    ('00000000-0000-4000-8000-0000000e0001', 'mk-a@check.homita.example', '{"name":"MK-A"}'),
    ('00000000-0000-4000-8000-0000000e0002', 'mk-b@check.homita.example', '{"name":"MK-B"}'),
    ('00000000-0000-4000-8000-0000000e0003', 'mk-y@check.homita.example', '{"name":"MK-Y"}');
insert into app_user (id, auth_uid, name, email) values
    (994001, '00000000-0000-4000-8000-0000000e0001', 'MK-A', 'mk-a@check.homita.example'),
    (994002, '00000000-0000-4000-8000-0000000e0002', 'MK-B', 'mk-b@check.homita.example'),
    (994003, '00000000-0000-4000-8000-0000000e0003', 'MK-Y', 'mk-y@check.homita.example');
set session_replication_role = default;

begin;
insert into home (id, name, status, is_personal, created_by) values
    (994001, 'MK-Hogar H', 'active', false, 994001),
    (994002, 'MK-Hogar G', 'active', false, 994003);
insert into home_membership (id, home_id, app_user_id, role) values
    (994001, 994001, 994001, 'admin'),
    (994002, 994001, 994002, 'member'),
    (994003, 994002, 994003, 'admin');
insert into home_member (id, home_id, kind, name, app_user_id) values
    (994001, 994001, 'adult', 'MK-A', 994001),
    (994002, 994001, 'adult', 'MK-B', 994002),
    (994008, 994002, 'adult', 'MK-Y', 994003);
update app_user set default_home_id = 994001 where id in (994001, 994002);
update app_user set default_home_id = 994002 where id = 994003;
select fn_seed_kind_permissions(994002, 'adult');
commit;

-- ── MK1: plan de Kito, idempotencia y revisión ──
do $$
declare
    v json;
    v2 json;
    v_cr1 uuid := '11111111-1111-4111-8111-111111111111';
    v_cr2 uuid := '22222222-2222-4222-8222-222222222222';
begin
    perform pg_temp.as_user(1);
    v := upsert_meal_plan_items('2030-01-07', 0, jsonb_build_array(
            jsonb_build_object('day', '2030-01-07', 'slot', 'lunch', 'kind', 'free_text', 'title', 'ZZMK Lentejas'),
            jsonb_build_object('day', '2030-01-08', 'slot', 'dinner', 'kind', 'free_text', 'title', 'ZZMK Tortilla')),
        null, v_cr1, 'kito');
    if v->>'origin' <> 'kito' or v->>'status' <> 'draft' or (v->>'revision')::int <> 1
       or json_array_length(v->'items') <> 2 then
        raise exception 'kito_menus MK1: plan de Kito mal creado %', v;
    end if;
    -- reintento: misma clave con la revisión de entonces (0): no duplica ni da Stale
    v2 := upsert_meal_plan_items('2030-01-07', 0, jsonb_build_array(
            jsonb_build_object('day', '2030-01-07', 'slot', 'lunch', 'kind', 'free_text', 'title', 'ZZMK Lentejas'),
            jsonb_build_object('day', '2030-01-08', 'slot', 'dinner', 'kind', 'free_text', 'title', 'ZZMK Tortilla')),
        null, v_cr1, 'kito');
    if v2::text <> v::text or (select count(*) from meal_plan where home_id = 994001) <> 1
       or (select count(*) from meal_plan_item where home_id = 994001) <> 2
       or (select count(*) from client_request where client_request_id = v_cr1) <> 1 then
        raise exception 'kito_menus MK1: el reintento duplicó o cambió el plan';
    end if;
    -- revisión vieja con una clave nueva → Stale (y no queda client_request)
    perform pg_temp.fails('MK1 stale',
        format('select upsert_meal_plan_items(''2030-01-07'', 0, null, null, %L, ''kito'')', v_cr2),
        'P0001', 'Stale meal plan revision');
    if exists (select 1 from client_request where client_request_id = v_cr2) then
        raise exception 'kito_menus MK1: una petición fallida dejó su client_request';
    end if;
    -- con la revisión vigente sí entra y sube la revisión
    v2 := upsert_meal_plan_items('2030-01-07', 1, jsonb_build_array(
        jsonb_build_object('day', '2030-01-09', 'slot', 'lunch', 'kind', 'free_text', 'title', 'ZZMK Arroz')),
        null, v_cr2, 'kito');
    if (v2->>'revision')::int <> 2 or json_array_length(v2->'items') <> 3 then
        raise exception 'kito_menus MK1: edición con la revisión vigente %', v2;
    end if;
    -- la misma clave en otro kind → Invalid client_request_id
    perform pg_temp.fails('MK1 kind ajeno',
        format('select create_recipe(''ZZMK kind'', 2, null, null, ''["p"]''::jsonb, null, %L, ''kito'')', v_cr1),
        'P0001', 'Invalid client_request_id');
    -- origin inválido
    perform pg_temp.fails('MK1 origin',
        $q$select upsert_meal_plan_items('2030-01-14', 0, null, null, null, 'otro')$q$,
        'P0001', 'Invalid meal plan');
    -- sin client_request_id y sin origin: comportamiento de 0044 (origin user)
    v := upsert_meal_plan_items('2030-01-14', 0, jsonb_build_array(
        jsonb_build_object('day', '2030-01-14', 'slot', 'lunch', 'kind', 'free_text', 'title', 'ZZMK Persona')));
    if v->>'origin' <> 'user' then
        raise exception 'kito_menus MK1: origin por defecto distinto de user';
    end if;
    raise notice 'ok MK1: plan de Kito con origin, reintento idempotente, revisión vieja = Stale, kind ajeno y origin inválido';
end $$;

-- ── MK2: plan aceptado ──
do $$
declare
    v json;
    v_id bigint := (select id from meal_plan where home_id = 994001 and week_start = '2030-01-07');
    v_rev int := (select revision from meal_plan where home_id = 994001 and week_start = '2030-01-07');
begin
    perform pg_temp.as_user(1);
    v := accept_meal_plan(v_id, v_rev);
    if v->>'status' <> 'accepted' or v->>'origin' <> 'kito' then
        raise exception 'kito_menus MK2: accept cambió origin o no aceptó %', v;
    end if;
    perform pg_temp.fails('MK2 kito sobre accepted',
        format('select upsert_meal_plan_items(''2030-01-07'', %s, ''[{"day":"2030-01-10","slot":"lunch","kind":"free_text","title":"ZZMK Otro"}]''::jsonb, null, null, ''kito'')', v_rev + 1),
        'P0001', 'Invalid meal plan');
    if (select status from meal_plan where id = v_id) <> 'accepted'
       or exists (select 1 from meal_plan_item where plan_id = v_id and title = 'ZZMK Otro') then
        raise exception 'kito_menus MK2: Kito modificó un plan aceptado';
    end if;
    -- la persona sí edita y el plan vuelve a draft (comportamiento de 0044)
    v := upsert_meal_plan_items('2030-01-07', v_rev + 1,
        '[{"day":"2030-01-10","slot":"lunch","kind":"free_text","title":"ZZMK Persona2"}]'::jsonb);
    if v->>'status' <> 'draft' or v->>'origin' <> 'kito' then
        raise exception 'kito_menus MK2: la edición de la persona %', v;
    end if;
    raise notice 'ok MK2: Kito no edita un plan accepted; la persona sí y vuelve a draft';
end $$;

-- ── MK3: estado de casilla ──
do $$
declare
    v json;
    v_id bigint := (select id from meal_plan where home_id = 994001 and week_start = '2030-01-14');
    v_rev int;
    v_item bigint;
    v_item2 bigint;
begin
    perform pg_temp.as_user(1);
    v_rev := (select revision from meal_plan where id = v_id);
    v := upsert_meal_plan_items('2030-01-14', v_rev, jsonb_build_array(
        jsonb_build_object('day', '2030-01-15', 'slot', 'lunch', 'kind', 'free_text', 'title', 'ZZMK A', 'state', 'rejected'),
        jsonb_build_object('day', '2030-01-16', 'slot', 'lunch', 'kind', 'free_text', 'title', 'ZZMK B', 'state', 'locked')));
    select id into v_item from meal_plan_item where plan_id = v_id and title = 'ZZMK A';
    select id into v_item2 from meal_plan_item where plan_id = v_id and title = 'ZZMK B';
    if (select state from meal_plan_item where id = v_item) <> 'rejected'
       or (select state from meal_plan_item where id = v_item2) <> 'locked'
       or not (v::jsonb->'items' @> '[{"title":"ZZMK A","state":"rejected"}]'::jsonb) then
        raise exception 'kito_menus MK3: estados no guardados %', v;
    end if;
    v_rev := v_rev + 1;
    perform pg_temp.fails('MK3 estado inválido',
        format('select upsert_meal_plan_items(''2030-01-14'', %s, jsonb_build_array(jsonb_build_object(''id'', %s, ''day'', ''2030-01-15'', ''slot'', ''lunch'', ''kind'', ''free_text'', ''title'', ''x'', ''state'', ''otro'')))', v_rev, v_item),
        'P0001', 'Invalid meal plan');
    perform pg_temp.fails('MK3 kito no bloquea',
        format('select upsert_meal_plan_items(''2030-01-14'', %s, jsonb_build_array(jsonb_build_object(''day'', ''2030-01-17'', ''slot'', ''lunch'', ''kind'', ''free_text'', ''title'', ''x'', ''state'', ''locked'')), null, null, ''kito'')', v_rev),
        'P0001', 'Invalid meal plan');
    perform pg_temp.fails('MK3 kito no cambia locked',
        format('select upsert_meal_plan_items(''2030-01-14'', %s, jsonb_build_array(jsonb_build_object(''id'', %s, ''day'', ''2030-01-16'', ''slot'', ''lunch'', ''kind'', ''free_text'', ''title'', ''ZZMK cambiado'')), null, null, ''kito'')', v_rev, v_item2),
        'P0001', 'Invalid meal plan');
    perform pg_temp.fails('MK3 kito no borra locked',
        format('select upsert_meal_plan_items(''2030-01-14'', %s, null, array[%s]::bigint[], null, ''kito'')', v_rev, v_item2),
        'P0001', 'Invalid meal plan');
    if (select title from meal_plan_item where id = v_item2) <> 'ZZMK B'
       or (select revision from meal_plan where id = v_id) <> v_rev then
        raise exception 'kito_menus MK3: una reproposición rechazada cambió datos o revisión';
    end if;
    -- Kito repropone la rechazada (state null la limpia); la locked sigue igual
    v := upsert_meal_plan_items('2030-01-14', v_rev, jsonb_build_array(
        jsonb_build_object('id', v_item, 'day', '2030-01-15', 'slot', 'lunch', 'kind', 'free_text',
                           'title', 'ZZMK A nueva', 'state', null)), null, null, 'kito');
    if (select state from meal_plan_item where id = v_item) is not null
       or (select title from meal_plan_item where id = v_item) <> 'ZZMK A nueva'
       or (select state from meal_plan_item where id = v_item2) <> 'locked' then
        raise exception 'kito_menus MK3: reproposición de la rechazada %', v;
    end if;
    v_rev := v_rev + 1;
    -- sin la clave state, el estado de la casilla se conserva
    v := upsert_meal_plan_items('2030-01-14', v_rev, jsonb_build_array(
        jsonb_build_object('id', v_item, 'day', '2030-01-15', 'slot', 'lunch', 'kind', 'free_text', 'title', 'ZZMK A 2',
                           'state', 'rejected')));
    v_rev := v_rev + 1;
    v := upsert_meal_plan_items('2030-01-14', v_rev, jsonb_build_array(
        jsonb_build_object('id', v_item, 'day', '2030-01-15', 'slot', 'lunch', 'kind', 'free_text', 'title', 'ZZMK A 3')));
    if (select state from meal_plan_item where id = v_item) <> 'rejected' then
        raise exception 'kito_menus MK3: el estado no se conservó sin la clave state';
    end if;
    v_rev := v_rev + 1;
    -- la persona sí cambia y desbloquea una locked
    v := upsert_meal_plan_items('2030-01-14', v_rev, jsonb_build_array(
        jsonb_build_object('id', v_item2, 'day', '2030-01-16', 'slot', 'lunch', 'kind', 'free_text',
                           'title', 'ZZMK B2', 'state', null)));
    if (select state from meal_plan_item where id = v_item2) is not null
       or (select title from meal_plan_item where id = v_item2) <> 'ZZMK B2' then
        raise exception 'kito_menus MK3: la persona no pudo cambiar una locked';
    end if;
    raise notice 'ok MK3: rejected y locked; Kito no bloquea ni toca locked; la persona sí';
end $$;

-- ── MK4: recetas de Kito ──
do $$
declare
    v json;
    v2 json;
    v_cr uuid := '33333333-3333-4333-8333-333333333333';
begin
    perform pg_temp.as_user(1);
    perform pg_temp.fails('MK4 sin pasos',
        $q$select create_recipe('ZZMK sin pasos', 2, null, null, null, null, null, 'kito')$q$, 'P0001', 'Invalid recipe');
    perform pg_temp.fails('MK4 pasos vacíos',
        $q$select create_recipe('ZZMK pasos vacíos', 2, null, null, '[]'::jsonb, null, null, 'kito')$q$, 'P0001', 'Invalid recipe');
    perform pg_temp.fails('MK4 origin',
        $q$select create_recipe('ZZMK origin', 2, null, null, '["p"]'::jsonb, null, null, 'otro')$q$, 'P0001', 'Invalid recipe');
    v := create_recipe('ZZMK Milanesas', 4, 40, '["lunch"]'::jsonb, '["Empanar", "Freír"]'::jsonb, null, v_cr, 'kito');
    v2 := create_recipe('ZZMK Milanesas', 4, 40, '["lunch"]'::jsonb, '["Empanar", "Freír"]'::jsonb, null, v_cr, 'kito');
    if v->>'origin' <> 'kito' or v2::text <> v::text or (select count(*) from recipe where name = 'ZZMK Milanesas') <> 1 then
        raise exception 'kito_menus MK4: receta de Kito duplicada o sin origin';
    end if;
    v := create_recipe('ZZMK Persona', 2);
    if v->>'origin' <> 'user' or (select origin from recipe where id = (v->>'id')::bigint) <> 'user' then
        raise exception 'kito_menus MK4: origin por defecto de receta';
    end if;
    raise notice 'ok MK4: recetas de Kito con pasos, idempotentes y con origin';
end $$;

-- ── MK5: aislamiento ──
do $$
declare
    v json;
    v_cr uuid := '11111111-1111-4111-8111-111111111111'; -- la misma clave que usó A en MK1
    v_plan_a bigint := (select id from meal_plan where home_id = 994001 and week_start = '2030-01-07');
    v_items_a integer := (select count(*) from meal_plan_item where plan_id = v_plan_a);
begin
    perform pg_temp.as_user(3);
    -- la clave de A no existe para Y: se crea en el hogar de Y sin tocar el de A
    v := upsert_meal_plan_items('2030-01-07', 0, '[{"day":"2030-01-07","slot":"lunch","kind":"free_text","title":"ZZMK Y"}]'::jsonb,
        null, v_cr, 'kito');
    if (v->>'id')::bigint = v_plan_a or (select home_id from meal_plan where id = (v->>'id')::bigint) <> 994002
       or (select count(*) from meal_plan_item where plan_id = v_plan_a) <> v_items_a then
        raise exception 'kito_menus MK5: Y tocó el hogar de A o reutilizó su plan';
    end if;
    -- B (mismo hogar que A, otra persona) no hereda la clave de A: ve la semana ocupada
    perform pg_temp.as_user(2);
    perform pg_temp.fails('MK5 B misma semana',
        format('select upsert_meal_plan_items(''2030-01-07'', 0, null, null, %L, ''kito'')', v_cr),
        'P0001', 'Stale meal plan revision');
    -- Y no ve recetas de H por RPC
    perform pg_temp.as_user(3);
    if json_array_length(list_recipes('ZZMK')) <> 0 then
        raise exception 'kito_menus MK5: Y lista recetas de H';
    end if;
    raise notice 'ok MK5: la clave es por persona y el hogar de A no se toca desde Y';
end $$;

-- ── MK6: grants ──
do $$
begin
    if exists (select 1 from pg_proc where pronamespace = 'public'::regnamespace
               and ((proname = 'upsert_meal_plan_items' and pronargs <> 6)
                 or (proname = 'create_recipe' and pronargs <> 8))) then
        raise exception 'kito_menus MK6: quedan firmas antiguas';
    end if;
    if has_function_privilege('anon', 'upsert_meal_plan_items(date, integer, jsonb, bigint[], uuid, text)', 'execute')
       or has_function_privilege('anon', 'create_recipe(text, integer, integer, jsonb, jsonb, jsonb, uuid, text)', 'execute')
       or not has_function_privilege('authenticated', 'upsert_meal_plan_items(date, integer, jsonb, bigint[], uuid, text)', 'execute')
       or not has_function_privilege('authenticated', 'create_recipe(text, integer, integer, jsonb, jsonb, jsonb, uuid, text)', 'execute') then
        raise exception 'kito_menus MK6: grants incorrectos';
    end if;
    raise notice 'ok MK6: firmas nuevas únicas, anon sin ejecución, authenticated con ejecución';
end $$;

-- ── MK7: limpieza ──
select pg_temp.clean();
do $$
begin
    if exists (select 1 from app_user where id between 994001 and 994003)
       or exists (select 1 from home where id in (994001, 994002))
       or exists (select 1 from recipe where home_id in (994001, 994002))
       or exists (select 1 from meal_plan where home_id in (994001, 994002))
       or exists (select 1 from meal_plan_item where home_id in (994001, 994002))
       or exists (select 1 from client_request where app_user_id between 994001 and 994003) then
        raise exception 'kito_menus MK7: quedaron filas scratch';
    end if;
    raise notice 'ok MK7: 0 filas scratch';
end $$;
