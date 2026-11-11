-- home_checks_rpc.sql — RPC nuevas y redefinidas de 0016 (fase 1.4, T3; plan §7.3, R1-01, R1-02).
-- Se ejecuta con psql tras aplicar 0016 sobre 0001–0015 (sin dependencias de la Edge):
--   psql -v ON_ERROR_STOP=1 -f home_checks_rpc.sql
-- La aserción de create_home con home_member vinculado REQUIERE 0023_create_home_admin_member.sql
-- (dc/tareas-asignar) aplicada antes.
-- Cada bloque DO emite 'ok …' o aborta con 'home_checks_rpc: …'. Impersonación vía
-- set_config('request.jwt.claim.sub', …, true) (auth.uid()); cabecera vía
-- set_config('request.headers', '{"x-home-id":"…"}', true) (fn_active_home_id).
--
-- Cubre (§7.3): get_homes sin uid → 42501; get_home_detail no miembro → P0002 y guest sin
-- home.view → 42501; update_home por member sin home.settings.manage → 42501; create_home →
-- una membresía admin y home.is_personal = false; get_home_memberships admin → 23 códigos y
-- member legacy17 → 17 (incluye home.view); cabecera ≠ p_home_id → P0002; set_default_home no
-- miembro → P0002. Más R1-02 (nombre en blanco → 'Name is required' P0001 en create_home y
-- update_home; p_timezone null → 'Europe/Madrid' en create y conserva en update) y R1-01
-- (get_calendars/get_task_lists con cabecera ajena → P0002 y filtro por hogar activo).
--
-- Datos scratch (usuarios 993001–993004, hogares 993001–993003, calendarios/listas 993001–993002,
-- auth_uid 00000000-0000-4000-8000-00000000096x) borrados al final. El alta scratch usa
-- session_replication_role = replica SOLO para saltarse la FK app_user→auth.users y el trigger
-- 0014(a) (ya probado en home_checks_compat.sql V5j).

-- ── §7.3: get_homes sin uid → 42501 'Not Allowed' ──

do $$
begin
    perform set_config('request.jwt.claim.sub', '', true);
    begin
        perform get_homes();
        raise exception 'home_checks_rpc: get_homes sin uid no falló';
    exception
        when sqlstate '42501' then
            if sqlerrm <> 'Not Allowed' then
                raise exception 'home_checks_rpc: get_homes sin uid, mensaje % (esperado Not Allowed)', sqlerrm;
            end if;
    end;
    raise notice 'ok get_homes sin uid → 42501 Not Allowed';
end $$;

-- ── Preambulo scratch: usuarios, hogares, membresías, permisos, calendarios y listas ──

set session_replication_role = replica;
insert into auth.users (id, email, raw_user_meta_data) values
    ('00000000-0000-4000-8000-000000000961', 'rpc-u1@check.homita.example', '{"name":"RPC-U1"}'),
    ('00000000-0000-4000-8000-000000000962', 'rpc-u2@check.homita.example', '{"name":"RPC-U2"}'),
    ('00000000-0000-4000-8000-000000000963', 'rpc-u3@check.homita.example', '{"name":"RPC-U3"}'),
    ('00000000-0000-4000-8000-000000000964', 'rpc-u4@check.homita.example', '{"name":"RPC-U4"}')
on conflict (id) do nothing;
insert into app_user (id, auth_uid, name, email) values
    (993001, '00000000-0000-4000-8000-000000000961', 'RPC-U1', 'rpc-u1@check.homita.example'),
    (993002, '00000000-0000-4000-8000-000000000962', 'RPC-U2', 'rpc-u2@check.homita.example'),
    (993003, '00000000-0000-4000-8000-000000000963', 'RPC-U3', 'rpc-u3@check.homita.example'),
    (993004, '00000000-0000-4000-8000-000000000964', 'RPC-U4', 'rpc-u4@check.homita.example')
on conflict (id) do nothing;
set session_replication_role = default;

begin;
insert into home (id, name, status, is_personal, created_by) values
    (993001, 'RPC Hogar A', 'active', false, 993001),
    (993002, 'RPC Hogar B', 'active', false, 993004),
    (993003, 'RPC Hogar C', 'active', false, 993004);
insert into home_membership (home_id, app_user_id, role) values
    (993001, 993001, 'admin'), (993001, 993002, 'member'), (993001, 993003, 'member'),
    (993002, 993004, 'admin'), (993002, 993001, 'member'),
    (993003, 993004, 'admin');
