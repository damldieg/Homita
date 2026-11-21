-- task_list_position_check.sql — Orden de listas de tareas (0040_task_list_position.sql, change
-- lista-prioritaria-inicio). Solo BD local, tras el reset 0001–0040:  psql -v ON_ERROR_STOP=1 -f ...
-- Cada bloque DO emite 'ok TPx: …' o aborta con 'task_list_position TPx: …'.
--
-- Fixture (ids 997xxx, auth_uid …0941–…0945): hogar H con A admin (owner de L1, L2, L3), M adult con ACL
-- de lectura en L1 y L2, E adult con ACL de edición en L1 y L2 pero sin ACL en L3, X adult sin ACL;
-- hogar B con Y admin y la lista LB.
--
-- TP1 columna integer null con check > 0; backfill (misma sentencia de 0040) por created_at, id.
-- TP2 get_task_lists: clave position y orden position, name, id (nulls last).
-- TP3 reorder feliz: posiciones 1..n, GET en ese orden, respuesta [{id,position}], updated_at intacto.
-- TP4 atómico: E con can_edit en L1 y solo lectura en L2 → Not Allowed y nada cambia; sin ACL → Not Found.
-- TP5 viewer sin can_edit (M) → Not Allowed.
-- TP6 vacío, duplicados, id inexistente y lista de otro hogar → Not Found, sin cambios.
-- TP7 miembro con can_edit pero sin 'tasklist.manage' → Not Allowed.
-- TP8 lista nueva (create_task_list) sin posición al final; anon sin EXECUTE; 0 filas scratch.

\set ON_ERROR_STOP 1
do $$
begin
    if inet_server_addr() is not null and host(inet_server_addr()) not in ('127.0.0.1', '::1') then
        raise exception 'task_list_position_check: solo BD local (socket o loopback); servidor %', host(inet_server_addr());
    end if;
    if not exists (select 1 from information_schema.columns
                    where table_schema = 'public' and table_name = 'task_list' and column_name = 'position') then
        raise exception 'task_list_position_check: 0040 no está aplicada (falta task_list.position)';
    end if;
end $$;

create function pg_temp.clean() returns void
language plpgsql as $$
begin
    set local session_replication_role = replica;
    delete from client_request where app_user_id between 997001 and 997005;
    delete from task where task_list_id in (select id from task_list where home_id in (997001, 997002));
    delete from task_list_user where task_list_id in (select id from task_list where home_id in (997001, 997002));
    delete from task_list where home_id in (997001, 997002);
    delete from person where home_id in (997001, 997002);
    delete from home_member where home_id in (997001, 997002);
    delete from membership_permission where home_membership_id between 997001 and 997005;
    delete from home_membership where home_id in (997001, 997002);
    delete from audit_log where home_id in (997001, 997002);
    update app_user set default_home_id = null where id between 997001 and 997005;
    delete from home where id in (997001, 997002);
    delete from app_user where id between 997001 and 997005;
    delete from auth.users where id in (
        '00000000-0000-4000-8000-000000000941', '00000000-0000-4000-8000-000000000942',
        '00000000-0000-4000-8000-000000000943', '00000000-0000-4000-8000-000000000944',
        '00000000-0000-4000-8000-000000000945');
end $$;

create function pg_temp.as_user(p_n int) returns void
language sql as $$
    select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-00000000094' || p_n, true)
$$;

-- Ejecuta p_sql y exige el errcode y mensaje dados.
create function pg_temp.expect_err(p_label text, p_sql text, p_state text, p_msg text) returns void
language plpgsql as $$
declare
    v_state text;
    v_text text;
begin
    execute p_sql;
    raise exception 'task_list_position %: no falló: %', p_label, p_sql;
exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_text = message_text;
    if v_state <> p_state or v_text <> p_msg then
        raise exception 'task_list_position %: % / % (esperado % / %)', p_label, v_state, v_text, p_state, p_msg;
    end if;
end $$;

-- Ids de las listas visibles del usuario actual en el orden de get_task_lists, como texto "1,2,3".
create function pg_temp.order_seen() returns text
language sql as $$
    select string_agg(((x->>'id')::bigint - 997000)::text, ',' order by ord)
      from json_array_elements(get_task_lists()) with ordinality t(x, ord)
     where (x->>'id')::bigint between 997001 and 997099
$$;

-- Posiciones guardadas de L1..L3 (y LB) como "p1,p2,p3,pB" ('-' si null).
create function pg_temp.positions() returns text
language sql as $$
    select string_agg(coalesce(position::text, '-'), ',' order by id) from task_list where id between 997001 and 997004
$$;

select pg_temp.clean();

