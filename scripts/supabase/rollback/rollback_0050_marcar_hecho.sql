-- rollback_0050_marcar_hecho.sql — Revierte 0050_marcar_hecho.sql (change dashboard-marcar-hecho).
-- Quita la capacidad de completar de las pantallas (task.complete de sus membresías) y las filas client_request de
-- kind 'task_complete' (se pierde la idempotencia de los toques en cola). La auditoría de pantallas (source: display)
-- se CONSERVA: no se borra nada de audit_log. Restaura complete_task de 0039 y fn_display_link_complete de 0049.
-- Idempotente. La fila '0050' de schema_migrations no se borra aquí.

begin;

delete from client_request where kind = 'task_complete';
alter table client_request drop constraint if exists client_request_kind_check;
alter table client_request add constraint client_request_kind_check
    check (kind in ('task', 'task_list', 'shopping_item', 'meal_shopping_sync', 'meal_plan', 'recipe'));

delete from membership_permission mp
using home_display d, home_membership hm
where mp.home_membership_id = hm.id and hm.home_id = d.home_id and hm.app_user_id = d.app_user_id
  and mp.permission_code = 'task.complete';

drop function if exists complete_task(bigint, boolean, uuid);
drop function if exists fn_is_display_for_list(bigint, bigint);

create or replace function complete_task(p_id bigint, p_completed boolean) returns json
language plpgsql security definer set search_path = public as $$
declare
    v_me bigint := fn_my_user_id();
    v_list bigint;
    v_home bigint;
    v_role user_role;
begin
    if v_me is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    -- 1.8 (§2.2/§2.3): lock (hogar de la tarea) → ACL → task.complete
    select t.task_list_id into v_list from task t where t.id = p_id
      and (t.hidden_at is null or t.hidden_at > now()); -- 0039: una oculta es Not Found
    if v_list is null then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    v_home := fn_home_of_task_list(v_list);
    perform fn_home_write_lock(v_home);
    select role into v_role from task_list_user where task_list_id = v_list and user_id = v_me for share;
    if v_role is null then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    -- 0029 (E2): tope adicional, permiso de edición en el ACL (owner o can_edit)
    if not fn_task_list_editable(v_list) then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    if not fn_has_permission(v_home, 'task.complete') then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    update task
    set completed_at = case when p_completed then (now() at time zone 'UTC') else null end,
        hidden_at = case when p_completed then ((now() at time zone 'UTC') + interval '3 days') at time zone 'UTC' else null end, -- 0039:
        updated_at = (now() at time zone 'UTC')
    where id = p_id;
    return get_task_detail(p_id);
end $$;

revoke execute on function complete_task(bigint, boolean) from public, anon;
grant execute on function complete_task(bigint, boolean) to authenticated;

create or replace function fn_display_link_complete(p_link_id bigint, p_auth_uid uuid, p_session jsonb) returns json
language plpgsql security definer set search_path = public as $$
declare
    v_link home_display_link;
    v_app_user bigint;
    v_membership bigint;
    v_member bigint;
    v_display bigint;
begin
    select * into v_link from home_display_link where id = p_link_id for update;
    if not found or v_link.claimed_at is null or v_link.display_id is not null then
        raise exception 'Not Found';
    end if;
    select id into v_app_user from app_user where auth_uid = p_auth_uid;
    if v_app_user is null then raise exception 'Not Found'; end if;

    insert into home_membership (home_id, app_user_id, role)
    values (v_link.home_id, v_app_user, 'member')
    returning id into v_membership;
    insert into home_member (home_id, kind, name, app_user_id)
    values (v_link.home_id, 'display', v_link.display_name, v_app_user)
    returning id into v_member;
    -- Solo lectura: ver calendarios, tareas y menú, y nada de escritura.
    insert into membership_permission (home_membership_id, permission_code)
    values (v_membership, 'calendar.view'), (v_membership, 'task.view'), (v_membership, 'menu.view');

    insert into home_display (home_id, app_user_id, home_member_id, name, linked_by)
    values (v_link.home_id, v_app_user, v_member, v_link.display_name, v_link.claimed_by)
    returning id into v_display;
    -- Hogar por defecto de la cuenta: las lecturas de la pantalla (menú de hoy) sin cabecera lo usan
    update app_user set default_home_id = v_link.home_id where id = v_app_user and default_home_id is null;

    update home_display_link set display_id = v_display, session = p_session where id = p_link_id;
    return json_build_object('display_id', v_display);
end
$$;

commit;
