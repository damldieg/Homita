-- shopping_check.sql — La Compra del menú (0045_menus_compra.sql). Solo BD local, tras el reset
-- 0001–0045 y la semilla supabase/seed/food_es.sql:
--   psql -v ON_ERROR_STOP=1 -f shopping_check.sql
-- Cada bloque DO emite 'ok SHx: …' o aborta con 'shopping SHx: …'.
--
-- Fixture (ids 994xxx, auth_uid …0e0001–…0e0005): hogar H (994001) con A admin (home_member 994001),
-- B adulto (994002), C niño con cuenta (994003), D invitado (994004), un niño sin cuenta (994006); hogar G
-- (994002) con Y admin. Semana W1 = 2030-01-07 (lunes). Todo lo creado lleva el prefijo 'ZZSH'.
-- Receta R1 (2 raciones, 4 comensales → factor 2) y R2 (4 raciones, 2 comensales → factor 0,5).
--
-- SH1  suma con conversiones (kg+g, l+ml, ud con grams_per_unit, cda y cdta aparte), factor
--      comensales/servings, redondeo comprable, y exclusión de opcional, «al gusto» y despensa.
-- SH2  plan en draft sin compra no genera nada; aceptar genera 8 líneas y devuelve shopping_sync;
--      una segunda sincronización da {0,0,0}.
-- SH3  mismo client_request_id = mismo resultado (sync y alta), y kind equivocado → Invalid client_request_id.
-- SH4  tras editar el menú aceptado (el plan vuelve a draft) la compra se reconcilia sin tocar checked,
--      skipped («ya lo tengo»), manuales ni cantidades editadas.
-- SH5  volver a aceptar reconcilia con {0,0,0}; archivar el plan no borra la compra y no se sincroniza.
-- SH6  permisos: niño lee, marca, «ya lo tengo» y añade; invitado → Not Allowed en todo.
-- SH7  RLS y cross-tenant: Y no lee ni escribe la compra de H (RPC → Not Found; tablas → vacío o denegado).
-- SH8  vaciar comprados y borrar: manuales se borran, los de origen menu se ocultan sin que vuelvan.
-- SH9  client_request admite los kinds nuevos y rechaza uno inválido.
-- SH10 grants: solo SELECT sobre la tabla, RPC solo para authenticated, helpers cerrados.
-- SH11 0 filas scratch al terminar.

\set ON_ERROR_STOP 1
do $$
begin
    if inet_server_addr() is not null and host(inet_server_addr()) not in ('127.0.0.1', '::1') then
        raise exception 'shopping_check: solo BD local (socket o loopback); servidor %', host(inet_server_addr());
    end if;
    if to_regclass('public.shopping_item') is null then
        raise exception 'shopping_check: 0045 no está aplicada (falta shopping_item)';
    end if;
end $$;

create function pg_temp.clean() returns void
language plpgsql as $$
begin
    set local session_replication_role = replica;
    delete from shopping_item where home_id in (994001, 994002);
    delete from client_request where app_user_id between 994001 and 994005;
    delete from meal_plan_item_member where home_id in (994001, 994002);
    delete from meal_plan_item where home_id in (994001, 994002);
    delete from meal_plan where home_id in (994001, 994002);
    delete from recipe_ingredient where home_id in (994001, 994002);
    delete from recipe where home_id in (994001, 994002);
    delete from food where home_id in (994001, 994002) or name like 'ZZSH%';
    delete from meal_schedule where home_id in (994001, 994002);
    delete from meal_profile_member where home_id in (994001, 994002);
    delete from meal_slot_setting where home_id in (994001, 994002);
    delete from meal_profile where home_id in (994001, 994002);
    delete from membership_permission where home_membership_id between 994001 and 994005;
    delete from audit_log where home_id in (994001, 994002);
    delete from home_member where home_id in (994001, 994002);
    delete from home_membership where home_id in (994001, 994002);
    update app_user set default_home_id = null where id between 994001 and 994005;
    delete from home where id in (994001, 994002);
    delete from app_user where id between 994001 and 994005;
    delete from auth.users where id::text like '00000000-0000-4000-8000-0000000e000_';
end $$;

create function pg_temp.fails(p_label text, p_sql text, p_state text, p_msg text) returns void
language plpgsql as $$
begin
    execute p_sql;
    raise exception 'shopping %: no falló: %', p_label, p_sql;
exception when others then
    if sqlstate <> p_state or sqlerrm <> p_msg then
        raise exception 'shopping %: % % (esperado % %)', p_label, sqlstate, sqlerrm, p_state, p_msg;
    end if;
end $$;

create function pg_temp.as_user(p_n int, p_home bigint default null) returns void
language plpgsql as $$
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000e000' || p_n, true);
    perform set_config('request.headers',
                       case when p_home is null then '' else json_build_object('x-home-id', p_home::text)::text end,
                       true);
end $$;

create function pg_temp.plan_id(p_week date, p_home bigint default 994001) returns bigint
language sql as $$
    select id from meal_plan where home_id = p_home and week_start = p_week and status <> 'archived'
$$;
create function pg_temp.rev(p_week date, p_home bigint default 994001) returns integer
language sql as $$
    select revision from meal_plan where home_id = p_home and week_start = p_week and status <> 'archived'
$$;
create function pg_temp.food_id(p_name text) returns bigint
language sql as $$ select id from food where name = p_name $$;
create function pg_temp.recipe_id(p_name text) returns bigint
language sql as $$ select id from recipe where name = p_name $$;
-- cantidad de la línea (label, unit) en un json {items:[…]} (preview) o null si no está
create function pg_temp.pv(p_json json, p_label text, p_unit text) returns numeric
language sql as $$
    select (e->>'quantity')::numeric from json_array_elements(p_json->'items') e
    where e->>'label' = p_label and e->>'unit' = p_unit
