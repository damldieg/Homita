-- recetas_precargadas_check.sql — Recetas comunes precargadas (0047_menus_recetas_precargadas.sql).
-- Solo BD local, tras las migraciones 0001–0047 y las dos cargas de supabase/seed/food_es.sql y
-- supabase/seed/recetas_precargadas.sql (ci.sh las hace antes y exige 'INSERT 0 0' en la segunda carga):
--   psql -v ON_ERROR_STOP=1 -f recetas_precargadas_check.sql
-- Cada bloque DO emite 'ok RPx: …' o aborta con 'recetas_precargadas RPx: …'.
--
-- Fixture (ids 994xxx, auth_uid …0d0e01/02): hogar H (994001) con A admin y hogar G (994002) con Y admin.
-- Todo lo creado lleva el prefijo 'ZZRP'.
--
-- RP1 filas comunes: 20 recetas (10 ES + 10 AR) sin duplicar tras dos cargas; con pasos, ingredientes y
--     al menos un ingrediente enlazado al catálogo; los ingredientes también sin hogar.
-- RP2 restricciones: país obligatorio y de dos letras en mayúsculas; (name, country) único entre comunes.
-- RP3 RLS: los hogares leen las recetas comunes y sus ingredientes, no escriben nada directo y no ven
--     lo propio del otro hogar.
-- RP4 RPC: list_recipes y get_recipe incluyen las comunes (con country); update_recipe y delete_recipe
--     sobre una común dan Not Found; la receta propia convive con las comunes.
-- RP5 0 filas scratch al terminar.

\set ON_ERROR_STOP 1
do $$
begin
    if inet_server_addr() is not null and host(inet_server_addr()) not in ('127.0.0.1', '::1') then
        raise exception 'recetas_precargadas_check: solo BD local (socket o loopback); servidor %', host(inet_server_addr());
    end if;
    if to_regclass('public.recipe') is null or not exists (select 1 from information_schema.columns
        where table_schema = 'public' and table_name = 'recipe' and column_name = 'country') then
        raise exception 'recetas_precargadas_check: 0047 no está aplicada (falta recipe.country)';
    end if;
end $$;

create function pg_temp.clean() returns void
language plpgsql as $$
begin
    set local session_replication_role = replica;
    delete from recipe_ingredient where home_id in (994001, 994002) or recipe_id in (select id from recipe where name like 'ZZRP%');
    delete from recipe where home_id in (994001, 994002) or name like 'ZZRP%';
    delete from audit_log where home_id in (994001, 994002);
    delete from membership_permission where home_membership_id between 994001 and 994002;
    delete from home_member where home_id in (994001, 994002);
    delete from home_membership where home_id in (994001, 994002);
    update app_user set default_home_id = null where id between 994001 and 994002;
    delete from home where id in (994001, 994002);
    delete from app_user where id between 994001 and 994002;
    delete from auth.users where id::text like '00000000-0000-4000-8000-0000000d0e0_';
end $$;

create function pg_temp.fails(p_label text, p_sql text, p_state text, p_msg text default null) returns void
language plpgsql as $$
begin
    execute p_sql;
    raise exception 'recetas_precargadas %: no falló: %', p_label, p_sql;
exception when others then
    if sqlstate <> p_state or (p_msg is not null and sqlerrm <> p_msg) then
        raise exception 'recetas_precargadas %: % % (esperado % %)', p_label, sqlstate, sqlerrm, p_state, p_msg;
    end if;
end $$;

create function pg_temp.as_user(p_n int) returns void
language plpgsql as $$
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000d0e0' || p_n, true);
    perform set_config('request.headers', '', true);
end $$;

select pg_temp.clean();

set session_replication_role = replica;
insert into auth.users (id, email, raw_user_meta_data) values
    ('00000000-0000-4000-8000-0000000d0e01', 'rp-a@check.homita.example', '{"name":"RP-A"}'),
    ('00000000-0000-4000-8000-0000000d0e02', 'rp-y@check.homita.example', '{"name":"RP-Y"}');
insert into app_user (id, auth_uid, name, email) values
    (994001, '00000000-0000-4000-8000-0000000d0e01', 'RP-A', 'rp-a@check.homita.example'),
    (994002, '00000000-0000-4000-8000-0000000d0e02', 'RP-Y', 'rp-y@check.homita.example');
set session_replication_role = default;

