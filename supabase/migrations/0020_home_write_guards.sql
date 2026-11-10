-- 0020_home_write_guards.sql — Enforcement de la matriz de permisos §3.4.1 (fase 1.8).
--
-- change: fase-1-8-matriz-permisos (plan.md ronda 1 + review ronda 2: R2-01 person_select con
-- `home_id = any (fn_my_home_ids())`; R2-02 recuento = 22 RPC de escritura con guardia).
-- * Helpers nuevos (10, §3.4): fn_home_write_lock (§2.2: home FOR KEY SHARE como PRIMER lock de
--   toda escritura de recurso; devuelve home_membership.id), fn_home_of_event/fn_home_of_routine,
--   fn_person_ids_array (§3.2: pasada 1 de 0011; null = no tocar), fn_event_assigned_ids/
--   fn_routine_assigned_ids (§3.2, R1-05: conjunto mostrado por el cliente), fn_visible_calendar_
--   ids/fn_visible_task_list_ids (§3.3: ACL ∪ admin) y fn_event_visible/fn_routine_visible.
--   Grants §3.6: solo fn_visible_*/fn_*_visible a authenticated (RLS); el resto sin ejecución
--   externa. Los helpers ACL de 0002/0012 (fn_my_calendar_ids, fn_my_task_list_ids,
--   fn_*_in_my_calendars, fn_materialize_my_routines) NO cambian (A-3).
-- * RLS SELECT (§3.3): las 8 policies de 0002 pasan a fn_visible_*/fn_*_visible y person_select a
--   home_id = any (fn_my_home_ids()) (D4: personas por hogar). Los *_user_select no cambian.
-- * Escritura (§3.1/§2.2/§2.3): 22 RPC con guardia (R2-02) — validación de entrada (P0001) →
--   lock del hogar → ACL tras el lock (for share) → owner → permiso del catálogo 0019. Orden
--   global de locks §3.7 (hogar → membresía → ACL → contenido → hijos; sin ciclos con 0018).
--   create_calendar/create_task_list: solo lock (alta raíz, miembro basta, Q2). create_person/
--   update_person/delete_person sin cambio (D15). Q-C (a): *.assign solo si el conjunto de
--   personas cambia (null = no tocar; [] = borrar todo; igual = sin permiso ni sync, A-13).
-- * Lectura (§3.3, Q1/S13): admin sin ACL ve su hogar (widget/dashboard false sin ACL propia,
--   A-5); personas por hogar en get_persons y fn_*_persons (D4/Q-G).
-- * fn_sync_assignments (§3.2/§3.4, R1-04): pasada 1 vía fn_person_ids_array; pasada 2 por hogar
--   del recurso (fn_home_of_event/fn_home_of_routine) en vez de por familia.
-- * materialize_routines_for (§3.8, Q-F (a)): materializa ACL ∪ admin por p_user_id (ruta de
--   lectura, service_role); fn_materialize_my_routines sin cambio (solo ACL).
-- Errores sin mensajes nuevos (§3.6): 'Not Found' P0002 → 500 legacy / 404 /home/*; 'Not Allowed'
-- 42501 → 403; 'Invalid person' P0001 → 400; validación de rutinas con los mensajes de
-- validate.ts:39-95 (§3.5). Sin rutas Edge ni plantillas nuevas (D-008).

begin;

-- ─────────────────── (a) Helpers nuevos (§3.4) y grants (§3.6) ───────────────────

-- §2.2: PRIMER lock de toda escritura de recurso: home FOR KEY SHARE (serializa con el
-- home FOR UPDATE de fn_home_mutation_guard, 0018:65: sin ciclos, orden global §3.7). Devuelve
-- home_membership.id del llamante (paso 4: la membresía es estable tras el lock). A-5 de 1.6:
-- hogar archived o inexistente o cabecera X-Home-Id ajena → 'Not Found' P0002.
create or replace function fn_home_write_lock(p_home_id bigint) returns bigint
language plpgsql security definer set search_path = public as $$
declare
    v_status home.status%type;
    v_mid bigint;
begin
    if p_home_id is null then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    select h.status into v_status from home h where h.id = p_home_id for key share;
    if not found or v_status <> 'active' then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    if fn_active_home_id() is not null and fn_active_home_id() <> p_home_id then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    select hm.id into v_mid from home_membership hm
    where hm.home_id = p_home_id and hm.app_user_id = fn_my_user_id();
    if v_mid is null then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    return v_mid;
end $$;

-- Hogar del evento/rutina vía calendar.home_id (el evento y la rutina no tienen home_id, R1-08).
create or replace function fn_home_of_event(p_event_id bigint) returns bigint
language sql stable security definer set search_path = public as $$
    select c.home_id from event e inner join calendar c on c.id = e.calendar_id
    where e.id = p_event_id
$$;

create or replace function fn_home_of_routine(p_routine_id bigint) returns bigint
language sql stable security definer set search_path = public as $$
    select c.home_id from routine r inner join calendar c on c.id = r.calendar_id
    where r.id = p_routine_id
$$;

-- §3.2: pasada 1 de 0011:61-73 (mismos errores) extraída a helper; null = 'no tocar' (igual que
-- update_event/create_event en 0011:166/207). Devuelve el array normalizado (distinct, ordenado;
-- el cast ::bigint va SOLO tras la validación jsonb → sin 22P02/22023/22003).
create or replace function fn_person_ids_array(p_person_ids jsonb) returns bigint[]
language plpgsql stable security definer set search_path = public as $$
begin
    if p_person_ids is null then
        return null;
    end if;
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
    return array(
        select distinct (e #>> '{}')::bigint
        from jsonb_array_elements(p_person_ids) e
        order by 1
    );
end $$;

-- §3.2 (R1-05): conjunto actual = lo que muestra el cliente: routine_person en sesión de rutina
-- (el cliente ve fn_event_persons) y event_person si no. Sin filtro de visibilidad (las personas
-- asignadas siempre son del hogar, trigger 0015 (iv)).
create or replace function fn_event_assigned_ids(p_event_id bigint) returns bigint[]
language sql stable security definer set search_path = public as $$
    select coalesce(array(
        select x.person_id from (
            select ep.person_id from event_person ep
            where e.routine_id is null and ep.event_id = e.id
            union
            select rp.person_id from routine_person rp where rp.routine_id = e.routine_id
        ) x order by x.person_id), array[]::bigint[])
    from event e where e.id = p_event_id
$$;

create or replace function fn_routine_assigned_ids(p_routine_id bigint) returns bigint[]
language sql stable security definer set search_path = public as $$
    select coalesce(array(
        select rp.person_id from routine_person rp
        where rp.routine_id = p_routine_id order by rp.person_id), array[]::bigint[])
$$;

-- §3.3 (Q1/S13): visibilidad de LECTURA = ACL ∪ admin del hogar (sin fn_is_home_admin por fila).
-- Las usan las policies y las RPC de lectura; no son oráculos de otros usuarios.
create or replace function fn_visible_calendar_ids() returns setof bigint
language sql stable security definer set search_path = public as $$
    select c.id from calendar c
    where c.id in (select cu.calendar_id from calendar_user cu where cu.user_id = fn_my_user_id())
       or c.home_id in (select hm.home_id from home_membership hm
                        where hm.app_user_id = fn_my_user_id() and hm.role = 'admin')
$$;

create or replace function fn_visible_task_list_ids() returns setof bigint
language sql stable security definer set search_path = public as $$
    select tl.id from task_list tl
    where tl.id in (select tlu.task_list_id from task_list_user tlu where tlu.user_id = fn_my_user_id())
       or tl.home_id in (select hm.home_id from home_membership hm
                         where hm.app_user_id = fn_my_user_id() and hm.role = 'admin')
$$;

create or replace function fn_event_visible(p_event_id bigint) returns boolean
language sql stable security definer set search_path = public as $$
    select exists (select 1 from event e where e.id = p_event_id
                   and e.calendar_id in (select fn_visible_calendar_ids()))
$$;

create or replace function fn_routine_visible(p_routine_id bigint) returns boolean
language sql stable security definer set search_path = public as $$
    select exists (select 1 from routine r where r.id = p_routine_id
                   and r.calendar_id in (select fn_visible_calendar_ids()))
$$;

-- Grants §3.6: fn_visible_*/fn_*_visible a authenticated (los usan las policies); el resto de
-- helpers sin ejecución externa (solo los llaman RPC SECURITY DEFINER).
revoke execute on function fn_home_write_lock(bigint), fn_home_of_event(bigint),
    fn_home_of_routine(bigint), fn_person_ids_array(jsonb), fn_event_assigned_ids(bigint),
    fn_routine_assigned_ids(bigint) from public, anon, authenticated;
