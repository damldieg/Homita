-- get_persons_home_id_check.sql — get_persons añade `home_id` al JSON (0038_task_create_person_access.sql,
-- change asignar-alta-lista, R1-02 decisión (a)). Solo BD local, tras el reset 0001–0038:
--   psql -v ON_ERROR_STOP=1 -f get_persons_home_id_check.sql
-- Cada bloque DO emite 'ok GPx: …' o aborta con 'get_persons_home_id GPx: …'.
--
-- GP1 una sola firma, get_persons(boolean), security definer, y el cuerpo lleva 'home_id' (0038).
-- GP2 grants de 0017 sin cambios: EXECUTE para authenticated y service_role; ni PUBLIC ni anon.
-- GP3 claves exactas de cada elemento: las de 0028 + home_id (aditivo, ninguna otra).
-- GP4 una cuenta con persona en dos hogares: get_persons la devuelve una vez por hogar, cada una con
--     el home_id de su persona; otro usuario solo del segundo hogar no ve el primero.
-- Al final, limpieza y 'ok GP-clean' (0 filas scratch).
--
-- Fixture (ids 991xxx, auth_uid …0951–…0952): A admin de H1 y H2 con persona en ambos; B member de
-- H2 con persona en H2.

\set ON_ERROR_STOP 1
do $$
begin
    if inet_server_addr() is not null and host(inet_server_addr()) not in ('127.0.0.1', '::1') then
        raise exception 'get_persons_home_id_check: solo BD local (socket o loopback); servidor %', host(inet_server_addr());
    end if;
end $$;

create function pg_temp.clean() returns void
language plpgsql as $$
begin
    set local session_replication_role = replica;
    delete from person where home_id between 991001 and 991002;
    delete from home_member where home_id between 991001 and 991002;
    delete from membership_permission where home_membership_id between 991001 and 991003;
    delete from home_membership where home_id between 991001 and 991002;
    delete from audit_log where home_id between 991001 and 991002;
    update app_user set default_home_id = null where id between 991001 and 991002;
    delete from home where id between 991001 and 991002;
    delete from app_user where id between 991001 and 991002;
    delete from auth.users where id in (
        '00000000-0000-4000-8000-000000000951', '00000000-0000-4000-8000-000000000952');
end $$;

select pg_temp.clean();

-- ── GP1: firma y cuerpo ──
do $$
declare
    v_sigs text[];
    v_fn oid := to_regprocedure('public.get_persons(boolean)');
begin
    select array_agg(oid::regprocedure::text) into v_sigs
      from pg_proc where pronamespace = 'public'::regnamespace and proname = 'get_persons';
    if v_sigs is distinct from array['get_persons(boolean)'] then
        raise exception 'get_persons_home_id GP1: firmas %', v_sigs;
    end if;
    if not (select prosecdef from pg_proc where oid = v_fn) then
        raise exception 'get_persons_home_id GP1: get_persons ya no es security definer';
    end if;
    if pg_get_functiondef(v_fn) not like '%''home_id'', p.home_id%' then
        raise exception 'get_persons_home_id GP1: el cuerpo no lleva ''home_id'' (¿0038 sin aplicar?)';
    end if;
    raise notice 'ok GP1: una sola firma get_persons(boolean), security definer y con home_id';
end $$;

-- ── GP2: grants ──
do $$
declare
    v_fn oid := to_regprocedure('public.get_persons(boolean)');
begin
    if has_function_privilege('anon', v_fn, 'execute')
       or not has_function_privilege('authenticated', v_fn, 'execute')
       or not has_function_privilege('service_role', v_fn, 'execute')
       or exists (select 1 from pg_proc p, aclexplode(p.proacl) a
                  where p.oid = v_fn and a.grantee = 0 and a.privilege_type = 'EXECUTE') then
        raise exception 'get_persons_home_id GP2: EXECUTE distinto del de 0017 (authenticated y service_role sí; PUBLIC y anon no)';
    end if;
    raise notice 'ok GP2: EXECUTE para authenticated y service_role; sin PUBLIC ni anon';
end $$;

-- ── Fixture ──
set session_replication_role = replica;
insert into auth.users (id, email, raw_user_meta_data) values
    ('00000000-0000-4000-8000-000000000951', 'gp-a@check.homita.example', '{"name":"GP-A"}'),
    ('00000000-0000-4000-8000-000000000952', 'gp-b@check.homita.example', '{"name":"GP-B"}');
