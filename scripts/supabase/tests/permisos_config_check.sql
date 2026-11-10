-- permisos_config_check.sql — Configuración de permisos y auditoría (fase 1.9, migración 0021).
-- Se ejecuta con psql DESPUÉS del reset 0001–0021 y la seed:
--   psql -v ON_ERROR_STOP=1 -f permisos_config_check.sql
-- Cada bloque DO emite 'ok Cx: …' o aborta con 'permisos_config Cx: …'.
--
-- C1 catálogo 23/defaults 37 y conjuntos por kind = oráculo BD; C2 memberships (admin = 23,
-- editable según llamante); C3 get sin home.view / no miembro / cabecera ajena; C4/C5 grant y
-- revoke efectivos vía fn_has_permission; C6 idempotente (0 escrituras, 0 audit); C7 [] revoca
-- todo; C8 target admin (A4) y 0 filas de admin; C9 member con home.permissions.manage → 403;
-- C10 member sin manage → 403; C11 membresía de otro hogar → 404 sin cambios; C12 código
-- inválido → Invalid permission con snapshot intacto; C13 shapes inválidos; C14 ids nulos;
-- C15 duplicados/orden en input; C16 fila de audit por código; C17 get_home_audit (id desc,
-- paginación before_id ≥3 páginas, clamp 0→1/1000→200/null→50, sin backfill.* (R1-01/R1-03),
-- member 403, no miembro 404, sin filas de otro hogar); C18 audit_log sin SELECT directo;
-- C19 cambio de kind → defaults del nuevo kind + audit kind_change; C20 admin vinculado →
-- kind cambia, 0 filas, 0 audit; C21 no-admin con manage cambia kind de vinculado → 403;
-- C22 no vinculado → sin reset ni audit; C23 solo name → permisos intactos; C24 promover borra
-- snapshot / degradar siembra legacy17; C25/C26 add_*_user doble → igual, 1 fila; C27/C28
-- remove_*_user contrato (último owner 403, self 400, viewer 403, owner con reemplazo ok);
-- C29 delete_* contrato; C30 proacl de las 11 funciones; C31 anon sin EXECUTE.
-- C32 no-admin con home.members.manage reenvía mismo kind + name → 200 sin reset ni audit.
--
-- Datos scratch 996xxx (usuarios auth_uid …0981–0986) borrados al final. Impersonación vía
-- set_config('request.jwt.claim.sub', …, true) (auth.uid()); cabecera X-Home-Id vía
-- set_config('request.headers', …, true) (fn_active_home_id).

-- ── Preambulo scratch: usuarios 996001–996006 ──

set session_replication_role = replica;
insert into auth.users (id, email, raw_user_meta_data) values
    ('00000000-0000-4000-8000-000000000981', 'pc-a@check.homita.example', '{"name":"PC-A"}'),
    ('00000000-0000-4000-8000-000000000982', 'pc-m@check.homita.example', '{"name":"PC-M"}'),
    ('00000000-0000-4000-8000-000000000983', 'pc-k@check.homita.example', '{"name":"PC-K"}'),
    ('00000000-0000-4000-8000-000000000984', 'pc-g@check.homita.example', '{"name":"PC-G"}'),
    ('00000000-0000-4000-8000-000000000985', 'pc-n@check.homita.example', '{"name":"PC-N"}'),
    ('00000000-0000-4000-8000-000000000986', 'pc-x@check.homita.example', '{"name":"PC-X"}')
on conflict (id) do nothing;
insert into app_user (id, auth_uid, name, email) values
    (996001, '00000000-0000-4000-8000-000000000981', 'PC-A', 'pc-a@check.homita.example'),
    (996002, '00000000-0000-4000-8000-000000000982', 'PC-M', 'pc-m@check.homita.example'),
    (996003, '00000000-0000-4000-8000-000000000983', 'PC-K', 'pc-k@check.homita.example'),
    (996004, '00000000-0000-4000-8000-000000000984', 'PC-G', 'pc-g@check.homita.example'),
    (996005, '00000000-0000-4000-8000-000000000985', 'PC-N', 'pc-n@check.homita.example'),
    (996006, '00000000-0000-4000-8000-000000000986', 'PC-X', 'pc-x@check.homita.example')
on conflict (id) do nothing;
set session_replication_role = default;

begin;
-- H (996001): A admin; M adult vinculada, K child vinculado, G guest vinculada con
-- home.permissions.manage + home.members.manage, N sin home.view. B (996002): X admin.
insert into home (id, name, status, is_personal, created_by) values
    (996001, 'PC-Hogar H', 'active', false, 996001),
    (996002, 'PC-Hogar B', 'active', false, 996006);
insert into home_membership (id, home_id, app_user_id, role) values
    (996001, 996001, 996001, 'admin'),
    (996002, 996001, 996002, 'member'),
    (996003, 996001, 996003, 'member'),
    (996004, 996001, 996004, 'member'),
    (996005, 996001, 996005, 'member'),
    (996006, 996002, 996006, 'admin');
update app_user set default_home_id = 996001 where id between 996001 and 996005;
update app_user set default_home_id = 996002 where id = 996006;
insert into home_member (id, home_id, kind, name, color, status, app_user_id) values
    (996001, 996001, 'adult', 'PC-Miembro', '#AA0000', 'active', 996002),
    (996002, 996001, 'child', 'PC-Nino', '#00AA00', 'active', 996003),
    (996003, 996001, 'adult', 'PC-SinCuenta', '#0000AA', 'active', null),
    (996004, 996001, 'adult', 'PC-AdminM', '#CC0000', 'active', 996001),
    (996005, 996001, 'guest', 'PC-Invitada', '#00CCCC', 'active', 996004);
commit;
select fn_seed_kind_permissions(996002, 'adult');
select fn_seed_kind_permissions(996003, 'child');
select fn_seed_kind_permissions(996004, 'guest');
begin;
insert into membership_permission (home_membership_id, permission_code) values
    (996004, 'home.permissions.manage'), (996004, 'home.members.manage'),
    (996005, 'task.view');
insert into calendar (id, name, color, token, home_id) values
    (996001, 'PC-C1', '#111111', 'pc-token-1', 996001),
    (996002, 'PC-C2', '#222222', 'pc-token-2', 996001);
insert into calendar_user (calendar_id, user_id, role, widget, dashboard, home_id) values
    (996001, 996001, 'owner', true, true, 996001),
    (996001, 996002, 'owner', true, true, 996001),
    (996001, 996003, 'viewer', true, true, 996001),
    (996001, 996004, 'viewer', true, true, 996001),
    (996002, 996001, 'owner', true, true, 996001);
insert into task_list (id, name, color, token, sort, home_id) values
    (996001, 'PC-L1', '#444444', 'pc-token-3', 'title', 996001),
    (996002, 'PC-L2', '#555555', 'pc-token-4', 'title', 996001);