revoke execute on function fn_visible_calendar_ids(), fn_visible_task_list_ids(),
    fn_event_visible(bigint), fn_routine_visible(bigint) from public, anon;
grant execute on function fn_visible_calendar_ids(), fn_visible_task_list_ids(),
    fn_event_visible(bigint), fn_routine_visible(bigint) to authenticated;

-- ─────────────────── (b) fn_sync_assignments por hogar (§3.2/§3.4) ───────────────────

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

-- ─────────────────── (b) RLS SELECT: visibilidad admin sin ACL (§3.3) ───────────────────
-- Las 8 policies de 0002 cambian su `using` (drop + create; los *_user_select no cambian).
-- R2-01: person_select usa `home_id = any (fn_my_home_ids())` (fn_my_home_ids devuelve
-- bigint[], no setof: `in (select …)` no compilaría). Sin policies de escritura.

drop policy if exists calendar_select on calendar;
create policy calendar_select on calendar for select to authenticated
    using (id in (select fn_visible_calendar_ids()));

drop policy if exists task_list_select on task_list;
create policy task_list_select on task_list for select to authenticated
    using (id in (select fn_visible_task_list_ids()));

drop policy if exists event_select on event;
create policy event_select on event for select to authenticated
    using (calendar_id in (select fn_visible_calendar_ids()));

