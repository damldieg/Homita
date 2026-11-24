-- menu_semana_check.sql — Catálogo de alimentos, recetas y menú semanal (0044_menus_semana.sql).
-- Solo BD local, tras el reset 0001–0044 y la semilla supabase/seed/food_es.sql:
--   psql -v ON_ERROR_STOP=1 -f menu_semana_check.sql
-- Cada bloque DO emite 'ok MSx: …' o aborta con 'menu_semana MSx: …'.
--
-- Fixture (ids 993xxx, auth_uid …0d0001–…0d0005): hogar H (993001) con A admin (home_member 993001),
-- B adulto (993002), C niño con cuenta (993003), D invitado (993004), una mascota (993005) y un niño sin
-- cuenta (993006); hogar G (993002) con Y admin (home_member 993008). Los permisos de los miembros salen
-- de fn_seed_kind_permissions. Semanas (lunes): W1 2030-01-07, W2 2030-01-14, W3 2030-01-21,
-- W4 2030-01-28, W5 2030-02-04, W6 2030-02-11. Todo lo creado lleva el prefijo 'ZZMS'.
--
-- MS1  RLS entre hogares: Y no lee food/recipe/plan de H, lee el catálogo común y no escribe directo.
-- MS2  catálogo: búsqueda sin acentos, común de solo lectura (Not Found), validación y duplicados.
-- MS3  permisos: niño lee y no escribe; invitado sin menu.view no lee nada.
-- MS4  recetas: crear, leer con alérgenos derivados, reemplazar ingredientes, filtros, validación y borrado.
-- MS5  unicidad por hogar y semana, revisión vieja → Stale meal plan revision, validación de casillas.
-- MS6  ciclo draft → accepted → draft (al editar) → accepted → archived; la semana archivada se libera.
-- MS7  copy_meal_plan_week: copia casillas y comensales; semana ocupada → Meal plan exists.
-- MS8  comensales por defecto desde meal_schedule; members [] explícito; miembros inválidos.
-- MS9  check_meal_plan: alérgeno, intolerancia, dieta y comensal fuera.
-- MS10 get_meals_today con la zona del hogar y has_plan falso / verdadero; Invalid timezone.
-- MS11 cross-tenant por RPC: Y no ve ni toca lo de H (Not Found / Invalid).
-- MS12 grants y RLS: solo SELECT, RPC solo para authenticated, helpers cerrados.
-- MS13 receta borrada: la casilla conserva el título.
-- MS14 0 filas scratch al terminar.
-- MS15 week_start_day bloqueado con planes no archivados (corre antes de MS14; R1-01).
-- MS16 accept y archive respetan expected_revision; accept doble → Stale (R1-02).

\set ON_ERROR_STOP 1
do $$
begin
    if inet_server_addr() is not null and host(inet_server_addr()) not in ('127.0.0.1', '::1') then
        raise exception 'menu_semana_check: solo BD local (socket o loopback); servidor %', host(inet_server_addr());
    end if;
    if date '2030-01-07' - 0 <> date '2030-01-07' or extract(isodow from date '2030-01-07') <> 1 then
        raise exception 'menu_semana_check: W1 no es lunes';
    end if;
end $$;

create function pg_temp.clean() returns void
language plpgsql as $$
begin
    set local session_replication_role = replica;
    delete from meal_plan_item_member where home_id in (993001, 993002);
    delete from meal_plan_item where home_id in (993001, 993002);
    delete from meal_plan where home_id in (993001, 993002);
    delete from recipe_ingredient where home_id in (993001, 993002);
    delete from recipe where home_id in (993001, 993002);
    delete from food where home_id in (993001, 993002) or name like 'ZZMS%';
    delete from meal_schedule where home_id in (993001, 993002);
    delete from meal_profile_member where home_id in (993001, 993002);
    delete from meal_slot_setting where home_id in (993001, 993002);
    delete from meal_profile where home_id in (993001, 993002);
    delete from membership_permission where home_membership_id between 993001 and 993005;
    delete from audit_log where home_id in (993001, 993002);
    delete from home_member where home_id in (993001, 993002);
    delete from home_membership where home_id in (993001, 993002);
    update app_user set default_home_id = null where id between 993001 and 993005;
    delete from home where id in (993001, 993002);
    delete from app_user where id between 993001 and 993005;
    delete from auth.users where id::text like '00000000-0000-4000-8000-0000000d000_';
end $$;

-- Ejecuta p_sql y exige el error p_msg (sqlstate p_state).
create function pg_temp.fails(p_label text, p_sql text, p_state text, p_msg text) returns void
language plpgsql as $$
begin
    execute p_sql;
    raise exception 'menu_semana %: no falló: %', p_label, p_sql;
exception when others then
    if sqlstate <> p_state or sqlerrm <> p_msg then
        raise exception 'menu_semana %: % % (esperado % %)', p_label, sqlstate, sqlerrm, p_state, p_msg;
    end if;
end $$;

-- Sesión de la persona p_n (1–5), con X-Home-Id opcional; vive en la transacción del DO que lo llama.
create function pg_temp.as_user(p_n int, p_home bigint default null) returns void
language plpgsql as $$
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000d000' || p_n, true);
    perform set_config('request.headers',
                       case when p_home is null then '' else json_build_object('x-home-id', p_home::text)::text end,
                       true);
end $$;

create function pg_temp.plan_id(p_week date, p_home bigint default 993001) returns bigint
language sql as $$
    select id from meal_plan where home_id = p_home and week_start = p_week and status <> 'archived'
$$;
create function pg_temp.rev(p_week date, p_home bigint default 993001) returns integer
language sql as $$
    select revision from meal_plan where home_id = p_home and week_start = p_week and status <> 'archived'
$$;
create function pg_temp.food_id(p_name text) returns bigint
language sql as $$ select id from food where name = p_name $$;
create function pg_temp.recipe_id(p_name text) returns bigint
language sql as $$ select id from recipe where name = p_name $$;

select pg_temp.clean();

-- ── Fixture ──
set session_replication_role = replica;
insert into auth.users (id, email, raw_user_meta_data) values
    ('00000000-0000-4000-8000-0000000d0001', 'ms-a@check.homita.example', '{"name":"MS-A"}'),
    ('00000000-0000-4000-8000-0000000d0002', 'ms-b@check.homita.example', '{"name":"MS-B"}'),
    ('00000000-0000-4000-8000-0000000d0003', 'ms-c@check.homita.example', '{"name":"MS-C"}'),
    ('00000000-0000-4000-8000-0000000d0004', 'ms-d@check.homita.example', '{"name":"MS-D"}'),
    ('00000000-0000-4000-8000-0000000d0005', 'ms-y@check.homita.example', '{"name":"MS-Y"}');
insert into app_user (id, auth_uid, name, email) values
    (993001, '00000000-0000-4000-8000-0000000d0001', 'MS-A', 'ms-a@check.homita.example'),
    (993002, '00000000-0000-4000-8000-0000000d0002', 'MS-B', 'ms-b@check.homita.example'),
    (993003, '00000000-0000-4000-8000-0000000d0003', 'MS-C', 'ms-c@check.homita.example'),
    (993004, '00000000-0000-4000-8000-0000000d0004', 'MS-D', 'ms-d@check.homita.example'),
    (993005, '00000000-0000-4000-8000-0000000d0005', 'MS-Y', 'ms-y@check.homita.example');
set session_replication_role = default;

begin;
insert into home (id, name, status, is_personal, created_by) values
    (993001, 'MS-Hogar H', 'active', false, 993001),
    (993002, 'MS-Hogar G', 'active', false, 993005);
insert into home_membership (id, home_id, app_user_id, role) values
    (993001, 993001, 993001, 'admin'),
    (993002, 993001, 993002, 'member'),
    (993003, 993001, 993003, 'member'),
    (993004, 993001, 993004, 'member'),
    (993005, 993002, 993005, 'admin');
insert into home_member (id, home_id, kind, name, app_user_id) values
    (993001, 993001, 'adult', 'MS-A', 993001),
    (993002, 993001, 'adult', 'MS-B', 993002),
    (993003, 993001, 'child', 'MS-C', 993003),
    (993004, 993001, 'guest', 'MS-D', 993004),
    (993005, 993001, 'pet', 'MS-Mascota', null),
    (993006, 993001, 'child', 'MS-Peque', null),
    (993008, 993002, 'adult', 'MS-Y', 993005);
update app_user set default_home_id = 993001 where id between 993001 and 993004;
update app_user set default_home_id = 993002 where id = 993005;
select fn_seed_kind_permissions(993002, 'adult');
select fn_seed_kind_permissions(993003, 'child');
select fn_seed_kind_permissions(993004, 'guest');
-- alimento del catálogo común de prueba (el seed real lo carga ci.sh; esto no depende de él)
insert into food (home_id, name, section, allergens) values (null, 'ZZMS Común Tomate', 'verdura', array[]::text[]);
commit;

