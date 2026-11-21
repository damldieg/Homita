-- task_priority_check.sql — Prioridad de tarea (0037_task_priority.sql, change prioridad-tarea, D-026).
-- Solo BD local, tras el reset 0001–0037:  psql -v ON_ERROR_STOP=1 -f task_priority_check.sql
-- Cada bloque DO emite 'ok Px: …' o aborta con 'task_priority Px: …'.
--
-- Fixture (ids 993xxx, auth_uid …0931): hogar H con A admin, owner de la lista L (orden custom).
--
-- P1 columna task.priority text NOT NULL DEFAULT 'media' con task_priority_check (alta|media|baja).
-- P2 0 filas con prioridad nula o fuera de las tres opciones (backfill).
-- P3 una sola firma por RPC (la nueva) y su ACL: authenticated sí; ni PUBLIC ni anon; get_tasks
--    también para service_role.
-- P4 create_task sin prioridad → 'media' en la fila y en la respuesta.
-- P5 create_task con 'alta' → 'alta'.
-- P6 prioridad inválida ('urgente', '', 'ALTA') → 'Invalid priority' P0001 sin fila nueva, en
--    create y en update (la fila no cambia).
-- P7 update_task con null conserva la prioridad; con valor la cambia.
-- P8 get_tasks(p_priority => 'alta') solo devuelve 'alta'; todas las respuestas llevan 'priority'.
-- P9 get_tasks(p_sort => 'priority'): pendientes alta > media > baja (desempate order, id) y
--    completadas al final; sin p_sort el orden es el de antes (completadas al final, order, id).
-- P10 replay con client_request_id ignora la prioridad del reenvío; las llamadas posicionales y
--     por nombre antiguas resuelven (create_task de 2, 3 y 4 args, update_task de 2, get_tasks de 3).
-- Al final, 0 filas scratch.

\set ON_ERROR_STOP 1
do $$
begin
    if inet_server_addr() is not null and host(inet_server_addr()) not in ('127.0.0.1', '::1') then
        raise exception 'task_priority_check: solo BD local (socket o loopback); servidor %', host(inet_server_addr());
    end if;
end $$;

create function pg_temp.clean() returns void
language plpgsql as $$
begin
    set local session_replication_role = replica;
    delete from client_request where app_user_id = 993001;
    delete from task_person where task_id in (select t.id from task t join task_list tl on tl.id = t.task_list_id
                                              where tl.home_id = 993001);
    delete from task where task_list_id in (select id from task_list where home_id = 993001);
    delete from task_list_user where task_list_id in (select id from task_list where home_id = 993001);
    delete from task_list where home_id = 993001;
    delete from membership_permission where home_membership_id = 993001;
    delete from home_membership where home_id = 993001;
    delete from audit_log where home_id = 993001;
    update app_user set default_home_id = null where id = 993001;
    delete from home where id = 993001;
    delete from app_user where id = 993001;
    delete from auth.users where id = '00000000-0000-4000-8000-000000000931';
end $$;

-- Ejecuta p_sql y exige el error p_msg (sqlstate p_state).
create function pg_temp.fails(p_label text, p_sql text, p_state text, p_msg text) returns void
language plpgsql as $$
begin
    execute p_sql;
    raise exception 'task_priority %: no falló: %', p_label, p_sql;
exception when others then
    if sqlstate <> p_state or sqlerrm <> p_msg then
        raise exception 'task_priority %: % % (esperado % %)', p_label, sqlstate, sqlerrm, p_state, p_msg;
    end if;
end $$;

create function pg_temp.as_a() returns void
language sql as $$
    select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000931', true)
$$;

select pg_temp.clean();

-- ── Fixture ──
set session_replication_role = replica;
insert into auth.users (id, email, raw_user_meta_data) values
    ('00000000-0000-4000-8000-000000000931', 'tp-a@check.homita.example', '{"name":"TP-A"}');
insert into app_user (id, auth_uid, name, email) values
    (993001, '00000000-0000-4000-8000-000000000931', 'TP-A', 'tp-a@check.homita.example');
