-- invitaciones_email_check.sql — Hogar con miembro creador e invitaciones ligadas a email
-- (change hogar-admin-miembro, migración 0026). Se ejecuta con psql DESPUÉS del reset 0001–0026
-- y la seed (solo BD local, nunca PROD):
--   psql -v ON_ERROR_STOP=1 -f invitaciones_email_check.sql
-- REQUIERE 0023_create_home_admin_member.sql (dc/tareas-asignar) aplicada ANTES de 0026: E1 y
-- los checks que usan create_home esperan que cree el home_member vinculado.
-- Cada bloque DO emite 'ok Ex: …' o aborta con 'invitaciones_email Ex: …'.
--
-- E1 create_home crea home_member adult activo vinculado + person 1:1, membresía admin y sin
-- snapshot de permisos; E2 create_home_invitation: 'Invalid email' (P0001) sin filas, 'Already
-- member' (P0001, case-insensitive) sin filas, ok guarda el email normalizado y lo expone;
-- E3 accept con email distinto → 'Not Allowed' 42501 sin consumir; con el email correcto vincula
-- (case-insensitive); E4 check_home_invitation_for_signup (anon): ok, 'Not Found' (inexistente,
-- mal formado, nulo, usada, revocada, caducada, hogar archivado) y 'Not Allowed' (email
-- distinto, nulo o invitación sin email), sin escrituras; E5 grants (anon solo el check;
-- create/accept solo authenticated); E6 0 filas scratch al terminar.
--
-- Datos scratch 9972xx (usuarios auth_uid …0981–…0984) borrados al final. Los códigos de
-- invitación solo viven en variables de los bloques (nunca se imprimen).

\set ON_ERROR_STOP 1
do $$
begin
    if inet_server_addr() is not null and host(inet_server_addr()) not in ('127.0.0.1', '::1') then
        raise exception 'invitaciones_email_check: solo BD local (socket o loopback); servidor %', host(inet_server_addr());
    end if;
end $$;

-- ── Helpers de sesión (pg_temp) ──

create function pg_temp.as_user(p_n int) returns void
language plpgsql as $$
begin
    perform set_config('request.jwt.claim.sub',
                       '00000000-0000-4000-8000-00000000098' || p_n::text, true);
    perform set_config('request.headers', '', true);
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

-- Igual que try, pero ejecutando con un rol de PostgREST (anon/authenticated)
create function pg_temp.try_as(p_role text, p_sql text) returns text
language plpgsql as $$
begin
    execute 'set local role ' || quote_ident(p_role);
    execute p_sql;
    reset role;
    return 'ok';
exception when others then
    reset role;
    return sqlerrm || '|' || sqlstate;
end $$;

create function pg_temp.clean() returns void
language plpgsql as $$
begin
    delete from audit_log where home_id between 997201 and 997203
        or home_id in (select id from home where name = 'T2-Nueva');
    delete from home_invitation where home_id between 997201 and 997203;
    delete from membership_permission where home_membership_id in (
        select id from home_membership where home_id between 997201 and 997203
           or app_user_id between 997201 and 997204
           or home_id in (select id from home where name = 'T2-Nueva'));
    delete from home_membership where home_id between 997201 and 997203
        or app_user_id between 997201 and 997204
        or home_id in (select id from home where name = 'T2-Nueva');
    delete from person where home_id between 997201 and 997203 or user_id between 997201 and 997204
        or home_id in (select id from home where name = 'T2-Nueva');
    delete from home_member where home_id between 997201 and 997203
        or home_id in (select id from home where name = 'T2-Nueva');
    delete from home where id between 997201 and 997203 or name = 'T2-Nueva';
    delete from app_user where id between 997201 and 997204;
    delete from auth.users where id in (
        '00000000-0000-4000-8000-000000000981', '00000000-0000-4000-8000-000000000982',
        '00000000-0000-4000-8000-000000000983', '00000000-0000-4000-8000-000000000984');
end $$;

-- ── Preámbulo scratch ──
-- Usuarios: A 997201 (…0981) admin de H; M 997202 (…0982) member de H; U 997203 (…0983) sin
-- hogar; X 997204 (…0984) sin hogar. Hogares: H 997201 (activo), Arch 997202 (archived, A admin).

set session_replication_role = replica;
select pg_temp.clean();
insert into auth.users (id, email, raw_user_meta_data) values
    ('00000000-0000-4000-8000-000000000981', 't2-a@check.homita.example', '{"name":"T2-A"}'),
    ('00000000-0000-4000-8000-000000000982', 't2-m@check.homita.example', '{"name":"T2-M"}'),
    ('00000000-0000-4000-8000-000000000983', 't2-u@check.homita.example', '{"name":"T2-U"}'),
    ('00000000-0000-4000-8000-000000000984', 't2-x@check.homita.example', '{"name":"T2-X"}');
