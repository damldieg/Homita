-- permisos_matriz_check.sql — Matriz §3.4.1 (fase 1.8): enforcement por kind × recurso ×
-- operación sobre 0020_home_write_guards.sql. Se ejecuta con psql DESPUÉS del reset 0001–0020 y
-- la seed (E4):
--   psql -v ON_ERROR_STOP=1 -f permisos_matriz_check.sql
-- Cada bloque DO emite 'ok Mx: …' o aborta con 'permisos_matriz Mx: …'.
--
-- Casos M1–M27 del plan §6.1: M1/M1b lectura admin sin ACL (RPC y RLS directo), M2 escritura
-- admin sin ACL, M3 co-miembro no admin, M4/M5 metadatos vs flags propios, M6–M9 contenido y
-- Q-C (a) (conjunto de personas), M8b sesión de rutina (A-13), M10–M12 tareas y alarmas, M13/M14
-- compartir y self-remove/último owner, M15 materialización, M16 hogar archived, M17 personas
-- (Q2/D15), M18 personas por hogar (D4), M19/M23 fn_sync_assignments por hogar (Q-G), M20 admin
-- con snapshot vacío (A4), M21 *_user_select sin cambios, M22 fn_person_ids_array, M24/M25
-- materialización (Q-F/R1-06), M26 orden de errores, M27 persona inactiva (trigger 0015 iv).
--
-- Datos scratch 997xxx (usuarios auth_uid …0971–0976) borrados al final. Impersonación vía
-- set_config('request.jwt.claim.sub', …, true) (auth.uid()). El RLS directo (M1b/M18/M21) usa
-- set role authenticated con capturas en una tabla temporal de la sesión.

-- ── Preambulo scratch: usuarios 997001–997006 ──

set session_replication_role = replica;
insert into auth.users (id, email, raw_user_meta_data) values
    ('00000000-0000-4000-8000-000000000971', 'pm-a@check.homita.example', '{"name":"PM-A"}'),
    ('00000000-0000-4000-8000-000000000972', 'pm-m@check.homita.example', '{"name":"PM-M"}'),
    ('00000000-0000-4000-8000-000000000973', 'pm-k@check.homita.example', '{"name":"PM-K"}'),
    ('00000000-0000-4000-8000-000000000974', 'pm-r@check.homita.example', '{"name":"PM-R"}'),
    ('00000000-0000-4000-8000-000000000975', 'pm-g@check.homita.example', '{"name":"PM-G"}'),
    ('00000000-0000-4000-8000-000000000976', 'pm-x@check.homita.example', '{"name":"PM-X"}')
on conflict (id) do nothing;
insert into app_user (id, auth_uid, name, email) values
    (997001, '00000000-0000-4000-8000-000000000971', 'PM-A', 'pm-a@check.homita.example'),
    (997002, '00000000-0000-4000-8000-000000000972', 'PM-M', 'pm-m@check.homita.example'),
    (997003, '00000000-0000-4000-8000-000000000973', 'PM-K', 'pm-k@check.homita.example'),
    (997004, '00000000-0000-4000-8000-000000000974', 'PM-R', 'pm-r@check.homita.example'),
    (997005, '00000000-0000-4000-8000-000000000975', 'PM-G', 'pm-g@check.homita.example'),
    (997006, '00000000-0000-4000-8000-000000000976', 'PM-X', 'pm-x@check.homita.example')
on conflict (id) do nothing;
set session_replication_role = default;

begin;
-- Hogar H (997001) con A admin, M adult, K child, R relative, G guest; hogar B (997002) con X
-- admin; hogar archived (997003) con M. C1 de A, C2 de M (K/R viewers), C3 en el hogar archived.
insert into home (id, name, status, is_personal, created_by) values
    (997001, 'PM-Hogar H', 'active', false, 997001),
    (997002, 'PM-Hogar B', 'active', false, 997006),
    (997003, 'PM-Hogar Arch', 'archived', false, 997002);
insert into home_membership (id, home_id, app_user_id, role) values
    (997001, 997001, 997001, 'admin'),
    (997002, 997001, 997002, 'member'),
    (997003, 997001, 997003, 'member'),
    (997004, 997001, 997004, 'member'),
    (997005, 997001, 997005, 'member'),
    (997006, 997002, 997006, 'admin'),
    (997007, 997003, 997002, 'member');
update app_user set default_home_id = 997001 where id in (997001, 997002, 997003, 997004, 997005);
update app_user set default_home_id = 997002 where id = 997006;
commit;
select fn_seed_kind_permissions(997002, 'adult');
select fn_seed_kind_permissions(997003, 'child');
select fn_seed_kind_permissions(997004, 'relative');
select fn_seed_kind_permissions(997005, 'guest');
select fn_seed_kind_permissions(997007, 'adult');

begin;
insert into calendar (id, name, color, token, home_id) values
    (997001, 'PM-C1', '#111111', 'pm-token-1', 997001),
    (997002, 'PM-C2', '#222222', 'pm-token-2', 997001),
    (997003, 'PM-C3', '#333333', 'pm-token-3', 997003);
insert into calendar_user (calendar_id, user_id, role, widget, dashboard, home_id) values
    (997001, 997001, 'owner', true, true, 997001),
    (997002, 997002, 'owner', true, true, 997001),
    (997002, 997003, 'viewer', true, true, 997001),
    (997002, 997004, 'viewer', true, true, 997001),
    (997001, 997005, 'viewer', true, true, 997001),
    (997003, 997002, 'owner', true, true, 997003);
insert into task_list (id, name, color, token, sort, home_id) values
    (997001, 'PM-L1', '#444444', 'pm-token-4', 'title', 997001),
    (997002, 'PM-L2', '#555555', 'pm-token-5', 'title', 997001);
insert into task_list_user (task_list_id, user_id, role, widget, dashboard, home_id) values
    (997001, 997001, 'owner', true, true, 997001),
    (997002, 997002, 'owner', true, true, 997001),
    (997002, 997003, 'viewer', true, true, 997001),
    (997002, 997005, 'viewer', true, true, 997001);
