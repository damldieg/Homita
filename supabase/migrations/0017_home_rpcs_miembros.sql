-- 0017_home_rpcs_miembros.sql — Gestión de miembros (fase 1.5; plan 1.5 §4). Una sola
-- transacción. NO modifica 0001–0016 ni datos. Sin tablas, columnas, índices ni constraints nuevos.
--
-- Contenido:
-- * Helper fn_home_member_json (§4.1): forma HOME_MEMBER de /home/member/*; sin grant a
--   authenticated (solo lo llaman RPC SECURITY DEFINER).
-- * get_persons(p_include_inactive boolean default false) (§4.2): firma nueva (drop + create,
--   R1-03) con join home_member y filtro de activos; JSON con 'home_member_id' y 'kind'.
-- * create_person (retorno +home_member_id/+kind), update_person (autorización D15: creador o
--   home.members.manage) y delete_person (baja soft §1.4: home_member.status='inactive' + borra
--   event_person/routine_person por paridad Q1; la fila person NO se borra). D-d queda retirado
--   del camino de delete_person; fn_person_deleted y su trigger (0014c) se CONSERVAN para las
--   cascadas app_user→person→home_member (I5).
-- * RPC nuevas /home/member/* (§4.3): get_home_members, create_home_member, update_home_member.
--   Convención D-a: 'Not Found' = P0002, 'Not Allowed' = 42501, 'Invalid member' = P0001 (nuevo
--   en RPC_STATUS de la Edge). Guardia R1-04: v_me is null → 'Not Allowed' 42501 antes de todo.
--   update_home_member con guarda 'is distinct from' (R1-01): updated_at solo si cambia (K13).
-- * Grants (§4.4): 3 nuevas a authenticated; get_persons(boolean) a authenticated+service_role
--   con revoke obligatorio a public/anon; fn_home_member_json sin grants de ejecución externos.
-- * Sin cambios: fn_sync_assignments y triggers *_person_check (0015), delete_routine (0014f),
--   add_*_user (0014b), fn_event_persons/fn_routine_persons (0011), trigger 0014c.
-- * Nota de implementación: 'Invalid member' para kind nulo en create_home_member usa
--   coalesce (SQL 3-valued logic: `p_kind not in (…)` no lanza con null; §6.1 kind es req).
--
-- Rollback: scripts/supabase/rollback/rollback_0017.sql (cuerpos previos copiados byte a byte de
-- 0005/0006/0014). Precondición del rollback: sin home_member.status='inactive' (ver §4.6).

begin;

-- ─────────────────── (a) Helper de salida HOME_MEMBER (§4.1, sin grants) ───────────────────

create or replace function fn_home_member_json(p_id bigint) returns json
language sql stable security definer set search_path = public as $$
    select json_build_object(
        'id', hm.id, 'home_id', hm.home_id, 'kind', hm.kind::text,
        'name', hm.name, 'color', hm.color, 'status', hm.status::text,
        'linked', hm.app_user_id is not null,
        'created_at', to_char(hm.created_at, 'YYYY-MM-DD HH24:MI:SS'),
        'updated_at', to_char(hm.updated_at, 'YYYY-MM-DD HH24:MI:SS'))
    from home_member hm where hm.id = p_id
$$;
revoke all on function fn_home_member_json(bigint) from public, anon, authenticated;

-- ─────────────────── (b) Redefiniciones legacy (§4.2) ───────────────────

-- Person::findVisibleForUser + ciclo person↔home_member (§1.4): solo personas de miembros
-- activos salvo p_include_inactive (Edge personIdsOf lo pasa true: K11). 'editable' y orden sin
-- cambios; claves nuevas 'home_member_id' y 'kind' (contrato PERSON, §7).
drop function if exists get_persons();
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
        where p.user_id = any (fn_family_user_ids())
          and (p_include_inactive or hm.status = 'active')
    );
end $$;

-- create_person (0014:107-138) sin cambio de lógica; el retorno añade home_member_id y kind
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
            'editable', true,
            'home_member_id', p.home_member_id,
            'kind', hm.kind::text)
        from person p
        inner join home_member hm on hm.id = p.home_member_id
        where p.id = v_id
    );
end $$;

-- update_person (0014:141-174) + autorización D15 (§3.4, §6.3): creador o home.members.manage.
-- Admin no creador pasa de 500 a 200; co-miembro sin permiso pasa de 500 a 403; no miembro
-- sigue en 500 'Not Found' (fn_require_member, paridad legacy). R1-04: guardia v_me is null.
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
    -- diseno §3.4: sin cabecera, el hogar operado es el del recurso (fn_home_of_person);
    -- person inexistente → home null → fn_require_member lanza 'Not Found' (sin oráculo)
    v_home := fn_home_of_person(p_id);
    perform fn_require_member(v_home);
    if fn_active_home_id() is not null and fn_active_home_id() <> v_home then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    -- D15: creador o home.members.manage (miembro sin permiso → 42501 'Not Allowed')
    if not exists (select 1 from person where id = p_id and user_id = v_me) then
        perform fn_require_permission(v_home, 'home.members.manage');
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
            'editable', true,
            'home_member_id', p.home_member_id,
            'kind', hm.kind::text)
        from person p
        inner join home_member hm on hm.id = p.home_member_id
        where p.id = p_id
    );
end $$;

-- delete_person: sustituye el hard delete de 0006:181-194 por la baja soft (§1.4, §4.2): la fila
-- person NO se borra; home_member.status = 'inactive' (solo si estaba active: idempotente) y se
-- borran las asignaciones event_person/routine_person por paridad Q1 (el histórico de eventos
-- queda sin la persona, como el ON DELETE CASCADE de 0001:151,157). Mismas comprobaciones de
-- autorización que update_person (D15, R1-04).
create or replace function delete_person(p_id bigint) returns json
language plpgsql security definer set search_path = public as $$
declare
    v_me bigint := fn_my_user_id();
    v_home bigint;
begin
    if v_me is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    v_home := fn_home_of_person(p_id);
    perform fn_require_member(v_home);
    if fn_active_home_id() is not null and fn_active_home_id() <> v_home then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    if not exists (select 1 from person where id = p_id and user_id = v_me) then
        perform fn_require_permission(v_home, 'home.members.manage');
    end if;
    update home_member set status = 'inactive', updated_at = (now() at time zone 'UTC')
     where id = (select home_member_id from person where id = p_id) and status = 'active';
    delete from event_person   where person_id = p_id;
    delete from routine_person where person_id = p_id;
    return '{"success":true}'::json;
end $$;

-- ─────────────────── (c) RPC nuevas /home/member/* (§4.3) ───────────────────

-- GET /home/member: miembros del hogar (activos e inactivos; orden status collate "C" →
-- 'active' antes que 'inactive', luego name, id). home.view; cabecera ≠ p_home_id → 'Not Found'.
create or replace function get_home_members(p_home_id bigint) returns json
language plpgsql stable security definer set search_path = public as $$
begin
    if fn_my_user_id() is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    if fn_active_home_id() is not null and fn_active_home_id() <> p_home_id then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    perform fn_require_permission(p_home_id, 'home.view');
    return (
        select coalesce(json_agg(fn_home_member_json(hm.id)
            order by hm.status::text collate "C", hm.name collate "C", hm.id), '[]'::json)
        from home_member hm where hm.home_id = p_home_id
    );
end $$;

-- POST /home/member/create: miembro sin cuenta (app_user_id null; sin home_membership ni
-- membership_permission) + su person 1:1 (D12, I5). kind req en 5 valores (§3.1); nombre/color
-- por fn_validate_person_fields (color default '#6923E2'). home.members.manage.
create or replace function create_home_member(
    p_home_id bigint, p_kind text, p_name text, p_color text
) returns json
language plpgsql security definer set search_path = public as $$
declare
    v_me bigint := fn_my_user_id();
    v_name text;
    v_color text;
    v_hm bigint;
begin
    if v_me is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    if fn_active_home_id() is not null and fn_active_home_id() <> p_home_id then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    perform fn_require_permission(p_home_id, 'home.members.manage');
    if coalesce(p_kind, '') not in ('adult', 'child', 'relative', 'guest', 'pet') then
        raise exception 'Invalid member' using errcode = 'P0001';
    end if;
    select f.v_name, f.v_color into v_name, v_color
      from fn_validate_person_fields(p_name, coalesce(p_color, '#6923E2')) f;
    insert into home_member (home_id, kind, name, color, status, created_by)
    values (p_home_id, p_kind::member_kind, v_name, v_color, 'active', v_me) returning id into v_hm;
    insert into person (user_id, home_id, home_member_id, name, color)
    values (v_me, p_home_id, v_hm, v_name, v_color);
    return fn_home_member_json(v_hm);
end $$;

-- PATCH /home/member/update: parámetros null = sin cambio (§6.1: clave ausente o JSON null).
-- 'for update' serializa PATCH concurrentes del mismo miembro. Guardas 'is distinct from' (R1-01):
-- sin cambios reales no se toca updated_at (K13 determinista). D12: person refleja name/color.
-- Re-alta (§3.5) = status 'active'. pet vinculado → 'Invalid member' (§3.1; la CHECK
-- home_member_pet_without_account es la barrera de segundo nivel).
create or replace function update_home_member(
    p_id bigint, p_kind text, p_name text, p_color text, p_status text
) returns json
language plpgsql security definer set search_path = public as $$
declare
    v_me bigint := fn_my_user_id();
    v_home bigint;
    v_linked bigint;
    v_kind text;
    v_name_cur text;
    v_color_cur text;
    v_status text;
    v_kind_new text;
    v_status_new text;
    v_name_new text;
    v_color_new text;
begin
    if v_me is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    select hm.home_id, hm.app_user_id, hm.kind::text, hm.name, hm.color, hm.status::text
      into v_home, v_linked, v_kind, v_name_cur, v_color_cur, v_status
      from home_member hm where hm.id = p_id for update;
    if not found then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    if fn_active_home_id() is not null and fn_active_home_id() <> v_home then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    perform fn_require_permission(v_home, 'home.members.manage');
    v_kind_new := coalesce(p_kind, v_kind);
    v_status_new := coalesce(p_status, v_status);
    if v_kind_new not in ('adult', 'child', 'relative', 'guest', 'pet')
       or v_status_new not in ('active', 'inactive') then
        raise exception 'Invalid member' using errcode = 'P0001';
    end if;
    if v_kind_new = 'pet' and v_linked is not null then
        raise exception 'Invalid member' using errcode = 'P0001';
    end if;
    select f.v_name, f.v_color into v_name_new, v_color_new
      from fn_validate_person_fields(coalesce(p_name, v_name_cur), coalesce(p_color, v_color_cur)) f;
    update home_member
       set kind = v_kind_new::member_kind, name = v_name_new, color = v_color_new,
           status = v_status_new::member_status, updated_at = (now() at time zone 'UTC')
     where id = p_id
       and (kind::text, name, color, status::text)
           is distinct from (v_kind_new, v_name_new, v_color_new, v_status_new);
    update person set name = v_name_new, color = v_color_new, updated_at = (now() at time zone 'UTC')
     where home_member_id = p_id and (name, color) is distinct from (v_name_new, v_color_new);
    return fn_home_member_json(p_id);
end $$;

-- ─────────────────── (d) Grants (§4.4) ───────────────────

revoke all on function get_home_members(bigint) from public, anon;
revoke all on function create_home_member(bigint, text, text, text) from public, anon;
revoke all on function update_home_member(bigint, text, text, text, text) from public, anon;
grant execute on function get_home_members(bigint) to authenticated;
grant execute on function create_home_member(bigint, text, text, text) to authenticated;
grant execute on function update_home_member(bigint, text, text, text, text) to authenticated;

-- get_persons(boolean): 'create' concede EXECUTE a PUBLIC por defecto; el revoke es obligatorio
-- (R1-03). create_person/update_person/delete_person conservan sus grants (create or replace).
revoke all on function get_persons(boolean) from public, anon;
grant execute on function get_persons(boolean) to authenticated, service_role;

commit;
