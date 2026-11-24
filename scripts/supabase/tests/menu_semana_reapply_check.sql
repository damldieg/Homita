-- menu_semana_reapply_check.sql — Tras reaplicar 0044_menus_semana.sql y la semilla
-- supabase/seed/food_es.sql sobre la BD revertida (ci.sh las aplica justo antes). Solo BD local.
-- RA3 existen las 6 tablas, las 16 RPC, los índices únicos parciales y 1 policy SELECT por tabla.
-- RA4 la semilla dejó entre 280 y 320 alimentos comunes con alérgenos válidos, y recargarla es idempotente.

\set ON_ERROR_STOP 1
do $$
begin
    if inet_server_addr() is not null and host(inet_server_addr()) not in ('127.0.0.1', '::1') then
        raise exception 'menu_semana_reapply_check: solo BD local (socket o loopback); servidor %', host(inet_server_addr());
    end if;
end $$;

do $$
declare
    t text;
begin
    foreach t in array array['food', 'recipe', 'recipe_ingredient', 'meal_plan', 'meal_plan_item', 'meal_plan_item_member'] loop
        if to_regclass('public.' || t) is null then
            raise exception 'menu_semana_reapply RA3: falta la tabla %', t;
        end if;
        if (select count(*) from pg_policy where polrelid = ('public.' || t)::regclass and polcmd = 'r') <> 1
           or has_table_privilege('authenticated', 'public.' || t, 'insert,update,delete') then
            raise exception 'menu_semana_reapply RA3: RLS o privilegios de % incorrectos', t;
        end if;
    end loop;
    if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace
        and proname in ('search_food', 'create_food', 'update_food', 'delete_food', 'list_recipes', 'get_recipe',
                        'create_recipe', 'update_recipe', 'delete_recipe', 'get_meal_plan', 'upsert_meal_plan_items',
                        'accept_meal_plan', 'archive_meal_plan', 'copy_meal_plan_week', 'check_meal_plan',
                        'get_meals_today')) <> 16 then
        raise exception 'menu_semana_reapply RA3: faltan RPC';
    end if;
    if not exists (select 1 from pg_indexes where indexname = 'meal_plan_home_week_uq')
       or not exists (select 1 from pg_indexes where indexname = 'food_common_name_uq')
       or not exists (select 1 from pg_indexes where indexname = 'food_home_name_uq') then
        raise exception 'menu_semana_reapply RA3: faltan los índices únicos parciales';
    end if;
    if (select count(*) from permission) <> 28 or (select count(*) from member_kind_default) <> 47 then
        raise exception 'menu_semana_reapply RA3: catálogo de permisos distinto de 28/47';
    end if;
    raise notice 'ok RA3: tablas, 16 RPC, índices parciales y RLS tras reaplicar';
end $$;

do $$
declare
    v_n bigint;
begin
    select count(*) into v_n from food where home_id is null;
    if v_n < 280 or v_n > 320 then
        raise exception 'menu_semana_reapply RA4: % alimentos comunes (esperado entre 280 y 320; ¿falta cargar food_es.sql?)', v_n;
    end if;
    if exists (select 1 from food where home_id is null and not fn_meal_food_allergens_valid(allergens)) then
        raise exception 'menu_semana_reapply RA4: alérgenos inválidos en el catálogo común';
    end if;
    raise notice 'ok RA4: % alimentos comunes cargados por la semilla', v_n;
end $$;