insert into task (id, task_list_id, title) values
    (997001, 997001, 'PM-Tarea1'),
    (997002, 997002, 'PM-Tarea2');
-- 0029 (tope adicional): esta matriz prueba el catálogo por kind, así que los viewers tienen
-- permiso de edición en el ACL (equivale al backfill de 0029). Sin la columna (pre-0029), no-op.
-- El tope en sí lo prueba acl_can_edit_check.sql.
do $$
begin
    if exists (select 1 from information_schema.columns
               where table_name = 'calendar_user' and column_name = 'can_edit') then
        execute 'update calendar_user set can_edit = true where calendar_id between 997001 and 997003';
        execute 'update task_list_user set can_edit = true where task_list_id between 997001 and 997002';
    end if;
end $$;
insert into home_member (id, home_id, kind, name, color, status) values
    (997001, 997001, 'adult', 'PM-Miembro', '#AA0000', 'active'),
    (997002, 997001, 'adult', 'PM-Inactivo', '#00AA00', 'inactive'),
    (997003, 997002, 'adult', 'PM-B', '#0000AA', 'active'),
    (997004, 997001, 'adult', 'PM-Miembro2', '#CC0000', 'active');
insert into person (id, user_id, home_id, home_member_id, name, color) values
    (997001, 997002, 997001, 997001, 'PM-P_h', '#AA0000'),
    (997002, 997002, 997001, 997004, 'PM-P_h2', '#BB0000'),
    (997003, 997002, 997001, 997002, 'PM-P_i', '#00AA00'),
    (997004, 997006, 997002, 997003, 'PM-P_b', '#0000AA');
insert into event (id, calendar_id, title, date_at) values
    (997001, 997001, 'PM-Ev1', '2026-12-01 10:00:00'),
    (997002, 997002, 'PM-Ev2', '2026-12-02 10:00:00'),
    (997003, 997002, 'PM-Ev3', '2026-12-03 10:00:00');
insert into routine (id, calendar_id, title, frequency, "interval", days, time, start_date, end_date,
                     active, available_from) values
    (997001, 997002, 'PM-Rutina', 'weekly', 1, '[1,3]'::jsonb, '09:30', '2026-11-01', null,
     true, '2026-11-01 00:00:00'),
    (997002, 997002, 'PM-Rutina2', 'weekly', 1, '[2,4]'::jsonb, '10:30', '2026-11-01', null,
     true, '2026-11-01 00:00:00'),
    (997003, 997001, 'PM-Rutina3', 'weekly', 1, '[1,5]'::jsonb, '11:30', '2026-11-01', null,
     true, '2026-11-01 00:00:00');
insert into routine_person (routine_id, person_id) values (997001, 997001);
update event set routine_id = 997001, routine_date = '2026-12-03' where id = 997003;
commit;

-- ── M1: lectura admin sin ACL (RPC): A ve C2 con widget/dashboard false (A-5) ──

do $$
declare
    v json;
    v_w int;
    v_d int;
    v_own int;
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000971', true);
    v := get_calendars();
    select (e->>'widget')::int, (e->>'dashboard')::int into v_w, v_d
    from jsonb_array_elements(v::jsonb) e where (e->>'id')::bigint = 997002;
    if v_w is null or v_w <> 0 or v_d <> 0 then
        raise exception 'permisos_matriz M1: C2 sin widget/dashboard false (%, %)', v_w, v_d;
    end if;
    select (e->>'widget')::int into v_own
    from jsonb_array_elements(v::jsonb) e where (e->>'id')::bigint = 997001;
    if v_own is distinct from 1 then
        raise exception 'permisos_matriz M1: C1 (ACL propia) widget=% (esperado 1)', v_own;
    end if;
    raise notice 'ok M1: admin sin ACL ve C2 con widget=false, dashboard=false (RPC)';
end $$;

-- ── M1b: RLS directo (set role authenticated): A ve C2 y sus eventos (§3.3) ──

create temporary table pm_rls (k text primary key, v bigint);
grant select, insert, update on pm_rls to authenticated;
insert into pm_rls values ('cal_c2_a', -1), ('ev_c2_a', -1), ('ev_c2_ref', -1),
                          ('cal_c1_k', -1), ('cu_c1_k', -1), ('p_h_k', -1), ('p_h_x', -1);
update pm_rls set v = (select count(*) from event where calendar_id = 997002) where k = 'ev_c2_ref';
begin;  -- set_config(..., true) es transaccional: el claim vive hasta el commit
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000971', true);
update pm_rls set v = (select count(*) from calendar where id = 997002) where k = 'cal_c2_a';
update pm_rls set v = (select count(*) from event where calendar_id = 997002) where k = 'ev_c2_a';
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000973', true);
update pm_rls set v = (select count(*) from calendar where id = 997001) where k = 'cal_c1_k';
update pm_rls set v = (select count(*) from calendar_user where calendar_id = 997001) where k = 'cu_c1_k';
update pm_rls set v = (select count(*) from person where id = 997001) where k = 'p_h_k';
select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000976', true);
update pm_rls set v = (select count(*) from person where id = 997001) where k = 'p_h_x';
reset role;
commit;

do $$
declare
    r record;
begin
    select pm.v into r from pm_rls pm where pm.k = 'cal_c2_a';
    if r.v <> 1 then
        raise exception 'permisos_matriz M1b: calendar C2 visible para admin sin ACL = % (esperado 1)', r.v;
    end if;
    select pm.v into r from pm_rls pm where pm.k = 'ev_c2_a';
    if r.v < 1 then
        raise exception 'permisos_matriz M1b: eventos de C2 visibles = % (esperado ≥ 1)', r.v;
    end if;
    select pm.v into r from pm_rls pm where pm.k = 'ev_c2_ref';
    if r.v <> (select pm.v from pm_rls pm where pm.k = 'ev_c2_a') then
        raise exception 'permisos_matriz M1b: RLS % ≠ conteo sin RLS %', r.v,
            (select pm.v from pm_rls pm where pm.k = 'ev_c2_ref');
    end if;
    raise notice 'ok M1b: RLS directo — admin sin ACL ve C2 y todos sus eventos (antes: 0)';
