-- 0041_task_due_at.sql — change fecha-limite-vencimiento (tarjeta [10]): fecha límite opcional en tareas.
--
-- * Columna task.due_at timestamp nullable (naive, en UTC, como completed_at). Sin default: sin fecha = null.
--   No hay CHECK con priority: la prioridad decide si el cliente avisa (solo alta), no el servidor.
-- * Nueva RPC task_due_set(p_id, p_due_at, p_clear_due): fija o borra la fecha. p_due_at en texto
--   'YYYY-MM-DD HH24:MI:SS' (UTC); p_clear_due = true la borra. Valor no parseable → 'Invalid due_at'
--   (P0001 → 400 en la Edge). Mismas reglas de acceso que update_task (0039): validación → lock del hogar →
--   ACL → task.edit; oculta o sin acceso → 'Not Found'. Devuelve get_task_detail.
--   update_task NO cambia de firma: la cadena de rollbacks LIFO (0035–0039) depende de su firma de 4
--   argumentos. Un cambio de firma aquí rompe esas guardas.
-- * get_tasks y get_task_detail devuelven la clave 'due_at' (UTC naive, mismo formato que completed_at).
--   Mismas firmas: create or replace conserva los grants.
-- * Cuerpos base (última definición vigente, sin otros cambios):
--     get_tasks(boolean,bigint,boolean,text,text)   0039_task_hidden_at.sql:57-105
--     get_task_detail(bigint)                       0039_task_hidden_at.sql:107-137
--   Cada línea añadida lleva `-- 0041:`.
-- Rollback: scripts/supabase/rollback/rollback_0041.sql (restaura get_tasks y get_task_detail de 0039, quita
-- task_due_set y la columna; solo se pierden las fechas). Orden LIFO: rollback_0041 → rollback_0040 → … .

begin;

-- 0041: columna
alter table task add column due_at timestamp; -- 0041:

-- get_tasks: cuerpo de 0039_task_hidden_at.sql:57-105 + due_at en la fila y en el json.
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
            'due_at', t.due_at, -- 0041:
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
               to_char(tk.due_at, 'YYYY-MM-DD HH24:MI:SS') as due_at, -- 0041:
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

-- get_task_detail: cuerpo de 0039_task_hidden_at.sql:107-137 + due_at.
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
            'due_at', to_char(t.due_at, 'YYYY-MM-DD HH24:MI:SS'), -- 0041:
            'task_list_color', tl.color, 'task_list_name', tl.name,
            'persons', coalesce(fn_task_persons(t.id), '[]'::json))
        from task t
        inner join task_list tl on tl.id = t.task_list_id
        where t.id = p_id
    );
end $$;

-- 0041: fijar o borrar la fecha límite de una tarea. Mismas reglas de acceso que update_task (0039).
create or replace function task_due_set(p_id bigint, p_due_at text default null, p_clear_due boolean default false)
returns json -- 0041:
language plpgsql security definer set search_path = public as $$
declare
    v_me bigint := fn_my_user_id();
    v_list bigint;
    v_home bigint;
    v_role user_role;
    v_due timestamp;
begin
    if v_me is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    -- Fecha: p_clear_due gana; si no, p_due_at es obligatorio y debe ser un timestamp válido.
    if not p_clear_due then
        begin
            v_due := p_due_at::timestamp;
        exception when others then
            raise exception 'Invalid due_at' using errcode = 'P0001';
        end;
    end if;
    -- validación → lock (hogar de la tarea) → ACL → task.edit, como update_task (0039)
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
    update task set due_at = case when p_clear_due then null else v_due end
    where id = p_id;
    return get_task_detail(p_id);
end $$;

revoke execute on function task_due_set(bigint, text, boolean) from public, anon; -- 0041:
grant execute on function task_due_set(bigint, text, boolean) to authenticated; -- 0041:

commit;

notify pgrst, 'reload schema';
