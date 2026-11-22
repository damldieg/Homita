-- client_request_check.sql — Idempotencia de create_task / create_task_list (0035_client_request_idempotency.sql).
-- Solo BD local, tras el reset 0001–0035:  psql -v ON_ERROR_STOP=1 -f client_request_check.sql
-- Cada bloque DO emite 'ok Cx: …' o aborta con 'client_request Cx: …'.
--
-- Fixture (ids 992xxx, auth_uid …0921–…0922): hogar H con A admin (owner de la lista L); hogar B
-- con Y admin (owner de la lista LB). A y Y no comparten nada.
--
-- C1 create_task con la misma clave dos veces → mismo id, misma respuesta, una sola tarea y una fila.
-- C2 create_task_list con la misma clave dos veces → mismo JSON, una sola lista y una fila.
-- C3 otro usuario (Y) con la misma clave crea su propio recurso; con la lista de A → 'Not Found'
--    (no lee ni reutiliza el recurso ajeno).
-- C4 la clave de una tarea usada en create_task_list (y al revés) → 'Invalid client_request_id'.
-- C5 sin clave (null) no hay deduplicación: dos altas → dos filas, sin filas en client_request.
-- C6 recurso borrado → el replay da 'Not Found' (tarea y lista).
-- C7 firmas: una sola por RPC; las llamadas posicionales antiguas siguen funcionando.
-- C8 permisos: client_request con RLS sin policies y sin privilegios para anon/authenticated;
--    anon sin EXECUTE sobre las RPC.
-- C9 0 filas scratch al terminar.

\set ON_ERROR_STOP 1
do $$
begin
    if inet_server_addr() is not null and host(inet_server_addr()) not in ('127.0.0.1', '::1') then
        raise exception 'client_request_check: solo BD local (socket o loopback); servidor %', host(inet_server_addr());
    end if;
end $$;

create function pg_temp.clean() returns void
language plpgsql as $$
begin
    set local session_replication_role = replica;
    delete from client_request where app_user_id between 992001 and 992002;
    delete from task_person where task_id in (select t.id from task t join task_list tl on tl.id = t.task_list_id
                                              where tl.home_id in (992001, 992002));
    delete from task where task_list_id in (select id from task_list where home_id in (992001, 992002));
    delete from task_list_user where task_list_id in (select id from task_list where home_id in (992001, 992002));
    delete from task_list where home_id in (992001, 992002);
    delete from membership_permission where home_membership_id between 992001 and 992002;
    delete from home_membership where home_id in (992001, 992002);
    delete from audit_log where home_id in (992001, 992002);
    update app_user set default_home_id = null where id between 992001 and 992002;
    delete from home where id in (992001, 992002);
    delete from app_user where id between 992001 and 992002;
    delete from auth.users where id in (
        '00000000-0000-4000-8000-000000000921', '00000000-0000-4000-8000-000000000922');
end $$;

-- Ejecuta p_sql y exige el error p_msg (sqlstate p_state).
create function pg_temp.fails(p_label text, p_sql text, p_state text, p_msg text) returns void
language plpgsql as $$
begin
    execute p_sql;
    raise exception 'client_request %: no falló: %', p_label, p_sql;
exception when others then
    if sqlstate <> p_state or sqlerrm <> p_msg then
        raise exception 'client_request %: % % (esperado % %)', p_label, sqlstate, sqlerrm, p_state, p_msg;
    end if;
end $$;

create function pg_temp.as_user(p_n int) returns void
language sql as $$
    select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-00000000092' || p_n, true)
$$;

select pg_temp.clean();

-- ── Fixture ──
set session_replication_role = replica;
insert into auth.users (id, email, raw_user_meta_data) values
    ('00000000-0000-4000-8000-000000000921', 'cr-a@check.homita.example', '{"name":"CR-A"}'),
    ('00000000-0000-4000-8000-000000000922', 'cr-y@check.homita.example', '{"name":"CR-Y"}');
insert into app_user (id, auth_uid, name, email) values
    (992001, '00000000-0000-4000-8000-000000000921', 'CR-A', 'cr-a@check.homita.example'),
    (992002, '00000000-0000-4000-8000-000000000922', 'CR-Y', 'cr-y@check.homita.example');
set session_replication_role = default;

begin;
insert into home (id, name, status, is_personal, created_by) values
    (992001, 'CR-Hogar H', 'active', false, 992001),
    (992002, 'CR-Hogar B', 'active', false, 992002);
insert into home_membership (id, home_id, app_user_id, role) values
    (992001, 992001, 992001, 'admin'),
    (992002, 992002, 992002, 'admin');
update app_user set default_home_id = 992001 where id = 992001;
update app_user set default_home_id = 992002 where id = 992002;
insert into task_list (id, name, color, token, sort, home_id) values
    (992001, 'CR-L', '#222222', 'cr-tok-1', 'custom', 992001),
    (992002, 'CR-LB', '#333333', 'cr-tok-2', 'custom', 992002);