-- ── MS1: RLS entre hogares ──
do $$
declare
    vf json;
    vr json;
    t text;
begin
    perform pg_temp.as_user(1);
    vf := create_food('ZZMS Leche A', 'lacteos', '["milk"]'::jsonb, 'ml', null);
    vr := create_recipe('ZZMS Receta A', 4, 30, '["lunch"]'::jsonb, '["Paso 1"]'::jsonb,
        jsonb_build_array(jsonb_build_object('food_id', (vf->>'id')::bigint, 'quantity', 200, 'unit', 'ml'),
                          jsonb_build_object('label', 'sal', 'unit', 'al gusto')));
    perform upsert_meal_plan_items('2030-01-07', 0, jsonb_build_array(jsonb_build_object(
        'day', '2030-01-07', 'slot', 'lunch', 'kind', 'recipe', 'recipe_id', (vr->>'id')::bigint)));
    if (select count(*) from meal_plan_item_member where home_id = 993001) = 0 then
        -- sin fichas de perfil no hay comensales por defecto: no es un error, solo se anota
        raise notice 'MS1: la casilla de W1 no tiene comensales (sin fichas de perfil)';
    end if;

    perform pg_temp.as_user(5);
    set local role authenticated;
    if exists (select 1 from food where home_id = 993001) or exists (select 1 from recipe where home_id = 993001)
       or exists (select 1 from recipe_ingredient where home_id = 993001)
       or exists (select 1 from meal_plan where home_id = 993001)
       or exists (select 1 from meal_plan_item where home_id = 993001)
       or exists (select 1 from meal_plan_item_member where home_id = 993001) then
        raise exception 'menu_semana MS1: Y lee tablas del menú de H';
    end if;
    if not exists (select 1 from food where name = 'ZZMS Común Tomate') then
        raise exception 'menu_semana MS1: el catálogo común no es legible';
    end if;
    foreach t in array array['food', 'recipe', 'recipe_ingredient', 'meal_plan', 'meal_plan_item', 'meal_plan_item_member'] loop
        begin
            execute format('delete from %I', t);
            raise exception 'menu_semana MS1: authenticated borró directo en %', t;
        exception when insufficient_privilege then null;
        end;
    end loop;
    begin
        insert into food (home_id, name, section) values (993002, 'ZZMS directo', 'otros');
        raise exception 'menu_semana MS1: authenticated insertó directo en food';
    exception when insufficient_privilege then null;
    end;
    begin
        update meal_plan set status = 'archived' where home_id = 993001;
        raise exception 'menu_semana MS1: authenticated actualizó directo meal_plan';
    exception when insufficient_privilege then null;
    end;
    reset role;
    raise notice 'ok MS1: Y no lee food/recipe/plan de H, lee el catálogo común y las tablas no admiten escritura directa';
end $$;

-- ── MS2: catálogo ──
do $$
declare
    v json;
    vy json;
    v_common bigint := (select id from food where name = 'ZZMS Común Tomate');
begin
    perform pg_temp.as_user(5);
    vy := create_food('ZZMS Propio Y', 'otros', null, null, null);
    perform pg_temp.as_user(1);
    v := search_food('zzms');
    if json_array_length(v) <> 2 then
        raise exception 'menu_semana MS2: búsqueda zzms devolvió % (esperado común + propio de H) %', json_array_length(v), v;
    end if;
    if json_array_length(search_food('COMUN tomate')) <> 1 or json_array_length(search_food('zzms leché')) <> 1 then
        raise exception 'menu_semana MS2: la búsqueda no ignora acentos ni mayúsculas';
    end if;
    if json_array_length(search_food('zzms propio')) <> 0 then
        raise exception 'menu_semana MS2: H ve el alimento propio de Y';
    end if;
    -- el prefijo va antes que el «contiene»
    if (search_food('tomate', 50)->0->>'name') is null then
        raise exception 'menu_semana MS2: búsqueda por tomate sin resultados (¿falta la semilla?)';
    end if;
    -- el común y el de otro hogar no se tocan ni por RPC
    perform pg_temp.fails('MS2 update común', format('select update_food(%s, ''{"name":"ZZMS x"}''::jsonb)', v_common), 'P0002', 'Not Found');
    perform pg_temp.fails('MS2 delete común', format('select delete_food(%s)', v_common), 'P0002', 'Not Found');
    perform pg_temp.fails('MS2 update ajeno', format('select update_food(%s, ''{"name":"ZZMS x"}''::jsonb)', vy->>'id'), 'P0002', 'Not Found');
    perform pg_temp.fails('MS2 delete ajeno', format('select delete_food(%s)', vy->>'id'), 'P0002', 'Not Found');
    -- validación
    perform pg_temp.fails('MS2 duplicado', $q$select create_food('zzms LECHÉ a', 'lacteos', null, null, null)$q$, 'P0001', 'Invalid food');
    perform pg_temp.fails('MS2 alérgeno', $q$select create_food('ZZMS Mal1', 'otros', '["foo"]'::jsonb, null, null)$q$, 'P0001', 'Invalid food');
    perform pg_temp.fails('MS2 sección', $q$select create_food('ZZMS Mal2', 'inventada', null, null, null)$q$, 'P0001', 'Invalid food');
    perform pg_temp.fails('MS2 unidad', $q$select create_food('ZZMS Mal3', 'otros', null, 'taza', null)$q$, 'P0001', 'Invalid food');
    perform pg_temp.fails('MS2 gramos', $q$select create_food('ZZMS Mal4', 'otros', null, 'ud', 0)$q$, 'P0001', 'Invalid food');
    perform pg_temp.fails('MS2 nombre vacío', $q$select create_food('  ', 'otros', null, null, null)$q$, 'P0001', 'Invalid food');
    perform pg_temp.fails('MS2 nombre nulo', $q$select create_food(null, 'otros', null, null, null)$q$, 'P0001', 'Invalid food');
    perform pg_temp.fails('MS2 alérgenos no array', $q$select create_food('ZZMS Mal5', 'otros', '"milk"'::jsonb, null, null)$q$, 'P0001', 'Invalid food');
    perform pg_temp.fails('MS2 update clave', format('select update_food(%s, ''{"foo":1}''::jsonb)', pg_temp.food_id('ZZMS Leche A')), 'P0001', 'Invalid food');
    -- el mismo nombre que un alimento común sí se puede tener como propio
    v := create_food('ZZMS Común Tomate', 'verdura', '[]'::jsonb, 'ud', 150);
    if (v->>'home_id')::bigint <> 993001 or (v->>'grams_per_unit')::numeric <> 150 then
        raise exception 'menu_semana MS2: alimento propio con nombre del común %', v;
    end if;
    -- update y delete de un alimento propio
    v := update_food((v->>'id')::bigint, '{"name":"ZZMS Tomate renombrado","allergens":["celery","sesame"],"section":"verdura"}'::jsonb);
    if v->>'name' <> 'ZZMS Tomate renombrado' or (v->'allergens')::jsonb <> '["celery","sesame"]'::jsonb then
        raise exception 'menu_semana MS2: update_food %', v;
    end if;
    if json_array_length(search_food('renombrado')) <> 1 then
        raise exception 'menu_semana MS2: name_norm no se actualizó con el nombre';
    end if;
    perform delete_food((v->>'id')::bigint);
    perform pg_temp.fails('MS2 delete dos veces', format('select delete_food(%s)', v->>'id'), 'P0002', 'Not Found');
    -- el común sigue intacto
    if (select name from food where id = v_common) <> 'ZZMS Común Tomate' then
        raise exception 'menu_semana MS2: el catálogo común cambió';
    end if;
    raise notice 'ok MS2: búsqueda sin acentos, común y ajenos de solo lectura, validación 400 y duplicados';
end $$;

-- ── MS3: permisos ──
do $$
declare
    v_rid bigint := pg_temp.recipe_id('ZZMS Receta A');
    v_fid bigint := pg_temp.food_id('ZZMS Leche A');
    v_pid bigint := pg_temp.plan_id('2030-01-07');
    s text;
