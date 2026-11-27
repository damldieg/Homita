-- actualizacion_remota_check.sql — 0051 (dashboard-actualizacion-remota). Estructura, ACL y el bucket.
-- U1 columnas y canal por defecto · U2 check del canal · U3 anon no ejecuta las funciones nuevas ·
-- U4 authenticated sí puede ejecutar fn_display_report y fn_display_set_channel · U5 bucket privado · U-clean.

do $$
declare v_default text;
begin
    select column_default into v_default from information_schema.columns
    where table_schema = 'public' and table_name = 'home_display' and column_name = 'update_channel';
    if v_default is null or v_default not like '%estable%' then
        raise exception 'actualizacion_remota U1: update_channel sin valor por defecto estable';
    end if;
    if not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'home_display'
                   and column_name in ('app_version_code', 'app_version_name', 'last_update_check_at', 'last_update_result')
                   having count(*) = 4) then
        raise exception 'actualizacion_remota U1: faltan columnas de versión o de comprobación';
    end if;
    raise notice 'ok U1: columnas y canal por defecto';
end $$;

do $$
begin
    if not exists (select 1 from pg_constraint where conrelid = 'home_display'::regclass and contype = 'c'
                   and pg_get_constraintdef(oid) like '%pruebas%') then
        raise exception 'actualizacion_remota U2: falta el check del canal';
    end if;
    raise notice 'ok U2: check del canal';
end $$;

do $$
begin
    if has_function_privilege('anon', 'public.fn_display_report(integer,text,text,boolean)', 'EXECUTE')
       or has_function_privilege('anon', 'public.fn_display_set_channel(bigint,bigint,text)', 'EXECUTE') then
        raise exception 'actualizacion_remota U3: anon ejecuta una función de canal o de informe';
    end if;
    raise notice 'ok U3: anon no ejecuta las funciones nuevas';
end $$;

do $$
begin
    if not has_function_privilege('authenticated', 'public.fn_display_report(integer,text,text,boolean)', 'EXECUTE')
       or not has_function_privilege('authenticated', 'public.fn_display_set_channel(bigint,bigint,text)', 'EXECUTE') then
        raise exception 'actualizacion_remota U4: authenticated no ejecuta las funciones nuevas';
    end if;
    raise notice 'ok U4: authenticated ejecuta las funciones nuevas';
end $$;

do $$
begin
    if not exists (select 1 from storage.buckets where id = 'display-releases' and public = false) then
        raise exception 'actualizacion_remota U5: falta el bucket display-releases privado';
    end if;
    raise notice 'ok U5: bucket privado';
end $$;

do $$
begin
    raise notice 'ok U-clean';
end $$;
