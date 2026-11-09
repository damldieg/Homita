-- home_checks_schema.sql — V5a–V5g y V5i del plan 1.3 (CA-3…CA-9 y CA-12 de la spec 1.1) sobre el
-- esquema creado por 0012_home_schema.sql. Se ejecuta con psql JUSTO DESPUÉS de 0012 y ANTES de
-- 0013 (E3), o tras seed en E4 (estado 0001–0015 completo):
--   psql -v ON_ERROR_STOP=1 -f home_checks_schema.sql
-- Cada bloque DO emite 'ok V5x: …' o aborta con 'home_checks V5x: …'.
--
-- Cubre: V5a conteos del seed de catálogo (23/37/0, sin pet), V5b unicidad y check pet (23505/23514),
-- V5c FK home_member↔home_membership (23503) y ON DELETE SET NULL, V5d RLS/grants/revokes de
-- secuencias (42501), V5e fn_active_home_id (cabecera x-home-id), V5f permisos por rol (D-a:
-- P0002/42501) y V5g fn_home_for_root_create, V5i los 12 índices (8 de §5.D + 4 de §5.B).
--
-- Los casos V5b/V5c/V5f/V5g crean datos scratch propios (usuarios 990001+, hogares 990001+,
-- auth_uid 00000000-0000-4000-8000-0000000009xx) y los borran al final, para no tocar el estado
-- del seed ni del fixture. El alta scratch usa session_replication_role = replica SOLO para saltarse
-- la FK app_user→auth.users y el trigger 0014(a) (aquí no se prueba ese trigger: ver
-- home_checks_compat.sql V5j).

-- ── Preambulo scratch: usuarios 990001–990005 (sin hogar: lo gestionan los casos) ──

set session_replication_role = replica;
insert into auth.users (id, email, raw_user_meta_data) values
    ('00000000-0000-4000-8000-000000000901', 'v5-a@check.homita.example', '{"name":"V5-A"}'),
    ('00000000-0000-4000-8000-000000000902', 'v5-b@check.homita.example', '{"name":"V5-B"}'),
    ('00000000-0000-4000-8000-000000000903', 'v5-c@check.homita.example', '{"name":"V5-C"}'),
    ('00000000-0000-4000-8000-000000000904', 'v5-d@check.homita.example', '{"name":"V5-D"}'),
    ('00000000-0000-4000-8000-000000000905', 'v5-e@check.homita.example', '{"name":"V5-E"}')
on conflict (id) do nothing;
insert into app_user (id, auth_uid, name, email) values
    (990001, '00000000-0000-4000-8000-000000000901', 'V5-A', 'v5-a@check.homita.example'),
    (990002, '00000000-0000-4000-8000-000000000902', 'V5-B', 'v5-b@check.homita.example'),
    (990003, '00000000-0000-4000-8000-000000000903', 'V5-C', 'v5-c@check.homita.example'),
    (990004, '00000000-0000-4000-8000-000000000904', 'V5-D', 'v5-d@check.homita.example'),
    (990005, '00000000-0000-4000-8000-000000000905', 'V5-E', 'v5-e@check.homita.example')
on conflict (id) do nothing;
set session_replication_role = default;

-- ── V5a (CA-3): seed de catálogo ──

do $$
declare
    v_n bigint;
    v_pet bigint;
    v_adult bigint;
    v_child bigint;
    v_rel bigint;
    v_guest bigint;
