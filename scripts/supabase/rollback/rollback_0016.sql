-- rollback_0016.sql — Rollback de 0016_home_rpcs_hogar.sql (fase 1.4, T2; plan §5.3).
-- Revierte 0016 dejando el estado previo: borra las 6 RPC nuevas y restaura los cuerpos de las
-- 6 redefinidas tal cual estaban en 0005/0006/0014 (copias exactas extraídas de esos ficheros, no
-- de memoria, para que el md5(prosrc) vuelva al baseline). Precondición: 0016 aplicada.
-- Verificado en local: reset → 0016 → rollback → fnhash de las 6 = baseline pre-0016 (T2).
-- Uso: psql -v ON_ERROR_STOP=1 -1 -f rollback_0016.sql

begin;

-- ── (a) Se borran las 6 RPC nuevas de /home/* (§5.1) ──
drop function if exists get_homes();
drop function if exists create_home(text, text);
drop function if exists get_home_detail(bigint);
drop function if exists update_home(bigint, text, text);
drop function if exists set_default_home(bigint);
drop function if exists get_home_memberships(bigint);

-- ── (b) Se restauran los cuerpos previos a 0016 de las 6 redefinidas (§5.2) ──
-- Copias literales de: 0005_read_rpcs.sql:49-71 y 94-115, 0006_write_rpcs.sql:225-259 y 388-418,
-- 0014_home_compat.sql:47-75 y 77-105 (prosrc byte a byte = baseline).

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
            'updated_at', to_char(c.updated_at, 'YYYY-MM-DD HH24:MI:SS'))
        from calendar c where c.id = v_id
    );
end $$;

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
            'updated_at', to_char(tl.updated_at, 'YYYY-MM-DD HH24:MI:SS'))
        from task_list tl where tl.id = v_id
    );
end $$;

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


commit;
