-- 0035_client_request_idempotency.sql — change ios-offline-outbox-tareas (D-024): idempotencia de
-- los creates de tarea y lista para la cola offline de Control iOS.
--
-- * Tabla `client_request(app_user_id, client_request_id uuid, kind, resource_id, created_at)`,
--   PK (app_user_id, client_request_id). La clave es por usuario (no por hogar): no depende de que
--   `task` tenga home_id ni created_by. RLS activada sin policies y sin grants a anon/authenticated:
--   solo se lee y escribe desde las RPC SECURITY DEFINER (mismo patrón que D-014).
-- * create_task y create_task_list ganan `p_client_request_id uuid default null` al final. Cambia la
--   firma: se borra la anterior (como 0025) para no dejar overloads ambiguos en PostgREST. Las
--   llamadas posicionales y por nombre existentes siguen resolviendo gracias al default.
--
-- Semántica con p_client_request_id no nulo, SIEMPRE después de las guardas del alta original
-- (sesión, hogar, lock, ACL y permiso):
--   · pg_advisory_xact_lock sobre (usuario, uuid) → serializa reenvíos concurrentes de la misma clave.
--   · Fila existente con el mismo kind → devuelve el recurso con la misma forma JSON que el alta,
--     sin insertar (la Edge responde 201 igual que el original, D-008). Recurso ya inexistente o no
--     visible → 'Not Found' P0002.
--   · Fila existente con otro kind → 'Invalid client_request_id' P0001 (→ 400 en la Edge).
--   · Sin fila → alta normal + fila en client_request en la misma transacción.
-- Con p_client_request_id null el comportamiento es idéntico al anterior (Android, Edge antigua).
--
-- Cuerpos: create_task de 0029_acl_can_edit.sql y create_task_list de 0020_home_write_guards.sql,
-- con el cambio mínimo.
-- Rollback: scripts/supabase/rollback/rollback_0035.sql.

begin;

-- ─────────────────── (a) Tabla de claves de idempotencia ───────────────────

create table client_request (
    app_user_id bigint not null references app_user (id) on delete cascade,
    client_request_id uuid not null,
    kind text not null check (kind in ('task', 'task_list')),
    resource_id bigint not null,
    created_at timestamptz not null default now(),
    primary key (app_user_id, client_request_id)
);

alter table client_request enable row level security;
revoke all on table client_request from public, anon, authenticated;

-- ─────────────────── (b) create_task ───────────────────

drop function if exists create_task(bigint, text, jsonb);

-- create_task: cuerpo de 0029_acl_can_edit.sql + idempotencia por client_request_id tras las guardas.
create function create_task(p_task_list_id bigint, p_title text, p_person_ids jsonb default null,
                            p_client_request_id uuid default null) returns json
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
end $$;

revoke execute on function create_task(bigint, text, jsonb, uuid) from public, anon;
grant execute on function create_task(bigint, text, jsonb, uuid) to authenticated;

-- ─────────────────── (c) create_task_list ───────────────────

drop function if exists create_task_list(text, text, text, boolean, boolean);

-- create_task_list: cuerpo de 0020_home_write_guards.sql + idempotencia por client_request_id tras
-- el lock del hogar. El replay devuelve el mismo JSON que el alta.
create function create_task_list(p_name text, p_color text, p_sort text, p_widget boolean, p_dashboard boolean,
                                 p_client_request_id uuid default null) returns json
language plpgsql security definer set search_path = public as $$
declare
    v_me bigint := fn_my_user_id();
    v_home bigint;
    v_id bigint;
    v_kind text;
begin
    if v_me is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    v_home := fn_home_for_root_create();
    -- 1.8 (§3.1): alta raíz — solo lock del hogar (miembro basta, Q2); sin ACL ni permiso
    perform fn_home_write_lock(v_home);
    -- 0035: replay idempotente (misma clave del mismo usuario → misma lista, sin insertar)
    if p_client_request_id is not null then
        perform pg_advisory_xact_lock(hashtextextended('client_request:' || v_me || ':' || p_client_request_id::text, 0));
        select cr.kind, cr.resource_id into v_kind, v_id from client_request cr
        where cr.app_user_id = v_me and cr.client_request_id = p_client_request_id;
        if found then
            if v_kind <> 'task_list' then
                raise exception 'Invalid client_request_id' using errcode = 'P0001';
            end if;
            if not exists (select 1 from task_list_user tlu where tlu.task_list_id = v_id and tlu.user_id = v_me) then
                raise exception 'Not Found' using errcode = 'P0002';
            end if;
        end if;
    end if;
    if v_id is null then
        insert into task_list (name, color, token, sort, home_id)
        values (p_name, coalesce(nullif(p_color, ''), '#6923E2'), fn_new_token(), p_sort::task_list_sort, v_home)
        returning id into v_id;
        insert into task_list_user (task_list_id, user_id, role, widget, dashboard, home_id)
        values (v_id, v_me, 'owner', p_widget, p_dashboard, v_home);
        if p_client_request_id is not null then
            insert into client_request (app_user_id, client_request_id, kind, resource_id)
            values (v_me, p_client_request_id, 'task_list', v_id);
        end if;
    end if;
    return (
        select json_build_object(
            'id', tl.id, 'name', tl.name, 'color', tl.color, 'token', tl.token, 'sort', tl.sort,
            'created_at', to_char(tl.created_at, 'YYYY-MM-DD HH24:MI:SS'),
            'updated_at', to_char(tl.updated_at, 'YYYY-MM-DD HH24:MI:SS'),
            'home_id', tl.home_id)
        from task_list tl where tl.id = v_id
    );
end $$;

revoke execute on function create_task_list(text, text, text, boolean, boolean, uuid) from public, anon;
grant execute on function create_task_list(text, text, text, boolean, boolean, uuid) to authenticated;

commit;

notify pgrst, 'reload schema';