begin
    select count(*) into v_n from permission;
    if v_n <> 23 then
        raise exception 'home_checks V5a: permission=% (esperado 23)', v_n;
    end if;
    select count(*), count(*) filter (where kind = 'adult'), count(*) filter (where kind = 'child'),
           count(*) filter (where kind = 'relative'), count(*) filter (where kind = 'guest'),
           count(*) filter (where kind = 'pet')
      into v_n, v_adult, v_child, v_rel, v_guest, v_pet from member_kind_default;
    if v_n <> 37 then
        raise exception 'home_checks V5a: member_kind_default=% (esperado 37)', v_n;
    end if;
    -- desglose A-7: adult 18, child 6, relative 10, guest 3
    if v_adult <> 18 or v_child <> 6 or v_rel <> 10 or v_guest <> 3 then
        raise exception 'home_checks V5a: desglose (adult %, child %, relative %, guest %) ≠ (18, 6, 10, 3)',
            v_adult, v_child, v_rel, v_guest;
    end if;
    if v_pet <> 0 then
        raise exception 'home_checks V5a: member_kind_default con kind=pet (%), el seed no lleva pet', v_pet;
    end if;
    select count(*) into v_n from membership_permission;
    if v_n <> 0 then
        raise exception 'home_checks V5a: membership_permission=% (esperado 0 tras 0012)', v_n;
    end if;
    raise notice 'ok V5a: permission=23, member_kind_default=37 (adult 18/child 6/relative 10/guest 3), membership_permission=0, pet=0';
end $$;

-- ── V5b (CA-4): unicidad (h,u) y check pet sin cuenta ──

begin;
insert into home (id, name, status, is_personal, created_by) values (990001, 'V5 Hogar Uno', 'active', false, 990001);
insert into home_membership (home_id, app_user_id, role) values (990001, 990001, 'admin');
commit;

do $$
begin
    begin
        insert into home_membership (home_id, app_user_id, role) values (990001, 990001, 'member');
        raise exception 'home_checks V5b: home_membership duplicada (h,u) no falló';
    exception
        when unique_violation then
            raise notice 'ok V5b: home_membership duplicada (h,u) → 23505';
    end;
    begin
        insert into home_member (home_id, kind, name, app_user_id) values (990001, 'pet', 'V5-Mascota', 990001);
        raise exception 'home_checks V5b: home_member pet con app_user_id no falló';
    exception
        when check_violation then
            raise notice 'ok V5b: home_member kind=pet con cuenta → 23514';
    end;
end $$;

-- ── V5c (CA-5): FK home_member↔home_membership y ON DELETE SET NULL (home archived: fuera del
-- invariante anti-admin, también en E4 con 0015 aplicado) ──

begin;
insert into home (id, name, status, is_personal, created_by) values (990003, 'V5 Hogar Tres', 'archived', false, 990001);
insert into home_membership (home_id, app_user_id, role) values (990003, 990004, 'member');
insert into home_member (id, home_id, kind, name, app_user_id, created_by)
    values (990003, 990003, 'adult', 'V5-Miembro', 990004, 990001);
commit;

do $$
declare
    v_app_user bigint;
    v_home bigint;
    v_kind member_kind;
    v_name text;
begin
    delete from home_membership where home_id = 990003 and app_user_id = 990004;
    select app_user_id, home_id, kind, name into v_app_user, v_home, v_kind, v_name
    from home_member where id = 990003;
    if v_app_user is not null or v_home <> 990003 or v_kind <> 'adult' or v_name <> 'V5-Miembro' then
        raise exception 'home_checks V5c: home_member tras borrar membresía = (%, %, %, %)',
            v_app_user, v_home, v_kind, v_name;
    end if;
    begin
        insert into home_member (home_id, kind, name, app_user_id) values (990003, 'adult', 'V5-Sin-Membresia', 990005);
        raise exception 'home_checks V5c: home_member (h,x) sin membresía (h,x) no falló';
    exception
        when foreign_key_violation then
            raise notice 'ok V5c: ON DELETE SET NULL conserva home_id/kind/name y FK sin membresía → 23503';
    end;
end $$;

-- ── V5d (CA-6, R1-01 1.1): RLS, grants y revokes (D-b secuencias) ──

