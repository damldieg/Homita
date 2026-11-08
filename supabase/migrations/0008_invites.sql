-- 0008_invites.sql — Invitación/retirada por email (calendar/user, task-list/user) (control-api).
--
-- Matriz §3: M + owner (viewer → 'Not Allowed' 42501 → 403 en Edge, desviación Q5). Retirada:
-- M → S ('User cannot remove themselves' → 400) → O ('Not Allowed' → 403). Búsqueda de usuario
-- por email replicando PHP User::findByEmail (Q6): no existe → 'Not Found' (P0002) = 500 en Edge;
-- nunca se expone auth_uid. El rol insertado es siempre 'viewer' (CalendarUserCreate.php:24).
-- SECURITY DEFINER + REVOKE a public, anon (el lookup por email necesita saltarse app_user_select).

create or replace function add_calendar_user(p_calendar_id bigint, p_email text) returns json
language plpgsql security definer set search_path = public as $$
declare
    v_me bigint := fn_my_user_id();
    v_role user_role;
    v_target app_user%rowtype;
begin
    if v_me is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    select role into v_role from calendar_user where calendar_id = p_calendar_id and user_id = v_me;
    if v_role is null then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    if v_role <> 'owner' then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    select * into v_target from app_user where email = p_email;
    if not found then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    if not exists (select 1 from calendar_user where calendar_id = p_calendar_id and user_id = v_target.id) then
        insert into calendar_user (calendar_id, user_id, role, widget, dashboard)
        values (p_calendar_id, v_target.id, 'viewer', true, true);
    end if;
    return json_build_object(
        'id', v_target.id, 'name', v_target.name, 'email', v_target.email,
        'created_at', to_char(v_target.created_at, 'YYYY-MM-DD HH24:MI:SS'),
        'updated_at', to_char(v_target.updated_at, 'YYYY-MM-DD HH24:MI:SS'));
end $$;

create or replace function remove_calendar_user(p_calendar_id bigint, p_user_id bigint) returns json
language plpgsql security definer set search_path = public as $$
declare
    v_me bigint := fn_my_user_id();
    v_role user_role;
begin
    if v_me is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    select role into v_role from calendar_user where calendar_id = p_calendar_id and user_id = v_me;
    if v_role is null then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    if p_user_id = v_me then
        raise exception 'User cannot remove themselves' using errcode = 'P0001';
    end if;
    if v_role <> 'owner' then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    delete from calendar_user where calendar_id = p_calendar_id and user_id = p_user_id;
    return '{"status":"ok"}'::json;
end $$;

create or replace function add_task_list_user(p_task_list_id bigint, p_email text) returns json
language plpgsql security definer set search_path = public as $$
declare
    v_me bigint := fn_my_user_id();
    v_role user_role;
    v_target app_user%rowtype;
begin
    if v_me is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    select role into v_role from task_list_user where task_list_id = p_task_list_id and user_id = v_me;
    if v_role is null then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    if v_role <> 'owner' then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    select * into v_target from app_user where email = p_email;
    if not found then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    if not exists (select 1 from task_list_user where task_list_id = p_task_list_id and user_id = v_target.id) then
        insert into task_list_user (task_list_id, user_id, role, widget, dashboard)
        values (p_task_list_id, v_target.id, 'viewer', true, true);
    end if;
    return json_build_object(
        'id', v_target.id, 'name', v_target.name, 'email', v_target.email,
        'created_at', to_char(v_target.created_at, 'YYYY-MM-DD HH24:MI:SS'),
        'updated_at', to_char(v_target.updated_at, 'YYYY-MM-DD HH24:MI:SS'));
end $$;

create or replace function remove_task_list_user(p_task_list_id bigint, p_user_id bigint) returns json
language plpgsql security definer set search_path = public as $$
declare
    v_me bigint := fn_my_user_id();
    v_role user_role;
begin
    if v_me is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    select role into v_role from task_list_user where task_list_id = p_task_list_id and user_id = v_me;
    if v_role is null then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    if p_user_id = v_me then
        raise exception 'User cannot remove themselves' using errcode = 'P0001';
    end if;
    if v_role <> 'owner' then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    delete from task_list_user where task_list_id = p_task_list_id and user_id = p_user_id;
    return '{"status":"ok"}'::json;
end $$;

revoke execute on function add_calendar_user(bigint, text) from public, anon;
revoke execute on function remove_calendar_user(bigint, bigint) from public, anon;
revoke execute on function add_task_list_user(bigint, text) from public, anon;
revoke execute on function remove_task_list_user(bigint, bigint) from public, anon;
grant execute on function add_calendar_user(bigint, text) to authenticated;
grant execute on function remove_calendar_user(bigint, bigint) to authenticated;
grant execute on function add_task_list_user(bigint, text) to authenticated;
grant execute on function remove_task_list_user(bigint, bigint) to authenticated;
