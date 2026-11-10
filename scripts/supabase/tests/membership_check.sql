-- membership_check.sql — RPC de administradores de 0018 (fase 1.6, T3; plan §6.1 T1–T15).
-- Se ejecuta con psql tras aplicar 0018 sobre 0001–0017 (sin dependencias de la Edge):
--   psql -v ON_ERROR_STOP=1 -f membership_check.sql
-- Cada bloque DO emite 'ok …' o aborta con 'membership_check: …'. Impersonación vía
-- set_config('request.jwt.claim.sub', …, true) (auth.uid()); cabecera vía
-- set_config('request.headers', '{"x-home-id":"…"}', true) (fn_active_home_id).
--
-- Cubre (§6.1): T1 promote (snapshot borrado); T2 demote (legacy17 exacto); T3 demote del último
-- admin → 42501; T4 bypass RPC con COMMIT que falla 42501 (trigger 0015; ver nota T4); T6
-- transfer atómico (éxito + fallo sin cambios); T7 transfer a sí mismo → P0001; T8 hogar archived
-- → P0002 y bypass en archived COMMIT OK; T9 salir (ACL/membership_permission borradas,
-- home_member conservado sin cuenta); T10 bloqueos (último admin, owner único, último hogar);
-- T11 default_home_id (personal primero, luego joined_at); T12 expulsar (member 42501, no miembro
-- P0002, membership de otro hogar P0002); T13 Q4 (baja soft no revoca; DELETE /home/membership sí);
-- T14 home_role en get_*_users y USER sin home_role en add_*_user; T15 RPC directa con nulos.
-- T5 (concurrencia) lo ejecuta membership_concurrency.sh (T4 del plan).
--
-- Nota T4: el COMMIT que falla no es atrapable dentro de la sesión con ON_ERROR_STOP=1, así que la
-- sección T4 hace \unset ON_ERROR_STOP alrededor de `begin; update; commit;` exactamente como §6.1
-- T4 y lo restaura después. La evidencia del 'ERROR:  Not Allowed' (42501) queda en la salida; el
-- DO posterior verifica que el estado no cambió (si el COMMIT hubiera sido correcto, el estado
-- cambiaría y el test fallaría).
--
-- Datos scratch (usuarios 994001–994010, auth_uid 00000000-0000-4000-8000-000000000971–0980,
-- hogares 994001–994008, membresías 994101–994119, calendarios/listas 994001–994002,
-- home_member 994001) borrados al final. El alta scratch usa session_replication_role = replica
-- SOLO para saltarse la FK app_user→auth.users (mismo patrón que home_checks_rpc.sql).

begin;
set session_replication_role = replica;
insert into auth.users (id, email, raw_user_meta_data) values
    ('00000000-0000-4000-8000-000000000971', 'mc-u1@check.homita.example', '{"name": "MC-U1"}'),
    ('00000000-0000-4000-8000-000000000972', 'mc-u2@check.homita.example', '{"name": "MC-U2"}'),
    ('00000000-0000-4000-8000-000000000973', 'mc-u3@check.homita.example', '{"name": "MC-U3"}'),
    ('00000000-0000-4000-8000-000000000974', 'mc-u4@check.homita.example', '{"name": "MC-U4"}'),
    ('00000000-0000-4000-8000-000000000975', 'mc-u5@check.homita.example', '{"name": "MC-U5"}'),
    ('00000000-0000-4000-8000-000000000976', 'mc-u6@check.homita.example', '{"name": "MC-U6"}'),
    ('00000000-0000-4000-8000-000000000977', 'mc-u7@check.homita.example', '{"name": "MC-U7"}'),
    ('00000000-0000-4000-8000-000000000978', 'mc-u8@check.homita.example', '{"name": "MC-U8"}'),
    ('00000000-0000-4000-8000-000000000979', 'mc-u9@check.homita.example', '{"name": "MC-U9"}'),
    ('00000000-0000-4000-8000-000000000980', 'mc-u10@check.homita.example', '{"name": "MC-U10"}')