$$;
-- artículo de la Compra de H por etiqueta (y unidad opcional)
create function pg_temp.si(p_label text, p_unit text default null) returns shopping_item
language sql as $$
    select s from shopping_item s where s.home_id = 994001 and s.label = p_label
        and (p_unit is null or s.unit = p_unit) order by s.id limit 1
$$;
create function pg_temp.n_items(p_home bigint default 994001) returns integer
language sql as $$ select count(*)::integer from shopping_item where home_id = p_home $$;

select pg_temp.clean();

-- ── Fixture ──
set session_replication_role = replica;
insert into auth.users (id, email, raw_user_meta_data) values
    ('00000000-0000-4000-8000-0000000e0001', 'sh-a@check.homita.example', '{"name":"SH-A"}'),
    ('00000000-0000-4000-8000-0000000e0002', 'sh-b@check.homita.example', '{"name":"SH-B"}'),
    ('00000000-0000-4000-8000-0000000e0003', 'sh-c@check.homita.example', '{"name":"SH-C"}'),
    ('00000000-0000-4000-8000-0000000e0004', 'sh-d@check.homita.example', '{"name":"SH-D"}'),
    ('00000000-0000-4000-8000-0000000e0005', 'sh-y@check.homita.example', '{"name":"SH-Y"}');
insert into app_user (id, auth_uid, name, email) values
    (994001, '00000000-0000-4000-8000-0000000e0001', 'SH-A', 'sh-a@check.homita.example'),
    (994002, '00000000-0000-4000-8000-0000000e0002', 'SH-B', 'sh-b@check.homita.example'),
    (994003, '00000000-0000-4000-8000-0000000e0003', 'SH-C', 'sh-c@check.homita.example'),
    (994004, '00000000-0000-4000-8000-0000000e0004', 'SH-D', 'sh-d@check.homita.example'),
    (994005, '00000000-0000-4000-8000-0000000e0005', 'SH-Y', 'sh-y@check.homita.example');
set session_replication_role = default;

begin;
insert into home (id, name, status, is_personal, created_by) values
    (994001, 'SH-Hogar H', 'active', false, 994001),
    (994002, 'SH-Hogar G', 'active', false, 994005);
insert into home_membership (id, home_id, app_user_id, role) values
    (994001, 994001, 994001, 'admin'),
    (994002, 994001, 994002, 'member'),
    (994003, 994001, 994003, 'member'),
    (994004, 994001, 994004, 'member'),
    (994005, 994002, 994005, 'admin');
insert into home_member (id, home_id, kind, name, app_user_id) values
    (994001, 994001, 'adult', 'SH-A', 994001),
    (994002, 994001, 'adult', 'SH-B', 994002),
    (994003, 994001, 'child', 'SH-C', 994003),
    (994004, 994001, 'guest', 'SH-D', 994004),
    (994006, 994001, 'child', 'SH-Peque', null),
    (994008, 994002, 'adult', 'SH-Y', 994005);
update app_user set default_home_id = 994001 where id between 994001 and 994004;
update app_user set default_home_id = 994002 where id = 994005;
select fn_seed_kind_permissions(994002, 'adult');
select fn_seed_kind_permissions(994003, 'child');
select fn_seed_kind_permissions(994004, 'guest');
commit;

-- Recetas y menú de la semana W1 (como A). Hecho en un DO propio para que SH1 lo lea ya confirmado.
do $$
declare
    v_r1 json;
    v_r2 json;
begin
    perform pg_temp.as_user(1);
    perform create_food('ZZSH Harina', 'cereales', '[]'::jsonb, 'g', null);
    perform create_food('ZZSH Leche', 'lacteos', '[]'::jsonb, 'ml', null);
    perform create_food('ZZSH Huevo', 'huevos', '[]'::jsonb, 'ud', 60);
    perform create_food('ZZSH Tomate', 'verdura', '[]'::jsonb, 'ud', null);
    perform create_food('ZZSH Patata', 'verdura', '[]'::jsonb, 'kg', null);
    perform create_food('ZZSH Arroz', 'cereales', '[]'::jsonb, 'g', null);
    v_r1 := create_recipe('ZZSH R1', 2, 30, '["lunch"]'::jsonb, '["Paso 1"]'::jsonb, jsonb_build_array(
        jsonb_build_object('food_id', pg_temp.food_id('ZZSH Harina'), 'quantity', 300, 'unit', 'g'),
        jsonb_build_object('food_id', pg_temp.food_id('ZZSH Leche'), 'quantity', 250, 'unit', 'ml'),
        jsonb_build_object('food_id', pg_temp.food_id('ZZSH Huevo'), 'quantity', 2, 'unit', 'ud'),
        jsonb_build_object('food_id', pg_temp.food_id('ZZSH Tomate'), 'quantity', 3, 'unit', 'ud'),
        jsonb_build_object('food_id', pg_temp.food_id('ZZSH Patata'), 'quantity', 2.3, 'unit', 'kg'),
        jsonb_build_object('label', 'ZZSH Vinagre', 'quantity', 1, 'unit', 'cda'),
        jsonb_build_object('label', 'sal', 'quantity', 1, 'unit', 'pizca'),
        jsonb_build_object('label', 'ZZSH Perejil', 'unit', 'al gusto'),
        jsonb_build_object('label', 'ZZSH Opcional', 'quantity', 100, 'unit', 'g'),
        jsonb_build_object('label', 'Aceite de oliva', 'quantity', 30, 'unit', 'ml')));
    v_r2 := create_recipe('ZZSH R2', 4, 45, '["dinner"]'::jsonb, '["Paso 1"]'::jsonb, jsonb_build_array(
        jsonb_build_object('food_id', pg_temp.food_id('ZZSH Harina'), 'quantity', 0.5, 'unit', 'kg'),
        jsonb_build_object('food_id', pg_temp.food_id('ZZSH Leche'), 'quantity', 1, 'unit', 'l'),
        jsonb_build_object('food_id', pg_temp.food_id('ZZSH Huevo'), 'quantity', 200, 'unit', 'g'),
        jsonb_build_object('food_id', pg_temp.food_id('ZZSH Tomate'), 'quantity', 1, 'unit', 'ud'),
        jsonb_build_object('food_id', pg_temp.food_id('ZZSH Patata'), 'quantity', 1.11, 'unit', 'kg'),
        jsonb_build_object('food_id', pg_temp.food_id('ZZSH Arroz'), 'quantity', 333, 'unit', 'g'),
        jsonb_build_object('label', 'ZZSH Vinagre', 'quantity', 1, 'unit', 'cdta'),
        jsonb_build_object('label', 'agua', 'quantity', 200, 'unit', 'ml')));
    update recipe_ingredient set optional = true where label = 'ZZSH Opcional';
    perform upsert_meal_plan_items('2030-01-07', 0, jsonb_build_array(
        jsonb_build_object('day', '2030-01-07', 'slot', 'lunch', 'kind', 'recipe',
            'recipe_id', (v_r1->>'id')::bigint, 'members', jsonb_build_array(994001, 994002, 994003, 994006)),
        jsonb_build_object('day', '2030-01-08', 'slot', 'dinner', 'kind', 'recipe',
            'recipe_id', (v_r2->>'id')::bigint, 'members', jsonb_build_array(994001, 994006)),
        jsonb_build_object('day', '2030-01-09', 'slot', 'lunch', 'kind', 'free_text', 'title', 'ZZSH Pizza')));