begin;
insert into home (id, name, status, is_personal, created_by) values
    (994001, 'RP-Hogar H', 'active', false, 994001),
    (994002, 'RP-Hogar G', 'active', false, 994002);
insert into home_membership (id, home_id, app_user_id, role) values
    (994001, 994001, 994001, 'admin'),
    (994002, 994002, 994002, 'admin');
insert into home_member (id, home_id, kind, name, app_user_id) values
    (994001, 994001, 'adult', 'RP-A', 994001),
    (994002, 994002, 'adult', 'RP-Y', 994002);
update app_user set default_home_id = 994001 where id = 994001;
update app_user set default_home_id = 994002 where id = 994002;
commit;

-- ── RP1: filas comunes ──
do $$
begin
    if (select count(*) from recipe where home_id is null) <> 20
       or (select count(distinct (name, country)) from recipe where home_id is null) <> 20 then
        raise exception 'recetas_precargadas RP1: se esperaban 20 recetas comunes distintas, hay % (% distintas)',
            (select count(*) from recipe where home_id is null),
            (select count(distinct (name, country)) from recipe where home_id is null);
    end if;
    if (select count(*) from recipe where home_id is null and country = 'ES') <> 10
       or (select count(*) from recipe where home_id is null and country = 'AR') <> 10 then
        raise exception 'recetas_precargadas RP1: se esperaban 10 recetas ES y 10 AR';
    end if;
    if exists (select 1 from recipe r where r.home_id is null
               and (coalesce(cardinality(r.steps), 0) = 0 or cardinality(r.slots) = 0 or r.minutes is null
                    or not exists (select 1 from recipe_ingredient i where i.recipe_id = r.id))) then
        raise exception 'recetas_precargadas RP1: hay una receta común sin pasos, franjas, tiempo o ingredientes';
    end if;
    if exists (select 1 from recipe_ingredient i join recipe r on r.id = i.recipe_id
               where r.home_id is null and i.home_id is not null) then
        raise exception 'recetas_precargadas RP1: ingredientes de recetas comunes con hogar';
    end if;
    if not exists (select 1 from recipe_ingredient i join recipe r on r.id = i.recipe_id
                   join food f on f.id = i.food_id where r.home_id is null and f.home_id is null) then
        raise exception 'recetas_precargadas RP1: ningún ingrediente común enlaza con el catálogo (¿falta food_es.sql?)';
    end if;
    raise notice 'ok RP1: 20 recetas comunes (10 ES + 10 AR) sin duplicar, con pasos, ingredientes y enlaces al catálogo';
end $$;

-- ── RP2: restricciones ──
do $$
begin
    perform pg_temp.fails('RP2 común sin país', $q$insert into recipe (home_id, name) values (null, 'ZZRP sin país')$q$, '23514');
    perform pg_temp.fails('RP2 país en minúsculas', $q$insert into recipe (home_id, name, country) values (null, 'ZZRP minus', 'es')$q$, '23514');
    perform pg_temp.fails('RP2 país de tres letras', $q$insert into recipe (home_id, name, country) values (null, 'ZZRP tres', 'ESP')$q$, '23514');
    insert into recipe (home_id, name, country) values (null, 'ZZRP Plato', 'ES');
    perform pg_temp.fails('RP2 común duplicada', $q$insert into recipe (home_id, name, country) values (null, 'ZZRP Plato', 'ES')$q$, '23505');
    insert into recipe (home_id, name, country) values (null, 'ZZRP Plato', 'AR');
    delete from recipe where name = 'ZZRP Plato';
    raise notice 'ok RP2: país obligatorio y de dos letras mayúsculas; (name, country) único entre comunes';
end $$;

-- ── RP3: RLS ──
do $$
declare
    v json;
    t text;