set session_replication_role = default;

begin;
insert into home (id, name, status, is_personal, created_by) values (993001, 'TP-Hogar H', 'active', false, 993001);
insert into home_membership (id, home_id, app_user_id, role) values (993001, 993001, 993001, 'admin');
update app_user set default_home_id = 993001 where id = 993001;
insert into task_list (id, name, color, token, sort, home_id) values (993001, 'TP-L', '#222222', 'tp-tok-1', 'custom', 993001);
insert into task_list_user (task_list_id, user_id, role, widget, dashboard, home_id) values (993001, 993001, 'owner', true, true, 993001);
commit;

-- ── P1: columna ──
do $$
begin
    if not exists (
        select 1 from information_schema.columns
        where table_schema = 'public' and table_name = 'task' and column_name = 'priority'
          and data_type = 'text' and is_nullable = 'NO' and column_default = '''media''::text'
    ) then
        raise exception 'task_priority P1: task.priority no es text NOT NULL DEFAULT ''media''';
    end if;
    if not exists (
        select 1 from pg_constraint
        where conrelid = 'public.task'::regclass and conname = 'task_priority_check' and contype = 'c'
          and pg_get_constraintdef(oid) like '%alta%media%baja%'
    ) then
        raise exception 'task_priority P1: falta task_priority_check';
    end if;
    raise notice 'ok P1: task.priority text NOT NULL DEFAULT media con task_priority_check';
end $$;

-- ── P2: backfill ──
do $$
declare
    v_bad bigint := (select count(*) from task where priority is null or priority not in ('alta', 'media', 'baja'));
begin
    if v_bad <> 0 then
        raise exception 'task_priority P2: % filas con prioridad inválida', v_bad;
    end if;
    raise notice 'ok P2: 0 filas con prioridad nula o inválida (de % tareas)', (select count(*) from task);
end $$;

-- ── P3: firmas y ACL ──
do $$
declare
    v_sigs text[];
begin
    select array_agg(oid::regprocedure::text order by proname) into v_sigs
      from pg_proc where pronamespace = 'public'::regnamespace and proname in ('create_task', 'get_tasks', 'update_task');
    if v_sigs is distinct from array['create_task(bigint,text,jsonb,uuid,text)',
                                     'get_tasks(boolean,bigint,boolean,text,text)',
                                     'update_task(bigint,text,jsonb,text)'] then
        raise exception 'task_priority P3: firmas %', v_sigs;
    end if;
    if exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace
                and p.proname in ('create_task', 'get_tasks', 'update_task')
                and (p.proacl is null
                     or exists (select 1 from aclexplode(p.proacl) a where a.grantee = 0 and a.privilege_type = 'EXECUTE')
                     or has_function_privilege('anon', p.oid, 'execute')
                     or not has_function_privilege('authenticated', p.oid, 'execute'))) then
        raise exception 'task_priority P3: EXECUTE incorrecto (authenticated sí; PUBLIC y anon no)';
    end if;
    if not has_function_privilege('service_role', 'get_tasks(boolean,bigint,boolean,text,text)', 'execute') then
        raise exception 'task_priority P3: service_role sin EXECUTE en get_tasks';
    end if;
    raise notice 'ok P3: una firma por RPC (la nueva); EXECUTE authenticated (+service_role en get_tasks), sin PUBLIC ni anon';
end $$;

-- ── P4: create sin prioridad → media ──
do $$
declare
    v json;
begin
    perform pg_temp.as_a();
    v := create_task(993001, 'TP-Sin');
    if v->>'priority' is distinct from 'media'
       or (select priority from task where id = (v->>'id')::bigint) <> 'media' then
        raise exception 'task_priority P4: %', v;
    end if;
    raise notice 'ok P4: create_task sin prioridad → media';
end $$;

-- ── P5: create con alta ──
do $$
declare
    v json;