end $$;

-- ── SH1: suma, conversiones, redondeo y exclusiones ──
do $$
declare
    v json;
begin
    perform pg_temp.as_user(1);
    v := preview_meal_shopping(pg_temp.plan_id('2030-01-07'));
    if json_array_length(v->'items') <> 8 then
        raise exception 'shopping SH1: % líneas (esperado 8): %', json_array_length(v->'items'), v;
    end if;
    -- kg + g: 600 + 250 = 850 g
    if pg_temp.pv(v, 'ZZSH Harina', 'g') is distinct from 850 then
        raise exception 'shopping SH1: harina %', pg_temp.pv(v, 'ZZSH Harina', 'g');
    end if;
    -- ml + l: 500 + 500 = 1000 ml → 1,00 l
    if pg_temp.pv(v, 'ZZSH Leche', 'l') is distinct from 1.00 or pg_temp.pv(v, 'ZZSH Leche', 'ml') is not null then
        raise exception 'shopping SH1: leche %', v;
    end if;
    -- ud con grams_per_unit: 4 ud × 60 g = 240 g, más 100 g sueltos = 340 g (el resto de la agregación es g)
    if pg_temp.pv(v, 'ZZSH Huevo', 'g') is distinct from 340 or pg_temp.pv(v, 'ZZSH Huevo', 'ud') is not null then
        raise exception 'shopping SH1: huevo %', v;
    end if;
    -- ud sin grams_per_unit: 6 + 0,5 → 7 ud (entero hacia arriba)
    if pg_temp.pv(v, 'ZZSH Tomate', 'ud') is distinct from 7 then
        raise exception 'shopping SH1: tomate %', pg_temp.pv(v, 'ZZSH Tomate', 'ud');
    end if;
    -- kg con 2 decimales hacia arriba: 5155 g → 5,16 kg
    if pg_temp.pv(v, 'ZZSH Patata', 'kg') is distinct from 5.16 then
        raise exception 'shopping SH1: patata %', pg_temp.pv(v, 'ZZSH Patata', 'kg');
    end if;
    -- g a múltiplo de 10 hacia arriba: 166,5 → 170 g
    if pg_temp.pv(v, 'ZZSH Arroz', 'g') is distinct from 170 then
        raise exception 'shopping SH1: arroz %', pg_temp.pv(v, 'ZZSH Arroz', 'g');
    end if;
    -- cda y cdta en líneas propias, sin sumarse con g/ml ni entre sí
    if pg_temp.pv(v, 'ZZSH Vinagre', 'cda') is distinct from 2.00 or pg_temp.pv(v, 'ZZSH Vinagre', 'cdta') is distinct from 0.50 then
        raise exception 'shopping SH1: vinagre %', v;
    end if;
    -- fuera: opcional, «al gusto», despensa básica (sal, aceite de oliva, agua) y el texto libre
    if exists (select 1 from json_array_elements(v->'items') e
               where e->>'label' in ('ZZSH Opcional', 'ZZSH Perejil', 'sal', 'Aceite de oliva', 'agua', 'ZZSH Pizza')) then
        raise exception 'shopping SH1: entró un ingrediente excluido: %', v;
    end if;
    -- sources: los dos platos de la harina, con su plan_item_id y la cantidad base
    if json_array_length((select e->'sources' from json_array_elements(v->'items') e where e->>'label' = 'ZZSH Harina')) <> 2
       or json_array_length((select e->'sources' from json_array_elements(v->'items') e where e->>'label' = 'ZZSH Arroz')) <> 1 then
        raise exception 'shopping SH1: sources %', v;
    end if;
    if (select e->'sources'->0->>'name' from json_array_elements(v->'items') e where e->>'label' = 'ZZSH Arroz') <> 'ZZSH R2' then
        raise exception 'shopping SH1: nombre del plato en sources';
    end if;
    -- solo lectura: no creó nada
    if pg_temp.n_items() <> 0 then
        raise exception 'shopping SH1: el preview escribió';
    end if;
    raise notice 'ok SH1: suma con conversiones, factor comensales/servings, redondeo y exclusiones (8 líneas)';
end $$;

