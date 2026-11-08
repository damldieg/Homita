-- 0006_write_rpcs.sql — RPC de escritura de la app gestora (control-api, D-008 contrato (a)).
--
-- Seguridad: una RPC por operación, `security definer set search_path = public`, guardia primera
-- línea `fn_my_user_id() is null` → 'Not Allowed' (42501), rol leído en la propia RPC
-- (`select role from calendar_user|task_list_user where … and user_id = fn_my_user_id()`),
-- REVOKE a public, anon; GRANT a authenticated. Sin DML directo para `authenticated` (0002).
--
-- Errores de la RPC (mensajes exactos PHP; la Edge los mapea a status):
-- * 'Not Found' (P0002) = selectOneOrFail de PHP (Database.php:56) → 500 en Edge.
-- * 'Not Allowed' (42501) = owner-only (desviación Q5, matriz §3) → 403 en Edge.
-- * 'User cannot remove themselves' (P0001) → 400 en Edge (CalendarUserDelete.php:21).
-- Validaciones de campos (400) viven en la Edge salvo person (orden PHP: lookup antes de validar,
-- PersonUpdate.php:12-13), que valida aquí tras el lookup.
--
-- Escrituras que materializan rutinas usan fn_materialize_one (0007, definida después; resuelta
-- en runtime). service_role NO se usa aquí.
--
-- Nota de orden SQLite (Task::reorderByList, Task.php:252-272): ROW_NUMBER con CASE por sort;
-- desempate por id (SQLite ordena empates por rowid). created_at/updated_at = (now() at time zone
-- 'UTC') (R1-07).

-- Token de calendar/task_list: PHP strtoupper(bin2hex(random_bytes(4))) (8 hex mayúsculas).
create or replace function fn_new_token() returns text
language plpgsql security definer set search_path = public as $$
declare
    v_token text;
begin
    loop
        v_token := upper(substr(md5(random()::text), 1, 8));
        exit when not exists (select 1 from calendar where token = v_token)
               and not exists (select 1 from task_list where token = v_token);
    end loop;
    return v_token;
end $$;

-- Task::reorderByList (Task.php:252-272): renumera `order` 1..n por sort de la lista.
create or replace function fn_reorder_tasks(p_task_list_id bigint) returns void
language plpgsql security definer set search_path = public as $$
begin
    update task t
    set "order" = ranked.rn
    from (
        select t2.id, row_number() over (
            order by case when tl.sort = 'title' then t2.title end asc,
                     case when tl.sort in ('updated_at', 'custom') then t2.updated_at end desc,
                     t2.id
        ) as rn
        from task t2
        inner join task_list tl on tl.id = t2.task_list_id
        where t2.task_list_id = p_task_list_id
    ) ranked
    where t.id = ranked.id and t.task_list_id = p_task_list_id;
end $$;

-- Routine::syncAlarms (Routine.php:139-143) para una rutina: upsert event_user de todos los
-- miembros del calendario de sus eventos futuros (routine_event_alarm por fecha > routine_user).
create or replace function fn_sync_routine_alarms(p_routine_id bigint, p_now text) returns void
language plpgsql security definer set search_path = public as $$
begin
    insert into event_user (event_id, user_id, alarm)
    select e.id, cu.user_id, case when rea.user_id is not null then rea.alarm else ru.alarm end
    from event e
    inner join (select distinct calendar_id, user_id from calendar_user) cu on cu.calendar_id = e.calendar_id
    left join routine_user ru on ru.routine_id = e.routine_id and ru.user_id = cu.user_id
    left join routine_event_alarm rea
        on rea.routine_id = e.routine_id and rea.routine_date = e.routine_date and rea.user_id = cu.user_id
    where e.routine_id = p_routine_id and e.date_at >= p_now::timestamp
    on conflict (event_id, user_id) do update
        set alarm = excluded.alarm, updated_at = (now() at time zone 'UTC')
        where event_user.alarm is distinct from excluded.alarm;
end $$;

-- Person::validate (Person.php:23-29) — solo para person (lookup-then-validate, PersonUpdate).
create or replace function fn_validate_person_fields(p_name text, p_color text, out v_name text, out v_color text)
language plpgsql immutable as $$
begin
    v_name := trim(coalesce(p_name, ''));
    v_color := coalesce(p_color, '');
    if v_name = '' or length(v_name) > 50 then
        raise exception 'Name is required (max 50 characters)' using errcode = 'P0001';
    end if;
    if v_color !~ '^#[0-9A-Fa-f]{6}$' then
        raise exception 'Color must be #RRGGBB' using errcode = 'P0001';
    end if;
    v_color := upper(v_color);