insert into task_list_user (task_list_id, user_id, role, widget, dashboard, home_id) values
    (996001, 996001, 'owner', true, true, 996001),
    (996001, 996002, 'owner', true, true, 996001),
    (996001, 996003, 'viewer', true, true, 996001),
    (996001, 996004, 'viewer', true, true, 996001),
    (996002, 996001, 'owner', true, true, 996001);
commit;

-- ── C1: catálogo 23 / defaults 37 y conjuntos por kind = oráculo BD ──

do $$
declare
    v json;
    v_cat int;
    v_def int;
    r record;
    v_set text[];
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000981', true);
    v := get_home_permissions(996001);
    select count(*) into v_cat from jsonb_array_elements(v::jsonb->'catalog') e;
    if v_cat <> 23 then
        raise exception 'permisos_config C1: catálogo % (esperado 23)', v_cat;
    end if;
    if (select count(distinct e->>'code') from jsonb_array_elements(v::jsonb->'catalog') e) <> 23
       or (select count(*) from jsonb_array_elements(v::jsonb->'catalog') e
           where not exists (select 1 from permission p
                             where p.code = e->>'code' and p.domain = e->>'domain'
                               and p.description = e->>'description')) <> 0 then
        raise exception 'permisos_config C1: catálogo ≠ tabla permission';
    end if;
    select coalesce(sum(jsonb_array_length(e->'permissions')), 0) into v_def
      from jsonb_array_elements(v::jsonb->'defaults') e;
    if v_def <> 37 then
        raise exception 'permisos_config C1: defaults total % (esperado 37)', v_def;
    end if;
    for r in select e->>'kind' as kind, e->'permissions' as perms
               from jsonb_array_elements(v::jsonb->'defaults') e loop
        select coalesce(array_agg(mkd.permission_code order by mkd.permission_code collate "C"),
                        '{}') into v_set
          from member_kind_default mkd where mkd.kind::text = r.kind;
        if r.perms <> to_jsonb(v_set) then
            raise exception 'permisos_config C1: defaults de % ≠ oráculo BD (%)', r.kind, r.perms;
        end if;
    end loop;
    if (select count(*) from jsonb_array_elements(v::jsonb->'defaults') e) <> 4
       or (select count(*) from jsonb_array_elements(v::jsonb->'defaults') e
           where e->>'kind' = 'pet') <> 0 then
        raise exception 'permisos_config C1: defaults ≠ 4 kinds sin pet';
    end if;
    -- Oráculo literal (0019:84-124 / findings §1): adult 18 sin home.*; child 6 y relative 10
    -- CON home.view; guest 3.
    if (select jsonb_array_length(e->'permissions') from jsonb_array_elements(v::jsonb->'defaults') e
        where e->>'kind' = 'adult') <> 18
       or (select count(*) from jsonb_array_elements(v::jsonb->'defaults') e
           where e->>'kind' = 'adult' and e->'permissions' ?| array['home.view',
                 'home.members.manage', 'home.permissions.manage']) <> 0
       or (select count(*) from jsonb_array_elements(v::jsonb->'defaults') e
           where e->>'kind' = 'adult'
             and not (e->'permissions' ?| array['calendar.manage', 'tasklist.manage'])) <> 0 then
        raise exception 'permisos_config C1: defaults adult ≠ oráculo';
    end if;
    if (select count(*) from jsonb_array_elements(v::jsonb->'defaults') e
        where e->>'kind' in ('child', 'relative')
          and not (e->'permissions' ? 'home.view')) <> 0 then
        raise exception 'permisos_config C1: child/relative sin home.view (A9/P1)';
    end if;
    raise notice 'ok C1: catálogo 23, defaults 37 (18/6/10/3) = oráculo 0019';
end $$;

-- ── C2: memberships (admin = 23, editable según llamante) ──

do $$
declare
    v jsonb;
    r record;
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000981', true);
    v := get_home_permissions(996001)::jsonb;
    for r in select e from jsonb_array_elements(v->'memberships') e loop
        if (r.e->>'role') = 'admin' then
            if jsonb_array_length(r.e->'permissions') <> 23 or (r.e->>'editable')::boolean then
                raise exception 'permisos_config C2: fila admin ≠ catálogo 23 / editable=false (%)', r.e;
            end if;
        else
            if not (r.e->>'editable')::boolean then
                raise exception 'permisos_config C2: member editable=false para admin (%)', r.e;
            end if;
        end if;
        if r.e->'permissions' = 'null'::jsonb then
            raise exception 'permisos_config C2: permissions JSON null (%)', r.e;
        end if;
    end loop;
    -- member con home.view (K, child): todo editable=false
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000983', true);
    v := get_home_permissions(996001)::jsonb;
    if (select count(*) from jsonb_array_elements(v->'memberships') e
        where (e->>'editable')::boolean) <> 0 then
        raise exception 'permisos_config C2: editable=true para un member';
    end if;
    raise notice 'ok C2: memberships con admin=23 y editable según llamante';
end $$;

-- ── C3: get sin home.view → 403; no miembro → 404; cabecera ajena → 404 ──

do $$
declare
    v_ok boolean;
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000985', true);
    v_ok := false;
    begin
        perform get_home_permissions(996001);
        v_ok := true;
    exception when sqlstate '42501' then
        if sqlerrm <> 'Not Allowed' then
            raise exception 'permisos_config C3: % (esperado Not Allowed)', sqlerrm;
        end if;
    end;
    if v_ok then raise exception 'permisos_config C3: get sin home.view no falló'; end if;
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000986', true);
    v_ok := false;
    begin
        perform get_home_permissions(996001);
        v_ok := true;
    exception when sqlstate 'P0002' then
        if sqlerrm <> 'Not Found' then
            raise exception 'permisos_config C3: % (esperado Not Found)', sqlerrm;
        end if;
    end;
    if v_ok then raise exception 'permisos_config C3: get de no miembro no falló'; end if;
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000982', true);
    perform set_config('request.headers', '{"x-home-id":"996002"}', true);
    v_ok := false;
    begin
        perform get_home_permissions(996001);
        v_ok := true;
    exception when sqlstate 'P0002' then
        if sqlerrm <> 'Not Found' then
            raise exception 'permisos_config C3: % (esperado Not Found)', sqlerrm;
        end if;
    end;
    if v_ok then raise exception 'permisos_config C3: cabecera ajena no falló'; end if;
    raise notice 'ok C3: get 403 sin home.view, 404 no miembro y 404 cabecera ajena';
end $$;

-- ── C4: grant efectivo (fn_has_permission false→true impersonando al member) ──

