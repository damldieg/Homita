-- rollback_0017.sql — Rollback de 0017_home_rpcs_miembros.sql (fase 1.5, T2; plan §4.6).
-- Revierte 0017 dejando el estado previo: borra las 3 RPC /home/member/* y el helper
-- fn_home_member_json, elimina get_persons(boolean) y restaura get_persons() 0-arg con sus
-- grants de 0005 (R1-03) y los cuerpos de create_person/update_person (0014) y delete_person
-- hard (0006) copiados byte a byte de esos ficheros (md5(prosrc) = baseline pre-0017).
-- Precondición: no hay home_member.status='inactive' (si los hay, reactivarlos antes o aceptar
-- que el delete_person restaurado vuelva a borrar home_member vía trigger 0014c).
-- Re-aplicar 0017 tras el rollback es idempotente (drop … if exists + create or replace).
-- Uso: psql -v ON_ERROR_STOP=1 -1 -f rollback_0017.sql

begin;

-- ── (a) Se borran las RPC nuevas de /home/member/* y el helper de salida ──
drop function if exists get_home_members(bigint);
drop function if exists create_home_member(bigint, text, text, text);
drop function if exists update_home_member(bigint, text, text, text, text);
drop function if exists fn_home_member_json(bigint);

-- ── (b) get_persons vuelve a la firma 0-arg de 0005 (con sus grants) ──
drop function if exists get_persons(boolean);

create or replace function get_persons() returns json
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
            'editable', p.user_id = fn_my_user_id()
        ) order by translate(p.name, 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', 'abcdefghijklmnopqrstuvwxyz'), p.id), '[]'::json)
        from person p
        where p.user_id = any (fn_family_user_ids())
    );
end $$;

-- Grants de 0005:282,293 (R1-03): sin anon/PUBLIC; sí authenticated y service_role
revoke execute on function get_persons() from public, anon;
grant execute on function get_persons() to authenticated, service_role;

-- ── (c) Se restauran los cuerpos previos a 0017 (copias literales de 0014 y 0006) ──

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

create or replace function delete_person(p_id bigint) returns json
language plpgsql security definer set search_path = public as $$
declare
    v_me bigint := fn_my_user_id();
begin
    if v_me is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    if not exists (select 1 from person where id = p_id and user_id = v_me) then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    delete from person where id = p_id;
    return '{"success":true}'::json;
end $$;


commit;
