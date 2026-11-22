-- 0038_task_create_person_access.sql — change asignar-alta-lista (Control iOS, tarjeta [5]):
-- al crear una tarea solo se puede asignar a personas con cuenta y con acceso a la lista.
--
-- * Motivo: el selector de personas del alta (iOS) filtra por cuenta y ACL; el servidor es la única
--   fuente de verdad y rechaza lo que el filtro no deja pasar (A-1 del brief).
-- * P-1: la persona debe tener cuenta (home_member.app_user_id no nulo) y fila en task_list_user de
--   la lista (owner o viewer, con o sin can_edit). Si no, 'Invalid person' P0001 (→ 400 en la Edge,
--   _shared/errors.ts), sin fila en task ni en client_request.
-- * P-2: solo create_task; update_task no cambia.
-- * P-4: el caso offline (persona que pierde el acceso antes del replay) lo resuelve el cliente al
--   reproducir la cola (roster fresco y reenvío con la misma clave); aquí el rechazo es siempre igual.
-- * Base: create_task de 0037_task_priority.sql tal cual, con la MISMA firma de 5 argumentos
--   (bigint, text, jsonb, uuid, text): create or replace, sin drop ni sobrecarga nueva; PostgREST y la
--   Edge no cambian.
-- * Orden de guardas: título → 'Invalid priority' → lock → ACL del llamante → task.create →
--   idempotencia (un reenvío con la misma clave devuelve la tarea existente aunque la persona haya
--   perdido el acceso después) → guarda 0038 (antes de cualquier escritura) → insert →
--   fn_sync_assignments (hogar e inactivos, sin cambios) → fn_reorder_tasks → client_request.
-- * Grants: los de 0037 sobre create_task(bigint, text, jsonb, uuid, text).
-- Rollback: scripts/supabase/rollback/rollback_0038.sql (restaura el cuerpo de 0037; sin datos).
-- Orden LIFO de rollbacks: rollback_0038 → rollback_0037 → rollback_0035.

begin;

-- create_task: cuerpo de 0037_task_priority.sql + guarda de acceso a la lista (0038).
create or replace function create_task(p_task_list_id bigint, p_title text, p_person_ids jsonb default null,
                                       p_client_request_id uuid default null, p_priority text default null) returns json
language plpgsql security definer set search_path = public as $$
declare
    v_me bigint := fn_my_user_id();
    v_id bigint;
    v_home bigint;
    v_role user_role;
    v_kind text;
    v_persons bigint[];
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
    -- 0038: guarda de acceso a la lista. Cada persona debe tener cuenta (home_member.app_user_id) y
    -- fila en task_list_user de esta lista (cualquier rol). Misma validación de forma y mismo error
    -- que fn_sync_assignments (fn_person_ids_array). Antes de escribir: sin fila en task ni en
    -- client_request si se rechaza.
    v_persons := fn_person_ids_array(p_person_ids);
    if v_persons is not null and cardinality(v_persons) > 0 then
        if exists (
            select 1 from unnest(v_persons) as x(person_id)
            where not exists (
                select 1 from person p
                inner join home_member hm on hm.id = p.home_member_id
                inner join task_list_user tlu on tlu.task_list_id = p_task_list_id
                                             and tlu.user_id = hm.app_user_id
                where p.id = x.person_id and hm.app_user_id is not null
            )
        ) then
            raise exception 'Invalid person' using errcode = 'P0001';
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

commit;

notify pgrst, 'reload schema';
