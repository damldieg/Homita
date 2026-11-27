-- marcar_hecho_check.sql — Pantallas que completan tareas (0050_marcar_hecho.sql, dashboard-marcar-hecho).
-- Solo BD local, tras aplicar 0050:  psql -v ON_ERROR_STOP=1 -f marcar_hecho_check.sql
-- Cada bloque emite 'ok MH…' o aborta con 'marcar_hecho …'.
--
-- Fixture (ids 995xxx, auth_uid …0951–…0955): hogar H (995001) con A owner de la lista L1 (995001), pantalla D
-- (cuenta técnica 995002) con L1 en su selección y solo task.view/task.complete, y V (995003), viewer no pantalla
-- de L1 sin can_edit. Hogar O (995002) con su lista L2 (995002) ajena a D.
--
-- MH1 la pantalla completa una tarea de su lista (audit_log source display; completed_at puesto).
-- MH2 la pantalla descompleta (audit task.uncomplete).
-- MH3 tarea de una lista fuera de su selección → 'Not Found'; de otro hogar → 'Not Found'.
-- MH4 el viewer no pantalla sin can_edit → 'Not Allowed' (regresión 0029).
-- MH5 idempotencia: la misma clave dos veces no vuelve a aplicar el cambio.
-- MH6 una clave usada para otra tarea → 'Invalid client_request_id'.
-- MH7 la pantalla no edita, no crea y no borra (update_task, create_task, delete_task → 'Not Allowed').
-- Limpieza y 'ok MH-clean'.

\set ON_ERROR_STOP 1
do $$
begin
    if inet_server_addr() is not null and host(inet_server_addr()) not in ('127.0.0.1', '::1') then
        raise exception 'marcar_hecho_check: solo BD local (socket o loopback); servidor %', host(inet_server_addr());
    end if;
    if to_regprocedure('public.complete_task(bigint,boolean,uuid)') is null then
        raise exception 'marcar_hecho_check: 0050 no está aplicada';
    end if;
end $$;

create function pg_temp.clean() returns void
language plpgsql as $$
begin
    set local session_replication_role = replica;
    delete from client_request where app_user_id between 995001 and 995004;
    delete from audit_log where home_id in (995001, 995002);
    delete from task where task_list_id in (995001, 995002);
    delete from task_list_user where task_list_id in (995001, 995002);
    delete from home_display_task_list where task_list_id in (995001, 995002);
    delete from home_display where home_id in (995001, 995002);
    delete from task_list where id in (995001, 995002);
    delete from membership_permission where home_membership_id between 995001 and 995004;
    delete from home_member where home_id in (995001, 995002);
    delete from home_membership where home_id in (995001, 995002);
    update app_user set default_home_id = null where id between 995001 and 995004;
    delete from home where id in (995001, 995002);
    delete from app_user where id between 995001 and 995004;
    delete from auth.users where id::text like '00000000-0000-4000-8000-00000000095%';
end $$;

create function pg_temp.as_user(p_n int) returns void
language sql as $$
    select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-00000000095' || p_n, true)
$$;

create function pg_temp.fails(p_label text, p_sql text, p_state text, p_msg text) returns void
language plpgsql as $$
begin
    execute p_sql;
    raise exception 'marcar_hecho %: no falló: %', p_label, p_sql;
exception when others then
    if sqlstate <> p_state or sqlerrm <> p_msg then
        raise exception 'marcar_hecho %: % % (esperado % %)', p_label, sqlstate, sqlerrm, p_state, p_msg;
    end if;
end $$;

select pg_temp.clean();

-- ── Fixture ──
begin;
set session_replication_role = replica;
insert into auth.users (id, email) values
    ('00000000-0000-4000-8000-000000000951', 'mh-a@check.homita.example'),
    ('00000000-0000-4000-8000-000000000952', 'mh-d@check.homita.example'),
    ('00000000-0000-4000-8000-000000000953', 'mh-v@check.homita.example'),
    ('00000000-0000-4000-8000-000000000954', 'mh-o@check.homita.example');
insert into app_user (id, auth_uid, name, email) values
    (995001, '00000000-0000-4000-8000-000000000951', 'MH-A', 'mh-a@check.homita.example'),
    (995002, '00000000-0000-4000-8000-000000000952', 'MH-D', 'mh-d@check.homita.example'),
    (995003, '00000000-0000-4000-8000-000000000953', 'MH-V', 'mh-v@check.homita.example'),
    (995004, '00000000-0000-4000-8000-000000000954', 'MH-O', 'mh-o@check.homita.example');
set session_replication_role = default;

insert into home (id, name, status, is_personal, created_by) values
    (995001, 'MH-Hogar H', 'active', false, 995001),
    (995002, 'MH-Hogar O', 'active', false, 995004);
insert into home_membership (id, home_id, app_user_id, role) values
    (995001, 995001, 995001, 'admin'),
    (995002, 995001, 995002, 'member'),
    (995003, 995001, 995003, 'member'),
    (995004, 995002, 995004, 'admin');
