-- 0005_read_rpcs.sql — RPC de lectura de la app gestora (control-api, D-008 contrato (a)).
--
-- Seguridad (R1-01): TODAS son `security definer set search_path = public`, sin depender de RLS
-- para el filtro de tenant:
-- * Guardia primera línea: `fn_my_user_id() is null` → 'Not Allowed' (42501).
-- * Filtro explícito de membresía: calendar/event/routine → fn_my_calendar_ids();
--   task_list/task → fn_my_task_list_ids(); person → fn_family_user_ids() (= Person::VISIBLE).
-- * Fallo de membresía en rutas con id → 'Not Found' (P0002), como selectOneOrFail de PHP
--   (Database.php:56 → 500 {"error":"Not Found"}).
-- * REVOKE EXECUTE FROM public, anon; GRANT EXECUTE TO authenticated.
-- Formato PHP: fechas 'YYYY-MM-DD HH24:MI:SS' (to_char), flags widget/dashboard como 0/1 int,
-- `active`/`editable` como bool JSON, `alarm` int|null, `days` array de ints.
-- Orden de arrays = orden SQLite BINARY → collate "C"; person por nombre NOCASE (translate ASCII,
-- misma técnica que fn_event_persons de 0003).

-- Persons embebido de rutinas (Person::byRoutine, Person.php:105-114: sin filtro de visibilidad,
-- paridad PHP). Misma técnica definer que fn_event_persons (0003): solo responde de rutinas
-- visibles para el llamante (guardia de calendario propio).
create or replace function fn_routine_persons(p_routine_id bigint) returns json
language sql stable security definer set search_path = public as $$
    select coalesce((
        select json_agg(json_build_object('id', p.id, 'user_id', p.user_id, 'name', p.name, 'color', p.color)
            order by translate(p.name, 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', 'abcdefghijklmnopqrstuvwxyz'), p.id)
        from routine_person rp
        inner join person p on p.id = rp.person_id
        where rp.routine_id = p_routine_id
          and fn_routine_in_my_calendars(p_routine_id)
    ), '[]'::json)
$$;

-- Forma PHP de user/update (User.php:findById → {id,name,email,created_at,updated_at}, sin token).
create or replace function get_user_me() returns json
language plpgsql stable security definer set search_path = public as $$
begin
    if fn_my_user_id() is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    return (
        select json_build_object(
            'id', u.id, 'name', u.name, 'email', u.email,
            'created_at', to_char(u.created_at, 'YYYY-MM-DD HH24:MI:SS'),
            'updated_at', to_char(u.updated_at, 'YYYY-MM-DD HH24:MI:SS'))
        from app_user u where u.id = fn_my_user_id()
    );
end $$;

-- Calendar::findByUser (Calendar.php:106-120): filas del usuario con widget/dashboard 0/1 y
-- upcoming_event_count (eventos manuales futuros; CURRENT_TIMESTAMP de SQLite = UTC).
create or replace function get_calendars() returns json
language plpgsql stable security definer set search_path = public as $$
begin
    if fn_my_user_id() is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    return (
        select coalesce(json_agg(json_build_object(
            'id', c.id, 'name', c.name, 'color', c.color, 'token', c.token,
            'created_at', to_char(c.created_at, 'YYYY-MM-DD HH24:MI:SS'),
            'updated_at', to_char(c.updated_at, 'YYYY-MM-DD HH24:MI:SS'),
            'widget', cu.widget::int, 'dashboard', cu.dashboard::int,
            'upcoming_event_count', coalesce(ec.cnt, 0)
        ) order by c.name collate "C"), '[]'::json)
        from calendar c
        inner join calendar_user cu on cu.calendar_id = c.id and cu.user_id = fn_my_user_id()
        left join lateral (
            select count(*) as cnt from event e
            where e.calendar_id = c.id and e.routine_id is null
              and e.date_at >= (now() at time zone 'UTC')
        ) ec on true
    );
end $$;

-- CalendarUser::findUsersByCalendar (CalendarUser.php:171-180): cu_id, orden role/name BINARY.
create or replace function get_calendar_users(p_calendar_id bigint) returns json
language plpgsql stable security definer set search_path = public as $$
begin
    if fn_my_user_id() is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    if not exists (select 1 from calendar_user where calendar_id = p_calendar_id and user_id = fn_my_user_id()) then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    return (
        select coalesce(json_agg(json_build_object(
            'cu_id', cu.id, 'user_id', u.id, 'name', u.name, 'email', u.email, 'role', cu.role
        ) order by (cu.role::text) collate "C", u.name collate "C"), '[]'::json)
        from calendar_user cu
        inner join app_user u on u.id = cu.user_id
        where cu.calendar_id = p_calendar_id
    );
end $$;

-- TaskList::findByUser (TaskList.php:127-142): widget/dashboard 0/1 + pending_task_count.
create or replace function get_task_lists() returns json
language plpgsql stable security definer set search_path = public as $$
begin
    if fn_my_user_id() is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    return (
        select coalesce(json_agg(json_build_object(
            'id', tl.id, 'name', tl.name, 'color', tl.color, 'token', tl.token, 'sort', tl.sort,
            'created_at', to_char(tl.created_at, 'YYYY-MM-DD HH24:MI:SS'),
            'updated_at', to_char(tl.updated_at, 'YYYY-MM-DD HH24:MI:SS'),
            'widget', tlu.widget::int, 'dashboard', tlu.dashboard::int,
            'pending_task_count', coalesce(pc.cnt, 0)
        ) order by tl.name collate "C"), '[]'::json)
        from task_list tl
        inner join task_list_user tlu on tlu.task_list_id = tl.id and tlu.user_id = fn_my_user_id()
        left join lateral (
            select count(*) as cnt from task t
            where t.task_list_id = tl.id and t.completed_at is null
        ) pc on true
    );
end $$;

-- TaskListUser::findUsersByTaskList (TaskListUser.php:155-163): TODOS los miembros de la lista
-- (también co-miembros que solo comparten lista; app_user_select RLS no los ve, por eso definer).
-- Paridad PHP, no fuga nueva (R1-01).
create or replace function get_task_list_users(p_task_list_id bigint) returns json
language plpgsql stable security definer set search_path = public as $$
begin
    if fn_my_user_id() is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    if not exists (select 1 from task_list_user where task_list_id = p_task_list_id and user_id = fn_my_user_id()) then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    return (
        select coalesce(json_agg(json_build_object(
            'tlu_id', tlu.id, 'user_id', u.id, 'name', u.name, 'email', u.email, 'role', tlu.role
        ) order by (tlu.role::text) collate "C", u.name collate "C"), '[]'::json)
        from task_list_user tlu
        inner join app_user u on u.id = tlu.user_id
        where tlu.task_list_id = p_task_list_id
    );
end $$;

-- Person::findVisibleForUser (Person.php:38-40, VISIBLE :20): propio + co-miembros de calendario,
-- orden name COLLATE NOCASE + editable (bool, PersonControllerAbstract.php:25).
create or replace function get_persons() returns json
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
            'editable', p.user_id = fn_my_user_id()
        ) order by translate(p.name, 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', 'abcdefghijklmnopqrstuvwxyz'), p.id), '[]'::json)
        from person p
        where p.user_id = any (fn_family_user_ids())
    );
end $$;

-- Routine::findByUser (Routine.php:124, SELECT :103): r.* + calendar_name/color + alarm del
-- usuario + persons embebidos. Sin filtro de activas (PHP tampoco).
create or replace function get_routines() returns json
language plpgsql stable security definer set search_path = public as $$
begin
    if fn_my_user_id() is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    return (
        select coalesce(json_agg(json_build_object(
            'id', r.id, 'calendar_id', r.calendar_id, 'title', r.title, 'days', r.days,
            'time', r.time,
            'start_date', to_char(r.start_date, 'YYYY-MM-DD'),
            'end_date', to_char(r.end_date, 'YYYY-MM-DD'),
            'active', r.active,
            'available_from', to_char(r.available_from, 'YYYY-MM-DD HH24:MI:SS'),
            'frequency', r.frequency, 'interval', r."interval",
            'created_at', to_char(r.created_at, 'YYYY-MM-DD HH24:MI:SS'),
            'updated_at', to_char(r.updated_at, 'YYYY-MM-DD HH24:MI:SS'),
            'calendar_name', c.name, 'calendar_color', c.color,
            'alarm', ru.alarm,
            'persons', coalesce(fn_routine_persons(r.id), '[]'::json)
        ) order by r.title collate "C", r.id), '[]'::json)
        from routine r
        inner join calendar c on c.id = r.calendar_id
        left join routine_user ru on ru.routine_id = r.id and ru.user_id = fn_my_user_id()
        where r.calendar_id = any (fn_my_calendar_ids())
    );
end $$;

-- Routine::findByIdAndUser (Routine.php:105): misma fila que get_routines para una rutina.
create or replace function get_routine_detail(p_id bigint) returns json
language plpgsql stable security definer set search_path = public as $$
begin
    if fn_my_user_id() is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    if not fn_routine_in_my_calendars(p_id) then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    return (
        select json_build_object(
            'id', r.id, 'calendar_id', r.calendar_id, 'title', r.title, 'days', r.days,
            'time', r.time,
            'start_date', to_char(r.start_date, 'YYYY-MM-DD'),
            'end_date', to_char(r.end_date, 'YYYY-MM-DD'),
            'active', r.active,
            'available_from', to_char(r.available_from, 'YYYY-MM-DD HH24:MI:SS'),
            'frequency', r.frequency, 'interval', r."interval",
            'created_at', to_char(r.created_at, 'YYYY-MM-DD HH24:MI:SS'),
            'updated_at', to_char(r.updated_at, 'YYYY-MM-DD HH24:MI:SS'),
            'calendar_name', c.name, 'calendar_color', c.color,
            'alarm', ru.alarm,
            'persons', coalesce(fn_routine_persons(r.id), '[]'::json))
        from routine r
        inner join calendar c on c.id = r.calendar_id
        left join routine_user ru on ru.routine_id = r.id and ru.user_id = fn_my_user_id()
        where r.id = p_id
    );
end $$;

-- Event::findByIdAndUser (Event.php:196-208): e.* + alarm del usuario + persons. SIN
-- calendar_color/calendar_name (solo el índice los incluye, Event.php:104-106).
create or replace function get_event_detail(p_id bigint) returns json
language plpgsql stable security definer set search_path = public as $$
begin
    if fn_my_user_id() is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    if not fn_event_in_my_calendars(p_id) then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    return (
        select json_build_object(
            'id', e.id, 'calendar_id', e.calendar_id, 'title', e.title,
            'date_at', to_char(e.date_at, 'YYYY-MM-DD HH24:MI:SS'),
            'created_at', to_char(e.created_at, 'YYYY-MM-DD HH24:MI:SS'),
            'updated_at', to_char(e.updated_at, 'YYYY-MM-DD HH24:MI:SS'),
            'routine_id', e.routine_id,
            'routine_date', to_char(e.routine_date, 'YYYY-MM-DD'),
            'alarm', eu.alarm,
            'persons', coalesce(fn_event_persons(e.id), '[]'::json))
        from event e
        left join event_user eu on eu.event_id = e.id and eu.user_id = fn_my_user_id()
        where e.id = p_id
    );
end $$;

-- Task::findByIdAndUser (Task.php:183-198): t.* + task_list_color/name.
create or replace function get_task_detail(p_id bigint) returns json
language plpgsql stable security definer set search_path = public as $$
begin
    if fn_my_user_id() is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    if not exists (
        select 1 from task t
        inner join task_list_user tlu on tlu.task_list_id = t.task_list_id and tlu.user_id = fn_my_user_id()
        where t.id = p_id
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
            'task_list_color', tl.color, 'task_list_name', tl.name)
        from task t
        inner join task_list tl on tl.id = t.task_list_id
        where t.id = p_id
    );
