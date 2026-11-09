-- 0011_persons_cross_tenant_hotfix.sql — Hotfix H0: cierre de la fuga cross-tenant de personas
-- por RPC directa (`.dorch/archive/fase-0-auditorias/validacion-fuga-cross-tenant.md`, 0.2 §5.5,
-- diseño §3.5/§3.5.1, change h0-hotfix-fuga-rpc). `create or replace` de 7 funciones: conserva los
-- grant/revoke existentes (sin grants nuevos).
--
-- * fn_event_persons / fn_routine_persons: `persons` embebido solo con personas visibles
--   (p.user_id = any (fn_family_user_ids()), la regla de get_persons). Cierra la lectura residual
--   de asignaciones contaminadas heredadas.
-- * fn_sync_assignments: barrera de escritura — dos pasadas ANTES de cualquier delete o cast:
--   pasada 1 en jsonb puro (tipo de lista/elementos y rango de id, evita 22P02/22023/22003) y
--   pasada 2 con cast ::bigint seguro (solo filas nuevas: la persona debe ser visible; si no,
--   'Invalid person' P0001 → 400 en la Edge vía RPC_STATUS). Orden vinculante del plan: un p_id
--   ajeno falla antes con 'Not Found' (membresía/lookup) que evalúa fn_sync_assignments — sin
--   oráculo cross-tenant — y un raise revierte también el insert/update previo (transacción única).
-- * create_event / update_event / create_task / update_task: validación de título/fecha (espejo de
--   phpEmpty e inputDateHour de la Edge) con los mensajes exactos de usecases/events.ts:91,116 y
--   usecases/tasks.ts:56,65, ANTES de la membresía (y antes de fn_materialize_my_routines en
--   update_event: sin efectos secundarios si falla).

