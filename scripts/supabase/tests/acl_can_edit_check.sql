-- acl_can_edit_check.sql — Permiso de edición por calendario y lista (0029_acl_can_edit.sql).
-- Solo BD local, tras el reset 0001–0029:  psql -v ON_ERROR_STOP=1 -f acl_can_edit_check.sql
-- Cada bloque DO emite 'ok Kx: …' o aborta con 'acl_can_edit Kx: …'.
--
-- Fixture (ids 996xxx, auth_uid …0961–…0965): hogar H con A admin (owner de C y L), M adult en
-- lectura, E adult en edición, X adult con cuenta sin ACL; hogar B con Y admin. Todos los adultos
-- tienen el catálogo completo de su kind, así que lo único que cambia entre M y E es can_edit.
--
-- K1 lectura: las 12 RPC de contenido → 'Not Allowed' 42501; renombrar → 42501; flags propios y
--    alarma propia → ok.
-- K2 edición: crear/editar/completar/ordenar/borrar → ok; renombrar → ok; borrar el recurso y
--    gestionar usuarios → 42501 (siguen siendo de owner).
-- K3 owner cambia el permiso de M (lectura → edición → lectura) y persiste.
-- K4 no-owner (E) → 42501; owner sobre sí mismo, sobre otro owner o sobre una cuenta de otro hogar
--    → 42501; anon sin EXECUTE; helpers sin EXECUTE para authenticated.
-- K5 owner da acceso a X (no estaba en el ACL) → fila viewer con can_edit pedido.
-- K6 lecturas: get_*_users y get_calendars/get_task_lists exponen can_edit efectivo.
-- K7 add_calendar_user / add_task_list_user nuevos entran en lectura.
-- K8 0 filas scratch al terminar.

\set ON_ERROR_STOP 1
do $$
begin
    if inet_server_addr() is not null and host(inet_server_addr()) not in ('127.0.0.1', '::1') then
        raise exception 'acl_can_edit_check: solo BD local (socket o loopback); servidor %', host(inet_server_addr());
    end if;
end $$;

create function pg_temp.clean() returns void
language plpgsql as $$
begin
    set local session_replication_role = replica;
    delete from event_user where user_id between 996001 and 996005
       or event_id in (select id from event where calendar_id between 996001 and 996002);
    delete from routine_event_alarm where user_id between 996001 and 996005;
    delete from routine_exception where routine_id in (select id from routine where calendar_id between 996001 and 996002);
    delete from event_person where event_id in (select id from event where calendar_id between 996001 and 996002);
    delete from routine_person where routine_id in (select id from routine where calendar_id between 996001 and 996002);
    delete from event where calendar_id between 996001 and 996002;
    delete from routine where calendar_id between 996001 and 996002;
    delete from task_person where task_id in (select id from task where task_list_id between 996001 and 996002);
    delete from task where task_list_id between 996001 and 996002;
    delete from task_list_user where task_list_id between 996001 and 996002;
    delete from task_list where id between 996001 and 996002;
    delete from calendar_user where calendar_id between 996001 and 996002;
    delete from calendar where id between 996001 and 996002;
    delete from person where home_id in (996001, 996002);
    delete from home_member where home_id in (996001, 996002);
    delete from membership_permission where home_membership_id between 996001 and 996005;
    delete from home_membership where home_id in (996001, 996002);
    delete from audit_log where home_id in (996001, 996002);
    update app_user set default_home_id = null where id between 996001 and 996005;
    delete from home where id in (996001, 996002);
    delete from app_user where id between 996001 and 996005;
    delete from auth.users where id in (
        '00000000-0000-4000-8000-000000000961', '00000000-0000-4000-8000-000000000962',
        '00000000-0000-4000-8000-000000000963', '00000000-0000-4000-8000-000000000964',
        '00000000-0000-4000-8000-000000000965');
end $$;