end $$;

-- Person::sync (Person.php:77-81): replace de asignaciones.
create or replace function fn_sync_assignments(p_table text, p_column text, p_id bigint, p_person_ids jsonb)
returns void language plpgsql security definer set search_path = public as $$
begin
    execute format('delete from %I where %I = $1', p_table, p_column) using p_id;
    if jsonb_array_length(p_person_ids) > 0 then
        execute format('insert into %I (%I, person_id) select $1, (value #>> ''{}'')::bigint from jsonb_array_elements($2)', p_table, p_column)
        using p_id, p_person_ids;
    end if;
end $$;

-- EventUser::apply (EventUser.php:13-33): valida alarm (Routine::validateAlarm, línea 18: int ≥ 0
-- o null → 400 `Alarm must be nonnegative minutes or null`) y luego rutina → routine_event_alarm +
-- upsert event_user; manual → alarm null borra event_user, si no upsert (clamp ≥0).
create or replace function fn_apply_event_alarm(
    p_event_id bigint, p_routine_id bigint, p_routine_date date, p_alarm integer, p_user_id bigint
) returns void language plpgsql security definer set search_path = public as $$
begin
    -- Routine::validateAlarm (Routine.php:83-86) vía EventUser::apply:18 (R1-02): alarm negativo
    -- nunca llega al clamp de setAlarm; la Edge lo mapea a 400 (RPC_STATUS en errors.ts)
    if p_alarm is not null and p_alarm < 0 then
        raise exception 'Alarm must be nonnegative minutes or null' using errcode = 'P0001';
    end if;
    if p_routine_id is not null then
        insert into routine_event_alarm (routine_id, routine_date, user_id, alarm)
        values (p_routine_id, p_routine_date, p_user_id, p_alarm)
        on conflict (routine_id, routine_date, user_id) do update set alarm = excluded.alarm;
        insert into event_user (event_id, user_id, alarm)
        values (p_event_id, p_user_id, p_alarm)
        on conflict (event_id, user_id) do update
            set alarm = excluded.alarm, updated_at = (now() at time zone 'UTC');
    elsif p_alarm is null then
        delete from event_user where event_id = p_event_id and user_id = p_user_id;
    else
        insert into event_user (event_id, user_id, alarm)
        values (p_event_id, p_user_id, greatest(0, p_alarm))
        on conflict (event_id, user_id) do update
            set alarm = excluded.alarm, updated_at = (now() at time zone 'UTC');
    end if;
end $$;

-- ─────────────────────────────── person ───────────────────────────────

create or replace function create_person(p_name text, p_color text) returns json
language plpgsql security definer set search_path = public as $$
declare
    v_me bigint := fn_my_user_id();
    v_name text;
    v_color text;
    v_id bigint;
begin
    if v_me is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    select f.v_name, f.v_color into v_name, v_color from fn_validate_person_fields(p_name, p_color) f;
    insert into person (user_id, name, color) values (v_me, v_name, v_color) returning id into v_id;
    return (
        select json_build_object(
            'id', p.id, 'user_id', p.user_id, 'name', p.name, 'color', p.color,
            'created_at', to_char(p.created_at, 'YYYY-MM-DD HH24:MI:SS'),
            'updated_at', to_char(p.updated_at, 'YYYY-MM-DD HH24:MI:SS'),
            'editable', true)
        from person p where p.id = v_id
    );
end $$;

create or replace function update_person(p_id bigint, p_name text, p_color text) returns json
language plpgsql security definer set search_path = public as $$
declare
    v_me bigint := fn_my_user_id();
    v_name text;
    v_color text;
begin
    if v_me is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    -- Person::findByIdAndOwner → selectOneOrFail: no creador = 500 'Not Found' (paridad A7)
    if not exists (select 1 from person where id = p_id and user_id = v_me) then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    select f.v_name, f.v_color into v_name, v_color from fn_validate_person_fields(p_name, p_color) f;
    update person set name = v_name, color = v_color, updated_at = (now() at time zone 'UTC')
    where id = p_id;
    return (
        select json_build_object(
            'id', p.id, 'user_id', p.user_id, 'name', p.name, 'color', p.color,
            'created_at', to_char(p.created_at, 'YYYY-MM-DD HH24:MI:SS'),
            'updated_at', to_char(p.updated_at, 'YYYY-MM-DD HH24:MI:SS'),
            'editable', true)
        from person p where p.id = p_id
    );
