-- invitaciones_check.sql — Invitaciones y vinculación (fase 1.15, migración 0022).
-- Se ejecuta con psql DESPUÉS del reset 0001–0026 y la seed:
--   psql -v ON_ERROR_STOP=1 -f invitaciones_check.sql
-- Cada bloque DO emite 'ok Nx: …' o aborta con 'invitaciones Nx: …'.
--
-- N1 columnas/tipos/NOT NULL; N2 constraints (UNIQUE, 5 CHECK, 4 FK con su on delete); N3
-- índices; N4 RLS on, 0 policies en home_invitation, pg_policies global = baseline 0021, sin
-- privilegios de tabla ni secuencia para anon/authenticated; N5 proacl (4 RPC solo
-- authenticated, helper sin grants, anon sin EXECUTE real); N6 create (32 hex, hash = sha256,
-- +7 días, pending, código no guardado); N7 los 9 'Invalid member' de crear sin filas; N8
-- permisos de crear (+ D-017: solo admin crea adult); N9 accept genérico; N10 accept con miembro
-- (kind actual tras un cambio); N11 'Already member' sin consumir; N12 los 404 sin oráculo; N13
-- miembro que deja de ser válido entre crear y aceptar (+ D-017: pasa a adult) sin consumir;
-- N14 revoke; N15 get; N16 audit sin código ni hash; N17 add_*_user con email externo → Not
-- Allowed y md5(prosrc) = baseline 0021; N18 accept ignora la cabecera X-Home-Id; N19
-- normalización (mayúsculas y espacios); N20 invariantes tras las aceptaciones; N21 helper no
-- ejecutable por authenticated; N22 0 filas scratch al terminar.
--
-- Datos scratch 9971xx (usuarios auth_uid …0991–0996; 9970xx es de permisos_matriz_check.sql)
-- borrados al final. Impersonación vía set_config('request.jwt.claim.sub', …, true) y cabecera
-- X-Home-Id vía set_config('request.headers', …, true). Los códigos de invitación solo viven en
-- variables de los bloques (nunca se imprimen).

-- ── Guarda de BD local (R1-04 review 1.15) ──
-- Este fichero BORRA rangos fijos (9971xx) con session_replication_role = replica. Igual que la
-- guarda de host de contract_check.py/cross_tenant_check.py, sin override: solo se acepta una
-- conexión por socket Unix (p. ej. `docker exec … psql` dentro del contenedor local) o por
-- loopback (127.0.0.1/::1). Cualquier otra (pooler o host remoto) aborta antes de tocar datos.
-- ON_ERROR_STOP se fuerza aquí para que la guarda corte aunque se invoque sin `-v ON_ERROR_STOP=1`.

\set ON_ERROR_STOP 1
do $$
begin
    if inet_server_addr() is not null and host(inet_server_addr()) not in ('127.0.0.1', '::1') then
        raise exception 'invitaciones_check: solo BD local (socket o loopback); servidor %', host(inet_server_addr());
    end if;
end $$;

-- ── Helpers de sesión (pg_temp: desaparecen al cerrar psql) ──

create function pg_temp.as_user(p_n int, p_home bigint default null) returns void
language plpgsql as $$
begin
    perform set_config('request.jwt.claim.sub',
                       '00000000-0000-4000-8000-00000000099' || p_n::text, true);
    perform set_config('request.headers',
                       case when p_home is null then '' else json_build_object('x-home-id', p_home::text)::text end,
                       true);
end $$;

-- 'ok' o 'mensaje|sqlstate' (la sentencia fallida se deshace en su subtransacción)
create function pg_temp.try(p_sql text) returns text
language plpgsql as $$
begin
    execute p_sql;
    return 'ok';
exception when others then
    return sqlerrm || '|' || sqlstate;
end $$;

-- Códigos que un bloque posterior necesita (solo en la sesión; nunca se imprimen)
create temp table n_codes (k text primary key, code text not null);

create function pg_temp.clean() returns void
language plpgsql as $$
begin
    delete from audit_log where home_id between 997101 and 997103;
    delete from home_invitation where home_id between 997101 and 997103;
    delete from membership_permission where home_membership_id in (
        select id from home_membership where home_id between 997101 and 997103
           or app_user_id between 997101 and 997106);
    delete from home_membership where home_id between 997101 and 997103
        or app_user_id between 997101 and 997106;
    delete from person where home_id between 997101 and 997103 or user_id between 997101 and 997106;
    delete from home_member where home_id between 997101 and 997103;
    delete from calendar_user where calendar_id = 997101;
    delete from calendar where id = 997101;
    delete from task_list_user where task_list_id = 997101;
    delete from task_list where id = 997101;
    delete from home where id between 997101 and 997103;
    delete from app_user where id between 997101 and 997106;
    delete from auth.users where id in (
        '00000000-0000-4000-8000-000000000991', '00000000-0000-4000-8000-000000000992',
        '00000000-0000-4000-8000-000000000993', '00000000-0000-4000-8000-000000000994',
        '00000000-0000-4000-8000-000000000995', '00000000-0000-4000-8000-000000000996');
end $$;

-- ── Preámbulo scratch ──
-- Usuarios: A 997101 (…0991) admin de H; M 997102 (…0992) member adult de H sin home.invite;
-- I 997103 (…0993) member guest de H con home.invite (no admin, D-017); U 997104 (…0994) y
-- V 997105 (…0995) sin hogar (aceptan); X 997106 (…0996) admin de B.
-- Hogares: H 997101, B 997102, Arch 997103 (archived, A admin).
-- Miembros de H: 997111 adult, 997112 relative, 997113 pet, 997114 child inactive, 997115 adult
-- vinculado a M, 997116 guest, 997117 child; de B: 997118 adult. Todos con su person 1:1 (I5).