on conflict (id) do nothing;
insert into app_user (id, auth_uid, name, email) values
    (994001, '00000000-0000-4000-8000-000000000971', 'MC-U1', 'mc-u1@check.homita.example'),
    (994002, '00000000-0000-4000-8000-000000000972', 'MC-U2', 'mc-u2@check.homita.example'),
    (994003, '00000000-0000-4000-8000-000000000973', 'MC-U3', 'mc-u3@check.homita.example'),
    (994004, '00000000-0000-4000-8000-000000000974', 'MC-U4', 'mc-u4@check.homita.example'),
    (994005, '00000000-0000-4000-8000-000000000975', 'MC-U5', 'mc-u5@check.homita.example'),
    (994006, '00000000-0000-4000-8000-000000000976', 'MC-U6', 'mc-u6@check.homita.example'),
    (994007, '00000000-0000-4000-8000-000000000977', 'MC-U7', 'mc-u7@check.homita.example'),
    (994008, '00000000-0000-4000-8000-000000000978', 'MC-U8', 'mc-u8@check.homita.example'),
    (994009, '00000000-0000-4000-8000-000000000979', 'MC-U9', 'mc-u9@check.homita.example'),
    (994010, '00000000-0000-4000-8000-000000000980', 'MC-U10', 'mc-u10@check.homita.example')
on conflict (id) do nothing;
set session_replication_role = default;

insert into home (id, name, status, is_personal, created_by) values
    (994001, 'MC Hogar A', 'active', false, 994001),
    (994002, 'MC Hogar B', 'active', false, 994005),
    (994003, 'MC Hogar C', 'archived', false, 994008),
    (994004, 'MC Hogar D', 'active', true, 994007),
    (994005, 'MC Hogar E', 'active', false, 994007),
    (994006, 'MC Hogar F', 'active', false, 994007),
    (994007, 'MC Hogar G', 'active', false, 994007),
    (994008, 'MC Hogar H', 'active', false, 994007);
insert into home_membership (id, home_id, app_user_id, role, joined_at) values
    (994101, 994001, 994001, 'admin', '2000-01-01 00:00:00'),   -- u1 @ A (T1/T6: caller)
    (994102, 994001, 994002, 'member', '2000-01-02 00:00:00'),  -- u2 @ A (T1/T2/T6/T7)
    (994103, 994001, 994003, 'member', '2000-01-03 00:00:00'),  -- u3 @ A (T9/T13: sale)
    (994104, 994001, 994004, 'member', '2000-01-04 00:00:00'),  -- u4 @ A (T10: owner único)
    (994105, 994002, 994005, 'admin', '2000-01-01 00:00:00'),   -- u5 @ B (T3/T4/T10: último admin)
    (994106, 994002, 994006, 'member', '2000-01-02 00:00:00'),  -- u6 @ B (T10: último hogar)
    (994107, 994003, 994008, 'admin', '2000-01-01 00:00:00'),   -- u8 @ C archived (T8)
    (994108, 994004, 994007, 'admin', '2000-01-01 00:00:00'),   -- u7 @ D..H (admin común)
    (994109, 994004, 994003, 'member', '2000-01-05 00:00:00'),  -- u3 @ D (2º hogar de u3)
    (994110, 994004, 994004, 'member', '2000-01-05 00:00:00'),  -- u4 @ D (2º hogar de u4)
    (994111, 994004, 994009, 'member', '2000-01-05 00:00:00'),  -- u9 @ D (T11a: personal)
    (994112, 994005, 994007, 'admin', '2000-01-01 00:00:00'),   -- u7 @ E
    (994113, 994005, 994009, 'member', '2000-01-06 00:00:00'),  -- u9 @ E (T11a: sale)
    (994114, 994006, 994007, 'admin', '2000-01-01 00:00:00'),   -- u7 @ F
    (994115, 994006, 994010, 'member', '2000-01-03 00:00:00'),  -- u10 @ F (T11b: sale; joined 01-03)
    (994116, 994007, 994007, 'admin', '2000-01-01 00:00:00'),   -- u7 @ G
    (994117, 994007, 994010, 'member', '2000-01-02 00:00:00'),  -- u10 @ G (joined 01-02)
    (994118, 994008, 994007, 'admin', '2000-01-01 00:00:00'),   -- u7 @ H
    (994119, 994008, 994010, 'member', '2000-01-01 00:00:00');  -- u10 @ H (joined 01-01: menor)
