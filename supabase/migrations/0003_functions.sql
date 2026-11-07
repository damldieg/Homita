-- 0003_functions.sql — RPCs del contrato de lectura del dashboard (fase 1, D-002).
--
-- * get_events / get_tasks: SECURITY INVOKER, ejecutadas con el JWT del usuario → RLS aplica
--   (doble capa con los JOINs por usuario). Salida JSON byte a byte con el PHP (json_encode de
--   Event/Task: claves en el orden de las propiedades de las clases) y fechas
--   to_char(..., 'YYYY-MM-DD HH24:MI:SS') como las cadenas SQLite.
-- * materialize_routines_for: port 1:1 de Routine::materializeForUser/occurrences/matches/
--   materialize/syncAlarms (api/src/Models/Routine.php:37-228) — SECURITY INVOKER ejecutada con
--   service_role (BYPASSRLS, como PHP escribe durante la lectura) y REVOKE a anon/authenticated:
--   p_user_id lo deriva la Edge del JWT verificado, nunca del request (R1-03).
-- * admin_bump_sequences: solo service_role (uso de migración).
-- * Todos los writes fijan created_at/updated_at con (now() at time zone 'UTC') (R1-07): nunca
--   CURRENT_TIMESTAMP crudo (depende del TimeZone de sesión en PG).

-- R1-13: `persons` embebido de get_events sin el filtro de visibilidad de la policy `person`
-- (Person::byEvent/byRoutine NO filtran por visibilidad, Person.php:96-121). SECURITY DEFINER para
-- saltarse la RLS de `person` dentro del subquery INVOKER, con guardia de calendario propio: solo
-- responde de eventos visibles para el llamante (misma superficie que el subquery previo, sin fuga
-- cross-tenant nueva). Orden y forma = Person::byEvent (translate() plegado ASCII ≈ COLLATE NOCASE).
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
        inner join person p on p.id = x.person_id
    ), '[]'::json)
    from event e
    where e.id = p_event_id
      and e.calendar_id = any (fn_my_calendar_ids())
$$;

create or replace function get_events(
    p_start_date text default null,       -- 'YYYY-MM-DD HH:MM:SS' (epoch ya convertido en la Edge, como ModelAbstract::getFilterTimestamp)
    p_end_date text default null,
    p_routine boolean default null,       -- null = sin filtro (getFilterBool de PHP)
    p_timezone text default null,         -- informativo: la materialización la hace materialize_routines_for
    p_dashboard boolean default null,
    p_calendar_id bigint default null,
    p_person_id bigint default null,
    p_search text default null,
    p_limit integer default null,
    p_offset integer default null,
    p_order_mode text default null,
    p_widget boolean default null
) returns json
language sql stable security invoker set search_path = public as $$
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
$$;

create or replace function get_tasks(
    p_dashboard boolean default null,     -- null = sin filtro (getFilterBool de PHP)
    p_task_list_id bigint default null,
    p_widget boolean default null
) returns json
language sql stable security invoker set search_path = public as $$
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
$$;

-- Port 1:1 de Routine::materializeForUser (Routine.php:117-123) sobre las rutinas visibles para
-- p_user_id (misma membresía que el SELECT de PHP) y activas. El orden por id reproduce el orden
-- de fila del SELECT de PHP para que los ids materializados coincidan.
create or replace function materialize_routines_for(p_user_id bigint, p_timezone text)
returns void language plpgsql security invoker set search_path = public as $$
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
end $$;

-- Avanza las secuencias de las 10 tablas con id tras importar ids explícitos (uso de migración).
create or replace function admin_bump_sequences() returns void
language plpgsql security invoker set search_path = public as $$
declare
    t text;
begin
    foreach t in array array['app_user', 'calendar', 'calendar_user', 'event', 'event_user',
                             'task_list', 'task_list_user', 'task', 'routine', 'person'] loop
        execute format(
            'select setval(pg_get_serial_sequence(%L, %L), coalesce((select max(id) from public.%I), 0) + 1, false)',
            t, 'id', t);
    end loop;
end $$;

-- Grants (R1-03): materialize_routines_for y admin_bump_sequences solo para service_role.
revoke execute on function materialize_routines_for(bigint, text) from public, anon, authenticated;
revoke execute on function admin_bump_sequences() from public, anon, authenticated;
revoke execute on function get_events(text, text, boolean, text, boolean, bigint, bigint, text, integer, integer, text, boolean) from public, anon;
revoke execute on function get_tasks(boolean, bigint, boolean) from public, anon;
revoke execute on function fn_event_persons(bigint) from public, anon;
grant execute on function get_events(text, text, boolean, text, boolean, bigint, bigint, text, integer, integer, text, boolean) to authenticated, service_role;
grant execute on function get_tasks(boolean, bigint, boolean) to authenticated, service_role;
grant execute on function fn_event_persons(bigint) to authenticated, service_role;
grant execute on function materialize_routines_for(bigint, text) to service_role;
grant execute on function admin_bump_sequences() to service_role;
