-- rollback_0038.sql — Revierte 0038_task_create_person_access.sql (change asignar-alta-lista).
-- create or replace de create_task(bigint,text,jsonb,uuid,text) con el cuerpo de 0037 verbatim
-- (pg_get_functiondef del reset local 0001–0037) y los mismos grants de 5 argumentos. Quita solo la
-- guarda de acceso a la lista (marcador `0038:`); la firma, la prioridad y la idempotencia siguen.
-- También restaura get_persons(boolean) a la versión vigente antes de 0038, la de
-- 0028_person_app_user_id.sql (sin la clave 'home_id'; ninguna migración 0029–0037 la redefine), con
-- los mismos grants de 0017 (authenticated y service_role; ni PUBLIC ni anon).
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

-- get_persons de 0028_person_app_user_id.sql verbatim (sin 'home_id').
create or replace function get_persons(p_include_inactive boolean default false) returns json
language plpgsql stable security definer set search_path = public as $$
begin
    if fn_my_user_id() is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    return (
        select coalesce(json_agg(json_build_object(
            'id', p.id, 'user_id', p.user_id, 'name', p.name, 'color', p.color,
            'created_at', to_char(p.created_at, 'YYYY-MM-DD HH24:MI:SS'),
            'updated_at', to_char(p.updated_at, 'YYYY-MM-DD HH24:MI:SS'),
            'editable', p.user_id = fn_my_user_id(),
            'home_member_id', p.home_member_id,
            'kind', hm.kind::text,
            'app_user_id', hm.app_user_id
        ) order by translate(p.name, 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', 'abcdefghijklmnopqrstuvwxyz'), p.id), '[]'::json)
        from person p
        inner join home_member hm on hm.id = p.home_member_id
        -- 1.8 (§3.3, D4/Q-G): personas por HOGAR del llamante (no por familia)
        where p.home_id = any (fn_my_home_ids())
          and (p_include_inactive or hm.status = 'active')
    );
end $$;

revoke all on function get_persons(boolean) from public, anon;
grant execute on function get_persons(boolean) to authenticated, service_role;

commit;

notify pgrst, 'reload schema';