-- u2: snapshot member legacy17 (17 permisos, incluye home.view); u3: solo task.view (guest-like)
insert into membership_permission (home_membership_id, permission_code)
select hm.id, c.code from home_membership hm
cross join (values
    ('home.view'), ('calendar.view'), ('task.view'), ('routine.view'),
    ('task.create'), ('task.edit'), ('task.complete'), ('task.assign'), ('task.delete'),
    ('event.create'), ('event.edit'), ('event.delete'), ('event.assign'),
    ('routine.create'), ('routine.edit'), ('routine.delete'), ('routine.assign')
) as c(code)
where hm.home_id = 993001 and hm.app_user_id = 993002;
insert into membership_permission (home_membership_id, permission_code)
select id, 'task.view' from home_membership where home_id = 993001 and app_user_id = 993003;
insert into calendar (id, name, color, token, home_id) values
    (993001, 'RPC-Cal-A', '#111111', 'rpc-cal-a', 993001),
    (993002, 'RPC-Cal-B', '#222222', 'rpc-cal-b', 993002);
insert into calendar_user (calendar_id, user_id, role, widget, dashboard, home_id) values
    (993001, 993001, 'owner', true, true, 993001),
    (993002, 993001, 'owner', true, true, 993002);
insert into task_list (id, name, color, token, sort, home_id) values
    (993001, 'RPC-Lista-A', '#333333', 'rpc-lista-a', 'updated_at', 993001),
    (993002, 'RPC-Lista-B', '#444444', 'rpc-lista-b', 'updated_at', 993002);
insert into task_list_user (task_list_id, user_id, role, widget, dashboard, home_id) values
    (993001, 993001, 'owner', true, true, 993001),
    (993002, 993001, 'owner', true, true, 993002);
commit;

-- ── get_homes: filas del usuario (A admin, B member), sin C (A7 excluye archived; aquí C es
-- ajena) y sin filtro por cabecera (§5.1) ──

do $$
declare
    v jsonb;
    v_n bigint;
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000961', true);
    v := get_homes()::jsonb;
    select count(*) into v_n from jsonb_array_elements(v) e
    where (e->>'home_id')::bigint = 993001 and e->>'role' = 'admin'
      and (e->>'is_personal')::bool = false and (e->>'is_default')::bool = false;
    if v_n <> 1 then
        raise exception 'home_checks_rpc: get_homes sin la fila de A (role admin): %', v;
    end if;
    if not exists (select 1 from jsonb_array_elements(v) e
                   where (e->>'home_id')::bigint = 993002 and e->>'role' = 'member')
       or exists (select 1 from jsonb_array_elements(v) e
                  where (e->>'home_id')::bigint = 993003) then
        raise exception 'home_checks_rpc: get_homes filas inesperadas: %', v;
    end if;
    raise notice 'ok get_homes: hogares propios con role/is_default/is_personal, sin ajenos';
end $$;

-- ── create_home (§7.3 + R1-02): membresía admin, is_personal=false, timezone default, name ──

do $$
declare
    v jsonb;
    v_id bigint;
    v_n bigint;
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000961', true);
    v := create_home('RPC-Nueva', null)::jsonb;
    v_id := (v->>'id')::bigint;
    if v_id is null or (v->>'is_personal')::bool <> false or v->>'timezone' <> 'Europe/Madrid' then
        raise exception 'home_checks_rpc: create_home → %', v;
    end if;
    select count(*) into v_n from home_membership where home_id = v_id;
    if v_n <> 1 or not exists (select 1 from home_membership
                              where home_id = v_id and app_user_id = 993001 and role = 'admin') then
        raise exception 'home_checks_rpc: create_home sin una única membresía admin (%)', v_n;
    end if;
    -- (0023_create_home_admin_member): el creador es el primer miembro (adult activo vinculado a su cuenta, con su person).
    if (select count(*) from home_member where home_id = v_id) <> 1
       or not exists (select 1 from home_member hm
                       where hm.home_id = v_id and hm.app_user_id = 993001
                         and hm.kind = 'adult' and hm.status = 'active')
       or not exists (select 1 from person p join home_member hm on hm.id = p.home_member_id
                       where p.home_id = v_id and hm.app_user_id = 993001) then
        raise exception 'home_checks_rpc: create_home sin home_member adult activo vinculado al creador';
    end if;
    raise notice 'ok create_home → HOME_DETAIL, is_personal=false, timezone Europe/Madrid, 1 membresía admin y 1 miembro vinculado';
    begin
        perform create_home('   ', null);
        raise exception 'home_checks_rpc: create_home con name en blanco no falló';
    exception
        when sqlstate 'P0001' then
            if sqlerrm <> 'Name is required' then
                raise exception 'home_checks_rpc: create_home name en blanco, mensaje % (esperado Name is required)', sqlerrm;
            end if;
    end;
    raise notice 'ok create_home con name en blanco → Name is required P0001 (R1-02)';
end $$;

-- ── update_home (R1-02): name en blanco → P0001; p_timezone null conserva la zona ──

