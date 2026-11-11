-- 0025_task_person_ids.sql — Asignar personas al crear o editar una tarea (tareas con personas, 0024).
-- create_task y update_task ganan `p_person_ids jsonb default null`:
--   · null  → no tocar las personas (en alta, ninguna; en edición, se mantienen).
--   · array → sincroniza task_person con fn_sync_assignments (validación de visibilidad de 0011).
-- Se borran las firmas antiguas (bigint,text) para no dejar overloads ambiguos; el resto del cuerpo
-- es el de 0020 sin cambios. Además, fn_sync_assignments gana la rama task_person (hogar de la tarea).
--
-- Rollback: volver a crear create_task(bigint,text) y update_task(bigint,text) desde 0020.

drop function if exists create_task(bigint, text);
drop function if exists update_task(bigint, text);

create or replace function create_task(p_task_list_id bigint, p_title text, p_person_ids jsonb default null) returns json
language plpgsql security definer set search_path = public as $$
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
    if not fn_has_permission(v_home, 'task.create') then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    insert into task (task_list_id, title) values (p_task_list_id, p_title) returning id into v_id;
    if p_person_ids is not null then
        perform fn_sync_assignments('task_person', 'task_id', v_id, p_person_ids);
    end if;
    perform fn_reorder_tasks(p_task_list_id);
    return get_task_detail(v_id);
end $$;

create or replace function update_task(p_id bigint, p_title text, p_person_ids jsonb default null) returns json
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
    if not fn_has_permission(v_home, 'task.edit') then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    update task set title = p_title, updated_at = (now() at time zone 'UTC') where id = p_id;
    if p_person_ids is not null then
        perform fn_sync_assignments('task_person', 'task_id', p_id, p_person_ids);
    end if;
    perform fn_reorder_tasks(v_list);
    return get_task_detail(p_id);
end $$;

-- fn_sync_assignments (0020) solo conocía event_person y routine_person: para task_person el
-- hogar era NULL y ninguna persona pasaba la validación. Se redefine con la rama de tareas.
create or replace function fn_sync_assignments(p_table text, p_column text, p_id bigint, p_person_ids jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare
    v_bad boolean;
    v_home bigint;
begin
    -- Pasada 1 (0020 §3.2): fn_person_ids_array (extrae la pasada 1 de 0011:61-73, mismos
    -- errores). null no valida aquí: el borrado de null = '[]' de 0015 se conserva.
    perform fn_person_ids_array(p_person_ids);
    -- Pasada 2 (0020 §3.2/§3.4, R1-04/Q-G): solo filas nuevas; la persona debe ser del HOGAR del
    -- recurso (fn_home_of_event/fn_home_of_routine), no de la familia del usuario
    if p_person_ids is not null then
        v_home := case p_table
            when 'event_person' then fn_home_of_event(p_id)
            when 'routine_person' then fn_home_of_routine(p_id)
            when 'task_person' then (select fn_home_of_task_list(t.task_list_id) from task t where t.id = p_id)
        end;
        execute format(
            'select exists (select 1 from jsonb_array_elements($1) e' ||
            ' where not exists (select 1 from %I t where t.%I = $2 and t.person_id = (e #>> ''{}'')::bigint)' ||
            ' and not exists (select 1 from person p where p.id = (e #>> ''{}'')::bigint' ||
            ' and p.home_id = $3))',
            p_table, p_column)
        into v_bad using p_person_ids, p_id, v_home;
        if v_bad then
            raise exception 'Invalid person' using errcode = 'P0001';
        end if;
    end if;
    -- Borrado por diferencia: solo las ausentes de la lista (null = '[]' → borra todo)
    execute format(
        'delete from %I where %I = $1 and person_id <> all' ||
        ' (select (value #>> ''{}'')::bigint from jsonb_array_elements(coalesce($2, ''[]''::jsonb)))',
        p_table, p_column)
    using p_id, p_person_ids;
    -- Inserción solo de nuevas: solo ellas disparan el trigger (iv)
    execute format(
        'insert into %I (%I, person_id) select $1, s.x from' ||
        ' (select (value #>> ''{}'')::bigint as x from jsonb_array_elements(coalesce($2, ''[]''::jsonb))) s' ||
        ' where not exists (select 1 from %I t where t.%I = $1 and t.person_id = s.x)',
        p_table, p_column, p_table, p_column)
    using p_id, p_person_ids;
end $$;

revoke execute on function create_task(bigint, text, jsonb) from public, anon;
revoke execute on function update_task(bigint, text, jsonb) from public, anon;
grant execute on function create_task(bigint, text, jsonb) to authenticated;
grant execute on function update_task(bigint, text, jsonb) to authenticated;
