-- rollback_0020.sql — Reversión de 0020_home_write_guards.sql (fase-1-8-matriz-permisos).
--
-- (a) Las 8 policies de §3.3 vuelven al `using` de 0002_rls.sql; (b) drop de los 10 helpers
-- nuevos; (c) los cuerpos PREVIOS (0001–0019) de todas las funciones redefinidas en 0020,
-- emitidos verbatim desde pg_get_functiondef (md5(prosrc) idéntico al baseline de T1).
-- Válido solo si no hay escrituras de recursos en prod desde el apply de 0020 (§7); la
-- alternativa completa es el volcado de G4. Apply: psql -v ON_ERROR_STOP=1 -1 -f (como G5).

begin;

-- ─────────────────── (a) RLS SELECT: vuelta al `using` de 0002 ───────────────────

drop policy if exists calendar_select on calendar;
create policy calendar_select on calendar for select to authenticated
    using (id = any (fn_my_calendar_ids()));

drop policy if exists task_list_select on task_list;
create policy task_list_select on task_list for select to authenticated
    using (id = any (fn_my_task_list_ids()));

drop policy if exists event_select on event;
create policy event_select on event for select to authenticated
    using (calendar_id = any (fn_my_calendar_ids()));

drop policy if exists routine_select on routine;
create policy routine_select on routine for select to authenticated
    using (calendar_id = any (fn_my_calendar_ids()));

drop policy if exists task_select on task;
create policy task_select on task for select to authenticated
    using (task_list_id = any (fn_my_task_list_ids()));

drop policy if exists event_person_select on event_person;
create policy event_person_select on event_person for select to authenticated
    using (fn_event_in_my_calendars(event_id));

drop policy if exists routine_person_select on routine_person;
create policy routine_person_select on routine_person for select to authenticated
    using (fn_routine_in_my_calendars(routine_id));

drop policy if exists person_select on person;
create policy person_select on person for select to authenticated
    using (user_id = any (fn_family_user_ids()));

-- ─────────────────── (b) Drop de los 10 helpers nuevos ───────────────────

drop function if exists fn_home_write_lock(bigint);
drop function if exists fn_home_of_event(bigint);
drop function if exists fn_home_of_routine(bigint);
drop function if exists fn_person_ids_array(jsonb);
drop function if exists fn_event_assigned_ids(bigint);
drop function if exists fn_routine_assigned_ids(bigint);
drop function if exists fn_visible_calendar_ids();
drop function if exists fn_visible_task_list_ids();
drop function if exists fn_event_visible(bigint);
drop function if exists fn_routine_visible(bigint);

-- ─────────────────── (c) Cuerpos previos (0001–0019) de las funciones redefinidas ───────────────────

CREATE OR REPLACE FUNCTION public.update_calendar(p_id bigint, p_name text, p_color text, p_widget boolean, p_dashboard boolean)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
            'updated_at', to_char(c.updated_at, 'YYYY-MM-DD HH24:MI:SS'),
            'home_id', c.home_id)
        from calendar c where c.id = p_id
    );
end $function$;


CREATE OR REPLACE FUNCTION public.delete_calendar(p_id bigint)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
end $function$;


