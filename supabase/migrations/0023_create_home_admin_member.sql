-- 0023_create_home_admin_member.sql — El creador de un hogar figura como primer miembro (B068nfHn).
-- create_home (0016) insertaba home_membership (admin) pero no home_member, así que la lista de
-- miembros no mostraba al creador. Aditiva: redefine solo create_home; el resto de la función queda
-- igual. Mismo patrón que create_person/0014 (home_member kind adult, active, created_by = creador).
--
-- Rollback: volver a aplicar la definición de create_home de 0016_home_rpcs_hogar.sql.

create or replace function create_home(p_name text, p_timezone text) returns json
language plpgsql security definer set search_path = public as $$
declare
    v_me bigint := fn_my_user_id();
    v_id bigint;
    v_name text;
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
    -- Primer miembro: el propio admin (B068nfHn).
    select u.name into v_name from app_user u where u.id = v_me;
    insert into home_member (home_id, kind, name, status, app_user_id, created_by)
    values (v_id, 'adult', coalesce(nullif(btrim(v_name), ''), 'Admin'), 'active', v_me, v_me);
    return (
        select json_build_object(
            'id', h.id, 'name', h.name, 'timezone', h.timezone, 'is_personal', h.is_personal,
            'created_at', to_char(h.created_at, 'YYYY-MM-DD HH24:MI:SS'),
            'updated_at', to_char(h.updated_at, 'YYYY-MM-DD HH24:MI:SS'))
        from home h where h.id = v_id
    );
end $$;