begin
    -- niño: lee, no escribe
    perform pg_temp.as_user(3);
    perform search_food('zzms');
    perform list_recipes();
    perform get_recipe(v_rid);
    if get_meal_plan('2030-01-07') is null then
        raise exception 'menu_semana MS3: el niño no lee el plan';
    end if;
    perform check_meal_plan(v_pid);
    perform get_meals_today();
    foreach s in array array[
        $q$select create_food('ZZMS niño', 'otros', null, null, null)$q$,
        format('select update_food(%s, ''{"name":"ZZMS x"}''::jsonb)', v_fid),
        format('select delete_food(%s)', v_fid),
        $q$select create_recipe('ZZMS niño', 2, null, null, null, null)$q$,
        format('select update_recipe(%s, ''{"name":"ZZMS x"}''::jsonb)', v_rid),
        format('select delete_recipe(%s)', v_rid),
        $q$select upsert_meal_plan_items('2030-01-07', 1, '[]'::jsonb)$q$,
        format('select accept_meal_plan(%s, 1)', v_pid),
        format('select archive_meal_plan(%s)', v_pid),
        $q$select copy_meal_plan_week('2030-01-07', '2030-01-14')$q$] loop
        perform pg_temp.fails('MS3 niño ' || s, s, '42501', 'Not Allowed');
    end loop;
    -- invitado: sin menu.view no lee nada
    perform pg_temp.as_user(4);
    foreach s in array array[
        $q$select search_food('zzms')$q$,
        $q$select list_recipes()$q$,
        format('select get_recipe(%s)', v_rid),
        $q$select get_meal_plan('2030-01-07')$q$,
        format('select check_meal_plan(%s)', v_pid),
        $q$select get_meals_today()$q$,
        $q$select create_food('ZZMS invitado', 'otros', null, null, null)$q$,
        $q$select upsert_meal_plan_items('2030-01-07', 1, '[]'::jsonb)$q$] loop
        perform pg_temp.fails('MS3 invitado ' || s, s, '42501', 'Not Allowed');
    end loop;
    perform pg_temp.as_user(4);
    set local role authenticated;
    if exists (select 1 from recipe where home_id = 993001) or exists (select 1 from meal_plan where home_id = 993001)
       or exists (select 1 from food where home_id = 993001) then
        raise exception 'menu_semana MS3: el invitado lee tablas del menú por RLS';
    end if;
    reset role;
    -- adulto (menu.plan.manage): escribe
    perform pg_temp.as_user(2);
    perform delete_recipe((create_recipe('ZZMS B', 2, null, null, null, null)->>'id')::bigint);
    raise notice 'ok MS3: niño lee y no escribe (Not Allowed); invitado sin menu.view no lee; adulto escribe';
end $$;

-- ── MS4: recetas ──
do $$
declare
    v json;
    v_id bigint;
    v_milk bigint := pg_temp.food_id('ZZMS Leche A');
begin
    perform pg_temp.as_user(1);
    v := create_recipe('ZZMS Tarta', 6, 90, '["dinner"]'::jsonb, null,
        jsonb_build_array(jsonb_build_object('label', 'harina', 'quantity', 250, 'unit', 'g'),
                          jsonb_build_object('food_id', v_milk, 'quantity', 1, 'unit', 'l')));
    v_id := (v->>'id')::bigint;
    if json_array_length(v->'ingredients') <> 2 or (v->'allergens')::jsonb <> '["milk"]'::jsonb
       or (v->'ingredients'->0->>'label') <> 'harina' or (v->'ingredients'->1->>'label') <> 'ZZMS Leche A'
       or (v->'ingredients'->1->>'food_id')::bigint <> v_milk or v->>'steps' is not null then
        raise exception 'menu_semana MS4: create_recipe %', v;
    end if;
    v := get_recipe(v_id);
    if v->>'name' <> 'ZZMS Tarta' or (v->>'servings')::int <> 6 or (v->>'minutes')::int <> 90 then
        raise exception 'menu_semana MS4: get_recipe %', v;
    end if;
    -- update reemplaza ingredientes y deja el resto
    v := update_recipe(v_id, '{"servings":8,"steps":["a","b"],"ingredients":[{"label":"azúcar","quantity":100,"unit":"g"}]}'::jsonb);
    if (v->>'servings')::int <> 8 or v->>'name' <> 'ZZMS Tarta' or json_array_length(v->'ingredients') <> 1
       or (v->'allergens')::jsonb <> '[]'::jsonb or (v->'steps')::jsonb <> '["a","b"]'::jsonb then
        raise exception 'menu_semana MS4: update_recipe %', v;
    end if;
    v := update_recipe(v_id, '{"name":"ZZMS Tarta de queso"}'::jsonb);
    if json_array_length(v->'ingredients') <> 1 or v->>'name' <> 'ZZMS Tarta de queso' then
        raise exception 'menu_semana MS4: update sin ingredients debe conservarlos %', v;
    end if;
    -- listado y filtros
    if json_array_length(list_recipes('TARTA')) <> 1 or json_array_length(list_recipes('receta a')) <> 1 then
        raise exception 'menu_semana MS4: búsqueda por nombre';
    end if;
    if not exists (select 1 from json_array_elements(list_recipes(null, 'dinner')) e where e->>'name' = 'ZZMS Tarta de queso')
       or exists (select 1 from json_array_elements(list_recipes(null, 'dinner')) e where e->>'name' = 'ZZMS Receta A') then
        raise exception 'menu_semana MS4: filtro por franja';
    end if;
    if exists (select 1 from json_array_elements(list_recipes(null, null, 60)) e where e->>'name' = 'ZZMS Tarta de queso')
       or not exists (select 1 from json_array_elements(list_recipes(null, null, 60)) e where e->>'name' = 'ZZMS Receta A') then
        raise exception 'menu_semana MS4: filtro por tiempo';
    end if;
    perform pg_temp.fails('MS4 franja inválida', $q$select list_recipes(null, 'brunch')$q$, 'P0001', 'Invalid recipe');
    -- validación
    perform pg_temp.fails('MS4 raciones', $q$select create_recipe('ZZMS Mala', 0)$q$, 'P0001', 'Invalid recipe');
    perform pg_temp.fails('MS4 minutos', $q$select create_recipe('ZZMS Mala', 2, -1)$q$, 'P0001', 'Invalid recipe');
    perform pg_temp.fails('MS4 franja', $q$select create_recipe('ZZMS Mala', 2, null, '["brunch"]'::jsonb)$q$, 'P0001', 'Invalid recipe');
    perform pg_temp.fails('MS4 nombre', $q$select create_recipe('', 2)$q$, 'P0001', 'Invalid recipe');
    perform pg_temp.fails('MS4 nombre nulo', $q$select create_recipe(null, 2)$q$, 'P0001', 'Invalid recipe');
    perform pg_temp.fails('MS4 unidad', $q$select create_recipe('ZZMS Mala', 2, null, null, null, '[{"label":"x","unit":"taza"}]'::jsonb)$q$, 'P0001', 'Invalid recipe');
    perform pg_temp.fails('MS4 ingrediente sin nada', $q$select create_recipe('ZZMS Mala', 2, null, null, null, '[{"quantity":1}]'::jsonb)$q$, 'P0001', 'Invalid recipe');
    perform pg_temp.fails('MS4 ingrediente no objeto', $q$select create_recipe('ZZMS Mala', 2, null, null, null, '[1]'::jsonb)$q$, 'P0001', 'Invalid recipe');
    perform pg_temp.fails('MS4 alimento inexistente', $q$select create_recipe('ZZMS Mala', 2, null, null, null, '[{"food_id":999999999}]'::jsonb)$q$, 'P0001', 'Invalid recipe');
    perform pg_temp.fails('MS4 alimento de otro hogar',
        format('select create_recipe(''ZZMS Mala'', 2, null, null, null, ''[{"food_id":%s}]''::jsonb)', pg_temp.food_id('ZZMS Propio Y')),
        'P0001', 'Invalid recipe');
    perform pg_temp.fails('MS4 update clave', format('select update_recipe(%s, ''{"foo":1}''::jsonb)', v_id), 'P0001', 'Invalid recipe');
    perform pg_temp.fails('MS4 update ingredientes malos',
        format('select update_recipe(%s, ''{"ingredients":[{"label":"x","unit":"taza"}]}''::jsonb)', v_id), 'P0001', 'Invalid recipe');
    if exists (select 1 from recipe where name = 'ZZMS Mala') then
        raise exception 'menu_semana MS4: una receta inválida dejó filas';
    end if;
    if (select count(*) from recipe_ingredient where recipe_id = v_id) <> 1 then
        raise exception 'menu_semana MS4: un update inválido dejó la receta sin sus ingredientes';
    end if;
    perform pg_temp.fails('MS4 get inexistente', $q$select get_recipe(999999999)$q$, 'P0002', 'Not Found');
    -- borrado
    perform delete_recipe(v_id);
    perform pg_temp.fails('MS4 get borrada', format('select get_recipe(%s)', v_id), 'P0002', 'Not Found');
    perform pg_temp.fails('MS4 delete dos veces', format('select delete_recipe(%s)', v_id), 'P0002', 'Not Found');
    if exists (select 1 from recipe_ingredient where recipe_id = v_id) then
        raise exception 'menu_semana MS4: el borrado dejó ingredientes';
    end if;
    -- borrar un alimento conserva el ingrediente (food_id → null, label intacta)
    v := create_food('ZZMS Efímero', 'otros', '["egg"]'::jsonb, null, null);
    v := create_recipe('ZZMS Con efímero', 2, null, null, null,
        jsonb_build_array(jsonb_build_object('food_id', (v->>'id')::bigint)));
    perform delete_food((select id from food where name = 'ZZMS Efímero'));
    v := get_recipe((v->>'id')::bigint);
    if (v->'ingredients'->0->>'food_id') is not null or (v->'ingredients'->0->>'label') <> 'ZZMS Efímero'
       or (v->'allergens')::jsonb <> '[]'::jsonb then
        raise exception 'menu_semana MS4: ingrediente tras borrar su alimento %', v;
    end if;
    perform delete_recipe((v->>'id')::bigint);
    raise notice 'ok MS4: recetas con alérgenos derivados, filtros, validación sin filas a medias y borrado';