insert into task_list_user (task_list_id, user_id, role, widget, dashboard, home_id) values
    (992001, 992001, 'owner', true, true, 992001),
    (992002, 992002, 'owner', true, true, 992002);
commit;

-- ── C1: create_task con la misma clave dos veces ──
do $$
declare
    v1 json;
    v2 json;
begin
    perform pg_temp.as_user(1);
    v1 := create_task(992001, 'CR-T1', null, '11111111-1111-4111-8111-111111111111');
    v2 := create_task(992001, 'CR-T1 reenvío', null, '11111111-1111-4111-8111-111111111111');
    if (v1->>'id') is null or (v1->>'id') <> (v2->>'id') then
        raise exception 'client_request C1: ids distintos % / %', v1->>'id', v2->>'id';
    end if;
    if v1::text <> v2::text then
        raise exception 'client_request C1: respuesta distinta % / %', v1, v2;
    end if;
    if (select count(*) from task where task_list_id = 992001) <> 1 then
        raise exception 'client_request C1: % tareas (esperado 1)', (select count(*) from task where task_list_id = 992001);
    end if;
    if (select count(*) from client_request where app_user_id = 992001) <> 1
       or (select resource_id from client_request where app_user_id = 992001) <> (v1->>'id')::bigint then
        raise exception 'client_request C1: fila de client_request incorrecta';
    end if;
    raise notice 'ok C1: create_task reenviado → mismo id y respuesta, 1 tarea, 1 fila';
end $$;

-- ── C2: create_task_list con la misma clave dos veces ──
do $$
declare
    v1 json;
    v2 json;
begin
    perform pg_temp.as_user(1);
    v1 := create_task_list('CR-Lista', '#444444', 'custom', true, false, '22222222-2222-4222-8222-222222222222');
    v2 := create_task_list('CR-Lista otra', '#555555', 'title', false, true, '22222222-2222-4222-8222-222222222222');
    if v1::text <> v2::text then
        raise exception 'client_request C2: respuesta distinta % / %', v1, v2;
    end if;
    if (select count(*) from task_list where home_id = 992001 and name like 'CR-Lista%') <> 1 then
        raise exception 'client_request C2: listas duplicadas';
    end if;
    if (select kind from client_request where app_user_id = 992001
        and client_request_id = '22222222-2222-4222-8222-222222222222') <> 'task_list' then
        raise exception 'client_request C2: fila de client_request incorrecta';
    end if;
    raise notice 'ok C2: create_task_list reenviado → mismo JSON, 1 lista, 1 fila';
end $$;

-- ── C3: otro usuario con la misma clave ──
do $$
declare
    v_a bigint := (select resource_id from client_request where app_user_id = 992001
                   and client_request_id = '11111111-1111-4111-8111-111111111111');
    v json;
begin
    perform pg_temp.as_user(2);
    perform pg_temp.fails('C3 lista ajena',
        $q$select create_task(992001, 'CR-intruso', null, '11111111-1111-4111-8111-111111111111')$q$,
        'P0002', 'Not Found');
    v := create_task(992002, 'CR-TY', null, '11111111-1111-4111-8111-111111111111');
    if (v->>'id')::bigint = v_a or (v->>'task_list_id')::bigint <> 992002 then
        raise exception 'client_request C3: Y reutilizó el recurso de A (%)', v;
    end if;
    if (select count(*) from client_request where client_request_id = '11111111-1111-4111-8111-111111111111') <> 2 then
        raise exception 'client_request C3: esperadas 2 filas independientes';
    end if;
    raise notice 'ok C3: misma clave de otro usuario → recurso propio; la lista ajena → Not Found';
end $$;

-- ── C4: la clave de otro kind ──
do $$
begin
    perform pg_temp.as_user(1);
    perform pg_temp.fails('C4 tarea→lista',
        $q$select create_task_list('CR-X', '#666666', 'custom', true, true, '11111111-1111-4111-8111-111111111111')$q$,
        'P0001', 'Invalid client_request_id');
    perform pg_temp.fails('C4 lista→tarea',
        $q$select create_task(992001, 'CR-X', null, '22222222-2222-4222-8222-222222222222')$q$,
        'P0001', 'Invalid client_request_id');
    if exists (select 1 from task where title = 'CR-X') or exists (select 1 from task_list where name = 'CR-X') then
        raise exception 'client_request C4: se creó un recurso pese al error';
    end if;
    raise notice 'ok C4: clave de otro kind → Invalid client_request_id sin alta';
end $$;

-- ── C5: sin clave no hay deduplicación ──
do $$
declare
    v_before bigint := (select count(*) from client_request);