do $$
declare
    v jsonb;
    v_before boolean;
    v_after boolean;
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000982', true);
    v_before := fn_has_permission(996001, 'home.invite');
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000981', true);
    v := set_home_permissions(996001, 996002,
        (select to_jsonb(coalesce(array_agg(mp.permission_code || '' order by mp.permission_code), '{}'))
           from membership_permission mp where mp.home_membership_id = 996002)
        || '["home.invite"]'::jsonb)::jsonb;
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000982', true);
    v_after := fn_has_permission(996001, 'home.invite');
    if v_before or not v_after then
        raise exception 'permisos_config C4: grant no efectivo (before=%, after=%)', v_before, v_after;
    end if;
    if not (v->'granted' = '["home.invite"]'::jsonb and v->'revoked' = '[]'::jsonb) then
        raise exception 'permisos_config C4: delta inesperado (%)', v;
    end if;
    raise notice 'ok C4: grant efectivo vía fn_has_permission (false→true)';
end $$;

-- ── C5: revoke efectivo ──

do $$
declare
    v jsonb;
    v_after boolean;
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000981', true);
    v := set_home_permissions(996001, 996002,
        (select to_jsonb(coalesce(array_agg(mp.permission_code order by mp.permission_code), '{}'))
           from membership_permission mp where mp.home_membership_id = 996002
             and mp.permission_code <> 'home.invite'))::jsonb;
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000982', true);
    v_after := fn_has_permission(996001, 'home.invite');
    if v_after or not (v->'revoked' = '["home.invite"]'::jsonb and v->'granted' = '[]'::jsonb) then
        raise exception 'permisos_config C5: revoke no efectivo (after=%, delta=%)', v_after, v;
    end if;
    raise notice 'ok C5: revoke efectivo vía fn_has_permission (true→false)';
end $$;

-- ── C6: idempotente (0 escrituras, 0 audit, granted/revoked vacíos) ──

do $$
declare
    v jsonb;
    v_n0 int;
    v_n1 int;
    v_snap0 int;
    v_snap1 int;
begin
    select count(*) into v_n0 from audit_log where home_id = 996001;
    select count(*) into v_snap0 from membership_permission where home_membership_id = 996002;
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000981', true);
    v := set_home_permissions(996001, 996002,
        (select to_jsonb(coalesce(array_agg(mp.permission_code order by mp.permission_code), '{}'))
           from membership_permission mp where mp.home_membership_id = 996002))::jsonb;
    select count(*) into v_n1 from audit_log where home_id = 996001;
    select count(*) into v_snap1 from membership_permission where home_membership_id = 996002;
    if v_n1 <> v_n0 or v_snap1 <> v_snap0
       or not (v->'granted' = '[]'::jsonb and v->'revoked' = '[]'::jsonb) then
        raise exception 'permisos_config C6: idempotente escribió (audit %→%, snap %→%, delta=%)',
            v_n0, v_n1, v_snap0, v_snap1, v;
    end if;
    raise notice 'ok C6: PATCH idempotente sin escrituras ni audit';
end $$;

-- ── C7: [] revoca todo (+N filas revoke) y restaura ──

do $$
declare
    v jsonb;
    v_n int;
    v_rev int;
    v_grants int;
    v_rest int;
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000981', true);
    select count(*) into v_n from membership_permission where home_membership_id = 996002;
    v := set_home_permissions(996001, 996002, '[]'::jsonb)::jsonb;
    select count(*) into v_rev from audit_log
     where home_id = 996001 and target_id = 996002 and action = 'home.permission.revoke'
       and payload->>'source' = 'set';
    select count(*) into v_grants from membership_permission where home_membership_id = 996002;
    if jsonb_array_length(v->'revoked') <> v_n or v_grants <> 0 or v_rev < v_n then
        raise exception 'permisos_config C7: [] no revocó todo (revoked=%, filas=%, audit=%)',
            v->'revoked', v_grants, v_rev;
    end if;
    v := set_home_permissions(996001, 996002,
        (select to_jsonb(coalesce(array_agg(mkd.permission_code order by mkd.permission_code), '{}'))
           from member_kind_default mkd where mkd.kind = 'adult'))::jsonb;
    select count(*) into v_rest from membership_permission where home_membership_id = 996002;
    if v_rest <> 18 then
        raise exception 'permisos_config C7: restauración adult ≠ 18 (%)', v_rest;
    end if;
    raise notice 'ok C7: [] revoca todo (% filas revoke) y restaura defaults adult', v_n;
end $$;

-- ── C8: target admin → Not Allowed y 0 filas admin global (A4) ──

do $$
declare
    v_ok boolean;
    v_adm int;
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000981', true);
    v_ok := false;
    begin
        perform set_home_permissions(996001, 996001, '["home.view"]'::jsonb);
        v_ok := true;
    exception when sqlstate '42501' then
        if sqlerrm <> 'Not Allowed' then
            raise exception 'permisos_config C8: % (esperado Not Allowed)', sqlerrm;
        end if;
    end;
    if v_ok then raise exception 'permisos_config C8: set sobre admin no falló'; end if;
    select count(*) into v_adm from membership_permission mp
      join home_membership hm on hm.id = mp.home_membership_id where hm.role = 'admin';
    if v_adm <> 0 then
        raise exception 'permisos_config C8: % filas de admin (A4)', v_adm;
    end if;
    raise notice 'ok C8: target admin → Not Allowed y 0 filas de admin (A4)';
end $$;

-- ── C9: member con home.permissions.manage concedido → Not Allowed ──

do $$
declare
    v_ok boolean;
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000984', true);
    v_ok := false;
    begin
        perform set_home_permissions(996001, 996002, '["home.view"]'::jsonb);
        v_ok := true;
    exception when sqlstate '42501' then
        if sqlerrm <> 'Not Allowed' then
            raise exception 'permisos_config C9: % (esperado Not Allowed)', sqlerrm;
        end if;
    end;
    if v_ok then raise exception 'permisos_config C9: member con manage editó permisos (escalada)'; end if;
    raise notice 'ok C9: member con home.permissions.manage → Not Allowed (Q1)';
end $$;

-- ── C10: member sin manage → Not Allowed ──

do $$
declare
    v_ok boolean;
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000982', true);
    v_ok := false;
    begin
        perform set_home_permissions(996001, 996003, '["home.view"]'::jsonb);
        v_ok := true;
    exception when sqlstate '42501' then
        if sqlerrm <> 'Not Allowed' then
            raise exception 'permisos_config C10: % (esperado Not Allowed)', sqlerrm;
        end if;
    end;
    if v_ok then raise exception 'permisos_config C10: member sin manage editó permisos'; end if;
    raise notice 'ok C10: member sin home.permissions.manage → Not Allowed';
end $$;

-- ── C11: membresía de otro hogar → Not Found, sin cambios ──

do $$
declare
    v_ok boolean;
    v_snap int;
    v_n0 int;
    v_n1 int;
