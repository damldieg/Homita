-- permisos_kind_check.sql — Permisos granulares por kind de 0019 (fase 1.7, T3; plan §6.1 P1–P11).
-- Se ejecuta con psql tras aplicar 0019 sobre 0001–0018 (sin dependencias de la Edge):
--   psql -v ON_ERROR_STOP=1 -f permisos_kind_check.sql
-- Cada bloque DO emite 'ok P…' o aborta con 'permisos_kind_check: …'. Impersonación vía
-- set_config('request.jwt.claim.sub', …, true) (auth.uid() → fn_my_user_id).
--
-- Cubre (§6.1): P1 catálogo 23/37 y conjuntos exactos por kind (§5.5, collate "C"); P2 adult
-- (18 filas, task.delete=true, home.view=false); P3 child (task.create=true, task.delete=false,
-- home.view=true); P4 relative (task.assign=true, event.edit=true, event.delete=false,
-- event.assign=false); P5 guest (task.complete=true, task.create=false); P6 reemplazo
-- adult→guest = 3 filas sin residuos; P7 pet/null → 'Invalid member' P0001, membership_id null
-- → 'Not Found' P0002, snapshot sin cambios (R1-01); P8 admin: fn_has_permission = true en los
-- 23 códigos sin filas (A4) y el helper rechaza admin ('Not Allowed' 42501) y membresía
-- inexistente ('Not Found' P0002) (R1-02); P9 ACL inmutable (md5 de calendar_user y
-- task_list_user idénticos tras cada seed); P10 las aserciones de 0019 abortan sin persistir;
-- P11 orden de locks home → home_membership → membership_permission, sin app_user.
--
-- Nota P10 (interpretación): las aserciones reales de 0019 viven en el fichero de migración y
-- psql corre dentro de docker sin ver los ficheros del host, así que aquí se ejecuta una COPIA
-- LITERAL de ese bloque contra estados corruptos dentro de subtransacciones (el rollback de la
-- subtransacción revierte la corrupción = "sin persistir"). La verificación runner-level del
-- fichero real (`psql -1` con corrupción + 0019 → abort sin persistir) forma parte de la batería
-- de este change (ver verificacion.md).
--
-- Datos scratch (usuarios 996001–996002, auth_uid 00000000-0000-4000-8000-000000000986–0987,
-- hogar 996001, membresías 996101–996102, calendario/lista 996001) borrados al final. El alta
-- scratch usa session_replication_role = replica SOLO para saltarse la FK app_user→auth.users
-- (mismo patrón que membership_check.sql).

begin;
set session_replication_role = replica;
insert into auth.users (id, email, raw_user_meta_data) values
    ('00000000-0000-4000-8000-000000000986', 'pk-u1@check.homita.example', '{"name": "PK-U1"}'),
    ('00000000-0000-4000-8000-000000000987', 'pk-u2@check.homita.example', '{"name": "PK-U2"}')
on conflict (id) do nothing;
insert into app_user (id, auth_uid, name, email) values
    (996001, '00000000-0000-4000-8000-000000000986', 'PK-U1', 'pk-u1@check.homita.example'),
    (996002, '00000000-0000-4000-8000-000000000987', 'PK-U2', 'pk-u2@check.homita.example')
on conflict (id) do nothing;
set session_replication_role = default;
insert into home (id, name, status, is_personal, created_by)
    values (996001, 'PK Hogar A', 'active', false, 996001);
insert into home_membership (id, home_id, app_user_id, role, joined_at) values
    (996101, 996001, 996001, 'admin', '2000-01-01 00:00:00'),
    (996102, 996001, 996002, 'member', '2000-01-02 00:00:00');
insert into calendar (id, name, color, token, home_id)
    values (996001, 'PK-Cal', '#123456', 'pk-cal', 996001);
insert into calendar_user (calendar_id, user_id, role, widget, dashboard, home_id) values
    (996001, 996001, 'owner', true, true, 996001),
    (996001, 996002, 'viewer', true, true, 996001);