end $$;

create or replace function delete_person(p_id bigint) returns json
language plpgsql security definer set search_path = public as $$
declare
    v_me bigint := fn_my_user_id();
begin
    if v_me is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    if not exists (select 1 from person where id = p_id and user_id = v_me) then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    delete from person where id = p_id;
    return '{"success":true}'::json;
end $$;

-- ─────────────────────────────── task_list ───────────────────────────────

create or replace function create_task_list(
    p_name text, p_color text, p_sort text, p_widget boolean, p_dashboard boolean
) returns json
language plpgsql security definer set search_path = public as $$
declare
    v_me bigint := fn_my_user_id();
    v_id bigint;
begin
    if v_me is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    insert into task_list (name, color, token, sort)
    values (p_name, coalesce(nullif(p_color, ''), '#6923E2'), fn_new_token(), p_sort::task_list_sort)
    returning id into v_id;
    insert into task_list_user (task_list_id, user_id, role, widget, dashboard)
    values (v_id, v_me, 'owner', p_widget, p_dashboard);
    return (
        select json_build_object(
            'id', tl.id, 'name', tl.name, 'color', tl.color, 'token', tl.token, 'sort', tl.sort,
            'created_at', to_char(tl.created_at, 'YYYY-MM-DD HH24:MI:SS'),
            'updated_at', to_char(tl.updated_at, 'YYYY-MM-DD HH24:MI:SS'))
        from task_list tl where tl.id = v_id
    );
end $$;

-- Matriz §3: name/color/sort compartidos → owner (distintos del actual); widget/dashboard →
-- self-row (cualquier rol). Viewer con valores compartidos iguales → solo sus flags.
create or replace function update_task_list(
    p_id bigint, p_name text, p_color text, p_sort text, p_widget boolean, p_dashboard boolean
) returns json
language plpgsql security definer set search_path = public as $$
declare
    v_me bigint := fn_my_user_id();
    v_role user_role;
begin
    if v_me is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    select role into v_role from task_list_user where task_list_id = p_id and user_id = v_me;
    if v_role is null then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    if (p_name, p_color, p_sort) is distinct from (select (name, color, sort::text) from task_list where id = p_id)
       and v_role <> 'owner' then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    update task_list set name = p_name, color = p_color, sort = p_sort::task_list_sort,
                         updated_at = (now() at time zone 'UTC')
    where id = p_id;
    update task_list_user set widget = p_widget, dashboard = p_dashboard
    where task_list_id = p_id and user_id = v_me;
    if p_sort <> 'custom' then
        perform fn_reorder_tasks(p_id);
    end if;
    return (
        select json_build_object(
            'id', tl.id, 'name', tl.name, 'color', tl.color, 'token', tl.token, 'sort', tl.sort,
            'created_at', to_char(tl.created_at, 'YYYY-MM-DD HH24:MI:SS'),
            'updated_at', to_char(tl.updated_at, 'YYYY-MM-DD HH24:MI:SS'))
        from task_list tl where tl.id = p_id
    );
end $$;

create or replace function delete_task_list(p_id bigint) returns json
language plpgsql security definer set search_path = public as $$
declare
    v_me bigint := fn_my_user_id();
    v_role user_role;
begin
    if v_me is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    select role into v_role from task_list_user where task_list_id = p_id and user_id = v_me;
    if v_role is null then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    if v_role <> 'owner' then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    delete from task_list where id = p_id;
    return '{"success":true}'::json;
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

create or replace function complete_task(p_id bigint, p_completed boolean) returns json
language plpgsql security definer set search_path = public as $$
declare
    v_me bigint := fn_my_user_id();
begin
    if v_me is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    if not exists (
        select 1 from task t
        inner join task_list_user tlu on tlu.task_list_id = t.task_list_id and tlu.user_id = v_me
        where t.id = p_id
    ) then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    update task
    set completed_at = case when p_completed then (now() at time zone 'UTC') else null end,
        updated_at = (now() at time zone 'UTC')
    where id = p_id;
    return get_task_detail(p_id);
end $$;

create or replace function delete_task(p_id bigint) returns json
language plpgsql security definer set search_path = public as $$
declare
    v_me bigint := fn_my_user_id();
