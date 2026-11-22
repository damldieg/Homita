-- task_person_access_check.sql — Guarda de acceso a la lista en create_task (0038_task_create_person_access.sql).
-- Solo BD local, tras el reset 0001–0038:  psql -v ON_ERROR_STOP=1 -f task_person_access_check.sql
-- Cada bloque DO emite 'ok Ax: …' o aborta con 'task_person_access Ax: …'.
--
-- Fixture (ids 993xxx, auth_uid …0931–…0933): hogar H con A admin (owner de la lista L), B member
-- (viewer de L, sin can_edit) y C member (sin fila en el ACL de L). Personas: PA (cuenta A), PB
-- (cuenta B, con acceso), PC (cuenta C, sin acceso) y PD (miembro sin cuenta).
--
-- A1 persona con cuenta y acceso → tarea creada y fila en task_person (también la propia del creador).
-- A2 p_person_ids null y '[]' → tarea sin personas.
-- A3 persona con cuenta sin ACL → 'Invalid person' P0001, sin fila en task ni en client_request.
-- A4 persona sin cuenta → 'Invalid person'.
-- A5 mezcla de válida e inválida → rechazo total (sin tarea).
-- A6 reenvío con la misma clave tras quitar el acceso → mismo id, sin insertar.
-- A7 update_task(bigint,text,jsonb,text) con persona sin acceso → OK (P-2: la guarda solo va en el alta).
-- A8 grants de create_task(bigint,text,jsonb,uuid,text): authenticated sí; anon y PUBLIC no.
-- A9 p_priority 'alta' + persona válida → tarea alta con la persona; prioridad inválida + persona sin
--    acceso → gana 'Invalid priority' (se valida antes).
-- Al final, limpieza y 'ok A-clean' (0 filas scratch).

\set ON_ERROR_STOP 1
do $$
begin
    if inet_server_addr() is not null and host(inet_server_addr()) not in ('127.0.0.1', '::1') then
        raise exception 'task_person_access_check: solo BD local (socket o loopback); servidor %', host(inet_server_addr());
    end if;
    if to_regprocedure('public.create_task(bigint,text,jsonb,uuid,text)') is null
       or pg_get_functiondef('public.create_task(bigint,text,jsonb,uuid,text)'::regprocedure) not like '%0038:%' then
        raise exception 'task_person_access_check: 0038 no está aplicada (create_task sin la guarda 0038:)';
    end if;
end $$;

create function pg_temp.clean() returns void
language plpgsql as $$
begin
    set local session_replication_role = replica;
    delete from client_request where app_user_id between 993001 and 993003;
    delete from task_person where task_id in (select t.id from task t join task_list tl on tl.id = t.task_list_id
                                              where tl.home_id = 993001);
    delete from task where task_list_id in (select id from task_list where home_id = 993001);
    delete from task_list_user where task_list_id in (select id from task_list where home_id = 993001);
    delete from task_list where home_id = 993001;
    delete from person where home_id = 993001;
    delete from home_member where home_id = 993001;
    delete from membership_permission where home_membership_id between 993001 and 993003;
    delete from home_membership where home_id = 993001;
    delete from audit_log where home_id = 993001;
    update app_user set default_home_id = null where id between 993001 and 993003;
    delete from home where id = 993001;
    delete from app_user where id between 993001 and 993003;
    delete from auth.users where id in (
        '00000000-0000-4000-8000-000000000931', '00000000-0000-4000-8000-000000000932',
        '00000000-0000-4000-8000-000000000933');
end $$;

-- Ejecuta p_sql y exige el error p_msg (sqlstate p_state).
create function pg_temp.fails(p_label text, p_sql text, p_state text, p_msg text) returns void
language plpgsql as $$
begin
    execute p_sql;
    raise exception 'task_person_access %: no falló: %', p_label, p_sql;
