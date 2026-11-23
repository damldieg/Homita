-- meal_profile_rollback_check.sql — Ida de la vuelta 0043 → rollback_0043_meal_profile.sql (change
-- menus-perfil-hogar). Solo BD local, tras el reset 0001–0043. ci.sh sustituye la línea
-- `-- @ROLLBACK:<fichero>@` por scripts/supabase/rollback/<fichero>. Cada bloque emite 'ok RMx: …' o
-- aborta con 'meal_profile_rollback RMx: …'.
--
-- NO va en transacción: el rollback se confirma de verdad. meal_profile_reapply_check.sql (tras
-- reaplicar 0043 desde ci.sh) comprueba que el esquema vuelve completo.
--
-- RM1 no existen las tablas meal_*, sus RPC ni los helpers.
-- RM2 catálogo como antes de 0043: 23 permisos, 37 defaults (18/6/10/3), sin menu.* en ningún sitio.
-- RM3 rollback_0043 una segunda vez no falla y deja el mismo estado (idempotente).

\set ON_ERROR_STOP 1
do $$
begin
    if inet_server_addr() is not null and host(inet_server_addr()) not in ('127.0.0.1', '::1') then
        raise exception 'meal_profile_rollback_check: solo BD local (socket o loopback); servidor %', host(inet_server_addr());
    end if;
    if to_regclass('public.meal_profile') is null then
        raise exception 'meal_profile_rollback_check: 0043 no está aplicada (falta meal_profile)';
    end if;
end $$;

create function pg_temp.rm_state() returns text
language plpgsql as $$
begin
    if to_regclass('public.meal_profile') is not null or to_regclass('public.meal_profile_member') is not null
       or to_regclass('public.meal_schedule') is not null or to_regclass('public.meal_slot_setting') is not null then
        return 'RM1 siguen existiendo tablas meal_*';
    end if;
    if exists (select 1 from pg_proc where pronamespace = 'public'::regnamespace
               and proname in ('get_meal_profile', 'update_meal_profile', 'update_meal_profile_member',
                               'set_meal_schedule', 'set_meal_slot_settings', 'fn_meal_profile_ensure',
                               'fn_meal_member_guard', 'fn_meal_allergies_valid', 'fn_meal_jsonb_to_text_array', 'fn_meal_texts_valid')) then
        return 'RM1 siguen existiendo funciones meal';
    end if;
    if (select count(*) from permission) <> 23 or (select count(*) from member_kind_default) <> 37
       or (select count(*) from member_kind_default where kind = 'adult') <> 18
       or (select count(*) from member_kind_default where kind = 'child') <> 6
       or (select count(*) from member_kind_default where kind = 'relative') <> 10
       or (select count(*) from member_kind_default where kind = 'guest') <> 3 then
        return 'RM2 catálogo distinto de 23/37 (18/6/10/3)';
    end if;
    if exists (select 1 from membership_permission where permission_code like 'menu.%')
       or exists (select 1 from member_kind_default where permission_code like 'menu.%')
       or exists (select 1 from permission where code like 'menu.%') then
        return 'RM2 quedan códigos menu.*';
    end if;
    return null;
end $$;

-- @ROLLBACK:rollback_0043_meal_profile.sql@

do $$
declare
    v_err text := pg_temp.rm_state();
begin
    if v_err is not null then
        raise exception 'meal_profile_rollback %', v_err;
    end if;
    raise notice 'ok RM1: sin tablas ni funciones meal_*';
    raise notice 'ok RM2: catálogo 23/37 sin menu.*';
end $$;

-- @ROLLBACK:rollback_0043_meal_profile.sql@

do $$
declare
    v_err text := pg_temp.rm_state();
begin
    if v_err is not null then
        raise exception 'meal_profile_rollback RM3 %', v_err;
    end if;
    raise notice 'ok RM3: segundo rollback sin error y mismo estado';
end $$;