update app_user set default_home_id = 995001 where id in (995001, 995002, 995003);
insert into membership_permission (home_membership_id, permission_code) values
    (995002, 'task.view'), (995002, 'task.complete'), (995003, 'task.view');
insert into home_member (id, home_id, kind, name, color, app_user_id, status) values
    (995001, 995001, 'adult', 'MH-MA', '#110000', 995001, 'active'),
    (995002, 995001, 'display', 'MH-PANT', '#220000', 995002, 'active'),
    (995003, 995001, 'adult', 'MH-MV', '#330000', 995003, 'active'),
    (995004, 995002, 'adult', 'MH-MO', '#440000', 995004, 'active');
insert into task_list (id, name, color, token, sort, home_id) values
    (995001, 'MH-L1', '#111111', 'mh-token-995001', 'title', 995001),
    (995002, 'MH-L2', '#222222', 'mh-token-995002', 'title', 995002);
insert into task_list_user (task_list_id, user_id, role, widget, dashboard, home_id) values
    (995001, 995001, 'owner', true, true, 995001),
    (995001, 995002, 'viewer', false, true, 995001),
    (995001, 995003, 'viewer', true, true, 995001),
    (995002, 995004, 'owner', true, true, 995002);
insert into home_display (id, home_id, app_user_id, home_member_id, name, linked_by) values
    (995001, 995001, 995002, 995002, 'MH-Pantalla', 995001);
insert into home_display_task_list (display_id, task_list_id) values (995001, 995001);
insert into task (id, task_list_id, title, "order") values
    (995001, 995001, 'MH-T1', 1), (995002, 995001, 'MH-T2', 2),
    (995003, 995001, 'MH-T3', 3), (995004, 995002, 'MH-T4', 1);
commit;

-- ── MH1 / MH2 ──
do $$
declare v_key uuid := 'a0000000-0000-4000-8000-000000000001';
begin
    perform pg_temp.as_user(2);
    perform complete_task(995001, true, v_key);
    if (select completed_at from task where id = 995001) is null then raise exception 'marcar_hecho MH1: no quedó completada'; end if;
    if not exists (select 1 from audit_log where home_id = 995001 and action = 'task.complete' and target_id = 995001
                   and payload->>'source' = 'display') then
        raise exception 'marcar_hecho MH1: falta el registro de auditoría de la pantalla';
    end if;
    perform complete_task(995001, false, 'a0000000-0000-4000-8000-000000000002');
    if (select completed_at from task where id = 995001) is not null then raise exception 'marcar_hecho MH2: no se descompletó'; end if;
    if not exists (select 1 from audit_log where home_id = 995001 and action = 'task.uncomplete' and target_id = 995001) then
        raise exception 'marcar_hecho MH2: falta el registro de descompletar';
    end if;
    raise notice 'ok MH1: la pantalla completa su tarea y queda auditado';
    raise notice 'ok MH2: la pantalla descompleta y queda auditado';
end $$;

-- ── MH3 ──
do $$
begin
    perform pg_temp.as_user(2);
    perform pg_temp.fails('MH3a', 'select complete_task(995004, true)', 'P0002', 'Not Found');
    -- La lista L2 es de otro hogar y no hay ninguna fila de ACL de la pantalla en ella
    raise notice 'ok MH3: lista fuera de la selección y de otro hogar → Not Found';
end $$;

-- ── MH4 ──
do $$
begin
    perform pg_temp.as_user(3);
    perform pg_temp.fails('MH4', 'select complete_task(995002, true)', '42501', 'Not Allowed');
    raise notice 'ok MH4: viewer sin can_edit y sin ser pantalla no completa';
end $$;

-- ── MH5 / MH6 ──
do $$
declare v_key uuid := 'a0000000-0000-4000-8000-000000000003';
begin
    perform set_config('role', 'postgres', true);
    perform pg_temp.as_user(2);
    perform complete_task(995002, true, v_key);
    perform complete_task(995002, false, 'a0000000-0000-4000-8000-000000000004');
    -- Reenvío con la clave original (toque repetido en cola): no vuelve a completar
    perform complete_task(995002, true, v_key);
    if (select completed_at from task where id = 995002) is not null then
        raise exception 'marcar_hecho MH5: el reenvío volvió a aplicar el cambio';
    end if;
    raise notice 'ok MH5: reenvío con la misma clave no aplica el cambio';
    perform pg_temp.fails('MH6', format('select complete_task(995003, true, %L)', v_key), 'P0001', 'Invalid client_request_id');
    raise notice 'ok MH6: clave usada para otra tarea → Invalid client_request_id';
end $$;

-- ── MH7 ──
do $$
begin
    perform pg_temp.as_user(2);
    perform pg_temp.fails('MH7a', 'select update_task(995001, ''editada'')', '42501', 'Not Allowed');
    perform pg_temp.fails('MH7b', 'select create_task(995001, ''nueva'')', '42501', 'Not Allowed');
    perform pg_temp.fails('MH7c', 'select delete_task(995001)', '42501', 'Not Allowed');
    raise notice 'ok MH7: la pantalla no edita, no crea y no borra';
end $$;

do $$
begin
    perform pg_temp.clean();
    raise notice 'ok MH-clean';
end $$;