end $$;

-- ── M2: escritura admin sin ACL → Not Found ──

do $$
declare
    v_ok boolean := false;
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000971', true);
    begin
        perform update_calendar(997002, 'PM-C2 X', '#222222', true, true);
        v_ok := true;
    exception when sqlstate 'P0002' then
        if sqlerrm <> 'Not Found' then
            raise exception 'permisos_matriz M2: % (esperado Not Found)', sqlerrm;
        end if;
    end;
    if v_ok then
        raise exception 'permisos_matriz M2: update_calendar de admin sin ACL no falló';
    end if;
    raise notice 'ok M2: escritura de admin sin ACL → Not Found';
end $$;

-- ── M3: co-miembro no admin sin ACL (K sobre C1) → Not Found / 0 filas ──

do $$
declare
    v_ok boolean := false;
    v json;
    v_c bigint;
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000973', true);
    begin
        v := get_calendar_users(997001);
        v_ok := true;
    exception when sqlstate 'P0002' then
        if sqlerrm <> 'Not Found' then
            raise exception 'permisos_matriz M3: % (esperado Not Found)', sqlerrm;
        end if;
    end;
    if v_ok then
        raise exception 'permisos_matriz M3: get_calendar_users de C1 no falló para K';
    end if;
    select pm.v into v_c from pm_rls pm where pm.k = 'cal_c1_k';
    if v_c <> 0 then
        raise exception 'permisos_matriz M3: RLS ve C1 = % (esperado 0)', v_c;
    end if;
    raise notice 'ok M3: co-miembro no admin sin ACL → Not Found / 0 filas';
end $$;

-- ── M4: metadatos = owner + calendar.manage (viewer 403; owner sin manage 403; adult ok) ──

do $$
declare
    v_ok boolean := false;
    v json;
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000974', true);
    begin
        perform update_calendar(997002, 'PM-C2 X', '#222222', true, true);
        v_ok := true;
    exception when sqlstate '42501' then
        if sqlerrm <> 'Not Allowed' then
            raise exception 'permisos_matriz M4 (viewer): % (esperado Not Allowed)', sqlerrm;
        end if;
    end;
    if v_ok then
        raise exception 'permisos_matriz M4: viewer pudo renombrar C2';
    end if;
    delete from membership_permission where home_membership_id = 997002
      and permission_code = 'calendar.manage';
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000972', true);
    v_ok := false;
    begin
        perform update_calendar(997002, 'PM-C2 X', '#222222', true, true);
        v_ok := true;
    exception when sqlstate '42501' then
        if sqlerrm <> 'Not Allowed' then
            raise exception 'permisos_matriz M4 (owner sin manage): % (esperado Not Allowed)', sqlerrm;
        end if;
    end;
    if v_ok then
        raise exception 'permisos_matriz M4: owner sin calendar.manage pudo renombrar';
    end if;
    perform fn_seed_kind_permissions(997002, 'adult');
    v := update_calendar(997002, 'PM-C2', '#222222', true, true);
    raise notice 'ok M4: viewer 403, owner sin manage 403, adult owner ok';
end $$;

-- ── M5: solo flags propios (widget) → ok con ACL de cualquier rol, sin permiso ni owner ──

do $$
declare
    v json;
    v_w int;
    v_other int;
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000974', true);
    v := update_calendar(997002, 'PM-C2', '#222222', false, true);
    select widget::int into v_w from calendar_user where calendar_id = 997002 and user_id = 997004;
    select widget::int into v_other from calendar_user where calendar_id = 997002 and user_id = 997002;
    if v_w <> 0 then
        raise exception 'permisos_matriz M5: widget del viewer = % (esperado 0)', v_w;
    end if;
    if v_other <> 1 then
        raise exception 'permisos_matriz M5: la fila ACL de M cambió (widget=%)', v_other;
    end if;
    raise notice 'ok M5: update_calendar solo widget por viewer → ok, solo su fila ACL';
end $$;

-- ── M6: create_event: guest sin event.create → Not Allowed; relative con event.create → ok ──

do $$
declare
    v_ok boolean := false;
    v json;
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000975', true);
    begin
        perform create_event(997001, 'PM-EvG', '2026-12-10 10:00:00', 5, null);
        v_ok := true;
    exception when sqlstate '42501' then
        if sqlerrm <> 'Not Allowed' then
            raise exception 'permisos_matriz M6 (guest): % (esperado Not Allowed)', sqlerrm;
        end if;
    end;
    if v_ok then
        raise exception 'permisos_matriz M6: guest sin event.create pudo crear evento';
    end if;
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000974', true);
    v := create_event(997002, 'PM-EvR', '2026-12-11 10:00:00', 5, null);
    if (v->>'id')::bigint is null then
        raise exception 'permisos_matriz M6: create_event de relative sin id: %', v;
    end if;
    raise notice 'ok M6: guest sin event.create 403; relative con event.create ok';
end $$;

-- ── M7: create_event con personas: relative sin event.assign → Not Allowed; adult → ok ──

do $$
declare
    v_ok boolean := false;
    v json;
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000974', true);
    begin
        perform create_event(997002, 'PM-EvP', '2026-12-12 10:00:00', 5,
                             '[997001]'::jsonb);
        v_ok := true;
    exception when sqlstate '42501' then
        if sqlerrm <> 'Not Allowed' then
            raise exception 'permisos_matriz M7 (relative): % (esperado Not Allowed)', sqlerrm;
        end if;
    end;
    if v_ok then
        raise exception 'permisos_matriz M7: relative sin event.assign pudo asignar personas';
    end if;
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000972', true);
    v := create_event(997002, 'PM-EvA', '2026-12-13 10:00:00', 5, '[997001]'::jsonb);
    if coalesce(jsonb_array_length(v::jsonb->'persons'), 0) <> 1 then
        raise exception 'permisos_matriz M7: personas de PM-EvA = % (esperado 1)', v->'persons';
    end if;
    raise notice 'ok M7: relative con personas 403; adult con event.assign ok';