do $$
declare
    v jsonb;
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000961', true);
    begin
        perform update_home(993001, '   ', null);
        raise exception 'home_checks_rpc: update_home con name en blanco no falló';
    exception
        when sqlstate 'P0001' then
            if sqlerrm <> 'Name is required' then
                raise exception 'home_checks_rpc: update_home name en blanco, mensaje % (esperado Name is required)', sqlerrm;
            end if;
    end;
    v := update_home(993001, 'RPC Hogar A', null)::jsonb;
    if v->>'timezone' <> 'Europe/Madrid' or v->>'name' <> 'RPC Hogar A' then
        raise exception 'home_checks_rpc: update_home con p_timezone null → %', v;
    end if;
    raise notice 'ok update_home: name en blanco → P0001; p_timezone null conserva la zona (R1-02)';
end $$;

-- ── Cabecera (§7.3): x-home-id ≠ p_home_id → P0002 'Not Found' (sin importar la membresía) ──

do $$
declare
    v bigint;
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000961', true);
    perform set_config('request.headers', '{"x-home-id":"993002"}', true);
    begin
        perform get_home_detail(993001);
        raise exception 'home_checks_rpc: get_home_detail con cabecera ≠ id no falló';
    exception
        when sqlstate 'P0002' then
            if sqlerrm <> 'Not Found' then
                raise exception 'home_checks_rpc: cabecera ≠ id, mensaje % (esperado Not Found)', sqlerrm;
            end if;
    end;
    raise notice 'ok cabecera x-home-id ≠ p_home_id → get_home_detail P0002 (§7.3)';
end $$;

-- ── get_home_detail: no miembro → P0002; miembro sin home.view (guest) → 42501 ──

do $$
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000964', true);
    begin
        perform get_home_detail(993001);
        raise exception 'home_checks_rpc: get_home_detail de no miembro no falló';
    exception
        when sqlstate 'P0002' then
            if sqlerrm <> 'Not Found' then
                raise exception 'home_checks_rpc: no miembro, mensaje % (esperado Not Found)', sqlerrm;
            end if;
    end;
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000963', true);
    begin
        perform get_home_detail(993001);
        raise exception 'home_checks_rpc: get_home_detail de guest sin home.view no falló';
    exception
        when sqlstate '42501' then
            if sqlerrm <> 'Not Allowed' then
                raise exception 'home_checks_rpc: guest sin home.view, mensaje % (esperado Not Allowed)', sqlerrm;
            end if;
    end;
    raise notice 'ok get_home_detail: no miembro → P0002; guest sin home.view → 42501 (§7.3)';
end $$;

-- ── update_home por member sin home.settings.manage → 42501 ──

do $$
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000962', true);
    begin
        perform update_home(993001, 'XT', null);
        raise exception 'home_checks_rpc: update_home por member sin permiso no falló';
    exception
        when sqlstate '42501' then
            if sqlerrm <> 'Not Allowed' then
                raise exception 'home_checks_rpc: member sin home.settings.manage, mensaje % (esperado Not Allowed)', sqlerrm;
            end if;
    end;
    raise notice 'ok update_home por member sin home.settings.manage → 42501 (§7.3)';
end $$;

-- ── set_default_home: no miembro → P0002 (§7.3) ──

do $$
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000964', true);
    begin
        perform set_default_home(993001);
        raise exception 'home_checks_rpc: set_default_home de no miembro no falló';
    exception
        when sqlstate 'P0002' then
            if sqlerrm <> 'Not Found' then
                raise exception 'home_checks_rpc: set_default_home no miembro, mensaje % (esperado Not Found)', sqlerrm;
            end if;
    end;
    raise notice 'ok set_default_home de no miembro → P0002 (§7.3)';
end $$;

-- ── get_home_memberships (§7.3 + R1-03): admin → 23 códigos; member legacy17 → 17 con home.view ──

do $$
declare
    v jsonb;
    v_n bigint;
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000961', true);
    v := get_home_memberships(993001)::jsonb;
    select jsonb_array_length(e->'permissions') into v_n from jsonb_array_elements(v) e
    where (e->>'app_user_id')::bigint = 993001 and e->>'role' = 'admin';
    if v_n <> 23 then
        raise exception 'home_checks_rpc: permissions de admin = % (esperado 23)', v_n;
    end if;
    raise notice 'ok get_home_memberships: fila admin → 23 códigos (A4)';
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000962', true);
    v := get_home_memberships(993001)::jsonb;
    select jsonb_array_length(e->'permissions') into v_n from jsonb_array_elements(v) e
    where (e->>'app_user_id')::bigint = 993002;
    if v_n <> 17 then
        raise exception 'home_checks_rpc: permissions de member legacy17 = % (esperado 17)', v_n;
    end if;
    if not exists (select 1 from jsonb_array_elements(v) e
                   where (e->>'app_user_id')::bigint = 993002
                     and e->'permissions' ? 'home.view') then
        raise exception 'home_checks_rpc: member legacy17 sin home.view: %', v;
    end if;
    select jsonb_array_length(e->'permissions') into v_n from jsonb_array_elements(v) e
    where (e->>'app_user_id')::bigint = 993003;
    if v_n <> 1 then
        raise exception 'home_checks_rpc: permissions de member con 1 permiso = %', v_n;
    end if;
    raise notice 'ok get_home_memberships: member legacy17 → 17 códigos (incluye home.view), guest → 1';