begin
    select count(*) into v_snap from membership_permission where home_membership_id = 996006;
    select count(*) into v_n0 from audit_log where home_id = 996001;
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000981', true);
    v_ok := false;
    begin
        perform set_home_permissions(996001, 996006, '["home.view"]'::jsonb);
        v_ok := true;
    exception when sqlstate 'P0002' then
        if sqlerrm <> 'Not Found' then
            raise exception 'permisos_config C11: % (esperado Not Found)', sqlerrm;
        end if;
    end;
    select count(*) into v_n1 from audit_log where home_id = 996001;
    if v_ok or v_n1 <> v_n0
       or (select count(*) from membership_permission where home_membership_id = 996006) <> v_snap then
        raise exception 'permisos_config C11: membresía ajena tocada o sin 404';
    end if;
    raise notice 'ok C11: membresía de otro hogar → Not Found sin cambios';
end $$;

-- ── C12: código inválido → Invalid permission, snapshot idéntico, 0 audit ──

do $$
declare
    v_ok boolean;
    v_n0 int;
    v_n1 int;
    v_snap0 int;
    v_snap1 int;
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000981', true);
    select count(*) into v_n0 from audit_log where home_id = 996001;
    select count(*) into v_snap0 from membership_permission where home_membership_id = 996002;
    v_ok := false;
    begin
        perform set_home_permissions(996001, 996002, '["home.view","no.existe"]'::jsonb);
        v_ok := true;
    exception when sqlstate 'P0001' then
        if sqlerrm <> 'Invalid permission' then
            raise exception 'permisos_config C12: % (esperado Invalid permission)', sqlerrm;
        end if;
    end;
    select count(*) into v_n1 from audit_log where home_id = 996001;
    select count(*) into v_snap1 from membership_permission where home_membership_id = 996002;
    if v_ok or v_n1 <> v_n0 or v_snap1 <> v_snap0 then
        raise exception 'permisos_config C12: código inválido escribió datos';
    end if;
    raise notice 'ok C12: código inválido → Invalid permission sin cambios ni audit';
end $$;

-- ── C13: shapes inválidos (null, objeto, string, elemento número/null/objeto) ──

do $$
declare
    v_case jsonb;
    v_ok boolean;
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000981', true);
    for v_case in select * from (values ('{}'::jsonb), ('"x"'::jsonb), ('1'::jsonb),
                                        ('[1]'::jsonb), ('[null]'::jsonb), ('[{}]'::jsonb)) t(x) loop
        v_ok := false;
        begin
            perform set_home_permissions(996001, 996002, v_case);
            v_ok := true;
        exception when sqlstate 'P0001' then
            if sqlerrm <> 'Invalid permission' then
                raise exception 'permisos_config C13: % con % (esperado Invalid permission)', sqlerrm, v_case;
            end if;
        end;
        if v_ok then
            raise exception 'permisos_config C13: shape % no falló', v_case;
        end if;
    end loop;
    v_ok := false;
    begin
        perform set_home_permissions(996001, 996002, null::jsonb);
        v_ok := true;
    exception when sqlstate 'P0001' then
        if sqlerrm <> 'Invalid permission' then
            raise exception 'permisos_config C13: % con null (esperado Invalid permission)', sqlerrm;
        end if;
    end;
    if v_ok then raise exception 'permisos_config C13: null no falló'; end if;
    raise notice 'ok C13: shapes inválidos → Invalid permission';
end $$;

-- ── C14: ids nulos → Not Found ──

do $$
declare
    v_ok boolean;
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000981', true);
    v_ok := false;
    begin
        perform set_home_permissions(null, 996002, '[]'::jsonb);
        v_ok := true;
    exception when sqlstate 'P0002' then
        if sqlerrm <> 'Not Found' then
            raise exception 'permisos_config C14: % (esperado Not Found)', sqlerrm;
        end if;
    end;
    if v_ok then raise exception 'permisos_config C14: home_id nulo no falló'; end if;
    v_ok := false;
    begin
        perform set_home_permissions(996001, null, '[]'::jsonb);
        v_ok := true;
    exception when sqlstate 'P0002' then
        if sqlerrm <> 'Not Found' then
            raise exception 'permisos_config C14: % (esperado Not Found)', sqlerrm;
        end if;
    end;
    if v_ok then raise exception 'permisos_config C14: membership_id nulo no falló'; end if;
    raise notice 'ok C14: ids nulos → Not Found';
end $$;

-- ── C15: duplicados/orden en input (normalización distinct + collate "C") ──

do $$
declare
    v jsonb;
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000981', true);
    v := set_home_permissions(996001, 996002,
        '["task.view","task.view","calendar.view"]'::jsonb)::jsonb;
    if v->'permissions' <> '["calendar.view","task.view"]'::jsonb then
        raise exception 'permisos_config C15: normalización incorrecta (%)', v->'permissions';
    end if;
    perform set_home_permissions(996001, 996002,
        (select to_jsonb(coalesce(array_agg(mkd.permission_code order by mkd.permission_code), '{}'))
           from member_kind_default mkd where mkd.kind = 'adult'))::jsonb;
    if (select count(*) from membership_permission where home_membership_id = 996002) <> 18 then
        raise exception 'permisos_config C15: restauración adult ≠ 18';
    end if;
    raise notice 'ok C15: duplicados y orden normalizados (distinct, collate "C")';
end $$;

-- ── C16: una fila de audit por código del delta (campos, actor, payload) ──

do $$
declare
    v jsonb;
    v_n int;
    v_id0 bigint;
    r record;
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000981', true);
    select coalesce(max(id), 0) into v_id0 from audit_log where home_id = 996001;
    v := set_home_permissions(996001, 996002,
        (select to_jsonb(coalesce(array_agg(mp.permission_code order by mp.permission_code), '{}'))
           || '["home.invite"]'::jsonb
           from membership_permission mp where mp.home_membership_id = 996002))::jsonb;
    select count(*) into v_n from audit_log
     where home_id = 996001 and id > v_id0 and target_id = 996002
       and action = 'home.permission.grant'
       and payload->>'permission_code' = 'home.invite' and payload->>'source' = 'set';
    if v_n <> 1 then
        raise exception 'permisos_config C16: % filas de audit para 1 código (esperado 1)', v_n;
    end if;
    select * into r from audit_log
     where home_id = 996001 and id > v_id0 and target_id = 996002
       and action = 'home.permission.grant'
       and payload->>'permission_code' = 'home.invite';
    if r.actor_app_user_id <> 996001 or r.target_type <> 'home_membership'
       or r.payload->>'before' <> 'false' or r.payload->>'after' <> 'true'
       or r.payload->>'source' <> 'set' or r.home_id <> 996001 then
        raise exception 'permisos_config C16: fila de audit incorrecta (%)', r.payload;
    end if;
    perform set_home_permissions(996001, 996002,
        (select to_jsonb(coalesce(array_agg(mp.permission_code order by mp.permission_code), '{}'))
           from membership_permission mp where mp.home_membership_id = 996002
             and mp.permission_code <> 'home.invite'))::jsonb;
    raise notice 'ok C16: una fila por código con before/after, actor y source=set';
