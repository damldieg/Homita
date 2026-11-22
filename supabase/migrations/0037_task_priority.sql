-- 0037_task_priority.sql — change prioridad-tarea (D-026, extensión aditiva de D-008 en `task`):
-- cada tarea tiene una prioridad alta, media o baja.
--
-- * Columna `task.priority text not null default 'media'` con `task_priority_check`
--   (alta|media|baja). El default es constante: PG 17 lo resuelve en metadatos, así que las filas
--   existentes quedan en 'media' sin reescribir la tabla y sin tocar `updated_at` (backfill).
-- * get_task_detail(bigint): misma firma, añade la clave 'priority'. create_task, update_task,
--   complete_task y task_order devuelven get_task_detail, así que todas las respuestas la llevan.
-- * get_tasks: DROP de (boolean,bigint,boolean) y CREATE con `p_priority text default null` (filtra
--   si no es nulo; la SQL no valida: un valor fuera de las tres opciones devuelve []) y
--   `p_sort text default null` ('priority' → pendientes primero, alta > media > baja, desempate por
--   "order" e id). Sin p_sort el orden es el de siempre (D-008).
-- * create_task: DROP de (bigint,text,jsonb,uuid) y CREATE con `p_priority text default null` al
--   final (cuerpo de 0035). update_task: DROP de (bigint,text,jsonb) y CREATE con
--   `p_priority text default null` (cuerpo de 0029): null conserva la guardada.
--   Ambas validan la prioridad justo después del título (antes del lock y de la ACL):
--   fuera de alta|media|baja → 'Invalid priority' P0001 (→ 400 en la Edge). El replay idempotente
--   de create_task devuelve la tarea original e ignora el p_priority del reenvío.
-- * Un solo objeto por RPC (PostgREST no admite sobrecargas ambiguas). Las llamadas existentes por
--   nombre o por posición siguen resolviendo gracias a los defaults.
-- Grants: los de 0003 (get_tasks), 0035 (create_task) y 0029 (update_task).
-- Rollback: scripts/supabase/rollback/rollback_0037.sql (borra la columna: se pierden las
-- prioridades; exportar antes `select id, priority from task where priority <> 'media'`).

begin;

-- ─────────────────── (a) Columna ───────────────────

alter table task add column priority text not null default 'media'
    constraint task_priority_check check (priority in ('alta', 'media', 'baja'));

-- ─────────────────── (b) get_task_detail ───────────────────

-- get_task_detail: cuerpo de 0024_task_persons.sql + 'priority'.
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
            'priority', t.priority,
            'task_list_color', tl.color, 'task_list_name', tl.name,
            'persons', coalesce(fn_task_persons(t.id), '[]'::json))
        from task t
        inner join task_list tl on tl.id = t.task_list_id
        where t.id = p_id
    );
end $$;

-- ─────────────────── (c) get_tasks ───────────────────

drop function if exists get_tasks(boolean, bigint, boolean);

-- get_tasks: cuerpo de 0024_task_persons.sql + 'priority', filtro p_priority y orden p_sort.
create function get_tasks(p_dashboard boolean default null::boolean, p_task_list_id bigint default null::bigint,
                          p_widget boolean default null::boolean, p_priority text default null::text,
                          p_sort text default null::text) returns json
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
    ) t
$$;

revoke execute on function get_tasks(boolean, bigint, boolean, text, text) from public, anon;
grant execute on function get_tasks(boolean, bigint, boolean, text, text) to authenticated, service_role;

-- ─────────────────── (d) create_task ───────────────────

drop function if exists create_task(bigint, text, jsonb, uuid);

-- create_task: cuerpo de 0035_client_request_idempotency.sql + p_priority (validación tras el título).
create function create_task(p_task_list_id bigint, p_title text, p_person_ids jsonb default null,
                            p_client_request_id uuid default null, p_priority text default null) returns json
language plpgsql security definer set search_path = public as $$
declare
    v_me bigint := fn_my_user_id();
    v_id bigint;
    v_home bigint;
    v_role user_role;
    v_kind text;
begin
    if v_me is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    -- H0: espejo de phpEmpty (usecases/tasks.ts:56)
    if p_title is null or p_title = '' or p_title = '0' then
        raise exception 'task_list_id and title are required' using errcode = 'P0001';
    end if;
    -- 0037: prioridad opcional (null → 'media'); fuera de las tres opciones → 400 en la Edge
    if p_priority is not null and p_priority not in ('alta', 'media', 'baja') then
        raise exception 'Invalid priority' using errcode = 'P0001';
    end if;
    -- 1.8 (§2.2/§2.3): validación → lock (hogar de la lista) → ACL → task.create
    v_home := fn_home_of_task_list(p_task_list_id);
    if v_home is null then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    perform fn_home_write_lock(v_home);
    select role into v_role from task_list_user
    where task_list_id = p_task_list_id and user_id = v_me for share;
    if v_role is null then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    -- 0029 (E2): tope adicional, permiso de edición en el ACL (owner o can_edit)
    if not fn_task_list_editable(p_task_list_id) then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    if not fn_has_permission(v_home, 'task.create') then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    -- 0035: replay idempotente (misma clave del mismo usuario → mismo recurso, sin insertar)
    if p_client_request_id is not null then
        perform pg_advisory_xact_lock(hashtextextended('client_request:' || v_me || ':' || p_client_request_id::text, 0));
        select cr.kind, cr.resource_id into v_kind, v_id from client_request cr
        where cr.app_user_id = v_me and cr.client_request_id = p_client_request_id;
        if found then
            if v_kind <> 'task' then
                raise exception 'Invalid client_request_id' using errcode = 'P0001';
            end if;
            -- get_task_detail lanza 'Not Found' si la tarea ya no existe o no es visible
            return get_task_detail(v_id);
        end if;
    end if;
    insert into task (task_list_id, title, priority)
    values (p_task_list_id, p_title, coalesce(p_priority, 'media')) returning id into v_id;
    if p_person_ids is not null then
        perform fn_sync_assignments('task_person', 'task_id', v_id, p_person_ids);
    end if;
    perform fn_reorder_tasks(p_task_list_id);
    if p_client_request_id is not null then
        insert into client_request (app_user_id, client_request_id, kind, resource_id)
        values (v_me, p_client_request_id, 'task', v_id);
    end if;
    return get_task_detail(v_id);
end $$;

revoke execute on function create_task(bigint, text, jsonb, uuid, text) from public, anon;
grant execute on function create_task(bigint, text, jsonb, uuid, text) to authenticated;

-- ─────────────────── (e) update_task ───────────────────

drop function if exists update_task(bigint, text, jsonb);

-- update_task: cuerpo de 0029_acl_can_edit.sql + p_priority (null conserva la guardada).
create function update_task(p_id bigint, p_title text, p_person_ids jsonb default null,
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
    -- H0: espejo de phpEmpty (usecases/tasks.ts:65)
    if p_title is null or p_title = '' or p_title = '0' then
        raise exception 'Task ID and title are required' using errcode = 'P0001';
    end if;
    -- 0037: prioridad opcional (null → se conserva); fuera de las tres opciones → 400 en la Edge
    if p_priority is not null and p_priority not in ('alta', 'media', 'baja') then
        raise exception 'Invalid priority' using errcode = 'P0001';
    end if;
    -- 1.8 (§2.2/§2.3): validación → lock (hogar de la tarea) → ACL → task.edit
    select t.task_list_id into v_list from task t where t.id = p_id;
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

commit;

notify pgrst, 'reload schema';