insert into membership_permission (home_membership_id, permission_code)
select hm.id, x.code
from home_membership hm
cross join (values
    ('home.view'), ('calendar.view'), ('task.view'), ('routine.view'),
    ('task.create'), ('task.edit'), ('task.complete'), ('task.assign'), ('task.delete'),
    ('event.create'), ('event.edit'), ('event.delete'), ('event.assign'),
    ('routine.create'), ('routine.edit'), ('routine.delete'), ('routine.assign')
) as x(code)
where hm.id in (994102, 994103, 994104);
insert into calendar (id, name, color, token, home_id) values
    (994001, 'MC-Cal-A', '#111111', 'mc-cal-a', 994001),
    (994002, 'MC-Cal-U4', '#222222', 'mc-cal-u4', 994001);
insert into calendar_user (calendar_id, user_id, role, widget, dashboard, home_id) values
    (994001, 994001, 'owner', true, true, 994001),
    (994001, 994002, 'viewer', true, true, 994001),
    (994001, 994003, 'viewer', true, true, 994001),
    (994002, 994004, 'owner', true, true, 994001);
insert into task_list (id, name, color, token, sort, home_id) values
    (994001, 'MC-Lista-A', '#333333', 'mc-lista-a', 'updated_at', 994001);
insert into task_list_user (task_list_id, user_id, role, widget, dashboard, home_id) values
    (994001, 994001, 'owner', true, true, 994001),
    (994001, 994003, 'viewer', true, true, 994001);
set session_replication_role = replica;
insert into home_member (id, home_id, kind, name, color, status, app_user_id, created_by)
    values (994001, 994001, 'adult', 'MC-Miembro-U3', '#A1B2C3', 'active', 994003, 994001);
set session_replication_role = default;
update app_user set default_home_id = 994001 where id = 994003;
update app_user set default_home_id = 994005 where id = 994009;
update app_user set default_home_id = 994006 where id = 994010;
commit;

-- ── §6.1 T1: promote member→admin — role='admin' y snapshot borrado (0 filas) ──

do $$
declare v jsonb; v_n bigint;
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000971', true);
    v := set_home_membership_role(994001, 994102, 'admin')::jsonb;
    if v->>'role' <> 'admin' or (v->>'membership_id')::bigint <> 994102
       or (v->>'home_id')::bigint <> 994001 or (v->>'app_user_id')::bigint <> 994002 then
        raise exception 'membership_check: T1 set_home_membership_role promote → %', v;
    end if;
    if (select role from home_membership where id = 994102) <> 'admin' then
        raise exception 'membership_check: T1 la membresía 994102 no quedó admin';
    end if;
    select count(*) into v_n from membership_permission where home_membership_id = 994102;
    if v_n <> 0 then
        raise exception 'membership_check: T1 promote sin borrar el snapshot (% filas)', v_n;
    end if;
    raise notice 'ok T1 promote member→admin: role=admin, membership_permission=0';
end $$;

-- ── §6.1 T2: demote admin→member con otro admin — legacy17 exacto ──