set session_replication_role = replica;
select pg_temp.clean();
insert into auth.users (id, email, raw_user_meta_data) values
    ('00000000-0000-4000-8000-000000000991', 'in-a@check.homita.example', '{"name":"IN-A"}'),
    ('00000000-0000-4000-8000-000000000992', 'in-m@check.homita.example', '{"name":"IN-M"}'),
    ('00000000-0000-4000-8000-000000000993', 'in-i@check.homita.example', '{"name":"IN-I"}'),
    ('00000000-0000-4000-8000-000000000994', 'in-u@check.homita.example', '{"name":"IN-U"}'),
    ('00000000-0000-4000-8000-000000000995', 'in-v@check.homita.example', '{"name":"IN-V"}'),
    ('00000000-0000-4000-8000-000000000996', 'in-x@check.homita.example', '{"name":"IN-X"}');
insert into app_user (id, auth_uid, name, email) values
    (997101, '00000000-0000-4000-8000-000000000991', 'IN-A', 'in-a@check.homita.example'),
    (997102, '00000000-0000-4000-8000-000000000992', 'IN-M', 'in-m@check.homita.example'),
    (997103, '00000000-0000-4000-8000-000000000993', 'IN-I', 'in-i@check.homita.example'),
    (997104, '00000000-0000-4000-8000-000000000994', 'IN-U', 'in-u@check.homita.example'),
    (997105, '00000000-0000-4000-8000-000000000995', 'IN-V', 'in-v@check.homita.example'),
    (997106, '00000000-0000-4000-8000-000000000996', 'IN-X', 'in-x@check.homita.example');
set session_replication_role = default;

begin;
insert into home (id, name, status, is_personal, created_by) values
    (997101, 'IN-Hogar H', 'active', false, 997101),
    (997102, 'IN-Hogar B', 'active', false, 997106),
    (997103, 'IN-Hogar Arch', 'archived', false, 997101);
insert into home_membership (id, home_id, app_user_id, role) values
    (997121, 997101, 997101, 'admin'),
    (997122, 997101, 997102, 'member'),
    (997123, 997101, 997103, 'member'),
    (997124, 997102, 997106, 'admin'),
    (997125, 997103, 997101, 'admin');
update app_user set default_home_id = 997101 where id in (997101, 997102, 997103);
update app_user set default_home_id = 997102 where id = 997106;
insert into home_member (id, home_id, kind, name, color, status, app_user_id, created_by) values
    (997111, 997101, 'adult', 'IN-Adulto', '#110000', 'active', null, 997101),
    (997112, 997101, 'relative', 'IN-Abuela', '#220000', 'active', null, 997101),
    (997113, 997101, 'pet', 'IN-Mascota', '#330000', 'active', null, 997101),
    (997114, 997101, 'child', 'IN-Inactivo', '#440000', 'inactive', null, 997101),
    (997115, 997101, 'adult', 'IN-M', '#550000', 'active', 997102, 997101),
    (997116, 997101, 'guest', 'IN-Huesped', '#660000', 'active', null, 997101),
    (997117, 997101, 'child', 'IN-Cambia', '#770000', 'active', null, 997101),
    (997118, 997102, 'adult', 'IN-OtroHogar', '#880000', 'active', null, 997106);
insert into person (user_id, home_id, home_member_id, name, color)
select coalesce(hm.app_user_id, hm.created_by), hm.home_id, hm.id, hm.name, hm.color
  from home_member hm where hm.id between 997111 and 997118;
insert into calendar (id, name, color, token, home_id) values (997101, 'IN-C1', '#111111', 'in-token-1', 997101);
insert into calendar_user (calendar_id, user_id, role, widget, dashboard, home_id) values
    (997101, 997101, 'owner', true, true, 997101);
insert into task_list (id, name, color, token, sort, home_id) values
    (997101, 'IN-L1', '#222222', 'in-token-2', 'title', 997101);
insert into task_list_user (task_list_id, user_id, role, widget, dashboard, home_id) values
    (997101, 997101, 'owner', true, true, 997101);
commit;
select fn_seed_kind_permissions(997122, 'adult');
select fn_seed_kind_permissions(997123, 'guest');
insert into membership_permission (home_membership_id, permission_code) values (997123, 'home.invite');

-- ── N1: columnas, tipos y NOT NULL ──

