-- 0029_acl_can_edit.sql — Permiso de edición por calendario y lista (change
-- permisos-edicion-registro-sesion, respuestas de Damian del 2026-11-13).
--
-- * Columna `can_edit boolean not null default false` en calendar_user y task_list_user (Q4: sin
--   tocar el enum user_role). Permiso efectivo de edición = role = 'owner' or can_edit.
-- * Backfill (Q3): las filas 'viewer' existentes pasan a can_edit = true, para que nadie pierda la
--   escritura que hoy le da el catálogo del hogar. Las altas nuevas por email entran en lectura.
-- * Tope adicional (Q1): las 12 RPC de contenido exigen, además del permiso del catálogo (0020),
--   fn_calendar_editable / fn_task_list_editable. No entran las alarmas propias
--   (set_event_alarm, set_routine_alarm) ni los flags widget/dashboard de la fila propia.
--   materialize_routine solo lo exige con p_reconcile (igual que routine.edit en 0020).
-- * Metadatos (Q2): update_calendar / update_task_list aceptan nombre, color y orden con permiso
--   de edición; siguen exigiendo calendar.manage / tasklist.manage. delete_* y add/remove_*_user
--   siguen siendo solo owner (sin cambios).
-- * RPC nuevas set_calendar_user_access / set_task_list_user_access: solo owner (+ *.manage, como
--   add_*_user). Destino = cuenta con membresía en el hogar del recurso; si no está en el ACL se
--   agrega como 'viewer' con el can_edit pedido. No cambian filas de owner ni la propia.
-- * Lecturas: get_calendar_users / get_task_list_users / get_calendars / get_task_lists agregan
--   la clave `can_edit` (aditiva, D-008: los clientes ignoran claves desconocidas).
--
-- Errores sin mensajes nuevos: 'Not Found' P0002 (→ 500 legacy), 'Not Allowed' 42501 (→ 403).
-- Cuerpos: última definición de cada función (0020/0025) con el cambio mínimo; generados y
-- verificados contra un reset local 0001–0029.
-- Rollback: scripts/supabase/rollback/rollback_0029.sql.

begin;

-- ─────────────────── (a) Columna y backfill ───────────────────

alter table calendar_user add column can_edit boolean not null default false;
alter table task_list_user add column can_edit boolean not null default false;

update calendar_user set can_edit = true where role = 'viewer';
update task_list_user set can_edit = true where role = 'viewer';

-- ─────────────────── (b) Helpers internos ───────────────────

-- Permiso efectivo de edición del llamante sobre el recurso (owner o can_edit).
create or replace function fn_calendar_editable(p_calendar_id bigint) returns boolean
language sql stable security definer set search_path = public as $$
    select exists (
        select 1 from calendar_user cu
        where cu.calendar_id = p_calendar_id and cu.user_id = fn_my_user_id()
          and (cu.role = 'owner' or cu.can_edit)
    )
$$;

create or replace function fn_task_list_editable(p_task_list_id bigint) returns boolean
language sql stable security definer set search_path = public as $$
    select exists (
        select 1 from task_list_user tlu
        where tlu.task_list_id = p_task_list_id and tlu.user_id = fn_my_user_id()
          and (tlu.role = 'owner' or tlu.can_edit)
    )
$$;

-- ─────────────────── (c) RPC nuevas: cambiar el permiso de un miembro ───────────────────
-- Orden de locks como add_*_user (0021): hogar (fn_home_write_lock) → ACL propia (for share) →
-- fila del destino. Idempotente: el upsert usa el unique (calendar_id, user_id) de 0015.

create or replace function set_calendar_user_access(p_calendar_id bigint, p_user_id bigint, p_can_edit boolean)
returns json
language plpgsql security definer set search_path = public as $$
declare
    v_me bigint := fn_my_user_id();
    v_role user_role;
    v_home bigint;
    v_target_role user_role;
