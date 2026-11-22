-- task_hidden_check.sql — Ocultar completadas a los 3 días (0039_task_hidden_at.sql, change
-- ocultar-completadas-3-dias, D-025). Solo BD local, tras el reset 0001–0039:
--   psql -v ON_ERROR_STOP=1 -f task_hidden_check.sql
-- Cada bloque DO emite 'ok Hn: …' o aborta con 'task_hidden Hn: …'.
--
-- Fixture (ids 9991xx, auth_uid …1001/…1002): hogar H con A admin, owner de la lista L (orden custom,
-- widget y dashboard); hogar H2 con B admin, sin acceso a L (no miembro). Las tareas se insertan por
-- SQL con completed_at retrocedido y hidden_at con la fórmula (el CHECK la exige).
--
-- H1 columna task.hidden_at timestamptz nullable sin default; CHECK task_hidden_at_consistent validado.
-- H2 tarea nueva (create_task) y descompletada con hidden_at null.
-- H3 completada a −3 d −1 min fuera de get_tasks: sin filtro, con p_task_list_id, con p_dashboard, con
--    p_priority y con p_sort = 'priority' (las visibles de la fixture sí salen).
-- H4 completada a −2 d 23 h visible en get_tasks y en get_task_detail.
-- H5 complete_task(true) fija hidden_at con la fórmula; re-completar recalcula completed_at y hidden_at.
-- H6 complete_task true/false, update_task (con y sin p_priority), task_order y delete_task sobre una
--    oculta → 'Not Found' P0002 y la fila queda idéntica (md5 de la fila).
-- H7 get_task_detail de una oculta (miembro) → 'Not Found' P0002, el mismo error que una inexistente.
-- H8 un no miembro recibe 'Not Found' sobre una oculta y sobre una visible (sin oráculo).
-- H9 task_order y fn_reorder_tasks numeran 1..n las visibles y no cambian el "order" de la oculta.
-- H10 con TimeZone Europe/Madrid, la fórmula da 72 h exactas a ±1 h de los cambios de hora y el CHECK
--     acepta las filas; complete_task con esa zona cumple el CHECK.
-- H11 (A7) en public solo complete_task asigna hidden_at; las que lo leen son las 7 de 0039; ninguna
--     función se llama %restore%, %unhide% ni %recover%.
-- H12 policy task_select con el predicado visible: por PostgREST (rol authenticated) A no lee la oculta.
-- Al final, 0 filas scratch.

\set ON_ERROR_STOP 1
do $$
begin
    if inet_server_addr() is not null and host(inet_server_addr()) not in ('127.0.0.1', '::1') then
        raise exception 'task_hidden_check: solo BD local (socket o loopback); servidor %', host(inet_server_addr());
    end if;
    if not exists (select 1 from information_schema.columns
                   where table_schema = 'public' and table_name = 'task' and column_name = 'hidden_at') then
        raise exception 'task_hidden_check: 0039 no está aplicada (falta task.hidden_at)';
    end if;
end $$;

create function pg_temp.clean() returns void
language plpgsql as $$
begin
    set local session_replication_role = replica;
    delete from client_request where app_user_id in (999101, 999102);
    delete from task_person where task_id in (select t.id from task t join task_list tl on tl.id = t.task_list_id
                                              where tl.home_id in (999101, 999102));
    delete from task where task_list_id in (select id from task_list where home_id in (999101, 999102));
    delete from task_list_user where task_list_id in (select id from task_list where home_id in (999101, 999102));
    delete from task_list where home_id in (999101, 999102);
    delete from membership_permission where home_membership_id in (999101, 999102);
    delete from home_membership where home_id in (999101, 999102);
    delete from audit_log where home_id in (999101, 999102);
    update app_user set default_home_id = null where id in (999101, 999102);
    delete from home where id in (999101, 999102);
    delete from app_user where id in (999101, 999102);
    delete from auth.users where id in ('00000000-0000-4000-8000-000000001001', '00000000-0000-4000-8000-000000001002');
end $$;

-- Ejecuta p_sql y exige el error p_msg (sqlstate p_state).
create function pg_temp.fails(p_label text, p_sql text, p_state text, p_msg text) returns void
language plpgsql as $$
begin
    execute p_sql;
    raise exception 'task_hidden %: no falló: %', p_label, p_sql;
