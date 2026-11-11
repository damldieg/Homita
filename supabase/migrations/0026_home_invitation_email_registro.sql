-- 0026_home_invitation_email_registro.sql — El admin es siempre el primer miembro y las
-- invitaciones quedan ligadas a un email (change hogar-admin-miembro, opción B: la invitación
-- pendiente es el estado "en espera"; no se añade ningún valor a member_status).
--
-- Requiere 0023_create_home_admin_member.sql aplicada antes (create_home vincula al creador).
--
-- Contenido (una transacción, aditiva sobre 0022):
-- * (a) home_invitation.email: el admin lo indica al crear el código. Nullable solo para
--   invitaciones anteriores a esta migración (no se pueden registrar con ellas; sí aceptarlas
--   con sesión, como hoy). CHECK: minúsculas y formato básico.
-- * (b) fn_home_invitation_json expone email (solo a quien ya puede listar invitaciones).
-- * (c) (create_home NO se redefine aquí: la cubre 0023_create_home_admin_member.sql, de la
--   rama dc/tareas-asignar, que crea el home_member vinculado al creador. Esta migración
--   DEPENDE de ella para los registros nuevos; el backfill (g) cubre los hogares existentes.)
-- * (d) create_home_invitation(p_home_id, p_kind, p_member_id, p_email): email obligatorio y
--   válido ('Invalid email' P0001); 'Already member' si ya hay un miembro activo con ese mail en
--   el hogar. Sustituye la firma de 3 argumentos (se elimina para evitar ambigüedad en PostgREST).
-- * (e) accept_home_invitation(p_code): si la invitación tiene email, la cuenta que acepta debe
--   tener ese mismo email → 'Not Allowed' 42501 sin consumir.
-- * (f) check_home_invitation_for_signup(p_code, p_email): RPC pública (anon) para validar un
--   código antes de registrar. Devuelve {home_name, kind}; código inválido/caducado/usado/
--   revocado/hogar archivado → 'Not Found'; email distinto → 'Not Allowed'. No crea nada.
-- * (g) Backfill: cada hogar cuyo creador tiene membresía pero no tiene miembro vinculado
--   recibe uno (adult, activo) y su person. Hogares sin created_by se listan en NOTICE.
--
-- Rollback: scripts/supabase/rollback/rollback_0026.sql (restaura las firmas de 0022; no
-- borra los miembros creados por el backfill).

begin;

-- ─────────────────── (a) Columna email ───────────────────