-- ── SH2: draft sin compra, aceptar genera, segunda sync = {0,0,0} ──
do $$
declare
    v_plan bigint := pg_temp.plan_id('2030-01-07');
    v json;
begin
    perform pg_temp.as_user(1);
    v := sync_meal_shopping(v_plan);
    if (v->>'added')::int <> 0 or (v->>'updated')::int <> 0 or (v->>'removed')::int <> 0 or pg_temp.n_items() <> 0 then
        raise exception 'shopping SH2: un plan en draft sin compra generó algo: %', v;
    end if;
    v := accept_meal_plan(v_plan, pg_temp.rev('2030-01-07'));
    if v->>'status' <> 'accepted' or (v->'shopping_sync'->>'added')::int <> 8 or (v->'shopping_sync'->>'updated')::int <> 0
       or (v->'shopping_sync'->>'removed')::int <> 0 then
        raise exception 'shopping SH2: accept → %', v;
    end if;
    if pg_temp.n_items() <> 8
       or exists (select 1 from shopping_item where home_id = 994001 and (origin <> 'menu' or state <> 'pending'
                  or plan_id <> v_plan or agg_key is null)) then
        raise exception 'shopping SH2: la compra generada no es la esperada';
    end if;
    if (select shopping_revision from meal_plan where id = v_plan) <> 1 then
        raise exception 'shopping SH2: shopping_revision tras aceptar = %', (select shopping_revision from meal_plan where id = v_plan);
    end if;
    v := sync_meal_shopping(v_plan);
    if (v->>'added')::int <> 0 or (v->>'updated')::int <> 0 or (v->>'removed')::int <> 0 then
        raise exception 'shopping SH2: segunda sync no es {0,0,0}: %', v;
    end if;
    if (select shopping_revision from meal_plan where id = v_plan) <> 1 or (list_shopping()->>'revision')::int <> 1 then
        raise exception 'shopping SH2: la sync sin cambios subió la revisión';
    end if;
    if (pg_temp.si('ZZSH Harina')).quantity <> 850 or (pg_temp.si('ZZSH Leche')).unit <> 'l'
       or (pg_temp.si('ZZSH Huevo')).section <> 'huevos' then
        raise exception 'shopping SH2: cantidades o secciones de la compra';
    end if;
    raise notice 'ok SH2: draft sin compra no genera; aceptar crea 8 líneas; segunda sync {0,0,0} y revisión estable';
end $$;

-- ── SH3: client_request_id ──
do $$
declare
    v_plan bigint := pg_temp.plan_id('2030-01-07');
    c1 uuid := '00000000-0000-4000-8000-00000000e301';
    c2 uuid := '00000000-0000-4000-8000-00000000e302';
    c3 uuid := '00000000-0000-4000-8000-00000000e303';
    v1 json;
    v2 json;
    i1 json;
    i2 json;
begin
    perform pg_temp.as_user(1);
    -- hueco: se borra Arroz a mano y la sync lo repone una sola vez, también si se reintenta
    delete from shopping_item where home_id = 994001 and label = 'ZZSH Arroz';
    v1 := sync_meal_shopping(v_plan, c1);
    if (v1->>'added')::int <> 1 then
        raise exception 'shopping SH3: la sync no repuso Arroz: %', v1;
    end if;
    v2 := sync_meal_shopping(v_plan, c1);
    if v1::jsonb <> v2::jsonb or (select count(*) from shopping_item where home_id = 994001 and label = 'ZZSH Arroz') <> 1 then
        raise exception 'shopping SH3: el reintento de la sync cambió el resultado: % vs %', v1, v2;
    end if;
    if (select shopping_revision from meal_plan where id = v_plan) <> 2 then
        raise exception 'shopping SH3: el reintento volvió a subir la revisión';
    end if;
    if (select count(*) from client_request where app_user_id = 994001 and kind = 'meal_shopping_sync' and resource_id = v_plan) <> 1 then
        raise exception 'shopping SH3: client_request de la sync';
    end if;
    -- alta idempotente
    i1 := create_shopping_item('ZZSH Pan', 2, 'ud', 'panaderia', null, c2);
    i2 := create_shopping_item('ZZSH Pan', 2, 'ud', 'panaderia', null, c2);
    if (i1->>'id') <> (i2->>'id') or (select count(*) from shopping_item where home_id = 994001 and label = 'ZZSH Pan') <> 1 then
        raise exception 'shopping SH3: el alta no es idempotente: % % ', i1, i2;
    end if;
    -- la misma clave con otro kind → Invalid client_request_id (en los dos sentidos)
    perform pg_temp.fails('SH3 kind alta', format('select sync_meal_shopping(%s, ''%s'')', v_plan, c2), 'P0001', 'Invalid client_request_id');
    perform pg_temp.fails('SH3 kind sync', format('select create_shopping_item(''ZZSH x'', 1, ''ud'', null, null, ''%s'')', c1), 'P0001', 'Invalid client_request_id');
    -- la misma clave con otro plan → Invalid client_request_id
    perform pg_temp.fails('SH3 otro plan', format('select sync_meal_shopping(%s, ''%s'')', v_plan + 100000, c1), 'P0001', 'Invalid client_request_id');
    -- sync nueva sin cambios
    v1 := sync_meal_shopping(v_plan, c3);
    if (v1->>'added')::int + (v1->>'updated')::int + (v1->>'removed')::int <> 0 then
        raise exception 'shopping SH3: sync nueva %', v1;
    end if;
    raise notice 'ok SH3: mismo client_request_id = mismo resultado (sync y alta) y kind cruzado rechazado';
end $$;