exception when others then
    if sqlstate <> p_state or sqlerrm <> p_msg then
        raise exception 'task_hidden %: % % (esperado % %)', p_label, sqlstate, sqlerrm, p_state, p_msg;
    end if;
end $$;

create function pg_temp.as_a() returns void
language sql as $$
    select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000001001', true)
$$;

create function pg_temp.as_b() returns void
language sql as $$
    select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000001002', true)
$$;

-- md5 de la fila completa (incluye hidden_at, completed_at, updated_at, "order", priority).
create function pg_temp.row_md5(p_id bigint) returns text
language sql as $$
    select md5(t::text) from task t where t.id = p_id
$$;

-- ids de get_tasks como array.
create function pg_temp.ids(p json) returns bigint[]
language sql as $$
    select coalesce(array_agg((e->>'id')::bigint order by ord), array[]::bigint[])
    from json_array_elements(p) with ordinality as x(e, ord)
$$;

select pg_temp.clean();

-- ── Fixture ──
set session_replication_role = replica;
insert into auth.users (id, email, raw_user_meta_data) values
    ('00000000-0000-4000-8000-000000001001', 'th-a@check.homita.example', '{"name":"TH-A"}'),
    ('00000000-0000-4000-8000-000000001002', 'th-b@check.homita.example', '{"name":"TH-B"}');
insert into app_user (id, auth_uid, name, email) values
    (999101, '00000000-0000-4000-8000-000000001001', 'TH-A', 'th-a@check.homita.example'),
    (999102, '00000000-0000-4000-8000-000000001002', 'TH-B', 'th-b@check.homita.example');
set session_replication_role = default;

begin;
insert into home (id, name, status, is_personal, created_by) values
    (999101, 'TH-Hogar H', 'active', false, 999101),
    (999102, 'TH-Hogar H2', 'active', false, 999102);
insert into home_membership (id, home_id, app_user_id, role) values
    (999101, 999101, 999101, 'admin'),
    (999102, 999102, 999102, 'admin');
update app_user set default_home_id = 999101 where id = 999101;
update app_user set default_home_id = 999102 where id = 999102;
insert into task_list (id, name, color, token, sort, home_id) values (999101, 'TH-L', '#222222', 'th-tok-1', 'custom', 999101);
insert into task_list_user (task_list_id, user_id, role, widget, dashboard, home_id) values (999101, 999101, 'owner', true, true, 999101);
-- 999101 oculta (−3 d −1 min, alta, order 50); 999102 reciente (−2 d 23 h); 999103..999105 pendientes.
insert into task (id, task_list_id, title, completed_at, hidden_at, "order", priority) values
    (999101, 999101, 'TH-Oculta',
     (now() at time zone 'UTC') - interval '3 days 1 minute',
     (((now() at time zone 'UTC') - interval '3 days 1 minute') + interval '3 days') at time zone 'UTC', 50, 'alta'),
    (999102, 999101, 'TH-Reciente',
     (now() at time zone 'UTC') - interval '2 days 23 hours',
     (((now() at time zone 'UTC') - interval '2 days 23 hours') + interval '3 days') at time zone 'UTC', 1, 'alta'),
    (999103, 999101, 'TH-P1', null, null, 2, 'media'),
    (999104, 999101, 'TH-P2', null, null, 3, 'baja'),
    (999105, 999101, 'TH-P3', null, null, 4, 'alta');
commit;

-- ── H1: columna y CHECK ──
do $$
begin
    if not exists (
        select 1 from information_schema.columns
        where table_schema = 'public' and table_name = 'task' and column_name = 'hidden_at'
          and data_type = 'timestamp with time zone' and is_nullable = 'YES' and column_default is null
    ) then
        raise exception 'task_hidden H1: task.hidden_at no es timestamptz nullable sin default';
    end if;
    if not exists (
        select 1 from pg_constraint
        where conrelid = 'public.task'::regclass and conname = 'task_hidden_at_consistent' and contype = 'c'
          and convalidated
    ) then
        raise exception 'task_hidden H1: falta task_hidden_at_consistent validado';
    end if;
    perform pg_temp.fails('H1 CHECK pendiente con hidden_at',
        $q$insert into task (task_list_id, title, hidden_at) values (999101, 'TH-X', now())$q$,
        '23514', 'new row for relation "task" violates check constraint "task_hidden_at_consistent"');
    perform pg_temp.fails('H1 CHECK completada sin hidden_at',
        $q$insert into task (task_list_id, title, completed_at) values (999101, 'TH-X', now() at time zone 'UTC')$q$,
        '23514', 'new row for relation "task" violates check constraint "task_hidden_at_consistent"');
    raise notice 'ok H1: task.hidden_at timestamptz nullable sin default; CHECK task_hidden_at_consistent validado';
