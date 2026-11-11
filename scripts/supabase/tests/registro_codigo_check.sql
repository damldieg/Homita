-- registro_codigo_check.sql — Trigger fn_auth_user_created (0027, change hogar-admin-miembro).
-- Solo BD local, tras el reset 0001–0027:  psql -v ON_ERROR_STOP=1 -f registro_codigo_check.sql
-- Las altas se hacen insertando en auth.users (dispara on_auth_user_created).
-- R1: con raw_user_meta_data.invitation_pending=true → app_user sin home ni membresía ni default_home_id.
-- R2: sin marcador → hogar personal + membresía admin + home_member adult activo vinculado + person 1:1.
-- R3: alta en auth.users de un usuario que ya tiene app_user con hogar no duplica home, home_member ni person.
-- R4: 0 filas scratch al terminar.
-- Datos scratch con uuids …0991–…0994, borrados al inicio y al final por pg_temp.clean(): por email
-- rc-%@check.homita.example Y por auth_uid (residuo de una corrida abortada), en orden de FKs:
-- audit_log, membership_permission, person, home_member, default_home_id, home_membership, home,
-- app_user, auth.users. invitaciones_check.sql comparte …0991–…0996 y limpia igual al empezar.

\set ON_ERROR_STOP 1
do $$
begin
    if inet_server_addr() is not null and host(inet_server_addr()) not in ('127.0.0.1', '::1') then
        raise exception 'registro_codigo_check: solo BD local (socket o loopback); servidor %', host(inet_server_addr());
    end if;
end $$;

create function pg_temp.clean() returns void
language plpgsql as $$
declare v_ids bigint[] := array(select id from app_user where email like 'rc-%@check.homita.example'
    or auth_uid in ('00000000-0000-4000-8000-000000000991', '00000000-0000-4000-8000-000000000992',
                    '00000000-0000-4000-8000-000000000993', '00000000-0000-4000-8000-000000000994'));
begin
    delete from audit_log where home_id in (select home_id from home_membership where app_user_id = any (v_ids));
    delete from membership_permission where home_membership_id in (
        select id from home_membership where app_user_id = any (v_ids));
    delete from person where user_id = any (v_ids);
    delete from home_member where created_by = any (v_ids) or app_user_id = any (v_ids);
    update app_user set default_home_id = null where id = any (v_ids);
    delete from home_membership where app_user_id = any (v_ids);
    delete from home where created_by = any (v_ids);
    delete from app_user where id = any (v_ids);
    delete from auth.users where email like 'rc-%@check.homita.example'
        or id in ('00000000-0000-4000-8000-000000000991', '00000000-0000-4000-8000-000000000992',
                  '00000000-0000-4000-8000-000000000993', '00000000-0000-4000-8000-000000000994');
end $$;

select pg_temp.clean();

-- (a) alta con marcador de invitación pendiente: sin hogar
insert into auth.users (id, email, raw_user_meta_data) values
    ('00000000-0000-4000-8000-000000000991', 'rc-a@check.homita.example',
     '{"name":"RC-A","invitation_pending":true}');
do $$
declare u app_user%rowtype;
begin
    select * into u from app_user where email = 'rc-a@check.homita.example';
    if u.id is null then raise exception 'registro_codigo R1: no se creó app_user'; end if;
    if u.default_home_id is not null
       or exists (select 1 from home_membership where app_user_id = u.id)
       or exists (select 1 from home where created_by = u.id)
       or exists (select 1 from home_member where app_user_id = u.id)
       or exists (select 1 from person where user_id = u.id) then
        raise exception 'registro_codigo R1: el alta con invitation_pending creó hogar/membresía/miembro';
    end if;
    raise notice 'ok R1: invitation_pending → app_user sin hogar';
end $$;

-- (b) alta sin marcador: hogar personal con miembro vinculado
insert into auth.users (id, email, raw_user_meta_data) values
    ('00000000-0000-4000-8000-000000000992', 'rc-b@check.homita.example', '{"name":"RC-B"}'),
    ('00000000-0000-4000-8000-000000000993', 'rc-c@check.homita.example',
     '{"name":"RC-C","invitation_pending":false}');
do $$
declare u app_user%rowtype; e text;
begin
    foreach e in array array['rc-b@check.homita.example', 'rc-c@check.homita.example'] loop
        select * into u from app_user where email = e;
        if (select count(*) from home h join home_membership m on m.home_id = h.id
             where h.created_by = u.id and h.is_personal and m.app_user_id = u.id and m.role = 'admin') <> 1
           or u.default_home_id is null then
            raise exception 'registro_codigo R2 (%): falta hogar personal con membresía admin y default', e;
        end if;
        if (select count(*) from home_member hm
             where hm.home_id = u.default_home_id and hm.app_user_id = u.id and hm.kind = 'adult'
               and hm.status = 'active' and hm.created_by = u.id) <> 1 then
            raise exception 'registro_codigo R2 (%): falta home_member adult activo vinculado', e;
        end if;
        if (select count(*) from person p join home_member hm on hm.id = p.home_member_id
             where p.user_id = u.id and p.home_id = u.default_home_id and hm.app_user_id = u.id) <> 1 then
            raise exception 'registro_codigo R2 (%): falta person 1:1 vinculada', e;
        end if;
    end loop;
    raise notice 'ok R2: alta sin marcador → hogar personal + home_member + person';
end $$;

-- (c) usuario que ya tiene app_user con hogar (re-ejecución del trigger): no duplica.
-- app_user.auth_uid tiene FK a auth.users: el app_user previo se inserta con la FK desactivada
-- (replica, solo BD local) y luego el alta en auth.users dispara el trigger sobre ese usuario.
set session_replication_role = replica;
insert into app_user (auth_uid, name, email)
values ('00000000-0000-4000-8000-000000000994', 'RC-D', 'rc-d@check.homita.example');
set session_replication_role = origin;
do $$
declare v_u bigint; v_h bigint;
begin
    select id into v_u from app_user where email = 'rc-d@check.homita.example';
    insert into home (name, is_personal, created_by) values ('RC-D previo', true, v_u) returning id into v_h;
    insert into home_membership (home_id, app_user_id, role) values (v_h, v_u, 'admin');
end $$;
insert into auth.users (id, email, raw_user_meta_data) values
    ('00000000-0000-4000-8000-000000000994', 'rc-d@check.homita.example', '{"name":"RC-D"}');
do $$
declare v_u bigint;
begin
    select id into v_u from app_user where email = 'rc-d@check.homita.example';
    if (select count(*) from home where created_by = v_u) <> 1
       or (select count(*) from home_membership where app_user_id = v_u) <> 1
       or exists (select 1 from home_member where app_user_id = v_u)
       or exists (select 1 from person where user_id = v_u) then
        raise exception 'registro_codigo R3: el trigger duplicó o añadió filas a un usuario con hogar';
    end if;
    raise notice 'ok R3: usuario con hogar previo no se duplica';
end $$;

select pg_temp.clean();
do $$
begin
    if exists (select 1 from app_user where email like 'rc-%@check.homita.example')
       or exists (select 1 from auth.users where email like 'rc-%@check.homita.example') then
        raise exception 'registro_codigo: quedaron filas scratch';
    end if;
    raise notice 'ok R4: 0 filas scratch';
end $$;