-- ── SH4: editar el menú aceptado respeta lo marcado, «ya lo tengo», lo manual y lo editado ──
do $$
declare
    v_plan bigint := pg_temp.plan_id('2030-01-07');
    v_item2 bigint;
    v json;
    v_harina bigint := (pg_temp.si('ZZSH Harina')).id;
    v_tomate bigint := (pg_temp.si('ZZSH Tomate')).id;
    v_patata bigint := (pg_temp.si('ZZSH Patata')).id;
    v_pan bigint := (pg_temp.si('ZZSH Pan')).id;
    v_rev_antes integer;
begin
    perform pg_temp.as_user(1);
    perform set_shopping_item_state(v_harina, 'checked');
    perform set_shopping_item_state(v_tomate, 'skipped');
    perform update_shopping_item_qty(v_patata, 9);
    perform set_shopping_item_state(v_pan, 'checked');
    select i.id into v_item2 from meal_plan_item i where i.plan_id = v_plan and i.recipe_id = pg_temp.recipe_id('ZZSH R2');
    v_rev_antes := (select shopping_revision from meal_plan where id = v_plan);
    -- se quita el plato R2: el plan vuelve a draft, pero la compra refleja la edición
    v := upsert_meal_plan_items('2030-01-07', pg_temp.rev('2030-01-07'), null, array[v_item2]);
    if v->>'status' <> 'draft' then
        raise exception 'shopping SH4: el plan no volvió a draft';
    end if;
    -- intactos
    if (pg_temp.si('ZZSH Harina')).state <> 'checked' or (pg_temp.si('ZZSH Harina')).quantity <> 850
       or (pg_temp.si('ZZSH Tomate')).state <> 'skipped' or (pg_temp.si('ZZSH Tomate')).quantity <> 7
       or (pg_temp.si('ZZSH Patata')).quantity <> 9 or not (pg_temp.si('ZZSH Patata')).qty_overridden
       or (pg_temp.si('ZZSH Patata')).unit <> 'kg'
       or (pg_temp.si('ZZSH Pan')).state <> 'checked' or (pg_temp.si('ZZSH Pan')).origin <> 'manual' then
        raise exception 'shopping SH4: se tocó algo marcado, «ya lo tengo», editado o manual';
    end if;
    -- reconciliado: Leche pasa de 1 l a 500 ml; Huevo en g y Arroz y Vinagre cdta desaparecen; Huevo en ud entra
    if (pg_temp.si('ZZSH Leche')).quantity <> 500 or (pg_temp.si('ZZSH Leche')).unit <> 'ml'
       or (pg_temp.si('ZZSH Arroz')).id is not null
       or (pg_temp.si('ZZSH Vinagre', 'cdta')).id is not null
       or (pg_temp.si('ZZSH Huevo', 'g')).id is not null
       or (pg_temp.si('ZZSH Huevo', 'ud')).quantity is distinct from 4
       or (pg_temp.si('ZZSH Vinagre', 'cda')).quantity <> 2 then
        raise exception 'shopping SH4: la compra no se reconcilió con el menú editado';
    end if;
    if (select shopping_revision from meal_plan where id = v_plan) <> v_rev_antes + 1 then
        raise exception 'shopping SH4: la revisión no subió una vez';
    end if;
    if pg_temp.n_items() <> 7 then
        raise exception 'shopping SH4: % artículos (esperado 7)', pg_temp.n_items();
    end if;
    -- plan en draft con compra previa: la sync explícita ya no tiene nada que hacer
    v := sync_meal_shopping(v_plan);
    if (v->>'added')::int + (v->>'updated')::int + (v->>'removed')::int <> 0 then
        raise exception 'shopping SH4: sync tras la edición %', v;
    end if;
    raise notice 'ok SH4: editar el menú aceptado reconcilia (+1 ~1 -3) sin tocar checked, skipped, manual ni cantidad editada';
end $$;

-- ── SH5: volver a aceptar y archivar ──
do $$
declare
    v_plan bigint := pg_temp.plan_id('2030-01-07');
    v json;
    v_n integer;
begin
    perform pg_temp.as_user(1);
    v := accept_meal_plan(v_plan, pg_temp.rev('2030-01-07'));
    if v->>'status' <> 'accepted' or (v->'shopping_sync'->>'added')::int + (v->'shopping_sync'->>'updated')::int
       + (v->'shopping_sync'->>'removed')::int <> 0 then
        raise exception 'shopping SH5: re-aceptar → %', v;
    end if;
    v_n := pg_temp.n_items();
    perform archive_meal_plan(v_plan);
    if pg_temp.n_items() <> v_n then
        raise exception 'shopping SH5: archivar el plan tocó la compra';
    end if;
    perform pg_temp.fails('SH5 sync archivado', format('select sync_meal_shopping(%s)', v_plan), 'P0001', 'Invalid meal plan');
    if json_array_length(list_shopping()->'items') <> v_n then
        raise exception 'shopping SH5: list_shopping tras archivar';
    end if;
    raise notice 'ok SH5: re-aceptar reconcilia con {0,0,0}; archivar no borra la compra y no se sincroniza';
end $$;

-- ── SH6: permisos ──
do $$
declare
    v_item bigint := (pg_temp.si('ZZSH Leche')).id;
    v json;
    v_plan bigint := (select id from meal_plan where home_id = 994001 limit 1);
