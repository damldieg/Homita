-- rollback_0021.sql — Reversión de 0021_home_permisos_audit.sql (fase 1.9).
-- Drop de las 3 RPC y el helper nuevos; restaura los cuerpos PRE-0021 de las 7 funciones
-- redefinidas, emitidos verbatim desde pg_get_functiondef del baseline (md5(prosrc) idéntico
-- a baseline-0020.txt). No revierte datos: membership_permission editada y audit_log
-- home.permission.* permanecen (restaurar el volcado G4 para volver al estado previo).
-- 0021 no crea policies/tablas: pg_policies es idéntico antes, con 0021 y tras este rollback.

begin;

drop function if exists get_home_permissions(bigint);
drop function if exists set_home_permissions(bigint, bigint, jsonb);
drop function if exists get_home_audit(bigint, integer, bigint);
drop function if exists fn_audit_permission_delta(bigint, bigint, text[], text[], text, jsonb);

CREATE OR REPLACE FUNCTION public.add_calendar_user(p_calendar_id bigint, p_email text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
    v_me bigint := fn_my_user_id();
    v_role user_role;
    v_home bigint;
    v_target app_user%rowtype;
begin
    if v_me is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    -- 1.8 (§2.2/§2.3): lock del hogar (incluye la cabecera X-Home-Id) → ACL → owner →
    -- calendar.manage. Q3 (0014): email de no-miembro del hogar → 'Not Allowed'.
    v_home := fn_home_of_calendar(p_calendar_id);
    if v_home is null then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    perform fn_home_write_lock(v_home);
    select role into v_role from calendar_user where calendar_id = p_calendar_id and user_id = v_me for share;
    if v_role is null then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    if v_role <> 'owner' or not fn_has_permission(v_home, 'calendar.manage') then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    select * into v_target from app_user where email = p_email;
    if not found then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    if not exists (select 1 from home_membership where home_id = v_home and app_user_id = v_target.id) then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    if not exists (select 1 from calendar_user where calendar_id = p_calendar_id and user_id = v_target.id) then
        insert into calendar_user (calendar_id, user_id, role, widget, dashboard, home_id)
        values (p_calendar_id, v_target.id, 'viewer', true, true, v_home);
    end if;
    return json_build_object(
        'id', v_target.id, 'name', v_target.name, 'email', v_target.email,
        'created_at', to_char(v_target.created_at, 'YYYY-MM-DD HH24:MI:SS'),
        'updated_at', to_char(v_target.updated_at, 'YYYY-MM-DD HH24:MI:SS'));
end $function$;

CREATE OR REPLACE FUNCTION public.add_task_list_user(p_task_list_id bigint, p_email text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
    v_me bigint := fn_my_user_id();
    v_role user_role;
    v_home bigint;
    v_target app_user%rowtype;
begin
    if v_me is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    -- 1.8 (§2.2/§2.3): lock del hogar (incluye la cabecera X-Home-Id) → ACL → owner →
    -- tasklist.manage. Q3 (0014): email de no-miembro del hogar → 'Not Allowed'.
    v_home := fn_home_of_task_list(p_task_list_id);
    if v_home is null then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    perform fn_home_write_lock(v_home);
    select role into v_role from task_list_user where task_list_id = p_task_list_id and user_id = v_me for share;
    if v_role is null then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    if v_role <> 'owner' or not fn_has_permission(v_home, 'tasklist.manage') then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    select * into v_target from app_user where email = p_email;
    if not found then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    if not exists (select 1 from home_membership where home_id = v_home and app_user_id = v_target.id) then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    if not exists (select 1 from task_list_user where task_list_id = p_task_list_id and user_id = v_target.id) then
        insert into task_list_user (task_list_id, user_id, role, widget, dashboard, home_id)
        values (p_task_list_id, v_target.id, 'viewer', true, true, v_home);
    end if;
    return json_build_object(
        'id', v_target.id, 'name', v_target.name, 'email', v_target.email,
        'created_at', to_char(v_target.created_at, 'YYYY-MM-DD HH24:MI:SS'),
        'updated_at', to_char(v_target.updated_at, 'YYYY-MM-DD HH24:MI:SS'));
end $function$;

CREATE OR REPLACE FUNCTION public.delete_calendar(p_id bigint)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
    v_me bigint := fn_my_user_id();
    v_role user_role;
    v_home bigint;
begin
    if v_me is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    -- 1.8 (§2.2/§2.3): lock del hogar primero → ACL tras el lock (for share) → owner → permiso
    v_home := fn_home_of_calendar(p_id);
    if v_home is null then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    perform fn_home_write_lock(v_home);
    select role into v_role from calendar_user where calendar_id = p_id and user_id = v_me for share;
    if v_role is null then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    if v_role <> 'owner' or not fn_has_permission(v_home, 'calendar.manage') then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    delete from calendar where id = p_id;
    return '{"success":true}'::json;
end $function$;

CREATE OR REPLACE FUNCTION public.delete_task_list(p_id bigint)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
    v_me bigint := fn_my_user_id();
    v_role user_role;
    v_home bigint;
begin
    if v_me is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    -- 1.8 (§2.2/§2.3): lock del hogar primero → ACL tras el lock (for share) → owner → permiso
    v_home := fn_home_of_task_list(p_id);
    if v_home is null then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    perform fn_home_write_lock(v_home);
    select role into v_role from task_list_user where task_list_id = p_id and user_id = v_me for share;
    if v_role is null then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    if v_role <> 'owner' or not fn_has_permission(v_home, 'tasklist.manage') then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    delete from task_list where id = p_id;
    return '{"success":true}'::json;
end $function$;

CREATE OR REPLACE FUNCTION public.remove_calendar_user(p_calendar_id bigint, p_user_id bigint)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
    v_me bigint := fn_my_user_id();
    v_role user_role;
    v_home bigint;
begin
    if v_me is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    -- 1.8 (§2.2/§2.3): lock → ACL → último owner (403) → self (400) → owner (403) →
    -- calendar.manage (403). El último owner va ANTES del self: su autoretiro recibe 403 (M14) y
    -- el de un owner con reemplazo sigue recibiendo 400 (contrato, R1-07).
    v_home := fn_home_of_calendar(p_calendar_id);
    if v_home is null then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    perform fn_home_write_lock(v_home);
    select role into v_role from calendar_user where calendar_id = p_calendar_id and user_id = v_me for share;
    if v_role is null then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    if exists (select 1 from calendar_user
               where calendar_id = p_calendar_id and user_id = p_user_id and role = 'owner')
       and not exists (select 1 from calendar_user
                       where calendar_id = p_calendar_id and role = 'owner' and user_id <> p_user_id) then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    if p_user_id = v_me then
        raise exception 'User cannot remove themselves' using errcode = 'P0001';
    end if;
    if v_role <> 'owner' or not fn_has_permission(v_home, 'calendar.manage') then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    delete from calendar_user where calendar_id = p_calendar_id and user_id = p_user_id;
    return '{"status":"ok"}'::json;
end $function$;

CREATE OR REPLACE FUNCTION public.remove_task_list_user(p_task_list_id bigint, p_user_id bigint)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
    v_me bigint := fn_my_user_id();
    v_role user_role;
    v_home bigint;
begin
    if v_me is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    -- 1.8 (§2.2/§2.3): lock → ACL → último owner (403) → self (400) → owner (403) →
    -- tasklist.manage (403). El último owner va ANTES del self (M14).
    v_home := fn_home_of_task_list(p_task_list_id);
    if v_home is null then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    perform fn_home_write_lock(v_home);
    select role into v_role from task_list_user where task_list_id = p_task_list_id and user_id = v_me for share;
    if v_role is null then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    if exists (select 1 from task_list_user
               where task_list_id = p_task_list_id and user_id = p_user_id and role = 'owner')
       and not exists (select 1 from task_list_user
                       where task_list_id = p_task_list_id and role = 'owner' and user_id <> p_user_id) then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    if p_user_id = v_me then
        raise exception 'User cannot remove themselves' using errcode = 'P0001';
    end if;
    if v_role <> 'owner' or not fn_has_permission(v_home, 'tasklist.manage') then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    delete from task_list_user where task_list_id = p_task_list_id and user_id = p_user_id;
    return '{"status":"ok"}'::json;
end $function$;

CREATE OR REPLACE FUNCTION public.update_home_member(p_id bigint, p_kind text, p_name text, p_color text, p_status text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
    v_me bigint := fn_my_user_id();
    v_home bigint;
    v_linked bigint;
    v_kind text;
    v_name_cur text;
    v_color_cur text;
    v_status text;
    v_kind_new text;
    v_status_new text;
    v_name_new text;
    v_color_new text;
begin
    if v_me is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    select hm.home_id, hm.app_user_id, hm.kind::text, hm.name, hm.color, hm.status::text
      into v_home, v_linked, v_kind, v_name_cur, v_color_cur, v_status
      from home_member hm where hm.id = p_id for update;
    if not found then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    if fn_active_home_id() is not null and fn_active_home_id() <> v_home then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    perform fn_require_permission(v_home, 'home.members.manage');
    v_kind_new := coalesce(p_kind, v_kind);
    v_status_new := coalesce(p_status, v_status);
    if v_kind_new not in ('adult', 'child', 'relative', 'guest', 'pet')
       or v_status_new not in ('active', 'inactive') then
        raise exception 'Invalid member' using errcode = 'P0001';
    end if;
    if v_kind_new = 'pet' and v_linked is not null then
        raise exception 'Invalid member' using errcode = 'P0001';
    end if;
    select f.v_name, f.v_color into v_name_new, v_color_new
      from fn_validate_person_fields(coalesce(p_name, v_name_cur), coalesce(p_color, v_color_cur)) f;
    update home_member
       set kind = v_kind_new::member_kind, name = v_name_new, color = v_color_new,
           status = v_status_new::member_status, updated_at = (now() at time zone 'UTC')
     where id = p_id
       and (kind::text, name, color, status::text)
           is distinct from (v_kind_new, v_name_new, v_color_new, v_status_new);
    update person set name = v_name_new, color = v_color_new, updated_at = (now() at time zone 'UTC')
     where home_member_id = p_id and (name, color) is distinct from (v_name_new, v_color_new);
    return fn_home_member_json(p_id);
end $function$;

commit;
