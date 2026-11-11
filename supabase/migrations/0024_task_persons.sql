-- 0024_task_persons.sql — Personas asignadas a tareas (tarjeta R4hVx8XK, tareas).
-- Aditiva: tabla task_person (espejo de event_person/routine_person), función fn_task_persons con el
-- mismo filtro de visibilidad que las tareas, y redefinición de get_tasks y get_task_detail que solo
-- añade el campo `persons` (el resto de la forma queda igual). Acceso solo por RPC (RLS sin policies,
-- sin privilegios de tabla para anon/authenticated), como las invitaciones (0022).
--
-- Rollback: quitar `persons` de get_tasks/get_task_detail (volver a 0020), drop function
-- fn_task_persons y drop table task_person.

create table if not exists task_person (
    task_id bigint not null references task (id) on delete cascade,
    person_id bigint not null references person (id) on delete cascade,
    primary key (task_id, person_id)
);
create index if not exists task_person_person on task_person (person_id);
alter table task_person enable row level security;
revoke all on table task_person from anon, authenticated;

create or replace function fn_task_persons(p_task_id bigint) returns json
language sql stable security definer set search_path = public as $$
    select coalesce((
        select json_agg(json_build_object('id', p.id, 'user_id', p.user_id, 'name', p.name, 'color', p.color)
            order by translate(p.name, 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', 'abcdefghijklmnopqrstuvwxyz'), p.id)
        from task_person tp
        inner join person p on p.id = tp.person_id
        where tp.task_id = p_task_id
          and exists (
              select 1 from task tk
              where tk.id = p_task_id and tk.task_list_id in (select fn_visible_task_list_ids())
          )
    ), '[]'::json)
$$;
revoke execute on function fn_task_persons(bigint) from public, anon;
grant execute on function fn_task_persons(bigint) to authenticated, service_role;

create or replace function get_tasks(p_dashboard boolean default null::boolean, p_task_list_id bigint default null::bigint, p_widget boolean default null::boolean) returns json
language sql stable set search_path = public as $$
    select coalesce(
        json_agg(json_build_object(
            'id', t.id,
            'task_list_id', t.task_list_id,
            'task_list_color', t.task_list_color,
            'task_list_name', t.task_list_name,
            'title', t.title,
            'order', t."order",
            'completed_at', t.completed_at,
            'created_at', t.created_at,
            'updated_at', t.updated_at,
            'persons', coalesce(fn_task_persons(t.id), '[]'::json)
        ) order by (t.completed_at is not null) asc, t."order" asc, t.id asc),
        '[]'::json)
    from (
        select tk.id,
               tk.task_list_id,
               tl.color as task_list_color,
               tl.name as task_list_name,
               tk.title,
               tk."order",
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
    ) t
$$;

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
    return (
        select json_build_object(
            'id', t.id, 'task_list_id', t.task_list_id, 'title', t.title,
            'completed_at', to_char(t.completed_at, 'YYYY-MM-DD HH24:MI:SS'),
            'created_at', to_char(t.created_at, 'YYYY-MM-DD HH24:MI:SS'),
            'updated_at', to_char(t.updated_at, 'YYYY-MM-DD HH24:MI:SS'),
            'order', t."order",
            'task_list_color', tl.color, 'task_list_name', tl.name,
            'persons', coalesce(fn_task_persons(t.id), '[]'::json))
        from task t
        inner join task_list tl on tl.id = t.task_list_id
        where t.id = p_id
    );
end $$;