end $$;

-- Grants (R1-01): solo authenticated.
revoke execute on function fn_routine_persons(bigint) from public, anon;
revoke execute on function get_user_me() from public, anon;
revoke execute on function get_calendars() from public, anon;
revoke execute on function get_calendar_users(bigint) from public, anon;
revoke execute on function get_task_lists() from public, anon;
revoke execute on function get_task_list_users(bigint) from public, anon;
revoke execute on function get_persons() from public, anon;
revoke execute on function get_routines() from public, anon;
revoke execute on function get_routine_detail(bigint) from public, anon;
revoke execute on function get_event_detail(bigint) from public, anon;
revoke execute on function get_task_detail(bigint) from public, anon;
grant execute on function fn_routine_persons(bigint) to authenticated, service_role;
grant execute on function get_user_me() to authenticated, service_role;
grant execute on function get_calendars() to authenticated, service_role;
grant execute on function get_calendar_users(bigint) to authenticated, service_role;
grant execute on function get_task_lists() to authenticated, service_role;
grant execute on function get_task_list_users(bigint) to authenticated, service_role;
grant execute on function get_persons() to authenticated, service_role;
grant execute on function get_routines() to authenticated, service_role;
grant execute on function get_routine_detail(bigint) to authenticated, service_role;
grant execute on function get_event_detail(bigint) to authenticated, service_role;
grant execute on function get_task_detail(bigint) to authenticated, service_role;