end $$;

-- ── C17: get_home_audit — id desc, paginación before_id, clamp, R1-01 sin backfill.* ──

do $$
declare
    v jsonb;
    v_items jsonb;
    v_ids bigint[];
    v_page bigint[];
    v_all bigint[];
    v_paged bigint[];
    v_before bigint := null;
    v_pages int := 0;
    v_n int;
    r record;
    v_ok boolean;
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000981', true);
    -- (a) asegurar ≥8 filas home.% en H (deltas reales si hiciera falta)
    select count(*) into v_n from audit_log where home_id = 996001 and action like 'home.%';
    while v_n < 8 loop
        perform set_home_permissions(996001, 996003, '["home.view"]'::jsonb);
        perform set_home_permissions(996001, 996003,
            (select to_jsonb(coalesce(array_agg(mkd.permission_code order by mkd.permission_code), '{}'))
               from member_kind_default mkd where mkd.kind = 'child'));
        select count(*) into v_n from audit_log where home_id = 996001 and action like 'home.%';
    end loop;
    -- (b) filas backfill.* y home.* con created_at antiguo (R1-01/R1-03): insert directo
    insert into audit_log (home_id, actor_app_user_id, action, target_type, target_id, payload, created_at) values
        (996001, null, 'backfill.home.v1', 'home', null,
         '{"homes_personal":1,"homes_shared":2,"memberships":3,"acl_dedupes":4}'::jsonb, now() at time zone 'UTC'),
        (996001, null, 'backfill.acl_dedupe', 'calendar_user', 996001,
         '{"user_id":996002,"resource_id":996001}'::jsonb, now() at time zone 'UTC'),
        (996001, 996001, 'home.permission.grant', 'home_membership', 996002,
         '{"permission_code":"home.invite","before":false,"after":true,"source":"set"}'::jsonb,
         (now() at time zone 'UTC') - interval '10 days');
    -- (c) filas del otro hogar B (201 clamp + 3 normales) para clamps y fuga
    insert into audit_log (home_id, actor_app_user_id, action, target_type, target_id, payload)
    select 996002, 996006, 'home.clamp.test', 'home', 996002, '{}'::jsonb
      from generate_series(1, 201);
    insert into audit_log (home_id, actor_app_user_id, action, target_type, target_id, payload)
    values (996002, 996006, 'home.b.test', 'home', 996002, '{}'),
           (996002, 996006, 'home.b.test', 'home', 996002, '{}'),
           (996002, 996006, 'home.b.test', 'home', 996002, '{}');
    -- (d) lista completa de H: orden id desc real, sin backfill.*, sin filas de B
    v := get_home_audit(996001, 200, null)::jsonb;
    v_items := coalesce(v, '[]'::jsonb);
    select coalesce(array_agg((t.elem->>'id')::bigint order by t.ord), '{}') into v_all
      from jsonb_array_elements(v_items) with ordinality as t(elem, ord);
    select coalesce(array_agg(id order by id desc), '{}') into v_ids
      from audit_log where home_id = 996001 and action not like 'backfill.%';
    if v_all <> v_ids then
        raise exception 'permisos_config C17: lista no coincide con filas home.* por id desc (% vs %)', v_all, v_ids;
    end if;
    if (select count(*) from jsonb_array_elements(v_items) e
        where e->>'action' like 'backfill.%' or e->>'action' not like 'home.%') <> 0 then
        raise exception 'permisos_config C17: get_home_audit expone filas backfill.* o ajenas';
    end if;
    if (select count(*) from jsonb_array_elements(v_items) e
        where (e->>'id')::bigint = (select max(id) from audit_log
                                     where home_id = 996001 and action = 'home.permission.grant'
                                       and payload->>'permission_code' = 'home.invite')) <> 1 then
        raise exception 'permisos_config C17: falta la fila home.* con created_at antiguo (orden por id)';
    end if;
    -- (e) paginación por before_id (limit=2): ≥3 páginas, sin repetir ni omitir
    v_paged := '{}';
    v_before := null;
    loop
        v := get_home_audit(996001, 2, v_before)::jsonb;
        exit when coalesce(jsonb_array_length(v), 0) = 0;
        select coalesce(array_agg((t.elem->>'id')::bigint order by t.ord), '{}') into v_page
          from jsonb_array_elements(v) with ordinality as t(elem, ord);
        v_paged := v_paged || v_page;
        v_pages := v_pages + 1;
        v_before := v_page[array_length(v_page, 1)];
    end loop;
    if v_pages < 3 then
        raise exception 'permisos_config C17: paginación < 3 páginas (%)', v_pages;
    end if;
    if v_paged <> v_all then
        raise exception 'permisos_config C17: paginación repite u omite ids (% vs %)', v_paged, v_all;
    end if;
    -- (f) clamps en B (X admin): 0→1, 1000→200, null→50
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000986', true);
    if jsonb_array_length(get_home_audit(996002, 0, null)::jsonb) <> 1 then
        raise exception 'permisos_config C17: limit=0 ≠ 1 item';
    end if;
    if jsonb_array_length(get_home_audit(996002, 1000, null)::jsonb) <> 200 then
        raise exception 'permisos_config C17: limit=1000 ≠ 200 items';
    end if;
    if jsonb_array_length(get_home_audit(996002, null, null)::jsonb) <> 50 then
        raise exception 'permisos_config C17: limit null ≠ 50 items';
    end if;
    -- (g) member → 403; no miembro → 404
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000982', true);
    v_ok := false;
    begin
        perform get_home_audit(996001);
        v_ok := true;
    exception when sqlstate '42501' then
        if sqlerrm <> 'Not Allowed' then
            raise exception 'permisos_config C17: % (esperado Not Allowed)', sqlerrm;
        end if;
    end;
    if v_ok then raise exception 'permisos_config C17: member leyó audit'; end if;
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000986', true);
    v_ok := false;
    begin
        perform get_home_audit(996001);
        v_ok := true;
    exception when sqlstate 'P0002' then
        if sqlerrm <> 'Not Found' then
            raise exception 'permisos_config C17: % (esperado Not Found)', sqlerrm;
        end if;
    end;
    if v_ok then raise exception 'permisos_config C17: no miembro leyó audit'; end if;
    raise notice 'ok C17: id desc, % páginas sin repetir/omitir, clamps 1/200/50, sin backfill.*', v_pages;
end $$;

-- ── C18: audit_log sin SELECT directo para authenticated/anon ──

do $$
declare
    v_ok boolean;