insert into task_list (id, name, color, token, sort, home_id)
    values (996001, 'PK-Lista', '#654321', 'pk-lista', 'updated_at', 996001);
insert into task_list_user (task_list_id, user_id, role, widget, dashboard, home_id) values
    (996001, 996001, 'owner', true, true, 996001),
    (996001, 996002, 'viewer', true, true, 996001);
commit;

-- ── P1 (§6.1): catálogo y defaults contra las listas literales de §5.5 (collate "C") ──

do $$
declare v_n bigint; v_set text; v_exp text;
begin
    select count(*) into v_n from permission;
    if v_n <> 23 then
        raise exception 'permisos_kind_check: P1 permission = % (esperado 23)', v_n;
    end if;
    select count(*) into v_n from member_kind_default;
    if v_n <> 37 then
        raise exception 'permisos_kind_check: P1 member_kind_default = % (esperado 37)', v_n;
    end if;
    v_exp := array_to_string(array[
        'calendar.manage', 'calendar.view', 'event.assign', 'event.create', 'event.delete',
        'event.edit', 'routine.assign', 'routine.create', 'routine.delete', 'routine.edit',
        'routine.view', 'task.assign', 'task.complete', 'task.create', 'task.delete',
        'task.edit', 'task.view', 'tasklist.manage'], ',');
    select coalesce(string_agg(permission_code, ',' order by permission_code collate "C"), '')
      into v_set from member_kind_default where kind = 'adult';
    if v_set <> v_exp then
        raise exception 'permisos_kind_check: P1 adult ≠ §5.5 (%, esperado %)', v_set, v_exp;
    end if;
    v_exp := array_to_string(array[
        'calendar.view', 'home.view', 'routine.view', 'task.complete', 'task.create',
        'task.view'], ',');
    select coalesce(string_agg(permission_code, ',' order by permission_code collate "C"), '')
      into v_set from member_kind_default where kind = 'child';
    if v_set <> v_exp then
        raise exception 'permisos_kind_check: P1 child ≠ §5.5 (%, esperado %)', v_set, v_exp;
    end if;
    v_exp := array_to_string(array[
        'calendar.view', 'event.create', 'event.edit', 'home.view', 'routine.view',
        'task.assign', 'task.complete', 'task.create', 'task.edit', 'task.view'], ',');
    select coalesce(string_agg(permission_code, ',' order by permission_code collate "C"), '')
      into v_set from member_kind_default where kind = 'relative';
    if v_set <> v_exp then
        raise exception 'permisos_kind_check: P1 relative ≠ §5.5 (%, esperado %)', v_set, v_exp;
    end if;
    v_exp := array_to_string(array[
        'calendar.view', 'task.complete', 'task.view'], ',');
    select coalesce(string_agg(permission_code, ',' order by permission_code collate "C"), '')
      into v_set from member_kind_default where kind = 'guest';
    if v_set <> v_exp then
        raise exception 'permisos_kind_check: P1 guest ≠ §5.5 (%, esperado %)', v_set, v_exp;
    end if;
    select count(*) into v_n from member_kind_default where kind = 'pet';
    if v_n <> 0 then
        raise exception 'permisos_kind_check: P1 pet con % filas (esperado 0)', v_n;
    end if;
    raise notice 'ok P1 catálogo: 23/37 y conjuntos exactos por kind (§5.5)';
end $$;

-- ── P2 (§6.1): seed adult — 18 filas = member_kind_default, task.delete=true, home.view=false ──

