-- task_person_access_reapply_check.sql — Vuelta de la ida 0038 → rollback_0038.sql → 0038 (change
-- asignar-alta-lista). Solo BD local, después de task_person_access_rollback_check.sql y de la ida y
-- vuelta anidada de 0037. ci.sh sustituye la línea `-- @MIGRATION:<fichero>@` por
-- supabase/migrations/<fichero>. Emite 'ok RA38-1: …' o aborta con 'task_person_access_reapply RA38-1: …'.
-- Después ci.sh vuelve a pasar task_person_access_check (A1-A9) y contract_check completo.
--
-- RA38-1 de partida, create_task de 5 argumentos sin la guarda; tras reaplicar 0038, una sola firma,
--        con el marcador `0038:`, y una persona con cuenta sin ACL vuelve a dar 'Invalid person'
--        sin crear la tarea.
--
-- Fixture (ids 994xxx, el mismo que task_person_access_rollback_check.sql): se borra al final.

\set ON_ERROR_STOP 1
do $$
begin
    if inet_server_addr() is not null and host(inet_server_addr()) not in ('127.0.0.1', '::1') then
        raise exception 'task_person_access_reapply_check: solo BD local (socket o loopback); servidor %', host(inet_server_addr());
    end if;
    if to_regprocedure('public.create_task(bigint,text,jsonb,uuid,text)') is null
       or pg_get_functiondef('public.create_task(bigint,text,jsonb,uuid,text)'::regprocedure) like '%0038:%' then
        raise exception 'task_person_access_reapply RA38-1: no se parte del esquema revertido por rollback_0038 (0037 sin guarda)';
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

-- @MIGRATION:0038_task_create_person_access.sql@

\echo '-- \\df tras volver a aplicar 0038'
\df public.create_task

do $$
declare
    v_sigs text[];
begin
    select array_agg(oid::regprocedure::text) into v_sigs
      from pg_proc where pronamespace = 'public'::regnamespace and proname = 'create_task';
    if v_sigs is distinct from array['create_task(bigint,text,jsonb,uuid,text)']
       or pg_get_functiondef('public.create_task(bigint,text,jsonb,uuid,text)'::regprocedure) not like '%0038:%' then
        raise exception 'task_person_access_reapply RA38-1: firmas % o sin la guarda 0038:', v_sigs;
    end if;
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000941', true);
    begin
        perform create_task(994001, 'PR-RA1', '[994002]'::jsonb, null, null);
        raise exception 'task_person_access_reapply RA38-1: no falló con persona sin ACL';
    exception when others then
        if sqlstate <> 'P0001' or sqlerrm <> 'Invalid person' then
            raise exception 'task_person_access_reapply RA38-1: % % (esperado P0001 Invalid person)', sqlstate, sqlerrm;
        end if;
    end;
    if exists (select 1 from task where title = 'PR-RA1') then
        raise exception 'task_person_access_reapply RA38-1: se creó la tarea';
    end if;
    raise notice 'ok RA38-1: 0038 reaplicada (una firma, guarda 0038:); persona sin ACL → Invalid person';
end $$;

select pg_temp.clean();