begin
    if v_me is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    if not exists (
        select 1 from task t
        inner join task_list_user tlu on tlu.task_list_id = t.task_list_id and tlu.user_id = v_me
        where t.id = p_id
    ) then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    delete from task where id = p_id;
    return '{"success":true}'::json;
end $$;

-- ─────────────────────────────── calendar ───────────────────────────────

create or replace function create_calendar(
    p_name text, p_color text, p_widget boolean, p_dashboard boolean
) returns json
language plpgsql security definer set search_path = public as $$
declare
    v_me bigint := fn_my_user_id();
    v_id bigint;
begin
    if v_me is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    insert into calendar (name, color, token) values (p_name, coalesce(p_color, '#6923E2'), fn_new_token())
    returning id into v_id;
    insert into calendar_user (calendar_id, user_id, role, widget, dashboard)
    values (v_id, v_me, 'owner', p_widget, p_dashboard);
    return (
        select json_build_object(
            'id', c.id, 'name', c.name, 'color', c.color, 'token', c.token,
            'created_at', to_char(c.created_at, 'YYYY-MM-DD HH24:MI:SS'),
            'updated_at', to_char(c.updated_at, 'YYYY-MM-DD HH24:MI:SS'))
        from calendar c where c.id = v_id
    );
end $$;

create or replace function update_calendar(
    p_id bigint, p_name text, p_color text, p_widget boolean, p_dashboard boolean
) returns json
language plpgsql security definer set search_path = public as $$
declare
    v_me bigint := fn_my_user_id();
    v_role user_role;
begin
    if v_me is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    select role into v_role from calendar_user where calendar_id = p_id and user_id = v_me;
    if v_role is null then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    if (p_name, p_color) is distinct from (select (name, color) from calendar where id = p_id)
       and v_role <> 'owner' then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    update calendar set name = p_name, color = p_color, updated_at = (now() at time zone 'UTC')
    where id = p_id;
    update calendar_user set widget = p_widget, dashboard = p_dashboard
    where calendar_id = p_id and user_id = v_me;
    return (
        select json_build_object(
            'id', c.id, 'name', c.name, 'color', c.color, 'token', c.token,
            'created_at', to_char(c.created_at, 'YYYY-MM-DD HH24:MI:SS'),
            'updated_at', to_char(c.updated_at, 'YYYY-MM-DD HH24:MI:SS'))
        from calendar c where c.id = p_id
    );
end $$;

create or replace function delete_calendar(p_id bigint) returns json
language plpgsql security definer set search_path = public as $$
declare
    v_me bigint := fn_my_user_id();
    v_role user_role;
begin
    if v_me is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    select role into v_role from calendar_user where calendar_id = p_id and user_id = v_me;
    if v_role is null then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    if v_role <> 'owner' then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    delete from calendar where id = p_id;
    return '{"success":true}'::json;
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

create or replace function delete_event(p_id bigint, p_timezone text) returns json
language plpgsql security definer set search_path = public as $$
declare
    v_me bigint := fn_my_user_id();
    v_routine_id bigint;
    v_routine_date date;
begin
    if v_me is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    -- EventDelete.php:12: materializeForUser ANTES del lookup (interno, sin service_role)
    perform fn_materialize_my_routines(p_timezone);
    select e.routine_id, e.routine_date into v_routine_id, v_routine_date
    from event e where e.id = p_id and e.calendar_id = any (fn_my_calendar_ids());
    if not found then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    -- Event::delete (Event.php:236-242): sesión de rutina → exception cancelled=true
    if v_routine_id is not null then
        insert into routine_exception (routine_id, routine_date, title, date_at, cancelled)
        values (v_routine_id, v_routine_date, null, null, true)
        on conflict (routine_id, routine_date) do update
            set title = excluded.title, date_at = excluded.date_at, cancelled = excluded.cancelled;
    end if;
    delete from event where id = p_id;
    return '{"success":true}'::json;
end $$;

create or replace function set_event_alarm(p_event_id bigint, p_alarm integer, p_timezone text) returns json
language plpgsql security definer set search_path = public as $$
declare
    v_me bigint := fn_my_user_id();
    v_routine_id bigint;
    v_routine_date date;
