-- rollback_0038.sql — Revierte 0038_task_create_person_access.sql (change asignar-alta-lista).
-- create or replace de create_task(bigint,text,jsonb,uuid,text) con el cuerpo de 0037 verbatim
-- (pg_get_functiondef del reset local 0001–0037) y los mismos grants de 5 argumentos. Quita solo la
-- guarda de acceso a la lista (marcador `0038:`); la firma, la prioridad y la idempotencia siguen.
-- Idempotente: se puede aplicar dos veces. No toca datos (las filas de task_person se conservan).
--
-- Orden en prod: solo BD (la Edge no cambia con 0038). Tras el rollback, una persona sin cuenta o sin
-- acceso a la lista vuelve a poder asignarse al crear (como antes de 0038).
-- supabase_migrations.schema_migrations: la fila '0038' no se borra aquí (mismo criterio que 0035/0037).
-- Orden LIFO: este script va ANTES de rollback_0037.sql (rollback_0038 → rollback_0037 → rollback_0035).
-- La guarda del principio aborta si create_task(bigint,text,jsonb,uuid,text) no existe (0037 ya
-- revertida): un create or replace de 5 argumentos dejaría entonces dos sobrecargas de create_task.

begin;

do $$
begin
    if to_regprocedure('public.create_task(bigint,text,jsonb,uuid,text)') is null then
        raise exception 'rollback_0038: no existe create_task(bigint,text,jsonb,uuid,text) (¿0037 revertida?); nada que revertir sin 0037 (orden LIFO)';
    end if;
end $$;

CREATE OR REPLACE FUNCTION public.create_task(p_task_list_id bigint, p_title text, p_person_ids jsonb DEFAULT NULL::jsonb, p_client_request_id uuid DEFAULT NULL::uuid, p_priority text DEFAULT NULL::text)
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
end $function$
;

revoke execute on function create_task(bigint, text, jsonb, uuid, text) from public, anon;
grant execute on function create_task(bigint, text, jsonb, uuid, text) to authenticated;

commit;

notify pgrst, 'reload schema';