begin
    -- niño: lee, marca, «ya lo tengo», desmarca y añade
    perform pg_temp.as_user(3);
    if json_array_length(list_shopping()->'items') < 1 then
        raise exception 'shopping SH6: el niño no lee la compra';
    end if;
    v := set_shopping_item_state(v_item, 'checked');
    if v->>'state' <> 'checked' or v->>'checked_at' is null or (v->>'checked_by')::bigint <> 994003 then
        raise exception 'shopping SH6: niño marca %', v;
    end if;
    v := set_shopping_item_state(v_item, 'skipped');
    if v->>'state' <> 'skipped' then
        raise exception 'shopping SH6: niño «ya lo tengo» %', v;
    end if;
    v := set_shopping_item_state(v_item, 'pending');
    if v->>'state' <> 'pending' or v->>'checked_at' is not null or v->>'checked_by' is not null then
        raise exception 'shopping SH6: niño desmarca %', v;
    end if;
    v := create_shopping_item('ZZSH Del niño', 1, 'ud', null, null, null);
    if v->>'origin' <> 'manual' or v->>'section' <> 'otros' then
        raise exception 'shopping SH6: alta del niño %', v;
    end if;
    perform pg_temp.fails('SH6 niño no acepta', format('select accept_meal_plan(%s, 0)', v_plan), '42501', 'Not Allowed');
    -- invitado: sin menu.view ni menu.shopping.edit → Not Allowed en todo
    perform pg_temp.as_user(4);
    perform pg_temp.fails('SH6 invitado lista', 'select list_shopping()', '42501', 'Not Allowed');
    perform pg_temp.fails('SH6 invitado preview', format('select preview_meal_shopping(%s)', v_plan), '42501', 'Not Allowed');
    perform pg_temp.fails('SH6 invitado marca', format('select set_shopping_item_state(%s, ''checked'')', v_item), '42501', 'Not Allowed');
    perform pg_temp.fails('SH6 invitado alta', 'select create_shopping_item(''ZZSH nope'', 1, ''ud'', null, null, null)', '42501', 'Not Allowed');
    perform pg_temp.fails('SH6 invitado cantidad', format('select update_shopping_item_qty(%s, 3)', v_item), '42501', 'Not Allowed');
    perform pg_temp.fails('SH6 invitado borra', format('select delete_shopping_item(%s)', v_item), '42501', 'Not Allowed');
    perform pg_temp.fails('SH6 invitado vacía', 'select clear_checked_shopping()', '42501', 'Not Allowed');
    perform pg_temp.fails('SH6 invitado sync', format('select sync_meal_shopping(%s)', v_plan), '42501', 'Not Allowed');
    if (select state from shopping_item where id = v_item) <> 'pending' then
        raise exception 'shopping SH6: el invitado cambió algo';
    end if;
    raise notice 'ok SH6: el niño lee, marca, «ya lo tengo», desmarca y añade; el invitado recibe Not Allowed en todo';
end $$;

-- ── SH7: RLS y cross-tenant ──
do $$
declare
    v_item bigint := (pg_temp.si('ZZSH Leche')).id;
    v_plan bigint := (select id from meal_plan where home_id = 994001 limit 1);
begin
    -- Y en su propio hogar: la compra está vacía
    perform pg_temp.as_user(5);
    if json_array_length(list_shopping()->'items') <> 0 or (list_shopping()->>'revision')::int <> 0 then
        raise exception 'shopping SH7: Y ve la compra de H en su hogar';
    end if;
    -- ids de H usados desde el hogar de Y
    perform pg_temp.fails('SH7 marca ajena', format('select set_shopping_item_state(%s, ''checked'')', v_item), 'P0002', 'Not Found');
    perform pg_temp.fails('SH7 cantidad ajena', format('select update_shopping_item_qty(%s, 3)', v_item), 'P0002', 'Not Found');
    perform pg_temp.fails('SH7 borrado ajeno', format('select delete_shopping_item(%s)', v_item), 'P0002', 'Not Found');
    perform pg_temp.fails('SH7 preview ajeno', format('select preview_meal_shopping(%s)', v_plan), 'P0002', 'Not Found');
    perform pg_temp.fails('SH7 sync ajena', format('select sync_meal_shopping(%s)', v_plan), 'P0002', 'Not Found');
    -- X-Home-Id de H sin ser miembro
    perform pg_temp.as_user(5, 994001);
    perform pg_temp.fails('SH7 lista con cabecera', 'select list_shopping()', 'P0002', 'Not Found');
    perform pg_temp.fails('SH7 alta con cabecera', 'select create_shopping_item(''ZZSH x'', 1, ''ud'', null, null, null)', 'P0002', 'Not Found');
    perform pg_temp.fails('SH7 vaciar con cabecera', 'select clear_checked_shopping()', 'P0002', 'Not Found');
    perform pg_temp.fails('SH7 preview con cabecera', format('select preview_meal_shopping(%s)', v_plan), 'P0002', 'Not Found');
    -- tablas: Y no lee nada de H y nadie escribe directo
    perform pg_temp.as_user(5);
    set local role authenticated;
    if exists (select 1 from shopping_item where home_id = 994001) then
        raise exception 'shopping SH7: Y lee shopping_item de H por tabla';
    end if;
    begin
        delete from shopping_item;
        raise exception 'shopping SH7: authenticated borró directo';
    exception when insufficient_privilege then null;
    end;
    begin
        insert into shopping_item (home_id, label) values (994002, 'ZZSH directo');
        raise exception 'shopping SH7: authenticated insertó directo';
    exception when insufficient_privilege then null;
    end;
    begin
        update shopping_item set state = 'checked' where home_id = 994001;
        raise exception 'shopping SH7: authenticated actualizó directo';
    exception when insufficient_privilege then null;
    end;
    reset role;
    -- B (adulto de H) sí lee por tabla
    perform pg_temp.as_user(2);
    set local role authenticated;
    if not exists (select 1 from shopping_item where home_id = 994001) then
        raise exception 'shopping SH7: B no lee la compra de su hogar';
    end if;
    reset role;
    raise notice 'ok SH7: Y no lee ni escribe la compra de H (RPC → Not Found, tabla vacía y sin escritura directa)';
end $$;

-- ── SH8: vaciar comprados y borrar ──
do $$
declare
    v_p2 bigint;
    v json;
    v_h2 bigint;
    v_t2 bigint;
    v_l2 bigint;
    v_pan bigint := (pg_temp.si('ZZSH Pan')).id;
    v_ninio bigint := (pg_temp.si('ZZSH Del niño')).id;