do $$
declare v text;
begin
    select string_agg(column_name || ':' || udt_name || ':' || is_nullable, ',' order by ordinal_position)
      into v from information_schema.columns
     where table_schema = 'public' and table_name = 'home_invitation';
    if v is distinct from 'id:int8:NO,home_id:int8:NO,kind:member_kind:NO,member_id:int8:YES,'
        'code_hash:text:NO,status:text:NO,expires_at:timestamp:NO,created_by:int8:YES,'
        'accepted_by:int8:YES,accepted_at:timestamp:YES,created_at:timestamp:NO,updated_at:timestamp:NO,email:text:YES' then
        raise exception 'invitaciones N1: columnas %', v;
    end if;
    if (select column_default from information_schema.columns
        where table_schema = 'public' and table_name = 'home_invitation' and column_name = 'status')
       <> '''pending''::text' then
        raise exception 'invitaciones N1: default de status';
    end if;
    raise notice 'ok N1: 13 columnas con tipos y NOT NULL del plan §1';
end $$;

-- ── N2: constraints (UNIQUE, 5 CHECK, 4 FK con su on delete) ──

do $$
declare v text;
begin
    select string_agg(conname || ':' || contype::text ||
                      case when contype = 'f' then ':' || confdeltype::text else '' end, ','
                      order by conname)
      into v from pg_constraint where conrelid = 'public.home_invitation'::regclass;
    if v is distinct from 'home_invitation_accepted_by_fkey:f:n,home_invitation_accepted_check:c,'
        'home_invitation_code_hash_format:c,home_invitation_code_hash_key:u,'
        'home_invitation_created_by_fkey:f:n,home_invitation_email_format:c,'
        'home_invitation_home_id_fkey:f:c,'
        'home_invitation_member_fk:f:c,home_invitation_no_pet:c,home_invitation_pkey:p,'
        'home_invitation_status_check:c' then
        raise exception 'invitaciones N2: constraints %', v;
    end if;
    if pg_get_constraintdef((select oid from pg_constraint where conname = 'home_invitation_member_fk'))
       <> 'FOREIGN KEY (member_id, home_id) REFERENCES home_member(id, home_id) ON DELETE CASCADE' then
        raise exception 'invitaciones N2: FK compuesta';
    end if;
    raise notice 'ok N2: UNIQUE code_hash, 5 CHECK y 4 FK (cascade/set null) del plan §1';
end $$;

-- ── N3: índices ──

do $$
declare v text;
begin
    select string_agg(indexname, ',' order by indexname) into v
      from pg_indexes where schemaname = 'public' and tablename = 'home_invitation';
    if v is distinct from 'home_invitation_code_hash_key,home_invitation_home_pending_idx,'
        'home_invitation_member_idx,home_invitation_pkey' then
        raise exception 'invitaciones N3: índices %', v;
    end if;
    if (select indexdef from pg_indexes where indexname = 'home_invitation_home_pending_idx')
       not like '%(home_id, id) WHERE (status = ''pending''::text)' then
        raise exception 'invitaciones N3: índice parcial de pendientes';
    end if;
    raise notice 'ok N3: pkey, UNIQUE code_hash, parcial (home_id, id) pending y member_id';
end $$;

-- ── N4: RLS sin policies y sin privilegios de tabla/secuencia ──

do $$
declare r record;
begin
    if not (select relrowsecurity from pg_class where oid = 'public.home_invitation'::regclass) then
        raise exception 'invitaciones N4: RLS desactivada';
    end if;
    if (select count(*) from pg_policies where tablename = 'home_invitation') <> 0 then
        raise exception 'invitaciones N4: home_invitation tiene policies (D-014)';
    end if;
    if (select count(*) || ':' || md5(string_agg(tablename || '.' || policyname || ':' || cmd || ':'
               || coalesce(qual, '') || ':' || coalesce(with_check, ''), ',' order by tablename, policyname))
        from pg_policies where schemaname = 'public') <> '15:922730919bcc294d24da4f6ccfc165f3' then
        raise exception 'invitaciones N4: pg_policies global ≠ baseline 0021';
    end if;
    for r in select rol, priv from unnest(array['anon', 'authenticated']) rol,
             unnest(array['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER']) priv loop
        if has_table_privilege(r.rol, 'public.home_invitation', r.priv) then
            raise exception 'invitaciones N4: % tiene % sobre home_invitation', r.rol, r.priv;
        end if;
    end loop;
    for r in select rol, priv from unnest(array['anon', 'authenticated']) rol,
             unnest(array['USAGE', 'SELECT', 'UPDATE']) priv loop
        if has_sequence_privilege(r.rol, 'public.home_invitation_id_seq', r.priv) then
            raise exception 'invitaciones N4: % tiene % sobre la secuencia', r.rol, r.priv;
        end if;
    end loop;
    raise notice 'ok N4: RLS on, 0 policies (D-014), pg_policies = baseline, sin privilegios anon/authenticated';
end $$;

-- ── N5: proacl (4 RPC solo authenticated; helper sin grants; anon sin EXECUTE real) ──

do $$
declare
    f text;
    v_acl text;
begin
    foreach f in array array['get_home_invitations(bigint)', 'create_home_invitation(bigint,text,bigint,text)',
                             'accept_home_invitation(text)', 'revoke_home_invitation(bigint,bigint)'] loop
        select coalesce(proacl::text, '') into v_acl from pg_proc where oid = to_regprocedure(f);
        if not has_function_privilege('authenticated', f, 'execute')
           or has_function_privilege('anon', f, 'execute')
           or v_acl like '%{=X%' or v_acl like '%,=X%' or v_acl like '%anon=%' then
            raise exception 'invitaciones N5: proacl de % = %', f, v_acl;
        end if;
    end loop;
    select coalesce(proacl::text, '') into v_acl from pg_proc
     where oid = to_regprocedure('fn_home_invitation_json(bigint)');
    if has_function_privilege('authenticated', 'fn_home_invitation_json(bigint)', 'execute')
       or has_function_privilege('anon', 'fn_home_invitation_json(bigint)', 'execute')
       or v_acl like '%{=X%' or v_acl like '%,=X%' or v_acl like '%anon=%'
       or v_acl like '%authenticated=%' then
        raise exception 'invitaciones N5: helper con grants externos (%)', v_acl;
    end if;
    set local role anon;
    begin
        perform accept_home_invitation('00000000000000000000000000000000');
        raise exception 'invitaciones N5: anon ejecutó accept_home_invitation';
    exception when insufficient_privilege then null;
    end;
    begin
        perform get_home_invitations(997101);
        raise exception 'invitaciones N5: anon ejecutó get_home_invitations';
    exception when insufficient_privilege then null;
    end;
    reset role;
    raise notice 'ok N5: 4 RPC solo authenticated, helper sin grants, anon sin EXECUTE';
end $$;

-- ── N6: create (32 hex, hash = sha256, +7 días, pending, código no guardado) ──

do $$
declare
    v jsonb;
    v_code text;
    r home_invitation%rowtype;
begin
    perform pg_temp.as_user(1);
    v := create_home_invitation(997101, 'guest', null, 'in-nuevo@check.homita.example')::jsonb;
    v_code := v->>'code';
    if v_code !~ '^[0-9a-f]{32}$' then
        raise exception 'invitaciones N6: código no es 32 hex';
    end if;
    select * into r from home_invitation where id = (v->>'id')::bigint;
    if r.code_hash <> encode(sha256(convert_to(v_code, 'UTF8')), 'hex')
       or r.code_hash <> encode(extensions.digest(v_code, 'sha256'), 'hex') then
        raise exception 'invitaciones N6: code_hash ≠ sha256(code)';
    end if;
    if r.expires_at - r.created_at <> interval '7 days' or r.status <> 'pending'
       or r.created_by <> 997101 or r.kind <> 'guest' or r.member_id is not null
       or r.accepted_at is not null or r.accepted_by is not null then
        raise exception 'invitaciones N6: fila % ≠ esperada', r.id;
    end if;
    if (select count(*) from home_invitation i where row_to_json(i)::text like '%' || v_code || '%') <> 0 then
        raise exception 'invitaciones N6: el código en claro está en alguna columna';
    end if;
    if (select array_agg(k order by k) from jsonb_object_keys(v) k)
       <> array['code', 'created_at', 'created_by', 'email', 'expires_at', 'home_id', 'id', 'kind',
                'member_id', 'member_name', 'status'] then
        raise exception 'invitaciones N6: claves de INVITATION_CREATED';
    end if;
    if r.email is distinct from 'in-nuevo@check.homita.example' or v->>'email' <> r.email then
        raise exception 'invitaciones N6: email no guardado/expuesto';
    end if;
    raise notice 'ok N6: create → código 32 hex, hash sha256, +7 días, pending, sin código en BD';
end $$;

-- ── N7: los 9 'Invalid member' de crear, sin insertar filas ──

do $$
declare
    v_n0 bigint;
    v_a0 bigint;
    s text;
    v_out text;
begin
    perform pg_temp.as_user(1);
    select count(*) into v_n0 from home_invitation;
    select count(*) into v_a0 from audit_log where home_id = 997101;
    foreach s in array array[
        'select create_home_invitation(997101, ''pet'', null, ''in-nuevo@check.homita.example'')',
        'select create_home_invitation(997101, null, null, ''in-nuevo@check.homita.example'')',
        'select create_home_invitation(997101, ''boss'', null, ''in-nuevo@check.homita.example'')',
        'select create_home_invitation(997101, null, 997113, ''in-nuevo@check.homita.example'')',
        'select create_home_invitation(997101, null, 997115, ''in-nuevo@check.homita.example'')',
        'select create_home_invitation(997101, null, 997114, ''in-nuevo@check.homita.example'')',
        'select create_home_invitation(997101, null, 997118, ''in-nuevo@check.homita.example'')',
        'select create_home_invitation(997101, null, 997199, ''in-nuevo@check.homita.example'')',
        'select create_home_invitation(997101, ''guest'', 997112, ''in-nuevo@check.homita.example'')'] loop
        v_out := pg_temp.try(s);
        if v_out <> 'Invalid member|P0001' then
            raise exception 'invitaciones N7: % → %', s, v_out;
        end if;
    end loop;
    if (select count(*) from home_invitation) <> v_n0
       or (select count(*) from audit_log where home_id = 997101) <> v_a0 then
        raise exception 'invitaciones N7: se insertaron filas';
    end if;
    raise notice 'ok N7: 9 × Invalid member (pet, vacío, boss, pet, vinculado, inactivo, otro hogar, inexistente, kind distinto) sin filas';
end $$;

-- ── N8: permisos de crear (+ D-017) ──

do $$
declare v_out text;
begin
    perform pg_temp.as_user(2);   -- M sin home.invite
    v_out := pg_temp.try('select create_home_invitation(997101, ''guest'', null, ''in-nuevo@check.homita.example'')');
    if v_out <> 'Not Allowed|42501' then raise exception 'invitaciones N8: member sin home.invite → %', v_out; end if;
    perform pg_temp.as_user(4);   -- U no miembro
    v_out := pg_temp.try('select create_home_invitation(997101, ''guest'', null, ''in-nuevo@check.homita.example'')');
    if v_out <> 'Not Found|P0002' then raise exception 'invitaciones N8: no miembro → %', v_out; end if;
    perform pg_temp.as_user(1, 997102);   -- A con cabecera ajena
    v_out := pg_temp.try('select create_home_invitation(997101, ''guest'', null, ''in-nuevo@check.homita.example'')');
    if v_out <> 'Not Found|P0002' then raise exception 'invitaciones N8: cabecera ajena → %', v_out; end if;
    perform pg_temp.as_user(1);
    v_out := pg_temp.try('select create_home_invitation(997103, ''guest'', null, ''in-nuevo@check.homita.example'')');
    if v_out <> 'Not Found|P0002' then raise exception 'invitaciones N8: archived → %', v_out; end if;
    v_out := pg_temp.try('select create_home_invitation(null, ''guest'', null, ''in-nuevo@check.homita.example'')');
    if v_out <> 'Not Found|P0002' then raise exception 'invitaciones N8: home null → %', v_out; end if;
    v_out := pg_temp.try('select create_home_invitation(997101, ''adult'', null, ''in-nuevo@check.homita.example'')');
    if v_out <> 'ok' then raise exception 'invitaciones N8: admin crea adult → %', v_out; end if;
    perform pg_temp.as_user(3);   -- I: member con home.invite, no admin
    v_out := pg_temp.try('select create_home_invitation(997101, ''guest'', null, ''in-nuevo@check.homita.example'')');
    if v_out <> 'ok' then raise exception 'invitaciones N8: con home.invite → %', v_out; end if;
    v_out := pg_temp.try('select create_home_invitation(997101, null, 997112, ''in-nuevo@check.homita.example'')');
    if v_out <> 'ok' then raise exception 'invitaciones N8: con home.invite + relative → %', v_out; end if;
    v_out := pg_temp.try('select create_home_invitation(997101, ''adult'', null, ''in-nuevo@check.homita.example'')');
    if v_out <> 'Not Allowed|42501' then raise exception 'invitaciones N8: D-017 adult genérica → %', v_out; end if;
    v_out := pg_temp.try('select create_home_invitation(997101, null, 997111, ''in-nuevo@check.homita.example'')');
    if v_out <> 'Not Allowed|42501' then raise exception 'invitaciones N8: D-017 miembro adult → %', v_out; end if;
    raise notice 'ok N8: sin home.invite 403, no miembro/cabecera/archived/null 404, home.invite ok, D-017 adult solo admin';
end $$;

-- ── N9: accept genérico (membresía member, snapshot exacto, home_member y person 1:1) ──

do $$
declare
    v jsonb;
    v_code text;
    v_inv bigint;
    r home_member%rowtype;
    p person%rowtype;
    v_snap text;
    v_def text;
begin
    perform pg_temp.as_user(1);
    v := create_home_invitation(997101, 'child', null, 'in-u@check.homita.example')::jsonb;
    v_code := v->>'code';
    v_inv := (v->>'id')::bigint;
    perform pg_temp.as_user(4);   -- U
    v := accept_home_invitation(v_code)::jsonb;
    insert into pg_temp.n_codes values ('N9', v_code);
    if (select array_agg(k order by k) from jsonb_object_keys(v) k)
       <> array['home_id', 'kind', 'member_id', 'membership_id', 'role'] then
        raise exception 'invitaciones N9: claves de INVITATION_ACCEPTED';
    end if;
    if (v->>'home_id')::bigint <> 997101 or v->>'role' <> 'member' or v->>'kind' <> 'child'
       or not exists (select 1 from home_membership where id = (v->>'membership_id')::bigint
                      and home_id = 997101 and app_user_id = 997104 and role = 'member') then
        raise exception 'invitaciones N9: respuesta/membresía %', v;
    end if;
    select string_agg(permission_code, ',' order by permission_code) into v_snap
      from membership_permission where home_membership_id = (v->>'membership_id')::bigint;
    select string_agg(permission_code, ',' order by permission_code) into v_def
      from member_kind_default where kind = 'child';
    if v_snap is distinct from v_def then
        raise exception 'invitaciones N9: snapshot % ≠ defaults child %', v_snap, v_def;
    end if;
    select * into r from home_member where id = (v->>'member_id')::bigint;
    if r.home_id <> 997101 or r.kind <> 'child' or r.name <> 'IN-U' or r.color <> '#6923E2'
       or r.app_user_id <> 997104 or r.created_by <> 997104 or r.status <> 'active' then
        raise exception 'invitaciones N9: home_member %', row_to_json(r);
    end if;
    select * into p from person where home_member_id = r.id;
    if not found or p.user_id <> 997104 or p.home_id <> 997101 or p.name <> 'IN-U' or p.color <> '#6923E2'
       or (select count(*) from person where home_member_id = r.id) <> 1 then
        raise exception 'invitaciones N9: person 1:1';
    end if;
    if not exists (select 1 from home_invitation where id = v_inv and status = 'accepted'
                   and accepted_by = 997104 and accepted_at is not null) then
        raise exception 'invitaciones N9: invitación no marcada accepted';
    end if;
    raise notice 'ok N9: accept genérico → member, snapshot child exacto, home_member + person 1:1, accepted';
end $$;

-- ── N10: accept con miembro (vincula, sin person nueva, snapshot por el kind ACTUAL) ──

do $$
declare
    v jsonb;
    v_code text;
    v_np bigint;
    v_snap text;
    v_def text;
begin
    perform pg_temp.as_user(1);
    v := create_home_invitation(997101, null, 997117, 'in-v@check.homita.example')::jsonb;   -- child
    v_code := v->>'code';
    if v->>'kind' <> 'child' or (v->>'member_id')::bigint <> 997117 or v->>'member_name' <> 'IN-Cambia' then
        raise exception 'invitaciones N10: create con miembro %', v - 'code';
    end if;
    update home_member set kind = 'relative' where id = 997117;   -- cambio entre crear y aceptar
    select count(*) into v_np from person where home_id = 997101;
    perform pg_temp.as_user(5);   -- V
    v := accept_home_invitation(v_code)::jsonb;
    if (v->>'member_id')::bigint <> 997117 or v->>'kind' <> 'relative' then
        raise exception 'invitaciones N10: respuesta %', v;
    end if;
    if (select app_user_id from home_member where id = 997117) <> 997105
       or (select count(*) from person where home_id = 997101) <> v_np
       or (select count(*) from person where home_member_id = 997117) <> 1 then
        raise exception 'invitaciones N10: vínculo o person';
    end if;
    select string_agg(permission_code, ',' order by permission_code) into v_snap
      from membership_permission where home_membership_id = (v->>'membership_id')::bigint;
    select string_agg(permission_code, ',' order by permission_code) into v_def
      from member_kind_default where kind = 'relative';
    if v_snap is distinct from v_def then
        raise exception 'invitaciones N10: snapshot ≠ defaults relative';
    end if;
    raise notice 'ok N10: accept con miembro → vincula sin person nueva, snapshot del kind actual (relative)';
end $$;

-- ── N11: 'Already member' sin consumir (0 escrituras) ──

do $$
declare
    v jsonb;
    v_code text;
    v_before text;
    v_after text;
    v_out text;
begin
    perform pg_temp.as_user(1);
    v := create_home_invitation(997101, 'guest', null, 'in-nuevo@check.homita.example')::jsonb;
    v_code := v->>'code';
    select (select count(*) from home_membership) || '/' || (select count(*) from home_member) || '/'
           || (select count(*) from person) || '/' || (select count(*) from membership_permission) || '/'
           || (select count(*) from audit_log) || '/' || (select count(*) from home_invitation where status = 'pending')
      into v_before;
    perform pg_temp.as_user(2);   -- M ya es miembro
    v_out := pg_temp.try(format('select accept_home_invitation(%L)', v_code));
    if v_out <> 'Already member|P0001' then
        raise exception 'invitaciones N11: miembro → %', v_out;
    end if;
    select (select count(*) from home_membership) || '/' || (select count(*) from home_member) || '/'
           || (select count(*) from person) || '/' || (select count(*) from membership_permission) || '/'
           || (select count(*) from audit_log) || '/' || (select count(*) from home_invitation where status = 'pending')
      into v_after;
    if v_before <> v_after
       or (select status from home_invitation where id = (v->>'id')::bigint) <> 'pending' then
        raise exception 'invitaciones N11: hubo escrituras (% → %)', v_before, v_after;
    end if;
    raise notice 'ok N11: Already member P0001, invitación pending y 0 escrituras';
end $$;

-- ── N12: los 404 sin oráculo (mismo mensaje y errcode) ──

do $$
declare
    v jsonb;
    v_used text;
    v_rev text;
    v_exp text;
    v_edge text;
    v_arch text := 'abcdefabcdefabcdefabcdefabcdef01';
    s text;
    v_i int := 0;
    v_out text;
    v_n0 bigint;
begin
    perform pg_temp.as_user(1);
    select code into v_used from pg_temp.n_codes where k = 'N9';   -- consumido de verdad en N9
    v := create_home_invitation(997101, 'guest', null, 'in-nuevo@check.homita.example')::jsonb;
    v_rev := v->>'code';
    perform revoke_home_invitation(997101, (v->>'id')::bigint);
    v := create_home_invitation(997101, 'guest', null, 'in-nuevo@check.homita.example')::jsonb;
    v_exp := v->>'code';
    update home_invitation set expires_at = (now() at time zone 'UTC') - interval '1 minute'
     where id = (v->>'id')::bigint;
    v := create_home_invitation(997101, 'guest', null, 'in-nuevo@check.homita.example')::jsonb;
    v_edge := v->>'code';
    update home_invitation set expires_at = (now() at time zone 'UTC') where id = (v->>'id')::bigint;
    insert into home_invitation (home_id, kind, code_hash, expires_at, created_by)
    values (997103, 'guest', encode(sha256(convert_to(v_arch, 'UTF8')), 'hex'),
            (now() at time zone 'UTC') + interval '7 days', 997101);
    select count(*) into v_n0 from home_membership;
    perform pg_temp.as_user(6);   -- X: no miembro de H ni de Arch
    foreach s in array array[
        'select accept_home_invitation(''0123456789abcdef0123456789abcdef'')',
        'select accept_home_invitation(''xyz'')',
        'select accept_home_invitation(null)',
        'select accept_home_invitation('''')',
        format('select accept_home_invitation(%L)', v_used),
        format('select accept_home_invitation(%L)', v_rev),
        format('select accept_home_invitation(%L)', v_exp),
        format('select accept_home_invitation(%L)', v_edge),
        format('select accept_home_invitation(%L)', v_arch)] loop
        v_i := v_i + 1;
        v_out := pg_temp.try(s);
        if v_out <> 'Not Found|P0002' then
            raise exception 'invitaciones N12: caso % → %', v_i, v_out;   -- sin imprimir el código
        end if;
    end loop;
    if (select count(*) from home_membership) <> v_n0 then
        raise exception 'invitaciones N12: se crearon membresías';
    end if;
    raise notice 'ok N12: desconocido, mal formado, null, vacío, usado, revocado, caducado, borde = now y archived → Not Found P0002';