do $$
declare v jsonb; v_n bigint; v_bad bigint;
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000971', true);
    v := set_home_membership_role(994001, 994102, 'member')::jsonb;
    if v->>'role' <> 'member' or (select role from home_membership where id = 994102) <> 'member' then
        raise exception 'membership_check: T2 set_home_membership_role demote → %', v;
    end if;
    select count(*) into v_n from membership_permission where home_membership_id = 994102;
    select count(*) into v_bad from membership_permission
     where home_membership_id = 994102 and permission_code not in (
        'home.view',
        'calendar.view', 'task.view', 'routine.view',
        'task.create', 'task.edit', 'task.complete', 'task.assign', 'task.delete',
        'event.create', 'event.edit', 'event.delete', 'event.assign',
        'routine.create', 'routine.edit', 'routine.delete', 'routine.assign');
    if v_n <> 17 or v_bad <> 0 then
        raise exception 'membership_check: T2 snapshot ≠ legacy17 (n=%, ajenos=%)', v_n, v_bad;
    end if;
    raise notice 'ok T2 demote admin→member: role=member, snapshot = 17 códigos de 0013 S4';
end $$;

-- ── §6.1 T3: demote del último admin vía RPC → 42501 'Not Allowed'; estado sin cambios ──

do $$
declare v_n bigint;
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000975', true);
    begin
        perform set_home_membership_role(994002, 994105, 'member');
        raise exception 'membership_check: T3 demote del último admin no falló';
    exception
        when sqlstate '42501' then
            if sqlerrm <> 'Not Allowed' then
                raise exception 'membership_check: T3 mensaje % (esperado Not Allowed)', sqlerrm;
            end if;
    end;
    if (select role from home_membership where id = 994105) <> 'admin' then
        raise exception 'membership_check: T3 el último admin quedó degradado';
    end if;
    select count(*) into v_n from home_membership where home_id = 994002 and role = 'admin';
    if v_n <> 1 then
        raise exception 'membership_check: T3 admins de MC Hogar B = % (esperado 1)', v_n;
    end if;
    raise notice 'ok T3 demote del último admin → 42501 Not Allowed, estado sin cambios';
end $$;

-- ── §6.1 T4: bypass RPC — COMMIT del trigger 0015 falla 42501 (ver nota T4) ──

\unset ON_ERROR_STOP
begin;
update home_membership set role = 'member' where id = 994105;
commit;
\set ON_ERROR_STOP 1

do $$
declare v_n bigint;
begin
    if (select role from home_membership where id = 994105) <> 'admin' then
        raise exception 'membership_check: T4 el COMMIT no falló (el último admin quedó degradado)';
    end if;
    select count(*) into v_n from home_membership where home_id = 994002 and role = 'admin';
    if v_n <> 1 then
        raise exception 'membership_check: T4 admins de MC Hogar B = % (esperado 1)', v_n;
    end if;
    raise notice 'ok T4 bypass RPC: COMMIT falla 42501 (trigger 0015), estado sin cambios';
end $$;

-- ── §6.1 T8: hogar archived — RPC → P0002 'Not Found' (A-5); bypass en archived COMMIT OK ──

do $$
declare v_n bigint;
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000978', true);
    begin
        perform set_home_membership_role(994003, 994107, 'member');
        raise exception 'membership_check: T8 set_role sobre archived no falló';
    exception
        when sqlstate 'P0002' then
            if sqlerrm <> 'Not Found' then
                raise exception 'membership_check: T8 mensaje % (esperado Not Found)', sqlerrm;
            end if;
    end;
    begin
        perform remove_home_membership(994003, 994107);
        raise exception 'membership_check: T8 remove sobre archived no falló';
    exception
        when sqlstate 'P0002' then
            if sqlerrm <> 'Not Found' then
                raise exception 'membership_check: T8 mensaje % (esperado Not Found)', sqlerrm;
            end if;
    end;
    raise notice 'ok T8 RPC sobre hogar archived → Not Found (A-5)';
end $$;

begin;
update home_membership set role = 'member' where id = 994107;
commit;

do $$
begin
    if (select role from home_membership where id = 994107) <> 'member' then
        raise exception 'membership_check: T8 el bypass en archived no llegó a COMMIT';
    end if;
    raise notice 'ok T8 bypass en hogar archived: COMMIT correcto (trigger 0015 lo ignora)';
end $$;