insert into app_user (id, auth_uid, name, email) values
    (997201, '00000000-0000-4000-8000-000000000981', 'T2-A', 't2-a@check.homita.example'),
    (997202, '00000000-0000-4000-8000-000000000982', 'T2-M', 't2-m@check.homita.example'),
    (997203, '00000000-0000-4000-8000-000000000983', 'T2-U', 't2-u@check.homita.example'),
    (997204, '00000000-0000-4000-8000-000000000984', 'T2-X', 't2-x@check.homita.example');
set session_replication_role = default;

begin;
insert into home (id, name, status, is_personal, created_by) values
    (997201, 'T2-Hogar H', 'active', false, 997201),
    (997202, 'T2-Hogar Arch', 'archived', false, 997201);
insert into home_membership (id, home_id, app_user_id, role) values
    (997221, 997201, 997201, 'admin'),
    (997222, 997201, 997202, 'member'),
    (997223, 997202, 997201, 'admin');
insert into home_member (id, home_id, kind, name, color, status, app_user_id, created_by) values
    (997211, 997201, 'adult', 'T2-A', '#110000', 'active', 997201, 997201),
    (997212, 997201, 'adult', 'T2-M', '#220000', 'active', 997202, 997201);
insert into person (user_id, home_id, home_member_id, name, color)
select hm.app_user_id, hm.home_id, hm.id, hm.name, hm.color
  from home_member hm where hm.id between 997211 and 997212;
select fn_seed_kind_permissions(997222, 'adult');
commit;

-- Invitación sin email (anterior a 0026) y de hogar archivado, insertadas a mano
-- (código fijo: solo existe en esta BD scratch y se borra al final)
insert into home_invitation (home_id, kind, code_hash, status, expires_at, created_by, email) values
    (997201, 'guest', encode(sha256(convert_to('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa01', 'UTF8')), 'hex'),
     'pending', (now() at time zone 'UTC') + interval '7 days', 997201, null),
    (997202, 'guest', encode(sha256(convert_to('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa02', 'UTF8')), 'hex'),
     'pending', (now() at time zone 'UTC') + interval '7 days', 997201, 't2-x@check.homita.example');

create temp table e_codes (k text primary key, code text not null);

-- ── E1: create_home crea el miembro vinculado ──

do $$
declare
    v jsonb;
    v_id bigint;
    r home_member%rowtype;
begin
    perform pg_temp.as_user(3);   -- U sin hogar
    v := create_home('T2-Nueva', null)::jsonb;
    v_id := (v->>'id')::bigint;
    if not exists (select 1 from home_membership where home_id = v_id and app_user_id = 997203 and role = 'admin')
       or (select count(*) from home_membership where home_id = v_id) <> 1 then
        raise exception 'invitaciones_email E1: membresía admin única';
    end if;
    if (select count(*) from home_member where home_id = v_id) <> 1 then
        raise exception 'invitaciones_email E1: el hogar no tiene exactamente 1 home_member';
    end if;
    select * into r from home_member where home_id = v_id;
    if r.kind <> 'adult' or r.status <> 'active' or r.app_user_id <> 997203
       or r.name <> 'T2-U' or r.created_by <> 997203 then
        raise exception 'invitaciones_email E1: home_member %', row_to_json(r);
    end if;
    if (select count(*) from person where home_member_id = r.id) <> 1
       or not exists (select 1 from person p where p.home_member_id = r.id and p.user_id = 997203
                      and p.home_id = v_id and p.name = r.name and p.color = r.color) then
        raise exception 'invitaciones_email E1: person 1:1';
    end if;
    if exists (select 1 from membership_permission mp join home_membership m on m.id = mp.home_membership_id
               where m.home_id = v_id) then
        raise exception 'invitaciones_email E1: el admin no debe tener snapshot de permisos (A4)';
    end if;
    raise notice 'ok E1: create_home → membresía admin + home_member adult activo vinculado + person 1:1, sin snapshot';
end $$;

-- ── E2: create_home_invitation con email ──

do $$
declare
    v jsonb;
    v_n0 bigint;
    v_a0 bigint;
    s text;
    v_out text;
