-- 0007_materialize_routine.sql — Materialización por rutina para las escrituras (control-api, R1-06).
--
-- IMPORTANTE: NO se toca materialize_routines_for(bigint, text) — su definición y grants son los de
-- 0003 (el dashboard en producción la sigue usando vía service_role). Aquí solo se AÑADEN:
--
-- * fn_materialize_one(p_routine_id, p_timezone, p_reconcile): cuerpo por rutina copiado de 0003
--   líneas 177-271 (occurrences, matches, excepciones, materialize read-mode) + rama
--   p_reconcile=true con la semántica de Routine::materialize(reconcile=true) (Routine.php:158-181):
--   historial intacto, DELETE de futuros que dejan de tocar, UPDATE de título/hora de los que
--   siguen tocando. syncAlarms delegado en fn_sync_routine_alarms (0006, mismo SQL que 0003).
--   Helper interno: REVOKE a public, anon, authenticated (lo ejecuta el owner dentro del definer).
-- * fn_materialize_my_routines(p_timezone): materializeForUser de PHP (Routine.php:117-123) para
--   las escrituras de eventos (update/delete/alarm materializan antes de escribir,
--   EventUpdate.php:14 etc.) sin service_role: bucle de fn_materialize_one por las rutinas activas
--   del llamante en orden de id (igual que 0003 materialize_routines_for).
-- * materialize_routine(p_routine_id, p_timezone, p_reconcile): entrada para `authenticated` con la
--   spec de §2 (R1-02): guardia primera línea, id de usuario nunca es parámetro, delega en
--   fn_materialize_one. REVOKE public, anon; GRANT authenticated.
--
-- Duplicación aceptada con 0003 (dos cuerpos de materialización): dedup en change posterior cuando
-- los fixtures de paridad pasen dos veces (plan §5).

create or replace function fn_materialize_one(p_routine_id bigint, p_timezone text, p_reconcile boolean)
returns void language plpgsql security definer set search_path = public as $$
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
    select id, calendar_id, title, frequency, "interval", days, time, start_date, end_date,
           available_from, active
    into rt
    from routine
    where id = p_routine_id;

    if not found then
        return;
    end if;

    -- Como occurrences() (Routine.php:133-136): rutina inactiva = sin fechas (pero el bucle de
    -- eventos existentes y syncAlarms siguen: reconcile=true con active=false borra los futuros).
    v_matched := '{}'::jsonb;
    v_added := '[]'::jsonb;

    if rt.active then
        v_avail := to_char(rt.available_from, 'YYYY-MM-DD HH24:MI:SS');
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
        -- sobrescribe/añade su ocurrencia (misma posición/append que 0003, R1-12)
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
    end if;

    -- materialize() (Routine.php:158-181): cada fila existente consume su fecha. Historial
    -- (date_at < now) nunca se toca. Con p_reconcile: los futuros que dejan de tocar se borran y
    -- los que siguen tocando reciben título/hora nuevos. (routine_date NULL no toca nada, como el
    -- unset($dates[null]) de PHP; esas filas no existen con routine_id relleno.)
    for ev in select id, routine_date, date_at from event
              where routine_id = p_routine_id and routine_date is not null loop
        v_key := to_char(ev.routine_date, 'YYYY-MM-DD');
        if ev.date_at >= v_now::timestamp and p_reconcile then
            select case
                when v_matched ? v_key then v_matched -> v_key
                else (select jsonb_build_object('title', elem->>'title', 'date_at', elem->>'date_at')
                      from jsonb_array_elements(v_added) with ordinality t(elem, ord)
                      where elem->>'key' = v_key limit 1)
            end into v_val;
            if v_val is null then
                delete from event where id = ev.id;
            else
                update event
                set title = v_val->>'title', date_at = (v_val->>'date_at')::timestamp,
                    updated_at = (now() at time zone 'UTC')
                where id = ev.id;
            end if;
        end if;
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

    -- syncAlarms() (Routine.php:196-199) — mismo SQL que 0003:260-271, extraído a 0006
    perform fn_sync_routine_alarms(rt.id, v_now);
end $$;

-- materializeForUser (Routine.php:117-123) para las escrituras de eventos: read-mode sobre las
-- rutinas activas del llamante, en orden de id. El id de usuario se deriva del JWT (fn_my_user_id),
-- nunca del request (R1-03).
create or replace function fn_materialize_my_routines(p_timezone text) returns void
language plpgsql security definer set search_path = public as $$
declare
    r record;
begin
    for r in
        select id from routine
        where active and calendar_id = any (fn_my_calendar_ids())
        order by id
    loop
        perform fn_materialize_one(r.id, p_timezone, false);
    end loop;
end $$;

-- Entrada para authenticated (§2, R1-02): guardia primera línea, delega en fn_materialize_one.
create or replace function materialize_routine(p_routine_id bigint, p_timezone text, p_reconcile boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
    if fn_my_user_id() is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    if not fn_routine_in_my_calendars(p_routine_id) then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    perform fn_materialize_one(p_routine_id, p_timezone, p_reconcile);
end $$;

revoke execute on function fn_materialize_one(bigint, text, boolean) from public, anon, authenticated;
revoke execute on function fn_materialize_my_routines(text) from public, anon, authenticated;
revoke execute on function materialize_routine(bigint, text, boolean) from public, anon;
grant execute on function materialize_routine(bigint, text, boolean) to authenticated;