end $$;

-- ── M8: update_event con el conjunto mostrado (sin cambio) → 200; quitar persona → 403 ──

do $$
declare
    v_ok boolean := false;
    v_id bigint;
    v json;
begin
    select id into v_id from event where title = 'PM-EvA';
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000974', true);
    v := fn_event_persons(v_id);
    if coalesce(jsonb_array_length(v::jsonb), 0) <> 1 then
        raise exception 'permisos_matriz M8: conjunto mostrado = % (esperado 1)', v;
    end if;
    -- reenvío del conjunto mostrado (idéntico, incluso con duplicados/orden distinto) → 200
    perform update_event(v_id, 'PM-EvA', '2026-12-13 10:00:00', 5, '[997001, 997001]'::jsonb,
                         'Europe/Madrid');
    begin
        perform update_event(v_id, 'PM-EvA', '2026-12-13 10:00:00', 5, '[]'::jsonb, 'Europe/Madrid');
        v_ok := true;
    exception when sqlstate '42501' then
        if sqlerrm <> 'Not Allowed' then
            raise exception 'permisos_matriz M8: % (esperado Not Allowed)', sqlerrm;
        end if;
    end;
    if v_ok then
        raise exception 'permisos_matriz M8: relative pudo quitar personas sin event.assign';
    end if;
    -- null = no tocar (Q-C (a)): ni permiso ni sync
    perform update_event(v_id, 'PM-EvA', '2026-12-13 10:00:00', 5, null, 'Europe/Madrid');
    raise notice 'ok M8: conjunto igual → 200 (con duplicados); cambio → 403; null → no toca';
end $$;

-- ── M8b: sesión de rutina (A-13): conjunto mostrado = routine_person; sin filas ocultas ──

do $$
declare
    v_ok boolean := false;
    v_n bigint;
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000974', true);
    -- ev3 es sesión de rutina (routine_person = {P_h}); relative reenvía {P_h} → 200 y
    -- 0 filas nuevas en event_person (no se escriben filas ocultas)
    perform update_event(997003, 'PM-Ev3', '2026-12-03 10:00:00', 5, '[997001]'::jsonb,
                         'Europe/Madrid');
    select count(*) into v_n from event_person where event_id = 997003;
    if v_n <> 0 then
        raise exception 'permisos_matriz M8b: event_person oculto escrito (% filas)', v_n;
    end if;
    begin
        perform update_event(997003, 'PM-Ev3', '2026-12-03 10:00:00', 5, '[997001, 997002]'::jsonb,
                             'Europe/Madrid');
        v_ok := true;
    exception when sqlstate '42501' then
        if sqlerrm <> 'Not Allowed' then
            raise exception 'permisos_matriz M8b: % (esperado Not Allowed)', sqlerrm;
        end if;
    end;
    if v_ok then
        raise exception 'permisos_matriz M8b: relative amplió el conjunto en sesión de rutina';
    end if;
    raise notice 'ok M8b: sesión de rutina — mismo conjunto 200 sin filas ocultas; cambio 403';
end $$;

-- ── M9: update_routine: mismo conjunto → ok; distinto → Not Allowed ──
-- DESVIACIÓN (plan §6.1 M9): el plan pide «mismo conjunto por relative → ok», pero el catálogo
-- 0019 (y diseno-home §3.4.1: update_routine exige routine.edit; relative solo tiene routine.view)
-- lo hace imposible con kinds. Se preserva la INTENCIÓN de M9 (Q-C (a), §3.2: el mismo conjunto no
-- exige routine.assign) con M adult SIN routine.assign (snapshot surgery) y se cubre el caso real
-- de relative (403). Desviación registrada en el envelope.

do $$
declare
    v_ok boolean := false;
    v json;
begin
    -- relative (sin routine.edit, 0019) → Not Allowed aunque el conjunto no cambie
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000974', true);
    begin
        perform update_routine(997001, 'PM-Rutina', 'weekly', 1, '[1, 3]'::jsonb, '09:30',
                               '2026-11-01', null, true, '[997001]'::jsonb, 'Europe/Madrid');
        v_ok := true;
    exception when sqlstate '42501' then
        if sqlerrm <> 'Not Allowed' then
            raise exception 'permisos_matriz M9 (relative): % (esperado Not Allowed)', sqlerrm;
        end if;
    end;
    if v_ok then
        raise exception 'permisos_matriz M9: relative sin routine.edit no falló';
    end if;
    -- Q-C (a): M con routine.edit pero SIN routine.assign → mismo conjunto ok; distinto 403
    delete from membership_permission where home_membership_id = 997002
      and permission_code = 'routine.assign';
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000972', true);
    perform update_routine(997001, 'PM-Rutina', 'weekly', 1, '[1, 3]'::jsonb, '09:30',
                           '2026-11-01', null, true, '[997001]'::jsonb, 'Europe/Madrid');
    v_ok := false;
    begin
        perform update_routine(997001, 'PM-Rutina', 'weekly', 1, '[1, 3]'::jsonb, '09:30',
                               '2026-11-01', null, true, '[997001, 997002]'::jsonb, 'Europe/Madrid');
        v_ok := true;
    exception when sqlstate '42501' then
        if sqlerrm <> 'Not Allowed' then
            raise exception 'permisos_matriz M9: % (esperado Not Allowed)', sqlerrm;
        end if;
    end;
    if v_ok then
        raise exception 'permisos_matriz M9: cambio de conjunto sin routine.assign no falló';
    end if;
    perform fn_seed_kind_permissions(997002, 'adult');  -- restaura el snapshot adult
    raise notice 'ok M9: relative sin routine.edit 403; sin routine.assign — mismo conjunto ok, distinto 403';
