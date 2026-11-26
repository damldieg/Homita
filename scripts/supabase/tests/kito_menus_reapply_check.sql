-- kito_menus_reapply_check.sql — Tras reaplicar 0048_menus_kito.sql sobre la BD revertida (ci.sh la aplica
-- justo antes). Solo BD local.
-- RK4 existen las columnas origin y state, las firmas nuevas de upsert_meal_plan_items y create_recipe y el
--     check de client_request.kind con los kinds nuevos.

\set ON_ERROR_STOP 1
do $$
begin
    if inet_server_addr() is not null and host(inet_server_addr()) not in ('127.0.0.1', '::1') then
        raise exception 'kito_menus_reapply_check: solo BD local (socket o loopback); servidor %', host(inet_server_addr());
    end if;
end $$;

do $$
begin
    if (select count(*) from information_schema.columns where table_schema = 'public'
        and ((table_name = 'meal_plan' and column_name = 'origin')
             or (table_name = 'recipe' and column_name = 'origin')
             or (table_name = 'meal_plan_item' and column_name = 'state'))) <> 3 then
        raise exception 'kito_menus_reapply RK4: faltan columnas de 0048';
    end if;
    if to_regprocedure('public.upsert_meal_plan_items(date, integer, jsonb, bigint[], uuid, text)') is null
       or to_regprocedure('public.create_recipe(text, integer, integer, jsonb, jsonb, jsonb, uuid, text)') is null
       or to_regprocedure('public.upsert_meal_plan_items(date, integer, jsonb, bigint[])') is not null
       or to_regprocedure('public.create_recipe(text, integer, integer, jsonb, jsonb, jsonb)') is not null then
        raise exception 'kito_menus_reapply RK4: firmas de 0048 incorrectas';
    end if;
    if not exists (select 1 from pg_constraint where conrelid = 'public.client_request'::regclass and contype = 'c'
                   and pg_get_constraintdef(oid) like '%meal_plan%' and pg_get_constraintdef(oid) like '%recipe%') then
        raise exception 'kito_menus_reapply RK4: el check de client_request.kind no admite los kinds nuevos';
    end if;
    raise notice 'ok RK4: columnas, firmas y kinds de 0048 restaurados';
end $$;