begin
    perform pg_temp.as_user(1);   -- A admin de H
    select count(*) into v_n0 from home_invitation;
    select count(*) into v_a0 from audit_log where home_id = 997201;
    foreach s in array array[
        'select create_home_invitation(997201, ''guest'', null, '''')',
        'select create_home_invitation(997201, ''guest'', null, ''   '')',
        'select create_home_invitation(997201, ''guest'', null, null)',
        'select create_home_invitation(997201, ''guest'', null, ''sin-arroba'')',
        'select create_home_invitation(997201, ''guest'', null, ''a@b'')',
        'select create_home_invitation(997201, ''guest'', null, ''a b@c.d'')'] loop
        v_out := pg_temp.try(s);
        if v_out <> 'Invalid email|P0001' then
            raise exception 'invitaciones_email E2: % → %', s, v_out;
        end if;
    end loop;
    -- Already member: miembros de H por email (case-insensitive, con espacios)
    v_out := pg_temp.try('select create_home_invitation(997201, ''guest'', null, ''t2-m@check.homita.example'')');
    if v_out <> 'Already member|P0001' then raise exception 'invitaciones_email E2: miembro → %', v_out; end if;
    v_out := pg_temp.try('select create_home_invitation(997201, ''guest'', null, ''  T2-A@Check.Homita.Example '')');
    if v_out <> 'Already member|P0001' then raise exception 'invitaciones_email E2: admin (mayúsculas) → %', v_out; end if;
    if (select count(*) from home_invitation) <> v_n0
       or (select count(*) from audit_log where home_id = 997201) <> v_a0 then
        raise exception 'invitaciones_email E2: los errores insertaron filas';
    end if;
    -- ok: guarda el email normalizado (trim + minúsculas) y lo expone
    v := create_home_invitation(997201, 'guest', null, '  T2-Nuevo@Check.Homita.Example ')::jsonb;
    if v->>'email' <> 't2-nuevo@check.homita.example'
       or (select email from home_invitation where id = (v->>'id')::bigint) <> 't2-nuevo@check.homita.example'
       or v->>'code' !~ '^[0-9a-f]{32}$' then
        raise exception 'invitaciones_email E2: email guardado/expuesto %', v - 'code';
    end if;
    if not exists (select 1 from jsonb_array_elements(get_home_invitations(997201)::jsonb) e
                   where (e->>'id')::bigint = (v->>'id')::bigint
                     and e->>'email' = 't2-nuevo@check.homita.example') then
        raise exception 'invitaciones_email E2: get_home_invitations no expone el email';
    end if;
    -- invitación a un miembro existente sin vincular: también exige email
    v_out := pg_temp.try('select create_home_invitation(997201, null, 997212, null)');
    if v_out not in ('Invalid email|P0001', 'Invalid member|P0001') then
        raise exception 'invitaciones_email E2: sin email con member_id → %', v_out;
    end if;
    -- la constraint de formato rechaza mayúsculas en la tabla
    v_out := pg_temp.try('update home_invitation set email = ''MAL@X.Y'' where id = ' || (v->>'id'));
    if v_out not like '%home_invitation_email_format%|23514' then
        raise exception 'invitaciones_email E2: constraint de email → %', v_out;
    end if;
    raise notice 'ok E2: Invalid email (6 casos) y Already member sin filas; ok guarda y expone el email normalizado';
end $$;

-- ── E3: accept con email distinto / correcto ──

do $$
declare
    v jsonb;
    v_code text;
    v_id bigint;
    v_before text;
    v_after text;
    v_out text;
begin
    perform pg_temp.as_user(1);
    v := create_home_invitation(997201, 'child', null, 't2-u@check.homita.example')::jsonb;
    v_code := v->>'code';
    v_id := (v->>'id')::bigint;
    insert into e_codes values ('E3', v_code);
    select (select count(*) from home_membership) || '/' || (select count(*) from home_member) || '/'
           || (select count(*) from person) || '/' || (select count(*) from membership_permission) || '/'
           || (select count(*) from audit_log) || '/'
           || (select count(*) from home_invitation where status = 'pending') into v_before;
    perform pg_temp.as_user(4);   -- X: email distinto
    v_out := pg_temp.try(format('select accept_home_invitation(%L)', v_code));
    if v_out <> 'Not Allowed|42501' then raise exception 'invitaciones_email E3: email distinto → %', v_out; end if;
    select (select count(*) from home_membership) || '/' || (select count(*) from home_member) || '/'
           || (select count(*) from person) || '/' || (select count(*) from membership_permission) || '/'
           || (select count(*) from audit_log) || '/'
           || (select count(*) from home_invitation where status = 'pending') into v_after;
    if v_before <> v_after or (select status from home_invitation where id = v_id) <> 'pending' then
        raise exception 'invitaciones_email E3: email distinto consumió o escribió (% → %)', v_before, v_after;
    end if;
    -- el email de la cuenta se compara sin distinguir mayúsculas
    update app_user set email = 'T2-U@Check.Homita.Example' where id = 997203;
    perform pg_temp.as_user(3);   -- U: email correcto
    v := accept_home_invitation(v_code)::jsonb;
    update app_user set email = 't2-u@check.homita.example' where id = 997203;
    if (v->>'home_id')::bigint <> 997201 or v->>'kind' <> 'child'
       or not exists (select 1 from home_membership where home_id = 997201 and app_user_id = 997203 and role = 'member')
       or not exists (select 1 from home_member where id = (v->>'member_id')::bigint
                      and app_user_id = 997203 and status = 'active')
       or (select status from home_invitation where id = v_id) <> 'accepted' then
        raise exception 'invitaciones_email E3: accept con el email correcto %', v;
    end if;
    -- invitación con member_id: el email también se exige y vincula al miembro existente
    perform pg_temp.as_user(1);
    insert into home_member (id, home_id, kind, name, color, status, app_user_id, created_by)
    values (997213, 997201, 'guest', 'T2-Huesped', '#330000', 'active', null, 997201);
    insert into person (user_id, home_id, home_member_id, name, color)
    values (997201, 997201, 997213, 'T2-Huesped', '#330000');
    v := create_home_invitation(997201, null, 997213, 't2-x@check.homita.example')::jsonb;
    v_code := v->>'code';
    perform pg_temp.as_user(3);   -- U ya es miembro: Already member tiene prioridad, sin consumir
    v_out := pg_temp.try(format('select accept_home_invitation(%L)', v_code));
    if v_out <> 'Already member|P0001' then raise exception 'invitaciones_email E3: miembro → %', v_out; end if;
    perform pg_temp.as_user(4);   -- X: email correcto, vincula
    v := accept_home_invitation(v_code)::jsonb;
    if (v->>'member_id')::bigint <> 997213
       or (select app_user_id from home_member where id = 997213) <> 997204 then
        raise exception 'invitaciones_email E3: accept con miembro no vinculó %', v;
    end if;
    raise notice 'ok E3: email distinto → Not Allowed 42501 sin consumir ni escribir; email correcto (case-insensitive) → vincula';
end $$;

-- ── E4: check_home_invitation_for_signup ──

do $$
declare
    v jsonb;
    v_code text;
    v_rev text;
    v_exp text;
    v_n0 bigint;
    v_i0 text;
    s text;
    v_out text;
    v_case int := 0;
begin
    perform pg_temp.as_user(1);
    v_code := create_home_invitation(997201, 'relative', null, 't2-nuevo2@check.homita.example')::jsonb->>'code';
    v := create_home_invitation(997201, 'guest', null, 't2-nuevo3@check.homita.example')::jsonb;
    v_rev := v->>'code';
    perform revoke_home_invitation(997201, (v->>'id')::bigint);
    v := create_home_invitation(997201, 'guest', null, 't2-nuevo4@check.homita.example')::jsonb;
    v_exp := v->>'code';
    update home_invitation set expires_at = (now() at time zone 'UTC') - interval '1 minute'
     where id = (v->>'id')::bigint;
    select count(*) into v_n0 from home_invitation;
    select string_agg(status, ',' order by id) into v_i0 from home_invitation where home_id between 997201 and 997202;
    -- ok como anon: email con mayúsculas y espacios, código con mayúsculas y espacios
    set local role anon;
    v := check_home_invitation_for_signup('  ' || upper(v_code) || E'\n', '  T2-Nuevo2@Check.Homita.Example ')::jsonb;
    reset role;
    if v->>'home_name' <> 'T2-Hogar H' or v->>'kind' <> 'relative'
       or (select array_agg(k order by k) from jsonb_object_keys(v) k) <> array['home_name', 'kind'] then
        raise exception 'invitaciones_email E4: respuesta ok %', v;
    end if;
    -- Not Found: sin oráculo (mismo mensaje y errcode)
    foreach s in array array[
        'select check_home_invitation_for_signup(''0123456789abcdef0123456789abcdef'', ''t2-nuevo2@check.homita.example'')',
        'select check_home_invitation_for_signup(''xyz'', ''t2-nuevo2@check.homita.example'')',
        'select check_home_invitation_for_signup(null, ''t2-nuevo2@check.homita.example'')',
        'select check_home_invitation_for_signup('''', ''t2-nuevo2@check.homita.example'')',
        format('select check_home_invitation_for_signup(%L, %L)', (select code from e_codes where k = 'E3'), 't2-u@check.homita.example'),
        format('select check_home_invitation_for_signup(%L, %L)', v_rev, 't2-nuevo3@check.homita.example'),
        format('select check_home_invitation_for_signup(%L, %L)', v_exp, 't2-nuevo4@check.homita.example'),
        'select check_home_invitation_for_signup(''aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa02'', ''t2-x@check.homita.example'')'] loop
        v_case := v_case + 1;
        v_out := pg_temp.try_as('anon', s);
        if v_out <> 'Not Found|P0002' then
            raise exception 'invitaciones_email E4: Not Found caso % → %', v_case, v_out;   -- sin imprimir el código
        end if;
    end loop;
    -- Not Allowed: email distinto, nulo o vacío; invitación sin email (anterior a 0026)
    foreach s in array array[
        format('select check_home_invitation_for_signup(%L, %L)', v_code, 'otro@check.homita.example'),
        format('select check_home_invitation_for_signup(%L, null)', v_code),
        format('select check_home_invitation_for_signup(%L, %L)', v_code, ''),
        'select check_home_invitation_for_signup(''aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa01'', ''t2-x@check.homita.example'')',
        'select check_home_invitation_for_signup(''aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa01'', null)'] loop
        v_case := v_case + 1;
        v_out := pg_temp.try_as('anon', s);
        if v_out <> 'Not Allowed|42501' then
            raise exception 'invitaciones_email E4: Not Allowed caso % → %', v_case, v_out;
        end if;
    end loop;
    -- no escribe nada y no consume
    if (select count(*) from home_invitation) <> v_n0
       or (select string_agg(status, ',' order by id) from home_invitation where home_id between 997201 and 997202) is distinct from v_i0
       or (select status from home_invitation i where i.code_hash = encode(sha256(convert_to(v_code, 'UTF8')), 'hex')) <> 'pending' then
        raise exception 'invitaciones_email E4: el chequeo escribió o consumió';
    end if;
    raise notice 'ok E4: check anon → ok {home_name, kind}; 8 × Not Found; 5 × Not Allowed; sin escrituras';