end $$;

-- ── M10: delete_event: relative → Not Allowed; guest → Not Allowed; adult → ok ──

do $$
declare
    v_ok boolean := false;
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000974', true);
    begin
        perform delete_event(997002, 'Europe/Madrid');
        v_ok := true;
    exception when sqlstate '42501' then
        if sqlerrm <> 'Not Allowed' then
            raise exception 'permisos_matriz M10 (relative): % (esperado Not Allowed)', sqlerrm;
        end if;
    end;
    if v_ok then
        raise exception 'permisos_matriz M10: relative sin event.delete pudo borrar';
    end if;
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000975', true);
    v_ok := false;
    begin
        perform delete_event(997001, 'Europe/Madrid');
        v_ok := true;
    exception when sqlstate '42501' then
        if sqlerrm <> 'Not Allowed' then
            raise exception 'permisos_matriz M10 (guest): % (esperado Not Allowed)', sqlerrm;
        end if;
    end;
    if v_ok then
        raise exception 'permisos_matriz M10: guest sin event.delete pudo borrar';
    end if;
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000972', true);
    perform delete_event(997002, 'Europe/Madrid');
    raise notice 'ok M10: relative 403, guest 403, adult ok';
end $$;

-- ── M11: tareas por kind: child crea/no borra; guest completa/no crea ──

do $$
declare
    v json;
    v_id bigint;
    v_ok boolean := false;
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000973', true);
    v := create_task(997002, 'PM-TareaK');
    v_id := (v->>'id')::bigint;
    if v_id is null then
        raise exception 'permisos_matriz M11: child sin create_task: %', v;
    end if;
    begin
        perform delete_task(v_id);
        v_ok := true;
    exception when sqlstate '42501' then
        if sqlerrm <> 'Not Allowed' then
            raise exception 'permisos_matriz M11 (child delete): % (esperado Not Allowed)', sqlerrm;
        end if;
    end;
    if v_ok then
        raise exception 'permisos_matriz M11: child sin task.delete pudo borrar';
    end if;
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000975', true);
    v_ok := false;
    begin
        perform create_task(997002, 'PM-TareaG');
        v_ok := true;
    exception when sqlstate '42501' then
        if sqlerrm <> 'Not Allowed' then
            raise exception 'permisos_matriz M11 (guest create): % (esperado Not Allowed)', sqlerrm;
        end if;
    end;
    if v_ok then
        raise exception 'permisos_matriz M11: guest sin task.create pudo crear';
    end if;
    v := complete_task(997002, true);
    if (v->>'completed_at') is null then
        raise exception 'permisos_matriz M11: guest con task.complete no completó: %', v;
    end if;
    raise notice 'ok M11: child crea/no borra; guest completa/no crea';
end $$;

-- ── M12: sin ACL → Not Found (complete_task, task_order, set_event_alarm) ──

do $$
declare
    v_ok boolean := false;
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000973', true);
    begin
        perform complete_task(997001, true);
        v_ok := true;
    exception when sqlstate 'P0002' then null;
    end;
    if v_ok then
        raise exception 'permisos_matriz M12: complete_task sin ACL no falló';
    end if;
    v_ok := false;
    begin
        perform task_order(997001, 0);
        v_ok := true;
    exception when sqlstate 'P0002' then null;
    end;
    if v_ok then
        raise exception 'permisos_matriz M12: task_order sin ACL no falló';
    end if;
    v_ok := false;
    begin
        perform set_event_alarm(997001, 5, 'Europe/Madrid');
        v_ok := true;
    exception when sqlstate 'P0002' then null;
    end;
    if v_ok then
        raise exception 'permisos_matriz M12: set_event_alarm sin ACL no falló';
    end if;
    raise notice 'ok M12: complete_task/task_order/set_event_alarm sin ACL → Not Found';
end $$;

-- ── M13: add_calendar_user: owner sin manage → 403; con manage → ok; no-miembro → 403 (Q3) ──

do $$
declare
    v_ok boolean := false;
    v json;
begin
    delete from membership_permission where home_membership_id = 997002
      and permission_code = 'calendar.manage';
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000972', true);
    begin
        perform add_calendar_user(997002, 'pm-g@check.homita.example');
        v_ok := true;
    exception when sqlstate '42501' then
        if sqlerrm <> 'Not Allowed' then
            raise exception 'permisos_matriz M13 (sin manage): % (esperado Not Allowed)', sqlerrm;
        end if;
    end;
    if v_ok then
        raise exception 'permisos_matriz M13: owner sin calendar.manage pudo compartir';
    end if;
    perform fn_seed_kind_permissions(997002, 'adult');
    v := add_calendar_user(997002, 'pm-g@check.homita.example');
    if (v->>'id')::bigint <> 997005 then
        raise exception 'permisos_matriz M13: alta de G inesperada: %', v;
    end if;
    v_ok := false;
    begin
        perform add_calendar_user(997002, 'pm-x@check.homita.example');
        v_ok := true;
    exception when sqlstate '42501' then
        if sqlerrm <> 'Not Allowed' then
            raise exception 'permisos_matriz M13 (Q3): % (esperado Not Allowed)', sqlerrm;
        end if;
    end;
    if v_ok then
        raise exception 'permisos_matriz M13: email de no-miembro del hogar no falló (Q3)';
    end if;
    raise notice 'ok M13: sin manage 403; con manage alta; no-miembro del hogar 403 (Q3)';
end $$;

-- ── M14: remove_calendar_user: último owner 403; self 400; owner con reemplazo self 400 ──

