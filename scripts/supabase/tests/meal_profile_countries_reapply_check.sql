-- meal_profile_countries_reapply_check.sql — Tras reaplicar 0046_menus_paises_hogar.sql sobre la BD revertida
-- (ci.sh la aplica justo antes). Solo BD local.
-- RC4 existen meal_profile.countries (text[] not null, default vacío), su check, las dos funciones cerradas
--     y get/update_meal_profile con `countries`.

\set ON_ERROR_STOP 1
do $$
begin
    if inet_server_addr() is not null and host(inet_server_addr()) not in ('127.0.0.1', '::1') then
        raise exception 'meal_profile_countries_reapply_check: solo BD local (socket o loopback); servidor %', host(inet_server_addr());
    end if;
end $$;

do $$
begin
    if (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'meal_profile'
        and column_name = 'countries' and data_type = 'ARRAY' and is_nullable = 'NO') <> 1 then
        raise exception 'meal_profile_countries_reapply RC4: falta la columna countries';
    end if;
    if not exists (select 1 from pg_constraint where conrelid = 'public.meal_profile'::regclass
                   and conname = 'meal_profile_countries_check' and contype = 'c') then
        raise exception 'meal_profile_countries_reapply RC4: falta meal_profile_countries_check';
    end if;
    if has_function_privilege('anon', 'fn_meal_countries_valid(text[])', 'execute')
       or has_function_privilege('authenticated', 'fn_meal_countries_normalize(jsonb)', 'execute') then
        raise exception 'meal_profile_countries_reapply RC4: funciones abiertas';
    end if;
    if pg_get_functiondef('public.get_meal_profile()'::regprocedure) not like '%countries%'
       or pg_get_functiondef('public.update_meal_profile(jsonb)'::regprocedure) not like '%countries%' then
        raise exception 'meal_profile_countries_reapply RC4: get/update_meal_profile sin countries';
    end if;
    raise notice 'ok RC4: columna, check, funciones cerradas y RPC con countries';
end $$;