CREATE OR REPLACE FUNCTION public.add_calendar_user(p_calendar_id bigint, p_email text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
    v_me bigint := fn_my_user_id();
    v_role user_role;
    v_home bigint;
    v_target app_user%rowtype;
begin
    if v_me is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    select role into v_role from calendar_user where calendar_id = p_calendar_id and user_id = v_me;
    if v_role is null then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    if v_role <> 'owner' then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    v_home := fn_home_of_calendar(p_calendar_id);
    if fn_active_home_id() is not null and fn_active_home_id() <> v_home then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    select * into v_target from app_user where email = p_email;
    if not found then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    if not exists (select 1 from home_membership where home_id = v_home and app_user_id = v_target.id) then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    if not exists (select 1 from calendar_user where calendar_id = p_calendar_id and user_id = v_target.id) then
        insert into calendar_user (calendar_id, user_id, role, widget, dashboard, home_id)
        values (p_calendar_id, v_target.id, 'viewer', true, true, v_home);
    end if;
    return json_build_object(
        'id', v_target.id, 'name', v_target.name, 'email', v_target.email,
        'created_at', to_char(v_target.created_at, 'YYYY-MM-DD HH24:MI:SS'),
        'updated_at', to_char(v_target.updated_at, 'YYYY-MM-DD HH24:MI:SS'));
end $function$;


CREATE OR REPLACE FUNCTION public.remove_calendar_user(p_calendar_id bigint, p_user_id bigint)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
    v_me bigint := fn_my_user_id();
    v_role user_role;
begin
    if v_me is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    select role into v_role from calendar_user where calendar_id = p_calendar_id and user_id = v_me;
    if v_role is null then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    if p_user_id = v_me then
        raise exception 'User cannot remove themselves' using errcode = 'P0001';
    end if;
    if v_role <> 'owner' then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    delete from calendar_user where calendar_id = p_calendar_id and user_id = p_user_id;
    return '{"status":"ok"}'::json;
end $function$;


CREATE OR REPLACE FUNCTION public.update_task_list(p_id bigint, p_name text, p_color text, p_sort text, p_widget boolean, p_dashboard boolean)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
            'updated_at', to_char(tl.updated_at, 'YYYY-MM-DD HH24:MI:SS'),
            'home_id', tl.home_id)
        from task_list tl where tl.id = p_id
    );
end $function$;


CREATE OR REPLACE FUNCTION public.delete_task_list(p_id bigint)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
end $function$;