end $$;

-- ── MS5: unicidad, revisión y validación de casillas ──
do $$
declare
    v json;
    v_old bigint;
    v_new bigint;
    v_item bigint;
    r integer;
begin
    perform pg_temp.as_user(1);
    v := get_meal_plan('2030-01-07');
    if v->>'status' <> 'draft' or (v->>'revision')::int <> 1 or json_array_length(v->'items') <> 1 then
        raise exception 'menu_semana MS5: plan inicial %', v;
    end if;
    if get_meal_plan('2030-01-21') is not null then
        raise exception 'menu_semana MS5: una semana sin plan debe dar null';
    end if;
    -- revisión vieja
    perform pg_temp.fails('MS5 stale 0', $q$select upsert_meal_plan_items('2030-01-07', 0, '[]'::jsonb)$q$, 'P0001', 'Stale meal plan revision');
    perform pg_temp.fails('MS5 stale 5', $q$select upsert_meal_plan_items('2030-01-07', 5, '[]'::jsonb)$q$, 'P0001', 'Stale meal plan revision');
    perform pg_temp.fails('MS5 sin plan y rev 3', $q$select upsert_meal_plan_items('2030-01-21', 3, '[]'::jsonb)$q$, 'P0001', 'Stale meal plan revision');
    if (select count(*) from meal_plan where home_id = 993001 and week_start = '2030-01-21') <> 0 then
        raise exception 'menu_semana MS5: un upsert stale creó un plan';
    end if;
    v := upsert_meal_plan_items('2030-01-07', 1, jsonb_build_array(jsonb_build_object(
        'day', '2030-01-07', 'slot', 'lunch', 'position', 1, 'kind', 'free_text', 'title', 'ZZMS lentejas')));
    if (v->>'revision')::int <> 2 or json_array_length(v->'items') <> 2 or v->>'status' <> 'draft' then
        raise exception 'menu_semana MS5: segunda escritura %', v;
    end if;
    if (v->'items'->1->>'title') <> 'ZZMS lentejas' or (v->'items'->0->>'title') <> 'ZZMS Receta A' then
        raise exception 'menu_semana MS5: títulos (instantánea de receta / texto libre) %', v->'items';
    end if;
    -- creación perezosa con expected 0
    v := upsert_meal_plan_items('2030-01-21', 0, null);
    if (v->>'revision')::int <> 1 or v->>'status' <> 'draft' or json_array_length(v->'items') <> 0 then
        raise exception 'menu_semana MS5: creación perezosa %', v;
    end if;
    v_old := (v->>'id')::bigint;
    perform pg_temp.fails('MS5 no lunes', $q$select upsert_meal_plan_items('2030-01-08', 0, '[]'::jsonb)$q$, 'P0001', 'Invalid meal plan');
    perform pg_temp.fails('MS5 semana nula', $q$select upsert_meal_plan_items(null, 0, '[]'::jsonb)$q$, 'P0001', 'Invalid meal plan');
    perform pg_temp.fails('MS5 revisión nula', $q$select upsert_meal_plan_items('2030-01-21', null, '[]'::jsonb)$q$, 'P0001', 'Invalid meal plan');
    perform pg_temp.fails('MS5 get semana nula', $q$select get_meal_plan(null)$q$, 'P0001', 'Invalid meal plan');
    -- unicidad por hogar y semana (índice parcial)
    perform pg_temp.fails('MS5 segundo plan',
        $q$insert into meal_plan (home_id, week_start) values (993001, '2030-01-21')$q$,
        '23505', 'duplicate key value violates unique constraint "meal_plan_home_week_uq"');
    -- archivar libera la semana
    v := archive_meal_plan(v_old);
    if v->>'status' <> 'archived' or (v->>'revision')::int <> 2 then
        raise exception 'menu_semana MS5: archive %', v;
    end if;
    if get_meal_plan('2030-01-21') is not null then
        raise exception 'menu_semana MS5: el plan archivado sigue visible en su semana';
    end if;
    perform pg_temp.fails('MS5 archivar dos veces', format('select archive_meal_plan(%s)', v_old), 'P0001', 'Invalid meal plan');
    perform pg_temp.fails('MS5 aceptar archivado', format('select accept_meal_plan(%s, 2)', v_old), 'P0001', 'Invalid meal plan');
    v := upsert_meal_plan_items('2030-01-21', 0, '[]'::jsonb);
    v_new := (v->>'id')::bigint;
    if v_new = v_old or (v->>'revision')::int <> 1 then
        raise exception 'menu_semana MS5: la semana liberada no admitió un plan nuevo %', v;
    end if;
    -- validación de casillas (revisión vigente: los errores deben ser de forma, no Stale)
    r := pg_temp.rev('2030-01-07');
    perform pg_temp.fails('MS5 día fuera', format('select upsert_meal_plan_items(''2030-01-07'', %s, ''[{"day":"2030-01-14","slot":"lunch","kind":"eat_out"}]''::jsonb)', r), 'P0001', 'Invalid meal plan');
    perform pg_temp.fails('MS5 franja', format('select upsert_meal_plan_items(''2030-01-07'', %s, ''[{"day":"2030-01-08","slot":"brunch","kind":"eat_out"}]''::jsonb)', r), 'P0001', 'Invalid meal plan');
    perform pg_temp.fails('MS5 tipo', format('select upsert_meal_plan_items(''2030-01-07'', %s, ''[{"day":"2030-01-08","slot":"lunch","kind":"x"}]''::jsonb)', r), 'P0001', 'Invalid meal plan');
    perform pg_temp.fails('MS5 receta sin id', format('select upsert_meal_plan_items(''2030-01-07'', %s, ''[{"day":"2030-01-08","slot":"lunch","kind":"recipe"}]''::jsonb)', r), 'P0001', 'Invalid meal plan');
    perform pg_temp.fails('MS5 texto libre vacío', format('select upsert_meal_plan_items(''2030-01-07'', %s, ''[{"day":"2030-01-08","slot":"lunch","kind":"free_text"}]''::jsonb)', r), 'P0001', 'Invalid meal plan');
    perform pg_temp.fails('MS5 recipe_id en texto libre',
        format('select upsert_meal_plan_items(''2030-01-07'', %s, ''[{"day":"2030-01-08","slot":"lunch","kind":"free_text","title":"x","recipe_id":%s}]''::jsonb)', r, pg_temp.recipe_id('ZZMS Receta A')),
        'P0001', 'Invalid meal plan');
    perform pg_temp.fails('MS5 clave desconocida', format('select upsert_meal_plan_items(''2030-01-07'', %s, ''[{"day":"2030-01-08","slot":"lunch","kind":"eat_out","foo":1}]''::jsonb)', r), 'P0001', 'Invalid meal plan');
    perform pg_temp.fails('MS5 título largo', format('select upsert_meal_plan_items(''2030-01-07'', %s, jsonb_build_array(jsonb_build_object(''day'',''2030-01-08'',''slot'',''lunch'',''kind'',''free_text'',''title'',repeat(''x'',201))))', r), 'P0001', 'Invalid meal plan');
    perform pg_temp.fails('MS5 casilla de otro plan', format('select upsert_meal_plan_items(''2030-01-07'', %s, ''[{"id":999999999,"day":"2030-01-08","slot":"lunch","kind":"eat_out"}]''::jsonb)', r), 'P0001', 'Invalid meal plan');
    perform pg_temp.fails('MS5 posición repetida', format('select upsert_meal_plan_items(''2030-01-07'', %s, ''[{"day":"2030-01-08","slot":"dinner","kind":"eat_out"},{"day":"2030-01-08","slot":"dinner","kind":"leftovers"}]''::jsonb)', r), 'P0001', 'Invalid meal plan');
    if pg_temp.rev('2030-01-07') <> r or (select count(*) from meal_plan_item where plan_id = pg_temp.plan_id('2030-01-07')) <> 2 then
        raise exception 'menu_semana MS5: una escritura inválida cambió la revisión o dejó casillas';
    end if;
    -- intercambio de posiciones en una sola llamada y borrado por id
    v := upsert_meal_plan_items('2030-01-07', r, '[{"day":"2030-01-09","slot":"dinner","position":0,"kind":"eat_out"},{"day":"2030-01-09","slot":"dinner","position":1,"kind":"leftovers","title":"ZZMS sobras"}]'::jsonb);
    r := (v->>'revision')::int;
    select (e->>'id')::bigint into v_item from json_array_elements(v->'items') e where e->>'kind' = 'eat_out';
    v := upsert_meal_plan_items('2030-01-07', r, format(
        '[{"id":%s,"day":"2030-01-09","slot":"dinner","position":1,"kind":"eat_out"},{"id":%s,"day":"2030-01-09","slot":"dinner","position":0,"kind":"leftovers","title":"ZZMS sobras"}]',
        v_item, (select (e->>'id')::bigint from json_array_elements(v->'items') e where e->>'kind' = 'leftovers'))::jsonb);
    if (select e->>'kind' from json_array_elements(v->'items') e where e->>'day' = '2030-01-09' order by (e->>'position')::int limit 1) <> 'leftovers' then
        raise exception 'menu_semana MS5: el intercambio de posiciones no se aplicó %', v->'items';
    end if;
    v := upsert_meal_plan_items('2030-01-07', (v->>'revision')::int, null, array[v_item]);
    if exists (select 1 from json_array_elements(v->'items') e where (e->>'id')::bigint = v_item) then
        raise exception 'menu_semana MS5: p_delete_ids no borró la casilla';
    end if;
    raise notice 'ok MS5: único por hogar y semana, revisión vieja = Stale, creación perezosa, validación de casillas, intercambio y borrado';
