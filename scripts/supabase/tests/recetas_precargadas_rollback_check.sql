-- recetas_precargadas_rollback_check.sql — Ida de la vuelta 0047 → rollback_0047_menus_recetas_precargadas.sql
-- (change menus-recetas-precargadas). Solo BD local, con 0047 y el seed de recetas cargados. ci.sh sustituye la
-- línea `-- @ROLLBACK:<fichero>@` por scripts/supabase/rollback/<fichero>. Emite 'ok RRx: …' o aborta.
--
-- NO va en transacción: el rollback se confirma de verdad. recetas_precargadas_reapply_check.sql (tras
-- reaplicar 0047 y el seed desde ci.sh) comprueba que el esquema vuelve completo.
--
-- RR1 sin recipe.country, sin recetas comunes (ni sus ingredientes), home_id otra vez NOT NULL y sin índice.
-- RR2 las policies de recipe vuelven a exigir hogar; list_recipes/get_recipe no devuelven ni filtran comunes.
-- RR3 rollback_0047 una segunda vez no falla y deja el mismo estado (idempotente).

\set ON_ERROR_STOP 1
do $$
begin
    if inet_server_addr() is not null and host(inet_server_addr()) not in ('127.0.0.1', '::1') then
        raise exception 'recetas_precargadas_rollback_check: solo BD local (socket o loopback); servidor %', host(inet_server_addr());
    end if;
    if not exists (select 1 from information_schema.columns where table_schema = 'public'
                   and table_name = 'recipe' and column_name = 'country') then
        raise exception 'recetas_precargadas_rollback_check: 0047 no está aplicada (falta recipe.country)';
    end if;
end $$;

create function pg_temp.rr_state() returns text
language plpgsql as $$
begin
    if exists (select 1 from information_schema.columns where table_schema = 'public'
               and table_name = 'recipe' and column_name = 'country')
       or to_regclass('public.recipe_common_name_country_uq') is not null
       or exists (select 1 from pg_constraint where conname = 'recipe_common_country_ck') then
        return 'RR1 siguen la columna country, su check o el índice único';
    end if;
    if exists (select 1 from recipe where home_id is null) or exists (select 1 from recipe_ingredient where home_id is null) then
        return 'RR1 quedan recetas comunes';
    end if;
    if (select count(*) from information_schema.columns where table_schema = 'public' and is_nullable = 'YES'
        and column_name = 'home_id' and table_name in ('recipe', 'recipe_ingredient')) <> 0 then
        return 'RR1 home_id de recipe o recipe_ingredient admite nulo';
    end if;
    if (select count(*) from pg_policy where polrelid in ('public.recipe'::regclass, 'public.recipe_ingredient'::regclass)
        and pg_get_expr(polqual, polrelid) like '%IS NULL%') <> 0 then
        return 'RR2 las policies de recipe siguen admitiendo home_id nulo';
    end if;
    if pg_get_functiondef('public.list_recipes(text,text,integer)'::regprocedure) like '%home_id is null%'
       or pg_get_functiondef('public.get_recipe(bigint)'::regprocedure) like '%home_id is null%'
       or pg_get_functiondef('public.fn_meal_recipe_json(bigint)'::regprocedure) like '%country%' then
        return 'RR2 las funciones siguen con el cuerpo de 0047';
    end if;
    return null;
end $$;

-- @ROLLBACK:rollback_0047_menus_recetas_precargadas.sql@

do $$
declare
    v_err text := pg_temp.rr_state();
begin
    if v_err is not null then
        raise exception 'recetas_precargadas_rollback %', v_err;
    end if;
    raise notice 'ok RR1: sin country, sin recetas comunes, home_id NOT NULL y sin índice único parcial';
    raise notice 'ok RR2: policies y funciones de recetas como en 0044/0045';
end $$;

-- @ROLLBACK:rollback_0047_menus_recetas_precargadas.sql@

do $$
declare
    v_err text := pg_temp.rr_state();
begin
    if v_err is not null then
        raise exception 'recetas_precargadas_rollback RR3 (segunda pasada) %', v_err;
    end if;
    raise notice 'ok RR3: rollback_0047 idempotente';
end $$;