end $$;

-- ── N13: miembro que deja de ser válido entre crear y aceptar → Invalid member sin consumir ──

do $$
declare
    v jsonb;
    v_code text;
    v_id bigint;
    v_out text;
    v_n0 bigint;
begin
    perform pg_temp.as_user(1);
    v := create_home_invitation(997101, null, 997116, 'in-x@check.homita.example')::jsonb;   -- guest
    v_code := v->>'code';
    v_id := (v->>'id')::bigint;
    select count(*) into v_n0 from home_membership;
    perform pg_temp.as_user(6);   -- X acepta
    -- (a) vinculado a otra cuenta (I, miembro de H)
    update home_member set app_user_id = 997103 where id = 997116;
    v_out := pg_temp.try(format('select accept_home_invitation(%L)', v_code));
    if v_out <> 'Invalid member|P0001' then raise exception 'invitaciones N13a: % ', v_out; end if;
    update home_member set app_user_id = null where id = 997116;
    -- (b) inactivo
    update home_member set status = 'inactive' where id = 997116;
    v_out := pg_temp.try(format('select accept_home_invitation(%L)', v_code));
    if v_out <> 'Invalid member|P0001' then raise exception 'invitaciones N13b: %', v_out; end if;
    update home_member set status = 'active' where id = 997116;
    -- (c) pasado a pet
    update home_member set kind = 'pet' where id = 997116;
    v_out := pg_temp.try(format('select accept_home_invitation(%L)', v_code));
    if v_out <> 'Invalid member|P0001' then raise exception 'invitaciones N13c: %', v_out; end if;
    -- (d) D-017: pasado a adult con una invitación no-adult
    update home_member set kind = 'adult' where id = 997116;
    v_out := pg_temp.try(format('select accept_home_invitation(%L)', v_code));
    if v_out <> 'Invalid member|P0001' then raise exception 'invitaciones N13d: %', v_out; end if;
    update home_member set kind = 'guest' where id = 997116;
    if (select status from home_invitation where id = v_id) <> 'pending'
       or (select count(*) from home_membership) <> v_n0
       or (select app_user_id from home_member where id = 997116) is not null then
        raise exception 'invitaciones N13: la invitación se consumió o hubo escrituras';
    end if;
    raise notice 'ok N13: vinculado, inactivo, pet y adult (D-017) → Invalid member sin consumir';