do $$
declare v_n bigint; v_bad bigint;
begin
    perform fn_seed_kind_permissions(996102, 'adult');
    select count(*) into v_n from membership_permission where home_membership_id = 996102;
    select count(*) into v_bad from membership_permission
     where home_membership_id = 996102 and permission_code not in (
        'calendar.manage', 'calendar.view', 'event.assign', 'event.create', 'event.delete',
        'event.edit', 'routine.assign', 'routine.create', 'routine.delete', 'routine.edit',
        'routine.view', 'task.assign', 'task.complete', 'task.create', 'task.delete',
        'task.edit', 'task.view', 'tasklist.manage');
    if v_n <> 18 or v_bad <> 0 then
        raise exception 'permisos_kind_check: P2 snapshot ≠ adult (n=%, ajenos=%)', v_n, v_bad;
    end if;
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000987', true);
    if not fn_has_permission(996001, 'task.delete') then
        raise exception 'permisos_kind_check: P2 task.delete = false (esperado true)';
    end if;
    if fn_has_permission(996001, 'home.view') then
        raise exception 'permisos_kind_check: P2 home.view = true (esperado false)';
    end if;
    raise notice 'ok P2 adult: 18 filas = member_kind_default, task.delete=true, home.view=false';
end $$;

-- ── P3 (§6.1): seed child — task.create=true, task.delete=false, home.view=true ──

do $$
declare v_n bigint; v_bad bigint;
begin
    perform fn_seed_kind_permissions(996102, 'child');
    select count(*) into v_n from membership_permission where home_membership_id = 996102;
    select count(*) into v_bad from membership_permission
     where home_membership_id = 996102 and permission_code not in (
        'calendar.view', 'home.view', 'routine.view', 'task.complete', 'task.create', 'task.view');
    if v_n <> 6 or v_bad <> 0 then
        raise exception 'permisos_kind_check: P3 snapshot ≠ child (n=%, ajenos=%)', v_n, v_bad;
    end if;
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000987', true);
    if not fn_has_permission(996001, 'task.create') or not fn_has_permission(996001, 'home.view') then
        raise exception 'permisos_kind_check: P3 task.create/home.view = false (esperado true)';
    end if;
    if fn_has_permission(996001, 'task.delete') then
        raise exception 'permisos_kind_check: P3 task.delete = true (esperado false)';
    end if;
    raise notice 'ok P3 child: 6 filas, task.create=true, task.delete=false, home.view=true';
end $$;

-- ── P4 (§6.1): seed relative — task.assign=true, event.edit=true, event.delete=false ──

do $$
declare v_n bigint; v_bad bigint;
begin
    perform fn_seed_kind_permissions(996102, 'relative');
    select count(*) into v_n from membership_permission where home_membership_id = 996102;
    select count(*) into v_bad from membership_permission
     where home_membership_id = 996102 and permission_code not in (
        'calendar.view', 'event.create', 'event.edit', 'home.view', 'routine.view',
        'task.assign', 'task.complete', 'task.create', 'task.edit', 'task.view');
    if v_n <> 10 or v_bad <> 0 then
        raise exception 'permisos_kind_check: P4 snapshot ≠ relative (n=%, ajenos=%)', v_n, v_bad;
    end if;
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000987', true);
    if not fn_has_permission(996001, 'task.assign') or not fn_has_permission(996001, 'event.edit') then
        raise exception 'permisos_kind_check: P4 task.assign/event.edit = false (esperado true)';
    end if;
    if fn_has_permission(996001, 'event.delete') or fn_has_permission(996001, 'event.assign') then
        raise exception 'permisos_kind_check: P4 event.delete/event.assign = true (esperado false)';
    end if;
    raise notice 'ok P4 relative: 10 filas, task.assign=true, event.edit=true, event.delete=false, event.assign=false';
end $$;

-- ── P5 (§6.1): seed guest — task.complete=true, task.create=false ──

do $$
declare v_n bigint; v_bad bigint;
begin
    perform fn_seed_kind_permissions(996102, 'guest');
    select count(*) into v_n from membership_permission where home_membership_id = 996102;
    select count(*) into v_bad from membership_permission
     where home_membership_id = 996102 and permission_code not in (
        'calendar.view', 'task.complete', 'task.view');
    if v_n <> 3 or v_bad <> 0 then
        raise exception 'permisos_kind_check: P5 snapshot ≠ guest (n=%, ajenos=%)', v_n, v_bad;
    end if;
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000987', true);
    if not fn_has_permission(996001, 'task.complete') then
        raise exception 'permisos_kind_check: P5 task.complete = false (esperado true)';
    end if;
    if fn_has_permission(996001, 'task.create') then
        raise exception 'permisos_kind_check: P5 task.create = true (esperado false)';
    end if;
    raise notice 'ok P5 guest: 3 filas, task.complete=true, task.create=false';
