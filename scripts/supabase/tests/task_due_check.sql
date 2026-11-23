-- task_due_check.sql — Fecha límite de tareas (0041_task_due_at.sql, change fecha-limite-vencimiento, [10]).
-- Solo BD local, tras aplicar 0001–0041 (update_task sigue con 4 argumentos):  psql -v ON_ERROR_STOP=1 -f task_due_check.sql
-- Cada bloque emite 'ok DNn: …' o aborta con 'task_due DNn: …'.
--
-- Fixture (ids 9971xx, auth_uid …0961–…0962): hogar H con A admin (owner de la lista L con can_edit) y
-- X miembro sin ACL sobre L.
--
-- DN1 columna task.due_at timestamp nullable.
-- DN2 una tarea nueva no tiene fecha (get_task_detail due_at null).
-- DN3 task_due_set fija la fecha; get_task_detail y get_tasks la devuelven en UTC.
-- DN4 update_task (título) no toca la fecha.
-- DN5 task_due_set con p_clear_due = true la borra.
-- DN6 fecha ilegible en task_due_set → 'Invalid due_at' P0001 y nada cambia.
-- DN7 X (sin ACL) → Not Found P0002 y nada cambia.
-- DN8 anon sin EXECUTE sobre task_due_set.
-- Al final, 0 filas scratch.

\set ON_ERROR_STOP 1
do $$
begin
    if inet_server_addr() is not null and host(inet_server_addr()) not in ('127.0.0.1', '::1') then
        raise exception 'task_due_check: solo BD local (socket o loopback); servidor %', host(inet_server_addr());
    end if;
    if not exists (select 1 from information_schema.columns
                    where table_schema = 'public' and table_name = 'task' and column_name = 'due_at') then
        raise exception 'task_due_check: 0041 no está aplicada (falta task.due_at)';
    end if;
end $$;

create function pg_temp.clean() returns void
language plpgsql as $$
begin
    set local session_replication_role = replica;
    delete from client_request where app_user_id between 997101 and 997102;
    delete from task where task_list_id in (select id from task_list where home_id = 997101);
    delete from task_list_user where task_list_id in (select id from task_list where home_id = 997101);
    delete from task_list where home_id = 997101;
    delete from person where home_id = 997101;
    delete from home_member where home_id = 997101;
    delete from membership_permission where home_membership_id between 997101 and 997102;
    delete from home_membership where home_id = 997101;
    delete from audit_log where home_id = 997101;
    update app_user set default_home_id = null where id between 997101 and 997102;
    delete from home where id = 997101;
    delete from app_user where id between 997101 and 997102;
    delete from auth.users where id in ('00000000-0000-4000-8000-000000000961', '00000000-0000-4000-8000-000000000962');
end $$;

create function pg_temp.as_user(p_n int) returns void
language sql as $$
    select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-00000000096' || p_n, false)
$$;

create function pg_temp.expect_err(p_label text, p_sql text, p_state text, p_msg text) returns void
language plpgsql as $$
declare
    v_state text;
    v_text text;
begin
    execute p_sql;
    raise exception 'task_due %: no falló: %', p_label, p_sql;
exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_text = message_text;
    if v_state <> p_state or v_text <> p_msg then
        raise exception 'task_due %: % / % (esperado % / %)', p_label, v_state, v_text, p_state, p_msg;
    end if;
end $$;

select pg_temp.clean();

-- ── Fixture ──
set session_replication_role = replica;
insert into auth.users (id, email, raw_user_meta_data) values
    ('00000000-0000-4000-8000-000000000961', 'td-a@check.homita.example', '{"name":"TD-A"}'),
    ('00000000-0000-4000-8000-000000000962', 'td-x@check.homita.example', '{"name":"TD-X"}');
insert into app_user (id, auth_uid, name, email) values
    (997101, '00000000-0000-4000-8000-000000000961', 'TD-A', 'td-a@check.homita.example'),
    (997102, '00000000-0000-4000-8000-000000000962', 'TD-X', 'td-x@check.homita.example');
set session_replication_role = default;

begin;
insert into home (id, name, status, is_personal, created_by) values (997101, 'TD-Hogar H', 'active', false, 997101);
insert into home_membership (id, home_id, app_user_id, role) values
    (997101, 997101, 997101, 'admin'),
    (997102, 997101, 997102, 'member');
update app_user set default_home_id = 997101 where id between 997101 and 997102;
insert into task_list (id, name, color, token, sort, home_id) values
    (997101, 'TD-Lista', '#111111', 'td-tok-1', 'custom', 997101);
insert into task_list_user (task_list_id, user_id, role, widget, dashboard, home_id, can_edit) values
    (997101, 997101, 'owner', true, true, 997101, false);