end $$;

-- ── H2: nueva y descompletada → null ──
do $$
declare
    v json;
    v_id bigint;
begin
    perform pg_temp.as_a();
    v := create_task(999101, 'TH-Nueva');
    v_id := (v->>'id')::bigint;
    if (select hidden_at from task where id = v_id) is not null then
        raise exception 'task_hidden H2: tarea nueva con hidden_at';
    end if;
    perform complete_task(v_id, true);
    perform complete_task(v_id, false);
    if (select row(completed_at, hidden_at)::text from task where id = v_id) <> '(,)' then
        raise exception 'task_hidden H2: descompletada con completed_at/hidden_at no nulos';
    end if;
    delete from task where id = v_id;
    raise notice 'ok H2: tarea nueva y descompletada con hidden_at null';
end $$;

-- ── H3: oculta fuera de get_tasks ──
do $$
declare
    v_call text;
    v_ids bigint[];
begin
    perform pg_temp.as_a();
    foreach v_call in array array[
        'get_tasks()',
        'get_tasks(p_task_list_id => 999101)',
        'get_tasks(p_dashboard => true)',
        'get_tasks(p_priority => ''alta'')',
        'get_tasks(p_sort => ''priority'')',
        'get_tasks(p_task_list_id => 999101, p_priority => ''alta'', p_sort => ''priority'')'
    ] loop
        execute format('select pg_temp.ids(%s)', v_call) into v_ids;
        if 999101 = any (v_ids) then
            raise exception 'task_hidden H3: % devuelve la oculta (%)', v_call, v_ids;
        end if;
        if not (999102 = any (v_ids)) then
            raise exception 'task_hidden H3: % no devuelve la reciente (%)', v_call, v_ids;
        end if;
    end loop;
    raise notice 'ok H3: completada a −3 d −1 min fuera de get_tasks (sin filtro, lista, dashboard, prioridad y sort)';
end $$;

-- ── H4: reciente visible ──
do $$
declare
    v json;
begin
    perform pg_temp.as_a();
    if not (999102 = any (pg_temp.ids(get_tasks(p_task_list_id => 999101)))) then
        raise exception 'task_hidden H4: la reciente no sale en get_tasks';
    end if;
    v := get_task_detail(999102);
    if (v->>'id')::bigint <> 999102 or v->>'completed_at' is null or v::jsonb ? 'hidden_at' then
        raise exception 'task_hidden H4: detail de la reciente %', v;
    end if;
    raise notice 'ok H4: completada a −2 d 23 h visible en get_tasks y get_task_detail (sin clave hidden_at)';
end $$;

-- ── H5: complete fija la fórmula; re-completar recalcula ──
do $$
declare
    v_c timestamp;
    v_h timestamptz;
begin
    perform pg_temp.as_a();
    perform complete_task(999103, true);
    select completed_at, hidden_at into v_c, v_h from task where id = 999103;
    if v_c is null or v_h is distinct from (v_c + interval '3 days') at time zone 'UTC'
       or v_c <> (now() at time zone 'UTC') then
        raise exception 'task_hidden H5: complete % / %', v_c, v_h;
    end if;
    -- Se retrocede a −1 d (coherente con el CHECK) y se re-completa.
    update task set completed_at = completed_at - interval '1 day',
                    hidden_at = ((completed_at - interval '1 day') + interval '3 days') at time zone 'UTC'
    where id = 999103;
    perform complete_task(999103, true);
    select completed_at, hidden_at into v_c, v_h from task where id = 999103;
    if v_c <> (now() at time zone 'UTC') or v_h is distinct from (v_c + interval '3 days') at time zone 'UTC' then
        raise exception 'task_hidden H5: re-completar no recalculó % / %', v_c, v_h;
    end if;
    perform complete_task(999103, false);
    raise notice 'ok H5: complete_task(true) fija hidden_at = completed_at + 3 d (UTC) y re-completar lo recalcula';
end $$;

-- ── H6: escrituras sobre la oculta → Not Found, fila intacta ──
do $$
declare
    v_md5 text := pg_temp.row_md5(999101);
