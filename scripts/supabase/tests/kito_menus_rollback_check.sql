-- kito_menus_rollback_check.sql — Ida de la vuelta 0048 → rollback_0048_menus_kito.sql (change kito-menus).
-- Solo BD local, tras el reset 0001–0048. ci.sh sustituye la línea `-- @ROLLBACK:<fichero>@` por
-- scripts/supabase/rollback/<fichero>. Cada bloque emite 'ok RKx: …' o aborta con 'kito_menus_rollback RKx: …'.
--
-- NO va en transacción: el rollback se confirma de verdad. kito_menus_reapply_check.sql (tras reaplicar
-- 0048 desde ci.sh) comprueba que el esquema vuelve completo.
--
-- RK1 no existen origin, state ni las firmas nuevas; client_request.kind vuelve al de 0045.
-- RK2 0044/0045 siguen enteras: upsert_meal_plan_items y create_recipe con sus firmas antiguas y la compra intacta.
-- RK3 rollback_0048 una segunda vez no falla y deja el mismo estado (idempotente).

\set ON_ERROR_STOP 1
do $$
begin
    if inet_server_addr() is not null and host(inet_server_addr()) not in ('127.0.0.1', '::1') then
        raise exception 'kito_menus_rollback_check: solo BD local (socket o loopback); servidor %', host(inet_server_addr());
    end if;
    if not exists (select 1 from information_schema.columns where table_schema = 'public'
                   and table_name = 'meal_plan' and column_name = 'origin') then
        raise exception 'kito_menus_rollback_check: 0048 no está aplicada (falta meal_plan.origin)';
    end if;
end $$;

create function pg_temp.rk_state() returns text
language plpgsql as $$
begin
    if exists (select 1 from information_schema.columns where table_schema = 'public'
               and ((table_name = 'meal_plan' and column_name = 'origin')
                    or (table_name = 'recipe' and column_name = 'origin')
                    or (table_name = 'meal_plan_item' and column_name = 'state'))) then
        return 'RK1 siguen existiendo columnas de 0048';
    end if;
    if exists (select 1 from pg_proc where pronamespace = 'public'::regnamespace
               and ((proname = 'upsert_meal_plan_items' and pronargs <> 4)
                    or (proname = 'create_recipe' and pronargs <> 6))) then
        return 'RK1 siguen existiendo las firmas nuevas';
    end if;
    if (select count(*) from pg_constraint where conrelid = 'public.client_request'::regclass and contype = 'c'
        and pg_get_constraintdef(oid) like '%meal_plan%') <> 0
       or (select count(*) from pg_constraint where conrelid = 'public.client_request'::regclass and contype = 'c'
           and pg_get_constraintdef(oid) like '%meal_shopping_sync%') <> 1 then
        return 'RK1 el check de client_request.kind no volvió al de 0045';
    end if;
    if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace
        and proname in ('upsert_meal_plan_items', 'create_recipe')) <> 2
       or to_regclass('public.shopping_item') is null
       or to_regprocedure('public.upsert_meal_plan_items(date, integer, jsonb, bigint[])') is null
       or to_regprocedure('public.create_recipe(text, integer, integer, jsonb, jsonb, jsonb)') is null then
        return 'RK2 el rollback tocó 0044/0045 (RPC o compra)';
    end if;
    if not exists (select 1 from pg_proc where proname = 'upsert_meal_plan_items'
                   and pg_get_functiondef(oid) like '%fn_meal_shopping_sync%') then
        return 'RK2 upsert_meal_plan_items no volvió al cuerpo de 0045';
    end if;
    return null;
end $$;

-- @ROLLBACK:rollback_0048_menus_kito.sql@

do $$
declare
    v_err text := pg_temp.rk_state();
begin
    if v_err is not null then
        raise exception 'kito_menus_rollback %', v_err;
    end if;
    raise notice 'ok RK1: sin origin, state ni firmas nuevas; client_request.kind vuelve al de 0045';
    raise notice 'ok RK2: 0044/0045 intactas con sus cuerpos originales';
end $$;

-- @ROLLBACK:rollback_0048_menus_kito.sql@

do $$
declare
    v_err text := pg_temp.rk_state();
begin
    if v_err is not null then
        raise exception 'kito_menus_rollback RK3 %', v_err;
    end if;
    raise notice 'ok RK3: segundo rollback sin error y mismo estado';
end $$;
