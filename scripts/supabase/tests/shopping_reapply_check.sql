-- shopping_reapply_check.sql — Tras reaplicar 0045_menus_compra.sql sobre la BD revertida (ci.sh la
-- aplica justo antes). Solo BD local.
-- RS4 existen shopping_item (1 policy SELECT, sin escritura), las columnas, el índice único parcial, las 9
--     RPC de la compra y el check de client_request.kind con los kinds nuevos.

\set ON_ERROR_STOP 1
do $$
begin
    if inet_server_addr() is not null and host(inet_server_addr()) not in ('127.0.0.1', '::1') then
        raise exception 'shopping_reapply_check: solo BD local (socket o loopback); servidor %', host(inet_server_addr());
    end if;
end $$;

do $$
begin
    if to_regclass('public.shopping_item') is null then
        raise exception 'shopping_reapply RS4: falta shopping_item';
    end if;
    if (select count(*) from pg_policy where polrelid = 'public.shopping_item'::regclass and polcmd = 'r') <> 1
       or has_table_privilege('authenticated', 'public.shopping_item', 'insert,update,delete') then
        raise exception 'shopping_reapply RS4: RLS o privilegios de shopping_item incorrectos';
    end if;
    if (select count(*) from information_schema.columns where table_schema = 'public'
        and ((table_name = 'recipe_ingredient' and column_name = 'optional')
             or (table_name = 'meal_plan' and column_name = 'shopping_revision')
             or (table_name = 'client_request' and column_name = 'result'))) <> 3 then
        raise exception 'shopping_reapply RS4: faltan columnas de 0045';
    end if;
    if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace
        and proname in ('preview_meal_shopping', 'sync_meal_shopping', 'list_shopping', 'create_shopping_item',
                        'set_shopping_item_state', 'update_shopping_item_qty', 'delete_shopping_item',
                        'clear_checked_shopping')) <> 8 then
        raise exception 'shopping_reapply RS4: faltan RPC de la compra';
    end if;
    if not exists (select 1 from pg_indexes where indexname = 'shopping_item_plan_agg_uq') then
        raise exception 'shopping_reapply RS4: falta el índice único parcial';
    end if;
    if not exists (select 1 from pg_constraint where conrelid = 'public.client_request'::regclass and contype = 'c'
                   and pg_get_constraintdef(oid) like '%meal_shopping_sync%') then
        raise exception 'shopping_reapply RS4: el check de client_request.kind no admite los kinds nuevos';
    end if;
    if (select count(*) from permission) <> 29 or (select count(*) from member_kind_default) <> 47 then
        raise exception 'shopping_reapply RS4: catálogo de permisos distinto de 29/47';
    end if;
    raise notice 'ok RS4: shopping_item, columnas, 8 RPC, índice parcial y kinds nuevos tras reaplicar';
end $$;