drop policy if exists routine_select on routine;
create policy routine_select on routine for select to authenticated
    using (calendar_id in (select fn_visible_calendar_ids()));

drop policy if exists task_select on task;
create policy task_select on task for select to authenticated
    using (task_list_id in (select fn_visible_task_list_ids()));

drop policy if exists event_person_select on event_person;
create policy event_person_select on event_person for select to authenticated
    using (fn_event_visible(event_id));

drop policy if exists routine_person_select on routine_person;
create policy routine_person_select on routine_person for select to authenticated
    using (fn_routine_visible(routine_id));

drop policy if exists person_select on person;
create policy person_select on person for select to authenticated
    using (home_id = any (fn_my_home_ids()));

-- ─────────────────── (c) RPC de escritura con guardia (22, §3.1) ───────────────────

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
       and (v_role <> 'owner' or not fn_has_permission(v_home, 'calendar.manage')) then
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

create or replace function delete_calendar(p_id bigint) returns json
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
    if v_role <> 'owner' or not fn_has_permission(v_home, 'calendar.manage') then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    delete from calendar where id = p_id;
    return '{"success":true}'::json;
end $$;

create or replace function add_calendar_user(p_calendar_id bigint, p_email text) returns json
language plpgsql security definer set search_path = public as $$
declare
    v_me bigint := fn_my_user_id();
    v_role user_role;
    v_home bigint;
    v_target app_user%rowtype;
begin
    if v_me is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    -- 1.8 (§2.2/§2.3): lock del hogar (incluye la cabecera X-Home-Id) → ACL → owner →
    -- calendar.manage. Q3 (0014): email de no-miembro del hogar → 'Not Allowed'.
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
end $$;

create or replace function remove_calendar_user(p_calendar_id bigint, p_user_id bigint) returns json
language plpgsql security definer set search_path = public as $$
declare
    v_me bigint := fn_my_user_id();
    v_role user_role;
    v_home bigint;
