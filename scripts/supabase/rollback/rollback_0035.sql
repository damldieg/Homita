-- rollback_0035.sql — Revierte 0035_client_request_idempotency.sql (change ios-offline-outbox-tareas).
-- Drop de las firmas nuevas de create_task (bigint,text,jsonb,uuid) y create_task_list
-- (text,text,text,boolean,boolean,uuid); restaura verbatim (pg_get_functiondef del reset local
-- 0001–0034) los cuerpos previos (create_task de 0029, create_task_list de 0020) con sus grants;
-- drop de la tabla client_request.
-- Orden en prod: revertir antes la Edge (deja de enviar p_client_request_id) y después la BD.
-- Datos: se pierden solo las claves de idempotencia; los recursos creados se conservan. Tras el
-- rollback, un create reintentado puede duplicar.
-- supabase_migrations.schema_migrations: la fila '0035' no se borra aquí.
-- SOLO SIN 0037 (orden LIFO): con 0037 aplicada, create_task es (bigint,text,jsonb,uuid,text), el drop
-- de arriba no hace nada y el CREATE de 3 argumentos dejaría dos sobrecargas que la llamada de la Edge
-- no puede desambiguar (POST /task/create → 500). Revertir antes 0037 (rollback_0037.sql). La guarda
-- del principio aborta la transacción si 0037 sigue aplicada (R1-02 de prioridad-tarea).

begin;

do $$
begin
    if exists (select 1 from information_schema.columns
               where table_schema = 'public' and table_name = 'task' and column_name = 'priority')
       or exists (select 1 from pg_proc where pronamespace = 'public'::regnamespace
                   and proname in ('create_task', 'update_task', 'get_tasks') and 'p_priority' = any(proargnames)) then
        raise exception 'rollback_0035: 0037 está aplicada; revertir antes 0037 (rollback_0037.sql, orden LIFO)';
    end if;
end $$;

drop function if exists create_task(bigint, text, jsonb, uuid);
drop function if exists create_task_list(text, text, text, boolean, boolean, uuid);

CREATE OR REPLACE FUNCTION public.create_task(p_task_list_id bigint, p_title text, p_person_ids jsonb DEFAULT NULL::jsonb)
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
    insert into task (task_list_id, title) values (p_task_list_id, p_title) returning id into v_id;
    if p_person_ids is not null then
        perform fn_sync_assignments('task_person', 'task_id', v_id, p_person_ids);
    end if;
    perform fn_reorder_tasks(p_task_list_id);
    return get_task_detail(v_id);
end $function$
;

CREATE OR REPLACE FUNCTION public.create_task_list(p_name text, p_color text, p_sort text, p_widget boolean, p_dashboard boolean)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
    v_me bigint := fn_my_user_id();
    v_home bigint;
    v_id bigint;
begin
    if v_me is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    v_home := fn_home_for_root_create();
    -- 1.8 (§3.1): alta raíz — solo lock del hogar (miembro basta, Q2); sin ACL ni permiso
    perform fn_home_write_lock(v_home);
    insert into task_list (name, color, token, sort, home_id)
    values (p_name, coalesce(nullif(p_color, ''), '#6923E2'), fn_new_token(), p_sort::task_list_sort, v_home)
    returning id into v_id;
    insert into task_list_user (task_list_id, user_id, role, widget, dashboard, home_id)
    values (v_id, v_me, 'owner', p_widget, p_dashboard, v_home);
    return (
        select json_build_object(
            'id', tl.id, 'name', tl.name, 'color', tl.color, 'token', tl.token, 'sort', tl.sort,
            'created_at', to_char(tl.created_at, 'YYYY-MM-DD HH24:MI:SS'),
            'updated_at', to_char(tl.updated_at, 'YYYY-MM-DD HH24:MI:SS'),
            'home_id', tl.home_id)
        from task_list tl where tl.id = v_id
    );
end $function$
;

revoke execute on function create_task(bigint, text, jsonb) from public, anon;
grant execute on function create_task(bigint, text, jsonb) to authenticated;
revoke execute on function create_task_list(text, text, text, boolean, boolean) from public, anon;
grant execute on function create_task_list(text, text, text, boolean, boolean) to authenticated;

drop table if exists client_request;

commit;

notify pgrst, 'reload schema';