end $$;

-- ── R1-01: get_calendars/get_task_lists con cabecera ajena → P0002 (no []) y filtro por hogar ──

do $$
declare
    v jsonb;
    v_n bigint;
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000961', true);
    perform set_config('request.headers', '{"x-home-id":"993003"}', true);  -- C: u1 no es miembro
    begin
        perform get_calendars();
        raise exception 'home_checks_rpc: get_calendars con cabecera ajena no falló';
    exception
        when sqlstate 'P0002' then
            if sqlerrm <> 'Not Found' then
                raise exception 'home_checks_rpc: get_calendars cabecera ajena, mensaje % (esperado Not Found)', sqlerrm;
            end if;
    end;
    begin
        perform get_task_lists();
        raise exception 'home_checks_rpc: get_task_lists con cabecera ajena no falló';
    exception
        when sqlstate 'P0002' then
            if sqlerrm <> 'Not Found' then
                raise exception 'home_checks_rpc: get_task_lists cabecera ajena, mensaje % (esperado Not Found)', sqlerrm;
            end if;
    end;
    raise notice 'ok get_calendars/get_task_lists con cabecera ajena → P0002 (R1-01)';
    -- Filtro D-2: con cabecera del hogar A solo los recursos de A; sin cabecera, todos
    perform set_config('request.headers', '{"x-home-id":"993001"}', true);
    v := get_calendars()::jsonb;
    select count(*) into v_n from jsonb_array_elements(v) e where (e->>'id')::bigint = 993001;
    if v_n <> 1 or jsonb_array_length(v) <> 1 then
        raise exception 'home_checks_rpc: get_calendars con cabecera A = % (esperado solo 993001)', v;
    end if;
    v := get_task_lists()::jsonb;
    if jsonb_array_length(v) <> 1 or (v->0->>'id')::bigint <> 993001 then
        raise exception 'home_checks_rpc: get_task_lists con cabecera A = % (esperado solo 993001)', v;
    end if;
    perform set_config('request.headers', '{}', true);
    v := get_calendars()::jsonb;
    if jsonb_array_length(v) <> 2 then
        raise exception 'home_checks_rpc: get_calendars sin cabecera = % (esperado 2)', v;
    end if;
    raise notice 'ok get_calendars/get_task_lists filtran por el hogar de cabecera y sin cabecera no filtran (D-2)';
end $$;

-- ── Limpieza scratch (una transacción, replica: sin triggers de 0014/0015) ──

do $$
begin
    set local session_replication_role = replica;
    delete from event_user where event_id in (select id from event where calendar_id in (993001, 993002));
    delete from event_person where event_id in (select id from event where calendar_id in (993001, 993002));
    delete from event where calendar_id in (993001, 993002);
    delete from routine_person where routine_id in (select id from routine where calendar_id in (993001, 993002));
    delete from routine_user where routine_id in (select id from routine where calendar_id in (993001, 993002));
    delete from routine where calendar_id in (993001, 993002);
    delete from task where task_list_id in (993001, 993002);
    delete from task_list_user where task_list_id in (993001, 993002) or home_id in (993001, 993002);
    delete from calendar_user where calendar_id in (993001, 993002) or home_id in (993001, 993002);
    delete from task_list where id in (993001, 993002);
    delete from calendar where id in (993001, 993002);
    delete from membership_permission where home_membership_id in
        (select id from home_membership where home_id in (993001, 993002, 993003)
            or app_user_id in (993001, 993002, 993003, 993004));
    delete from home_membership where home_id in (993001, 993002, 993003)
        or app_user_id in (993001, 993002, 993003, 993004)
        or home_id in (select id from home where name = 'RPC-Nueva');
    delete from person where home_id in (select id from home where name = 'RPC-Nueva');
    delete from home_member where home_id in (993001, 993002, 993003)
        or home_id in (select id from home where name = 'RPC-Nueva');
    delete from audit_log where home_id in (993001, 993002, 993003);
    delete from home where id in (993001, 993002, 993003) or name = 'RPC-Nueva';
    delete from app_user where id in (993001, 993002, 993003, 993004);
    delete from auth.users where id in (
        '00000000-0000-4000-8000-000000000961', '00000000-0000-4000-8000-000000000962',
        '00000000-0000-4000-8000-000000000963', '00000000-0000-4000-8000-000000000964');
    set local session_replication_role = default;
end $$;
