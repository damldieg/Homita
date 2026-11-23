-- meal_profile_reapply_check.sql — Tras reaplicar 0043_meal_profile.sql sobre la BD revertida
-- (ci.sh la aplica justo antes). Solo BD local.
-- RA1 existen las 4 tablas, las 5 RPC y el catálogo vuelve a 28/47 (23/8/13/3).
-- RA2 el backfill dio los menu.* a las membresías `member` existentes según su kind (ninguna
--     membresía admin recibió filas) y no hay membresías `member` con kind sin sus menu.* de defecto.

\set ON_ERROR_STOP 1
do $$
begin
    if inet_server_addr() is not null and host(inet_server_addr()) not in ('127.0.0.1', '::1') then
        raise exception 'meal_profile_reapply_check: solo BD local (socket o loopback); servidor %', host(inet_server_addr());
    end if;
end $$;

do $$
begin
    if to_regclass('public.meal_profile') is null or to_regclass('public.meal_profile_member') is null
       or to_regclass('public.meal_schedule') is null or to_regclass('public.meal_slot_setting') is null
       or (select count(*) from pg_proc where pronamespace = 'public'::regnamespace
           and proname in ('get_meal_profile', 'update_meal_profile', 'update_meal_profile_member',
                           'set_meal_schedule', 'set_meal_slot_settings')) <> 5 then
        raise exception 'meal_profile_reapply RA1: faltan tablas o RPC';
    end if;
    if (select count(*) from permission) <> 28 or (select count(*) from member_kind_default) <> 47
       or (select count(*) from member_kind_default where kind = 'adult') <> 23
       or (select count(*) from member_kind_default where kind = 'child') <> 8
       or (select count(*) from member_kind_default where kind = 'relative') <> 13
       or (select count(*) from member_kind_default where kind = 'guest') <> 3 then
        raise exception 'meal_profile_reapply RA1: catálogo distinto de 28/47';
    end if;
    raise notice 'ok RA1: tablas, RPC y catálogo 28/47 tras reaplicar';
end $$;

do $$
begin
    if exists (select 1 from membership_permission mp join home_membership hm on hm.id = mp.home_membership_id
               where hm.role = 'admin' and mp.permission_code like 'menu.%') then
        raise exception 'meal_profile_reapply RA2: el backfill dio menu.* a un admin';
    end if;
    if exists (
        select 1 from home_membership hm
        join home_member m on m.home_id = hm.home_id and m.app_user_id = hm.app_user_id
        join member_kind_default d on d.kind = m.kind and d.permission_code like 'menu.%'
        where hm.role = 'member'
          and not exists (select 1 from membership_permission mp
                          where mp.home_membership_id = hm.id and mp.permission_code = d.permission_code)) then
        raise exception 'meal_profile_reapply RA2: membresía member sin sus menu.* tras el backfill';
    end if;
    raise notice 'ok RA2: backfill por kind completo, sin filas para admin';
end $$;
