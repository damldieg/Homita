-- actualizacion_remota_rollback_check.sql — tras rollback_0051: sin columnas nuevas ni funciones de canal/informe.
-- V1 columnas de 0051 fuera de home_display · V2 funciones fn_display_report y fn_display_set_channel fuera.

do $$
begin
    if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'home_display'
               and column_name in ('update_channel', 'app_version_code', 'app_version_name', 'last_update_check_at', 'last_update_result')) then
        raise exception 'actualizacion_remota_rollback V1: quedan columnas de 0051';
    end if;
    raise notice 'ok V1: sin columnas de 0051';
end $$;

do $$
begin
    if exists (select 1 from pg_proc where proname in ('fn_display_report', 'fn_display_set_channel')) then
        raise exception 'actualizacion_remota_rollback V2: quedan funciones de 0051';
    end if;
    raise notice 'ok V2: sin funciones de 0051';
end $$;