-- R1-13 (0003) + H0: personas embebidas solo con las visibles para el llamante (familia).
create or replace function fn_event_persons(p_event_id bigint) returns json
language sql stable security definer set search_path = public as $$
    select coalesce((
        select json_agg(json_build_object('id', p.id, 'user_id', p.user_id, 'name', p.name, 'color', p.color)
            order by translate(p.name, 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', 'abcdefghijklmnopqrstuvwxyz'), p.id)
        from (
            select ep.person_id
            from event_person ep
            where e.routine_id is null and ep.event_id = e.id
            union
            select rp.person_id
            from routine_person rp
            where rp.routine_id = e.routine_id
        ) x
        inner join person p on p.id = x.person_id and p.user_id = any (fn_family_user_ids())
    ), '[]'::json)
    from event e
    where e.id = p_event_id
      and e.calendar_id = any (fn_my_calendar_ids())
$$;

-- Person::byRoutine (0005) + H0: igual filtro de familia en el join.
create or replace function fn_routine_persons(p_routine_id bigint) returns json
language sql stable security definer set search_path = public as $$
    select coalesce((
        select json_agg(json_build_object('id', p.id, 'user_id', p.user_id, 'name', p.name, 'color', p.color)
            order by translate(p.name, 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', 'abcdefghijklmnopqrstuvwxyz'), p.id)
        from routine_person rp
        inner join person p on p.id = rp.person_id and p.user_id = any (fn_family_user_ids())
        where rp.routine_id = p_routine_id
          and fn_routine_in_my_calendars(p_routine_id)
    ), '[]'::json)
$$;

-- Person::sync (Person.php:77-81) + H0: valida antes de borrar/insertar (dos pasadas, R1-02).
create or replace function fn_sync_assignments(p_table text, p_column text, p_id bigint, p_person_ids jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare
    v_bad boolean;
begin
    -- Pasada 1 (solo jsonb, sin cast): la lista es un array de enteros positivos en rango bigint
    if p_person_ids is not null then
        if jsonb_typeof(p_person_ids) <> 'array' then
            raise exception 'Invalid person' using errcode = 'P0001';
        end if;
        if exists (
            select 1 from jsonb_array_elements(p_person_ids) e
            where jsonb_typeof(e) <> 'number'
               or (e #>> '{}') !~ '^[1-9][0-9]{0,17}$'
        ) then
            raise exception 'Invalid person' using errcode = 'P0001';
        end if;
    end if;
    -- Pasada 2 (cast ::bigint seguro): solo filas nuevas; la persona debe existir y ser visible
    if p_person_ids is not null then
        execute format(
            'select exists (select 1 from jsonb_array_elements($1) e' ||
            ' where not exists (select 1 from %I t where t.%I = $2 and t.person_id = (e #>> ''{}'')::bigint)' ||
            ' and not exists (select 1 from person p where p.id = (e #>> ''{}'')::bigint' ||
            ' and p.user_id = any (fn_family_user_ids())))',
            p_table, p_column)
        into v_bad using p_person_ids, p_id;
        if v_bad then
            raise exception 'Invalid person' using errcode = 'P0001';
        end if;
    end if;
    execute format('delete from %I where %I = $1', p_table, p_column) using p_id;
    if jsonb_array_length(p_person_ids) > 0 then
        execute format('insert into %I (%I, person_id) select $1, (value #>> ''{}'')::bigint from jsonb_array_elements($2)', p_table, p_column)
        using p_id, p_person_ids;
    end if;
end $$;

-- ─────────────────────────────── task ───────────────────────────────

create or replace function create_task(p_task_list_id bigint, p_title text) returns json
language plpgsql security definer set search_path = public as $$
declare
    v_me bigint := fn_my_user_id();
    v_id bigint;
begin
    if v_me is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    -- H0: espejo de phpEmpty (usecases/tasks.ts:56)
    if p_title is null or p_title = '' or p_title = '0' then
        raise exception 'task_list_id and title are required' using errcode = 'P0001';
    end if;
    if not exists (select 1 from task_list_user where task_list_id = p_task_list_id and user_id = v_me) then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    insert into task (task_list_id, title) values (p_task_list_id, p_title) returning id into v_id;
    perform fn_reorder_tasks(p_task_list_id);
    return get_task_detail(v_id);
end $$;

create or replace function update_task(p_id bigint, p_title text) returns json
language plpgsql security definer set search_path = public as $$
declare
    v_me bigint := fn_my_user_id();
    v_list bigint;
begin
    if v_me is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    -- H0: espejo de phpEmpty (usecases/tasks.ts:65)
    if p_title is null or p_title = '' or p_title = '0' then
        raise exception 'Task ID and title are required' using errcode = 'P0001';
    end if;
    select t.task_list_id into v_list
    from task t
    inner join task_list_user tlu on tlu.task_list_id = t.task_list_id and tlu.user_id = v_me
    where t.id = p_id;
    if v_list is null then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    update task set title = p_title, updated_at = (now() at time zone 'UTC') where id = p_id;
    perform fn_reorder_tasks(v_list);
    return get_task_detail(p_id);
end $$;

-- ─────────────────────────────── event ───────────────────────────────

create or replace function create_event(
    p_calendar_id bigint, p_title text, p_date_at text, p_alarm integer, p_person_ids jsonb
) returns json
language plpgsql security definer set search_path = public as $$
declare
    v_me bigint := fn_my_user_id();
    v_id bigint;
begin
    if v_me is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    -- H0: espejo de phpEmpty (null, '', '0') e inputDateHour (usecases/events.ts:91)
    if p_title is null or p_title = '' or p_title = '0'
       or p_date_at is null or p_date_at !~ '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$' then
        raise exception 'Title and date_at are required if text is not provided' using errcode = 'P0001';
    end if;
    if not exists (select 1 from calendar_user where calendar_id = p_calendar_id and user_id = v_me) then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    insert into event (calendar_id, title, date_at)
    values (p_calendar_id, p_title, p_date_at::timestamp) returning id into v_id;
    perform fn_apply_event_alarm(v_id, null, null, p_alarm, v_me);
    if p_person_ids is not null then
        perform fn_sync_assignments('event_person', 'event_id', v_id, p_person_ids);
    end if;
    return get_event_detail(v_id);
end $$;

create or replace function update_event(
    p_id bigint, p_title text, p_date_at text, p_alarm integer, p_person_ids jsonb, p_timezone text
) returns json
language plpgsql security definer set search_path = public as $$
declare
    v_me bigint := fn_my_user_id();
    v_routine_id bigint;
    v_routine_date date;
begin
    if v_me is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    -- H0: título/fecha ANTES de fn_materialize_my_routines (sin efectos si falla;
    -- usecases/events.ts:116)
    if p_title is null or p_title = '' or p_title = '0'
       or p_date_at is null or p_date_at !~ '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$' then
        raise exception 'Event ID, title, and date_at are required' using errcode = 'P0001';
    end if;
    -- EventUpdate.php:14: materializeForUser ANTES del lookup (interno, sin service_role)
    perform fn_materialize_my_routines(p_timezone);
    select e.routine_id, e.routine_date into v_routine_id, v_routine_date
    from event e where e.id = p_id and e.calendar_id = any (fn_my_calendar_ids());
    if not found then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    -- Event::update (Event.php:221-227): sesión de rutina → routine_exception antes de escribir
    if v_routine_id is not null then
        insert into routine_exception (routine_id, routine_date, title, date_at, cancelled)
        values (v_routine_id, v_routine_date, p_title, p_date_at::timestamp, false)
        on conflict (routine_id, routine_date) do update
            set title = excluded.title, date_at = excluded.date_at, cancelled = excluded.cancelled;
    end if;
    update event set title = p_title, date_at = p_date_at::timestamp, updated_at = (now() at time zone 'UTC')
    where id = p_id;
    perform fn_apply_event_alarm(p_id, v_routine_id, v_routine_date, p_alarm, v_me);
    if p_person_ids is not null then
        perform fn_sync_assignments('event_person', 'event_id', p_id, p_person_ids);
    end if;
    return get_event_detail(p_id);
end $$;