-- ── Fixture ──
set session_replication_role = replica;
insert into auth.users (id, email, raw_user_meta_data) values
    ('00000000-0000-4000-8000-000000000941', 'tp-a@check.homita.example', '{"name":"TP-A"}'),
    ('00000000-0000-4000-8000-000000000942', 'tp-m@check.homita.example', '{"name":"TP-M"}'),
    ('00000000-0000-4000-8000-000000000943', 'tp-e@check.homita.example', '{"name":"TP-E"}'),
    ('00000000-0000-4000-8000-000000000944', 'tp-x@check.homita.example', '{"name":"TP-X"}'),
    ('00000000-0000-4000-8000-000000000945', 'tp-y@check.homita.example', '{"name":"TP-Y"}');
insert into app_user (id, auth_uid, name, email) values
    (997001, '00000000-0000-4000-8000-000000000941', 'TP-A', 'tp-a@check.homita.example'),
    (997002, '00000000-0000-4000-8000-000000000942', 'TP-M', 'tp-m@check.homita.example'),
    (997003, '00000000-0000-4000-8000-000000000943', 'TP-E', 'tp-e@check.homita.example'),
    (997004, '00000000-0000-4000-8000-000000000944', 'TP-X', 'tp-x@check.homita.example'),
    (997005, '00000000-0000-4000-8000-000000000945', 'TP-Y', 'tp-y@check.homita.example');
set session_replication_role = default;

begin;
insert into home (id, name, status, is_personal, created_by) values
    (997001, 'TP-Hogar H', 'active', false, 997001),
    (997002, 'TP-Hogar B', 'active', false, 997005);
insert into home_membership (id, home_id, app_user_id, role) values
    (997001, 997001, 997001, 'admin'),
    (997002, 997001, 997002, 'member'),
    (997003, 997001, 997003, 'member'),
    (997004, 997001, 997004, 'member'),
    (997005, 997002, 997005, 'admin');
update app_user set default_home_id = 997001 where id between 997001 and 997004;
update app_user set default_home_id = 997002 where id = 997005;
commit;
select fn_seed_kind_permissions(997002, 'adult');
select fn_seed_kind_permissions(997003, 'adult');
select fn_seed_kind_permissions(997004, 'adult');

-- Listas sin posición, con created_at distintos (L3 la más antigua) para probar el backfill.
begin;
insert into task_list (id, name, color, token, sort, home_id, created_at, updated_at) values
    (997001, 'TP-B lista', '#111111', 'tp-tok-1', 'custom', 997001, '2026-01-02 10:00:00', '2026-01-02 10:00:00'),
    (997002, 'TP-A lista', '#222222', 'tp-tok-2', 'custom', 997001, '2026-01-03 10:00:00', '2026-01-03 10:00:00'),
    (997003, 'TP-C lista', '#333333', 'tp-tok-3', 'custom', 997001, '2026-01-01 10:00:00', '2026-01-01 10:00:00'),
    (997004, 'TP-LB',      '#444444', 'tp-tok-4', 'custom', 997002, '2026-01-01 10:00:00', '2026-01-01 10:00:00');
insert into task_list_user (task_list_id, user_id, role, widget, dashboard, home_id, can_edit) values
    (997001, 997001, 'owner', true, true, 997001, false),
    (997002, 997001, 'owner', true, true, 997001, false),
    (997003, 997001, 'owner', true, true, 997001, false),
    (997001, 997002, 'viewer', true, true, 997001, false),
    (997002, 997002, 'viewer', true, true, 997001, false),
    (997001, 997003, 'viewer', true, true, 997001, true),
    (997002, 997003, 'viewer', true, true, 997001, false),
    (997004, 997005, 'owner', true, true, 997002, false);
commit;

-- ── TP1: columna, check y backfill ──
do $$
declare
    v_type text;
    v_null text;
begin
    select data_type, is_nullable into v_type, v_null from information_schema.columns
     where table_schema = 'public' and table_name = 'task_list' and column_name = 'position';
    if v_type <> 'integer' or v_null <> 'YES' then
        raise exception 'task_list_position TP1: position es % nullable=%', v_type, v_null;
    end if;
    begin
        update task_list set position = 0 where id = 997001;
        raise exception 'task_list_position TP1: el check acepta position = 0';
    exception when check_violation then null;
    end;
    -- Misma sentencia de backfill de 0040, acotada al fixture
    update task_list tl set position = r.rn
    from (select id, row_number() over (partition by home_id order by created_at, id)::integer as rn
            from task_list where home_id in (997001, 997002)) r
    where r.id = tl.id;
    if pg_temp.positions() <> '2,3,1,1' then
        raise exception 'task_list_position TP1: backfill %', pg_temp.positions();
    end if;
    raise notice 'ok TP1: integer null con check > 0; backfill por created_at, id dentro de cada hogar (2,3,1 y 1)';