begin
    if v_me is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    -- EventAlarm.php:13: materializeForUser ANTES del lookup (interno, sin service_role)
    perform fn_materialize_my_routines(p_timezone);
    select e.routine_id, e.routine_date into v_routine_id, v_routine_date
    from event e where e.id = p_event_id and e.calendar_id = any (fn_my_calendar_ids());
    if not found then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    perform fn_apply_event_alarm(p_event_id, v_routine_id, v_routine_date, p_alarm, v_me);
    return get_event_detail(p_event_id);
end $$;

-- ─────────────────────────────── routine ───────────────────────────────
-- (materializan vía fn_materialize_one de 0007: create/update; syncAlarms vía
-- fn_sync_routine_alarms: alarm)

create or replace function create_routine(
    p_calendar_id bigint, p_title text, p_frequency text, p_interval integer, p_days jsonb,
    p_time text, p_start_date text, p_end_date text, p_active boolean, p_alarm integer,
    p_person_ids jsonb, p_timezone text
) returns json
language plpgsql security definer set search_path = public as $$
declare
    v_me bigint := fn_my_user_id();
    v_now text;
    v_id bigint;
begin
    if v_me is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    if not exists (select 1 from calendar_user where calendar_id = p_calendar_id and user_id = v_me) then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    v_now := to_char(now() at time zone p_timezone, 'YYYY-MM-DD HH24:MI:SS');
    insert into routine (calendar_id, title, frequency, "interval", days, time, start_date, end_date, active, available_from)
    values (p_calendar_id, p_title, p_frequency::routine_frequency, p_interval, p_days, p_time,
            p_start_date::date, p_end_date::date, p_active, v_now::timestamp)
    returning id into v_id;
    insert into routine_user (routine_id, user_id, alarm) values (v_id, v_me, p_alarm);
    if p_person_ids is not null then
        perform fn_sync_assignments('routine_person', 'routine_id', v_id, p_person_ids);
    end if;
    perform fn_materialize_one(v_id, p_timezone, false);
    return get_routine_detail(v_id);
end $$;

create or replace function update_routine(
    p_id bigint, p_title text, p_frequency text, p_interval integer, p_days jsonb,
    p_time text, p_start_date text, p_end_date text, p_active boolean,
    p_person_ids jsonb, p_timezone text
) returns json
language plpgsql security definer set search_path = public as $$
declare
    v_me bigint := fn_my_user_id();
    v_now text;
    v_available timestamp;
    v_active boolean;
begin
    if v_me is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    select active into v_active from routine
    where id = p_id and calendar_id = any (fn_my_calendar_ids());
    if not found then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    v_now := to_char(now() at time zone p_timezone, 'YYYY-MM-DD HH24:MI:SS');
    -- Routine::update (Routine.php:108): available_from = now solo si pasa de inactiva a activa
    v_available := case when not v_active and p_active then v_now::timestamp
                       else (select available_from from routine where id = p_id) end;
    update routine
    set title = p_title, frequency = p_frequency::routine_frequency, "interval" = p_interval,
        days = p_days, time = p_time, start_date = p_start_date::date, end_date = p_end_date::date,
        active = p_active, available_from = v_available, updated_at = (now() at time zone 'UTC')
    where id = p_id;
    if p_person_ids is not null then
        perform fn_sync_assignments('routine_person', 'routine_id', p_id, p_person_ids);
    end if;
    perform fn_materialize_one(p_id, p_timezone, true);
    return get_routine_detail(p_id);
end $$;

create or replace function delete_routine(p_id bigint, p_timezone text) returns json
language plpgsql security definer set search_path = public as $$
declare
    v_me bigint := fn_my_user_id();
    v_now text;
begin
    if v_me is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    if not fn_routine_in_my_calendars(p_id) then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    v_now := to_char(now() at time zone p_timezone, 'YYYY-MM-DD HH24:MI:SS');
    -- Routine::delete (Routine.php:148-156): borra futuros, copia personas al historial,
    -- desvincula historial y borra la rutina
    delete from event where routine_id = p_id and date_at >= v_now::timestamp;
    insert into event_person (event_id, person_id)
    select e.id, rp.person_id
    from event e
    inner join routine_person rp on rp.routine_id = e.routine_id
    where e.routine_id = p_id
    on conflict do nothing;
    update event set routine_id = null, routine_date = null where routine_id = p_id;
    delete from routine where id = p_id;
    return '{"success":true}'::json;
end $$;

create or replace function set_routine_alarm(p_id bigint, p_alarm integer, p_timezone text) returns json
language plpgsql security definer set search_path = public as $$
declare
    v_me bigint := fn_my_user_id();
    v_now text;