end $$;

-- ── MS6: ciclo del plan ──
do $$
declare
    v json;
    v_id bigint;
begin
    perform pg_temp.as_user(1);
    v := upsert_meal_plan_items('2030-01-14', 0, '[]'::jsonb);
    v_id := (v->>'id')::bigint;
    perform pg_temp.fails('MS6 aceptar sin casillas', format('select accept_meal_plan(%s, 1)', v_id), 'P0001', 'Invalid meal plan');
    v := upsert_meal_plan_items('2030-01-14', 1, '[{"day":"2030-01-14","slot":"dinner","kind":"eat_out"}]'::jsonb);
    if (v->>'revision')::int <> 2 then
        raise exception 'menu_semana MS6: revisión tras añadir casilla %', v;
    end if;
    perform pg_temp.fails('MS6 aceptar stale', format('select accept_meal_plan(%s, 1)', v_id), 'P0001', 'Stale meal plan revision');
    v := accept_meal_plan(v_id, 2);
    if v->>'status' <> 'accepted' or (v->>'revision')::int <> 3 or (v->>'accepted_by')::bigint <> 993001 or v->>'accepted_at' is null then
        raise exception 'menu_semana MS6: accept %', v;
    end if;
    perform pg_temp.fails('MS6 aceptar dos veces', format('select accept_meal_plan(%s, 3)', v_id), 'P0001', 'Invalid meal plan');
    -- editar un aceptado lo devuelve a draft y sube la revisión
    v := upsert_meal_plan_items('2030-01-14', 3, '[{"day":"2030-01-15","slot":"lunch","kind":"leftovers"}]'::jsonb);
    if v->>'status' <> 'draft' or (v->>'revision')::int <> 4 or v->>'accepted_at' is not null or v->>'accepted_by' is not null then
        raise exception 'menu_semana MS6: editar un aceptado %', v;
    end if;
    v := accept_meal_plan(v_id, 4);
    if v->>'status' <> 'accepted' or (v->>'revision')::int <> 5 then
        raise exception 'menu_semana MS6: segundo accept %', v;
    end if;
    v := archive_meal_plan(v_id);
    if v->>'status' <> 'archived' or (v->>'revision')::int <> 6 then
        raise exception 'menu_semana MS6: archive de un aceptado %', v;
    end if;
    if pg_temp.plan_id('2030-01-14') is not null then
        raise exception 'menu_semana MS6: la semana archivada no quedó libre';
    end if;
    -- el auditado de cada paso existe y no lleva datos de menú
    if (select count(distinct action) from audit_log where home_id = 993001
        and action in ('meal.plan.update', 'meal.plan.accept', 'meal.plan.archive', 'meal.recipe.create', 'meal.food.create')) <> 5 then
        raise exception 'menu_semana MS6: faltan acciones de auditoría meal.*';
    end if;
    raise notice 'ok MS6: draft → accepted → draft al editar → accepted → archived, con revisión +1 por escritura';
end $$;

-- ── MS7: copiar semana ──
do $$
declare
    v json;
    v_src json;
begin
    perform pg_temp.as_user(1);
    v_src := get_meal_plan('2030-01-07');
    perform pg_temp.fails('MS7 semana ocupada', $q$select copy_meal_plan_week('2030-01-07', '2030-01-21')$q$, 'P0001', 'Meal plan exists');
    perform pg_temp.fails('MS7 origen sin plan', $q$select copy_meal_plan_week('2030-02-18', '2030-02-25')$q$, 'P0002', 'Not Found');
    perform pg_temp.fails('MS7 misma semana', $q$select copy_meal_plan_week('2030-01-07', '2030-01-07')$q$, 'P0001', 'Invalid meal plan');
    perform pg_temp.fails('MS7 no lunes', $q$select copy_meal_plan_week('2030-01-07', '2030-01-15')$q$, 'P0001', 'Invalid meal plan');
    perform pg_temp.fails('MS7 nulo', $q$select copy_meal_plan_week(null, '2030-01-14')$q$, 'P0001', 'Invalid meal plan');
    -- W2 quedó archivada en MS6: libre
    v := copy_meal_plan_week('2030-01-07', '2030-01-14');
    if v->>'status' <> 'draft' or (v->>'revision')::int <> 1 or v->>'week_start' <> '2030-01-14'
       or json_array_length(v->'items') <> json_array_length(v_src->'items') then
        raise exception 'menu_semana MS7: copia %', v;
    end if;
    if exists (select 1 from json_array_elements(v->'items') n
               where not exists (select 1 from json_array_elements(v_src->'items') o
                                 where (o->>'day')::date + 7 = (n->>'day')::date and o->>'slot' = n->>'slot'
                                   and o->>'kind' = n->>'kind' and o->>'title' = n->>'title'
                                   and (o->'members')::jsonb = (n->'members')::jsonb)) then
        raise exception 'menu_semana MS7: las casillas copiadas no son las del origen desplazadas 7 días %', v->'items';
    end if;
    -- el origen no cambió
    if get_meal_plan('2030-01-07')::text <> v_src::text then
        raise exception 'menu_semana MS7: copiar cambió el origen';
    end if;
    -- ahora W2 está ocupada
    perform pg_temp.fails('MS7 copiar otra vez', $q$select copy_meal_plan_week('2030-01-07', '2030-01-14')$q$, 'P0001', 'Meal plan exists');
    raise notice 'ok MS7: copia desplazada con casillas y comensales; semana ocupada = Meal plan exists';
end $$;

-- ── MS8: comensales por defecto ──
do $$
declare
    v json;
    v_items json;
