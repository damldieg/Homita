-- rollback_0026.sql — Revierte 0026_home_invitation_email_registro.sql (change hogar-admin-miembro).
-- Restaura las definiciones de 0022 (fn_home_invitation_json,
-- create_home_invitation de 3 argumentos, accept_home_invitation) y elimina la columna
-- home_invitation.email, la constraint home_invitation_email_format y
-- check_home_invitation_for_signup(text, text).
--
-- NO borra (no es reversible sin perder datos):
-- * Los home_member / person creados por el backfill (g) de 0026 ni los creados por create_home
--   mientras 0026 estuvo aplicada. Siguen en la BD, vinculados a sus creadores.
-- * Los emails ya guardados en home_invitation: se pierden al borrar la columna.
-- * supabase_migrations.schema_migrations: la fila '0026' no se borra aquí; el check final FALLA
--   mientras exista, para que el operador decida (borrar el registro o re-aplicar 0026).
-- NO restaura create_home: su redefinición vive en 0023_create_home_admin_member.sql (rama
-- dc/tareas-asignar) y se revierte con su propio rollback.
-- Las funciones restauradas son copia literal de 0022.

begin;

drop function if exists check_home_invitation_for_signup(text, text);
drop function if exists create_home_invitation(bigint, text, bigint, text);

alter table home_invitation drop constraint if exists home_invitation_email_format;
alter table home_invitation drop column if exists email;

-- fn_home_invitation_json (0022 (b))
create or replace function fn_home_invitation_json(p_id bigint) returns json
language sql stable security definer set search_path = public as $$
    select json_build_object(
        'id', i.id, 'home_id', i.home_id, 'kind', i.kind::text, 'member_id', i.member_id,
        'member_name', hm.name, 'status', i.status,
        'expires_at', to_char(i.expires_at, 'YYYY-MM-DD HH24:MI:SS'),
        'created_by', i.created_by,
        'created_at', to_char(i.created_at, 'YYYY-MM-DD HH24:MI:SS'))
    from home_invitation i left join home_member hm on hm.id = i.member_id
    where i.id = p_id
$$;

-- create_home_invitation de 3 argumentos (0022)
create or replace function create_home_invitation(
    p_home_id bigint, p_kind text, p_member_id bigint
) returns json
language plpgsql security definer set search_path = public as $$
declare
    v_me bigint := fn_my_user_id();
    v_m home_member%rowtype;
    v_kind text;
    v_code text;
    v_id bigint;
begin
    if v_me is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    if p_home_id is null then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    if p_kind is not null and p_kind not in ('adult', 'child', 'relative', 'guest') then
        raise exception 'Invalid member' using errcode = 'P0001';   -- pet o fuera del enum
    end if;
    if p_kind is null and p_member_id is null then
        raise exception 'Invalid member' using errcode = 'P0001';
    end if;
    perform fn_home_mutation_guard(p_home_id);
    perform fn_require_permission(p_home_id, 'home.invite');
    if p_member_id is not null then
        -- Inexistente y de otro hogar dan el mismo error (sin oráculo de ids).
        select * into v_m from home_member hm where hm.id = p_member_id for update;
        if not found or v_m.home_id <> p_home_id or v_m.kind = 'pet' or v_m.status <> 'active'
           or v_m.app_user_id is not null or (p_kind is not null and p_kind <> v_m.kind::text) then
            raise exception 'Invalid member' using errcode = 'P0001';
        end if;
        v_kind := v_m.kind::text;
    else
        v_kind := p_kind;
    end if;
    if v_kind = 'adult' and not fn_is_home_admin(p_home_id) then
        raise exception 'Not Allowed' using errcode = '42501';      -- D-017
    end if;
    v_code := encode(extensions.gen_random_bytes(16), 'hex');
    insert into home_invitation (home_id, kind, member_id, code_hash, status, expires_at, created_by)
    values (p_home_id, v_kind::member_kind, p_member_id,
            encode(sha256(convert_to(v_code, 'UTF8')), 'hex'), 'pending',
            (now() at time zone 'UTC') + interval '7 days', v_me)
    returning id into v_id;
    insert into audit_log (home_id, actor_app_user_id, action, target_type, target_id, payload)
    values (p_home_id, v_me, 'home.invitation.create', 'home_invitation', v_id,
            jsonb_build_object('invitation_id', v_id, 'kind', v_kind, 'member_id', p_member_id));
    return (fn_home_invitation_json(v_id)::jsonb || jsonb_build_object('code', v_code))::json;
end $$;