end $$;

-- ── N14: revoke ──

do $$
declare
    v jsonb;
    v_id bigint;
    v_acc bigint;
    v_exp bigint;
    v_out text;
begin
    perform pg_temp.as_user(1);
    v_id := (create_home_invitation(997101, 'guest', null, 'in-nuevo@check.homita.example')::jsonb->>'id')::bigint;
    v_exp := (create_home_invitation(997101, 'guest', null, 'in-nuevo@check.homita.example')::jsonb->>'id')::bigint;
    update home_invitation set expires_at = (now() at time zone 'UTC') - interval '1 second' where id = v_exp;
    select id into v_acc from home_invitation where home_id = 997101 and status = 'accepted' limit 1;
    perform pg_temp.as_user(2);   -- M sin home.invite
    v_out := pg_temp.try(format('select revoke_home_invitation(997101, %s)', v_id));
    if v_out <> 'Not Allowed|42501' then raise exception 'invitaciones N14: sin home.invite → %', v_out; end if;
    perform pg_temp.as_user(6);   -- X no miembro de H
    v_out := pg_temp.try(format('select revoke_home_invitation(997101, %s)', v_id));
    if v_out <> 'Not Found|P0002' then raise exception 'invitaciones N14: no miembro → %', v_out; end if;
    v_out := pg_temp.try(format('select revoke_home_invitation(997102, %s)', v_id));   -- su hogar B
    if v_out <> 'Not Found|P0002' then raise exception 'invitaciones N14: otro hogar → %', v_out; end if;
    perform pg_temp.as_user(1, 997102);
    v_out := pg_temp.try(format('select revoke_home_invitation(997101, %s)', v_id));
    if v_out <> 'Not Found|P0002' then raise exception 'invitaciones N14: cabecera ajena → %', v_out; end if;
    perform pg_temp.as_user(1);
    v_out := pg_temp.try('select revoke_home_invitation(null, null)');
    if v_out <> 'Not Found|P0002' then raise exception 'invitaciones N14: nulos → %', v_out; end if;
    v := revoke_home_invitation(997101, v_id)::jsonb;
    if v->>'status' <> 'revoked' or v ? 'code' or v ? 'code_hash' then
        raise exception 'invitaciones N14: respuesta %', v;
    end if;
    foreach v_out in array array[
        pg_temp.try(format('select revoke_home_invitation(997101, %s)', v_id)),
        pg_temp.try(format('select revoke_home_invitation(997101, %s)', v_acc)),
        pg_temp.try(format('select revoke_home_invitation(997101, %s)', v_exp)),
        pg_temp.try('select revoke_home_invitation(997101, 997199999)')] loop
        if v_out <> 'Not Found|P0002' then raise exception 'invitaciones N14: repetida/aceptada/caducada/inexistente → %', v_out; end if;
    end loop;
    perform pg_temp.as_user(3);   -- I con home.invite revoca una pendiente
    v_id := (create_home_invitation(997101, 'guest', null, 'in-nuevo@check.homita.example')::jsonb->>'id')::bigint;
    v_out := pg_temp.try(format('select revoke_home_invitation(997101, %s)', v_id));
    if v_out <> 'ok' then raise exception 'invitaciones N14: home.invite revoca → %', v_out; end if;
    raise notice 'ok N14: revoke pending → revoked; repetida, aceptada, caducada, inexistente, otro hogar → Not Found; permisos';