begin
    if v_me is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    -- 1.8 (§2.2/§2.3): lock → ACL → último owner (403) → self (400) → owner (403) →
    -- calendar.manage (403). El último owner va ANTES del self: su autoretiro recibe 403 (M14) y
    -- el de un owner con reemplazo sigue recibiendo 400 (contrato, R1-07).
    v_home := fn_home_of_calendar(p_calendar_id);
    if v_home is null then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    perform fn_home_write_lock(v_home);
    select role into v_role from calendar_user where calendar_id = p_calendar_id and user_id = v_me for share;
    if v_role is null then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    if exists (select 1 from calendar_user
               where calendar_id = p_calendar_id and user_id = p_user_id and role = 'owner')
       and not exists (select 1 from calendar_user
                       where calendar_id = p_calendar_id and role = 'owner' and user_id <> p_user_id) then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    if p_user_id = v_me then
        raise exception 'User cannot remove themselves' using errcode = 'P0001';
    end if;
    if v_role <> 'owner' or not fn_has_permission(v_home, 'calendar.manage') then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    delete from calendar_user where calendar_id = p_calendar_id and user_id = p_user_id;
    return '{"status":"ok"}'::json;
end $$;

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
       and (v_role <> 'owner' or not fn_has_permission(v_home, 'tasklist.manage')) then
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

create or replace function delete_task_list(p_id bigint) returns json
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
    if v_role <> 'owner' or not fn_has_permission(v_home, 'tasklist.manage') then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    delete from task_list where id = p_id;
    return '{"success":true}'::json;
end $$;

create or replace function add_task_list_user(p_task_list_id bigint, p_email text) returns json
language plpgsql security definer set search_path = public as $$
declare
    v_me bigint := fn_my_user_id();
    v_role user_role;
    v_home bigint;
    v_target app_user%rowtype;
begin
    if v_me is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    -- 1.8 (§2.2/§2.3): lock del hogar (incluye la cabecera X-Home-Id) → ACL → owner →
    -- tasklist.manage. Q3 (0014): email de no-miembro del hogar → 'Not Allowed'.
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
end $$;

create or replace function remove_task_list_user(p_task_list_id bigint, p_user_id bigint) returns json
language plpgsql security definer set search_path = public as $$
declare
    v_me bigint := fn_my_user_id();
    v_role user_role;
    v_home bigint;
begin
    if v_me is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    -- 1.8 (§2.2/§2.3): lock → ACL → último owner (403) → self (400) → owner (403) →
    -- tasklist.manage (403). El último owner va ANTES del self (M14).
    v_home := fn_home_of_task_list(p_task_list_id);
    if v_home is null then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    perform fn_home_write_lock(v_home);
    select role into v_role from task_list_user where task_list_id = p_task_list_id and user_id = v_me for share;
    if v_role is null then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    if exists (select 1 from task_list_user
               where task_list_id = p_task_list_id and user_id = p_user_id and role = 'owner')
       and not exists (select 1 from task_list_user
                       where task_list_id = p_task_list_id and role = 'owner' and user_id <> p_user_id) then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    if p_user_id = v_me then
        raise exception 'User cannot remove themselves' using errcode = 'P0001';
    end if;
    if v_role <> 'owner' or not fn_has_permission(v_home, 'tasklist.manage') then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    delete from task_list_user where task_list_id = p_task_list_id and user_id = p_user_id;
    return '{"status":"ok"}'::json;
end $$;

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

create or replace function set_event_alarm(p_event_id bigint, p_alarm integer, p_timezone text) returns json
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
    -- 1.8 (§2.2/§2.3): lock → ACL (alarma propia, event_user) → materialización → lookup →
    -- escritura. Sin permiso de contenido (solo escribe la fila event_user del llamante).
    v_home := fn_home_of_event(p_event_id);
    if v_home is null then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    perform fn_home_write_lock(v_home);
    select role into v_role from calendar_user
    where calendar_id = (select calendar_id from event where id = p_event_id) and user_id = v_me for share;
    if v_role is null then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    -- EventAlarm.php:13: materializeForUser ANTES del lookup (interno, sin service_role)
    perform fn_materialize_my_routines(p_timezone);
    select e.routine_id, e.routine_date into v_routine_id, v_routine_date
    from event e where e.id = p_event_id;
    if not found then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    perform fn_apply_event_alarm(p_event_id, v_routine_id, v_routine_date, p_alarm, v_me);
    return get_event_detail(p_event_id);