do $$
declare
    v_ok boolean := false;
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000972', true);
    begin
        perform remove_calendar_user(997002, 997002);
        v_ok := true;
    exception when sqlstate '42501' then
        if sqlerrm <> 'Not Allowed' then
            raise exception 'permisos_matriz M14 (último owner): % (esperado Not Allowed)', sqlerrm;
        end if;
    end;
    if v_ok then
        raise exception 'permisos_matriz M14: el último owner se autoretiró';
    end if;
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000974', true);
    v_ok := false;
    begin
        perform remove_calendar_user(997002, 997004);
        v_ok := true;
    exception when sqlstate 'P0001' then
        if sqlerrm <> 'User cannot remove themselves' then
            raise exception 'permisos_matriz M14 (viewer self): % (esperado User cannot remove themselves)', sqlerrm;
        end if;
    end;
    if v_ok then
        raise exception 'permisos_matriz M14: viewer self-remove no falló';
    end if;
    update calendar_user set role = 'owner' where calendar_id = 997002 and user_id = 997004;
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000972', true);
    v_ok := false;
    begin
        perform remove_calendar_user(997002, 997002);
        v_ok := true;
    exception when sqlstate 'P0001' then
        if sqlerrm <> 'User cannot remove themselves' then
            raise exception 'permisos_matriz M14 (owner self): % (esperado User cannot remove themselves)', sqlerrm;
        end if;
    end;
    if v_ok then
        raise exception 'permisos_matriz M14: owner con reemplazo self-remove no falló';
    end if;
    update calendar_user set role = 'viewer' where calendar_id = 997002 and user_id = 997004;
    raise notice 'ok M14: último owner 403; viewer self 400; owner con reemplazo self 400';
end $$;

-- ── M15: materialize_routine: child reconcile → Not Allowed; adult → ok; false → solo ACL ──

do $$
declare
    v_ok boolean := false;
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000973', true);
    begin
        perform materialize_routine(997001, 'Europe/Madrid', true);
        v_ok := true;
    exception when sqlstate '42501' then
        if sqlerrm <> 'Not Allowed' then
            raise exception 'permisos_matriz M15 (child): % (esperado Not Allowed)', sqlerrm;
        end if;
    end;
    if v_ok then
        raise exception 'permisos_matriz M15: child sin routine.edit reconcilió';
    end if;
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000972', true);
    perform materialize_routine(997001, 'Europe/Madrid', true);
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000974', true);
    perform materialize_routine(997001, 'Europe/Madrid', false);
    raise notice 'ok M15: child reconcile 403; adult ok; reconcile=false solo ACL';
end $$;

-- ── M16: hogar archived → Not Found en toda RPC de recurso ──

do $$
declare
    v_ok boolean := false;
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000972', true);
    begin
        perform update_calendar(997003, 'PM-C3 X', '#333333', true, true);
        v_ok := true;
    exception when sqlstate 'P0002' then
        if sqlerrm <> 'Not Found' then
            raise exception 'permisos_matriz M16: % (esperado Not Found)', sqlerrm;
        end if;
    end;
    if v_ok then
        raise exception 'permisos_matriz M16: escritura en hogar archived no falló';
    end if;
    raise notice 'ok M16: hogar archived → Not Found';
end $$;

-- ── M17: personas: child crea (Q2); creador edita; tercero sin manage → Not Allowed (D15) ──

do $$
declare
    v json;
    v_id bigint;
    v_ok boolean := false;
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000973', true);
    v := create_person('PM-Nueva', '#123456');
    v_id := (v->>'id')::bigint;
    if v_id is null then
        raise exception 'permisos_matriz M17: child sin create_person (Q2): %', v;
    end if;
    v := update_person(v_id, 'PM-Nueva2', '#654321');
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000975', true);
    begin
        perform update_person(v_id, 'PM-Hack', '#000000');
        v_ok := true;
    exception when sqlstate '42501' then
        if sqlerrm <> 'Not Allowed' then
            raise exception 'permisos_matriz M17 (tercero): % (esperado Not Allowed)', sqlerrm;
        end if;
    end;
    if v_ok then
        raise exception 'permisos_matriz M17: tercero sin home.members.manage editó persona ajena';
    end if;
    raise notice 'ok M17: child crea (Q2); creador edita; tercero 403 (D15)';
end $$;

-- ── M18: personas por hogar (D4/Q-G): K ve P_h (sin lista compartida); X no ──

do $$
declare
    v json;
    v_ok boolean := false;
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000973', true);
    v := get_persons();
    if (v::jsonb @> '[{"id": 997001}]'::jsonb) is not true then
        raise exception 'permisos_matriz M18: K no ve P_h en get_persons: %', v;
    end if;
    v := fn_event_persons(997003);
    if (v::jsonb @> '[{"id": 997001}]'::jsonb) is not true then
        raise exception 'permisos_matriz M18: K no ve P_h en fn_event_persons: %', v;
    end if;
    select pm.v into v_ok from pm_rls pm where pm.k = 'p_h_k';
    if v_ok::int <> 1 then
        raise exception 'permisos_matriz M18: person_select para K = % (esperado 1)', v_ok;
    end if;
    select pm.v into v_ok from pm_rls pm where pm.k = 'p_h_x';
    if v_ok::int <> 0 then
        raise exception 'permisos_matriz M18: X ve personas de H = % (esperado 0)', v_ok;
    end if;
    raise notice 'ok M18: personas por hogar — K ve P_h (RPC y RLS); X no';
end $$;

-- ── M19: fn_sync_assignments: persona de otro hogar → Invalid person P0001 ──

do $$
declare
    v_ok boolean := false;
    v_id bigint;
begin
    select id into v_id from event where title = 'PM-EvA';
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000972', true);
    begin
        perform update_event(v_id, 'PM-EvA', '2026-12-13 10:00:00', 5, '[997004]'::jsonb,
                             'Europe/Madrid');
        v_ok := true;
    exception when sqlstate 'P0001' then
        if sqlerrm <> 'Invalid person' then
            raise exception 'permisos_matriz M19: % (esperado Invalid person)', sqlerrm;
        end if;
    end;
    if v_ok then
        raise exception 'permisos_matriz M19: persona de B asignada a evento de H';
    end if;
    raise notice 'ok M19: fn_sync_assignments por hogar — persona de B → Invalid person';
end $$;

