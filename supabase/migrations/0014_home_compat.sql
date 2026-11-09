-- 0014_home_compat.sql — Compatibilidad del modelo Home (fase 1.3; §7.1, §5.3, D7, D12, Q2, Q3,
-- D-010; cuerpos aprobados en plan 1.3 r2 §Cuerpos). Sin cambio de firma ni de respuesta (D-008):
-- (a) trigger de altas: hogar personal + membresía admin + default_home_id;
-- (b) RPC de alta raíz y person escriben home_id / home_member 1:1; add_*_user exige membresía
--     del hogar del recurso (Q3/D-c: email externo → 403 'Not Allowed' 42501);
-- (c) trigger de borrado de person → borra su home_member (puente D-d hasta 1.5);
-- (f) delete_routine copia al historial solo personas activas (§5.3).
--
-- Notas:
-- * D-a: 'Not Found' → P0002, 'Not Allowed' → 42501 (convención de 0005/0006/0008/0011).
-- * delete_person NO se redefine: el trigger (c) hace el trabajo (hard delete hasta 1.5).
-- * Con cabecera X-Home-Id (1.4+): si el hogar de la cabecera ≠ hogar del recurso/raíz →
--   'Not Found' P0002 (diseno §3.4). En 1.3 la Edge no propaga la cabecera (A-12).

-- ─────────────────────── (a) Altas: hogar personal atómico ───────────────────────
-- Sustituye 0004 (mismo trigger on_auth_user_created, mismo when (new.email is not null)).
-- Atomicidad: hogar + membresía admin en la misma transacción que app_user; el constraint trigger
-- diferido de 0015 exige admin al COMMIT (por eso el orden home → membership es válido).

create or replace function fn_auth_user_created() returns trigger
language plpgsql security definer set search_path = public as $$
declare
    v_user_id bigint;
    v_name text := coalesce(new.raw_user_meta_data->>'name', split_part(coalesce(new.email, ''), '@', 1));
    v_home bigint;
begin
    insert into app_user (auth_uid, name, email, created_at, updated_at)
    values (new.id, v_name, new.email, (now() at time zone 'UTC'), (now() at time zone 'UTC'))
    on conflict (auth_uid) do nothing
    returning id into v_user_id;
    if v_user_id is null then
        select id into v_user_id from app_user where auth_uid = new.id;
    end if;
    if exists (select 1 from home_membership where app_user_id = v_user_id) then
        return new;  -- ya tiene hogar (usuario previo o re-ejecución): no duplicar
    end if;
    insert into home (name, is_personal, created_by) values ('Hogar de ' || v_name, true, v_user_id)
    returning id into v_home;
    insert into home_membership (home_id, app_user_id, role) values (v_home, v_user_id, 'admin');
    update app_user set default_home_id = v_home where id = v_user_id;
    return new;
end $$;
revoke execute on function fn_auth_user_created() from public, anon, authenticated;

-- ─────────────────────── (b) RPC de compatibilidad ───────────────────────

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

-- create_person (0006:131-152) + home_member 1:1 (D7, Q2: miembro del hogar sin permiso de gestión)
create or replace function create_person(p_name text, p_color text) returns json
language plpgsql security definer set search_path = public as $$
declare
    v_me bigint := fn_my_user_id();
    v_home bigint;
    v_name text;
    v_color text;
    v_hm bigint;
    v_id bigint;
begin
    if v_me is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    v_home := fn_home_for_root_create();
    if fn_active_home_id() is not null and fn_active_home_id() <> v_home then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    select f.v_name, f.v_color into v_name, v_color from fn_validate_person_fields(p_name, p_color) f;
    insert into home_member (home_id, kind, name, color, status, created_by)
    values (v_home, 'adult', v_name, v_color, 'active', v_me) returning id into v_hm;
    insert into person (user_id, home_id, home_member_id, name, color)
    values (v_me, v_home, v_hm, v_name, v_color) returning id into v_id;
    return (
        select json_build_object(
            'id', p.id, 'user_id', p.user_id, 'name', p.name, 'color', p.color,
            'created_at', to_char(p.created_at, 'YYYY-MM-DD HH24:MI:SS'),
            'updated_at', to_char(p.updated_at, 'YYYY-MM-DD HH24:MI:SS'),
            'editable', true)
        from person p where p.id = v_id
    );
end $$;

-- update_person (0006:154-179) + D12: home_member refleja nombre/color
create or replace function update_person(p_id bigint, p_name text, p_color text) returns json
language plpgsql security definer set search_path = public as $$
declare
    v_me bigint := fn_my_user_id();
    v_home bigint;
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
    -- diseno §3.4: sin cabecera, el hogar operado es el del recurso (fn_home_of_person)
    v_home := fn_home_of_person(p_id);
    if fn_active_home_id() is not null and fn_active_home_id() <> v_home then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    select f.v_name, f.v_color into v_name, v_color from fn_validate_person_fields(p_name, p_color) f;
    update person set name = v_name, color = v_color, updated_at = (now() at time zone 'UTC')
    where id = p_id;
    update home_member set name = v_name, color = v_color, updated_at = (now() at time zone 'UTC')
    where id = (select home_member_id from person where id = p_id);
    return (
        select json_build_object(
            'id', p.id, 'user_id', p.user_id, 'name', p.name, 'color', p.color,
            'created_at', to_char(p.created_at, 'YYYY-MM-DD HH24:MI:SS'),
            'updated_at', to_char(p.updated_at, 'YYYY-MM-DD HH24:MI:SS'),
            'editable', true)
        from person p where p.id = p_id
    );
end $$;

-- add_calendar_user (0008:9-38) + Q3/D-c: el invitado debe ser miembro del hogar del calendario
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
end $$;

-- add_task_list_user (0008:63-92) + Q3/D-c
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
end $$;

-- ─────────────────────── (c) Borrado de person → home_member (puente D-d hasta 1.5) ───────────────────────

create or replace function fn_person_deleted() returns trigger
language plpgsql security definer set search_path = public as $$
begin
    delete from home_member where id = old.home_member_id;  -- null en filas pre-backfill: no-op
    return null;
end $$;
create trigger person_after_delete_home_member after delete on person
    for each row execute function fn_person_deleted();
revoke execute on function fn_person_deleted() from public, anon, authenticated;

-- ─────────────────────── (f) delete_routine: copia al historial solo personas activas ───────────────────────
-- Sustituye 0006:619-644 (cuerpo idéntico salvo el INSERT): el trigger de 0015 rechazaría copiar
-- una persona inactive ('Invalid person' → 400 en delete_routine). En 1.3 no hay inactive (1.5).

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
    inner join person p on p.id = rp.person_id
    inner join home_member hm on hm.id = p.home_member_id and hm.status = 'active'
    where e.routine_id = p_id
    on conflict do nothing;
    update event set routine_id = null, routine_date = null where routine_id = p_id;
    delete from routine where id = p_id;
    return '{"success":true}'::json;
end $$;
