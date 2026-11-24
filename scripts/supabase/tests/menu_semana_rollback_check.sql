-- menu_semana_rollback_check.sql — Ida de la vuelta 0044 → rollback_0044_menus_semana.sql (change
-- menus-semana). Solo BD local, tras el reset 0001–0044. ci.sh sustituye la línea
-- `-- @ROLLBACK:<fichero>@` por scripts/supabase/rollback/<fichero>. Cada bloque emite 'ok RMx: …' o
-- aborta con 'menu_semana_rollback RMx: …'.
--
-- NO va en transacción: el rollback se confirma de verdad. menu_semana_reapply_check.sql (tras
-- reaplicar 0044 y el seed desde ci.sh) comprueba que el esquema vuelve completo.
--
-- RM4 no existen las tablas de menús, sus RPC ni los helpers de 0044.
-- RM5 0043 sigue entera: tablas meal_*, sus RPC y el catálogo 28/47.
-- RM6 rollback_0044 una segunda vez no falla y deja el mismo estado (idempotente).

\set ON_ERROR_STOP 1
do $$
begin
    if inet_server_addr() is not null and host(inet_server_addr()) not in ('127.0.0.1', '::1') then
        raise exception 'menu_semana_rollback_check: solo BD local (socket o loopback); servidor %', host(inet_server_addr());
    end if;
    if to_regclass('public.meal_plan') is null or to_regclass('public.food') is null then
        raise exception 'menu_semana_rollback_check: 0044 no está aplicada (faltan meal_plan o food)';
    end if;
end $$;

create function pg_temp.rm_state() returns text
language plpgsql as $$
begin
    if to_regclass('public.food') is not null or to_regclass('public.recipe') is not null
       or to_regclass('public.recipe_ingredient') is not null or to_regclass('public.meal_plan') is not null
       or to_regclass('public.meal_plan_item') is not null or to_regclass('public.meal_plan_item_member') is not null then
        return 'RM4 siguen existiendo tablas de menús';
    end if;
    if exists (select 1 from pg_proc where pronamespace = 'public'::regnamespace
               and proname in ('search_food', 'create_food', 'update_food', 'delete_food', 'list_recipes', 'get_recipe',
                               'create_recipe', 'update_recipe', 'delete_recipe', 'get_meal_plan',
                               'upsert_meal_plan_items', 'accept_meal_plan', 'archive_meal_plan',
                               'copy_meal_plan_week', 'check_meal_plan', 'get_meals_today',
                               'fn_meal_norm', 'fn_meal_food_allergens_valid', 'fn_meal_food_before',
                               'fn_meal_food_json', 'fn_meal_recipe_json', 'fn_meal_recipe_set_ingredients',
                               'fn_meal_plan_json', 'fn_meal_week_of', 'fn_meal_profile_week_guard')) then
        return 'RM4 siguen existiendo funciones de 0044';
    end if;
    if to_regclass('public.meal_profile') is null or to_regclass('public.meal_profile_member') is null
       or to_regclass('public.meal_schedule') is null or to_regclass('public.meal_slot_setting') is null
       or (select count(*) from pg_proc where pronamespace = 'public'::regnamespace
           and proname in ('get_meal_profile', 'update_meal_profile', 'update_meal_profile_member',
                           'set_meal_schedule', 'set_meal_slot_settings')) <> 5 then
        return 'RM5 el rollback tocó 0043 (tablas o RPC)';
    end if;
    if (select count(*) from permission) <> 28 or (select count(*) from member_kind_default) <> 47 then
        return 'RM5 catálogo de permisos distinto de 28/47';
    end if;
    return null;
end $$;

-- @ROLLBACK:rollback_0044_menus_semana.sql@

do $$
declare
    v_err text := pg_temp.rm_state();
begin
    if v_err is not null then
        raise exception 'menu_semana_rollback %', v_err;
    end if;
    raise notice 'ok RM4: sin tablas ni funciones de 0044';
    raise notice 'ok RM5: 0043 intacta (tablas meal_*, 5 RPC, catálogo 28/47)';
end $$;

-- @ROLLBACK:rollback_0044_menus_semana.sql@

do $$
declare
    v_err text := pg_temp.rm_state();
begin
    if v_err is not null then
        raise exception 'menu_semana_rollback RM6 %', v_err;
    end if;
    raise notice 'ok RM6: segundo rollback sin error y mismo estado';
end $$;