-- ── M20: admin con snapshot vacío (A4) puede todo en su hogar con ACL ──

do $$
declare
    v bigint;
begin
    select count(*) into v from membership_permission where home_membership_id = 997001;
    if v <> 0 then
        raise exception 'permisos_matriz M20: admin con % filas (esperado 0, A4)', v;
    end if;
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000971', true);
    perform update_calendar(997001, 'PM-C1', '#111111', true, true);
    v := (create_event(997001, 'PM-EvAdm', '2026-12-14 10:00:00', 5, null)::jsonb->>'id')::bigint;
    if v is null then
        raise exception 'permisos_matriz M20: admin sin filas no creó evento';
    end if;
    raise notice 'ok M20: admin sin filas de permisos puede todo con ACL propia';
end $$;

-- ── M21: calendar_user_select sin cambios: K no ve calendar_user de C1 ──

do $$
declare
    v bigint;
begin
    select pm.v into v from pm_rls pm where pm.k = 'cu_c1_k';
    if v <> 0 then
        raise exception 'permisos_matriz M21: K ve % filas de calendar_user de C1 (esperado 0)', v;
    end if;
    raise notice 'ok M21: calendar_user_select sin cambios (K no ve ACL de C1)';
end $$;

-- ── M22: fn_person_ids_array (§3.2): null/no tocar, [], duplicados/orden, inválidos ──

do $$
declare
    v_ok boolean := false;
begin
    if fn_person_ids_array(null) is not null then
        raise exception 'permisos_matriz M22: null ≠ null';
    end if;
    if fn_person_ids_array('[]'::jsonb) <> array[]::bigint[] then
        raise exception 'permisos_matriz M22: [] ≠ {}';
    end if;
    if fn_person_ids_array('[1, 1]'::jsonb) <> array[1]::bigint[] then
        raise exception 'permisos_matriz M22: [1,1] ≠ [1]';
    end if;
    if fn_person_ids_array('[2, 1]'::jsonb) <> array[1, 2]::bigint[] then
        raise exception 'permisos_matriz M22: [2,1] ≠ [1,2]';
    end if;
    begin
        perform fn_person_ids_array('{}'::jsonb);
        v_ok := true;
    exception when sqlstate 'P0001' then
        if sqlerrm <> 'Invalid person' then raise; end if;
    end;
    if v_ok then
        raise exception 'permisos_matriz M22: objeto no-array no falló';
    end if;
    v_ok := false;
    begin
        perform fn_person_ids_array('"1"'::jsonb);
        v_ok := true;
    exception when sqlstate 'P0001' then
        if sqlerrm <> 'Invalid person' then raise; end if;
    end;
    if v_ok then
        raise exception 'permisos_matriz M22: string no-array no falló';
    end if;
    v_ok := false;
    begin
        perform fn_person_ids_array('["1"]'::jsonb);
        v_ok := true;
    exception when sqlstate 'P0001' then
        if sqlerrm <> 'Invalid person' then raise; end if;
    end;
    if v_ok then
        raise exception 'permisos_matriz M22: elemento string no falló';
    end if;
    v_ok := false;
    begin
        perform fn_person_ids_array('[1.5]'::jsonb);
        v_ok := true;
    exception when sqlstate 'P0001' then
        if sqlerrm <> 'Invalid person' then raise; end if;
    end;
    if v_ok then
        raise exception 'permisos_matriz M22: elemento decimal no falló';
    end if;
    v_ok := false;
    begin
        perform fn_person_ids_array('[true]'::jsonb);
        v_ok := true;
    exception when sqlstate 'P0001' then
        if sqlerrm <> 'Invalid person' then raise; end if;
    end;
    if v_ok then
        raise exception 'permisos_matriz M22: elemento booleano no falló';
    end if;
    v_ok := false;
    begin
        perform fn_person_ids_array('[0]'::jsonb);
        v_ok := true;
    exception when sqlstate 'P0001' then
        if sqlerrm <> 'Invalid person' then raise; end if;
    end;
    if v_ok then
        raise exception 'permisos_matriz M22: id 0 no falló';
    end if;
    v_ok := false;
    begin
        perform fn_person_ids_array('[-1]'::jsonb);
        v_ok := true;
    exception when sqlstate 'P0001' then
        if sqlerrm <> 'Invalid person' then raise; end if;
    end;
    if v_ok then
        raise exception 'permisos_matriz M22: id negativo no falló';
    end if;
    v_ok := false;
    begin
        perform fn_person_ids_array('[9999999999999999999]'::jsonb);
        v_ok := true;
    exception when sqlstate 'P0001' then
        if sqlerrm <> 'Invalid person' then raise; end if;
    end;
    if v_ok then
        raise exception 'permisos_matriz M22: desbordamiento bigint no falló';
    end if;
    raise notice 'ok M22: fn_person_ids_array — null/[]/duplicados/orden ok; malformados Invalid person';
end $$;

-- ── M23: create_event: persona de otro hogar → Invalid person; del hogar sin lista → ok ──

do $$
declare
    v_ok boolean := false;
    v json;
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000972', true);
    begin
        perform create_event(997002, 'PM-EvF', '2026-12-15 10:00:00', 5, '[997004]'::jsonb);
        v_ok := true;
    exception when sqlstate 'P0001' then
        if sqlerrm <> 'Invalid person' then
            raise exception 'permisos_matriz M23: % (esperado Invalid person)', sqlerrm;
        end if;
    end;
    if v_ok then
        raise exception 'permisos_matriz M23: persona de B en evento de H';
    end if;
    v := create_event(997002, 'PM-EvH', '2026-12-16 10:00:00', 5, '[997001]'::jsonb);
    if coalesce(jsonb_array_length(v::jsonb->'persons'), 0) <> 1 then
        raise exception 'permisos_matriz M23: persona del hogar sin lista no asignada: %', v->'persons';
    end if;
    raise notice 'ok M23: persona de otro hogar Invalid person; del hogar sin lista ok (D4)';
end $$;