CREATE OR REPLACE FUNCTION public.add_task_list_user(p_task_list_id bigint, p_email text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
    v_me bigint := fn_my_user_id();
    v_role user_role;
    v_home bigint;
    v_target app_user%rowtype;
begin
    if v_me is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    select role into v_role from task_list_user where task_list_id = p_task_list_id and user_id = v_me;
    if v_role is null then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    if v_role <> 'owner' then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    v_home := fn_home_of_task_list(p_task_list_id);
    if fn_active_home_id() is not null and fn_active_home_id() <> v_home then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    select * into v_target from app_user where email = p_email;
    if not found then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    if not exists (select 1 from home_membership where home_id = v_home and app_user_id = v_target.id) then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    if not exists (select 1 from task_list_user where task_list_id = p_task_list_id and user_id = v_target.id) then
        insert into task_list_user (task_list_id, user_id, role, widget, dashboard, home_id)
        values (p_task_list_id, v_target.id, 'viewer', true, true, v_home);
    end if;
    return json_build_object(
        'id', v_target.id, 'name', v_target.name, 'email', v_target.email,
        'created_at', to_char(v_target.created_at, 'YYYY-MM-DD HH24:MI:SS'),
        'updated_at', to_char(v_target.updated_at, 'YYYY-MM-DD HH24:MI:SS'));
end $function$;


CREATE OR REPLACE FUNCTION public.remove_task_list_user(p_task_list_id bigint, p_user_id bigint)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
    v_me bigint := fn_my_user_id();
    v_role user_role;
begin
    if v_me is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    select role into v_role from task_list_user where task_list_id = p_task_list_id and user_id = v_me;
    if v_role is null then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    if p_user_id = v_me then
        raise exception 'User cannot remove themselves' using errcode = 'P0001';
    end if;
    if v_role <> 'owner' then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    delete from task_list_user where task_list_id = p_task_list_id and user_id = p_user_id;
    return '{"status":"ok"}'::json;
end $function$;


CREATE OR REPLACE FUNCTION public.create_event(p_calendar_id bigint, p_title text, p_date_at text, p_alarm integer, p_person_ids jsonb)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
end $function$;


CREATE OR REPLACE FUNCTION public.update_event(p_id bigint, p_title text, p_date_at text, p_alarm integer, p_person_ids jsonb, p_timezone text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
end $function$;


CREATE OR REPLACE FUNCTION public.delete_event(p_id bigint, p_timezone text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
end $function$;


CREATE OR REPLACE FUNCTION public.set_event_alarm(p_event_id bigint, p_alarm integer, p_timezone text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
end $function$;


CREATE OR REPLACE FUNCTION public.create_routine(p_calendar_id bigint, p_title text, p_frequency text, p_interval integer, p_days jsonb, p_time text, p_start_date text, p_end_date text, p_active boolean, p_alarm integer, p_person_ids jsonb, p_timezone text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
end $function$;


CREATE OR REPLACE FUNCTION public.update_routine(p_id bigint, p_title text, p_frequency text, p_interval integer, p_days jsonb, p_time text, p_start_date text, p_end_date text, p_active boolean, p_person_ids jsonb, p_timezone text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
end $function$;


CREATE OR REPLACE FUNCTION public.delete_routine(p_id bigint, p_timezone text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
    inner join person p on p.id = rp.person_id
    inner join home_member hm on hm.id = p.home_member_id and hm.status = 'active'
    where e.routine_id = p_id
    on conflict do nothing;
    update event set routine_id = null, routine_date = null where routine_id = p_id;
    delete from routine where id = p_id;
    return '{"success":true}'::json;
end $function$;


CREATE OR REPLACE FUNCTION public.set_routine_alarm(p_id bigint, p_alarm integer, p_timezone text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
end $function$;


CREATE OR REPLACE FUNCTION public.materialize_routine(p_routine_id bigint, p_timezone text, p_reconcile boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
    if fn_my_user_id() is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    if not fn_routine_in_my_calendars(p_routine_id) then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    perform fn_materialize_one(p_routine_id, p_timezone, p_reconcile);
end $function$;


CREATE OR REPLACE FUNCTION public.create_task(p_task_list_id bigint, p_title text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
end $function$;


CREATE OR REPLACE FUNCTION public.update_task(p_id bigint, p_title text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
end $function$;


CREATE OR REPLACE FUNCTION public.complete_task(p_id bigint, p_completed boolean)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
end $function$;


CREATE OR REPLACE FUNCTION public.task_order(p_id bigint, p_position integer)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
    v_me bigint := fn_my_user_id();
    v_list bigint;
    v_ids bigint[];
    v_rest bigint[];
    v_pos integer;
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
    select coalesce(array_agg(id order by "order", id), array[]::bigint[])
    into v_ids from task where task_list_id = v_list;
    select coalesce(array_agg(id order by ord), array[]::bigint[])
    into v_rest from unnest(v_ids) with ordinality t(id, ord)
    where id <> p_id;
    v_pos := least(greatest(p_position, 0), array_length(v_rest, 1));
    v_rest := (select array_agg(x order by ord) from (
        select elem as x, ord from unnest(v_rest[1:v_pos]) with ordinality t(elem, ord)
        union all
        select p_id, v_pos + 1
        union all
        select elem as x, ord + v_pos + 1 from unnest(v_rest[v_pos + 1:]) with ordinality t(elem, ord)
    ) s);
    for v_pos in 1 .. array_length(v_rest, 1) loop
        update task set "order" = v_pos where id = v_rest[v_pos];
    end loop;
    return get_task_detail(p_id);
end $function$;


CREATE OR REPLACE FUNCTION public.delete_task(p_id bigint)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
end $function$;


CREATE OR REPLACE FUNCTION public.create_calendar(p_name text, p_color text, p_widget boolean, p_dashboard boolean)
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
    if fn_active_home_id() is not null and fn_active_home_id() <> v_home then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    insert into calendar (name, color, token, home_id)
    values (p_name, coalesce(p_color, '#6923E2'), fn_new_token(), v_home)
    returning id into v_id;
    insert into calendar_user (calendar_id, user_id, role, widget, dashboard, home_id)
    values (v_id, v_me, 'owner', p_widget, p_dashboard, v_home);
    return (
        select json_build_object(
            'id', c.id, 'name', c.name, 'color', c.color, 'token', c.token,
            'created_at', to_char(c.created_at, 'YYYY-MM-DD HH24:MI:SS'),
            'updated_at', to_char(c.updated_at, 'YYYY-MM-DD HH24:MI:SS'),
            'home_id', c.home_id)
        from calendar c where c.id = v_id
    );
end $function$;


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
    if fn_active_home_id() is not null and fn_active_home_id() <> v_home then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
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
end $function$;


CREATE OR REPLACE FUNCTION public.get_calendars()
 RETURNS json
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
    if fn_my_user_id() is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    if fn_active_home_id() is not null then
        perform fn_require_member(fn_active_home_id());
    end if;
    return (
        select coalesce(json_agg(json_build_object(
            'id', c.id, 'name', c.name, 'color', c.color, 'token', c.token,
            'created_at', to_char(c.created_at, 'YYYY-MM-DD HH24:MI:SS'),
            'updated_at', to_char(c.updated_at, 'YYYY-MM-DD HH24:MI:SS'),
            'widget', cu.widget::int, 'dashboard', cu.dashboard::int,
            'upcoming_event_count', coalesce(ec.cnt, 0),
            'home_id', c.home_id
        ) order by c.name collate "C"), '[]'::json)
        from calendar c
        inner join calendar_user cu on cu.calendar_id = c.id and cu.user_id = fn_my_user_id()
        left join lateral (
            select count(*) as cnt from event e
            where e.calendar_id = c.id and e.routine_id is null
              and e.date_at >= (now() at time zone 'UTC')
        ) ec on true
        where fn_active_home_id() is null or c.home_id = fn_active_home_id()
    );
end $function$;


CREATE OR REPLACE FUNCTION public.get_task_lists()
 RETURNS json
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
    if fn_my_user_id() is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    if fn_active_home_id() is not null then
        perform fn_require_member(fn_active_home_id());
    end if;
    return (
        select coalesce(json_agg(json_build_object(
            'id', tl.id, 'name', tl.name, 'color', tl.color, 'token', tl.token, 'sort', tl.sort,
            'created_at', to_char(tl.created_at, 'YYYY-MM-DD HH24:MI:SS'),
            'updated_at', to_char(tl.updated_at, 'YYYY-MM-DD HH24:MI:SS'),
            'widget', tlu.widget::int, 'dashboard', tlu.dashboard::int,
            'pending_task_count', coalesce(pc.cnt, 0),
            'home_id', tl.home_id
        ) order by tl.name collate "C"), '[]'::json)
        from task_list tl
        inner join task_list_user tlu on tlu.task_list_id = tl.id and tlu.user_id = fn_my_user_id()
        left join lateral (
            select count(*) as cnt from task t
            where t.task_list_id = tl.id and t.completed_at is null
        ) pc on true
        where fn_active_home_id() is null or tl.home_id = fn_active_home_id()
    );
end $function$;


CREATE OR REPLACE FUNCTION public.get_calendar_users(p_calendar_id bigint)
 RETURNS json
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
    if fn_my_user_id() is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    if not exists (select 1 from calendar_user where calendar_id = p_calendar_id and user_id = fn_my_user_id()) then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    return (
        select coalesce(json_agg(json_build_object(
            'cu_id', cu.id, 'user_id', u.id, 'name', u.name, 'email', u.email, 'role', cu.role,
            'home_role', (select hm.role::text from home_membership hm
                          where hm.home_id = cu.home_id and hm.app_user_id = cu.user_id)
        ) order by (cu.role::text) collate "C", u.name collate "C"), '[]'::json)
        from calendar_user cu
        inner join app_user u on u.id = cu.user_id
        where cu.calendar_id = p_calendar_id
    );
end $function$;


CREATE OR REPLACE FUNCTION public.get_task_list_users(p_task_list_id bigint)
 RETURNS json
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
    if fn_my_user_id() is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    if not exists (select 1 from task_list_user where task_list_id = p_task_list_id and user_id = fn_my_user_id()) then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    return (
        select coalesce(json_agg(json_build_object(
            'tlu_id', tlu.id, 'user_id', u.id, 'name', u.name, 'email', u.email, 'role', tlu.role,
            'home_role', (select hm.role::text from home_membership hm
                          where hm.home_id = tlu.home_id and hm.app_user_id = tlu.user_id)
        ) order by (tlu.role::text) collate "C", u.name collate "C"), '[]'::json)
        from task_list_user tlu
        inner join app_user u on u.id = tlu.user_id
        where tlu.task_list_id = p_task_list_id
    );
end $function$;


CREATE OR REPLACE FUNCTION public.get_events(p_start_date text DEFAULT NULL::text, p_end_date text DEFAULT NULL::text, p_routine boolean DEFAULT NULL::boolean, p_timezone text DEFAULT NULL::text, p_dashboard boolean DEFAULT NULL::boolean, p_calendar_id bigint DEFAULT NULL::bigint, p_person_id bigint DEFAULT NULL::bigint, p_search text DEFAULT NULL::text, p_limit integer DEFAULT NULL::integer, p_offset integer DEFAULT NULL::integer, p_order_mode text DEFAULT NULL::text, p_widget boolean DEFAULT NULL::boolean)
 RETURNS json
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
    select coalesce(
        json_agg(json_build_object(
            'id', ev.id,
            'calendar_id', ev.calendar_id,
            'routine_id', ev.routine_id,
            'routine_date', ev.routine_date,
            'calendar_color', ev.calendar_color,
            'calendar_name', ev.calendar_name,
            'title', ev.title,
            'date_at', ev.date_at,
            'alarm', ev.alarm,
            'persons', ev.persons,
            'created_at', ev.created_at,
            'updated_at', ev.updated_at
        ) order by (case when upper(coalesce(p_order_mode, '')) = 'DESC' then ev.date_at end) desc,
                   (case when upper(coalesce(p_order_mode, '')) = 'DESC' then null else ev.date_at end) asc,
                   ev.id asc),
        '[]'::json)
    from (
        select e.id,
               e.calendar_id,
               e.routine_id,
               to_char(e.routine_date, 'YYYY-MM-DD') as routine_date,
               c.color as calendar_color,
               c.name as calendar_name,
               e.title,
               to_char(e.date_at, 'YYYY-MM-DD HH24:MI:SS') as date_at,
               eu.alarm,
               coalesce(fn_event_persons(e.id), '[]'::json) as persons,
               to_char(e.created_at, 'YYYY-MM-DD HH24:MI:SS') as created_at,
               to_char(e.updated_at, 'YYYY-MM-DD HH24:MI:SS') as updated_at
        from event e
        inner join calendar_user cu on cu.calendar_id = e.calendar_id
        inner join calendar c on c.id = e.calendar_id
        left join event_user eu on eu.event_id = e.id and eu.user_id = cu.user_id
        where cu.user_id = fn_my_user_id()
          and (p_calendar_id is null or p_calendar_id = 0 or e.calendar_id = p_calendar_id)
          and (p_search is null or e.title ilike '%' || p_search || '%')
          and (p_start_date is null or e.date_at >= p_start_date::timestamp)
          and (p_end_date is null or e.date_at <= p_end_date::timestamp)
          and (p_widget is null or cu.widget = p_widget)
          and (p_dashboard is null or cu.dashboard = p_dashboard)
          and (p_routine is null or (e.routine_id is not null) = p_routine)
          and (p_person_id is null or p_person_id = 0 or
               exists (select 1 from event_person ep2 where e.routine_id is null and ep2.event_id = e.id and ep2.person_id = p_person_id)
            or exists (select 1 from routine_person rp2 where rp2.routine_id = e.routine_id and rp2.person_id = p_person_id))
        order by (case when upper(coalesce(p_order_mode, '')) = 'DESC' then e.date_at end) desc,
                 (case when upper(coalesce(p_order_mode, '')) = 'DESC' then null else e.date_at end) asc,
                 e.id asc
        limit case when p_limit > 0 then p_limit end
        offset case when p_offset > 0 then p_offset end
    ) ev
$function$;


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
            'updated_at', t.updated_at
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
        inner join task_list_user tlu on tlu.task_list_id = tk.task_list_id and tlu.user_id = fn_my_user_id()
        where (p_task_list_id is null or p_task_list_id = 0 or tk.task_list_id = p_task_list_id)
          and (p_widget is null or tlu.widget = p_widget)
          and (p_dashboard is null or tlu.dashboard = p_dashboard)
    ) t
$function$;


CREATE OR REPLACE FUNCTION public.get_routines()
 RETURNS json
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
end $function$;


CREATE OR REPLACE FUNCTION public.get_event_detail(p_id bigint)
 RETURNS json
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
end $function$;


CREATE OR REPLACE FUNCTION public.get_routine_detail(p_id bigint)
 RETURNS json
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
end $function$;


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
end $function$;


CREATE OR REPLACE FUNCTION public.fn_event_persons(p_event_id bigint)
 RETURNS json
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;


CREATE OR REPLACE FUNCTION public.fn_routine_persons(p_routine_id bigint)
 RETURNS json
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
    select coalesce((
        select json_agg(json_build_object('id', p.id, 'user_id', p.user_id, 'name', p.name, 'color', p.color)
            order by translate(p.name, 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', 'abcdefghijklmnopqrstuvwxyz'), p.id)
        from routine_person rp
        inner join person p on p.id = rp.person_id and p.user_id = any (fn_family_user_ids())
        where rp.routine_id = p_routine_id
          and fn_routine_in_my_calendars(p_routine_id)
    ), '[]'::json)
$function$;


CREATE OR REPLACE FUNCTION public.get_persons(p_include_inactive boolean DEFAULT false)
 RETURNS json
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
            'kind', hm.kind::text
        ) order by translate(p.name, 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', 'abcdefghijklmnopqrstuvwxyz'), p.id), '[]'::json)
        from person p
        inner join home_member hm on hm.id = p.home_member_id
        where p.user_id = any (fn_family_user_ids())
          and (p_include_inactive or hm.status = 'active')
    );
end $function$;


CREATE OR REPLACE FUNCTION public.fn_sync_assignments(p_table text, p_column text, p_id bigint, p_person_ids jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
end $function$;


CREATE OR REPLACE FUNCTION public.materialize_routines_for(p_user_id bigint, p_timezone text)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare
    v_now text := to_char((now() at time zone p_timezone), 'YYYY-MM-DD HH24:MI:SS');
    rt record;
    v_avail text;
    v_from date;
    v_last date;
    v_day date;
    v_date text;
    v_date_at text;
    v_match boolean;
    v_matched jsonb;
    v_added jsonb;
    v_key text;
    v_val jsonb;
    ex record;
    ev record;
begin
    for rt in
        select id, calendar_id, title, frequency, "interval", days, time, start_date, end_date, available_from
        from routine
        where active
          and exists (select 1 from calendar_user cu where cu.calendar_id = routine.calendar_id and cu.user_id = p_user_id)
        order by id
    loop
        v_avail := to_char(rt.available_from, 'YYYY-MM-DD HH24:MI:SS');
        -- PHP $dates es un array asociativo cuyo orden de inserción son las posiciones que luego
        -- fijan los event.id (Routine.php:150-160, 190-192): dos colecciones para reproducirlo —
        -- v_matched con las claves de matches (jsonb_each order by key = orden ascendente de
        -- inserción, y la sobrescritura de excepción conserva posición) y v_added con las claves
        -- NUEVAS de routine_exception, append al final (R1-12).
        v_matched := '{}'::jsonb;
        v_added := '[]'::jsonb;

        -- occurrences() (Routine.php:144-154)
        v_from := greatest(v_now::date, rt.start_date, rt.available_from::date);
        v_last := (v_now::date + 89);
        if rt.end_date is not null then
            v_last := least(v_last, rt.end_date);
        end if;

        for v_day in select generate_series(v_from::timestamp, v_last::timestamp, interval '1 day')::date loop
            v_date := to_char(v_day, 'YYYY-MM-DD');
            v_date_at := v_date || ' ' || rt.time || ':00';
            -- matches() (Routine.php:165-177)
            v_match := case rt.frequency
                when 'daily' then
                    ((v_day - rt.start_date) % rt."interval") = 0
                when 'weekly' then
                    exists (select 1 from jsonb_array_elements_text(rt.days) d where d::int = extract(isodow from v_day))
                    and (((date_trunc('week', v_day)::date - date_trunc('week', rt.start_date)::date) / 7) % rt."interval") = 0
                when 'monthly' then
                    ((extract(year from v_day)::int * 12 + extract(month from v_day)::int)
                        - (extract(year from rt.start_date)::int * 12 + extract(month from rt.start_date)::int)) % rt."interval" = 0
                    and extract(day from v_day)::int = least(
                        extract(day from rt.start_date)::int,
                        extract(day from (date_trunc('month', v_day) + interval '1 month' - interval '1 day'))::int)
            end;
            if v_match and v_date_at >= greatest(v_now, v_avail) then
                v_matched := v_matched || jsonb_build_object(v_date, jsonb_build_object('title', rt.title, 'date_at', v_date_at));
            end if;
        end loop;

        -- routine_exception (Routine.php:156-162): cancelada borra la fecha; en otro caso
        -- sobrescribe/añade su ocurrencia. Orden por routine_date = orden de fila de SQLite (índice
        -- PK (routine_id, routine_date)). Sobrescribir conserva posición (asignación PHP en sitio);
        -- una clave NUEVA se añade al final, como el append de PHP (R1-12).
        for ex in select routine_date, title, date_at, cancelled
                  from routine_exception where routine_id = rt.id order by routine_date loop
            v_key := to_char(ex.routine_date, 'YYYY-MM-DD');
            if ex.cancelled then
                v_matched := v_matched - v_key;
                v_added := coalesce((select jsonb_agg(elem order by ord)
                    from jsonb_array_elements(v_added) with ordinality t(elem, ord)
                    where elem->>'key' <> v_key), '[]'::jsonb);
            elsif ex.date_at is not null and to_char(ex.date_at, 'YYYY-MM-DD HH24:MI:SS') >= greatest(v_now, v_avail) then
                if v_matched ? v_key then
                    v_matched := v_matched || jsonb_build_object(v_key, jsonb_build_object('title', ex.title, 'date_at', to_char(ex.date_at, 'YYYY-MM-DD HH24:MI:SS')));
                else
                    v_added := v_added || jsonb_build_array(jsonb_build_object('key', v_key, 'title', ex.title, 'date_at', to_char(ex.date_at, 'YYYY-MM-DD HH24:MI:SS')));
                end if;
            end if;
        end loop;

        -- materialize() en modo lectura (reconcile=false, el de materializeForUser): cada fila
        -- existente consume su fecha (pasada o futura) y solo se insertan las que falten (las
        -- routine_date NULL no tocan nada, como el unset($dates[null]) de PHP)
        for ev in select routine_date from event where routine_id = rt.id and routine_date is not null loop
            v_key := to_char(ev.routine_date, 'YYYY-MM-DD');
            v_matched := v_matched - v_key;
            v_added := coalesce((select jsonb_agg(elem order by ord)
                from jsonb_array_elements(v_added) with ordinality t(elem, ord)
                where elem->>'key' <> v_key), '[]'::jsonb);
        end loop;

        -- Orden de inserción = orden de $dates en PHP (R1-12): emparejadas ascendentes y luego las
        -- añadidas por excepción al final
        for v_key, v_val in select key, value from jsonb_each(v_matched) order by key loop
            insert into event (calendar_id, title, date_at, routine_id, routine_date)
            values (rt.calendar_id, v_val->>'title', (v_val->>'date_at')::timestamp, rt.id, v_key::date)
            on conflict (routine_id, routine_date) do nothing;
        end loop;
        for v_val in select elem from jsonb_array_elements(v_added) with ordinality t(elem, ord) order by ord loop
            insert into event (calendar_id, title, date_at, routine_id, routine_date)
            values (rt.calendar_id, v_val->>'title', (v_val->>'date_at')::timestamp, rt.id, (v_val->>'key')::date)
            on conflict (routine_id, routine_date) do nothing;
        end loop;

        -- syncAlarms() (Routine.php:196-199): event_user para TODOS los miembros del calendario
        insert into event_user (event_id, user_id, alarm)
        select e.id, cu.user_id, case when rea.user_id is not null then rea.alarm else ru.alarm end
        from event e
        inner join (select distinct calendar_id, user_id from calendar_user) cu on cu.calendar_id = e.calendar_id
        left join routine_user ru on ru.routine_id = e.routine_id and ru.user_id = cu.user_id
        left join routine_event_alarm rea
            on rea.routine_id = e.routine_id and rea.routine_date = e.routine_date and rea.user_id = cu.user_id
        where e.routine_id = rt.id and e.date_at >= v_now::timestamp
        on conflict (event_id, user_id) do update
            set alarm = excluded.alarm, updated_at = (now() at time zone 'UTC')
            where event_user.alarm is distinct from excluded.alarm;
    end loop;
end $function$;


commit;