-- ── §6.1 T6: transfer atómico — éxito (target admin, caller member + legacy17) y fallo sin
-- cambios (target de otro hogar → P0002; T7: transfer a sí mismo → P0001 'Invalid membership') ──

do $$
declare v jsonb; v_n bigint; v_pre text;
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000971', true);
    v := transfer_home_admin(994001, 994102)::jsonb;
    if (v->>'from_membership_id')::bigint <> 994101 or (v->>'to_membership_id')::bigint <> 994102 then
        raise exception 'membership_check: T6 transfer_home_admin → %', v;
    end if;
    if (select role from home_membership where id = 994102) <> 'admin'
       or (select role from home_membership where id = 994101) <> 'member' then
        raise exception 'membership_check: T6 roles sin transferir (target/caller)';
    end if;
    select count(*) into v_n from membership_permission where home_membership_id = 994102;
    if v_n <> 0 then
        raise exception 'membership_check: T6 el target promovido conserva snapshot (% filas)', v_n;
    end if;
    select count(*) into v_n from membership_permission where home_membership_id = 994101;
    if v_n <> 17 then
        raise exception 'membership_check: T6 el caller degradado sin legacy17 (% filas)', v_n;
    end if;
    raise notice 'ok T6 transfer atómico: target admin, caller member con legacy17';
end $$;

do $$
declare v_n bigint;
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000972', true);
    begin
        perform transfer_home_admin(994001, 994102);  -- T7: a la propia membresía
        raise exception 'membership_check: T7 transfer a sí mismo no falló';
    exception
        when sqlstate 'P0001' then
            if sqlerrm <> 'Invalid membership' then
                raise exception 'membership_check: T7 mensaje % (esperado Invalid membership)', sqlerrm;
            end if;
    end;
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000972', true);
    begin
        perform transfer_home_admin(994001, 994106);  -- T6 fallo: membership de otro hogar
        raise exception 'membership_check: T6 transfer con target de otro hogar no falló';
    exception
        when sqlstate 'P0002' then
            if sqlerrm <> 'Not Found' then
                raise exception 'membership_check: T6 fallo, mensaje % (esperado Not Found)', sqlerrm;
            end if;
    end;
    -- T6: 0 cambios (roles y conteos iguales al estado previo)
    if (select role from home_membership where id = 994102) <> 'admin'
       or (select role from home_membership where id = 994101) <> 'member' then
        raise exception 'membership_check: T6 el fallo sí cambió roles';
    end if;
    select count(*) into v_n from home_membership where home_id = 994001;
    if v_n <> 4 or (select count(*) from membership_permission mp
                    join home_membership hm on hm.id = mp.home_membership_id
                    where hm.home_id = 994001) <> 17 + 17 + 17 then
        raise exception 'membership_check: T6 el fallo sí cambió conteos';
    end if;
    raise notice 'ok T6/T7: transfer a sí mismo → Invalid membership; target de otro hogar → Not Found, 0 cambios';
end $$;

-- Restauración: u1 vuelve a ser admin (u2 queda member con legacy17)
do $$
declare v jsonb;
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000972', true);
    v := transfer_home_admin(994001, 994101)::jsonb;
    if (v->>'from_membership_id')::bigint <> 994102 or (v->>'to_membership_id')::bigint <> 994101 then
        raise exception 'membership_check: restauración transfer → %', v;
    end if;
    if (select role from home_membership where id = 994101) <> 'admin'
       or (select role from home_membership where id = 994102) <> 'member' then
        raise exception 'membership_check: restauración de roles falló';
    end if;
    raise notice 'ok restauración: u1 admin, u2 member';
end $$;

-- ── §6.1 T12: expulsar — member → 42501; no miembro → P0002; membership de otro hogar → P0002 ──