end $$;

-- ── N15: get (solo pendientes no caducadas del hogar, id desc, sin code_hash) ──

do $$
declare
    v jsonb;
    v_ids bigint[];
    v_exp bigint[];
    v_out text;
begin
    perform pg_temp.as_user(6);   -- una pendiente en B (no debe aparecer en H)
    perform create_home_invitation(997102, 'guest', null, 'in-nuevo@check.homita.example');
    perform pg_temp.as_user(1);
    v := get_home_invitations(997101)::jsonb;
    select array_agg((e->>'id')::bigint order by ord) into v_ids
      from jsonb_array_elements(v) with ordinality x(e, ord);
    select array_agg(id order by id desc) into v_exp from home_invitation
     where home_id = 997101 and status = 'pending' and expires_at > (now() at time zone 'UTC');
    if v_ids is distinct from v_exp or coalesce(array_length(v_ids, 1), 0) < 3 then
        raise exception 'invitaciones N15: ids % ≠ %', v_ids, v_exp;
    end if;
    if (select count(*) from jsonb_array_elements(v) e
        where e ? 'code' or e ? 'code_hash' or (e->>'home_id')::bigint <> 997101
           or e->>'status' <> 'pending') <> 0 then
        raise exception 'invitaciones N15: item con code/code_hash, otro hogar u otro estado';
    end if;
    perform pg_temp.as_user(3);
    if jsonb_array_length(get_home_invitations(997101)::jsonb) <> array_length(v_exp, 1) then
        raise exception 'invitaciones N15: home.invite no ve el listado';
    end if;
    perform pg_temp.as_user(2);
    v_out := pg_temp.try('select get_home_invitations(997101)');
    if v_out <> 'Not Allowed|42501' then raise exception 'invitaciones N15: sin home.invite → %', v_out; end if;
    perform pg_temp.as_user(6);
    v_out := pg_temp.try('select get_home_invitations(997101)');
    if v_out <> 'Not Found|P0002' then raise exception 'invitaciones N15: no miembro → %', v_out; end if;
    perform pg_temp.as_user(1, 997103);
    v_out := pg_temp.try('select get_home_invitations(997101)');
    if v_out <> 'Not Found|P0002' then raise exception 'invitaciones N15: cabecera ajena → %', v_out; end if;
    raise notice 'ok N15: get = pendientes no caducadas del hogar (id desc), sin code/code_hash; 403/404';
