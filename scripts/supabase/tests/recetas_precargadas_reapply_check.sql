-- recetas_precargadas_reapply_check.sql — Tras reaplicar 0047_menus_recetas_precargadas.sql y recargar
-- supabase/seed/recetas_precargadas.sql sobre la BD revertida (ci.sh lo hace justo antes). Solo BD local.
-- RA5 vuelven recipe.country, el check, el índice único parcial, home_id nulable, las policies con home_id
--     nulo, el cuerpo de las funciones y las 20 recetas comunes.

\set ON_ERROR_STOP 1
do $$
begin
    if inet_server_addr() is not null and host(inet_server_addr()) not in ('127.0.0.1', '::1') then
        raise exception 'recetas_precargadas_reapply_check: solo BD local (socket o loopback); servidor %', host(inet_server_addr());
    end if;
end $$;

do $$
begin
    if not exists (select 1 from information_schema.columns where table_schema = 'public'
                   and table_name = 'recipe' and column_name = 'country') then
        raise exception 'recetas_precargadas_reapply RA5: falta recipe.country';
    end if;
    if to_regclass('public.recipe_common_name_country_uq') is null
       or not exists (select 1 from pg_constraint where conname = 'recipe_common_country_ck') then
        raise exception 'recetas_precargadas_reapply RA5: falta el índice único parcial o el check de país';
    end if;
    if (select count(*) from information_schema.columns where table_schema = 'public' and is_nullable = 'YES'
        and column_name = 'home_id' and table_name in ('recipe', 'recipe_ingredient')) <> 2 then
        raise exception 'recetas_precargadas_reapply RA5: home_id no admite nulo en recipe y recipe_ingredient';
    end if;
    if (select count(*) from pg_policy where polrelid in ('public.recipe'::regclass, 'public.recipe_ingredient'::regclass)
        and polcmd = 'r' and pg_get_expr(polqual, polrelid) like '%IS NULL%') <> 2 then
        raise exception 'recetas_precargadas_reapply RA5: las policies SELECT no admiten home_id nulo';
    end if;
    if (select count(*) from recipe where home_id is null) <> 20 then
        raise exception 'recetas_precargadas_reapply RA5: se esperaban 20 recetas comunes tras recargar el seed';
    end if;
    if (select count(*) from permission) <> 28 or (select count(*) from member_kind_default) <> 47 then
        raise exception 'recetas_precargadas_reapply RA5: catálogo de permisos distinto de 28/47';
    end if;
    raise notice 'ok RA5: country, índice único, check, home_id nulable, policies y 20 comunes tras reaplicar';
end $$;