begin
    if v_me is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    if p_calendar_id is null or p_user_id is null or p_can_edit is null then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    v_home := fn_home_of_calendar(p_calendar_id);
    if v_home is null then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    perform fn_home_write_lock(v_home);
    select role into v_role from calendar_user where calendar_id = p_calendar_id and user_id = v_me for share;
    if v_role is null then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    if v_role <> 'owner' or not fn_has_permission(v_home, 'calendar.manage') then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    -- La fila propia y las de otros owners no se cambian.
    if p_user_id = v_me then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    -- Solo cuentas con membresía en el hogar del calendario (los miembros sin cuenta no tienen fila).
    if not exists (select 1 from home_membership where home_id = v_home and app_user_id = p_user_id) then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    select role into v_target_role from calendar_user
    where calendar_id = p_calendar_id and user_id = p_user_id for update;
    if v_target_role = 'owner' then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    insert into calendar_user (calendar_id, user_id, role, widget, dashboard, home_id, can_edit)
    values (p_calendar_id, p_user_id, 'viewer', true, true, v_home, p_can_edit)
    on conflict (calendar_id, user_id) do update set can_edit = excluded.can_edit;
    return (
        select json_build_object(
            'cu_id', cu.id, 'user_id', u.id, 'name', u.name, 'email', u.email, 'role', cu.role,
            'can_edit', (cu.role = 'owner' or cu.can_edit))
        from calendar_user cu inner join app_user u on u.id = cu.user_id
        where cu.calendar_id = p_calendar_id and cu.user_id = p_user_id
    );
end $$;

create or replace function set_task_list_user_access(p_task_list_id bigint, p_user_id bigint, p_can_edit boolean)
returns json
language plpgsql security definer set search_path = public as $$
declare
    v_me bigint := fn_my_user_id();
    v_role user_role;
    v_home bigint;
    v_target_role user_role;
begin
    if v_me is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    if p_task_list_id is null or p_user_id is null or p_can_edit is null then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    v_home := fn_home_of_task_list(p_task_list_id);
    if v_home is null then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    perform fn_home_write_lock(v_home);
    select role into v_role from task_list_user where task_list_id = p_task_list_id and user_id = v_me for share;
    if v_role is null then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    if v_role <> 'owner' or not fn_has_permission(v_home, 'tasklist.manage') then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    if p_user_id = v_me then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    if not exists (select 1 from home_membership where home_id = v_home and app_user_id = p_user_id) then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    select role into v_target_role from task_list_user
    where task_list_id = p_task_list_id and user_id = p_user_id for update;
    if v_target_role = 'owner' then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    insert into task_list_user (task_list_id, user_id, role, widget, dashboard, home_id, can_edit)
    values (p_task_list_id, p_user_id, 'viewer', true, true, v_home, p_can_edit)
    on conflict (task_list_id, user_id) do update set can_edit = excluded.can_edit;
    return (
        select json_build_object(
            'tlu_id', tlu.id, 'user_id', u.id, 'name', u.name, 'email', u.email, 'role', tlu.role,
            'can_edit', (tlu.role = 'owner' or tlu.can_edit))
        from task_list_user tlu inner join app_user u on u.id = tlu.user_id
        where tlu.task_list_id = p_task_list_id and tlu.user_id = p_user_id
    );
end $$;

-- ─────────────────── (d) RPC redefinidas ───────────────────

-- create_event: cuerpo de 0020_home_write_guards.sql + guardia de edición tras la ACL.
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

-- update_event: cuerpo de 0020_home_write_guards.sql + guardia de edición tras la ACL.
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

-- delete_event: cuerpo de 0020_home_write_guards.sql + guardia de edición tras la ACL.
create or replace function delete_event(p_id bigint, p_timezone text) returns json
language plpgsql security definer set search_path = public as $$
declare
    v_me bigint := fn_my_user_id();
    v_routine_id bigint;
    v_routine_date date;
    v_home bigint;
    v_role user_role;
begin
    if v_me is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    -- 1.8 (§2.2/§2.3): lock → ACL → event.delete → materialización → lookup → escritura
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
    if not fn_has_permission(v_home, 'event.delete') then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    -- EventDelete.php:12: materializeForUser ANTES del lookup (interno, sin service_role)
    perform fn_materialize_my_routines(p_timezone);
    select e.routine_id, e.routine_date into v_routine_id, v_routine_date
    from event e where e.id = p_id;
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