exception when others then
    if sqlstate <> p_state or sqlerrm <> p_msg then
        raise exception 'task_person_access %: % % (esperado % %)', p_label, sqlstate, sqlerrm, p_state, p_msg;
    end if;
end $$;

create function pg_temp.as_user(p_n int) returns void
language sql as $$
    select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-00000000093' || p_n, true)
$$;

create function pg_temp.persons_of(p_task_id bigint) returns bigint[]
language sql as $$
    select coalesce(array(select person_id from task_person where task_id = p_task_id order by 1), array[]::bigint[])
$$;

select pg_temp.clean();

-- ── Fixture ──
set session_replication_role = replica;
insert into auth.users (id, email, raw_user_meta_data) values
    ('00000000-0000-4000-8000-000000000931', 'pa-a@check.homita.example', '{"name":"PA-A"}'),
    ('00000000-0000-4000-8000-000000000932', 'pa-b@check.homita.example', '{"name":"PA-B"}'),
    ('00000000-0000-4000-8000-000000000933', 'pa-c@check.homita.example', '{"name":"PA-C"}');
insert into app_user (id, auth_uid, name, email) values
    (993001, '00000000-0000-4000-8000-000000000931', 'PA-A', 'pa-a@check.homita.example'),
    (993002, '00000000-0000-4000-8000-000000000932', 'PA-B', 'pa-b@check.homita.example'),
    (993003, '00000000-0000-4000-8000-000000000933', 'PA-C', 'pa-c@check.homita.example');
set session_replication_role = default;

begin;
insert into home (id, name, status, is_personal, created_by) values
    (993001, 'PA-Hogar H', 'active', false, 993001);
insert into home_membership (id, home_id, app_user_id, role) values
    (993001, 993001, 993001, 'admin'),
    (993002, 993001, 993002, 'member'),
    (993003, 993001, 993003, 'member');
update app_user set default_home_id = 993001 where id between 993001 and 993003;
insert into home_member (id, home_id, kind, name, color, app_user_id, status) values
    (993001, 993001, 'adult', 'PA-MA', '#110000', 993001, 'active'),
    (993002, 993001, 'adult', 'PA-MB', '#220000', 993002, 'active'),
    (993003, 993001, 'adult', 'PA-MC', '#330000', 993003, 'active'),
    (993004, 993001, 'adult', 'PA-MD', '#440000', null, 'active');
insert into person (id, user_id, home_id, home_member_id, name, color) values
    (993001, 993001, 993001, 993001, 'PA-PA', '#110000'),
    (993002, 993001, 993001, 993002, 'PA-PB', '#220000'),
    (993003, 993001, 993001, 993003, 'PA-PC', '#330000'),
    (993004, 993001, 993001, 993004, 'PA-PD', '#440000');
insert into task_list (id, name, color, token, sort, home_id) values
    (993001, 'PA-L', '#222222', 'pa-tok-1', 'custom', 993001);
insert into task_list_user (task_list_id, user_id, role, widget, dashboard, home_id) values
    (993001, 993001, 'owner', true, true, 993001),
    (993001, 993002, 'viewer', true, true, 993001);
commit;

-- ── A1: persona con cuenta y acceso ──
do $$
declare
    v json;
begin
    perform pg_temp.as_user(1);
    v := create_task(993001, 'PA-T1', '[993002]'::jsonb, null, null);
    if pg_temp.persons_of((v->>'id')::bigint) <> array[993002]::bigint[]
       or not exists (select 1 from json_array_elements(v->'persons') p where (p->>'id')::bigint = 993002) then
        raise exception 'task_person_access A1: personas % (esperado [993002]) en %', pg_temp.persons_of((v->>'id')::bigint), v;
    end if;
    v := create_task(993001, 'PA-T1b', '[993001, 993002]'::jsonb, null, null);
    if pg_temp.persons_of((v->>'id')::bigint) <> array[993001, 993002]::bigint[] then
        raise exception 'task_person_access A1: personas % (esperado [993001,993002])', pg_temp.persons_of((v->>'id')::bigint);
    end if;
    raise notice 'ok A1: persona con cuenta y acceso (viewer sin can_edit y el propio owner) → asignada';