end $$;

-- ── N16: audit home.invitation.* sin código ni hash ──

do $$
begin
    if (select count(distinct action) from audit_log
        where home_id = 997101 and action in ('home.invitation.create', 'home.invitation.accept',
                                              'home.invitation.revoke')) <> 3 then
        raise exception 'invitaciones N16: faltan acciones de auditoría';
    end if;
    if (select count(*) from audit_log
        where action like 'home.invitation.%'
          and (payload ? 'code' or payload ? 'code_hash' or payload::text ~ '[0-9a-f]{32}')) <> 0 then
        raise exception 'invitaciones N16: payload con código o hash';
    end if;
    if exists (select 1 from audit_log a join home_invitation i on i.home_id = a.home_id
               where a.action like 'home.invitation.%' and a.payload::text like '%' || i.code_hash || '%') then
        raise exception 'invitaciones N16: payload con un code_hash';
    end if;
    raise notice 'ok N16: audit create/accept/revoke sin claves code/code_hash ni valores hex de 32/64';
end $$;

-- ── N17: add_*_user con email externo → Not Allowed y md5(prosrc) = baseline 0021 ──

do $$
declare v_out text;
begin
    if md5((select prosrc from pg_proc where oid = to_regprocedure('add_calendar_user(bigint,text)')))
       <> '834643af3167507c1e9fa9fa4b0a19d9'
       or md5((select prosrc from pg_proc where oid = to_regprocedure('add_task_list_user(bigint,text)')))
       <> 'f557fb36657c961147225e31cb7d701e' then
        raise exception 'invitaciones N17: add_*_user ≠ baseline 0021';
    end if;
    perform pg_temp.as_user(1);
    v_out := pg_temp.try('select add_calendar_user(997101, ''in-x@check.homita.example'')');
    if v_out <> 'Not Allowed|42501' then raise exception 'invitaciones N17: calendar → %', v_out; end if;
    v_out := pg_temp.try('select add_task_list_user(997101, ''in-x@check.homita.example'')');
    if v_out <> 'Not Allowed|42501' then raise exception 'invitaciones N17: task_list → %', v_out; end if;
    if (select count(*) from calendar_user where calendar_id = 997101) <> 1
       or (select count(*) from task_list_user where task_list_id = 997101) <> 1 then
        raise exception 'invitaciones N17: filas ACL nuevas';
    end if;
    raise notice 'ok N17: email externo en add_calendar_user/add_task_list_user → Not Allowed, cuerpos = 0021';