do $$
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000972', true);
    begin
        perform remove_home_membership(994001, 994103);  -- u2 (member) expulsa a u3
        raise exception 'membership_check: T12 expulsión por member no falló';
    exception
        when sqlstate '42501' then
            if sqlerrm <> 'Not Allowed' then
                raise exception 'membership_check: T12 mensaje % (esperado Not Allowed)', sqlerrm;
            end if;
    end;
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000977', true);
    begin
        perform remove_home_membership(994001, 994103);  -- u7 no miembro de MC Hogar A
        raise exception 'membership_check: T12 remove por no miembro no falló';
    exception
        when sqlstate 'P0002' then
            if sqlerrm <> 'Not Found' then
                raise exception 'membership_check: T12 mensaje % (esperado Not Found)', sqlerrm;
            end if;
    end;
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000971', true);
    begin
        perform remove_home_membership(994001, 994106);  -- membership de MC Hogar B
        raise exception 'membership_check: T12 remove con membership de otro hogar no falló';
    exception
        when sqlstate 'P0002' then
            if sqlerrm <> 'Not Found' then
                raise exception 'membership_check: T12 mensaje % (esperado Not Found)', sqlerrm;
            end if;
    end;
    raise notice 'ok T12: member expulsa → Not Allowed; no miembro → Not Found; membership ajena → Not Found';
end $$;

-- ── §6.1 T10: bloqueos — último admin (salir/expulsar), owner único, último hogar ──

do $$
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000975', true);
    begin
        perform remove_home_membership(994002, 994105);  -- u5 sale siendo el último admin
        raise exception 'membership_check: T10 salida del último admin no falló';
    exception
        when sqlstate '42501' then
            if sqlerrm <> 'Not Allowed' then
                raise exception 'membership_check: T10 mensaje % (esperado Not Allowed)', sqlerrm;
            end if;
    end;
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000976', true);
    begin
        perform remove_home_membership(994002, 994105);  -- u6 (member) expulsa al último admin
        raise exception 'membership_check: T10 expulsión del último admin no falló';
    exception
        when sqlstate '42501' then
            if sqlerrm <> 'Not Allowed' then
                raise exception 'membership_check: T10 mensaje % (esperado Not Allowed)', sqlerrm;
            end if;
    end;
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000974', true);
    begin
        perform remove_home_membership(994001, 994104);  -- u4 es owner único de MC-Cal-U4
        raise exception 'membership_check: T10 salida del owner único no falló';
    exception
        when sqlstate '42501' then
            if sqlerrm <> 'Not Allowed' then
                raise exception 'membership_check: T10 mensaje % (esperado Not Allowed)', sqlerrm;
            end if;
    end;
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000976', true);
    begin
        perform remove_home_membership(994002, 994106);  -- u6: MC Hogar B es su único hogar
        raise exception 'membership_check: T10 salida del último hogar no falló';
    exception
        when sqlstate '42501' then
            if sqlerrm <> 'Not Allowed' then
                raise exception 'membership_check: T10 mensaje % (esperado Not Allowed)', sqlerrm;
            end if;
    end;
    if (select role from home_membership where id = 994105) <> 'admin'
       or (select role from home_membership where id = 994104) <> 'member'
       or (select role from home_membership where id = 994106) <> 'member' then
        raise exception 'membership_check: T10 los bloqueos cambiaron estado';
    end if;
    raise notice 'ok T10: último admin (salir/expulsar), owner único y último hogar → Not Allowed';
end $$;

-- ── §6.1 T13 + T9: Q4 (baja soft no revoca) y salida propia con cascadas ──

do $$
declare v jsonb; v_n bigint;
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000971', true);
    -- T13: PATCH /home/member/update status=inactive (RPC update_home_member) no revoca la membresía
    v := update_home_member(994001, null, null, null, 'inactive')::jsonb;
    if v->>'status' <> 'inactive' or (v->>'linked')::bool <> true then
        raise exception 'membership_check: T13 update_home_member status inactive → %', v;
    end if;
    v := get_home_memberships(994001)::jsonb;
    if not exists (select 1 from jsonb_array_elements(v) e where (e->>'membership_id')::bigint = 994103) then
        raise exception 'membership_check: T13 la baja soft revocó la membresía: %', v;
    end if;
    raise notice 'ok T13: status=inactive conserva la membresía en GET /home/membership';