end $$;

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

create or replace function set_routine_alarm(p_id bigint, p_alarm integer, p_timezone text) returns json
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
    -- 1.8 (§2.2/§2.3): lock → ACL (alarma propia, routine_user); sin permiso de contenido
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
    insert into routine_user (routine_id, user_id, alarm) values (p_id, v_me, p_alarm)
    on conflict (routine_id, user_id) do update set alarm = excluded.alarm;
    v_now := to_char(now() at time zone p_timezone, 'YYYY-MM-DD HH24:MI:SS');
    perform fn_sync_routine_alarms(p_id, v_now);
    return get_routine_detail(p_id);
end $$;

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
    if p_reconcile and not fn_has_permission(v_home, 'routine.edit') then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    perform fn_materialize_one(p_routine_id, p_timezone, p_reconcile);
end $$;

create or replace function create_task(p_task_list_id bigint, p_title text) returns json
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
    perform fn_reorder_tasks(p_task_list_id);
    return get_task_detail(v_id);
end $$;

create or replace function update_task(p_id bigint, p_title text) returns json
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
    perform fn_reorder_tasks(v_list);
    return get_task_detail(p_id);
end $$;

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
    if not fn_has_permission(v_home, 'task.complete') then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    update task
    set completed_at = case when p_completed then (now() at time zone 'UTC') else null end,
        updated_at = (now() at time zone 'UTC')
    where id = p_id;
    return get_task_detail(p_id);
end $$;

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
    if not fn_has_permission(v_home, 'task.delete') then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    delete from task where id = p_id;
    return '{"success":true}'::json;
end $$;

-- ─────────────────── (d) Altas raíz: solo lock del hogar (Q2) ───────────────────

create or replace function create_calendar(p_name text, p_color text, p_widget boolean, p_dashboard boolean) returns json
language plpgsql security definer set search_path = public as $$
declare
    v_me bigint := fn_my_user_id();
    v_home bigint;
    v_id bigint;
begin
    if v_me is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    v_home := fn_home_for_root_create();
    -- 1.8 (§3.1): alta raíz — solo lock del hogar (miembro basta, Q2); sin ACL ni permiso
    perform fn_home_write_lock(v_home);
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
end $$;

create or replace function create_task_list(p_name text, p_color text, p_sort text, p_widget boolean, p_dashboard boolean) returns json
language plpgsql security definer set search_path = public as $$
declare
    v_me bigint := fn_my_user_id();
    v_home bigint;
    v_id bigint;
begin
    if v_me is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    v_home := fn_home_for_root_create();
    -- 1.8 (§3.1): alta raíz — solo lock del hogar (miembro basta, Q2); sin ACL ni permiso
    perform fn_home_write_lock(v_home);
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
end $$;

-- ─────────────────── (e) RPC de lectura: admin sin ACL y personas por hogar (§3.3) ───────────────────

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
            'home_id', c.home_id
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
            'home_id', tl.home_id
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
            'cu_id', cu.id, 'user_id', u.id, 'name', u.name, 'email', u.email, 'role', cu.role,
            'home_role', (select hm.role::text from home_membership hm
                          where hm.home_id = cu.home_id and hm.app_user_id = cu.user_id)
        ) order by (cu.role::text) collate "C", u.name collate "C"), '[]'::json)
        from calendar_user cu
        inner join app_user u on u.id = cu.user_id
        where cu.calendar_id = p_calendar_id
    );
end $$;

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
            'tlu_id', tlu.id, 'user_id', u.id, 'name', u.name, 'email', u.email, 'role', tlu.role,
            'home_role', (select hm.role::text from home_membership hm
                          where hm.home_id = tlu.home_id and hm.app_user_id = tlu.user_id)
        ) order by (tlu.role::text) collate "C", u.name collate "C"), '[]'::json)
        from task_list_user tlu
        inner join app_user u on u.id = tlu.user_id
        where tlu.task_list_id = p_task_list_id
    );