end $$;

-- ── P6 (§6.1): idempotencia y reemplazo — adult → guest = 3 filas, sin residuos de adult ──

do $$
declare v_n bigint; v_bad bigint;
begin
    perform fn_seed_kind_permissions(996102, 'adult');
    perform fn_seed_kind_permissions(996102, 'guest');
    select count(*) into v_n from membership_permission where home_membership_id = 996102;
    select count(*) into v_bad from membership_permission
     where home_membership_id = 996102 and permission_code not in (
        'calendar.view', 'task.complete', 'task.view');
    if v_n <> 3 or v_bad <> 0 then
        raise exception 'permisos_kind_check: P6 reemplazo adult→guest ≠ 3 (n=%, ajenos=%)', v_n, v_bad;
    end if;
    raise notice 'ok P6 reemplazo: seed adult → seed guest = 3 filas exactas, sin residuos';
end $$;

-- ── P7 (§6.1 + R1-01): pet/null → 'Invalid member' P0001; membership_id null → P0002; sin cambios ──

do $$
declare v_pre text; v_post text;
begin
    select coalesce(string_agg(permission_code, ',' order by permission_code), '') into v_pre
      from membership_permission where home_membership_id = 996102;
    begin
        perform fn_seed_kind_permissions(996102, 'pet');
        raise exception 'permisos_kind_check: P7 pet no falló';
    exception
        when sqlstate 'P0001' then
            if sqlerrm <> 'Invalid member' then
                raise exception 'permisos_kind_check: P7 mensaje % (esperado Invalid member)', sqlerrm;
            end if;
    end;
    begin
        perform fn_seed_kind_permissions(996102, null::member_kind);
        raise exception 'permisos_kind_check: P7 p_kind null no falló';
    exception
        when sqlstate 'P0001' then
            if sqlerrm <> 'Invalid member' then
                raise exception 'permisos_kind_check: P7 mensaje % (esperado Invalid member)', sqlerrm;
            end if;
    end;
    begin
        perform fn_seed_kind_permissions(null, 'adult');
        raise exception 'permisos_kind_check: P7 membership_id null no falló';
    exception
        when sqlstate 'P0002' then
            if sqlerrm <> 'Not Found' then
                raise exception 'permisos_kind_check: P7 mensaje % (esperado Not Found)', sqlerrm;
            end if;
    end;
    select coalesce(string_agg(permission_code, ',' order by permission_code), '') into v_post
      from membership_permission where home_membership_id = 996102;
    if v_post is distinct from v_pre then
        raise exception 'permisos_kind_check: P7 los fallos cambiaron el snapshot (% → %)', v_pre, v_post;
    end if;
    raise notice 'ok P7: pet/null → Invalid member P0001, membership_id null → Not Found P0002, snapshot intacto';
end $$;

-- ── P8 (§6.1 + R1-02): admin = 23 códigos sin filas (A4) y el helper rechaza admin/inexistente ──

do $$
declare v_n bigint; v_code text;
begin
    -- R1-02: el helper rechaza una membresía admin → 'Not Allowed' 42501 (y sin filas)
    begin
        perform fn_seed_kind_permissions(996101, 'adult');
        raise exception 'permisos_kind_check: P8 el helper aceptó una membresía admin';
    exception
        when sqlstate '42501' then
            if sqlerrm <> 'Not Allowed' then
                raise exception 'permisos_kind_check: P8 mensaje % (esperado Not Allowed)', sqlerrm;
            end if;
    end;
    -- R1-02: membresía inexistente → 'Not Found' P0002
    begin
        perform fn_seed_kind_permissions(996999, 'adult');
        raise exception 'permisos_kind_check: P8 el helper aceptó una membresía inexistente';
    exception
        when sqlstate 'P0002' then
            if sqlerrm <> 'Not Found' then
                raise exception 'permisos_kind_check: P8 mensaje % (esperado Not Found)', sqlerrm;
            end if;
    end;
    select count(*) into v_n from membership_permission where home_membership_id = 996101;
    if v_n <> 0 then
        raise exception 'permisos_kind_check: P8 la admin quedó con % filas (esperado 0, A4)', v_n;
    end if;
    -- A4: fn_has_permission = true en los 23 códigos sin snapshot (sin llamar al helper)
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000986', true);
    for v_code in select code from permission order by code collate "C" loop
        if not fn_has_permission(996001, v_code) then
            raise exception 'permisos_kind_check: P8 admin sin % (esperado true)', v_code;
        end if;
    end loop;
    raise notice 'ok P8 admin: 23/23 con fn_has_permission=true y 0 filas; helper rechaza admin (42501) e inexistente (P0002)';