end $$;

-- ── N18: accept ignora request.headers con x-home-id ajeno ──

do $$
declare
    v jsonb;
    v_code text;
begin
    perform pg_temp.as_user(1);
    v_code := create_home_invitation(997101, 'guest', null, 'in-x@check.homita.example')::jsonb->>'code';
    perform pg_temp.as_user(6, 997102);   -- X con la cabecera de su hogar B
    v := accept_home_invitation(v_code)::jsonb;
    if (v->>'home_id')::bigint <> 997101
       or not exists (select 1 from home_membership where home_id = 997101 and app_user_id = 997106) then
        raise exception 'invitaciones N18: %', v;
    end if;
    raise notice 'ok N18: accept con X-Home-Id de otro hogar → ok en el hogar del código (D-015)';
end $$;

-- ── N19: normalización (mayúsculas, espacios y salto de línea) ──

do $$
declare
    v jsonb;
    v_code text;
begin
    perform pg_temp.as_user(6);   -- X invita en B
    v_code := create_home_invitation(997102, 'relative', null, 'in-a@check.homita.example')::jsonb->>'code';
    perform pg_temp.as_user(1);   -- A acepta en B
    v := accept_home_invitation('  ' || upper(v_code) || E'\n')::jsonb;
    if (v->>'home_id')::bigint <> 997102 or v->>'kind' <> 'relative' then
        raise exception 'invitaciones N19: %', v;
    end if;
    raise notice 'ok N19: código en mayúsculas con espacios/salto de línea → ok';
end $$;

-- ── N20: invariantes tras las aceptaciones ──

do $$
begin
    if (select count(*) from (select home_id, app_user_id from home_member where app_user_id is not null
                              group by 1, 2 having count(*) > 1) d) <> 0 then
        raise exception 'invitaciones N20: home_member_linked_key';
    end if;
    if (select count(*) from home_member hm where hm.app_user_id is not null
        and not exists (select 1 from home_membership m
                        where m.home_id = hm.home_id and m.app_user_id = hm.app_user_id)) <> 0 then
        raise exception 'invitaciones N20: FK compuesta home_member → membresía';
    end if;
    if (select count(*) from home_member hm left join person p on p.home_member_id = hm.id
        where hm.home_id between 997101 and 997102 and (p.id is null or p.home_id <> hm.home_id)) <> 0 then
        raise exception 'invitaciones N20: I5 person ↔ home_member';
    end if;
    if (select count(*) from home h where h.status = 'active'
        and not exists (select 1 from home_membership m where m.home_id = h.id and m.role = 'admin')) <> 0 then
        raise exception 'invitaciones N20: hogares activos sin admin';
    end if;
    if (select count(*) from membership_permission mp join home_membership m on m.id = mp.home_membership_id
        where m.role = 'admin') <> 0 then
        raise exception 'invitaciones N20: snapshot en admins';
    end if;
    raise notice 'ok N20: linked_key, FK compuesta, I5, hogares con admin y admins sin snapshot';
end $$;

-- ── N21: fn_home_invitation_json no ejecutable por authenticated ──

do $$
begin
    set local role authenticated;
    begin
        perform fn_home_invitation_json(1);
        raise exception 'invitaciones N21: authenticated ejecutó el helper';
    exception when insufficient_privilege then null;
    end;
    reset role;
    raise notice 'ok N21: fn_home_invitation_json → permission denied para authenticated';
end $$;

-- ── Limpieza de datos scratch 9971xx ──

set session_replication_role = replica;
select pg_temp.clean();
set session_replication_role = default;

-- ── N22: 0 filas scratch ──

do $$
begin
    if (select count(*) from home where id between 997101 and 997103) + (select count(*) from app_user where id between 997101 and 997106)
       + (select count(*) from home_member where home_id between 997101 and 997103)
       + (select count(*) from person where user_id between 997101 and 997106)
       + (select count(*) from home_membership where app_user_id between 997101 and 997106)
       + (select count(*) from home_invitation where home_id between 997101 and 997103)
       + (select count(*) from audit_log where home_id between 997101 and 997103)
       + (select count(*) from auth.users where email like 'in-_@check.homita.example') <> 0 then
        raise exception 'invitaciones N22: quedan filas scratch';
    end if;
    raise notice 'ok N22: 0 filas scratch 9971xx';
end $$;