do $$
begin
    begin
        set local role authenticated;
        perform 1 from home limit 1;
        raise exception 'home_checks V5d: authenticated puede leer home';
    exception
        when insufficient_privilege then
            raise notice 'ok V5d: set role authenticated; select * from home → 42501';
    end;
    reset role;
    if exists (select 1 from information_schema.role_table_grants
               where table_schema = 'public' and grantee in ('anon', 'authenticated')
                 and table_name in ('home', 'home_membership', 'home_member', 'permission',
                                    'member_kind_default', 'membership_permission', 'audit_log')) then
        raise exception 'home_checks V5d: hay grants de anon/authenticated sobre las 7 tablas nuevas';
    end if;
    if exists (select 1 from pg_class c
               join pg_namespace n on n.oid = c.relnamespace
               where n.nspname = 'public' and c.relkind = 'S'
                 and c.relname in ('home_id_seq', 'home_membership_id_seq', 'home_member_id_seq', 'audit_log_id_seq')
                 and (has_sequence_privilege('anon', c.oid, 'USAGE')
                      or has_sequence_privilege('anon', c.oid, 'SELECT')
                      or has_sequence_privilege('anon', c.oid, 'UPDATE')
                      or has_sequence_privilege('authenticated', c.oid, 'USAGE')
                      or has_sequence_privilege('authenticated', c.oid, 'SELECT')
                      or has_sequence_privilege('authenticated', c.oid, 'UPDATE'))) then
        raise exception 'home_checks V5d: secuencias nuevas con grants a anon/authenticated (D-b)';
    end if;
    raise notice 'ok V5d: sin grants de tablas ni secuencias para anon/authenticated';
end $$;

-- ── V5e (CA-7): fn_active_home_id y cabecera x-home-id ──

do $$
declare
    v bigint;
begin
    perform set_config('request.headers', '{"x-home-id":"7"}', true);
    v := fn_active_home_id();
    if v <> 7 then
        raise exception 'home_checks V5e: fn_active_home_id()=% (esperado 7)', v;
    end if;
    perform set_config('request.headers', '{}', true);
    if fn_active_home_id() is not null then
        raise exception 'home_checks V5e: sin x-home-id debe devolver NULL';
    end if;
    perform set_config('request.headers', '{"x-home-id":""}', true);
    if fn_active_home_id() is not null then
        raise exception 'home_checks V5e: x-home-id vacío debe devolver NULL';
    end if;
    perform set_config('request.headers', '{"x-home-id":"abc"}', true);
    begin
        perform fn_active_home_id();
        raise exception 'home_checks V5e: x-home-id ''abc'' no falló';
    exception
        when sqlstate 'P0001' then
            if sqlerrm <> 'Invalid home' then
                raise exception 'home_checks V5e: mensaje % (esperado Invalid home)', sqlerrm;
            end if;
    end;
    raise notice 'ok V5e: fn_active_home_id (7 / NULL / Invalid home P0001)';
end $$;

-- ── V5f (CA-8, D-a): fn_has_permission / fn_require_member / fn_require_permission ──

begin;
insert into home (id, name, status, is_personal, created_by) values (990004, 'V5 Hogar Cuatro', 'active', false, 990001);
insert into home_membership (home_id, app_user_id, role) values (990004, 990001, 'admin');
insert into home_membership (home_id, app_user_id, role) values (990004, 990002, 'member');
insert into membership_permission (home_membership_id, permission_code)
    select id, 'task.create' from home_membership where home_id = 990004 and app_user_id = 990002;
commit;

do $$
declare
    v bigint;
begin
    -- admin sin filas en membership_permission → todo true por rol
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000901', true);
    select count(*) into v from membership_permission mp
    join home_membership hm on hm.id = mp.home_membership_id
    where hm.home_id = 990004 and hm.app_user_id = 990001;
    if v <> 0 then
        raise exception 'home_checks V5f: admin con % filas membership_permission', v;
    end if;
    if not fn_has_permission(990004, 'routine.delete') then
        raise exception 'home_checks V5f: admin sin permisos debe tener routine.delete';
    end if;
    -- member con solo task.create
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000902', true);
    if not fn_has_permission(990004, 'task.create') then
        raise exception 'home_checks V5f: member con task.create no lo tiene';
    end if;
    if fn_has_permission(990004, 'task.delete') then
        raise exception 'home_checks V5f: member sin task.delete no debe tenerlo';
    end if;
    -- no miembro: D-a → 'Not Found' P0002 (nunca 'Not Allowed')
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000903', true);
    begin
        perform fn_require_member(990004);
        raise exception 'home_checks V5f: fn_require_member no falló para no miembro';
    exception
        when sqlstate 'P0002' then
            if sqlerrm <> 'Not Found' then
                raise exception 'home_checks V5f: fn_require_member mensaje % (esperado Not Found)', sqlerrm;
            end if;
    end;
    begin
        perform fn_require_permission(990004, 'task.view');
        raise exception 'home_checks V5f: fn_require_permission no falló para no miembro';
    exception
        when sqlstate 'P0002' then
            if sqlerrm <> 'Not Found' then
                raise exception 'home_checks V5f: fn_require_permission mensaje % (esperado Not Found)', sqlerrm;
            end if;
    end;
    raise notice 'ok V5f: admin sin permisos=true, member (task.create ✓ / task.delete ✗), no miembro → Not Found P0002';