-- Ejecuta p_sql y exige 'Not Allowed' 42501.
create function pg_temp.denied(p_label text, p_sql text) returns void
language plpgsql as $$
begin
    execute p_sql;
    raise exception 'acl_can_edit %: no falló: %', p_label, p_sql;
exception when sqlstate '42501' then
    if sqlerrm <> 'Not Allowed' then
        raise exception 'acl_can_edit %: % (esperado Not Allowed)', p_label, sqlerrm;
    end if;
end $$;

create function pg_temp.as_user(p_n int) returns void
language sql as $$
    select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-00000000096' || p_n, true)
$$;

select pg_temp.clean();

-- ── Fixture ──
set session_replication_role = replica;
insert into auth.users (id, email, raw_user_meta_data) values
    ('00000000-0000-4000-8000-000000000961', 'ce-a@check.homita.example', '{"name":"CE-A"}'),
    ('00000000-0000-4000-8000-000000000962', 'ce-m@check.homita.example', '{"name":"CE-M"}'),
    ('00000000-0000-4000-8000-000000000963', 'ce-e@check.homita.example', '{"name":"CE-E"}'),
    ('00000000-0000-4000-8000-000000000964', 'ce-x@check.homita.example', '{"name":"CE-X"}'),
    ('00000000-0000-4000-8000-000000000965', 'ce-y@check.homita.example', '{"name":"CE-Y"}');
insert into app_user (id, auth_uid, name, email) values
    (996001, '00000000-0000-4000-8000-000000000961', 'CE-A', 'ce-a@check.homita.example'),
    (996002, '00000000-0000-4000-8000-000000000962', 'CE-M', 'ce-m@check.homita.example'),
    (996003, '00000000-0000-4000-8000-000000000963', 'CE-E', 'ce-e@check.homita.example'),
    (996004, '00000000-0000-4000-8000-000000000964', 'CE-X', 'ce-x@check.homita.example'),
    (996005, '00000000-0000-4000-8000-000000000965', 'CE-Y', 'ce-y@check.homita.example');
set session_replication_role = default;

begin;
insert into home (id, name, status, is_personal, created_by) values
    (996001, 'CE-Hogar H', 'active', false, 996001),
    (996002, 'CE-Hogar B', 'active', false, 996005);
insert into home_membership (id, home_id, app_user_id, role) values
    (996001, 996001, 996001, 'admin'),
    (996002, 996001, 996002, 'member'),
    (996003, 996001, 996003, 'member'),
    (996004, 996001, 996004, 'member'),
    (996005, 996002, 996005, 'admin');
update app_user set default_home_id = 996001 where id between 996001 and 996004;
update app_user set default_home_id = 996002 where id = 996005;
commit;
select fn_seed_kind_permissions(996002, 'adult');
select fn_seed_kind_permissions(996003, 'adult');
select fn_seed_kind_permissions(996004, 'adult');

begin;
insert into calendar (id, name, color, token, home_id) values
    (996001, 'CE-C', '#111111', 'ce-tok-1', 996001);
insert into calendar_user (calendar_id, user_id, role, widget, dashboard, home_id, can_edit) values
    (996001, 996001, 'owner', true, true, 996001, false),
    (996001, 996002, 'viewer', true, true, 996001, false),
    (996001, 996003, 'viewer', true, true, 996001, true);
insert into task_list (id, name, color, token, sort, home_id) values
    (996001, 'CE-L', '#222222', 'ce-tok-2', 'custom', 996001);
insert into task_list_user (task_list_id, user_id, role, widget, dashboard, home_id, can_edit) values
    (996001, 996001, 'owner', true, true, 996001, false),
    (996001, 996002, 'viewer', true, true, 996001, false),
    (996001, 996003, 'viewer', true, true, 996001, true);
insert into event (id, calendar_id, title, date_at) values
    (996001, 996001, 'CE-Ev', '2026-12-01 10:00:00');
insert into routine (id, calendar_id, title, frequency, "interval", days, time, start_date, end_date,
                     active, available_from) values
    (996001, 996001, 'CE-Rutina', 'weekly', 1, '[1,3]'::jsonb, '09:30', '2026-11-01', null,
     true, '2026-11-01 00:00:00');