begin
    perform pg_temp.as_user(1);
    perform upsert_meal_plan_items('2030-01-14', 0, jsonb_build_array(jsonb_build_object(
        'day', '2030-01-14', 'slot', 'lunch', 'kind', 'recipe', 'recipe_id', pg_temp.recipe_id('ZZSH R1'),
        'members', jsonb_build_array(994001, 994002, 994003, 994006))));
    v_p2 := pg_temp.plan_id('2030-01-14');
    v := accept_meal_plan(v_p2, pg_temp.rev('2030-01-14'));
    if (v->'shopping_sync'->>'added')::int <> 6 then
        raise exception 'shopping SH8: la semana 2 generó % líneas (esperado 6): %', v->'shopping_sync'->>'added', v;
    end if;
    select id into v_h2 from shopping_item where plan_id = v_p2 and label = 'ZZSH Harina';
    select id into v_t2 from shopping_item where plan_id = v_p2 and label = 'ZZSH Tomate';
    select id into v_l2 from shopping_item where plan_id = v_p2 and label = 'ZZSH Leche';
    perform set_shopping_item_state(v_h2, 'checked');
    perform set_shopping_item_state(v_t2, 'skipped');
    -- comprados vigentes: Harina de la semana 1, Harina de la semana 2 y el Pan manual → 3
    v := clear_checked_shopping();
    if (v->>'cleared')::int <> 3 then
        raise exception 'shopping SH8: clear_checked_shopping devolvió %', v;
    end if;
    if exists (select 1 from shopping_item where id = v_pan) then
        raise exception 'shopping SH8: el comprado manual no se borró';
    end if;
    if not exists (select 1 from shopping_item where id = v_h2 and cleared and state = 'checked') then
        raise exception 'shopping SH8: el comprado de origen menu no quedó oculto';
    end if;
    if exists (select 1 from json_array_elements(list_shopping()->'items') e where e->>'state' = 'checked')
       or not exists (select 1 from json_array_elements(list_shopping()->'items') e where (e->>'id')::bigint = v_t2 and e->>'state' = 'skipped') then
        raise exception 'shopping SH8: list_shopping tras vaciar (los skipped deben seguir)';
    end if;
    -- la sync no vuelve a crear lo oculto
    v := sync_meal_shopping(v_p2);
    if (v->>'added')::int + (v->>'updated')::int + (v->>'removed')::int <> 0
       or (select count(*) from shopping_item where plan_id = v_p2 and label = 'ZZSH Harina') <> 1 then
        raise exception 'shopping SH8: la sync recreó lo vaciado: %', v;
    end if;
    -- borrar: manual de verdad; menu pendiente → oculto y «ya lo tengo»
    perform delete_shopping_item(v_ninio);
    if exists (select 1 from shopping_item where id = v_ninio) then
        raise exception 'shopping SH8: el manual no se borró';
    end if;
    v := delete_shopping_item(v_l2);
    if not exists (select 1 from shopping_item where id = v_l2 and cleared and state = 'skipped') then
        raise exception 'shopping SH8: el pendiente de origen menu no quedó oculto';
    end if;
    v := sync_meal_shopping(v_p2);
    if (v->>'added')::int + (v->>'updated')::int + (v->>'removed')::int <> 0
       or exists (select 1 from json_array_elements(list_shopping()->'items') e where (e->>'id')::bigint = v_l2) then
        raise exception 'shopping SH8: la sync recreó lo borrado: %', v;
    end if;
    -- un cambio de estado sobre un artículo oculto (replay offline) no lo hace reaparecer
    v := set_shopping_item_state(v_l2, 'checked');
    if not exists (select 1 from shopping_item where id = v_l2 and cleared and state = 'skipped')
       or exists (select 1 from json_array_elements(list_shopping()->'items') e where (e->>'id')::bigint = v_l2) then
        raise exception 'shopping SH8: un artículo oculto reapareció por set_shopping_item_state: %', v;
    end if;
    perform pg_temp.fails('SH8 borrar dos veces', format('select delete_shopping_item(%s)', v_ninio), 'P0002', 'Not Found');
    -- validación
    perform pg_temp.fails('SH8 estado', format('select set_shopping_item_state(%s, ''hecho'')', v_t2), 'P0001', 'Invalid shopping item');
    perform pg_temp.fails('SH8 estado nulo', format('select set_shopping_item_state(%s, null)', v_t2), 'P0001', 'Invalid shopping item');
    perform pg_temp.fails('SH8 cantidad negativa', format('select update_shopping_item_qty(%s, -1)', v_t2), 'P0001', 'Invalid shopping item');
    perform pg_temp.fails('SH8 cantidad nula', format('select update_shopping_item_qty(%s, null)', v_t2), 'P0001', 'Invalid shopping item');
    perform pg_temp.fails('SH8 unidad', format('select update_shopping_item_qty(%s, 1, ''taza'')', v_t2), 'P0001', 'Invalid shopping item');
    perform pg_temp.fails('SH8 alta sin nombre', 'select create_shopping_item(''  '', 1, ''ud'', null, null, null)', 'P0001', 'Invalid shopping item');
    perform pg_temp.fails('SH8 alta unidad', 'select create_shopping_item(''ZZSH x'', 1, ''taza'', null, null, null)', 'P0001', 'Invalid shopping item');
    perform pg_temp.fails('SH8 alta sección', 'select create_shopping_item(''ZZSH x'', 1, ''ud'', ''inventada'', null, null)', 'P0001', 'Invalid shopping item');
    perform pg_temp.fails('SH8 alta alimento', 'select create_shopping_item(''ZZSH x'', 1, ''ud'', null, 999999999, null)', 'P0001', 'Invalid shopping item');
    perform pg_temp.fails('SH8 alta cantidad', 'select create_shopping_item(''ZZSH x'', -1, ''ud'', null, null, null)', 'P0001', 'Invalid shopping item');
    -- alta con alimento: toma nombre y sección del catálogo
    v := create_shopping_item(null, 3, 'g', null, pg_temp.food_id('ZZSH Arroz'), null);
    if v->>'label' <> 'ZZSH Arroz' or v->>'section' <> 'cereales' or (v->>'food_id')::bigint <> pg_temp.food_id('ZZSH Arroz') then
        raise exception 'shopping SH8: alta con alimento %', v;
    end if;
    raise notice 'ok SH8: vaciar y borrar (manuales fuera; los de menu ocultos sin volver) y validación 400';