begin
    if has_table_privilege('authenticated', 'audit_log', 'select')
       or has_table_privilege('anon', 'audit_log', 'select') then
        raise exception 'permisos_config C18: audit_log con SELECT para authenticated/anon';
    end if;
    v_ok := false;
    begin
        perform set_config('role', 'authenticated', true);
        perform (select count(*) from audit_log);
        v_ok := true;
    exception when sqlstate '42501' then
        null;
    end;
    perform set_config('role', 'none', true);
    if v_ok then
        raise exception 'permisos_config C18: SELECT directo sobre audit_log no falló';
    end if;
    raise notice 'ok C18: audit_log sin SELECT directo (authenticated/anon)';
end $$;

-- ── C19: cambio de kind member vinculado → defaults del nuevo kind + audit kind_change ──

do $$
declare
    v json;
    v_n0 int;
    v_n1 int;
    v_rows int;
    v_delta int;
    v_kind text;
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000981', true);
    select count(*) into v_n0 from audit_log where home_id = 996001;
    v := update_home_member(996001, 'child', null, null, null);
    select count(*) into v_n1 from audit_log where home_id = 996001;
    -- snapshot de la membresía de M = defaults de child
    if (select coalesce(array_agg(mp.permission_code order by mp.permission_code collate "C"), '{}')
          from membership_permission mp where mp.home_membership_id = 996002)
       <> (select coalesce(array_agg(mkd.permission_code order by mkd.permission_code collate "C"), '{}')
             from member_kind_default mkd where mkd.kind = 'child') then
        raise exception 'permisos_config C19: snapshot ≠ defaults de child';
    end if;
    select count(*) into v_rows from audit_log
     where home_id = 996001 and target_id = 996002 and payload->>'source' = 'kind_change'
       and payload->>'kind_from' = 'adult' and payload->>'kind_to' = 'child';
    select count(*) into v_delta from (
        (select permission_code from member_kind_default where kind = 'adult'
         except
         select permission_code from member_kind_default where kind = 'child')
        union all
        (select permission_code from member_kind_default where kind = 'child'
         except
         select permission_code from member_kind_default where kind = 'adult')) d;
    if v_rows <> v_delta or v_n1 - v_n0 <> v_delta then
        raise exception 'permisos_config C19: audit kind_change % filas (esperado %)', v_rows, v_delta;
    end if;
    if (select count(*) from audit_log
         where home_id = 996001 and target_id = 996002 and id > (select max(id) - 200 from audit_log)
           and payload->>'source' = 'kind_change'
           and (action not in ('home.permission.grant', 'home.permission.revoke')
                or target_type <> 'home_membership' or actor_app_user_id <> 996001)) <> 0 then
        raise exception 'permisos_config C19: filas kind_change con campos incorrectos';
    end if;
    -- reversión: kind adult restaura defaults de adult (segundo reset auditado)
    perform update_home_member(996001, 'adult', null, null, null);
    if (select count(*) from membership_permission where home_membership_id = 996002) <> 18 then
        raise exception 'permisos_config C19: reversión a adult ≠ 18';
    end if;
    raise notice 'ok C19: cambio de kind → defaults del nuevo kind + audit kind_change';
end $$;

-- ── C20: admin vinculado → kind cambia, 0 filas, 0 audit ──

do $$
declare
    v_n0 int;
    v_n1 int;
    v_rows int;
    v_kind text;
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000981', true);
    select count(*) into v_n0 from audit_log where home_id = 996001;
    perform update_home_member(996004, 'child', null, null, null);
    select kind::text into v_kind from home_member where id = 996004;
    select count(*) into v_n1 from audit_log where home_id = 996001;
    select count(*) into v_rows from membership_permission where home_membership_id = 996001;
    if v_kind <> 'child' or v_rows <> 0 or v_n1 <> v_n0 then
        raise exception 'permisos_config C20: kind=%, filas=%, audit %→%', v_kind, v_rows, v_n0, v_n1;
    end if;
    perform update_home_member(996004, 'adult', null, null, null);
    raise notice 'ok C20: admin vinculado cambia kind sin filas ni audit (A4)';
end $$;

-- ── C21: no-admin con home.members.manage cambia kind de vinculado → Not Allowed ──

do $$
declare
    v_ok boolean;
    v_kind text;
    v_snap int;
begin
    select count(*) into v_snap from membership_permission where home_membership_id = 996002;
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000984', true);
    v_ok := false;
    begin
        perform update_home_member(996001, 'child', null, null, null);
        v_ok := true;
    exception when sqlstate '42501' then
        if sqlerrm <> 'Not Allowed' then
            raise exception 'permisos_config C21: % (esperado Not Allowed)', sqlerrm;
        end if;
    end;
    select kind::text into v_kind from home_member where id = 996001;
    if v_ok or v_kind <> 'adult'
       or (select count(*) from membership_permission where home_membership_id = 996002) <> v_snap then
        raise exception 'permisos_config C21: kind/snapshot cambiaron sin admin (kind=%)', v_kind;
    end if;
    raise notice 'ok C21: no-admin con manage → Not Allowed al cambiar kind de vinculado (D-011)';
end $$;

-- ── C22: miembro sin vínculo → sin reset ni audit ──

do $$
declare
    v_n0 int;
    v_n1 int;
    v_kind text;
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000981', true);
    select count(*) into v_n0 from audit_log where home_id = 996001;
    perform update_home_member(996003, 'child', null, null, null);
    select kind::text into v_kind from home_member where id = 996003;
    select count(*) into v_n1 from audit_log where home_id = 996001;
    if v_kind <> 'child' or v_n1 <> v_n0 then
        raise exception 'permisos_config C22: kind=%, audit %→% (esperado child, sin audit)',
            v_kind, v_n0, v_n1;
    end if;
    raise notice 'ok C22: cambio de kind sin vínculo → 200 sin reset ni audit';
end $$;

-- ── C23: solo name/color → permisos intactos ──

do $$
declare
    v_n0 int;
    v_n1 int;
    v_snap int;
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000981', true);
    select count(*) into v_snap from membership_permission where home_membership_id = 996002;
    select count(*) into v_n0 from audit_log where home_id = 996001;
    perform update_home_member(996001, null, 'PC-Miembro X', null, null);
    select count(*) into v_n1 from audit_log where home_id = 996001;
    if (select count(*) from membership_permission where home_membership_id = 996002) <> v_snap
       or v_n1 <> v_n0 then
        raise exception 'permisos_config C23: solo name tocó permisos o audit';
    end if;
    raise notice 'ok C23: solo name/color → permisos intactos y sin audit';
end $$;

-- ── C24: promover borra snapshot / degradar siembra legacy17 (sin regresión) ──