begin
    perform pg_temp.as_user(1);
    perform update_meal_profile_member(993001, '{"age_band":"adult"}'::jsonb);
    perform update_meal_profile_member(993002, '{"age_band":"adult"}'::jsonb);
    perform update_meal_profile_member(993003, '{"age_band":"4-12"}'::jsonb);
    -- B no come en casa los lunes a mediodía (weekday 1 = lunes)
    perform set_meal_schedule('[{"home_member_id":993002,"weekday":1,"slot":"lunch","status":"out"}]'::jsonb);
    v := upsert_meal_plan_items('2030-01-28', 0, '[
        {"day":"2030-01-28","slot":"lunch","kind":"free_text","title":"ZZMS lunes"},
        {"day":"2030-01-29","slot":"lunch","kind":"free_text","title":"ZZMS martes"},
        {"day":"2030-01-30","slot":"lunch","kind":"free_text","title":"ZZMS nadie","members":[]},
        {"day":"2030-01-31","slot":"lunch","kind":"free_text","title":"ZZMS solo B","members":[993002],"cook_member_id":993001},
        {"day":"2030-02-01","slot":"lunch","kind":"free_text","title":"ZZMS peque","members":[993006]}]'::jsonb);
    v_items := v->'items';
    if (v_items->0->'members')::jsonb <> '[993001,993003]'::jsonb then
        raise exception 'menu_semana MS8: lunes (B fuera) %', v_items->0;
    end if;
    if (v_items->1->'members')::jsonb <> '[993001,993002,993003]'::jsonb then
        raise exception 'menu_semana MS8: martes (todos en casa) %', v_items->1;
    end if;
    if (v_items->2->'members')::jsonb <> '[]'::jsonb then
        raise exception 'menu_semana MS8: members [] explícito debe ser nadie %', v_items->2;
    end if;
    if (v_items->3->'members')::jsonb <> '[993002]'::jsonb or (v_items->3->>'cook_member_id')::bigint <> 993001 then
        raise exception 'menu_semana MS8: members explícitos y cocinero %', v_items->3;
    end if;
    if (v_items->4->'members')::jsonb <> '[993006]'::jsonb then
        raise exception 'menu_semana MS8: miembro sin ficha de perfil %', v_items->4;
    end if;
    -- reenviar una casilla existente sin members conserva los suyos
    v := upsert_meal_plan_items('2030-01-28', (v->>'revision')::int, jsonb_build_array(jsonb_build_object(
        'id', (v_items->3->>'id')::bigint, 'day', '2030-01-31', 'slot', 'lunch', 'kind', 'free_text', 'title', 'ZZMS solo B v2')));
    if (select (e->'members')::jsonb from json_array_elements(v->'items') e where e->>'title' = 'ZZMS solo B v2') <> '[993002]'::jsonb then
        raise exception 'menu_semana MS8: reenviar sin members debe conservarlos';
    end if;
    -- inválidos
    perform pg_temp.fails('MS8 mascota', format('select upsert_meal_plan_items(''2030-01-28'', %s, ''[{"day":"2030-01-28","slot":"dinner","kind":"eat_out","members":[993005]}]''::jsonb)', v->>'revision'), 'P0001', 'Invalid meal plan');
    perform pg_temp.fails('MS8 otro hogar', format('select upsert_meal_plan_items(''2030-01-28'', %s, ''[{"day":"2030-01-28","slot":"dinner","kind":"eat_out","members":[993008]}]''::jsonb)', v->>'revision'), 'P0001', 'Invalid meal plan');
    perform pg_temp.fails('MS8 members no array', format('select upsert_meal_plan_items(''2030-01-28'', %s, ''[{"day":"2030-01-28","slot":"dinner","kind":"eat_out","members":"x"}]''::jsonb)', v->>'revision'), 'P0001', 'Invalid meal plan');
    perform pg_temp.fails('MS8 cocinero ajeno', format('select upsert_meal_plan_items(''2030-01-28'', %s, ''[{"day":"2030-01-28","slot":"dinner","kind":"eat_out","cook_member_id":993008}]''::jsonb)', v->>'revision'), 'P0001', 'Invalid meal plan');
    raise notice 'ok MS8: comensales por defecto según meal_schedule, [] explícito = nadie, miembros inválidos rechazados';
end $$;

-- ── MS9: check_meal_plan ──
do $$
declare
    v json;
    c json;
    v_recipe json;
    v_plan bigint;
begin
    perform pg_temp.as_user(1);
    perform update_meal_profile_member(993001, '{"diet":"vegetarian"}'::jsonb);
    perform update_meal_profile_member(993002, '{"allergies_answered":true,"allergies":[{"allergen":"milk","severity":"avoid_ingredient"}]}'::jsonb);
    perform update_meal_profile_member(993003, '{"allergies_answered":true,"allergies":[{"allergen":"gluten","severity":"no_traces"}]}'::jsonb);
    perform create_food('ZZMS Pollo', 'carne', null, 'g', null);
    perform create_food('ZZMS Pan', 'cereales', '["gluten"]'::jsonb, 'g', null);
    v_recipe := create_recipe('ZZMS Combo', 4, 20, '["lunch"]'::jsonb, null, jsonb_build_array(
        jsonb_build_object('food_id', pg_temp.food_id('ZZMS Leche A'), 'quantity', 100, 'unit', 'ml'),
        jsonb_build_object('food_id', pg_temp.food_id('ZZMS Pollo'), 'quantity', 200, 'unit', 'g'),
        jsonb_build_object('food_id', pg_temp.food_id('ZZMS Pan'), 'quantity', 50, 'unit', 'g'),
        jsonb_build_object('label', 'sal', 'unit', 'al gusto')));
    -- lunes a mediodía: B está fuera (MS8)
    v := upsert_meal_plan_items('2030-02-04', 0, jsonb_build_array(
        jsonb_build_object('day', '2030-02-04', 'slot', 'lunch', 'kind', 'recipe', 'recipe_id', (v_recipe->>'id')::bigint,
                           'members', jsonb_build_array(993001, 993002, 993003)),
        jsonb_build_object('day', '2030-02-05', 'slot', 'lunch', 'kind', 'recipe', 'recipe_id', (v_recipe->>'id')::bigint,
                           'members', jsonb_build_array(993001)),
        jsonb_build_object('day', '2030-02-06', 'slot', 'lunch', 'kind', 'free_text', 'title', 'ZZMS libre',
                           'members', jsonb_build_array(993002))));
    v_plan := (v->>'id')::bigint;
    c := check_meal_plan(v_plan);
    if json_array_length(c) <> 5 then
        raise exception 'menu_semana MS9: se esperaban 5 avisos y hay % %', json_array_length(c), c;
    end if;
    -- lunes: B fuera de casa (member_out), alérgico a la leche (allergen), C con trazas de gluten (intolerance), A vegetariano con pollo (diet)
    if not exists (select 1 from json_array_elements(c) e where (e->>'member_id')::bigint = 993002 and e->>'code' = 'member_out'
                   and e->>'day' = '2030-02-04' and e->'detail'->>'status' = 'out')
       or not exists (select 1 from json_array_elements(c) e where (e->>'member_id')::bigint = 993002 and e->>'code' = 'allergen'
                      and e->'detail'->>'allergen' = 'milk' and e->'detail'->>'ingredient' = 'ZZMS Leche A')
       or not exists (select 1 from json_array_elements(c) e where (e->>'member_id')::bigint = 993003 and e->>'code' = 'intolerance'
                      and e->'detail'->>'allergen' = 'gluten')
       or not exists (select 1 from json_array_elements(c) e where (e->>'member_id')::bigint = 993001 and e->>'code' = 'diet'
                      and e->'detail'->>'ingredient' = 'ZZMS Pollo' and e->>'day' = '2030-02-04') then
        raise exception 'menu_semana MS9: avisos del lunes %', c;
    end if;
    -- martes: solo A con el pollo (diet); B solo en el texto libre del miércoles no se evalúa (ni alérgeno ni member_out: está en casa)
    if (select count(*) from json_array_elements(c) e where e->>'day' = '2030-02-05') <> 1
       or exists (select 1 from json_array_elements(c) e where e->>'day' = '2030-02-06') then
        raise exception 'menu_semana MS9: avisos de martes/miércoles %', c;
    end if;
    -- un plan sin conflictos devuelve [] (W4: casillas de texto libre y B solo come el jueves, en casa)
    if json_array_length(check_meal_plan(pg_temp.plan_id('2030-01-28'))) <> 0 then
        raise exception 'menu_semana MS9: W4 no debía tener avisos %', check_meal_plan(pg_temp.plan_id('2030-01-28'));
    end if;
    perform pg_temp.fails('MS9 plan inexistente', $q$select check_meal_plan(999999999)$q$, 'P0002', 'Not Found');
    -- el audit de perfil no copia los datos de salud
    raise notice 'ok MS9: member_out, allergen (B1), intolerance (B2) y diet (B5) detectados; sin avisos donde no hay conflicto';
end $$;

-- ── MS10: comidas de hoy con la zona del hogar ──
do $$
declare
    t json;
    v json;
    v_tz text;
    v_d date;
    v_w date;
    v_other date;
    v_dates date[] := array[]::date[];