end $$;

-- ── SH9: client_request admite los kinds nuevos ──
do $$
begin
    insert into client_request (app_user_id, client_request_id, kind, resource_id)
    values (994001, '00000000-0000-4000-8000-00000000e901', 'shopping_item', 1),
           (994001, '00000000-0000-4000-8000-00000000e902', 'meal_shopping_sync', 1);
    begin
        insert into client_request (app_user_id, client_request_id, kind, resource_id)
        values (994001, '00000000-0000-4000-8000-00000000e903', 'bogus', 1);
        raise exception 'shopping SH9: kind inválido aceptado';
    exception when check_violation then null;
    end;
    begin
        insert into client_request (app_user_id, client_request_id, kind, resource_id)
        values (994001, '00000000-0000-4000-8000-00000000e904', 'shopping_item', null);
        raise exception 'shopping SH9: resource_id nulo aceptado';
    exception when not_null_violation then null;
    end;
    delete from client_request where client_request_id::text like '00000000-0000-4000-8000-00000000e90_';
    if not exists (select 1 from pg_constraint where conrelid = 'public.client_request'::regclass
                   and conname = 'client_request_kind_check') then
        raise exception 'shopping SH9: falta client_request_kind_check';
    end if;
    raise notice 'ok SH9: client_request acepta shopping_item y meal_shopping_sync y rechaza un kind inválido';
end $$;

-- ── SH10: grants, índices y checks ──
do $$
declare
    f text;
begin
    if has_table_privilege('authenticated', 'public.shopping_item', 'insert,update,delete')
       or not has_table_privilege('authenticated', 'public.shopping_item', 'select')
       or has_table_privilege('anon', 'public.shopping_item', 'select')
       or (select count(*) from pg_policy where polrelid = 'public.shopping_item'::regclass and polcmd = 'r') <> 1
       or (select count(*) from pg_policy where polrelid = 'public.shopping_item'::regclass) <> 1 then
        raise exception 'shopping SH10: RLS o privilegios de shopping_item incorrectos';
    end if;
    foreach f in array array['preview_meal_shopping(bigint)', 'sync_meal_shopping(bigint,uuid)', 'list_shopping()',
        'create_shopping_item(text,numeric,text,text,bigint,uuid)', 'set_shopping_item_state(bigint,text)',
        'update_shopping_item_qty(bigint,numeric,text)', 'delete_shopping_item(bigint)', 'clear_checked_shopping()'] loop
        if not has_function_privilege('authenticated', f, 'execute') or has_function_privilege('anon', f, 'execute') then
            raise exception 'shopping SH10: grants de %', f;
        end if;
    end loop;
    foreach f in array array['fn_meal_shopping_sync(bigint,bigint)', 'fn_meal_shopping_calc(bigint)',
        'fn_meal_shopping_round(numeric,text)', 'fn_meal_pantry_basic_names()', 'fn_shopping_item_json(bigint)'] loop
        if has_function_privilege('authenticated', f, 'execute') or has_function_privilege('anon', f, 'execute') then
            raise exception 'shopping SH10: el helper % es ejecutable', f;
        end if;
    end loop;
    if not exists (select 1 from pg_indexes where indexname = 'shopping_item_plan_agg_uq' and indexdef like '%WHERE%origin%') then
        raise exception 'shopping SH10: falta el índice único parcial (plan_id, agg_key)';
    end if;
    -- un artículo de origen menu exige plan y agg_key
    begin
        insert into shopping_item (home_id, label, origin) values (994001, 'ZZSH sin plan', 'menu');
        raise exception 'shopping SH10: origen menu sin plan aceptado';
    exception when check_violation then null;
    end;
    -- (plan_id, agg_key) único entre los de origen menu
    begin
        insert into shopping_item (home_id, label, origin, plan_id, agg_key)
        select home_id, 'ZZSH dup', 'menu', plan_id, agg_key from shopping_item where origin = 'menu' limit 1;
        raise exception 'shopping SH10: agg_key duplicada aceptada';
    exception when unique_violation then null;
    end;
    raise notice 'ok SH10: grants, RLS, índice único parcial y checks de coherencia';
end $$;

-- ── SH11: limpieza ──
select pg_temp.clean();
do $$
begin
    if exists (select 1 from app_user where id between 994001 and 994005)
       or exists (select 1 from home where id in (994001, 994002))
       or exists (select 1 from shopping_item where home_id in (994001, 994002) or label like 'ZZSH%')
       or exists (select 1 from client_request where app_user_id between 994001 and 994005)
       or exists (select 1 from food where home_id in (994001, 994002) or name like 'ZZSH%')
       or exists (select 1 from recipe where home_id in (994001, 994002))
       or exists (select 1 from recipe_ingredient where home_id in (994001, 994002))
       or exists (select 1 from meal_plan where home_id in (994001, 994002))
       or exists (select 1 from meal_plan_item where home_id in (994001, 994002))
       or exists (select 1 from meal_plan_item_member where home_id in (994001, 994002)) then
        raise exception 'shopping SH11: quedaron filas scratch';
    end if;
    raise notice 'ok SH11: 0 filas scratch';
end $$;