end $$;

-- ── TP2: get_task_lists con position y orden ──
do $$
declare
    v json;
begin
    perform pg_temp.as_user(1);
    if pg_temp.order_seen() <> '3,1,2' then
        raise exception 'task_list_position TP2: orden %', pg_temp.order_seen();
    end if;
    select x into v from json_array_elements(get_task_lists()) x where (x->>'id')::bigint = 997003;
    if (v->>'position')::int <> 1 or not (v::jsonb ? 'can_edit') or not (v::jsonb ? 'pending_task_count') then
        raise exception 'task_list_position TP2: shape %', v;
    end if;
    -- Empates y nulls: L1 y L2 sin posición → al final por name (A lista < B lista), L3 primero
    update task_list set position = null where id in (997001, 997002);
    if pg_temp.order_seen() <> '3,2,1' then
        raise exception 'task_list_position TP2: nulls last / name %', pg_temp.order_seen();
    end if;
    select x into v from json_array_elements(get_task_lists()) x where (x->>'id')::bigint = 997001;
    if not (v::jsonb ? 'position') or (v->'position')::text <> 'null' then
        raise exception 'task_list_position TP2: position null debe salir como null: %', v;
    end if;
    update task_list set position = 1 where id in (997001, 997002, 997003); -- empate total → name, id
    if pg_temp.order_seen() <> '2,1,3' then
        raise exception 'task_list_position TP2: desempate por name %', pg_temp.order_seen();
    end if;
    update task_list set position = 3 - (id - 997001) where id in (997001, 997002, 997003); -- 3,2,1
    if pg_temp.order_seen() <> '3,2,1' then
        raise exception 'task_list_position TP2: por posición %', pg_temp.order_seen();
    end if;
    raise notice 'ok TP2: get_task_lists lleva position (int o null) y ordena por position nulls last, name, id';
end $$;

-- ── TP3: reorder feliz ──
do $$
declare
    v json;
    v_upd timestamp;
begin
    perform pg_temp.as_user(1);
    select updated_at into v_upd from task_list where id = 997001;
    v := reorder_task_lists(array[997002, 997003, 997001]::bigint[]);
    if v::jsonb <> '[{"id":997002,"position":1},{"id":997003,"position":2},{"id":997001,"position":3}]'::jsonb then
        raise exception 'task_list_position TP3: respuesta %', v;
    end if;
    if pg_temp.order_seen() <> '2,3,1' or pg_temp.positions() <> '3,1,2,1' then
        raise exception 'task_list_position TP3: orden % posiciones %', pg_temp.order_seen(), pg_temp.positions();
    end if;
    if (select updated_at from task_list where id = 997001) <> v_upd then
        raise exception 'task_list_position TP3: updated_at cambió';
    end if;
    -- un subconjunto también es válido: reescribe 1..k solo para esas listas
    perform reorder_task_lists(array[997001, 997002]::bigint[]);
    if pg_temp.positions() <> '1,2,2,1' then
        raise exception 'task_list_position TP3: subconjunto %', pg_temp.positions();
    end if;
    perform reorder_task_lists(array[997002, 997003, 997001]::bigint[]);
    raise notice 'ok TP3: reorder feliz (1..n, GET en ese orden, respuesta {id,position}, updated_at intacto)';
end $$;

-- ── TP4: atomicidad ──
do $$
begin
    perform pg_temp.as_user(3);
    -- E edita L1 pero solo lee L2 → no puede reordenar [L1, L2]; ninguna cambia
    perform pg_temp.expect_err('TP4 sin edición en L2', 'select reorder_task_lists(array[997001, 997002]::bigint[])', '42501', 'Not Allowed');
    if pg_temp.positions() <> '3,1,2,1' then
        raise exception 'task_list_position TP4: cambió algo %', pg_temp.positions();
    end if;
    -- E sin ACL en L3
    perform pg_temp.expect_err('TP4 sin ACL en L3', 'select reorder_task_lists(array[997001, 997003]::bigint[])', 'P0002', 'Not Found');
    if pg_temp.positions() <> '3,1,2,1' then
        raise exception 'task_list_position TP4: cambió algo %', pg_temp.positions();
    end if;
    -- X (sin ACL) tampoco
    perform pg_temp.as_user(4);
    perform pg_temp.expect_err('TP4 X', 'select reorder_task_lists(array[997001]::bigint[])', 'P0002', 'Not Found');
    raise notice 'ok TP4: una lista sin permiso (o sin ACL) aborta todo y nada cambia';
