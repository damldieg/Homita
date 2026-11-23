-- rollback_0041.sql — Revierte 0041_task_due_at.sql (change fecha-limite-vencimiento, tarjeta [10]).
-- Orden en prod: primero la Edge anterior (sin p_due_at en PATCH /task) y, antes de ejecutar esto, export
-- SELECT-only de (id, due_at) y confirmación del usuario: se pierden las fechas límite (no hay otro dato).
-- Quita la RPC task_due_set, restaura get_tasks y get_task_detail con los cuerpos literales de
-- 0039_task_hidden_at.sql (líneas 57-105 y 107-137) y quita la columna due_at. update_task no cambió en 0041.
-- Sin guarda automática: el rollback se ejecuta a mano tras el export y la confirmación indicados arriba.
-- supabase_migrations.schema_migrations: la fila '0041' no se borra aquí.

begin;

-- task_due_set fuera (0041).
drop function if exists task_due_set(bigint, text, boolean);

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
                   -- 0037: con p_sort = 'priority', alta > media > baja; si no, sin efecto (constante)
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
        -- 1.8 (§3.3): visibilidad ACL ∪ admin (Q1)
        left join task_list_user tlu on tlu.task_list_id = tk.task_list_id and tlu.user_id = fn_my_user_id()
        where tk.task_list_id in (select fn_visible_task_list_ids())
          and (p_task_list_id is null or p_task_list_id = 0 or tk.task_list_id = p_task_list_id)
          and (p_widget is null or tlu.widget = p_widget)
          and (p_dashboard is null or tlu.dashboard = p_dashboard)
          -- 0037: filtro opcional por prioridad
          and (p_priority is null or tk.priority = p_priority)
          and (tk.hidden_at is null or tk.hidden_at > now()) -- 0039: fuera las ocultas
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
    if exists (select 1 from task t where t.id = p_id and t.hidden_at is not null and t.hidden_at <= now()) then -- 0039:
        raise exception 'Not Found' using errcode = 'P0002'; -- 0039: oculta, como inexistente
    end if; -- 0039:
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

-- Quita la columna (y con ella las fechas límite).
alter table task drop column if exists due_at;

commit;

notify pgrst, 'reload schema';
