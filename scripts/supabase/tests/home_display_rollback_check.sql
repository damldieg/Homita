-- home_display_rollback_check.sql — Ida y vuelta de 0049 (rollback_0049_home_display.sql).
-- Solo BD local, tras aplicar 0049 y antes de reaplicarla:  psql -v ON_ERROR_STOP=1 -f home_display_rollback_check.sql
-- Tras el rollback: 'ok R1' (sin tablas home_display*), 'ok R2' (sin funciones fn_display_*) y 'ok R3' (sin
-- permiso display.manage). El script de ci.sh reaplica 0049 y vuelve a correr home_display_check.sql.

do $$
begin
    if exists (select 1 from information_schema.tables where table_schema = 'public' and table_name like 'home_display%') then
        raise exception 'home_display_rollback R1: quedan tablas home_display%%';
    end if;
    raise notice 'ok R1: sin tablas home_display';
end $$;

do $$
begin
    if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
               where n.nspname = 'public' and p.proname like 'fn_display%')
       or exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                  where n.nspname = 'public' and p.proname = 'fn_can_manage_displays') then
        raise exception 'home_display_rollback R2: quedan funciones fn_display*';
    end if;
    raise notice 'ok R2: sin funciones de pantallas';
end $$;

do $$
begin
    if exists (select 1 from permission where code = 'display.manage')
       or exists (select 1 from membership_permission where permission_code = 'display.manage') then
        raise exception 'home_display_rollback R3: queda display.manage';
    end if;
    raise notice 'ok R3: sin permiso display.manage';
end $$;
