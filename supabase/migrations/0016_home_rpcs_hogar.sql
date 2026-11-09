-- 0016_home_rpcs_hogar.sql — Servicios y repositorios Home (fase 1.4; plan 1.4 §5, diseño §2.2,
-- §3.4, §5.2–§5.3). Una sola transacción. NO modifica 0001–0015.
--
-- Contenido:
-- * 6 RPC nuevas de /home/* (§5.1): get_homes, create_home, get_home_detail, update_home,
--   set_default_home, get_home_memberships. Convención D-a: 'Not Found' = P0002, 'Not Allowed' =
--   42501, validación = P0001. Cabecera: si fn_active_home_id() no es null y ≠ p_home_id →
--   'Not Found' P0002 (sin oráculo de existencia ni pertenencia).
-- * 6 RPC redefinidas (§5.2): solo se añade 'home_id' a la salida; get_calendars/get_task_lists
--   además filtran por el hogar activo (D-2) y exigen membresía del hogar de cabecera (R1-01,
--   para que una RPC directa con cabecera ajena devuelva 'Not Found' y no []).
-- * R1-02: guardia de nombre (btrim) y timezone opcional con default 'Europe/Madrid' en
--   create_home; update_home conserva la zona si p_timezone es null.
-- * R1-03: orden por (role::text) collate "C" (home_role es enum) y permissions con coalesce
--   para que nunca sea JSON null.
-- * Grants de las 6 nuevas: revoke a public/anon + grant a authenticated (mismo patrón que
--   0012/0014). Las redefinidas conservan sus grants con create or replace.
-- * Sin policies RLS, tablas o índices nuevos (fuera de 1.4).
--
-- Rollback: scripts/supabase/rollback/rollback_0016.sql (cuerpos previos copiados de
-- 0005/0006/0014 byte a byte).

begin;

-- ─────────────────────────── (a) RPC nuevas de /home/* (§5.1) ───────────────────────────

-- GET /home: mis hogares activos (A7: sin archived), orden home.id (A11), sin filtro por
-- cabecera (§5.1: el índice se lista completo aunque haya hogar activo).
create or replace function get_homes() returns json
language plpgsql stable security definer set search_path = public as $$
declare
    v_me bigint := fn_my_user_id();
begin
    if v_me is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    return (
        select coalesce(json_agg(json_build_object(
            'home_id', h.id, 'name', h.name, 'role', (hm.role::text),
            'is_default', coalesce(au.default_home_id = h.id, false),
            'is_personal', h.is_personal
        ) order by h.id), '[]'::json)
        from home_membership hm
        inner join home h on h.id = hm.home_id and h.status = 'active'
        inner join app_user au on au.id = hm.app_user_id
        where hm.app_user_id = v_me
    );
end $$;

-- POST /home/create: nuevo hogar con el creador de admin (trigger diferido de 0015 se cumple al
-- COMMIT de la llamada). R1-02: nombre con btrim obligatorio y timezone con default.
create or replace function create_home(p_name text, p_timezone text) returns json
language plpgsql security definer set search_path = public as $$
declare
    v_me bigint := fn_my_user_id();
    v_id bigint;
begin
    if v_me is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    if btrim(coalesce(p_name, '')) = '' then
        raise exception 'Name is required' using errcode = 'P0001';
    end if;
    insert into home (name, timezone, created_by)
    values (btrim(p_name), coalesce(p_timezone, 'Europe/Madrid'), v_me)
    returning id into v_id;
    insert into home_membership (home_id, app_user_id, role) values (v_id, v_me, 'admin');
    return (
        select json_build_object(
            'id', h.id, 'name', h.name, 'timezone', h.timezone, 'is_personal', h.is_personal,
            'created_at', to_char(h.created_at, 'YYYY-MM-DD HH24:MI:SS'),
            'updated_at', to_char(h.updated_at, 'YYYY-MM-DD HH24:MI:SS'))
        from home h where h.id = v_id
    );
end $$;

-- GET /home/detail: cabecera ≠ id → 'Not Found'; permiso home.view (no miembro → 'Not Found',
-- miembro sin permiso → 'Not Allowed').
create or replace function get_home_detail(p_home_id bigint) returns json
language plpgsql stable security definer set search_path = public as $$
begin
    if fn_active_home_id() is not null and fn_active_home_id() <> p_home_id then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    perform fn_require_permission(p_home_id, 'home.view');
    return (
        select json_build_object(
            'id', h.id, 'name', h.name, 'timezone', h.timezone, 'is_personal', h.is_personal,
            'created_at', to_char(h.created_at, 'YYYY-MM-DD HH24:MI:SS'),
            'updated_at', to_char(h.updated_at, 'YYYY-MM-DD HH24:MI:SS'))
        from home h where h.id = p_home_id
    );
end $$;

-- PATCH /home/update: permiso home.settings.manage. R1-02: nombre con btrim obligatorio;
-- timezone opcional (p_timezone null → conserva la zona actual).
create or replace function update_home(p_home_id bigint, p_name text, p_timezone text) returns json
language plpgsql security definer set search_path = public as $$
declare
    v_updated_at timestamp without time zone;
begin
    if fn_active_home_id() is not null and fn_active_home_id() <> p_home_id then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    perform fn_require_permission(p_home_id, 'home.settings.manage');
    if btrim(coalesce(p_name, '')) = '' then
        raise exception 'Name is required' using errcode = 'P0001';
    end if;
    update home
       set name = btrim(coalesce(p_name, name)),
           timezone = coalesce(p_timezone, timezone),
           updated_at = (now() at time zone 'UTC')
     where id = p_home_id
    returning updated_at into v_updated_at;
    return (
        select json_build_object(
            'id', h.id, 'name', h.name, 'timezone', h.timezone, 'is_personal', h.is_personal,
            'created_at', to_char(h.created_at, 'YYYY-MM-DD HH24:MI:SS'),
            'updated_at', to_char(h.updated_at, 'YYYY-MM-DD HH24:MI:SS'))
        from home h where h.id = p_home_id
    );
end $$;

-- PATCH /home/default: miembro basta (la FK compuesta de 0015 (default_home_id, id) →
-- home_membership garantiza la membresía de la fila resultante).
create or replace function set_default_home(p_home_id bigint) returns json
language plpgsql security definer set search_path = public as $$
declare
    v_me bigint := fn_my_user_id();
begin
    if v_me is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    if fn_active_home_id() is not null and fn_active_home_id() <> p_home_id then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    perform fn_require_member(p_home_id);
    update app_user set default_home_id = p_home_id where id = v_me;
    return json_build_object('default_home_id', p_home_id);
end $$;

-- GET /home/membership: permiso home.view. permissions = catálogo completo si role = 'admin'
-- (A4, sin filas en membership_permission), si no los permisos del snapshot del miembro.
-- R1-03: home_role es enum → cast a text para collate "C"; permissions nunca JSON null.
create or replace function get_home_memberships(p_home_id bigint) returns json
language plpgsql stable security definer set search_path = public as $$
begin
    if fn_active_home_id() is not null and fn_active_home_id() <> p_home_id then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    perform fn_require_permission(p_home_id, 'home.view');
    return (
        select coalesce(json_agg(json_build_object(
            'membership_id', hm.id, 'app_user_id', u.id, 'name', u.name, 'email', u.email,
            'role', (hm.role::text),
            'permissions', case when hm.role = 'admin' then (
                select coalesce(json_agg(pe.code order by pe.code collate "C"), '[]'::json)
                from permission pe)
            else (
                select coalesce(json_agg(mp.permission_code order by mp.permission_code collate "C"),
                                '[]'::json)
                from membership_permission mp where mp.home_membership_id = hm.id)
            end
        ) order by (hm.role::text) collate "C", u.name collate "C"), '[]'::json)
        from home_membership hm
        inner join app_user u on u.id = hm.app_user_id
        where hm.home_id = p_home_id
    );
end $$;

revoke all on function get_homes() from public, anon;
revoke all on function create_home(text, text) from public, anon;
revoke all on function get_home_detail(bigint) from public, anon;
revoke all on function update_home(bigint, text, text) from public, anon;
revoke all on function set_default_home(bigint) from public, anon;
revoke all on function get_home_memberships(bigint) from public, anon;
grant execute on function get_homes() to authenticated;
grant execute on function create_home(text, text) to authenticated;
grant execute on function get_home_detail(bigint) to authenticated;
grant execute on function update_home(bigint, text, text) to authenticated;
grant execute on function set_default_home(bigint) to authenticated;
grant execute on function get_home_memberships(bigint) to authenticated;

-- ─────────────── (b) RPC redefinidas (§5.2): solo 'home_id' + filtro D-2/R1-01 ───────────────

-- Calendar::findByUser (cuerpo de 0005:49-71) + 'home_id'. D-2: filtro por hogar activo.
-- R1-01: cabecera de hogar ajeno → 'Not Found' (antes que el filtro, para no devolver []).
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
end $$;

-- TaskList::findByUser (cuerpo de 0005:94-115) + 'home_id'. D-2 y R1-01 ídem.
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
end $$;

-- create_calendar (cuerpo de 0014:47-75) + 'home_id' en el JSON de retorno.
create or replace function create_calendar(
    p_name text, p_color text, p_widget boolean, p_dashboard boolean
) returns json
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
end $$;

-- create_task_list (cuerpo de 0014:77-105) + 'home_id' en el JSON de retorno.
create or replace function create_task_list(
    p_name text, p_color text, p_sort text, p_widget boolean, p_dashboard boolean
) returns json
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
end $$;

-- update_calendar (cuerpo de 0006:388-418) + 'home_id' en el JSON de retorno; autorización sin
-- cambios (la matriz §3.4.1 de escritura es de 1.8).
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
            'updated_at', to_char(c.updated_at, 'YYYY-MM-DD HH24:MI:SS'),
            'home_id', c.home_id)
        from calendar c where c.id = p_id
    );
end $$;

-- update_task_list (cuerpo de 0006:225-259) + 'home_id' en el JSON de retorno; autorización sin
-- cambios (1.8).
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
            'updated_at', to_char(tl.updated_at, 'YYYY-MM-DD HH24:MI:SS'),
            'home_id', tl.home_id)
        from task_list tl where tl.id = p_id
    );
end $$;

commit;
