-- rollback_0037.sql — Revierte 0037_task_priority.sql (change prioridad-tarea, D-026).
-- Drop de las firmas nuevas get_tasks(boolean,bigint,boolean,text,text),
-- create_task(bigint,text,jsonb,uuid,text) y update_task(bigint,text,jsonb,text); restaura verbatim
-- (pg_get_functiondef del reset local 0001–0036) get_tasks y get_task_detail (0024), create_task (0035)
-- y update_task (0029) con sus grants; después `drop column if exists priority` (con su CHECK).
-- Idempotente: se puede aplicar dos veces.
--
-- DATOS (N1): se pierden TODAS las prioridades. Antes de un rollback en prod, con confirmación del
-- usuario, exportar en modo SELECT-only `select id, priority from task where priority <> 'media'`
-- (o un pg_dump). Restaurar = UPDATE manual tras reaplicar 0037.
-- Orden en prod (N3): 1) Edge anterior (deja de enviar p_priority/p_sort), 2) export, 3) este script.
-- supabase_migrations.schema_migrations: la fila '0037' no se borra aquí (mismo criterio que 0035).

begin;

drop function if exists get_tasks(boolean, bigint, boolean, text, text);
drop function if exists create_task(bigint, text, jsonb, uuid, text);
drop function if exists update_task(bigint, text, jsonb, text);

CREATE OR REPLACE FUNCTION public.get_task_detail(p_id bigint)
 RETURNS json
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
end $function$
;

CREATE OR REPLACE FUNCTION public.get_tasks(p_dashboard boolean DEFAULT NULL::boolean, p_task_list_id bigint DEFAULT NULL::bigint, p_widget boolean DEFAULT NULL::boolean)
 RETURNS json
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION public.create_task(p_task_list_id bigint, p_title text, p_person_ids jsonb DEFAULT NULL::jsonb, p_client_request_id uuid DEFAULT NULL::uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
    insert into task (task_list_id, title) values (p_task_list_id, p_title) returning id into v_id;
    if p_person_ids is not null then
        perform fn_sync_assignments('task_person', 'task_id', v_id, p_person_ids);
    end if;
    perform fn_reorder_tasks(p_task_list_id);
    if p_client_request_id is not null then
        insert into client_request (app_user_id, client_request_id, kind, resource_id)
        values (v_me, p_client_request_id, 'task', v_id);
    end if;
    return get_task_detail(v_id);
end $function$
;

CREATE OR REPLACE FUNCTION public.update_task(p_id bigint, p_title text, p_person_ids jsonb DEFAULT NULL::jsonb)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
    update task set title = p_title, updated_at = (now() at time zone 'UTC') where id = p_id;
    if p_person_ids is not null then
        perform fn_sync_assignments('task_person', 'task_id', p_id, p_person_ids);
    end if;
    perform fn_reorder_tasks(v_list);
    return get_task_detail(p_id);
end $function$
;

revoke execute on function get_tasks(boolean, bigint, boolean) from public, anon;
grant execute on function get_tasks(boolean, bigint, boolean) to authenticated, service_role;
revoke execute on function create_task(bigint, text, jsonb, uuid) from public, anon;
grant execute on function create_task(bigint, text, jsonb, uuid) to authenticated;
revoke execute on function update_task(bigint, text, jsonb) from public, anon;
grant execute on function update_task(bigint, text, jsonb) to authenticated;

alter table task drop column if exists priority;

commit;

notify pgrst, 'reload schema';