end $$;

do $$
declare v jsonb; v_n bigint; v_status text; v_linked text;
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000973', true);
    -- T9: u3 sale de MC Hogar A por su cuenta
    v := remove_home_membership(994001, 994103)::jsonb;
    if v::text <> '{"success": true}' and v::text <> '{"success":true}' then
        raise exception 'membership_check: T9 remove_home_membership → %', v;
    end if;
    -- ACL del hogar borradas (cascade FK compuesta) y membership_permission borrada
    select count(*) into v_n from calendar_user where home_id = 994001 and user_id = 994003;
    if v_n <> 0 then
        raise exception 'membership_check: T9 quedan ACL de calendario de u3 (% filas)', v_n;
    end if;
    select count(*) into v_n from task_list_user where home_id = 994001 and user_id = 994003;
    if v_n <> 0 then
        raise exception 'membership_check: T9 quedan ACL de lista de u3 (% filas)', v_n;
    end if;
    select count(*) into v_n from membership_permission where home_membership_id = 994103;
    if v_n <> 0 then
        raise exception 'membership_check: T9 quedan permisos de la membresía borrada (% filas)', v_n;
    end if;
    -- home_member conservado, sin cuenta (SET NULL), con el status intacto (T13)
    select coalesce(app_user_id::text, 'null'), status::text into v_linked, v_status
      from home_member where id = 994001;
    if v_linked <> 'null' or v_status <> 'inactive' then
        raise exception 'membership_check: T9 home_member linked=% status=% (esperado null/inactive)',
            v_linked, v_status;
    end if;
    if (select default_home_id from app_user where id = 994003) <> 994004 then
        raise exception 'membership_check: T9 default_home_id sin reasignar a MC Hogar D';
    end if;
    raise notice 'ok T9 salir: ACL y permisos borrados, home_member conservado sin cuenta, default reasignado';
end $$;

-- ── §6.1 T11: default_home_id — personal primero; si no, el de menor joined_at ──

do $$
declare v jsonb;
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000979', true);
    -- T11a: u9 sale de MC Hogar E (default) → MC Hogar D (is_personal, aunque joined más tarde)
    v := remove_home_membership(994005, 994113)::jsonb;
    if (select default_home_id from app_user where id = 994009) <> 994004 then
        raise exception 'membership_check: T11a default ≠ MC Hogar D (personal)';
    end if;
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000980', true);
    -- T11b: u10 sale de MC Hogar F (default) → MC Hogar H (menor joined_at 2000-01-01, no el menor id)
    v := remove_home_membership(994006, 994115)::jsonb;
    if (select default_home_id from app_user where id = 994010) <> 994008 then
        raise exception 'membership_check: T11b default ≠ MC Hogar H (menor joined_at)';
    end if;
    raise notice 'ok T11: default = hogar personal si lo hay; si no, el de menor joined_at';
end $$;

-- ── §6.1 T14: home_role en get_*_users (= rol en home_membership del hogar del recurso) y
-- add_*_user con exactamente la plantilla USER (sin home_role, D-008) ──