-- create_routine: cuerpo de 0020_home_write_guards.sql + guardia de edición tras la ACL.
create or replace function create_routine(p_calendar_id bigint, p_title text, p_frequency text, p_interval integer, p_days jsonb, p_time text, p_start_date text, p_end_date text, p_active boolean, p_alarm integer, p_person_ids jsonb, p_timezone text) returns json
language plpgsql security definer set search_path = public as $$
declare
    v_me bigint := fn_my_user_id();
    v_now text;
    v_id bigint;
    v_home bigint;
    v_role user_role;
    v_persons bigint[];
    v_frequency text;
    v_interval integer;
    v_date date;
    v_date2 date;
begin
    if v_me is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    -- 1.8 (§3.5): validación SQL de rutinas ANTES del lock (entrada), mensajes de validate.ts:39-95
    if p_title is null then
        raise exception 'Title is required' using errcode = 'P0001';
    end if;
    v_frequency := coalesce(p_frequency, 'weekly');
    v_interval := coalesce(p_interval, 1);
    if v_frequency not in ('daily', 'weekly', 'monthly') then
        raise exception 'Frequency must be daily, weekly or monthly' using errcode = 'P0001';
    end if;
    if v_interval < 1 or v_interval > 99 then
        raise exception 'Interval must be 1 to 99' using errcode = 'P0001';
    end if;
    if btrim(p_title) = ''
       or (v_frequency = 'weekly'
           and (p_days is null or jsonb_typeof(p_days) <> 'array' or jsonb_array_length(p_days) = 0)) then
        raise exception 'Title and selected days are required' using errcode = 'P0001';
    end if;
    if v_frequency = 'weekly'
       and exists (select 1 from jsonb_array_elements(p_days) e
                   where jsonb_typeof(e) <> 'number' or (e #>> '{}') !~ '^[1-7]$') then
        raise exception 'Days must be ISO weekdays 1 to 7' using errcode = 'P0001';
    end if;
    if p_time is null or p_time !~ '^(?:[01][0-9]|2[0-3]):[0-5][0-9]$' then
        raise exception 'Invalid time' using errcode = 'P0001';
    end if;
    if p_start_date is not null and p_start_date !~ '^\d{4}-\d{2}-\d{2}$' then
        raise exception 'Invalid date' using errcode = 'P0001';
    end if;
    if p_end_date is not null and p_end_date !~ '^\d{4}-\d{2}-\d{2}$' then
        raise exception 'Invalid date' using errcode = 'P0001';
    end if;
    begin
        v_date := p_start_date::date;
        v_date2 := p_end_date::date;
    exception when others then
        raise exception 'Invalid date' using errcode = 'P0001';
    end;
    if p_start_date is null or (p_end_date is not null and p_end_date < p_start_date) then
        raise exception 'Invalid date range' using errcode = 'P0001';
    end if;
    if p_active is null then
        raise exception 'Active must be boolean' using errcode = 'P0001';
    end if;
    -- 1.8 (§2.2/§2.3/§3.2): personas → lock → ACL → routine.create → routine.assign
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
    if not fn_has_permission(v_home, 'routine.create') then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    -- Q-C (a): routine.assign solo si el conjunto deja de ser vacío
    if v_persons is not null and cardinality(v_persons) > 0
       and not fn_has_permission(v_home, 'routine.assign') then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    v_now := to_char(now() at time zone p_timezone, 'YYYY-MM-DD HH24:MI:SS');
    insert into routine (calendar_id, title, frequency, "interval", days, time, start_date, end_date, active, available_from)
    values (p_calendar_id, p_title, v_frequency::routine_frequency, v_interval, p_days, p_time,
            p_start_date::date, p_end_date::date, p_active, v_now::timestamp)
    returning id into v_id;
    insert into routine_user (routine_id, user_id, alarm) values (v_id, v_me, p_alarm);
    if v_persons is not null and cardinality(v_persons) > 0 then
        perform fn_sync_assignments('routine_person', 'routine_id', v_id, p_person_ids);
    end if;
    perform fn_materialize_one(v_id, p_timezone, false);
    return get_routine_detail(v_id);
end $$;

-- update_routine: cuerpo de 0020_home_write_guards.sql + guardia de edición tras la ACL.
create or replace function update_routine(p_id bigint, p_title text, p_frequency text, p_interval integer, p_days jsonb, p_time text, p_start_date text, p_end_date text, p_active boolean, p_person_ids jsonb, p_timezone text) returns json
language plpgsql security definer set search_path = public as $$
declare
    v_me bigint := fn_my_user_id();
    v_now text;
    v_available timestamp;
    v_active boolean;
    v_home bigint;
    v_role user_role;
    v_persons bigint[];
    v_changed boolean;
    v_frequency text;
    v_interval integer;
    v_cur_freq text;
    v_cur_interval integer;
    v_date date;
    v_date2 date;
begin
    if v_me is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    select r.active, r.frequency::text, r."interval" into v_active, v_cur_freq, v_cur_interval
    from routine r where r.id = p_id;
    -- 1.8 (§3.5): validación SQL de rutinas ANTES del lock (entrada), mensajes de validate.ts:39-95
    if p_title is null then
        raise exception 'Title is required' using errcode = 'P0001';
    end if;
    v_frequency := coalesce(p_frequency, v_cur_freq, 'weekly');
    v_interval := coalesce(p_interval, v_cur_interval, 1);
    if v_frequency not in ('daily', 'weekly', 'monthly') then
        raise exception 'Frequency must be daily, weekly or monthly' using errcode = 'P0001';
    end if;
    if v_interval < 1 or v_interval > 99 then
        raise exception 'Interval must be 1 to 99' using errcode = 'P0001';
    end if;
    if btrim(p_title) = ''
       or (v_frequency = 'weekly'
           and (p_days is null or jsonb_typeof(p_days) <> 'array' or jsonb_array_length(p_days) = 0)) then
        raise exception 'Title and selected days are required' using errcode = 'P0001';
    end if;
    if v_frequency = 'weekly'
       and exists (select 1 from jsonb_array_elements(p_days) e
                   where jsonb_typeof(e) <> 'number' or (e #>> '{}') !~ '^[1-7]$') then
        raise exception 'Days must be ISO weekdays 1 to 7' using errcode = 'P0001';
    end if;
    if p_time is null or p_time !~ '^(?:[01][0-9]|2[0-3]):[0-5][0-9]$' then
        raise exception 'Invalid time' using errcode = 'P0001';
    end if;
    if p_start_date is not null and p_start_date !~ '^\d{4}-\d{2}-\d{2}$' then
        raise exception 'Invalid date' using errcode = 'P0001';
    end if;
    if p_end_date is not null and p_end_date !~ '^\d{4}-\d{2}-\d{2}$' then
        raise exception 'Invalid date' using errcode = 'P0001';
    end if;
    begin
        v_date := p_start_date::date;
        v_date2 := p_end_date::date;
    exception when others then
        raise exception 'Invalid date' using errcode = 'P0001';
    end;
    if p_start_date is null or (p_end_date is not null and p_end_date < p_start_date) then
        raise exception 'Invalid date range' using errcode = 'P0001';
    end if;
    if p_active is null then
        raise exception 'Active must be boolean' using errcode = 'P0001';
    end if;
    -- 1.8 (§2.2/§2.3/§3.2): personas → lock → ACL → routine.edit → routine.assign si cambia el
    -- conjunto (null = no tocar; igual = sin permiso ni sync, A-13)
    v_persons := fn_person_ids_array(p_person_ids);
    v_home := fn_home_of_routine(p_id);
    if v_home is null then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    perform fn_home_write_lock(v_home);
    select role into v_role from calendar_user
    where calendar_id = (select calendar_id from routine where id = p_id) and user_id = v_me for share;
    if v_role is null then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    -- 0029 (E2): tope adicional, permiso de edición en el ACL (owner o can_edit)
    if not fn_calendar_editable((select calendar_id from routine where id = p_id)) then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    if not fn_has_permission(v_home, 'routine.edit') then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    v_changed := v_persons is not null and v_persons is distinct from fn_routine_assigned_ids(p_id);
    if v_changed and not fn_has_permission(v_home, 'routine.assign') then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    v_now := to_char(now() at time zone p_timezone, 'YYYY-MM-DD HH24:MI:SS');
    -- Routine::update (Routine.php:108): available_from = now solo si pasa de inactiva a activa
    v_available := case when not v_active and p_active then v_now::timestamp
                       else (select available_from from routine where id = p_id) end;
    update routine
    set title = p_title, frequency = v_frequency::routine_frequency, "interval" = v_interval,
        days = p_days, time = p_time, start_date = p_start_date::date, end_date = p_end_date::date,
        active = p_active, available_from = v_available, updated_at = (now() at time zone 'UTC')
    where id = p_id;
    if v_changed then
        perform fn_sync_assignments('routine_person', 'routine_id', p_id, p_person_ids);
    end if;
    perform fn_materialize_one(p_id, p_timezone, true);
    return get_routine_detail(p_id);
end $$;

-- delete_routine: cuerpo de 0020_home_write_guards.sql + guardia de edición tras la ACL.
create or replace function delete_routine(p_id bigint, p_timezone text) returns json
language plpgsql security definer set search_path = public as $$
declare
    v_me bigint := fn_my_user_id();
    v_now text;
    v_home bigint;
    v_role user_role;
begin
    if v_me is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    -- 1.8 (§2.2/§2.3): lock → ACL → routine.delete
    v_home := fn_home_of_routine(p_id);
    if v_home is null then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    perform fn_home_write_lock(v_home);
    select role into v_role from calendar_user
    where calendar_id = (select calendar_id from routine where id = p_id) and user_id = v_me for share;
    if v_role is null then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    -- 0029 (E2): tope adicional, permiso de edición en el ACL (owner o can_edit)
    if not fn_calendar_editable((select calendar_id from routine where id = p_id)) then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    if not fn_has_permission(v_home, 'routine.delete') then
        raise exception 'Not Allowed' using errcode = '42501';
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
end $$;

-- materialize_routine: cuerpo de 0020_home_write_guards.sql + guardia de edición tras la ACL.
create or replace function materialize_routine(p_routine_id bigint, p_timezone text, p_reconcile boolean) returns void
language plpgsql security definer set search_path = public as $$
declare
    v_me bigint := fn_my_user_id();
    v_home bigint;
    v_role user_role;
begin
    if v_me is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    -- 1.8 (§2.2/§2.3): lock → ACL → routine.edit solo si p_reconcile (M15); sin permiso si no
    v_home := fn_home_of_routine(p_routine_id);
    if v_home is null then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    perform fn_home_write_lock(v_home);
    select role into v_role from calendar_user
    where calendar_id = (select calendar_id from routine where id = p_routine_id) and user_id = v_me for share;
    if v_role is null then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    -- 0029 (E2): tope adicional, permiso de edición en el ACL (owner o can_edit)
    if p_reconcile and not fn_calendar_editable((select calendar_id from routine where id = p_routine_id)) then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    if p_reconcile and not fn_has_permission(v_home, 'routine.edit') then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    perform fn_materialize_one(p_routine_id, p_timezone, p_reconcile);
end $$;

-- create_task: cuerpo de 0025_task_person_ids.sql + guardia de edición tras la ACL.
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
    -- 0029 (E2): tope adicional, permiso de edición en el ACL (owner o can_edit)
    if not fn_task_list_editable(p_task_list_id) then
        raise exception 'Not Allowed' using errcode = '42501';
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

-- update_task: cuerpo de 0025_task_person_ids.sql + guardia de edición tras la ACL.
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
    -- 0029 (E2): tope adicional, permiso de edición en el ACL (owner o can_edit)
    if not fn_task_list_editable(v_list) then
        raise exception 'Not Allowed' using errcode = '42501';
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

-- complete_task: cuerpo de 0020_home_write_guards.sql + guardia de edición tras la ACL.
create or replace function complete_task(p_id bigint, p_completed boolean) returns json
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
    -- 1.8 (§2.2/§2.3): lock (hogar de la tarea) → ACL → task.complete
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
    -- 0029 (E2): tope adicional, permiso de edición en el ACL (owner o can_edit)
    if not fn_task_list_editable(v_list) then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    if not fn_has_permission(v_home, 'task.complete') then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    update task
    set completed_at = case when p_completed then (now() at time zone 'UTC') else null end,
        updated_at = (now() at time zone 'UTC')
    where id = p_id;
    return get_task_detail(p_id);
end $$;

-- task_order: cuerpo de 0020_home_write_guards.sql + guardia de edición tras la ACL.
create or replace function task_order(p_id bigint, p_position integer) returns json
language plpgsql security definer set search_path = public as $$
declare
    v_me bigint := fn_my_user_id();
    v_list bigint;
    v_ids bigint[];
    v_rest bigint[];
    v_pos integer;
    v_home bigint;
    v_role user_role;
begin
    if v_me is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    -- 1.8 (§2.2/§2.3): lock (hogar de la tarea) → ACL → task.edit
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
    -- 0029 (E2): tope adicional, permiso de edición en el ACL (owner o can_edit)
    if not fn_task_list_editable(v_list) then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    if not fn_has_permission(v_home, 'task.edit') then
        raise exception 'Not Allowed' using errcode = '42501';
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
end $$;

-- delete_task: cuerpo de 0020_home_write_guards.sql + guardia de edición tras la ACL.
create or replace function delete_task(p_id bigint) returns json
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
    -- 1.8 (§2.2/§2.3): lock (hogar de la tarea) → ACL → task.delete
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
    -- 0029 (E2): tope adicional, permiso de edición en el ACL (owner o can_edit)
    if not fn_task_list_editable(v_list) then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    if not fn_has_permission(v_home, 'task.delete') then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    delete from task where id = p_id;
    return '{"success":true}'::json;
end $$;

-- update_calendar: cuerpo de 0020_home_write_guards.sql; nombre/color/orden con permiso de edición (E3, respuesta 2).
create or replace function update_calendar(p_id bigint, p_name text, p_color text, p_widget boolean, p_dashboard boolean) returns json
language plpgsql security definer set search_path = public as $$
declare
    v_me bigint := fn_my_user_id();
    v_role user_role;
    v_home bigint;
begin
    if v_me is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    -- 1.8 (§2.2/§2.3): lock del hogar primero → ACL tras el lock (for share) → owner → permiso
    v_home := fn_home_of_calendar(p_id);
    if v_home is null then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    perform fn_home_write_lock(v_home);
    select role into v_role from calendar_user where calendar_id = p_id and user_id = v_me for share;
    if v_role is null then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    -- Metadatos (name/color): owner + calendar.manage; solo widget/dashboard: basta la ACL (§5.1)
    if (p_name, p_color) is distinct from (select (name, color) from calendar where id = p_id)
       and (not fn_calendar_editable(p_id) or not fn_has_permission(v_home, 'calendar.manage')) then
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
end $$;

-- update_task_list: cuerpo de 0020_home_write_guards.sql; nombre/color/orden con permiso de edición (E3, respuesta 2).
create or replace function update_task_list(p_id bigint, p_name text, p_color text, p_sort text, p_widget boolean, p_dashboard boolean) returns json
language plpgsql security definer set search_path = public as $$
declare
    v_me bigint := fn_my_user_id();
    v_role user_role;
    v_home bigint;
begin
    if v_me is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    -- 1.8 (§2.2/§2.3): lock del hogar primero → ACL tras el lock (for share) → owner → permiso
    v_home := fn_home_of_task_list(p_id);
    if v_home is null then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    perform fn_home_write_lock(v_home);
    select role into v_role from task_list_user where task_list_id = p_id and user_id = v_me for share;
    if v_role is null then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    -- Metadatos (name/color/sort): owner + tasklist.manage; solo widget/dashboard: basta la ACL (§5.1)
    if (p_name, p_color, p_sort) is distinct from (select (name, color, sort::text) from task_list where id = p_id)
       and (not fn_task_list_editable(p_id) or not fn_has_permission(v_home, 'tasklist.manage')) then
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
end $$;

-- get_calendar_users: cuerpo de 0020_home_write_guards.sql + clave aditiva `can_edit` (E6).
create or replace function get_calendar_users(p_calendar_id bigint) returns json
language plpgsql stable security definer set search_path = public as $$
begin
    if fn_my_user_id() is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    -- 1.8 (§3.3): guardia de lectura (ACL o admin del hogar, Q1) en vez de ACL propia
    if not exists (select 1 from calendar c
                   where c.id = p_calendar_id and c.id in (select fn_visible_calendar_ids())) then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    return (
        select coalesce(json_agg(json_build_object(
            'cu_id', cu.id, 'user_id', u.id, 'name', u.name, 'email', u.email, 'role', cu.role, 'can_edit', (cu.role = 'owner' or cu.can_edit),
            'home_role', (select hm.role::text from home_membership hm
                          where hm.home_id = cu.home_id and hm.app_user_id = cu.user_id)
        ) order by (cu.role::text) collate "C", u.name collate "C"), '[]'::json)
        from calendar_user cu
        inner join app_user u on u.id = cu.user_id
        where cu.calendar_id = p_calendar_id
    );
end $$;

-- get_task_list_users: cuerpo de 0020_home_write_guards.sql + clave aditiva `can_edit` (E6).
create or replace function get_task_list_users(p_task_list_id bigint) returns json
language plpgsql stable security definer set search_path = public as $$
begin
    if fn_my_user_id() is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    -- 1.8 (§3.3): guardia de lectura (ACL o admin del hogar, Q1) en vez de ACL propia
    if not exists (select 1 from task_list tl
                   where tl.id = p_task_list_id and tl.id in (select fn_visible_task_list_ids())) then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    return (
        select coalesce(json_agg(json_build_object(
            'tlu_id', tlu.id, 'user_id', u.id, 'name', u.name, 'email', u.email, 'role', tlu.role, 'can_edit', (tlu.role = 'owner' or tlu.can_edit),
            'home_role', (select hm.role::text from home_membership hm
                          where hm.home_id = tlu.home_id and hm.app_user_id = tlu.user_id)
        ) order by (tlu.role::text) collate "C", u.name collate "C"), '[]'::json)
        from task_list_user tlu
        inner join app_user u on u.id = tlu.user_id
        where tlu.task_list_id = p_task_list_id
    );
end $$;

-- get_calendars: cuerpo de 0020_home_write_guards.sql + clave aditiva `can_edit` (E6).
create or replace function get_calendars() returns json
language plpgsql stable security definer set search_path = public as $$
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
            'widget', coalesce(cu.widget, false)::int,
            'dashboard', coalesce(cu.dashboard, false)::int,
            'upcoming_event_count', coalesce(ec.cnt, 0),
            'home_id', c.home_id,
            'can_edit', coalesce(cu.role = 'owner' or cu.can_edit, false)
        ) order by c.name collate "C"), '[]'::json)
        from calendar c
        -- 1.8 (§3.3): ACL izquierda (admin sin ACL: widget/dashboard false, A-5) + visibilidad
        -- fn_visible_calendar_ids (ACL ∪ admin, Q1)
        left join calendar_user cu on cu.calendar_id = c.id and cu.user_id = fn_my_user_id()
        left join lateral (
            select count(*) as cnt from event e
            where e.calendar_id = c.id and e.routine_id is null
              and e.date_at >= (now() at time zone 'UTC')
        ) ec on true
        where c.id in (select fn_visible_calendar_ids())
          and (fn_active_home_id() is null or c.home_id = fn_active_home_id())
    );