begin
    perform pg_temp.as_a();
    perform pg_temp.fails('H6 complete false', 'select complete_task(999101, false)', 'P0002', 'Not Found');
    perform pg_temp.fails('H6 complete true', 'select complete_task(999101, true)', 'P0002', 'Not Found');
    perform pg_temp.fails('H6 update', $q$select update_task(999101, 'TH-Cambio')$q$, 'P0002', 'Not Found');
    perform pg_temp.fails('H6 update prioridad', $q$select update_task(999101, 'TH-Cambio', null, 'baja')$q$, 'P0002', 'Not Found');
    perform pg_temp.fails('H6 order', 'select task_order(999101, 0)', 'P0002', 'Not Found');
    perform pg_temp.fails('H6 delete', 'select delete_task(999101)', 'P0002', 'Not Found');
    if pg_temp.row_md5(999101) is distinct from v_md5 then
        raise exception 'task_hidden H6: la fila oculta cambió';
    end if;
    raise notice 'ok H6: complete true/false, update (con y sin prioridad), order y delete sobre una oculta → Not Found P0002, fila idéntica';
end $$;

-- ── H7: detail de una oculta = inexistente ──
do $$
begin
    perform pg_temp.as_a();
    perform pg_temp.fails('H7 detail oculta', 'select get_task_detail(999101)', 'P0002', 'Not Found');
    perform pg_temp.fails('H7 detail inexistente', 'select get_task_detail(999199)', 'P0002', 'Not Found');
    raise notice 'ok H7: get_task_detail de una oculta → Not Found P0002, igual que una inexistente';
end $$;

-- ── H8: no miembro ──
do $$
declare
    v_md5 text := pg_temp.row_md5(999101);
    v_id bigint;
begin
    perform pg_temp.as_b();
    foreach v_id in array array[999101, 999104] loop
        perform pg_temp.fails('H8 detail ' || v_id, format('select get_task_detail(%s)', v_id), 'P0002', 'Not Found');
        perform pg_temp.fails('H8 complete ' || v_id, format('select complete_task(%s, true)', v_id), 'P0002', 'Not Found');
        perform pg_temp.fails('H8 update ' || v_id, format($q$select update_task(%s, 'TH-B')$q$, v_id), 'P0002', 'Not Found');
        perform pg_temp.fails('H8 order ' || v_id, format('select task_order(%s, 0)', v_id), 'P0002', 'Not Found');
        perform pg_temp.fails('H8 delete ' || v_id, format('select delete_task(%s)', v_id), 'P0002', 'Not Found');
    end loop;
    if 999101 = any (pg_temp.ids(get_tasks())) or 999104 = any (pg_temp.ids(get_tasks())) then
        raise exception 'task_hidden H8: B ve tareas de L';
    end if;
    if pg_temp.row_md5(999101) is distinct from v_md5 then
        raise exception 'task_hidden H8: la fila oculta cambió';
    end if;
    raise notice 'ok H8: un no miembro recibe Not Found sobre una oculta y sobre una visible (sin oráculo)';
end $$;

-- ── H9: orden solo sobre visibles ──
do $$
declare
    v_visible bigint[];
begin
    perform pg_temp.as_a();
    perform task_order(999105, 0);
    select array_agg(id order by "order", id) into v_visible
      from task where task_list_id = 999101 and id <> 999101;
    if (select "order" from task where id = 999101) <> 50 then
        raise exception 'task_hidden H9: task_order cambió el order de la oculta';
    end if;
    if (select array_agg("order" order by "order") from task where task_list_id = 999101 and id <> 999101)
       is distinct from array[1, 2, 3, 4] or v_visible[1] <> 999105 then
        raise exception 'task_hidden H9: task_order no numeró 1..n las visibles (%)', v_visible;
    end if;
    perform fn_reorder_tasks(999101);
    if (select "order" from task where id = 999101) <> 50 then
        raise exception 'task_hidden H9: fn_reorder_tasks cambió el order de la oculta';
    end if;
    if (select array_agg("order" order by "order") from task where task_list_id = 999101 and id <> 999101)
       is distinct from array[1, 2, 3, 4] then
        raise exception 'task_hidden H9: fn_reorder_tasks no numeró 1..n las visibles';
    end if;
    raise notice 'ok H9: task_order y fn_reorder_tasks numeran 1..n las visibles y no tocan el order de la oculta';
end $$;