commit;
select fn_seed_kind_permissions(997102, 'adult');

-- ── DN1 ──
do $$
declare v_null text;
begin
    select is_nullable into v_null from information_schema.columns
     where table_schema = 'public' and table_name = 'task' and column_name = 'due_at';
    if v_null is distinct from 'YES' then
        raise exception 'task_due DN1: due_at nullable=%', v_null;
    end if;
    raise notice 'ok DN1: task.due_at timestamp nullable';
end $$;

-- Tarea de prueba creada por A.
select pg_temp.as_user(1);
select set_config('task_due.tid', (create_task(997101, 'Leche', null, null, 'alta')->>'id'), false);

-- ── DN2 ──
do $$
declare v_tid bigint := current_setting('task_due.tid')::bigint;
begin
    perform pg_temp.as_user(1);
    if (get_task_detail(v_tid)->>'due_at') is not null then
        raise exception 'task_due DN2: tarea nueva con fecha';
    end if;
    raise notice 'ok DN2: tarea nueva sin fecha';
end $$;

-- ── DN3 ──
do $$
declare v_tid bigint := current_setting('task_due.tid')::bigint; v_seen text;
begin
    perform pg_temp.as_user(1);
    perform task_due_set(v_tid, '2026-12-03 18:00:00', false);
    if (get_task_detail(v_tid)->>'due_at') is distinct from '2026-12-03 18:00:00' then
        raise exception 'task_due DN3: detalle % ', get_task_detail(v_tid)->>'due_at';
    end if;
    select x->>'due_at' into v_seen
      from json_array_elements(get_tasks(null, 997101, null, null, null)) x
     where (x->>'id')::bigint = v_tid;
    if v_seen is distinct from '2026-12-03 18:00:00' then
        raise exception 'task_due DN3: listado %', v_seen;
    end if;
    raise notice 'ok DN3: fijar fecha en UTC, visible en detalle y listado';
end $$;

-- ── DN4 ──
do $$
declare v_tid bigint := current_setting('task_due.tid')::bigint;
begin
    perform pg_temp.as_user(1);
    perform update_task(v_tid, 'Leche entera');
    if (get_task_detail(v_tid)->>'due_at') is distinct from '2026-12-03 18:00:00' then
        raise exception 'task_due DN4: se tocó la fecha sin pedirlo';
    end if;
    raise notice 'ok DN4: sin fecha en la llamada no se toca';
end $$;

-- ── DN5 ──
do $$
declare v_tid bigint := current_setting('task_due.tid')::bigint;
begin
    perform pg_temp.as_user(1);
    perform task_due_set(v_tid, null, true);
    if (get_task_detail(v_tid)->>'due_at') is not null then
        raise exception 'task_due DN5: no se borró la fecha';
    end if;
    raise notice 'ok DN5: p_clear_due borra la fecha';
end $$;

-- ── DN6 ──
do $$
declare v_tid bigint := current_setting('task_due.tid')::bigint;
begin
    perform pg_temp.as_user(1);
    perform task_due_set(v_tid, '2026-12-03 18:00:00', false);
    perform pg_temp.expect_err('DN6', format('select task_due_set(%s, ''2026-13-01 10:00:00'', false)', v_tid),
                               'P0001', 'Invalid due_at');
    if (get_task_detail(v_tid)->>'due_at') is distinct from '2026-12-03 18:00:00' then
        raise exception 'task_due DN6: la fecha cambió tras un error';
    end if;
    raise notice 'ok DN6: fecha ilegible → Invalid due_at, sin cambios';
end $$;

-- ── DN7 ──
do $$
declare v_tid bigint := current_setting('task_due.tid')::bigint;
begin
    perform pg_temp.as_user(2);
    perform pg_temp.expect_err('DN7', format('select task_due_set(%s, null, true)', v_tid), 'P0002', 'Not Found');
    perform pg_temp.as_user(1);
    if (get_task_detail(v_tid)->>'due_at') is distinct from '2026-12-03 18:00:00' then
        raise exception 'task_due DN7: un no miembro cambió la fecha';
    end if;
    raise notice 'ok DN7: sin ACL → Not Found, fila intacta';
end $$;

-- ── DN8 ──
do $$
begin
    if has_function_privilege('anon', 'task_due_set(bigint, text, boolean)', 'EXECUTE') then
        raise exception 'task_due DN8: anon puede ejecutar task_due_set';
    end if;
    raise notice 'ok DN8: anon sin EXECUTE sobre task_due_set';
end $$;

-- ── Limpieza ──
select pg_temp.clean();
do $$
begin
    if exists (select 1 from task where task_list_id = 997101) then
        raise exception 'task_due: quedan filas scratch';
    end if;
    raise notice 'ok 0 filas scratch';
end $$;