end $$;

-- ── E5: grants ──

do $$
declare v_out text;
begin
    if not has_function_privilege('anon', 'check_home_invitation_for_signup(text,text)', 'execute')
       or not has_function_privilege('authenticated', 'check_home_invitation_for_signup(text,text)', 'execute') then
        raise exception 'invitaciones_email E5: el check debe ser ejecutable por anon y authenticated';
    end if;
    if has_function_privilege('anon', 'create_home_invitation(bigint,text,bigint,text)', 'execute')
       or has_function_privilege('anon', 'accept_home_invitation(text)', 'execute')
       or has_function_privilege('anon', 'create_home(text,text)', 'execute')
       or not has_function_privilege('authenticated', 'create_home_invitation(bigint,text,bigint,text)', 'execute')
       or not has_function_privilege('authenticated', 'accept_home_invitation(text)', 'execute') then
        raise exception 'invitaciones_email E5: grants de create/accept';
    end if;
    if to_regprocedure('create_home_invitation(bigint,text,bigint)') is not null then
        raise exception 'invitaciones_email E5: sigue existiendo create_home_invitation de 3 argumentos';
    end if;
    v_out := pg_temp.try_as('anon', 'select create_home_invitation(997201, ''guest'', null, ''t2-z@check.homita.example'')');
    if v_out not like 'permission denied%|42501' then raise exception 'invitaciones_email E5: anon create → %', v_out; end if;
    raise notice 'ok E5: check ejecutable por anon; create/accept solo authenticated; sin firma de 3 argumentos';
end $$;

-- ── Limpieza de datos scratch 9972xx ──

set session_replication_role = replica;
select pg_temp.clean();
set session_replication_role = default;

-- ── E6: 0 filas scratch ──

do $$
begin
    if (select count(*) from home where id between 997201 and 997202 or name = 'T2-Nueva')
       + (select count(*) from app_user where id between 997201 and 997204)
       + (select count(*) from home_member where home_id between 997201 and 997202)
       + (select count(*) from person where user_id between 997201 and 997204)
       + (select count(*) from home_membership where app_user_id between 997201 and 997204)
       + (select count(*) from home_invitation where home_id between 997201 and 997202)
       + (select count(*) from audit_log where home_id between 997201 and 997202)
       + (select count(*) from auth.users where email like 't2-_@check.homita.example') <> 0 then
        raise exception 'invitaciones_email E6: quedan filas scratch';
    end if;
    raise notice 'ok E6: 0 filas scratch 9972xx';
end $$;