-- ── H10: zona horaria y cambios de hora ──
do $$
declare
    v_c timestamp;
    v_h timestamptz;
    v_id bigint := 999110;
begin
    perform set_config('timezone', 'Europe/Madrid', true);
    -- Cambios de hora UE 2026: 29-mar 01:00 UTC y 25-oct 01:00 UTC. completed_at a ±1 h de las 3 d previas
    -- (la suma cruza el cambio) y a ±1 h del propio cambio.
    foreach v_c in array array[
        '2026-03-26 00:00', '2026-03-26 02:00', '2026-03-29 00:00', '2026-03-29 02:00',
        '2026-10-22 00:00', '2026-10-22 02:00', '2026-10-25 00:00', '2026-10-25 02:00'
    ]::timestamp[] loop
        v_h := (v_c + interval '3 days') at time zone 'UTC';
        if extract(epoch from v_h - (v_c at time zone 'UTC')) <> 259200 then
            raise exception 'task_hidden H10: % → % no son 72 h', v_c, v_h;
        end if;
        insert into task (id, task_list_id, title, completed_at, hidden_at)
        values (v_id, 999101, 'TH-DST', v_c, (v_c + interval '3 days') at time zone 'UTC');
        v_id := v_id + 1;
    end loop;
    perform pg_temp.as_a();
    perform complete_task(999104, true);
    perform complete_task(999104, false);
    delete from task where id between 999110 and 999117;
    raise notice 'ok H10: con TimeZone Europe/Madrid la fórmula da 72 h a ±1 h de los cambios de hora y el CHECK acepta';
end $$;

-- ── H11: A7, sin restauración ──
do $$
declare
    v_writers text[];
    v_readers text[];
    v_restore text[];
begin
    select array_agg(proname::text order by proname) into v_writers
      from pg_proc where pronamespace = 'public'::regnamespace and prosrc ~ '\mhidden_at\s*=';
    if v_writers is distinct from array['complete_task'] then
        raise exception 'task_hidden H11: asignan hidden_at %', v_writers;
    end if;
    select array_agg(proname::text order by proname) into v_readers
      from pg_proc where pronamespace = 'public'::regnamespace and prosrc like '%hidden_at%';
    if v_readers is distinct from array['complete_task', 'delete_task', 'fn_reorder_tasks', 'get_task_detail',
                                        'get_tasks', 'task_order', 'update_task'] then
        raise exception 'task_hidden H11: usan hidden_at %', v_readers;
    end if;
    select array_agg(proname::text) into v_restore
      from pg_proc where pronamespace = 'public'::regnamespace
       and (proname ilike '%restore%' or proname ilike '%unhide%' or proname ilike '%recover%');
    if v_restore is not null then
        raise exception 'task_hidden H11: funciones de restauración %', v_restore;
    end if;
    raise notice 'ok H11: solo complete_task asigna hidden_at; lectores = las 7 de 0039; sin restore/unhide/recover';
end $$;

-- ── H12: policy task_select ──
do $$
begin
    if not exists (
        select 1 from pg_policy
        where polrelid = 'public.task'::regclass and polname = 'task_select' and polcmd = 'r'
          and pg_get_expr(polqual, polrelid) like '%fn_visible_task_list_ids%'
          and pg_get_expr(polqual, polrelid) like '%hidden_at IS NULL%hidden_at > now()%'
    ) then
        raise exception 'task_hidden H12: task_select sin el predicado visible';
    end if;
end $$;
begin;
set local role authenticated;
select pg_temp.as_a();
do $$
begin
    if exists (select 1 from task where id = 999101) then
        raise exception 'task_hidden H12: authenticated lee la oculta por la policy';
    end if;
    if not exists (select 1 from task where id = 999102) then
        raise exception 'task_hidden H12: authenticated no lee la reciente';
    end if;
    raise notice 'ok H12: policy task_select con el predicado visible (la oculta no se lee por PostgREST)';
end $$;
rollback;

-- ── Limpieza ──
select pg_temp.clean();
do $$
begin
    if exists (select 1 from app_user where id in (999101, 999102)) or exists (select 1 from home where id in (999101, 999102))
       or exists (select 1 from task_list where id = 999101) or exists (select 1 from task where id between 999101 and 999199) then
        raise exception 'task_hidden: quedaron filas scratch';
    end if;
    raise notice 'ok H-clean: 0 filas scratch';
end $$;