insert into app_user (id, auth_uid, name, email) values
    (991001, '00000000-0000-4000-8000-000000000951', 'GP-A', 'gp-a@check.homita.example'),
    (991002, '00000000-0000-4000-8000-000000000952', 'GP-B', 'gp-b@check.homita.example');
set session_replication_role = default;

begin;
insert into home (id, name, status, is_personal, created_by) values
    (991001, 'GP-Hogar H1', 'active', false, 991001),
    (991002, 'GP-Hogar H2', 'active', false, 991001);
insert into home_membership (id, home_id, app_user_id, role) values
    (991001, 991001, 991001, 'admin'),
    (991002, 991002, 991001, 'admin'),
    (991003, 991002, 991002, 'member');
update app_user set default_home_id = 991001 where id = 991001;
update app_user set default_home_id = 991002 where id = 991002;
insert into home_member (id, home_id, kind, name, color, app_user_id, status) values
    (991001, 991001, 'adult', 'GP-MA1', '#110000', 991001, 'active'),
    (991002, 991002, 'adult', 'GP-MA2', '#220000', 991001, 'active'),
    (991003, 991002, 'adult', 'GP-MB2', '#330000', 991002, 'active');
insert into person (id, user_id, home_id, home_member_id, name, color) values
    (991001, 991001, 991001, 991001, 'GP-PA1', '#110000'),
    (991002, 991001, 991002, 991002, 'GP-PA2', '#220000'),
    (991003, 991001, 991002, 991003, 'GP-PB2', '#330000');
commit;

-- ── GP3: claves exactas ──
do $$
declare
    v json;
    v_item json;
    v_keys text[];
    v_expected text[] := array['app_user_id', 'color', 'created_at', 'editable', 'home_id',
                               'home_member_id', 'id', 'kind', 'name', 'updated_at', 'user_id'];
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000951', true);
    v := get_persons(false);
    for v_item in select * from json_array_elements(v) loop
        select array_agg(k order by k) into v_keys from json_object_keys(v_item) as k;
        if v_keys is distinct from v_expected then
            raise exception 'get_persons_home_id GP3: claves % (esperadas %)', v_keys, v_expected;
        end if;
    end loop;
    raise notice 'ok GP3: claves de 0028 + home_id, ninguna otra';
end $$;

-- ── GP4: una persona por hogar, cada una con su home_id ──
do $$
declare
    v json;
    v_got text;
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000951', true);
    v := get_persons(false);
    select string_agg(format('%s:%s:%s', x->>'id', x->>'home_id', x->>'app_user_id'), ',' order by (x->>'id')::bigint)
      into v_got from json_array_elements(v) x where (x->>'id')::bigint between 991001 and 991003;
    if v_got is distinct from '991001:991001:991001,991002:991002:991001,991003:991002:991002' then
        raise exception 'get_persons_home_id GP4: A ve %', v_got;
    end if;
    if exists (select 1 from json_array_elements(v) x
               join person p on p.id = (x->>'id')::bigint
               where (x->>'home_id')::bigint is distinct from p.home_id) then
        raise exception 'get_persons_home_id GP4: algún home_id no coincide con person.home_id';
    end if;
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000952', true);
    v := get_persons(false);
    select string_agg(format('%s:%s', x->>'id', x->>'home_id'), ',' order by (x->>'id')::bigint)
      into v_got from json_array_elements(v) x where (x->>'id')::bigint between 991001 and 991003;
    if v_got is distinct from '991002:991002,991003:991002' then
        raise exception 'get_persons_home_id GP4: B ve %', v_got;
    end if;
    raise notice 'ok GP4: la cuenta de A sale una vez por hogar con su home_id; B solo ve H2';
end $$;

select pg_temp.clean();

do $$
begin
    if exists (select 1 from person where home_id between 991001 and 991002)
       or exists (select 1 from home where id between 991001 and 991002)
       or exists (select 1 from app_user where id between 991001 and 991002) then
        raise exception 'get_persons_home_id GP-clean: quedan filas scratch';
    end if;
    raise notice 'ok GP-clean: 0 filas scratch';
end $$;