begin
    perform pg_temp.as_user(1);
    perform create_task(992001, 'CR-Null', null, null);
    perform create_task(992001, 'CR-Null', null, null);
    perform create_task_list('CR-NullL', '#777777', 'custom', true, true, null);
    perform create_task_list('CR-NullL', '#777777', 'custom', true, true, null);
    if (select count(*) from task where task_list_id = 992001 and title = 'CR-Null') <> 2
       or (select count(*) from task_list where home_id = 992001 and name = 'CR-NullL') <> 2 then
        raise exception 'client_request C5: con null se deduplicó';
    end if;
    if (select count(*) from client_request) <> v_before then
        raise exception 'client_request C5: con null se escribió en client_request';
    end if;
    raise notice 'ok C5: sin clave → dos altas de cada, sin filas en client_request';
end $$;

-- ── C6: recurso borrado ──
do $$
begin
    perform pg_temp.as_user(1);
    perform delete_task((select resource_id from client_request where app_user_id = 992001
                         and client_request_id = '11111111-1111-4111-8111-111111111111'));
    perform pg_temp.fails('C6 tarea borrada',
        $q$select create_task(992001, 'CR-T1', null, '11111111-1111-4111-8111-111111111111')$q$,
        'P0002', 'Not Found');
    perform delete_task_list((select resource_id from client_request where app_user_id = 992001
                              and client_request_id = '22222222-2222-4222-8222-222222222222'));
    perform pg_temp.fails('C6 lista borrada',
        $q$select create_task_list('CR-Lista', '#444444', 'custom', true, false, '22222222-2222-4222-8222-222222222222')$q$,
        'P0002', 'Not Found');
    if exists (select 1 from task where title like 'CR-T1%') or exists (select 1 from task_list where name like 'CR-Lista%') then
        raise exception 'client_request C6: el replay recreó el recurso borrado';
    end if;
    raise notice 'ok C6: recurso borrado → Not Found sin recrearlo';
end $$;

-- ── C7: firmas y llamadas antiguas ──
do $$
declare
    v json;
begin
    if (select count(*) from pg_proc where proname = 'create_task' and pronamespace = 'public'::regnamespace) <> 1
       or (select count(*) from pg_proc where proname = 'create_task_list' and pronamespace = 'public'::regnamespace) <> 1 then
        raise exception 'client_request C7: más de una firma de create_task/create_task_list';
    end if;
    perform pg_temp.as_user(1);
    v := create_task(992001, 'CR-Pos2');
    v := create_task(992001, 'CR-Pos3', null);
    v := create_task(p_task_list_id => 992001, p_title => 'CR-Nombre', p_person_ids => null);
    v := create_task_list('CR-PosL', '#888888', 'custom', true, true);
    if (v->>'id') is null or (select count(*) from task where task_list_id = 992001 and title in ('CR-Pos2', 'CR-Pos3', 'CR-Nombre')) <> 3 then
        raise exception 'client_request C7: las llamadas antiguas no crearon lo esperado';
    end if;
    raise notice 'ok C7: una firma por RPC; llamadas posicionales y por nombre antiguas ok';
end $$;

-- ── C8: permisos ──
do $$
declare
    -- 0037 (prioridad-tarea) amplía la firma de create_task: se resuelve la única por proname (C7)
    -- en lugar de castear la de 0035, así C8 vale con y sin 0037.
    v_ct oid := (select oid from pg_proc where proname = 'create_task' and pronamespace = 'public'::regnamespace);
begin
    if not (select relrowsecurity from pg_class where oid = 'public.client_request'::regclass)
       or exists (select 1 from pg_policy where polrelid = 'public.client_request'::regclass) then
        raise exception 'client_request C8: RLS desactivada o con policies';
    end if;
    if has_table_privilege('anon', 'public.client_request', 'select,insert,update,delete')
       or has_table_privilege('authenticated', 'public.client_request', 'select,insert,update,delete') then
        raise exception 'client_request C8: anon/authenticated con privilegios sobre client_request';
    end if;
    if v_ct is null or has_function_privilege('anon', v_ct, 'execute')
       or has_function_privilege('anon', 'create_task_list(text,text,text,boolean,boolean,uuid)', 'execute')
       or not has_function_privilege('authenticated', v_ct, 'execute')
       or not has_function_privilege('authenticated', 'create_task_list(text,text,text,boolean,boolean,uuid)', 'execute') then
        raise exception 'client_request C8: EXECUTE incorrecto en las RPC';
    end if;
    raise notice 'ok C8: client_request sin acceso directo; RPC solo para authenticated';
end $$;

-- ── C9: limpieza ──
select pg_temp.clean();
do $$
begin
    if exists (select 1 from app_user where id between 992001 and 992002)
       or exists (select 1 from home where id in (992001, 992002))
       or exists (select 1 from client_request where app_user_id between 992001 and 992002) then
        raise exception 'client_request C9: quedaron filas scratch';
    end if;
    raise notice 'ok C9: 0 filas scratch';
end $$;