do $$
declare
    v_rows int;
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000981', true);
    perform set_home_membership_role(996001, 996002, 'admin');
    select count(*) into v_rows from membership_permission where home_membership_id = 996002;
    if v_rows <> 0 then
        raise exception 'permisos_config C24: promover dejó % filas (A4)', v_rows;
    end if;
    perform set_home_membership_role(996001, 996002, 'member');
    if (select count(*) from membership_permission mp
         where mp.home_membership_id = 996002
           and mp.permission_code not in (
               'home.view', 'calendar.view', 'task.view', 'routine.view',
               'task.create', 'task.edit', 'task.complete', 'task.assign', 'task.delete',
               'event.create', 'event.edit', 'event.delete', 'event.assign',
               'routine.create', 'routine.edit', 'routine.delete', 'routine.assign')) <> 0
       or (select count(*) from membership_permission mp
           where mp.home_membership_id = 996002) <> 17 then
        raise exception 'permisos_config C24: degradar no siembra legacy17 (17 códigos exactos)';
    end if;
    raise notice 'ok C24: promover borra snapshot (A4) y degradar siembra legacy17';
end $$;

-- ── C25: add_calendar_user doble → misma respuesta, 1 fila ──

do $$
declare
    v1 json;
    v2 json;
    v_rows int;
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000981', true);
    v1 := add_calendar_user(996001, 'pc-n@check.homita.example');
    v2 := add_calendar_user(996001, 'pc-n@check.homita.example');
    select count(*) into v_rows from calendar_user where calendar_id = 996001 and user_id = 996005;
    if v1::jsonb <> v2::jsonb or v_rows <> 1 or (v1::jsonb->>'id')::bigint <> 996005 then
        raise exception 'permisos_config C25: doble add ≠ idempotente (filas=%, v1=%, v2=%)', v_rows, v1, v2;
    end if;
    raise notice 'ok C25: add_calendar_user doble → 200+200 iguales, 1 fila (A-12)';
end $$;

-- ── C26: add_task_list_user doble → misma respuesta, 1 fila ──

do $$
declare
    v1 json;
    v2 json;
    v_rows int;
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000981', true);
    v1 := add_task_list_user(996001, 'pc-n@check.homita.example');
    v2 := add_task_list_user(996001, 'pc-n@check.homita.example');
    select count(*) into v_rows from task_list_user where task_list_id = 996001 and user_id = 996005;
    if v1::jsonb <> v2::jsonb or v_rows <> 1 or (v1::jsonb->>'id')::bigint <> 996005 then
        raise exception 'permisos_config C26: doble add ≠ idempotente (filas=%)', v_rows;
    end if;
    raise notice 'ok C26: add_task_list_user doble → 200+200 iguales, 1 fila (A-12)';
end $$;

-- ── C27: remove_calendar_user contrato (último owner 403, self 400, viewer 403, reemplazo ok) ──

do $$
declare
    v_ok boolean;
    v json;
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000981', true);
    -- último owner (C2 solo tiene a A) → 403 incluso en self-remove
    v_ok := false;
    begin
        perform remove_calendar_user(996002, 996001);
        v_ok := true;
    exception when sqlstate '42501' then
        if sqlerrm <> 'Not Allowed' then
            raise exception 'permisos_config C27: % (esperado Not Allowed)', sqlerrm;
        end if;
    end;
    if v_ok then raise exception 'permisos_config C27: último owner eliminado'; end if;
    -- self con reemplazo (C1 tiene owners A y M) → 400
    v_ok := false;
    begin
        perform remove_calendar_user(996001, 996001);
        v_ok := true;
    exception when sqlstate 'P0001' then
        if sqlerrm <> 'User cannot remove themselves' then
            raise exception 'permisos_config C27: % (esperado self 400)', sqlerrm;
        end if;
    end;
    if v_ok then raise exception 'permisos_config C27: self-remove no falló'; end if;
    -- viewer (K) → 403
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000983', true);
    v_ok := false;
    begin
        perform remove_calendar_user(996001, 996005);
        v_ok := true;
    exception when sqlstate '42501' then
        if sqlerrm <> 'Not Allowed' then
            raise exception 'permisos_config C27: % (esperado Not Allowed)', sqlerrm;
        end if;
    end;
    if v_ok then raise exception 'permisos_config C27: viewer eliminó'; end if;
    -- owner con reemplazo elimina a otro → 200
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000981', true);
    v := remove_calendar_user(996001, 996005);
    if (select count(*) from calendar_user where calendar_id = 996001 and user_id = 996005) <> 0
       or v::jsonb <> '{"status":"ok"}'::jsonb then
        raise exception 'permisos_config C27: remove con reemplazo no ok (%)', v;
    end if;
    raise notice 'ok C27: remove_calendar_user contrato intacto (403/400/403/200)';
end $$;

-- ── C28: remove_task_list_user contrato (ídem) ──

do $$
declare
    v_ok boolean;
    v json;
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000981', true);
    v_ok := false;
    begin
        perform remove_task_list_user(996002, 996001);
        v_ok := true;
    exception when sqlstate '42501' then
        if sqlerrm <> 'Not Allowed' then
            raise exception 'permisos_config C28: % (esperado Not Allowed)', sqlerrm;
        end if;
    end;
    if v_ok then raise exception 'permisos_config C28: último owner eliminado'; end if;
    v_ok := false;
    begin
        perform remove_task_list_user(996001, 996001);
        v_ok := true;
    exception when sqlstate 'P0001' then
        if sqlerrm <> 'User cannot remove themselves' then
            raise exception 'permisos_config C28: % (esperado self 400)', sqlerrm;
        end if;
    end;
    if v_ok then raise exception 'permisos_config C28: self-remove no falló'; end if;
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000983', true);
    v_ok := false;
    begin
        perform remove_task_list_user(996001, 996005);
        v_ok := true;
    exception when sqlstate '42501' then
        if sqlerrm <> 'Not Allowed' then
            raise exception 'permisos_config C28: % (esperado Not Allowed)', sqlerrm;
        end if;
    end;
    if v_ok then raise exception 'permisos_config C28: viewer eliminó'; end if;
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000981', true);
    v := remove_task_list_user(996001, 996005);
    if (select count(*) from task_list_user where task_list_id = 996001 and user_id = 996005) <> 0
       or v::jsonb <> '{"status":"ok"}'::jsonb then
        raise exception 'permisos_config C28: remove con reemplazo no ok (%)', v;
    end if;
    raise notice 'ok C28: remove_task_list_user contrato intacto (403/400/403/200)';
end $$;

-- ── C29: delete_calendar / delete_task_list contrato intacto ──