end $$;

-- ── TP5: viewer sin can_edit ──
do $$
begin
    perform pg_temp.as_user(2);
    perform pg_temp.expect_err('TP5 M', 'select reorder_task_lists(array[997001, 997002]::bigint[])', '42501', 'Not Allowed');
    if pg_temp.positions() <> '3,1,2,1' then
        raise exception 'task_list_position TP5: cambió algo %', pg_temp.positions();
    end if;
    raise notice 'ok TP5: viewer sin can_edit → Not Allowed';
end $$;

-- ── TP6: ids inválidos ──
do $$
begin
    perform pg_temp.as_user(1);
    perform pg_temp.expect_err('TP6 vacío', 'select reorder_task_lists(array[]::bigint[])', 'P0002', 'Not Found');
    perform pg_temp.expect_err('TP6 null', 'select reorder_task_lists(null)', 'P0002', 'Not Found');
    perform pg_temp.expect_err('TP6 duplicados', 'select reorder_task_lists(array[997001, 997001]::bigint[])', 'P0002', 'Not Found');
    perform pg_temp.expect_err('TP6 inexistente', 'select reorder_task_lists(array[997001, 999999999]::bigint[])', 'P0002', 'Not Found');
    perform pg_temp.expect_err('TP6 otro hogar', 'select reorder_task_lists(array[997001, 997004]::bigint[])', 'P0002', 'Not Found');
    -- Y (otro hogar) sobre listas de H
    perform pg_temp.as_user(5);
    perform pg_temp.expect_err('TP6 Y sobre H', 'select reorder_task_lists(array[997001, 997002]::bigint[])', 'P0002', 'Not Found');
    if pg_temp.positions() <> '3,1,2,1' then
        raise exception 'task_list_position TP6: cambió algo %', pg_temp.positions();
    end if;
    raise notice 'ok TP6: vacío, null, duplicados, inexistente, otro hogar y tenant ajeno → Not Found sin escribir';
end $$;

-- ── TP7: can_edit pero sin tasklist.manage ──
do $$
begin
    delete from membership_permission where home_membership_id = 997003 and permission_code = 'tasklist.manage';
    perform pg_temp.as_user(3);
    perform pg_temp.expect_err('TP7 E sin permiso', 'select reorder_task_lists(array[997001]::bigint[])', '42501', 'Not Allowed');
    if pg_temp.positions() <> '3,1,2,1' then
        raise exception 'task_list_position TP7: cambió algo %', pg_temp.positions();
    end if;
    insert into membership_permission (home_membership_id, permission_code) values (997003, 'tasklist.manage');
    perform pg_temp.as_user(3);
    perform reorder_task_lists(array[997001]::bigint[]);
    if (select position from task_list where id = 997001) <> 1 then
        raise exception 'task_list_position TP7: con permiso no escribió';
    end if;
    raise notice 'ok TP7: sin tasklist.manage → Not Allowed; con él, can_edit reordena';
end $$;

-- ── TP8: lista nueva al final, grants, limpieza ──
do $$
declare
    v json;
    v_new bigint;
begin
    perform pg_temp.as_user(1);
    perform reorder_task_lists(array[997003, 997002, 997001]::bigint[]);
    v := create_task_list('TP-Nueva', '#555555', 'custom', false, false);
    v_new := (v->>'id')::bigint;
    if (select position from task_list where id = v_new) is not null then
        raise exception 'task_list_position TP8: la lista nueva nace con position';
    end if;
    if (select (x->>'id')::bigint from json_array_elements(get_task_lists()) with ordinality t(x, o)
         where (x->>'home_id')::bigint = 997001 order by o desc limit 1) <> v_new then
        raise exception 'task_list_position TP8: la lista nueva no sale al final';
    end if;
    if has_function_privilege('anon', 'reorder_task_lists(bigint[])', 'execute')
       or not has_function_privilege('authenticated', 'reorder_task_lists(bigint[])', 'execute') then
        raise exception 'task_list_position TP8: grants de reorder_task_lists';
    end if;
    if (select count(*) from pg_proc where proname = 'reorder_task_lists') <> 1 then
        raise exception 'task_list_position TP8: más de una firma';
    end if;
    perform pg_temp.clean();
    if exists (select 1 from task_list where home_id in (997001, 997002)) or exists (select 1 from home where id in (997001, 997002)) then
        raise exception 'task_list_position TP8: quedan filas scratch';
    end if;
    raise notice 'ok TP8: lista nueva sin posición al final; anon sin EXECUTE, authenticated sí; 0 filas scratch';
end $$;
