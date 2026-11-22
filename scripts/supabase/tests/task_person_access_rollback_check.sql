-- task_person_access_rollback_check.sql — Ida de la vuelta 0038 → rollback_0038.sql (change
-- asignar-alta-lista). Solo BD local, tras el reset 0001–0038. ci.sh sustituye la línea
-- `-- @ROLLBACK:<fichero>@` por scripts/supabase/rollback/<fichero> (psql corre dentro del
-- contenedor y recibe stdin). Cada bloque emite 'ok RB38-x: …' o aborta con 'task_person_access_rollback RB38-x: …'.
--
-- NO va en transacción: el rollback se confirma de verdad, para que ci.sh pase después los checks
-- sobre el esquema sin 0038 y la ida y vuelta anidada de 0037. task_person_access_reapply_check.sql
-- vuelve a aplicar 0038 al final.
--
-- RB38-1 una sola firma de create_task, la de 5 argumentos (bigint,text,jsonb,uuid,text).
-- RB38-2 EXECUTE para authenticated; ni PUBLIC ni anon.
-- RB38-3 sin la guarda: una persona con cuenta sin ACL vuelve a aceptarse, y pg_get_functiondef es
--        el de 0037 (md5 de abajo; si cambia la 0037 o su volcado, regenerarlo desde un reset 0001–0037:
--        select md5(pg_get_functiondef('create_task(bigint,text,jsonb,uuid,text)'::regprocedure))).
-- RB38-4 rollback_0038 una segunda vez no falla y deja el mismo estado (idempotente).
-- RB38-5 get_persons vuelve a la de 0028: una sola firma get_persons(boolean), sin 'home_id' en el
--        cuerpo ni en el JSON, y los grants de 0017 (authenticated y service_role; ni PUBLIC ni anon).
--
-- Fixture (ids 994xxx, auth_uid …0941–…0942): hogar H con A admin (owner de la lista L) y C member
-- sin ACL en L; personas PC (cuenta C). Se borra al final.

\set ON_ERROR_STOP 1
do $$
begin
    if inet_server_addr() is not null and host(inet_server_addr()) not in ('127.0.0.1', '::1') then
        raise exception 'task_person_access_rollback_check: solo BD local (socket o loopback); servidor %', host(inet_server_addr());
    end if;
    if to_regprocedure('public.create_task(bigint,text,jsonb,uuid,text)') is null
       or pg_get_functiondef('public.create_task(bigint,text,jsonb,uuid,text)'::regprocedure) not like '%0038:%' then
        raise exception 'task_person_access_rollback_check: 0038 no está aplicada (create_task sin la guarda 0038:)';
    end if;
end $$;

create function pg_temp.clean() returns void
language plpgsql as $$
begin
    set local session_replication_role = replica;
    delete from task_person where task_id in (select t.id from task t join task_list tl on tl.id = t.task_list_id
                                              where tl.home_id = 994001);
    delete from task where task_list_id in (select id from task_list where home_id = 994001);
    delete from task_list_user where task_list_id in (select id from task_list where home_id = 994001);
    delete from task_list where home_id = 994001;
    delete from person where home_id = 994001;
    delete from home_member where home_id = 994001;
    delete from membership_permission where home_membership_id between 994001 and 994002;
    delete from home_membership where home_id = 994001;
    delete from audit_log where home_id = 994001;
    update app_user set default_home_id = null where id between 994001 and 994002;
    delete from home where id = 994001;
    delete from app_user where id between 994001 and 994002;
    delete from auth.users where id in (
        '00000000-0000-4000-8000-000000000941', '00000000-0000-4000-8000-000000000942');
end $$;

create function pg_temp.rb_state() returns text
language plpgsql as $$
declare
    v_sigs text[];
    v_ct oid := to_regprocedure('public.create_task(bigint,text,jsonb,uuid,text)');
    v_gp oid := to_regprocedure('public.get_persons(boolean)');