end $$;

-- ── A2: null y [] ──
do $$
declare
    v1 json;
    v2 json;
begin
    perform pg_temp.as_user(1);
    v1 := create_task(993001, 'PA-T2a', null, null, null);
    v2 := create_task(993001, 'PA-T2b', '[]'::jsonb, null, null);
    if cardinality(pg_temp.persons_of((v1->>'id')::bigint)) <> 0
       or cardinality(pg_temp.persons_of((v2->>'id')::bigint)) <> 0 then
        raise exception 'task_person_access A2: tareas con personas';
    end if;
    raise notice 'ok A2: p_person_ids null y [] → tarea sin personas';
end $$;

-- ── A3: persona con cuenta sin ACL ──
do $$
begin
    perform pg_temp.as_user(1);
    perform pg_temp.fails('A3 sin ACL',
        $q$select create_task(993001, 'PA-T3', '[993003]'::jsonb, '33333333-3333-4333-8333-333333333331', null)$q$,
        'P0001', 'Invalid person');
    if exists (select 1 from task where title = 'PA-T3')
       or exists (select 1 from client_request where client_request_id = '33333333-3333-4333-8333-333333333331') then
        raise exception 'task_person_access A3: quedó fila en task o client_request';
    end if;
    raise notice 'ok A3: persona con cuenta sin ACL → Invalid person, sin task ni client_request';
end $$;

-- ── A4: persona sin cuenta ──
do $$
begin
    perform pg_temp.as_user(1);
    perform pg_temp.fails('A4 sin cuenta',
        $q$select create_task(993001, 'PA-T4', '[993004]'::jsonb, null, null)$q$,
        'P0001', 'Invalid person');
    if exists (select 1 from task where title = 'PA-T4') then
        raise exception 'task_person_access A4: se creó la tarea';
    end if;
    raise notice 'ok A4: persona sin cuenta → Invalid person';
end $$;

-- ── A5: mezcla de válida e inválida ──
do $$
begin
    perform pg_temp.as_user(1);
    perform pg_temp.fails('A5 mezcla sin ACL',
        $q$select create_task(993001, 'PA-T5', '[993002, 993003]'::jsonb, null, null)$q$,
        'P0001', 'Invalid person');
    perform pg_temp.fails('A5 mezcla sin cuenta',
        $q$select create_task(993001, 'PA-T5', '[993004, 993001]'::jsonb, null, null)$q$,
        'P0001', 'Invalid person');
    if exists (select 1 from task where title = 'PA-T5') then
        raise exception 'task_person_access A5: se creó la tarea';
    end if;
    raise notice 'ok A5: mezcla de válida e inválida → rechazo total';
end $$;

-- ── A6: reenvío con la misma clave tras quitar el acceso ──
do $$
declare
    v1 json;
    v2 json;
begin
    perform pg_temp.as_user(1);
    v1 := create_task(993001, 'PA-T6', '[993002]'::jsonb, '66666666-6666-4666-8666-666666666666', null);
    delete from task_list_user where task_list_id = 993001 and user_id = 993002;
    v2 := create_task(993001, 'PA-T6 reenvío', '[993002]'::jsonb, '66666666-6666-4666-8666-666666666666', null);
    if (v1->>'id') <> (v2->>'id') then
        raise exception 'task_person_access A6: ids distintos % / %', v1->>'id', v2->>'id';
    end if;
    if (select count(*) from task where title like 'PA-T6%') <> 1 then
        raise exception 'task_person_access A6: % tareas (esperado 1)', (select count(*) from task where title like 'PA-T6%');
    end if;
    -- Sin la clave, la persona que perdió el acceso ya no se acepta.
    perform pg_temp.fails('A6 sin clave',
        $q$select create_task(993001, 'PA-T6c', '[993002]'::jsonb, null, null)$q$,
        'P0001', 'Invalid person');
    insert into task_list_user (task_list_id, user_id, role, widget, dashboard, home_id)
    values (993001, 993002, 'viewer', true, true, 993001);
    raise notice 'ok A6: reenvío con la misma clave tras perder el acceso → mismo id, una sola tarea';