end $$;

-- ── P9 (§6.1): ACL inmutable — md5 de calendar_user y task_list_user idénticos tras cada seed ──

do $$
declare v_cu text; v_tu text;
begin
    select md5(coalesce(string_agg(cu.calendar_id || ':' || cu.user_id || ':' || cu.role::text,
                                   ',' order by cu.calendar_id, cu.user_id), ''))
      into v_cu from calendar_user cu where cu.home_id = 996001;
    select md5(coalesce(string_agg(tu.task_list_id || ':' || tu.user_id || ':' || tu.role::text,
                                   ',' order by tu.task_list_id, tu.user_id), ''))
      into v_tu from task_list_user tu where tu.home_id = 996001;
    perform fn_seed_kind_permissions(996102, 'adult');
    if v_cu <> (select md5(coalesce(string_agg(cu.calendar_id || ':' || cu.user_id || ':' || cu.role::text,
                                               ',' order by cu.calendar_id, cu.user_id), ''))
                  from calendar_user cu where cu.home_id = 996001)
       or v_tu <> (select md5(coalesce(string_agg(tu.task_list_id || ':' || tu.user_id || ':' || tu.role::text,
                                                  ',' order by tu.task_list_id, tu.user_id), ''))
                     from task_list_user tu where tu.home_id = 996001) then
        raise exception 'permisos_kind_check: P9 ACL tocada por el seed adult';
    end if;
    perform fn_seed_kind_permissions(996102, 'child');
    if v_cu <> (select md5(coalesce(string_agg(cu.calendar_id || ':' || cu.user_id || ':' || cu.role::text,
                                               ',' order by cu.calendar_id, cu.user_id), ''))
                  from calendar_user cu where cu.home_id = 996001)
       or v_tu <> (select md5(coalesce(string_agg(tu.task_list_id || ':' || tu.user_id || ':' || tu.role::text,
                                                  ',' order by tu.task_list_id, tu.user_id), ''))
                     from task_list_user tu where tu.home_id = 996001) then
        raise exception 'permisos_kind_check: P9 ACL tocada por el seed child';
    end if;
    perform fn_seed_kind_permissions(996102, 'guest');
    if v_cu <> (select md5(coalesce(string_agg(cu.calendar_id || ':' || cu.user_id || ':' || cu.role::text,
                                               ',' order by cu.calendar_id, cu.user_id), ''))
                  from calendar_user cu where cu.home_id = 996001)
       or v_tu <> (select md5(coalesce(string_agg(tu.task_list_id || ':' || tu.user_id || ':' || tu.role::text,
                                                  ',' order by tu.task_list_id, tu.user_id), ''))
                     from task_list_user tu where tu.home_id = 996001) then
        raise exception 'permisos_kind_check: P9 ACL tocada por el seed guest';
    end if;
    raise notice 'ok P9: calendar_user y task_list_user idénticos (md5) tras cada seed';
end $$;

-- ── P10 (§6.1): las aserciones de 0019 abortan sin persistir (copia literal + subtransacción) ──