end $$;

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

create or replace function get_tasks(p_dashboard boolean default null::boolean, p_task_list_id bigint default null::bigint, p_widget boolean default null::boolean) returns json
language sql stable set search_path = public as $$
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
        -- 1.8 (§3.3): visibilidad ACL ∪ admin (Q1)
        left join task_list_user tlu on tlu.task_list_id = tk.task_list_id and tlu.user_id = fn_my_user_id()
        where tk.task_list_id in (select fn_visible_task_list_ids())
          and (p_task_list_id is null or p_task_list_id = 0 or tk.task_list_id = p_task_list_id)
          and (p_widget is null or tlu.widget = p_widget)
          and (p_dashboard is null or tlu.dashboard = p_dashboard)
    ) t
$$;

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
        where r.calendar_id in (select fn_visible_calendar_ids())
    );
end $$;

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

create or replace function get_routine_detail(p_id bigint) returns json
language plpgsql stable security definer set search_path = public as $$
begin
    if fn_my_user_id() is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    if not fn_routine_visible(p_id) then
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

create or replace function get_task_detail(p_id bigint) returns json
language plpgsql stable security definer set search_path = public as $$
begin
    if fn_my_user_id() is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    if not exists (
        select 1 from task t
        where t.id = p_id and t.task_list_id in (select fn_visible_task_list_ids())
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
        -- 1.8 (§3.3, D4/Q-G): personas por HOGAR del evento (no por familia); visibilidad
        -- ACL ∪ admin (Q1)
        inner join person p on p.id = x.person_id and p.home_id = fn_home_of_event(p_event_id)
    ), '[]'::json)
    from event e
    where e.id = p_event_id
      and e.calendar_id in (select fn_visible_calendar_ids())
$$;

create or replace function fn_routine_persons(p_routine_id bigint) returns json
language sql stable security definer set search_path = public as $$
    select coalesce((
        select json_agg(json_build_object('id', p.id, 'user_id', p.user_id, 'name', p.name, 'color', p.color)
            order by translate(p.name, 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', 'abcdefghijklmnopqrstuvwxyz'), p.id)
        from routine_person rp
        -- 1.8 (§3.3, D4/Q-G): personas por HOGAR de la rutina (no por familia); visibilidad
        -- ACL ∪ admin (Q1)
        inner join person p on p.id = rp.person_id and p.home_id = fn_home_of_routine(p_routine_id)
        where rp.routine_id = p_routine_id
          and fn_routine_visible(p_routine_id)
    ), '[]'::json)
$$;

create or replace function get_persons(p_include_inactive boolean default false) returns json
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
            'editable', p.user_id = fn_my_user_id(),
            'home_member_id', p.home_member_id,
            'kind', hm.kind::text
        ) order by translate(p.name, 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', 'abcdefghijklmnopqrstuvwxyz'), p.id), '[]'::json)
        from person p
        inner join home_member hm on hm.id = p.home_member_id
        -- 1.8 (§3.3, D4/Q-G): personas por HOGAR del llamante (no por familia)
        where p.home_id = any (fn_my_home_ids())
          and (p_include_inactive or hm.status = 'active')
    );
end $$;

-- ─────────────────── (f) Materialización de lectura: ACL ∪ admin (§3.8, Q-F) ───────────────────

create or replace function materialize_routines_for(p_user_id bigint, p_timezone text) returns void
language plpgsql set search_path = public as $$
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
          -- 1.8 (§3.8, Q-F (a)): ACL ∪ admin del usuario p_user_id (sin auth.uid(): criterio por
          -- p_user_id, no por fn_is_home_admin). fn_materialize_my_routines sigue siendo solo ACL.
          and (exists (select 1 from calendar_user cu
                       where cu.calendar_id = routine.calendar_id and cu.user_id = p_user_id)
               or exists (select 1 from calendar c
                          inner join home_membership hm on hm.home_id = c.home_id
                          where c.id = routine.calendar_id
                            and hm.app_user_id = p_user_id and hm.role = 'admin'))
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

commit;