end $$;

-- ── A7: update_task no cambia (P-2) ──
do $$
declare
    v json;
    v_id bigint := (select id from task where title = 'PA-T2a');
begin
    perform pg_temp.as_user(1);
    if to_regprocedure('public.update_task(bigint,text,jsonb,text)') is null then
        raise exception 'task_person_access A7: falta update_task(bigint,text,jsonb,text)';
    end if;
    if pg_get_functiondef('public.update_task(bigint,text,jsonb,text)'::regprocedure) like '%0038%' then
        raise exception 'task_person_access A7: update_task tiene la guarda 0038';
    end if;
    v := update_task(v_id, 'PA-T2a editada', '[993003]'::jsonb, null);
    if pg_temp.persons_of(v_id) <> array[993003]::bigint[] then
        raise exception 'task_person_access A7: personas % (esperado [993003])', pg_temp.persons_of(v_id);
    end if;
    raise notice 'ok A7: update_task con persona sin acceso → OK (sin guarda en la edición)';
end $$;

-- ── A8: grants ──
do $$
declare
    v_ct regprocedure := 'public.create_task(bigint,text,jsonb,uuid,text)'::regprocedure;
begin
    if (select count(*) from pg_proc where proname = 'create_task' and pronamespace = 'public'::regnamespace) <> 1 then
        raise exception 'task_person_access A8: más de una firma de create_task';
    end if;
    if has_function_privilege('anon', v_ct, 'execute')
       or not has_function_privilege('authenticated', v_ct, 'execute')
       or exists (select 1 from pg_proc p, aclexplode(p.proacl) a
                  where p.oid = v_ct and a.grantee = 0 and a.privilege_type = 'EXECUTE') then
        raise exception 'task_person_access A8: EXECUTE incorrecto en create_task';
    end if;
    raise notice 'ok A8: una firma; EXECUTE para authenticated, sin anon ni PUBLIC';
end $$;

-- ── A9: prioridad y personas ──
do $$
declare
    v json;
begin
    perform pg_temp.as_user(1);
    v := create_task(993001, 'PA-T9', '[993002]'::jsonb, null, 'alta');
    if (select priority from task where id = (v->>'id')::bigint) <> 'alta' or (v->>'priority') <> 'alta'
       or pg_temp.persons_of((v->>'id')::bigint) <> array[993002]::bigint[] then
        raise exception 'task_person_access A9: tarea % sin prioridad alta o sin la persona', v;
    end if;
    perform pg_temp.fails('A9 prioridad inválida antes que la persona',
        $q$select create_task(993001, 'PA-T9b', '[993003]'::jsonb, null, 'urgente')$q$,
        'P0001', 'Invalid priority');
    if exists (select 1 from task where title = 'PA-T9b') then
        raise exception 'task_person_access A9: se creó la tarea';
    end if;
    raise notice 'ok A9: prioridad alta con persona válida; prioridad inválida gana a la persona sin acceso';
end $$;

-- ── Limpieza ──
select pg_temp.clean();
do $$
begin
    if exists (select 1 from app_user where id between 993001 and 993003)
       or exists (select 1 from home where id = 993001)
       or exists (select 1 from person where home_id = 993001)
       or exists (select 1 from client_request where app_user_id between 993001 and 993003) then
        raise exception 'task_person_access A-clean: quedaron filas scratch';
    end if;
    raise notice 'ok A-clean: 0 filas scratch';
end $$;
