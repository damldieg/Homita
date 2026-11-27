-- pantallas_canal_version_check.sql — 0053 (dashboard-pantallas-canal): fn_display_list expone canal y versión.
-- F1 la definición incluye los campos nuevos · F2 sigue sin EXECUTE para anon · F3 authenticated la ejecuta · F-clean.

do $$
declare v_def text := pg_get_functiondef('public.fn_display_list(bigint)'::regprocedure);
begin
    if v_def not like '%update_channel%' or v_def not like '%app_version_code%'
       or v_def not like '%last_update_result%' or v_def not like '%last_update_check_at%' then
        raise exception 'pantallas_canal_version F1: fn_display_list no expone canal ni versión';
    end if;
    raise notice 'ok F1: fn_display_list expone canal y versión';
end $$;

do $$
begin
    if has_function_privilege('anon', 'public.fn_display_list(bigint)', 'EXECUTE') then
        raise exception 'pantallas_canal_version F2: anon ejecuta fn_display_list';
    end if;
    raise notice 'ok F2: anon no ejecuta fn_display_list';
end $$;

do $$
begin
    if not has_function_privilege('authenticated', 'public.fn_display_list(bigint)', 'EXECUTE') then
        raise exception 'pantallas_canal_version F3: authenticated no ejecuta fn_display_list';
    end if;
    raise notice 'ok F3: authenticated ejecuta fn_display_list';
end $$;

do $$
begin
    raise notice 'ok F-clean';
end $$;