do $$
declare v_ok boolean; v_n bigint; v_set text; v_exp text;
begin
    -- Corrupción 1: catálogo con 22 códigos (se revierte con la subtransacción)
    v_ok := false;
    begin
        delete from permission where code = 'home.permissions.manage';
        -- ── copia literal del bloque de aserciones de 0019 §3.2 ──
        select count(*) into v_n from permission;
        if v_n <> 23 then
            raise exception 'Aserción 0019: permission = % (esperado 23)', v_n;
        end if;
        select count(*) into v_n from member_kind_default;
        if v_n <> 37 then
            raise exception 'Aserción 0019: member_kind_default = % (esperado 37)', v_n;
        end if;
        v_exp := array_to_string(array[
            'calendar.manage', 'calendar.view', 'event.assign', 'event.create', 'event.delete',
            'event.edit', 'routine.assign', 'routine.create', 'routine.delete', 'routine.edit',
            'routine.view', 'task.assign', 'task.complete', 'task.create', 'task.delete',
            'task.edit', 'task.view', 'tasklist.manage'], ',');
        select coalesce(string_agg(permission_code, ',' order by permission_code collate "C"), '')
          into v_set from member_kind_default where kind = 'adult';
        if v_set <> v_exp then
            raise exception 'Aserción 0019: adult ≠ §5.5 (%, esperado %)', v_set, v_exp;
        end if;
        v_exp := array_to_string(array[
            'calendar.view', 'home.view', 'routine.view', 'task.complete', 'task.create',
            'task.view'], ',');
        select coalesce(string_agg(permission_code, ',' order by permission_code collate "C"), '')
          into v_set from member_kind_default where kind = 'child';
        if v_set <> v_exp then
            raise exception 'Aserción 0019: child ≠ §5.5 (%, esperado %)', v_set, v_exp;
        end if;
        v_exp := array_to_string(array[
            'calendar.view', 'event.create', 'event.edit', 'home.view', 'routine.view',
            'task.assign', 'task.complete', 'task.create', 'task.edit', 'task.view'], ',');
        select coalesce(string_agg(permission_code, ',' order by permission_code collate "C"), '')
          into v_set from member_kind_default where kind = 'relative';
        if v_set <> v_exp then
            raise exception 'Aserción 0019: relative ≠ §5.5 (%, esperado %)', v_set, v_exp;
        end if;
        v_exp := array_to_string(array[
            'calendar.view', 'task.complete', 'task.view'], ',');
        select coalesce(string_agg(permission_code, ',' order by permission_code collate "C"), '')
          into v_set from member_kind_default where kind = 'guest';
        if v_set <> v_exp then
            raise exception 'Aserción 0019: guest ≠ §5.5 (%, esperado %)', v_set, v_exp;
        end if;
        select count(*) into v_n from member_kind_default where kind = 'pet';
        if v_n <> 0 then
            raise exception 'Aserción 0019: pet con % filas (esperado 0)', v_n;
        end if;
        select count(*) into v_n
          from membership_permission mp
          join home_membership hm on hm.id = mp.home_membership_id
         where hm.role = 'admin';
        if v_n <> 0 then
            raise exception 'Aserción 0019: % filas de membership_permission en membresías admin (A4)', v_n;
        end if;
        -- fin de la copia literal
        raise exception 'permisos_kind_check: P10 las aserciones NO abortaron con permission = 22';
    exception
        when raise_exception then
            if sqlerrm like 'Aserción 0019:%' then
                v_ok := true;
            else
                raise;
            end if;
    end;
    if not v_ok then
        raise exception 'permisos_kind_check: P10 corrupción del catálogo sin abortar';
    end if;
    select count(*) into v_n from permission;
    if v_n <> 23 then
        raise exception 'permisos_kind_check: P10 la corrupción persistió (permission = %)', v_n;
    end if;

    -- Corrupción 2: conjunto guest alterado (fila extra) → la aserción de conjuntos aborta
    v_ok := false;
    begin
        insert into member_kind_default (kind, permission_code) values ('guest', 'task.create');
        v_exp := array_to_string(array[
            'calendar.view', 'task.complete', 'task.view'], ',');
        select coalesce(string_agg(permission_code, ',' order by permission_code collate "C"), '')
          into v_set from member_kind_default where kind = 'guest';
        if v_set <> v_exp then
            raise exception 'Aserción 0019: guest ≠ §5.5 (%, esperado %)', v_set, v_exp;
        end if;
        raise exception 'permisos_kind_check: P10 las aserciones NO abortaron con guest alterado';
    exception
        when raise_exception then
            if sqlerrm like 'Aserción 0019:%' then
                v_ok := true;
            else
                raise;
            end if;
    end;
    if not v_ok then
        raise exception 'permisos_kind_check: P10 corrupción de guest sin abortar';
    end if;
    select count(*) into v_n from member_kind_default where kind = 'guest';
    if v_n <> 3 then
        raise exception 'permisos_kind_check: P10 la corrupción de guest persistió (n=%)', v_n;
    end if;
    raise notice 'ok P10: las aserciones de 0019 abortan y la subtransacción revierte (sin persistir)';