do $$
declare
    v_ok boolean;
    v json;
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000981', true);
    v := delete_calendar(996002);
    if v::jsonb <> '{"success":true}'::jsonb
       or (select count(*) from calendar where id = 996002) <> 0 then
        raise exception 'permisos_config C29: delete_calendar no ok (%)', v;
    end if;
    v_ok := false;
    begin
        perform delete_calendar(996002);
        v_ok := true;
    exception when sqlstate 'P0002' then
        if sqlerrm <> 'Not Found' then
            raise exception 'permisos_config C29: % (esperado Not Found)', sqlerrm;
        end if;
    end;
    if v_ok then raise exception 'permisos_config C29: delete_calendar de inexistente no falló'; end if;
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000983', true);
    v_ok := false;
    begin
        perform delete_calendar(996001);
        v_ok := true;
    exception when sqlstate '42501' then
        if sqlerrm <> 'Not Allowed' then
            raise exception 'permisos_config C29: % (esperado Not Allowed)', sqlerrm;
        end if;
    end;
    if v_ok then raise exception 'permisos_config C29: viewer borró calendario'; end if;
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000981', true);
    v := delete_task_list(996002);
    if v::jsonb <> '{"success":true}'::jsonb
       or (select count(*) from task_list where id = 996002) <> 0 then
        raise exception 'permisos_config C29: delete_task_list no ok (%)', v;
    end if;
    v_ok := false;
    begin
        perform delete_task_list(996002);
        v_ok := true;
    exception when sqlstate 'P0002' then
        if sqlerrm <> 'Not Found' then
            raise exception 'permisos_config C29: % (esperado Not Found)', sqlerrm;
        end if;
    end;
    if v_ok then raise exception 'permisos_config C29: delete_task_list de inexistente no falló'; end if;
    raise notice 'ok C29: delete_calendar/delete_task_list contrato intacto';
end $$;

-- ── C30: proacl — 3 RPC a authenticated; helper sin; 7 redefinidas conservan grants ──

do $$
declare
    r record;
    v_acl text;
begin
    for r in select * from (values
        ('get_home_permissions(bigint)', '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'),
        ('set_home_permissions(bigint,bigint,jsonb)', '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'),
        ('get_home_audit(bigint,integer,bigint)', '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'),
        ('fn_audit_permission_delta(bigint,bigint,text[],text[],text,jsonb)', '{postgres=X/postgres,service_role=X/postgres}'),
        ('update_home_member(bigint,text,text,text,text)', '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'),
        ('add_calendar_user(bigint,text)', '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'),
        ('add_task_list_user(bigint,text)', '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'),
        ('remove_calendar_user(bigint,bigint)', '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'),
        ('remove_task_list_user(bigint,bigint)', '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'),
        ('delete_calendar(bigint)', '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'),
        ('delete_task_list(bigint)', '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}')
    ) t(sig, esperado) loop
        select coalesce(p.proacl::text, '(none)') into v_acl
          from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public'
           and p.oid::regprocedure::text in (r.sig, 'public.' || r.sig);
        if v_acl is distinct from r.esperado then
            raise exception 'permisos_config C30: proacl de % = % (esperado %)', r.sig, v_acl, r.esperado;
        end if;
    end loop;
    if not has_function_privilege('authenticated', 'get_home_permissions(bigint)', 'execute')
       or not has_function_privilege('authenticated', 'set_home_permissions(bigint,bigint,jsonb)', 'execute')
       or not has_function_privilege('authenticated', 'get_home_audit(bigint,integer,bigint)', 'execute') then
        raise exception 'permisos_config C30: authenticated sin EXECUTE en las 3 RPC';
    end if;
    if has_function_privilege('authenticated', 'fn_audit_permission_delta(bigint,bigint,text[],text[],text,jsonb)', 'execute') then
        raise exception 'permisos_config C30: helper con EXECUTE para authenticated';
    end if;
    raise notice 'ok C30: proacl exacto (3 RPC authenticated; helper sin; 7 redefinidas = baseline)';
end $$;

-- ── C31: anon no ejecuta las 3 RPC ──

do $$
declare
begin
    if has_function_privilege('anon', 'get_home_permissions(bigint)', 'execute')
       or has_function_privilege('anon', 'set_home_permissions(bigint,bigint,jsonb)', 'execute')
       or has_function_privilege('anon', 'get_home_audit(bigint,integer,bigint)', 'execute')
       or has_function_privilege('anon', 'fn_audit_permission_delta(bigint,bigint,text[],text[],text,jsonb)', 'execute') then
        raise exception 'permisos_config C31: anon con EXECUTE';
    end if;
    raise notice 'ok C31: anon sin EXECUTE en las 3 RPC ni en el helper';
end $$;

-- ── C32: no-admin con manage reenvía mismo kind + name → 200 sin reset ni audit; idem admin ──

do $$
declare
    v json;
    v_n0 int;
    v_n1 int;
    v_snap int;
    v_kind text;
begin
    select count(*) into v_snap from membership_permission where home_membership_id = 996002;
    select count(*) into v_n0 from audit_log where home_id = 996001;
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000984', true);
    v := update_home_member(996001, 'adult', 'PC-Miembro Y', null, null);
    select count(*) into v_n1 from audit_log where home_id = 996001;
    select kind::text into v_kind from home_member where id = 996001;
    if v_kind <> 'adult' or v_n1 <> v_n0
       or (select count(*) from membership_permission where home_membership_id = 996002) <> v_snap then
        raise exception 'permisos_config C32: mismo kind por no-admin tocó snapshot/audit (kind=%)', v_kind;
    end if;
    select count(*) into v_n0 from audit_log where home_id = 996001;
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000981', true);
    v := update_home_member(996001, 'adult', 'PC-Miembro Z', null, null);
    select count(*) into v_n1 from audit_log where home_id = 996001;
    if v_n1 <> v_n0
       or (select count(*) from membership_permission where home_membership_id = 996002) <> v_snap then
        raise exception 'permisos_config C32: mismo kind por admin tocó snapshot/audit';
    end if;
    raise notice 'ok C32: mismo kind (no-admin con manage y admin) → 200 sin reset ni audit';
end $$;

-- ── Limpieza de datos scratch 996xxx ──

set session_replication_role = replica;
begin;
delete from audit_log where home_id in (996001, 996002);
delete from membership_permission where home_membership_id between 996001 and 996006;
delete from home_membership where home_id in (996001, 996002);
delete from person where home_id in (996001, 996002);
delete from home_member where home_id in (996001, 996002);
delete from event_user where user_id between 996001 and 996006;
delete from task where task_list_id between 996001 and 996002;
delete from task_list_user where home_id = 996001;
delete from task_list where id between 996001 and 996002;
delete from calendar_user where calendar_id between 996001 and 996002;
delete from calendar where id between 996001 and 996002;
delete from home where id in (996001, 996002);
delete from app_user where id between 996001 and 996006;
delete from auth.users where id in (
    '00000000-0000-4000-8000-000000000981', '00000000-0000-4000-8000-000000000982',
    '00000000-0000-4000-8000-000000000983', '00000000-0000-4000-8000-000000000984',
    '00000000-0000-4000-8000-000000000985', '00000000-0000-4000-8000-000000000986');
commit;
set session_replication_role = default;
