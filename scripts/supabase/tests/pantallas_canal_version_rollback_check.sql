-- pantallas_canal_version_rollback_check.sql — tras rollback_0053: fn_display_list vuelve a la forma de 0049.
-- V1 sin canal ni versión en fn_display_list.

do $$
declare v_def text := pg_get_functiondef('public.fn_display_list(bigint)'::regprocedure);
begin
    if v_def like '%update_channel%' or v_def like '%app_version_code%' then
        raise exception 'pantallas_canal_version_rollback V1: fn_display_list sigue con canal o versión';
    end if;
    raise notice 'ok V1: fn_display_list sin canal ni versión';
end $$;
