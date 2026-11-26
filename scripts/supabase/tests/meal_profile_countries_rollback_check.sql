-- meal_profile_countries_rollback_check.sql — Ida de la vuelta 0046 → rollback_0046_menus_paises_hogar.sql
-- (change menus-paises-hogar). Solo BD local, tras el reset 0001–0046. ci.sh sustituye la línea
-- `-- @ROLLBACK:<fichero>@` por scripts/supabase/rollback/<fichero>. NO va en transacción: el rollback se
-- confirma de verdad; meal_profile_countries_reapply_check.sql comprueba la reaplicación.
-- RC1 no existen meal_profile.countries ni las funciones fn_meal_countries_*; get_meal_profile y
--     update_meal_profile vuelven al cuerpo de 0043 (sin `countries`, que se rechaza como clave desconocida).
-- RC2 0043–0045 siguen enteras (meal_profile, menú y compra).
-- RC3 rollback_0046 una segunda vez no falla y deja el mismo estado (idempotente).

\set ON_ERROR_STOP 1
do $$
begin
    if inet_server_addr() is not null and host(inet_server_addr()) not in ('127.0.0.1', '::1') then
        raise exception 'meal_profile_countries_rollback_check: solo BD local (socket o loopback); servidor %', host(inet_server_addr());
    end if;
    if not exists (select 1 from information_schema.columns where table_schema = 'public'
                   and table_name = 'meal_profile' and column_name = 'countries') then
        raise exception 'meal_profile_countries_rollback_check: 0046 no está aplicada (falta meal_profile.countries)';
    end if;
end $$;

create function pg_temp.rc_state() returns text
language plpgsql as $$
begin
    if exists (select 1 from information_schema.columns where table_schema = 'public'
               and table_name = 'meal_profile' and column_name = 'countries')
       or exists (select 1 from pg_proc where pronamespace = 'public'::regnamespace
                  and proname in ('fn_meal_countries_valid', 'fn_meal_countries_normalize')) then
        return 'RC1 siguen existiendo la columna countries o sus funciones';
    end if;
    if pg_get_functiondef('public.get_meal_profile()'::regprocedure) like '%countries%'
       or pg_get_functiondef('public.update_meal_profile(jsonb)'::regprocedure) like '%countries%' then
        return 'RC1 get_meal_profile / update_meal_profile conservan countries';
    end if;
    if to_regclass('public.meal_profile') is null or to_regclass('public.meal_plan') is null
       or to_regclass('public.shopping_item') is null
       or to_regprocedure('public.get_meal_profile()') is null or to_regprocedure('public.update_meal_profile(jsonb)') is null
       or not has_function_privilege('authenticated', 'public.update_meal_profile(jsonb)', 'execute')
       or has_function_privilege('anon', 'public.update_meal_profile(jsonb)', 'execute') then
        return 'RC2 faltan tablas, funciones o grants de 0043–0045';
    end if;
    return 'ok';
end $$;

-- @ROLLBACK:rollback_0046_menus_paises_hogar.sql@

do $$
declare
    v text := pg_temp.rc_state();
begin
    if v <> 'ok' then
        raise exception 'meal_profile_countries_rollback %', v;
    end if;
    raise notice 'ok RC1: sin columna ni funciones de 0046; get/update_meal_profile como en 0043';
    raise notice 'ok RC2: 0043–0045 intactas y grants conservados';
end $$;

-- @ROLLBACK:rollback_0046_menus_paises_hogar.sql@

do $$
declare
    v text := pg_temp.rc_state();
begin
    if v <> 'ok' then
        raise exception 'meal_profile_countries_rollback RC3 segunda pasada: %', v;
    end if;
    raise notice 'ok RC3: rollback idempotente';
end $$;
