-- rollback_0030.sql — Revierte 0030_event_end_date.sql (change event-end-date).
-- Restaura las firmas y cuerpos previos: create_event/update_event de 0029, get_events y
-- get_event_detail de 0020, con sus ACL (authenticated y service_role; sin PUBLIC/anon), y borra
-- la columna event.end_date.
-- Datos: se PIERDEN los end_date guardados tras el deploy. Rollback preferido si solo falla la app/Edge:
-- revertir la app/Edge y dejar la columna.
-- supabase_migrations.schema_migrations: la fila '0030' no se borra aquí.

begin;

drop function if exists create_event(bigint, text, text, integer, jsonb, text);
drop function if exists update_event(bigint, text, text, integer, jsonb, text, text, boolean);

create or replace function create_event(p_calendar_id bigint, p_title text, p_date_at text, p_alarm integer, p_person_ids jsonb) returns json
language plpgsql security definer set search_path = public as $$
declare
    v_me bigint := fn_my_user_id();
    v_id bigint;
    v_home bigint;
    v_role user_role;
    v_persons bigint[];
begin
    if v_me is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    -- H0: espejo de phpEmpty (null, '', '0') e inputDateHour (usecases/events.ts:91)
    if p_title is null or p_title = '' or p_title = '0'
       or p_date_at is null or p_date_at !~ '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$' then
        raise exception 'Title and date_at are required if text is not provided' using errcode = 'P0001';
    end if;
    -- 1.8 (§2.2/§2.3/§3.2): validación de personas → lock → ACL → event.create → event.assign
    v_persons := fn_person_ids_array(p_person_ids);
    v_home := fn_home_of_calendar(p_calendar_id);
    if v_home is null then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    perform fn_home_write_lock(v_home);
    select role into v_role from calendar_user where calendar_id = p_calendar_id and user_id = v_me for share;
    if v_role is null then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    -- 0029 (E2): tope adicional, permiso de edición en el ACL (owner o can_edit)
    if not fn_calendar_editable(p_calendar_id) then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    if not fn_has_permission(v_home, 'event.create') then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    -- Q-C (a): event.assign solo si el conjunto deja de ser vacío (null = no tocar; [] = vacío)
    if v_persons is not null and cardinality(v_persons) > 0
       and not fn_has_permission(v_home, 'event.assign') then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    insert into event (calendar_id, title, date_at)
    values (p_calendar_id, p_title, p_date_at::timestamp) returning id into v_id;
    perform fn_apply_event_alarm(v_id, null, null, p_alarm, v_me);
    if v_persons is not null and cardinality(v_persons) > 0 then
        perform fn_sync_assignments('event_person', 'event_id', v_id, p_person_ids);
    end if;
    return get_event_detail(v_id);
end $$;

create or replace function update_event(p_id bigint, p_title text, p_date_at text, p_alarm integer, p_person_ids jsonb, p_timezone text) returns json
language plpgsql security definer set search_path = public as $$
declare
    v_me bigint := fn_my_user_id();
    v_routine_id bigint;
    v_routine_date date;
    v_home bigint;
    v_role user_role;
    v_persons bigint[];
    v_changed boolean;
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
    -- 1.8 (§2.2/§2.3/§3.2/§3.8): validación de personas → lock → ACL → event.edit →
    -- event.assign si cambia el conjunto → materialización → lookup → escritura. Si validación,
    -- lock, ACL o permiso fallan, no hay efecto secundario (R1-06).
    v_persons := fn_person_ids_array(p_person_ids);
    v_home := fn_home_of_event(p_id);
    if v_home is null then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    perform fn_home_write_lock(v_home);
    select role into v_role from calendar_user
    where calendar_id = (select calendar_id from event where id = p_id) and user_id = v_me for share;
    if v_role is null then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    -- 0029 (E2): tope adicional, permiso de edición en el ACL (owner o can_edit)
    if not fn_calendar_editable((select calendar_id from event where id = p_id)) then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    if not fn_has_permission(v_home, 'event.edit') then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    -- Q-C (a): event.assign solo si el conjunto mostrado cambia (null = no tocar; A-13: sin sync
    -- si no hay cambio, para no escribir filas ocultas de event_person en sesión de rutina)
    v_changed := v_persons is not null and v_persons is distinct from fn_event_assigned_ids(p_id);
    if v_changed and not fn_has_permission(v_home, 'event.assign') then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    -- EventUpdate.php:14: materializeForUser ANTES del lookup (interno, sin service_role)
    perform fn_materialize_my_routines(p_timezone);
    select e.routine_id, e.routine_date into v_routine_id, v_routine_date
    from event e where e.id = p_id;
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
    if v_changed then
        perform fn_sync_assignments('event_person', 'event_id', p_id, p_person_ids);
    end if;
    return get_event_detail(p_id);
end $$;

revoke execute on function create_event(bigint, text, text, integer, jsonb) from public, anon;
revoke execute on function update_event(bigint, text, text, integer, jsonb, text) from public, anon;
grant execute on function create_event(bigint, text, text, integer, jsonb) to authenticated, service_role;
grant execute on function update_event(bigint, text, text, integer, jsonb, text) to authenticated, service_role;

create or replace function get_events(p_start_date text default null::text, p_end_date text default null::text, p_routine boolean default null::boolean, p_timezone text default null::text, p_dashboard boolean default null::boolean, p_calendar_id bigint default null::bigint, p_person_id bigint default null::bigint, p_search text default null::text, p_limit integer default null::integer, p_offset integer default null::integer, p_order_mode text default null::text, p_widget boolean default null::boolean) returns json
language sql stable set search_path = public as $$
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
        -- 1.8 (§3.3): visibilidad ACL ∪ admin (Q1); la alarma es siempre la del llamante
        left join calendar_user cu on cu.calendar_id = e.calendar_id and cu.user_id = fn_my_user_id()
        inner join calendar c on c.id = e.calendar_id
        left join event_user eu on eu.event_id = e.id and eu.user_id = fn_my_user_id()
        where e.calendar_id in (select fn_visible_calendar_ids())
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
$$;

create or replace function get_event_detail(p_id bigint) returns json
language plpgsql stable security definer set search_path = public as $$
begin
    if fn_my_user_id() is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    if not fn_event_visible(p_id) then
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

alter table event drop column end_date;

commit;