end $$;

-- get_task_lists: cuerpo de 0020_home_write_guards.sql + clave aditiva `can_edit` (E6).
create or replace function get_task_lists() returns json
language plpgsql stable security definer set search_path = public as $$
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
            'widget', coalesce(tlu.widget, false)::int,
            'dashboard', coalesce(tlu.dashboard, false)::int,
            'pending_task_count', coalesce(pc.cnt, 0),
            'home_id', tl.home_id,
            'can_edit', coalesce(tlu.role = 'owner' or tlu.can_edit, false)
        ) order by tl.name collate "C"), '[]'::json)
        from task_list tl
        -- 1.8 (§3.3): ACL izquierda (admin sin ACL: widget/dashboard false, A-5) + visibilidad
        -- fn_visible_task_list_ids (ACL ∪ admin, Q1)
        left join task_list_user tlu on tlu.task_list_id = tl.id and tlu.user_id = fn_my_user_id()
        left join lateral (
            select count(*) as cnt from task t
            where t.task_list_id = tl.id and t.completed_at is null
        ) pc on true
        where tl.id in (select fn_visible_task_list_ids())
          and (fn_active_home_id() is null or tl.home_id = fn_active_home_id())
    );
end $$;

-- ─────────────────── (e) Grants ───────────────────
-- Helpers sin ejecución externa (como los de 0020); RPC nuevas solo para authenticated.
revoke execute on function fn_calendar_editable(bigint), fn_task_list_editable(bigint)
    from public, anon, authenticated;
revoke all on function set_calendar_user_access(bigint, bigint, boolean),
    set_task_list_user_access(bigint, bigint, boolean) from public, anon;
grant execute on function set_calendar_user_access(bigint, bigint, boolean),
    set_task_list_user_access(bigint, bigint, boolean) to authenticated;

commit;