begin
    perform pg_temp.as_user(1);
    v := create_recipe('ZZRP Receta H', 2, 10, '["lunch"]'::jsonb, '["Paso"]'::jsonb,
        '[{"label":"sal","unit":"al gusto"}]'::jsonb);
    perform pg_temp.as_user(2);
    set local role authenticated;
    if (select count(*) from recipe where home_id is null) <> 20
       or (select count(*) from recipe_ingredient i join recipe r on r.id = i.recipe_id where r.home_id is null) = 0 then
        raise exception 'recetas_precargadas RP3: el hogar G no lee las recetas comunes y sus ingredientes';
    end if;
    if exists (select 1 from recipe where name = 'ZZRP Receta H') then
        raise exception 'recetas_precargadas RP3: G lee una receta de H';
    end if;
    foreach t in array array['recipe', 'recipe_ingredient'] loop
        begin
            execute format('delete from %I where home_id is null', t);
            raise exception 'recetas_precargadas RP3: authenticated borró directo en %', t;
        exception when insufficient_privilege then null;
        end;
    end loop;
    begin
        insert into recipe (home_id, name, country) values (null, 'ZZRP directo', 'ES');
        raise exception 'recetas_precargadas RP3: authenticated insertó una receta común';
    exception when insufficient_privilege then null;
    end;
    begin
        update recipe set name = 'ZZRP cambiada' where home_id is null;
        raise exception 'recetas_precargadas RP3: authenticated actualizó una receta común';
    exception when insufficient_privilege then null;
    end;
    reset role;
    if has_table_privilege('authenticated', 'public.recipe', 'insert,update,delete')
       or has_table_privilege('authenticated', 'public.recipe_ingredient', 'insert,update,delete')
       or has_table_privilege('anon', 'public.recipe', 'select') then
        raise exception 'recetas_precargadas RP3: privilegios de recipe o recipe_ingredient incorrectos';
    end if;
    if (select count(*) from pg_policy where polrelid in ('public.recipe'::regclass, 'public.recipe_ingredient'::regclass)
        and polcmd <> 'r') <> 0 then
        raise exception 'recetas_precargadas RP3: hay policies de escritura en recipe o recipe_ingredient';
    end if;
    raise notice 'ok RP3: los hogares leen las comunes, no escriben directo y no ven lo propio del otro hogar';
end $$;

-- ── RP4: RPC ──
do $$
declare
    v_common bigint;
    v_list json;
    v_det json;
begin
    select id into v_common from recipe where home_id is null and name = 'Tortilla de patatas' and country = 'ES';
    if v_common is null then
        raise exception 'recetas_precargadas RP4: falta la Tortilla de patatas común';
    end if;
    perform pg_temp.as_user(2);
    v_list := list_recipes();
    if (select count(*) from json_array_elements(v_list) e where e->>'home_id' is null) <> 20
       or exists (select 1 from json_array_elements(v_list) e where e->>'name' = 'ZZRP Receta H') then
        raise exception 'recetas_precargadas RP4: list_recipes de G no devuelve exactamente las 20 comunes';
    end if;
    if (select count(*) from json_array_elements(list_recipes('tortilla')) e where e->>'country' = 'ES') <> 1 then
        raise exception 'recetas_precargadas RP4: la búsqueda no encuentra la tortilla común (con country)';
    end if;
    v_det := get_recipe(v_common);
    if v_det->>'country' <> 'ES' or json_array_length(v_det->'ingredients') < 3 or json_array_length(v_det->'steps') < 3
       or json_array_length(v_det->'allergens') = 0 then
        raise exception 'recetas_precargadas RP4: get_recipe de una común incompleto (country, ingredientes, pasos o alérgenos)';
    end if;
    perform pg_temp.fails('RP4 update común', format($q$select update_recipe(%s, '{"name":"x"}'::jsonb)$q$, v_common), 'P0002', 'Not Found');
    perform pg_temp.fails('RP4 delete común', format($q$select delete_recipe(%s)$q$, v_common), 'P0002', 'Not Found');
    perform pg_temp.as_user(1);
    v_list := list_recipes();
    if json_array_length(v_list) <> 21
       or (select count(*) from json_array_elements(v_list) e where e->>'name' = 'ZZRP Receta H') <> 1 then
        raise exception 'recetas_precargadas RP4: H debe ver sus propias recetas y las 20 comunes';
    end if;
    if (select count(*) from recipe where home_id is null) <> 20 then
        raise exception 'recetas_precargadas RP4: un hogar alteró las recetas comunes';
    end if;
    raise notice 'ok RP4: list_recipes y get_recipe incluyen las comunes; update y delete sobre una común dan Not Found';
end $$;

-- ── RP5: limpieza ──
select pg_temp.clean();
do $$
begin
    if exists (select 1 from recipe where name like 'ZZRP%' or home_id in (994001, 994002)) then
        raise exception 'recetas_precargadas RP5: quedan filas scratch';
    end if;
    raise notice 'ok RP5: 0 filas scratch';
end $$;