insert into task (id, task_list_id, title, "order") values
    (996001, 996001, 'CE-Tarea', 1),
    (996002, 996001, 'CE-Tarea2', 2);
commit;

-- ── K1: lectura (M) ──
do $$
begin
    perform pg_temp.as_user(2);
    perform pg_temp.denied('K1 create_event', $q$select create_event(996001, 'X', '2026-12-05 10:00:00', null, null)$q$);
    perform pg_temp.denied('K1 update_event', $q$select update_event(996001, 'X', '2026-12-01 10:00:00', null, null, 'UTC')$q$);
    perform pg_temp.denied('K1 delete_event', $q$select delete_event(996001, 'UTC')$q$);
    perform pg_temp.denied('K1 create_routine', $q$select create_routine(996001, 'X', 'weekly', 1, '[1]'::jsonb, '09:00', '2026-11-01', null, true, null, null, 'UTC')$q$);
    perform pg_temp.denied('K1 update_routine', $q$select update_routine(996001, 'X', 'weekly', 1, '[1]'::jsonb, '09:00', '2026-11-01', null, true, null, 'UTC')$q$);
    perform pg_temp.denied('K1 delete_routine', $q$select delete_routine(996001, 'UTC')$q$);
    perform pg_temp.denied('K1 materialize_routine', $q$select materialize_routine(996001, 'UTC', true)$q$);
    perform pg_temp.denied('K1 create_task', $q$select create_task(996001, 'X')$q$);
    perform pg_temp.denied('K1 update_task', $q$select update_task(996001, 'X')$q$);
    perform pg_temp.denied('K1 complete_task', $q$select complete_task(996001, true)$q$);
    perform pg_temp.denied('K1 task_order', $q$select task_order(996001, 2)$q$);
    perform pg_temp.denied('K1 delete_task', $q$select delete_task(996001)$q$);
    perform pg_temp.denied('K1 rename calendar', $q$select update_calendar(996001, 'CE-C X', '#111111', true, true)$q$);
    perform pg_temp.denied('K1 rename list', $q$select update_task_list(996001, 'CE-L X', '#222222', 'custom', true, true)$q$);
    -- Lo personal no entra en el tope: flags propios, alarma propia, materializar sin reconciliar.
    perform update_calendar(996001, 'CE-C', '#111111', false, true);
    perform update_task_list(996001, 'CE-L', '#222222', 'custom', false, true);
    perform set_event_alarm(996001, 15, 'UTC');
    perform materialize_routine(996001, 'UTC', false);
    if (select widget from calendar_user where calendar_id = 996001 and user_id = 996002) then
        raise exception 'acl_can_edit K1: el flag propio no se guardó';
    end if;
    raise notice 'ok K1: lectura → 42501 en 12 RPC de contenido y en metadatos; flags y alarma propios ok';
end $$;

-- ── K2: edición (E) ──
do $$
declare
    v json;
    v_id bigint;
begin
    perform pg_temp.as_user(3);
    v := create_event(996001, 'CE-Nuevo', '2026-12-06 10:00:00', null, null);
    v_id := (v->>'id')::bigint;
    perform update_event(v_id, 'CE-Nuevo2', '2026-12-06 11:00:00', null, null, 'UTC');
    perform delete_event(v_id, 'UTC');
    v := create_task(996001, 'CE-T3');
    v_id := (v->>'id')::bigint;
    perform update_task(v_id, 'CE-T3b');
    perform complete_task(v_id, true);
    perform task_order(996001, 2);
    perform delete_task(v_id);
    perform materialize_routine(996001, 'UTC', true);
    perform update_calendar(996001, 'CE-C ren', '#123456', true, true);
    perform update_task_list(996001, 'CE-L ren', '#654321', 'custom', true, true);
    if (select name from calendar where id = 996001) <> 'CE-C ren'
       or (select name from task_list where id = 996001) <> 'CE-L ren' then
        raise exception 'acl_can_edit K2: el editor no pudo renombrar';
    end if;
    perform pg_temp.denied('K2 delete_calendar', $q$select delete_calendar(996001)$q$);
    perform pg_temp.denied('K2 delete_task_list', $q$select delete_task_list(996001)$q$);
    perform pg_temp.denied('K2 add_calendar_user', $q$select add_calendar_user(996001, 'ce-x@check.homita.example')$q$);
    perform pg_temp.denied('K2 remove_calendar_user', $q$select remove_calendar_user(996001, 996002)$q$);
    raise notice 'ok K2: edición crea/edita/completa/ordena/borra y renombra; borrar recurso y usuarios → 42501';