begin
    perform pg_temp.as_a();
    v := create_task(p_task_list_id => 993001, p_title => 'TP-Alta', p_priority => 'alta');
    if v->>'priority' is distinct from 'alta'
       or (select priority from task where id = (v->>'id')::bigint) <> 'alta' then
        raise exception 'task_priority P5: %', v;
    end if;
    raise notice 'ok P5: create_task con alta → alta';
end $$;

-- ── P6: inválida → Invalid priority sin fila ──
do $$
declare
    v_before bigint := (select count(*) from task where task_list_id = 993001);
    v_id bigint := (select id from task where task_list_id = 993001 and title = 'TP-Sin');
    v_row text;
begin
    perform pg_temp.as_a();
    perform pg_temp.fails('P6 create urgente', $q$select create_task(p_task_list_id => 993001, p_title => 'TP-X', p_priority => 'urgente')$q$, 'P0001', 'Invalid priority');
    perform pg_temp.fails('P6 create vacía', $q$select create_task(p_task_list_id => 993001, p_title => 'TP-X', p_priority => '')$q$, 'P0001', 'Invalid priority');
    perform pg_temp.fails('P6 create ALTA', $q$select create_task(p_task_list_id => 993001, p_title => 'TP-X', p_priority => 'ALTA')$q$, 'P0001', 'Invalid priority');
    if (select count(*) from task where task_list_id = 993001) <> v_before then
        raise exception 'task_priority P6: se insertó una fila pese al error';
    end if;
    select row(title, priority, updated_at)::text into v_row from task where id = v_id;
    perform pg_temp.fails('P6 update urgente', format($q$select update_task(%s, 'TP-Cambiado', null, 'urgente')$q$, v_id), 'P0001', 'Invalid priority');
    if (select row(title, priority, updated_at)::text from task where id = v_id) <> v_row then
        raise exception 'task_priority P6: update inválido cambió la fila';
    end if;
    raise notice 'ok P6: prioridad inválida → Invalid priority P0001, sin fila nueva y sin cambios';
end $$;

-- ── P7: update conserva / cambia ──
do $$
declare
    v_id bigint := (select id from task where task_list_id = 993001 and title = 'TP-Alta');
    v json;
begin
    perform pg_temp.as_a();
    v := update_task(v_id, 'TP-Alta 2');
    if v->>'priority' is distinct from 'alta' then
        raise exception 'task_priority P7: update sin prioridad no conservó (%)', v;
    end if;
    v := update_task(p_id => v_id, p_title => 'TP-Alta 2', p_priority => 'baja');
    if v->>'priority' is distinct from 'baja' or (select priority from task where id = v_id) <> 'baja' then
        raise exception 'task_priority P7: update con baja no cambió (%)', v;
    end if;
    perform update_task(v_id, 'TP-Alta', null, 'alta');
    raise notice 'ok P7: update_task null conserva; con valor cambia';
end $$;

-- ── P8: filtro ──
do $$
declare
    v json;
begin
    perform pg_temp.as_a();
    perform create_task(p_task_list_id => 993001, p_title => 'TP-Baja', p_priority => 'baja');
    perform create_task(p_task_list_id => 993001, p_title => 'TP-Alta B', p_priority => 'alta');
    v := get_tasks(p_task_list_id => 993001, p_priority => 'alta');
    if json_array_length(v) <> 2 or exists (select 1 from json_array_elements(v) e where e->>'priority' <> 'alta') then
        raise exception 'task_priority P8: filtro alta → %', v;
    end if;
    v := get_tasks(p_task_list_id => 993001);
    if exists (select 1 from json_array_elements(v) e where not (e::jsonb ? 'priority')) then
        raise exception 'task_priority P8: falta la clave priority en get_tasks';
    end if;
    if json_array_length(get_tasks(p_task_list_id => 993001, p_priority => 'x')) <> 0 then
        raise exception 'task_priority P8: un filtro desconocido debería devolver []';
    end if;
    raise notice 'ok P8: get_tasks(p_priority) filtra; todas las filas llevan priority';
end $$;