begin
    select array_agg(oid::regprocedure::text) into v_sigs
      from pg_proc where pronamespace = 'public'::regnamespace and proname = 'create_task';
    if v_sigs is distinct from array['create_task(bigint,text,jsonb,uuid,text)'] then
        return format('RB38-1 firmas %s', v_sigs);
    end if;
    if has_function_privilege('anon', v_ct, 'execute')
       or not has_function_privilege('authenticated', v_ct, 'execute')
       or exists (select 1 from pg_proc p, aclexplode(p.proacl) a
                  where p.oid = v_ct and a.grantee = 0 and a.privilege_type = 'EXECUTE') then
        return 'RB38-2 EXECUTE distinto del de 0037 (authenticated sí; PUBLIC y anon no)';
    end if;
    if pg_get_functiondef(v_ct) like '%0038:%'
       or md5(pg_get_functiondef(v_ct)) <> '91c512311639f3ff136a906b6e68b3a0' then
        return format('RB38-3 create_task no es el de 0037 (md5 %s)', md5(pg_get_functiondef(v_ct)));
    end if;
    select array_agg(oid::regprocedure::text) into v_sigs
      from pg_proc where pronamespace = 'public'::regnamespace and proname = 'get_persons';
    if v_sigs is distinct from array['get_persons(boolean)'] then
        return format('RB38-5 firmas de get_persons %s', v_sigs);
    end if;
    if pg_get_functiondef(v_gp) like '%''home_id''%' or pg_get_functiondef(v_gp) not like '%''app_user_id''%' then
        return 'RB38-5 get_persons no es el de 0028 (sigue con home_id o sin app_user_id)';
    end if;
    if has_function_privilege('anon', v_gp, 'execute')
       or not has_function_privilege('authenticated', v_gp, 'execute')
       or not has_function_privilege('service_role', v_gp, 'execute')
       or exists (select 1 from pg_proc p, aclexplode(p.proacl) a
                  where p.oid = v_gp and a.grantee = 0 and a.privilege_type = 'EXECUTE') then
        return 'RB38-5 EXECUTE de get_persons distinto del de 0017';
    end if;
    return null;
end $$;

select pg_temp.clean();

-- ── Fixture ──
set session_replication_role = replica;
insert into auth.users (id, email, raw_user_meta_data) values
    ('00000000-0000-4000-8000-000000000941', 'pr-a@check.homita.example', '{"name":"PR-A"}'),
    ('00000000-0000-4000-8000-000000000942', 'pr-c@check.homita.example', '{"name":"PR-C"}');
insert into app_user (id, auth_uid, name, email) values
    (994001, '00000000-0000-4000-8000-000000000941', 'PR-A', 'pr-a@check.homita.example'),
    (994002, '00000000-0000-4000-8000-000000000942', 'PR-C', 'pr-c@check.homita.example');
set session_replication_role = default;

begin;
insert into home (id, name, status, is_personal, created_by) values
    (994001, 'PR-Hogar H', 'active', false, 994001);
insert into home_membership (id, home_id, app_user_id, role) values
    (994001, 994001, 994001, 'admin'),
    (994002, 994001, 994002, 'member');
update app_user set default_home_id = 994001 where id between 994001 and 994002;
insert into home_member (id, home_id, kind, name, color, app_user_id, status) values
    (994002, 994001, 'adult', 'PR-MC', '#330000', 994002, 'active');
insert into person (id, user_id, home_id, home_member_id, name, color) values
    (994002, 994001, 994001, 994002, 'PR-PC', '#330000');
insert into task_list (id, name, color, token, sort, home_id) values
    (994001, 'PR-L', '#222222', 'pr-tok-1', 'custom', 994001);
insert into task_list_user (task_list_id, user_id, role, widget, dashboard, home_id) values
    (994001, 994001, 'owner', true, true, 994001);
commit;

-- @ROLLBACK:rollback_0038.sql@

\echo '-- \\df tras rollback_0038'
\df public.create_task

do $$
declare
    v_err text := pg_temp.rb_state();
    v json;
begin
    if v_err is not null then
        raise exception 'task_person_access_rollback %', v_err;
    end if;
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000941', true);
    v := create_task(994001, 'PR-T1', '[994002]'::jsonb, null, null);
    if not exists (select 1 from task_person where task_id = (v->>'id')::bigint and person_id = 994002) then
        raise exception 'task_person_access_rollback RB38-3: sin la guarda la persona sin ACL no se asignó (%)', v;
    end if;
    v := get_persons(false);
    if json_array_length(v) = 0 or exists (select 1 from json_array_elements(v) x where (x::jsonb) ? 'home_id') then
        raise exception 'task_person_access_rollback RB38-5: get_persons sigue con home_id o vacío (%)', left(v::text, 200);
    end if;
    raise notice 'ok RB38-1: una sola firma de create_task, la de 5 argumentos';
    raise notice 'ok RB38-2: EXECUTE para authenticated; sin PUBLIC ni anon';
    raise notice 'ok RB38-3: sin guarda 0038 (persona sin ACL aceptada) y create_task idéntico al de 0037';
    raise notice 'ok RB38-5: get_persons de 0028 (sin home_id) con los grants de 0017';
end $$;

-- RB38-4: segunda pasada.
-- @ROLLBACK:rollback_0038.sql@

do $$
declare
    v_err text := pg_temp.rb_state();
begin
    if v_err is not null then
        raise exception 'task_person_access_rollback RB38-4 (2.ª pasada): %', v_err;
    end if;
    raise notice 'ok RB38-4: rollback_0038 dos veces sin error y con el mismo estado';
end $$;

select pg_temp.clean();