begin
    foreach v_tz in array array['Pacific/Kiritimati', 'Etc/GMT+12'] loop
        update home set timezone = v_tz where id = 993001;
        v_d := (now() at time zone v_tz)::date;
        v_w := v_d - (extract(isodow from v_d)::int - 1);
        delete from meal_plan where home_id = 993001 and week_start = v_w and status <> 'archived';
        perform pg_temp.as_user(1);
        v := upsert_meal_plan_items(v_w, 0, jsonb_build_array(jsonb_build_object(
            'day', v_d, 'slot', 'lunch', 'kind', 'free_text', 'title', 'ZZMS hoy ' || v_tz)));
        t := get_meals_today();
        if (t->>'has_plan')::boolean is not false or t->>'timezone' <> v_tz or (t->>'date')::date <> v_d
           or json_array_length(t->'items') <> 0 or t->>'now_local' !~ '^[0-9]{2}:[0-9]{2}$' then
            raise exception 'menu_semana MS10: borrador en % debe dar has_plan=false %', v_tz, t;
        end if;
        perform accept_meal_plan((v->>'id')::bigint, (v->>'revision')::int);
        t := get_meals_today();
        if (t->>'has_plan')::boolean is not true or (t->>'date')::date <> v_d or json_array_length(t->'items') <> 1
           or t->'items'->0->>'title' <> 'ZZMS hoy ' || v_tz or t->'items'->0->>'time' <> '14:00'
           or t->'items'->0->>'slot' <> 'lunch' or t->'items'->0->>'kind' <> 'free_text' then
            raise exception 'menu_semana MS10: comidas de hoy en % %', v_tz, t;
        end if;
        -- otro día de la misma semana sin casillas: has_plan = true con items []
        v_other := v_w + (((v_d - v_w) + 1) % 7);
        t := get_meals_today(v_other);
        if (t->>'has_plan')::boolean is not true or json_array_length(t->'items') <> 0 or (t->>'date')::date <> v_other then
            raise exception 'menu_semana MS10: día sin casillas en % %', v_tz, t;
        end if;
        -- una semana sin plan aceptado oculta el bloque
        t := get_meals_today(v_w + 14);
        if (t->>'has_plan')::boolean is not false then
            raise exception 'menu_semana MS10: semana sin plan debe dar has_plan=false %', t;
        end if;
        v_dates := v_dates || v_d;
    end loop;
    -- UTC+14 y UTC-12 se llevan 26 h: las fechas locales siempre difieren
    if v_dates[1] = v_dates[2] then
        raise exception 'menu_semana MS10: las fechas de Kiritimati y GMT-12 coinciden %', v_dates;
    end if;
    -- la hora de la franja sale de meal_slot_setting
    perform set_meal_slot_settings('[{"slot":"lunch","time":"13:30"}]'::jsonb);
    t := get_meals_today();
    if t->'items'->0->>'time' <> '13:30' then
        raise exception 'menu_semana MS10: la hora de franja no sale de meal_slot_setting %', t;
    end if;
    update home set timezone = 'Foo/Bar' where id = 993001;
    perform pg_temp.fails('MS10 zona inválida', $q$select get_meals_today()$q$, 'P0001', 'Invalid timezone');
    update home set timezone = 'Europe/Madrid' where id = 993001;
    raise notice 'ok MS10: get_meals_today usa home.timezone (% / %), has_plan falso con borrador o sin plan, items [] con menú sin casillas hoy', v_dates[1], v_dates[2];
end $$;

-- ── MS11: cross-tenant por RPC ──
do $$
declare
    v_rid bigint := pg_temp.recipe_id('ZZMS Receta A');
    v_fid bigint := pg_temp.food_id('ZZMS Leche A');
    v_pid bigint := pg_temp.plan_id('2030-01-07');
    v_rev integer := pg_temp.rev('2030-01-07');
    s text;
    v json;
begin
    -- con la cabecera de H, Y no es miembro: Not Found
    perform pg_temp.as_user(5, 993001);
    foreach s in array array[
        $q$select get_meal_plan('2030-01-07')$q$, $q$select list_recipes()$q$, $q$select search_food('zzms')$q$,
        $q$select get_meals_today()$q$, $q$select create_recipe('ZZMS Y', 2)$q$,
        $q$select upsert_meal_plan_items('2030-01-07', 2, '[]'::jsonb)$q$] loop
        perform pg_temp.fails('MS11 cabecera ajena ' || s, s, 'P0002', 'Not Found');
    end loop;
    -- sin cabecera, Y opera en su hogar: lo de H no existe para él
    perform pg_temp.as_user(5);
    if get_meal_plan('2030-01-07') is not null then
        raise exception 'menu_semana MS11: Y ve el plan de H';
    end if;
    if json_array_length(list_recipes()) <> 0 or json_array_length(search_food('ZZMS Leche')) <> 0 then
        raise exception 'menu_semana MS11: Y ve recetas o alimentos de H';
    end if;
    foreach s in array array[
        format('select get_recipe(%s)', v_rid),
        format('select update_recipe(%s, ''{"name":"ZZMS hack"}''::jsonb)', v_rid),
        format('select delete_recipe(%s)', v_rid),
        format('select update_food(%s, ''{"name":"ZZMS hack"}''::jsonb)', v_fid),
        format('select delete_food(%s)', v_fid),
        format('select accept_meal_plan(%s, %s)', v_pid, v_rev),
        format('select archive_meal_plan(%s)', v_pid),
        format('select check_meal_plan(%s)', v_pid),
        $q$select copy_meal_plan_week('2030-01-07', '2030-03-04')$q$] loop
        perform pg_temp.fails('MS11 ' || s, s, 'P0002', 'Not Found');
    end loop;
    -- datos de H dentro de lo de Y: Invalid
    perform pg_temp.fails('MS11 receta de H en mi plan',
        format('select upsert_meal_plan_items(''2030-01-07'', 0, ''[{"day":"2030-01-07","slot":"lunch","kind":"recipe","recipe_id":%s}]''::jsonb)', v_rid),
        'P0001', 'Invalid meal plan');
    perform pg_temp.fails('MS11 cocinero de H en mi plan',
        $q$select upsert_meal_plan_items('2030-01-07', 0, '[{"day":"2030-01-07","slot":"lunch","kind":"eat_out","cook_member_id":993001}]'::jsonb)$q$,
        'P0001', 'Invalid meal plan');
    perform pg_temp.fails('MS11 comensal de H en mi plan',
        $q$select upsert_meal_plan_items('2030-01-07', 0, '[{"day":"2030-01-07","slot":"lunch","kind":"eat_out","members":[993001]}]'::jsonb)$q$,
        'P0001', 'Invalid meal plan');
    perform pg_temp.fails('MS11 alimento de H en mi receta',
        format('select create_recipe(''ZZMS Y2'', 2, null, null, null, ''[{"food_id":%s}]''::jsonb)', v_fid),
        'P0001', 'Invalid recipe');
    if exists (select 1 from meal_plan where home_id = 993002) or exists (select 1 from recipe where home_id = 993002) then
        raise exception 'menu_semana MS11: los intentos inválidos de Y dejaron filas';
    end if;
    -- lo de H sigue intacto
    if pg_temp.rev('2030-01-07') <> v_rev or pg_temp.recipe_id('ZZMS Receta A') <> v_rid
       or pg_temp.food_id('ZZMS Leche A') <> v_fid or (select name from food where id = v_fid) <> 'ZZMS Leche A' then
        raise exception 'menu_semana MS11: Y modificó datos de H';
    end if;
    raise notice 'ok MS11: Y no lee ni escribe recetas, alimentos ni planes de H (Not Found / Invalid), lo de H intacto';
end $$;

-- ── MS12: grants y RLS ──
do $$
declare
    t text;