-- ── M24: admin sin ACL en C2 → update_event Not Found y 0 filas nuevas en C2 ──

do $$
declare
    v_before bigint;
    v_after bigint;
    v_ok boolean := false;
begin
    select count(*) into v_before from event where calendar_id = 997002;
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000971', true);
    begin
        perform update_event(997002, 'PM-Ev2 X', '2026-12-02 10:00:00', 5, null, 'Europe/Madrid');
        v_ok := true;
    exception when sqlstate 'P0002' then
        if sqlerrm <> 'Not Found' then
            raise exception 'permisos_matriz M24: % (esperado Not Found)', sqlerrm;
        end if;
    end;
    if v_ok then
        raise exception 'permisos_matriz M24: admin sin ACL editó evento de C2';
    end if;
    select count(*) into v_after from event where calendar_id = 997002;
    if v_after <> v_before then
        raise exception 'permisos_matriz M24: % → % filas nuevas en C2 (R1-06)', v_before, v_after;
    end if;
    raise notice 'ok M24: admin sin ACL → Not Found y 0 filas nuevas en C2';
end $$;

-- ── M25: materialize_routines_for (Q-F (a)): ACL ∪ admin por p_user_id ──

do $$
declare
    v bigint;
begin
    -- eventos materializados por llamadas previas (M8/M8b llaman fn_materialize_my_routines):
    -- se limpian r2/r3 para medir el efecto de cada call sin precuenta frágil
    delete from event where routine_id in (997002, 997003);
    -- K (child, sin ACL en C1 ni admin): NO materializa r3 de C1
    perform materialize_routines_for(997003, 'Europe/Madrid');
    select count(*) into v from event where routine_id = 997003;
    if v <> 0 then
        raise exception 'permisos_matriz M25: K materializó % eventos de C1 sin ACL (esperado 0)', v;
    end if;
    -- A (admin sin ACL en C2): materializa r2 de C2 por Q-F (a)
    perform materialize_routines_for(997001, 'Europe/Madrid');
    select count(*) into v from event where routine_id = 997002;
    if v < 1 then
        raise exception 'permisos_matriz M25: admin sin ACL no materializó r2 (Q-F (a))';
    end if;
    raise notice 'ok M25: materialize_routines_for — admin sin ACL materializa; K sin ACL no';
end $$;

-- ── M26: orden de errores: validación P0001 antes del lock; recurso inexistente → Not Found ──

do $$
declare
    v_ok boolean := false;
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000972', true);
    begin
        perform update_event(997999999, '', '2026-12-20 10:00:00', 5, null, 'Europe/Madrid');
        v_ok := true;
    exception when sqlstate 'P0001' then
        if sqlerrm <> 'Event ID, title, and date_at are required' then
            raise exception 'permisos_matriz M26: % (esperado Event ID, title, and date_at are required)', sqlerrm;
        end if;
    end;
    if v_ok then
        raise exception 'permisos_matriz M26: título vacío no falló antes del lock';
    end if;
    v_ok := false;
    begin
        perform update_event(997999999, 'PM-X', '2026-12-20 10:00:00', 5, null, 'Europe/Madrid');
        v_ok := true;
    exception when sqlstate 'P0002' then
        if sqlerrm <> 'Not Found' then
            raise exception 'permisos_matriz M26: % (esperado Not Found)', sqlerrm;
        end if;
    end;
    if v_ok then
        raise exception 'permisos_matriz M26: evento inexistente no falló';
    end if;
    raise notice 'ok M26: validación P0001 antes del lock; evento inexistente → Not Found';
end $$;

-- ── M27: persona inactiva del hogar → Invalid person (pasada 2 + trigger 0015 iv) ──

do $$
declare
    v_ok boolean := false;
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000972', true);
    begin
        perform create_event(997002, 'PM-EvI', '2026-12-21 10:00:00', 5, '[997003]'::jsonb);
        v_ok := true;
    exception when sqlstate 'P0001' then
        if sqlerrm <> 'Invalid person' then
            raise exception 'permisos_matriz M27: % (esperado Invalid person)', sqlerrm;
        end if;
    end;
    if v_ok then
        raise exception 'permisos_matriz M27: persona inactiva asignada';
    end if;
    raise notice 'ok M27: persona inactiva de H → Invalid person 400';
end $$;

-- ── Limpieza de datos scratch 997xxx ──

set session_replication_role = replica;
begin;
delete from event_user where user_id between 997001 and 997006
   or event_id in (select id from event where calendar_id between 997001 and 997003);
delete from routine_event_alarm where user_id between 997001 and 997006;
delete from routine_exception where routine_id between 997001 and 997003;
delete from event_person where event_id in (select id from event where calendar_id between 997001 and 997003);
delete from routine_person where routine_id between 997001 and 997003;
delete from event where calendar_id between 997001 and 997003;
delete from routine where calendar_id between 997001 and 997003;
delete from task where task_list_id between 997001 and 997002;
delete from task_list_user where home_id = 997001 and task_list_id between 997001 and 997002;
delete from task_list where id between 997001 and 997002;
delete from calendar_user where calendar_id between 997001 and 997003;
delete from calendar where id between 997001 and 997003;
delete from person where home_id in (997001, 997002) or name like 'PM-%';
delete from home_member where home_id in (997001, 997002) or name like 'PM-%';
delete from membership_permission where home_membership_id between 997001 and 997007;
delete from home_membership where home_id in (997001, 997002, 997003);
delete from audit_log where home_id in (997001, 997002, 997003);
delete from home where id in (997001, 997002, 997003);
delete from app_user where id between 997001 and 997006;
delete from auth.users where id in (
    '00000000-0000-4000-8000-000000000971', '00000000-0000-4000-8000-000000000972',
    '00000000-0000-4000-8000-000000000973', '00000000-0000-4000-8000-000000000974',
    '00000000-0000-4000-8000-000000000975', '00000000-0000-4000-8000-000000000976');
commit;
set session_replication_role = default;
