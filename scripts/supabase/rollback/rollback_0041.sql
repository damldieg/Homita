-- rollback_0041.sql — Revierte 0041_task_due_at.sql (change fecha-limite-vencimiento, tarjeta [10]).
-- Orden en prod: primero la Edge anterior (sin p_due_at en PATCH /task) y, antes de ejecutar esto, export
-- SELECT-only de (id, due_at) y confirmación del usuario: se pierden las fechas límite (no hay otro dato).
-- Restaura get_tasks, get_task_detail y update_task (4 argumentos) con los cuerpos literales de
-- 0039_task_hidden_at.sql (líneas 57-105, 107-137 y 178-226). Quita la columna due_at.
-- Sin guarda automática: el rollback se ejecuta a mano tras el export y la confirmación indicados arriba.
-- supabase_migrations.schema_migrations: la fila '0041' no se borra aquí.

begin;

-- update_task de 6 argumentos fuera; vuelve la de 4 de 0039.
drop function if exists update_task(bigint, text, jsonb, text, text, boolean);

-- get_tasks: cuerpo de 0039_task_hidden_at.sql:57-105 (sin due_at).
create or replace function get_tasks(p_dashboard boolean default null, p_task_list_id bigint default null,
                                     p_widget boolean default null, p_priority text default null,
                                     p_sort text default null) returns json
language sql stable set search_path = public as $$
    select coalesce(
        json_agg(json_build_object(
            'id', t.id,
            'task_list_id', t.task_list_id,
            'task_list_color', t.task_list_color,
            'task_list_name', t.task_list_name,
            'title', t.title,
            'order', t."order",
            'priority', t.priority,
            'completed_at', t.completed_at,
            'created_at', t.created_at,
            'updated_at', t.updated_at,
            'persons', coalesce(fn_task_persons(t.id), '[]'::json)
        ) order by (t.completed_at is not null) asc,
                   case when p_sort = 'priority' then
                       case t.priority when 'alta' then 1 when 'media' then 2 else 3 end
                   else 0 end asc,
                   t."order" asc, t.id asc),
        '[]'::json)
    from (
        select tk.id,
               tk.task_list_id,
               tl.color as task_list_color,
               tl.name as task_list_name,
               tk.title,
               tk."order",
               tk.priority,
               to_char(tk.completed_at, 'YYYY-MM-DD HH24:MI:SS') as completed_at,
               to_char(tk.created_at, 'YYYY-MM-DD HH24:MI:SS') as created_at,
               to_char(tk.updated_at, 'YYYY-MM-DD HH24:MI:SS') as updated_at
        from task tk
        inner join task_list tl on tl.id = tk.task_list_id
        left join task_list_user tlu on tlu.task_list_id = tk.task_list_id and tlu.user_id = fn_my_user_id()
        where tk.task_list_id in (select fn_visible_task_list_ids())
          and (p_task_list_id is null or p_task_list_id = 0 or tk.task_list_id = p_task_list_id)
          and (p_widget is null or tlu.widget = p_widget)
          and (p_dashboard is null or tlu.dashboard = p_dashboard)
          and (p_priority is null or tk.priority = p_priority)
          and (tk.hidden_at is null or tk.hidden_at > now())
    ) t
$$;

-- get_task_detail: cuerpo de 0039_task_hidden_at.sql:107-137 (sin due_at).
create or replace function get_task_detail(p_id bigint) returns json
language plpgsql stable security definer set search_path = public as $$
begin
    if fn_my_user_id() is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    if not exists (
        select 1 from task t
        where t.id = p_id and t.task_list_id in (select fn_visible_task_list_ids())
    ) then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    if exists (select 1 from task t where t.id = p_id and t.hidden_at is not null and t.hidden_at <= now()) then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    return (
        select json_build_object(
            'id', t.id, 'task_list_id', t.task_list_id, 'title', t.title,
            'completed_at', to_char(t.completed_at, 'YYYY-MM-DD HH24:MI:SS'),
            'created_at', to_char(t.created_at, 'YYYY-MM-DD HH24:MI:SS'),
            'updated_at', to_char(t.updated_at, 'YYYY-MM-DD HH24:MI:SS'),
            'order', t."order",
            'priority', t.priority,
            'task_list_color', tl.color, 'task_list_name', tl.name,
            'persons', coalesce(fn_task_persons(t.id), '[]'::json))
        from task t
        inner join task_list tl on tl.id = t.task_list_id
        where t.id = p_id
    );
end $$;

-- update_task de 4 argumentos: cuerpo de 0039_task_hidden_at.sql:178-226.
create or replace function update_task(p_id bigint, p_title text, p_person_ids jsonb default null,
                                       p_priority text default null) returns json
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
    if p_title is null or p_title = '' or p_title = '0' then
        raise exception 'Task ID and title are required' using errcode = 'P0001';
    end if;
    if p_priority is not null and p_priority not in ('alta', 'media', 'baja') then
        raise exception 'Invalid priority' using errcode = 'P0001';
    end if;
    select t.task_list_id into v_list from task t where t.id = p_id
      and (t.hidden_at is null or t.hidden_at > now());
    if v_list is null then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    v_home := fn_home_of_task_list(v_list);
    perform fn_home_write_lock(v_home);
    select role into v_role from task_list_user where task_list_id = v_list and user_id = v_me for share;
    if v_role is null then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    if not fn_task_list_editable(v_list) then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    if not fn_has_permission(v_home, 'task.edit') then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    update task set title = p_title, priority = coalesce(p_priority, priority),
                    updated_at = (now() at time zone 'UTC')
    where id = p_id;
    if p_person_ids is not null then
        perform fn_sync_assignments('task_person', 'task_id', p_id, p_person_ids);
    end if;
    perform fn_reorder_tasks(v_list);
    return get_task_detail(p_id);
end $$;

revoke execute on function update_task(bigint, text, jsonb, text) from public, anon;
grant execute on function update_task(bigint, text, jsonb, text) to authenticated;

-- Quita la columna (y con ella las fechas límite).
alter table task drop column if exists due_at;

commit;

notify pgrst, 'reload schema';