begin
    foreach t in array array['food', 'recipe', 'recipe_ingredient', 'meal_plan', 'meal_plan_item', 'meal_plan_item_member'] loop
        if not (select relrowsecurity from pg_class where oid = ('public.' || t)::regclass) then
            raise exception 'menu_semana MS12: % sin RLS', t;
        end if;
        if has_table_privilege('anon', 'public.' || t, 'select,insert,update,delete')
           or has_table_privilege('authenticated', 'public.' || t, 'insert,update,delete')
           or not has_table_privilege('authenticated', 'public.' || t, 'select') then
            raise exception 'menu_semana MS12: privilegios de % incorrectos', t;
        end if;
        if exists (select 1 from pg_policy where polrelid = ('public.' || t)::regclass and polcmd <> 'r') then
            raise exception 'menu_semana MS12: % con policy de escritura', t;
        end if;
        if (select count(*) from pg_policy where polrelid = ('public.' || t)::regclass) <> 1 then
            raise exception 'menu_semana MS12: % debe tener exactamente 1 policy', t;
        end if;
    end loop;
    foreach t in array array['search_food(text,integer)', 'create_food(text,text,jsonb,text,numeric)', 'update_food(bigint,jsonb)',
            'delete_food(bigint)', 'list_recipes(text,text,integer)', 'get_recipe(bigint)',
            'create_recipe(text,integer,integer,jsonb,jsonb,jsonb)', 'update_recipe(bigint,jsonb)', 'delete_recipe(bigint)',
            'get_meal_plan(date)', 'upsert_meal_plan_items(date,integer,jsonb,bigint[])', 'accept_meal_plan(bigint,integer)',
            'archive_meal_plan(bigint,integer)', 'copy_meal_plan_week(date,date)', 'check_meal_plan(bigint)', 'get_meals_today(date)'] loop
        if has_function_privilege('anon', t, 'execute') or not has_function_privilege('authenticated', t, 'execute') then
            raise exception 'menu_semana MS12: EXECUTE incorrecto en %', t;
        end if;
    end loop;
    foreach t in array array['fn_meal_norm(text)', 'fn_meal_food_allergens_valid(text[])', 'fn_meal_food_before()',
            'fn_meal_food_json(bigint)', 'fn_meal_recipe_json(bigint)', 'fn_meal_recipe_set_ingredients(bigint,bigint,jsonb)',
            'fn_meal_plan_json(bigint)', 'fn_meal_week_of(bigint,date)'] loop
        if has_function_privilege('anon', t, 'execute') or has_function_privilege('authenticated', t, 'execute') then
            raise exception 'menu_semana MS12: helper % accesible', t;
        end if;
    end loop;
    -- índices únicos parciales y composición
    if not exists (select 1 from pg_indexes where indexname = 'meal_plan_home_week_uq' and indexdef like '%WHERE%archived%')
       or not exists (select 1 from pg_indexes where indexname = 'food_common_name_uq' and indexdef like '%home_id IS NULL%')
       or not exists (select 1 from pg_indexes where indexname = 'food_home_name_uq' and indexdef like '%home_id IS NOT NULL%') then
        raise exception 'menu_semana MS12: faltan los índices únicos parciales';
    end if;
    -- el seed del catálogo común: idempotente y sin duplicados por name_norm
    if exists (select 1 from food where home_id is null group by name_norm having count(*) > 1) then
        raise exception 'menu_semana MS12: nombres normalizados duplicados en el catálogo común';
    end if;
    if exists (select 1 from food where home_id is null and not fn_meal_food_allergens_valid(allergens)) then
        raise exception 'menu_semana MS12: alérgenos inválidos en el catálogo común';
    end if;
    raise notice 'ok MS12: RLS activa con 1 policy SELECT por tabla, RPC solo para authenticated, helpers cerrados, índices parciales';
end $$;

-- ── MS13: receta borrada ──
do $$
declare
    v json;
    v_item bigint;
    v_rid bigint;
begin
    perform pg_temp.as_user(1);
    v_rid := (create_recipe('ZZMS Borrar', 3, null, null, null, null)->>'id')::bigint;
    v := upsert_meal_plan_items('2030-02-11', 0, jsonb_build_array(jsonb_build_object(
        'day', '2030-02-11', 'slot', 'dinner', 'kind', 'recipe', 'recipe_id', v_rid)));
    v_item := (v->'items'->0->>'id')::bigint;
    if (v->'items'->0->>'servings')::int <> 3 then
        raise exception 'menu_semana MS13: las raciones por defecto salen de la receta %', v->'items'->0;
    end if;
    perform delete_recipe(v_rid);
    v := get_meal_plan('2030-02-11');
    if v->'items'->0->>'recipe_id' is not null or v->'items'->0->>'title' <> 'ZZMS Borrar' or v->'items'->0->>'kind' <> 'recipe' then
        raise exception 'menu_semana MS13: la casilla no conserva el título tras borrar la receta %', v->'items'->0;
    end if;
    -- reenviar la casilla tal cual (sin recipe_id) no falla y conserva el título
    v := upsert_meal_plan_items('2030-02-11', (v->>'revision')::int, jsonb_build_array(jsonb_build_object(
        'id', v_item, 'day', '2030-02-11', 'slot', 'dinner', 'kind', 'recipe', 'servings', 2)));
    if v->'items'->0->>'title' <> 'ZZMS Borrar' or (v->'items'->0->>'servings')::int <> 2 then
        raise exception 'menu_semana MS13: reenviar la casilla de una receta borrada %', v->'items'->0;
    end if;
    -- una casilla nueva de receta sin recipe_id sigue siendo inválida
    perform pg_temp.fails('MS13 receta sin id nueva',
        format('select upsert_meal_plan_items(''2030-02-11'', %s, ''[{"day":"2030-02-12","slot":"dinner","kind":"recipe"}]''::jsonb)', v->>'revision'),
        'P0001', 'Invalid meal plan');
    raise notice 'ok MS13: borrar una receta conserva el título de sus casillas';
end $$;

-- ── MS15: week_start_day bloqueado con planes no archivados (R1-01) ──
do $$
declare
    v_id bigint;
begin
    perform pg_temp.as_user(1);
    if (select count(*) from meal_plan where home_id = 993001 and status <> 'archived') = 0 then
        raise exception 'menu_semana MS15: el fixture no tiene planes vivos';
    end if;
    perform pg_temp.fails('MS15 cambio con planes', $q$select update_meal_profile('{"week_start_day":7}'::jsonb)$q$,
        'P0001', 'Invalid meal profile');
    perform update_meal_profile('{"week_start_day":1}'::jsonb);   -- mismo valor: sin efecto
    if (select week_start_day from meal_profile where home_id = 993001) <> 1 then
        raise exception 'menu_semana MS15: week_start_day cambió con planes vivos';
    end if;
    for v_id in select id from meal_plan where home_id = 993001 and status <> 'archived' loop
        perform archive_meal_plan(v_id);
    end loop;
    perform update_meal_profile('{"week_start_day":7}'::jsonb);
    if (select week_start_day from meal_profile where home_id = 993001) <> 7 then
        raise exception 'menu_semana MS15: no cambió sin planes vivos';
    end if;
    perform update_meal_profile('{"week_start_day":1}'::jsonb);
    raise notice 'ok MS15: week_start_day solo cambia sin planes no archivados';
end $$;

-- ── MS16: revisión esperada en accept y archive (R1-02) ──
do $$
declare
    v json;
    v_id bigint;
begin
    perform pg_temp.as_user(1);
    v := upsert_meal_plan_items('2030-03-04', 0, jsonb_build_array(jsonb_build_object(
        'day', '2030-03-04', 'slot', 'lunch', 'kind', 'free_text', 'title', 'ZZMS rev')));
    v_id := (v->>'id')::bigint;
    perform pg_temp.fails('MS16 archive revisión vieja', format('select archive_meal_plan(%s, 0)', v_id),
        'P0001', 'Stale meal plan revision');
    v := accept_meal_plan(v_id, 1);
    if v->>'status' <> 'accepted' or (v->>'revision')::int <> 2 then
        raise exception 'menu_semana MS16: accept %', v;
    end if;
    -- segunda aceptación con la revisión vieja: Stale (409), no Invalid
    perform pg_temp.fails('MS16 accept doble', format('select accept_meal_plan(%s, 1)', v_id),
        'P0001', 'Stale meal plan revision');
    perform pg_temp.fails('MS16 archive tras otra escritura', format('select archive_meal_plan(%s, 1)', v_id),
        'P0001', 'Stale meal plan revision');
    if (select status from meal_plan where id = v_id) <> 'accepted' then
        raise exception 'menu_semana MS16: un archive stale cambió el plan';
    end if;
    v := archive_meal_plan(v_id, 2);
    if v->>'status' <> 'archived' or (v->>'revision')::int <> 3 then
        raise exception 'menu_semana MS16: archive con revisión vigente %', v;
    end if;
    -- sin expected_revision sigue valiendo (compatibilidad)
    raise notice 'ok MS16: accept y archive respetan expected_revision';
end $$;

-- ── MS14: limpieza ──
select pg_temp.clean();
do $$
begin
    if exists (select 1 from app_user where id between 993001 and 993005)
       or exists (select 1 from home where id in (993001, 993002))
       or exists (select 1 from food where home_id in (993001, 993002) or name like 'ZZMS%')
       or exists (select 1 from recipe where home_id in (993001, 993002))
       or exists (select 1 from recipe_ingredient where home_id in (993001, 993002))
       or exists (select 1 from meal_plan where home_id in (993001, 993002))
       or exists (select 1 from meal_plan_item where home_id in (993001, 993002))
       or exists (select 1 from meal_plan_item_member where home_id in (993001, 993002)) then
        raise exception 'menu_semana MS14: quedaron filas scratch';
    end if;
    raise notice 'ok MS14: 0 filas scratch';
end $$;