end $$;

-- ── V5g (CA-9): fn_home_for_root_create ──

begin;
insert into home (id, name, status, is_personal, created_by) values (990005, 'V5 Hogar Cinco', 'archived', false, 990001);
insert into home (id, name, status, is_personal, created_by) values (990006, 'V5 Hogar Seis', 'archived', false, 990001);
insert into home_membership (home_id, app_user_id, role) values (990005, 990004, 'member');
insert into home_membership (home_id, app_user_id, role) values (990006, 990004, 'member');
commit;

do $$
declare
    v bigint;
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000904', true);
    begin
        perform fn_home_for_root_create();
        raise exception 'home_checks V5g: 2 membresías sin default debe fallar';
    exception
        when sqlstate 'P0001' then
            if sqlerrm <> 'Home header required' then
                raise exception 'home_checks V5g: mensaje % (esperado Home header required)', sqlerrm;
            end if;
    end;
    delete from home_membership where home_id = 990005 and app_user_id = 990004;
    v := fn_home_for_root_create();
    if v <> 990006 then
        raise exception 'home_checks V5g: fn_home_for_root_create()=% (esperado 990006)', v;
    end if;
    raise notice 'ok V5g: 2 membresías → ''Home header required'' P0001; 1 membresía sin default → esa';
end $$;

-- ── V5i (CA-12): los 12 índices (8 de §5.D + 4 de §5.B) ──

do $$
declare
    v_missing text;
begin
    select string_agg(x.name, ', ') into v_missing
    from (values
        ('home_membership_app_user_idx'), ('home_member_linked_key'), ('home_member_home_idx'),
        ('audit_log_home_created_idx'), ('calendar_home_idx'), ('task_list_home_idx'),
        ('calendar_user_user_idx'), ('task_list_user_user_idx'), ('event_calendar_date_idx'),
        ('task_task_list_idx'), ('routine_calendar_idx'), ('person_home_idx')
    ) as x(name)
    where not exists (select 1 from pg_indexes i
                      where i.schemaname = 'public' and i.indexname = x.name);
    if v_missing is not null then
        raise exception 'home_checks V5i: faltan índices: %', v_missing;
    end if;
    raise notice 'ok V5i: los 12 índices (8 §5.D + 4 §5.B) presentes en pg_indexes';
end $$;

-- ── Limpieza scratch (una transacción: borrados + homes, el anti-admin diferido no ve hogares) ──

do $$
begin
    set local session_replication_role = replica;
    delete from membership_permission where home_membership_id in
        (select id from home_membership where home_id in (990001, 990003, 990004, 990005, 990006)
            or app_user_id in (990001, 990002, 990003, 990004, 990005));
    delete from home_membership where home_id in (990001, 990003, 990004, 990005, 990006)
        or app_user_id in (990001, 990002, 990003, 990004, 990005);
    delete from home_member where home_id in (990001, 990003, 990004, 990005, 990006);
    delete from audit_log where home_id in (990001, 990003, 990004, 990005, 990006);
    delete from home where id in (990001, 990003, 990004, 990005, 990006);
    delete from app_user where id in (990001, 990002, 990003, 990004, 990005);
    delete from auth.users where id in (
        '00000000-0000-4000-8000-000000000901', '00000000-0000-4000-8000-000000000902',
        '00000000-0000-4000-8000-000000000903', '00000000-0000-4000-8000-000000000904',
        '00000000-0000-4000-8000-000000000905');
    set local session_replication_role = default;
end $$;