begin
    if v_me is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    if not fn_routine_in_my_calendars(p_id) then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    insert into routine_user (routine_id, user_id, alarm) values (p_id, v_me, p_alarm)
    on conflict (routine_id, user_id) do update set alarm = excluded.alarm;
    v_now := to_char(now() at time zone p_timezone, 'YYYY-MM-DD HH24:MI:SS');
    perform fn_sync_routine_alarms(p_id, v_now);
    return get_routine_detail(p_id);
end $$;

-- Grants: helpers internos NO ejecutables por clientes (los ejecuta el owner dentro del definer);
-- RPCs de escritura solo para authenticated.
revoke execute on function fn_new_token() from public, anon, authenticated;
revoke execute on function fn_reorder_tasks(bigint) from public, anon, authenticated;
revoke execute on function fn_sync_routine_alarms(bigint, text) from public, anon, authenticated;
revoke execute on function fn_validate_person_fields(text, text) from public, anon, authenticated;
revoke execute on function fn_sync_assignments(text, text, bigint, jsonb) from public, anon, authenticated;
revoke execute on function fn_apply_event_alarm(bigint, bigint, date, integer, bigint) from public, anon, authenticated;

revoke execute on function create_person(text, text) from public, anon;
revoke execute on function update_person(bigint, text, text) from public, anon;
revoke execute on function delete_person(bigint) from public, anon;
revoke execute on function create_task_list(text, text, text, boolean, boolean) from public, anon;
revoke execute on function update_task_list(bigint, text, text, text, boolean, boolean) from public, anon;
revoke execute on function delete_task_list(bigint) from public, anon;
revoke execute on function create_task(bigint, text) from public, anon;
revoke execute on function update_task(bigint, text) from public, anon;
revoke execute on function complete_task(bigint, boolean) from public, anon;
revoke execute on function delete_task(bigint) from public, anon;
revoke execute on function create_calendar(text, text, boolean, boolean) from public, anon;
revoke execute on function update_calendar(bigint, text, text, boolean, boolean) from public, anon;
revoke execute on function delete_calendar(bigint) from public, anon;
revoke execute on function create_event(bigint, text, text, integer, jsonb) from public, anon;
revoke execute on function update_event(bigint, text, text, integer, jsonb, text) from public, anon;
revoke execute on function delete_event(bigint, text) from public, anon;
revoke execute on function set_event_alarm(bigint, integer, text) from public, anon;
revoke execute on function create_routine(bigint, text, text, integer, jsonb, text, text, text, boolean, integer, jsonb, text) from public, anon;
revoke execute on function update_routine(bigint, text, text, integer, jsonb, text, text, text, boolean, jsonb, text) from public, anon;
revoke execute on function delete_routine(bigint, text) from public, anon;
revoke execute on function set_routine_alarm(bigint, integer, text) from public, anon;

grant execute on function create_person(text, text) to authenticated;
grant execute on function update_person(bigint, text, text) to authenticated;
grant execute on function delete_person(bigint) to authenticated;
grant execute on function create_task_list(text, text, text, boolean, boolean) to authenticated;
grant execute on function update_task_list(bigint, text, text, text, boolean, boolean) to authenticated;
grant execute on function delete_task_list(bigint) to authenticated;
grant execute on function create_task(bigint, text) to authenticated;
grant execute on function update_task(bigint, text) to authenticated;
grant execute on function complete_task(bigint, boolean) to authenticated;
grant execute on function delete_task(bigint) to authenticated;
grant execute on function create_calendar(text, text, boolean, boolean) to authenticated;
grant execute on function update_calendar(bigint, text, text, boolean, boolean) to authenticated;
grant execute on function delete_calendar(bigint) to authenticated;
grant execute on function create_event(bigint, text, text, integer, jsonb) to authenticated;
grant execute on function update_event(bigint, text, text, integer, jsonb, text) to authenticated;
grant execute on function delete_event(bigint, text) to authenticated;
grant execute on function set_event_alarm(bigint, integer, text) to authenticated;
grant execute on function create_routine(bigint, text, text, integer, jsonb, text, text, text, boolean, integer, jsonb, text) to authenticated;
grant execute on function update_routine(bigint, text, text, integer, jsonb, text, text, text, boolean, jsonb, text) to authenticated;
grant execute on function delete_routine(bigint, text) to authenticated;
grant execute on function set_routine_alarm(bigint, integer, text) to authenticated;