end $$;

-- ── P11 (§6.1): orden de locks home → home_membership → membership_permission, sin app_user ──
-- Snapshots incrementales de pg_locks en la misma transacción (solo modos ≠ AccessShareLock: las
-- lecturas lockean en AccessShare y no son del invariante). Tras el guard de 0018 (FOR UPDATE de
-- home): solo home. Tras el seed: + home_membership (FK FOR KEY SHARE del insert) y
-- membership_permission (DELETE/INSERT). Sin locks sobre app_user (el orden de 0018 se respeta).

do $$
declare v_s1 text; v_s2 text;
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000986', true);
    perform fn_home_mutation_guard(996001);
    select coalesce(string_agg(relation::regclass::text || '/' || locktype || '/' || mode,
                               ',' order by 1), '')
      into v_s1 from pg_locks
     where pid = pg_backend_pid()
       and relation in ('home'::regclass, 'home_membership'::regclass,
                        'membership_permission'::regclass, 'app_user'::regclass)
       and mode <> 'AccessShareLock';
    perform fn_seed_kind_permissions(996102, 'child');
    select coalesce(string_agg(relation::regclass::text || '/' || locktype || '/' || mode,
                               ',' order by 1), '')
      into v_s2 from pg_locks
     where pid = pg_backend_pid()
       and relation in ('home'::regclass, 'home_membership'::regclass,
                        'membership_permission'::regclass, 'app_user'::regclass)
       and mode <> 'AccessShareLock';
    if v_s1 is null or v_s1 not like '%home/%'
       or v_s1 like '%membership_permission%' or v_s1 like '%home_membership%' then
        raise exception 'permisos_kind_check: P11 tras el guard, locks = % (esperado solo home)', v_s1;
    end if;
    if v_s2 is null or v_s2 not like '%home/%' or v_s2 not like '%home_membership/%'
       or v_s2 not like '%membership_permission/%' then
        raise exception 'permisos_kind_check: P11 tras el seed falta alguno de home/home_membership/membership_permission (%)', v_s2;
    end if;
    if v_s2 like '%app_user%' then
        raise exception 'permisos_kind_check: P11 el seed tomó locks sobre app_user (%)', v_s2;
    end if;
    raise notice 'ok P11 orden de locks: guard=home (%); seed=+% (home_membership + membership_permission, sin app_user)',
        v_s1, v_s2;
end $$;

-- ── Limpieza de los datos scratch (una transacción: el trigger diferido ve hogares borrados) ──

begin;
delete from membership_permission where home_membership_id in (996101, 996102);
delete from calendar_user where calendar_id = 996001;
delete from task_list_user where task_list_id = 996001;
delete from calendar where id = 996001;
delete from task_list where id = 996001;
delete from home_membership where id in (996101, 996102);
delete from home where id = 996001;
delete from app_user where id in (996001, 996002);
delete from auth.users where id in ('00000000-0000-4000-8000-000000000986',
                                    '00000000-0000-4000-8000-000000000987');
commit;

do $$
begin
    raise notice 'permisos_kind_check: P1–P11 verdes';
end $$;