end $$;

-- ── K3: el owner cambia el permiso de M ──
do $$
declare
    v json;
begin
    perform pg_temp.as_user(1);
    v := set_calendar_user_access(996001, 996002, true);
    if (v->>'can_edit')::boolean is not true or v->>'role' <> 'viewer' then
        raise exception 'acl_can_edit K3: respuesta inesperada %', v;
    end if;
    perform set_task_list_user_access(996001, 996002, true);
    perform pg_temp.as_user(2);
    perform create_event(996001, 'CE-M', '2026-12-07 10:00:00', null, null);
    perform create_task(996001, 'CE-M');
    perform pg_temp.as_user(1);
    perform set_calendar_user_access(996001, 996002, false);
    perform set_task_list_user_access(996001, 996002, false);
    perform pg_temp.as_user(2);
    perform pg_temp.denied('K3 vuelta a lectura (evento)', $q$select create_event(996001, 'X', '2026-12-05 10:00:00', null, null)$q$);
    perform pg_temp.denied('K3 vuelta a lectura (tarea)', $q$select create_task(996001, 'X')$q$);
    if (select can_edit from calendar_user where calendar_id = 996001 and user_id = 996002)
       or (select can_edit from task_list_user where task_list_id = 996001 and user_id = 996002) then
        raise exception 'acl_can_edit K3: can_edit no persistió en false';
    end if;
    raise notice 'ok K3: owner pasa a M de lectura a edición y vuelta; persiste y se aplica';
end $$;

-- ── K4: quién no puede cambiar permisos ──
do $$
begin
    perform pg_temp.as_user(3);
    perform pg_temp.denied('K4 no-owner calendario', $q$select set_calendar_user_access(996001, 996002, true)$q$);
    perform pg_temp.denied('K4 no-owner lista', $q$select set_task_list_user_access(996001, 996002, true)$q$);
    perform pg_temp.as_user(1);
    perform pg_temp.denied('K4 propia fila', $q$select set_calendar_user_access(996001, 996001, false)$q$);
    perform pg_temp.denied('K4 otro hogar', $q$select set_calendar_user_access(996001, 996005, true)$q$);
    perform pg_temp.denied('K4 otro hogar (lista)', $q$select set_task_list_user_access(996001, 996005, true)$q$);
    -- Otro owner: E pasa a owner a mano y A no puede cambiarle el permiso.
    update calendar_user set role = 'owner' where calendar_id = 996001 and user_id = 996003;
    perform pg_temp.denied('K4 otro owner', $q$select set_calendar_user_access(996001, 996003, false)$q$);
    update calendar_user set role = 'viewer' where calendar_id = 996001 and user_id = 996003;
    if has_function_privilege('anon', 'set_calendar_user_access(bigint, bigint, boolean)', 'execute')
       or has_function_privilege('anon', 'set_task_list_user_access(bigint, bigint, boolean)', 'execute')
       or not has_function_privilege('authenticated', 'set_calendar_user_access(bigint, bigint, boolean)', 'execute')
       or has_function_privilege('authenticated', 'fn_calendar_editable(bigint)', 'execute')
       or has_function_privilege('authenticated', 'fn_task_list_editable(bigint)', 'execute') then
        raise exception 'acl_can_edit K4: grants inesperados';
    end if;
    raise notice 'ok K4: no-owner, propia fila, otro owner y otro hogar → 42501; grants correctos';