alter table home_invitation add column email text;
alter table home_invitation add constraint home_invitation_email_format
    check (email is null or (email = lower(email) and email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'));

-- ─────────────────── (b) Salida con email ───────────────────

create or replace function fn_home_invitation_json(p_id bigint) returns json
language sql stable security definer set search_path = public as $$
    select json_build_object(
        'id', i.id, 'home_id', i.home_id, 'kind', i.kind::text, 'member_id', i.member_id,
        'member_name', hm.name, 'email', i.email, 'status', i.status,
        'expires_at', to_char(i.expires_at, 'YYYY-MM-DD HH24:MI:SS'),
        'created_by', i.created_by,
        'created_at', to_char(i.created_at, 'YYYY-MM-DD HH24:MI:SS'))
    from home_invitation i left join home_member hm on hm.id = i.member_id
    where i.id = p_id
$$;

-- ─────────────────── (d) create_home_invitation con email ───────────────────

drop function if exists create_home_invitation(bigint, text, bigint);

create or replace function create_home_invitation(
    p_home_id bigint, p_kind text, p_member_id bigint, p_email text
) returns json
language plpgsql security definer set search_path = public as $$
declare
    v_me bigint := fn_my_user_id();
    v_m home_member%rowtype;
    v_kind text;
    v_email text := lower(btrim(coalesce(p_email, '')));
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
    if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
        raise exception 'Invalid email' using errcode = 'P0001';
    end if;
    perform fn_home_mutation_guard(p_home_id);
    perform fn_require_permission(p_home_id, 'home.invite');
    if exists (select 1 from home_membership hm
                 join app_user u on u.id = hm.app_user_id
                where hm.home_id = p_home_id and lower(u.email) = v_email) then
        raise exception 'Already member' using errcode = 'P0001';
    end if;
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
    insert into home_invitation (home_id, kind, member_id, code_hash, status, expires_at, created_by, email)
    values (p_home_id, v_kind::member_kind, p_member_id,
            encode(sha256(convert_to(v_code, 'UTF8')), 'hex'), 'pending',
            (now() at time zone 'UTC') + interval '7 days', v_me, v_email)
    returning id into v_id;
    insert into audit_log (home_id, actor_app_user_id, action, target_type, target_id, payload)
    values (p_home_id, v_me, 'home.invitation.create', 'home_invitation', v_id,
            jsonb_build_object('invitation_id', v_id, 'kind', v_kind, 'member_id', p_member_id));
    return (fn_home_invitation_json(v_id)::jsonb || jsonb_build_object('code', v_code))::json;
end $$;

-- ─────────────────── (e) accept_home_invitation exige el email de la invitación ───────────────────

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
    v_my_email text;
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
    -- 0026: la invitación va ligada a un email; la cuenta que acepta debe tenerlo.
    if v_inv.email is not null then
        select lower(u.email) into v_my_email from app_user u where u.id = v_me;
        if v_my_email is distinct from v_inv.email then
            raise exception 'Not Allowed' using errcode = '42501';   -- no consume
        end if;
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

-- ─────────────────── (f) Chequeo de código para el registro (público) ───────────────────

-- Sin sesión (anon): el registro con código valida antes de crear la cuenta. Solo devuelve el
-- nombre del hogar y el tipo; nunca el código ni el hash. Código ausente o no válido → Not Found.
create or replace function check_home_invitation_for_signup(p_code text, p_email text)
returns json
language plpgsql stable security definer set search_path = public as $$
declare
    v_code text;
    v_hash text;
    v_inv home_invitation%rowtype;
    v_home_name text;
    v_home_status home_status;
begin
    v_code := lower(btrim(coalesce(p_code, ''), E' \t\r\n'));
    if v_code !~ '^[0-9a-f]{32}$' then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    v_hash := encode(sha256(convert_to(v_code, 'UTF8')), 'hex');
    select * into v_inv from home_invitation i where i.code_hash = v_hash;
    if not found or v_inv.status <> 'pending' or v_inv.expires_at <= (now() at time zone 'UTC') then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    select h.name, h.status into v_home_name, v_home_status from home h where h.id = v_inv.home_id;
    if not found or v_home_status = 'archived' then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    -- Sin email en la invitación (anterior a 0026) no se puede registrar con ella.
    if v_inv.email is null or lower(btrim(coalesce(p_email, ''))) <> v_inv.email then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    return json_build_object('home_name', v_home_name, 'kind', v_inv.kind::text);
end $$;

-- ─────────────────── (g) Backfill: creador sin miembro vinculado ───────────────────

do $$
declare
    r record;
    v_name text;
    v_color text;
    v_hm bigint;
    v_n integer := 0;
    v_sin_creador integer;
begin
    for r in
        select h.id as home_id, h.created_by, u.name as user_name
          from home h
          join app_user u on u.id = h.created_by
         where h.created_by is not null
           and exists (select 1 from home_membership hm
                        where hm.home_id = h.id and hm.app_user_id = h.created_by)
           and not exists (select 1 from home_member hm
                            where hm.home_id = h.id and hm.app_user_id = h.created_by)
    loop
        select f.v_name, f.v_color into v_name, v_color
          from fn_validate_person_fields(r.user_name, '#6923E2') f;
        insert into home_member (home_id, kind, name, color, status, app_user_id, created_by)
        values (r.home_id, 'adult', v_name, v_color, 'active', r.created_by, r.created_by)
        returning id into v_hm;
        insert into person (user_id, home_id, home_member_id, name, color)
        values (r.created_by, r.home_id, v_hm, v_name, v_color);
        v_n := v_n + 1;
    end loop;
    select count(*) into v_sin_creador from home where created_by is null;
    raise notice '0026 backfill: % miembro(s) creador(es) creados; % hogar(es) sin created_by', v_n, v_sin_creador;
end $$;

-- ─────────────────── (h) Grants ───────────────────

revoke all on function check_home_invitation_for_signup(text, text) from public;
grant execute on function check_home_invitation_for_signup(text, text) to anon, authenticated;

revoke all on function create_home_invitation(bigint, text, bigint, text), accept_home_invitation(text),
    fn_home_invitation_json(bigint) from public, anon;
grant execute on function create_home_invitation(bigint, text, bigint, text), accept_home_invitation(text)
    to authenticated;

commit;