-- ── P9: orden ──
do $$
declare
    v_got bigint[];
    v_want bigint[];
begin
    perform pg_temp.as_a();
    -- Una completada de prioridad alta: tiene que quedar al final igualmente.
    perform complete_task((select id from task where task_list_id = 993001 and title = 'TP-Alta B'), true);
    select array_agg((e->>'id')::bigint order by ord) into v_got
      from json_array_elements(get_tasks(p_task_list_id => 993001, p_sort => 'priority')) with ordinality as x(e, ord);
    select array_agg(id order by (completed_at is not null), case priority when 'alta' then 1 when 'media' then 2 else 3 end, "order", id)
      into v_want from task where task_list_id = 993001;
    if v_got is distinct from v_want then
        raise exception 'task_priority P9: p_sort=priority % (esperado %)', v_got, v_want;
    end if;
    if (select priority from task where id = v_got[1]) <> 'alta'
       or (select completed_at from task where id = v_got[array_length(v_got, 1)]) is null then
        raise exception 'task_priority P9: no empieza por alta pendiente o no acaba en completada';
    end if;
    select array_agg((e->>'id')::bigint order by ord) into v_got
      from json_array_elements(get_tasks(p_task_list_id => 993001)) with ordinality as x(e, ord);
    select array_agg(id order by (completed_at is not null), "order", id) into v_want from task where task_list_id = 993001;
    if v_got is distinct from v_want then
        raise exception 'task_priority P9: orden por defecto cambió % (esperado %)', v_got, v_want;
    end if;
    select array_agg((e->>'id')::bigint order by ord) into v_got
      from json_array_elements(get_tasks(p_task_list_id => 993001, p_sort => 'title')) with ordinality as x(e, ord);
    if v_got is distinct from v_want then
        raise exception 'task_priority P9: un p_sort desconocido cambió el orden';
    end if;
    raise notice 'ok P9: p_sort=priority alta>media>baja (desempate order, id), completadas al final; sin p_sort, el orden de siempre';
end $$;

-- ── P10: replay y llamadas antiguas ──
do $$
declare
    v1 json;
    v2 json;
begin
    perform pg_temp.as_a();
    v1 := create_task(993001, 'TP-Replay', null, '33333333-3333-4333-8333-333333333333', 'alta');
    v2 := create_task(993001, 'TP-Replay', null, '33333333-3333-4333-8333-333333333333', 'baja');
    if v1::text <> v2::text or v2->>'priority' <> 'alta' then
        raise exception 'task_priority P10: el replay no devolvió la original (% / %)', v1, v2;
    end if;
    perform create_task(993001, 'TP-Pos2');
    perform create_task(993001, 'TP-Pos3', null);
    perform create_task(993001, 'TP-Pos4', null, '44444444-4444-4444-8444-444444444444');
    perform create_task(p_task_list_id => 993001, p_title => 'TP-Nombre', p_person_ids => null);
    perform update_task((v1->>'id')::bigint, 'TP-Replay 2');
    perform get_tasks(p_dashboard => null, p_task_list_id => 993001, p_widget => null);
    perform get_tasks(null, 993001, null);
    if (select count(*) from task where task_list_id = 993001 and title in ('TP-Pos2', 'TP-Pos3', 'TP-Pos4', 'TP-Nombre')
                                     and priority = 'media') <> 4
       or (select priority from task where id = (v1->>'id')::bigint) <> 'alta' then
        raise exception 'task_priority P10: llamadas antiguas sin el resultado esperado';
    end if;
    raise notice 'ok P10: replay ignora la prioridad del reenvío; llamadas antiguas posicionales y por nombre ok';
end $$;

-- ── Limpieza ──
select pg_temp.clean();
do $$
begin
    if exists (select 1 from app_user where id = 993001) or exists (select 1 from home where id = 993001)
       or exists (select 1 from task_list where id = 993001) then
        raise exception 'task_priority: quedaron filas scratch';
    end if;
    raise notice 'ok P-clean: 0 filas scratch';
end $$;
