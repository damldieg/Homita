-- shopping_rollback_check.sql — Ida de la vuelta 0045 → rollback_0045_menus_compra.sql (change
-- menus-compra). Solo BD local, tras el reset 0001–0045. ci.sh sustituye la línea
-- `-- @ROLLBACK:<fichero>@` por scripts/supabase/rollback/<fichero>. Cada bloque emite 'ok RSx: …' o
-- aborta con 'shopping_rollback RSx: …'.
--
-- NO va en transacción: el rollback se confirma de verdad. shopping_reapply_check.sql (tras reaplicar
-- 0045 desde ci.sh) comprueba que el esquema vuelve completo.
--
-- RS1 no existen shopping_item, las columnas optional y shopping_revision, ni las funciones de 0045;
--     client_request vuelve a ('task', 'task_list') sin la columna result.
-- RS2 0044 sigue entera y accept_meal_plan / upsert_meal_plan_items vuelven al cuerpo de 0044.
-- RS3 rollback_0045 una segunda vez no falla y deja el mismo estado (idempotente).

\set ON_ERROR_STOP 1
do $$
begin
    if inet_server_addr() is not null and host(inet_server_addr()) not in ('127.0.0.1', '::1') then
        raise exception 'shopping_rollback_check: solo BD local (socket o loopback); servidor %', host(inet_server_addr());
    end if;
    if to_regclass('public.shopping_item') is null then
        raise exception 'shopping_rollback_check: 0045 no está aplicada (falta shopping_item)';
    end if;
end $$;

create function pg_temp.rs_state() returns text
language plpgsql as $$
begin
    if to_regclass('public.shopping_item') is not null
       or exists (select 1 from information_schema.columns where table_schema = 'public'
                  and ((table_name = 'recipe_ingredient' and column_name = 'optional')
                       or (table_name = 'meal_plan' and column_name = 'shopping_revision')
                       or (table_name = 'client_request' and column_name = 'result'))) then
        return 'RS1 siguen existiendo shopping_item o columnas de 0045';
    end if;
    if exists (select 1 from pg_proc where pronamespace = 'public'::regnamespace
               and proname in ('preview_meal_shopping', 'sync_meal_shopping', 'list_shopping', 'create_shopping_item',
                               'set_shopping_item_state', 'update_shopping_item_qty', 'delete_shopping_item',
                               'clear_checked_shopping', 'fn_meal_shopping_sync', 'fn_meal_shopping_calc',
                               'fn_meal_shopping_round', 'fn_meal_pantry_basic_names', 'fn_shopping_item_json')) then
        return 'RS1 siguen existiendo funciones de 0045';
    end if;
    if (select count(*) from pg_constraint where conrelid = 'public.client_request'::regclass and contype = 'c'
        and pg_get_constraintdef(oid) like '%shopping_item%') <> 0
       or (select count(*) from pg_constraint where conrelid = 'public.client_request'::regclass and contype = 'c'
           and pg_get_constraintdef(oid) like '%task_list%') <> 1 then
        return 'RS1 el check de client_request.kind no volvió a 0035';
    end if;
    if to_regclass('public.meal_plan') is null or to_regclass('public.recipe_ingredient') is null
       or to_regclass('public.food') is null
       or (select count(*) from pg_proc where pronamespace = 'public'::regnamespace
           and proname in ('accept_meal_plan', 'upsert_meal_plan_items', 'archive_meal_plan', 'get_meal_plan')) <> 4 then
        return 'RS2 el rollback tocó 0044 (tablas o RPC)';
    end if;
    if exists (select 1 from pg_proc where pronamespace = 'public'::regnamespace
               and proname in ('accept_meal_plan', 'upsert_meal_plan_items')
               and pg_get_functiondef(oid) like '%shopping%') then
        return 'RS2 accept_meal_plan o upsert_meal_plan_items siguen llamando a la compra';
    end if;
    return null;
end $$;

-- @ROLLBACK:rollback_0045_menus_compra.sql@

do $$
declare
    v_err text := pg_temp.rs_state();
begin
    if v_err is not null then
        raise exception 'shopping_rollback %', v_err;
    end if;
    raise notice 'ok RS1: sin shopping_item, columnas ni funciones de 0045; client_request vuelve a task/task_list';
    raise notice 'ok RS2: 0044 intacta con sus cuerpos originales';
end $$;

-- @ROLLBACK:rollback_0045_menus_compra.sql@

do $$
declare
    v_err text := pg_temp.rs_state();
begin
    if v_err is not null then
        raise exception 'shopping_rollback RS3 %', v_err;
    end if;
    raise notice 'ok RS3: segundo rollback sin error y mismo estado';
end $$;