end $$;

-- ── K5: compartir con una cuenta del hogar que no estaba en el ACL ──
do $$
declare
    v json;
begin
    perform pg_temp.as_user(1);
    v := set_calendar_user_access(996001, 996004, true);
    perform set_task_list_user_access(996001, 996004, false);
    if not exists (select 1 from calendar_user where calendar_id = 996001 and user_id = 996004
                   and role = 'viewer' and can_edit and home_id = 996001)
       or not exists (select 1 from task_list_user where task_list_id = 996001 and user_id = 996004
                      and role = 'viewer' and not can_edit and home_id = 996001) then
        raise exception 'acl_can_edit K5: filas de X no creadas como se esperaba';
    end if;
    perform pg_temp.as_user(4);
    perform create_event(996001, 'CE-X', '2026-12-08 10:00:00', null, null);
    perform pg_temp.denied('K5 X lectura en la lista', $q$select create_task(996001, 'X')$q$);
    raise notice 'ok K5: compartir sin email agrega a X con el permiso pedido';
end $$;

-- ── K6: lecturas exponen can_edit ──
do $$
declare
    v jsonb;
begin
    perform pg_temp.as_user(1);
    v := get_calendar_users(996001)::jsonb;
    if (select (e->>'can_edit')::boolean from jsonb_array_elements(v) e where (e->>'user_id')::bigint = 996001) is not true
       or (select (e->>'can_edit')::boolean from jsonb_array_elements(v) e where (e->>'user_id')::bigint = 996002) is not false
       or (select (e->>'can_edit')::boolean from jsonb_array_elements(v) e where (e->>'user_id')::bigint = 996003) is not true then
        raise exception 'acl_can_edit K6: get_calendar_users %', v;
    end if;
    v := get_task_list_users(996001)::jsonb;
    if (select (e->>'can_edit')::boolean from jsonb_array_elements(v) e where (e->>'user_id')::bigint = 996004) is not false then
        raise exception 'acl_can_edit K6: get_task_list_users %', v;
    end if;
    perform pg_temp.as_user(2);
    if (select (e->>'can_edit')::boolean from jsonb_array_elements(get_calendars()::jsonb) e
        where (e->>'id')::bigint = 996001) is not false
       or (select (e->>'can_edit')::boolean from jsonb_array_elements(get_task_lists()::jsonb) e
           where (e->>'id')::bigint = 996001) is not false then
        raise exception 'acl_can_edit K6: M debería ver can_edit=false';
    end if;
    perform pg_temp.as_user(3);
    if (select (e->>'can_edit')::boolean from jsonb_array_elements(get_calendars()::jsonb) e
        where (e->>'id')::bigint = 996001) is not true then
        raise exception 'acl_can_edit K6: E debería ver can_edit=true';
    end if;
    raise notice 'ok K6: get_*_users y get_calendars/get_task_lists exponen can_edit efectivo';
end $$;

-- ── K7: invitar por email entra en lectura ──
do $$
begin
    perform pg_temp.as_user(1);
    delete from calendar_user where calendar_id = 996001 and user_id = 996004;
    perform add_calendar_user(996001, 'ce-x@check.homita.example');
    if (select can_edit from calendar_user where calendar_id = 996001 and user_id = 996004) then
        raise exception 'acl_can_edit K7: alta por email con can_edit=true';
    end if;
    raise notice 'ok K7: add_calendar_user nuevo entra en lectura';
end $$;

-- ── K8: limpieza ──
select pg_temp.clean();
do $$
begin
    if exists (select 1 from app_user where id between 996001 and 996005)
       or exists (select 1 from calendar where id = 996001) or exists (select 1 from home where id in (996001, 996002)) then
        raise exception 'acl_can_edit K8: quedaron filas scratch';
    end if;
    raise notice 'ok K8: 0 filas scratch';
end $$;