do $$
declare v jsonb; e jsonb; v_keys text; v_role text;
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000971', true);
    v := get_calendar_users(994001)::jsonb;
    for e in select * from jsonb_array_elements(v) loop
        select hm.role::text into v_role from home_membership hm
         where hm.home_id = 994001 and hm.app_user_id = (e->>'user_id')::bigint;
        if e->>'home_role' is distinct from v_role then
            raise exception 'membership_check: T14 home_role de get_calendar_users (%) ≠ home_membership (%)',
                e->>'home_role', v_role;
        end if;
    end loop;
    v := get_task_list_users(994001)::jsonb;
    for e in select * from jsonb_array_elements(v) loop
        select hm.role::text into v_role from home_membership hm
         where hm.home_id = 994001 and hm.app_user_id = (e->>'user_id')::bigint;
        if e->>'home_role' is distinct from v_role then
            raise exception 'membership_check: T14 home_role de get_task_list_users (%) ≠ home_membership (%)',
                e->>'home_role', v_role;
        end if;
    end loop;
    v := add_calendar_user(994001, 'mc-u4@check.homita.example')::jsonb;
    select string_agg(k, ',' order by k) into v_keys from jsonb_object_keys(v) k;
    if v_keys <> 'created_at,email,id,name,updated_at' then
        raise exception 'membership_check: T14 add_calendar_user claves % (esperado USER sin home_role)', v_keys;
    end if;
    v := add_task_list_user(994001, 'mc-u4@check.homita.example')::jsonb;
    select string_agg(k, ',' order by k) into v_keys from jsonb_object_keys(v) k;
    if v_keys <> 'created_at,email,id,name,updated_at' then
        raise exception 'membership_check: T14 add_task_list_user claves % (esperado USER sin home_role)', v_keys;
    end if;
    raise notice 'ok T14: home_role = rol de home_membership; USER sin home_role en add_*_user';
end $$;

-- ── §6.1 T15: RPC directa con nulos — 'Invalid role' P0001 / 'Not Found' P0002; sin cambios ──

do $$
declare v_pre text; v_post text;
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000971', true);
    select string_agg(id || ':' || role::text, ',' order by id) into v_pre
      from home_membership where home_id = 994001;
    begin
        perform set_home_membership_role(994001, 994102, null);
        raise exception 'membership_check: T15 set_role con p_role null no falló';
    exception
        when sqlstate 'P0001' then
            if sqlerrm <> 'Invalid role' then
                raise exception 'membership_check: T15 mensaje % (esperado Invalid role)', sqlerrm;
            end if;
    end;
    begin
        perform set_home_membership_role(994001, null, 'member');
        raise exception 'membership_check: T15 set_role con p_membership_id null no falló';
    exception
        when sqlstate 'P0002' then
            if sqlerrm <> 'Not Found' then
                raise exception 'membership_check: T15 mensaje % (esperado Not Found)', sqlerrm;
            end if;
    end;
    begin
        perform transfer_home_admin(994001, null);
        raise exception 'membership_check: T15 transfer con p_to_membership_id null no falló';
    exception
        when sqlstate 'P0002' then
            if sqlerrm <> 'Not Found' then
                raise exception 'membership_check: T15 mensaje % (esperado Not Found)', sqlerrm;
            end if;
    end;
    begin
        perform remove_home_membership(994001, null);
        raise exception 'membership_check: T15 remove con p_membership_id null no falló';
    exception
        when sqlstate 'P0002' then
            if sqlerrm <> 'Not Found' then
                raise exception 'membership_check: T15 mensaje % (esperado Not Found)', sqlerrm;
            end if;
    end;
    select string_agg(id || ':' || role::text, ',' order by id) into v_post
      from home_membership where home_id = 994001;
    if v_post is distinct from v_pre then
        raise exception 'membership_check: T15 los nulos cambiaron estado (% → %)', v_pre, v_post;
    end if;
    raise notice 'ok T15: nulos → Invalid role/Not Found, ninguna fila cambia';
end $$;

-- ── Limpieza de los datos scratch (una transacción: el trigger diferido ve hogares borrados) ──

begin;
delete from membership_permission where home_membership_id between 994101 and 994119;
delete from calendar_user where calendar_id in (994001, 994002);
delete from task_list_user where task_list_id = 994001;
delete from calendar where id in (994001, 994002);
delete from task_list where id = 994001;
delete from home_member where home_id between 994001 and 994008;
delete from home_membership where id between 994101 and 994119;
delete from home where id between 994001 and 994008;
delete from app_user where id between 994001 and 994010;
delete from auth.users where id between '00000000-0000-4000-8000-000000000971'
                                   and '00000000-0000-4000-8000-000000000980';
commit;

do $$
begin
    raise notice 'membership_check: T1–T4 y T6–T15 verdes (T5 en membership_concurrency.sh)';
end $$;
