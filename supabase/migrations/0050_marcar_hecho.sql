-- 0050_marcar_hecho.sql — Pantallas que completan tareas (change dashboard-marcar-hecho, paso 4 de la mejora).
--
-- Decisión 1 (Damian): la pantalla puede completar y descompletar tareas de las listas que enseña, y nada más.
-- Cuerpo de 0039_task_hidden_at.sql (oculta = Not Found, hidden_at al completar) + lo nuevo de 0050.
-- * fn_is_display_for_list: la cuenta es una pantalla activa y la lista está en su selección (0049).
-- * complete_task: una pantalla salta solo la comprobación de edición (owner/can_edit), no la de task.complete ni
--   la de pertenencia al ACL; cualquier otro usuario sigue igual que en 0029. Registra en audit_log que lo hizo la
--   pantalla y es idempotente con p_client_request_id (client_request, kind 'task_complete'): un reenvío con la misma
--   clave devuelve la tarea sin volver a aplicar el cambio.
-- * Las pantallas de 0049 ganan task.complete (membresía); las ya vinculadas se completan con el backfill.
-- Rollback: scripts/supabase/rollback/rollback_0050_marcar_hecho.sql.

alter table client_request drop constraint if exists client_request_kind_check;
-- Mismos kinds que 0048 (shopping_item, meal_shopping_sync, meal_plan, recipe) más el nuevo.
alter table client_request add constraint client_request_kind_check
    check (kind in ('task', 'task_list', 'shopping_item', 'meal_shopping_sync', 'meal_plan', 'recipe', 'task_complete'));

create or replace function fn_is_display_for_list(p_user bigint, p_list bigint) returns boolean
language sql stable security definer set search_path = public as $$
    select exists (
        select 1 from home_display d
        join home_display_task_list t on t.display_id = d.id
        where d.app_user_id = p_user and d.revoked_at is null and t.task_list_id = p_list
    )
$$;

-- Backfill: las pantallas ya vinculadas (0049) ganan task.complete.
insert into membership_permission (home_membership_id, permission_code)
select hm.id, 'task.complete'
from home_display d
join home_membership hm on hm.home_id = d.home_id and hm.app_user_id = d.app_user_id
where d.revoked_at is null
on conflict do nothing;

drop function if exists complete_task(bigint, boolean);
create or replace function complete_task(p_id bigint, p_completed boolean, p_client_request_id uuid default null) returns json
language plpgsql security definer set search_path = public as $$
declare
    v_me bigint := fn_my_user_id();
    v_list bigint;
    v_home bigint;
    v_role user_role;
    v_display boolean;
    v_kind text;
    v_id bigint;
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
    v_display := fn_is_display_for_list(v_me, v_list);
    -- 0029 (E2): tope adicional, permiso de edición en el ACL (owner o can_edit). Una pantalla lo salta: 0050.
    if not v_display and not fn_task_list_editable(v_list) then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    if not fn_has_permission(v_home, 'task.complete') then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    -- Idempotencia (0050): una clave ya usada para completar esta tarea no vuelve a cambiar nada.
    if p_client_request_id is not null then
        perform pg_advisory_xact_lock(hashtextextended('client_request:' || v_me || ':' || p_client_request_id::text, 0));
        select cr.kind, cr.resource_id into v_kind, v_id from client_request cr
        where cr.app_user_id = v_me and cr.client_request_id = p_client_request_id;
        if v_kind is not null then
            if v_kind <> 'task_complete' or v_id <> p_id then
                raise exception 'Invalid client_request_id' using errcode = 'P0001';
            end if;
            return get_task_detail(p_id);
        end if;
    end if;
    update task
    set completed_at = case when p_completed then (now() at time zone 'UTC') else null end,
        hidden_at = case when p_completed then ((now() at time zone 'UTC') + interval '3 days') at time zone 'UTC' else null end, -- 0039
        updated_at = (now() at time zone 'UTC')
    where id = p_id;
    if p_client_request_id is not null then
        insert into client_request (app_user_id, client_request_id, kind, resource_id)
        values (v_me, p_client_request_id, 'task_complete', p_id);
    end if;
    if v_display then
        insert into audit_log (home_id, actor_app_user_id, action, target_type, target_id, payload)
        values (v_home, v_me, case when p_completed then 'task.complete' else 'task.uncomplete' end, 'task', p_id,
                jsonb_build_object('source', 'display', 'task_list_id', v_list));
    end if;
    return get_task_detail(p_id);
end $$;

revoke execute on function complete_task(bigint, boolean, uuid) from public, anon;
grant execute on function complete_task(bigint, boolean, uuid) to authenticated;

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
    -- Solo lectura y completar tareas (0050): nada de crear, editar ni borrar.
    insert into membership_permission (home_membership_id, permission_code)
    values (v_membership, 'calendar.view'), (v_membership, 'task.view'), (v_membership, 'menu.view'),
           (v_membership, 'task.complete');

    insert into home_display (home_id, app_user_id, home_member_id, name, linked_by)
    values (v_link.home_id, v_app_user, v_member, v_link.display_name, v_link.claimed_by)
    returning id into v_display;
    -- Hogar por defecto de la cuenta: las lecturas de la pantalla (menú de hoy) sin cabecera lo usan
    update app_user set default_home_id = v_link.home_id where id = v_app_user and default_home_id is null;

    update home_display_link set display_id = v_display, session = p_session where id = p_link_id;
    return json_build_object('display_id', v_display);
end
$$;
