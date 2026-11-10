-- rollback_0018.sql — Rollback de 0018_home_membership_admin.sql (fase 1.6, T9; plan §7).
-- Revierte 0018 dejando el estado previo: borra las 3 RPC /home/membership/* y los 4 helpers
-- internos, y restaura los cuerpos de get_calendar_users y get_task_list_users de 0005:74-91 y
-- 0005:120-137 copiados byte a byte (md5(prosrc) = baseline pre-0018; sin la clave 'home_role').
-- Los grants de las dos redefinidas se conservan (create or replace, mismos de 0005:279-292);
-- add_calendar_user/add_task_list_user nunca se tocaron (0014b, plantilla USER intacta).
-- Precondición: sin membresías modificadas por las RPC de 0018 desde el volcado de G4 (el rollback
-- no deshace promote/demote/salidas ya aplicadas a los datos).
-- Re-aplicar 0018 tras el rollback es idempotente (create or replace + revoke/grant repetibles).
-- Uso: psql -v ON_ERROR_STOP=1 -1 -f rollback_0018.sql

begin;

-- ── (a) Se borran las RPC nuevas de /home/membership/* y los helpers internos ──
drop function if exists set_home_membership_role(bigint, bigint, text);
drop function if exists transfer_home_admin(bigint, bigint);
drop function if exists remove_home_membership(bigint, bigint);
drop function if exists fn_home_mutation_guard(bigint);
drop function if exists fn_admin_count_excluding(bigint, bigint);
drop function if exists fn_is_sole_owner_somewhere(bigint, bigint);
drop function if exists fn_seed_member_legacy(bigint);

-- ── (b) Se restauran los cuerpos previos a 0018 (copias literales de 0005) ──

create or replace function get_calendar_users(p_calendar_id bigint) returns json
language plpgsql stable security definer set search_path = public as $$
begin
    if fn_my_user_id() is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    if not exists (select 1 from calendar_user where calendar_id = p_calendar_id and user_id = fn_my_user_id()) then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    return (
        select coalesce(json_agg(json_build_object(
            'cu_id', cu.id, 'user_id', u.id, 'name', u.name, 'email', u.email, 'role', cu.role
        ) order by (cu.role::text) collate "C", u.name collate "C"), '[]'::json)
        from calendar_user cu
        inner join app_user u on u.id = cu.user_id
        where cu.calendar_id = p_calendar_id
    );
end $$;

create or replace function get_task_list_users(p_task_list_id bigint) returns json
language plpgsql stable security definer set search_path = public as $$
begin
    if fn_my_user_id() is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    if not exists (select 1 from task_list_user where task_list_id = p_task_list_id and user_id = fn_my_user_id()) then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    return (
        select coalesce(json_agg(json_build_object(
            'tlu_id', tlu.id, 'user_id', u.id, 'name', u.name, 'email', u.email, 'role', tlu.role
        ) order by (tlu.role::text) collate "C", u.name collate "C"), '[]'::json)
        from task_list_user tlu
        inner join app_user u on u.id = tlu.user_id
        where tlu.task_list_id = p_task_list_id
    );
end $$;


commit;