-- accept_home_invitation (0022)
create or replace function accept_home_invitation(p_code text) returns json
language plpgsql security definer set search_path = public as $$
declare
    v_me bigint := fn_my_user_id();
    v_now timestamp without time zone := (now() at time zone 'UTC');
    v_code text;
    v_hash text;
    v_home bigint;
    v_status home_status;
    v_inv home_invitation%rowtype;
    v_m home_member%rowtype;
    v_kind member_kind;
    v_mid bigint;
    v_hm bigint;
    v_name text;
    v_color text;
    v_n integer;
begin
    if v_me is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    v_code := lower(btrim(coalesce(p_code, ''), E' \t\r\n'));   -- espacios y saltos de línea
    if v_code !~ '^[0-9a-f]{32}$' then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    v_hash := encode(sha256(convert_to(v_code, 'UTF8')), 'hex');
    -- Lectura previa sin lock: solo decide qué hogar bloquear.
    select i.home_id into v_home from home_invitation i where i.code_hash = v_hash;
    if not found then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    select h.status into v_status from home h where h.id = v_home for update;
    if not found or v_status = 'archived' then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    -- Relectura bajo el lock de hogar (paso 1 del diseño): pendiente y no caducada.
    select * into v_inv from home_invitation i
     where i.code_hash = v_hash and i.home_id = v_home
       and i.status = 'pending' and i.expires_at > v_now;
    if not found then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    if exists (select 1 from home_membership hm
               where hm.home_id = v_home and hm.app_user_id = v_me) then
        raise exception 'Already member' using errcode = 'P0001';   -- no consume (paso 2)
    end if;
    if v_inv.member_id is not null then
        select * into v_m from home_member hm where hm.id = v_inv.member_id for update;
        if not found or v_m.home_id <> v_home or v_m.kind = 'pet' or v_m.status <> 'active'
           or v_m.app_user_id is not null then
            raise exception 'Invalid member' using errcode = 'P0001';
        end if;
        if v_m.kind = 'adult' and v_inv.kind <> 'adult' then
            raise exception 'Invalid member' using errcode = 'P0001';   -- D-017
        end if;
        v_kind := v_m.kind;
    else
        v_kind := v_inv.kind;
    end if;
    insert into home_membership (home_id, app_user_id, role)
    values (v_home, v_me, 'member') returning id into v_mid;
    if v_inv.member_id is not null then
        update home_member set app_user_id = v_me, updated_at = v_now where id = v_inv.member_id;
        v_hm := v_inv.member_id;
    else
        select f.v_name, f.v_color into v_name, v_color
          from app_user u, fn_validate_person_fields(u.name, '#6923E2') f where u.id = v_me;
        insert into home_member (home_id, kind, name, color, status, app_user_id, created_by)
        values (v_home, v_kind, v_name, v_color, 'active', v_me, v_me) returning id into v_hm;
        insert into person (user_id, home_id, home_member_id, name, color)
        values (v_me, v_home, v_hm, v_name, v_color);
    end if;
    perform fn_seed_kind_permissions(v_mid, v_kind);
    perform 1 from home_invitation i where i.id = v_inv.id for update;
    update home_invitation
       set status = 'accepted', accepted_by = v_me, accepted_at = v_now, updated_at = v_now
     where id = v_inv.id and status = 'pending';
    get diagnostics v_n = row_count;
    if v_n = 0 then
        raise exception 'Not Found' using errcode = 'P0002';   -- deshace membresía y snapshot
    end if;
    insert into audit_log (home_id, actor_app_user_id, action, target_type, target_id, payload)
    values (v_home, v_me, 'home.invitation.accept', 'home_invitation', v_inv.id,
            jsonb_build_object('invitation_id', v_inv.id, 'membership_id', v_mid,
                               'member_id', v_hm, 'kind', v_kind::text));
    return json_build_object('home_id', v_home, 'membership_id', v_mid, 'member_id', v_hm,
                             'role', 'member', 'kind', v_kind::text);
end $$;

-- Grants (patrón 0022 (d) y 0016)
revoke all on function fn_home_invitation_json(bigint) from public, anon, authenticated;
revoke all on function create_home_invitation(bigint, text, bigint), accept_home_invitation(text)
    from public, anon;
grant execute on function create_home_invitation(bigint, text, bigint), accept_home_invitation(text)
    to authenticated;

commit;

-- Check post-rollback: falla si la migración 0026 sigue registrada.
do $$
begin
    if to_regclass('supabase_migrations.schema_migrations') is not null
       and exists (select 1 from supabase_migrations.schema_migrations where version = '0026') then
        raise exception 'rollback_0026: objetos revertidos, pero schema_migrations aún registra 0026 (borrar el registro en un paso confirmado aparte o re-aplicar 0026)';
    end if;
end $$;
