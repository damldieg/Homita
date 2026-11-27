-- meal_profile_check.sql — Perfil de hogar del planificador de comidas (0043_meal_profile.sql).
-- Solo BD local, tras el reset 0001–0043:  psql -v ON_ERROR_STOP=1 -f meal_profile_check.sql
-- Cada bloque DO emite 'ok MPx: …' o aborta con 'meal_profile MPx: …'.
--
-- Fixture (ids 981xxx, auth_uid …0c0001–…0c0006): hogar H (981001) con A admin, B adulto, C niño
-- con cuenta, D familiar, E invitado, un niño sin cuenta (981006) y una mascota (981007); hogar G
-- (981002) con Y admin. Los permisos de los miembros salen de fn_seed_kind_permissions.
--
-- MP1 defaults (AC1): get_meal_profile en un hogar nuevo siembra comida 14:00 y cena 21:00 activas,
--     el resto desactivadas; perfil con defaults (E5, D3).
-- MP2 mascotas y hogar ajeno rechazados en meal_profile_member y meal_schedule (AC2).
-- MP3 cross-tenant (AC3): Y no lee ni escribe lo de H (SELECT vacío; RPC Not Found; tabla sin escritura).
-- MP4 matriz menu.* por kind (AC4): 29 permisos, 47 defaults (23/8/13/3), fn_has_permission por kind.
-- MP5 backfill (AC4): solo añade los menu.* que faltan y conserva personalizaciones; idempotente.
-- MP6 bloque C (AC5): cada persona edita solo sus C1–C4 sin menu.profile.edit; B/A propios y C ajeno → 403.
-- MP7 permisos de lectura/escritura del perfil y validación (400) incl. lista G5 de otro hogar, task_list_id
--     no numérico (R1-02), límites de longitud/tamaño (R1-03) y candidates de A1 sin home.view (R1-01).
-- MP8 alergias B1+B2: validación, obligatoriedad, B3/B4 ausentes; audit_log por escritura sin datos.
-- MP9 horario y franjas: set_meal_schedule / set_meal_slot_settings, eats=false borra la ficha.
-- MP10 grants: anon sin EXECUTE; authenticated sin escritura directa; RLS activa.
-- MP11 0 filas scratch al terminar.

\set ON_ERROR_STOP 1
do $$
begin
    if inet_server_addr() is not null and host(inet_server_addr()) not in ('127.0.0.1', '::1') then
        raise exception 'meal_profile_check: solo BD local (socket o loopback); servidor %', host(inet_server_addr());
    end if;
end $$;

create function pg_temp.clean() returns void
language plpgsql as $$
begin
    set local session_replication_role = replica;
    delete from meal_schedule where home_id in (981001, 981002);
    delete from meal_profile_member where home_id in (981001, 981002);
    delete from meal_slot_setting where home_id in (981001, 981002);
    delete from meal_profile where home_id in (981001, 981002);
    delete from task_list where home_id in (981001, 981002);
    delete from membership_permission where home_membership_id between 981001 and 981006;
    delete from audit_log where home_id in (981001, 981002);
    delete from home_member where home_id in (981001, 981002);
    delete from home_membership where home_id in (981001, 981002);
    update app_user set default_home_id = null where id between 981001 and 981006;
    delete from home where id in (981001, 981002);
    delete from app_user where id between 981001 and 981006;
    delete from auth.users where id::text like '00000000-0000-4000-8000-0000000c000_';
end $$;

-- Ejecuta p_sql y exige el error p_msg (sqlstate p_state).
create function pg_temp.fails(p_label text, p_sql text, p_state text, p_msg text) returns void
language plpgsql as $$
begin
    execute p_sql;
    raise exception 'meal_profile %: no falló: %', p_label, p_sql;
exception when others then
    if sqlstate <> p_state or sqlerrm <> p_msg then
        raise exception 'meal_profile %: % % (esperado % %)', p_label, sqlstate, sqlerrm, p_state, p_msg;
    end if;
end $$;

-- Sesión de la persona p_n (1–6), con X-Home-Id opcional; vive en la transacción del DO que lo llama.
create function pg_temp.as_user(p_n int, p_home bigint default null) returns void
language plpgsql as $$
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-0000000c000' || p_n, true);
    perform set_config('request.headers',
                       case when p_home is null then '' else json_build_object('x-home-id', p_home::text)::text end,
                       true);
end $$;

select pg_temp.clean();

-- ── Fixture ──
set session_replication_role = replica;
insert into auth.users (id, email, raw_user_meta_data) values
    ('00000000-0000-4000-8000-0000000c0001', 'mp-a@check.homita.example', '{"name":"MP-A"}'),
    ('00000000-0000-4000-8000-0000000c0002', 'mp-b@check.homita.example', '{"name":"MP-B"}'),
    ('00000000-0000-4000-8000-0000000c0003', 'mp-c@check.homita.example', '{"name":"MP-C"}'),
    ('00000000-0000-4000-8000-0000000c0004', 'mp-d@check.homita.example', '{"name":"MP-D"}'),
    ('00000000-0000-4000-8000-0000000c0005', 'mp-e@check.homita.example', '{"name":"MP-E"}'),
    ('00000000-0000-4000-8000-0000000c0006', 'mp-y@check.homita.example', '{"name":"MP-Y"}');
insert into app_user (id, auth_uid, name, email) values
    (981001, '00000000-0000-4000-8000-0000000c0001', 'MP-A', 'mp-a@check.homita.example'),
    (981002, '00000000-0000-4000-8000-0000000c0002', 'MP-B', 'mp-b@check.homita.example'),
    (981003, '00000000-0000-4000-8000-0000000c0003', 'MP-C', 'mp-c@check.homita.example'),
    (981004, '00000000-0000-4000-8000-0000000c0004', 'MP-D', 'mp-d@check.homita.example'),
    (981005, '00000000-0000-4000-8000-0000000c0005', 'MP-E', 'mp-e@check.homita.example'),
    (981006, '00000000-0000-4000-8000-0000000c0006', 'MP-Y', 'mp-y@check.homita.example');
set session_replication_role = default;

begin;
insert into home (id, name, status, is_personal, created_by) values
    (981001, 'MP-Hogar H', 'active', false, 981001),
    (981002, 'MP-Hogar G', 'active', false, 981006);
insert into home_membership (id, home_id, app_user_id, role) values
    (981001, 981001, 981001, 'admin'),
    (981002, 981001, 981002, 'member'),
    (981003, 981001, 981003, 'member'),
    (981004, 981001, 981004, 'member'),
    (981005, 981001, 981005, 'member'),
    (981006, 981002, 981006, 'admin');
insert into home_member (id, home_id, kind, name, app_user_id) values
    (981001, 981001, 'adult', 'MP-A', 981001),
    (981002, 981001, 'adult', 'MP-B', 981002),
    (981003, 981001, 'child', 'MP-C', 981003),
    (981004, 981001, 'relative', 'MP-D', 981004),
    (981005, 981001, 'guest', 'MP-E', 981005),
    (981006, 981001, 'child', 'MP-Peque', null),
    (981007, 981001, 'pet', 'MP-Mascota', null),
    (981008, 981002, 'adult', 'MP-Y', 981006);
update app_user set default_home_id = 981001 where id between 981001 and 981005;
update app_user set default_home_id = 981002 where id = 981006;
select fn_seed_kind_permissions(981002, 'adult');
select fn_seed_kind_permissions(981003, 'child');
select fn_seed_kind_permissions(981004, 'relative');
select fn_seed_kind_permissions(981005, 'guest');
insert into task_list (id, name, color, token, sort, home_id) values
    (981001, 'MP-Compra', '#222222', 'mp-tok-1', 'custom', 981001),
    (981002, 'MP-Compra-G', '#333333', 'mp-tok-2', 'custom', 981002);
commit;

-- ── MP1: defaults (AC1) ──
do $$
declare
    v json;
    s json;
begin
    perform pg_temp.as_user(1);
    if exists (select 1 from meal_slot_setting where home_id = 981001) then
        raise exception 'meal_profile MP1: hay franjas antes de la primera lectura';
    end if;
    v := get_meal_profile();
    if (v->>'home_id')::bigint <> 981001 or (v->>'can_edit')::boolean is not true then
        raise exception 'meal_profile MP1: cabecera %', v;
    end if;
    for s in select json_array_elements(v->'slots') loop
        if (s->>'slot' in ('lunch', 'dinner')) <> (s->>'enabled')::boolean then
            raise exception 'meal_profile MP1: franja activa incorrecta %', s;
        end if;
    end loop;
    if (select count(*) from meal_slot_setting where home_id = 981001) <> 5
       or (select to_char(time, 'HH24:MI') from meal_slot_setting where home_id = 981001 and slot = 'lunch') <> '14:00'
       or (select to_char(time, 'HH24:MI') from meal_slot_setting where home_id = 981001 and slot = 'dinner') <> '21:00'
       or (select count(*) from meal_slot_setting where home_id = 981001 and enabled) <> 2 then
        raise exception 'meal_profile MP1: franjas por defecto distintas de comida 14:00 / cena 21:00';
    end if;
    if (v->'profile'->>'shopping_day')::int <> 6 or (v->'profile'->>'week_start_day')::int <> 1
       or (v->'profile'->'equipment')::jsonb is distinct from '["stove","oven","microwave"]'::jsonb then
        raise exception 'meal_profile MP1: perfil sin defaults %', v->'profile';
    end if;
    if (v->>'members')::jsonb <> '[]'::jsonb or (v->>'schedule')::jsonb <> '[]'::jsonb then
        raise exception 'meal_profile MP1: miembros o horario no vacíos %', v;
    end if;
    -- segunda lectura: idempotente
    perform get_meal_profile();
    if (select count(*) from meal_slot_setting where home_id = 981001) <> 5
       or (select count(*) from meal_profile where home_id = 981001) <> 1 then
        raise exception 'meal_profile MP1: la segunda lectura duplicó filas';
    end if;
    raise notice 'ok MP1: hogar nuevo con comida 14:00 y cena 21:00 activas, resto desactivadas, perfil por defecto';
end $$;

-- ── MP2: mascotas y hogar ajeno rechazados (AC2) ──
do $$
begin
    perform pg_temp.as_user(1);
    perform pg_temp.fails('MP2 RPC pet', $q$select update_meal_profile_member(981007, '{"diet":"vegan"}'::jsonb)$q$,
        'P0001', 'Invalid member');
    perform pg_temp.fails('MP2 insert pet',
        $q$insert into meal_profile_member (home_member_id, home_id) values (981007, 981001)$q$,
        'P0001', 'Invalid member');
    perform pg_temp.fails('MP2 insert schedule pet',
        $q$insert into meal_schedule (home_member_id, home_id, weekday, slot) values (981007, 981001, 1, 'lunch')$q$,
        'P0001', 'Invalid member');
    -- miembro de otro hogar con el home_id del propio: lo rechaza el trigger (y la FK compuesta de respaldo)
    perform pg_temp.fails('MP2 insert otro hogar',
        $q$insert into meal_profile_member (home_member_id, home_id) values (981008, 981001)$q$,
        'P0001', 'Invalid member');
    perform pg_temp.fails('MP2 insert schedule otro hogar',
        $q$insert into meal_schedule (home_member_id, home_id, weekday, slot) values (981008, 981001, 1, 'lunch')$q$,
        'P0001', 'Invalid member');
    -- update: pasar una ficha existente a una mascota
    perform update_meal_profile_member(981006, '{"diet":"omnivore"}'::jsonb);
    perform pg_temp.fails('MP2 update a pet',
        $q$update meal_profile_member set home_member_id = 981007 where home_member_id = 981006$q$,
        'P0001', 'Invalid member');
    -- RPC con miembro de otro hogar
    perform pg_temp.fails('MP2 RPC otro hogar', $q$select update_meal_profile_member(981008, '{"diet":"vegan"}'::jsonb)$q$,
        'P0002', 'Not Found');
    perform pg_temp.fails('MP2 schedule otro hogar',
        $q$select set_meal_schedule('[{"home_member_id":981008,"weekday":1,"slot":"lunch","status":"out"}]'::jsonb)$q$,
        'P0002', 'Not Found');
    perform pg_temp.fails('MP2 schedule pet',
        $q$select set_meal_schedule('[{"home_member_id":981007,"weekday":1,"slot":"lunch","status":"out"}]'::jsonb)$q$,
        'P0001', 'Invalid member');
    raise notice 'ok MP2: mascotas y miembros de otro hogar rechazados en ficha y horario';
end $$;

-- ── MP3: cross-tenant (AC3) ──
do $$
begin
    perform pg_temp.as_user(1);
    perform update_meal_profile_member(981002, '{"diet":"vegetarian"}'::jsonb);
    perform set_meal_schedule('[{"home_member_id":981002,"weekday":2,"slot":"dinner","status":"out"}]'::jsonb);

    -- Y como authenticated: ni lee ni escribe lo de H
    perform pg_temp.as_user(6);
    set local role authenticated;
    if exists (select 1 from meal_profile where home_id = 981001)
       or exists (select 1 from meal_profile_member where home_id = 981001)
       or exists (select 1 from meal_schedule where home_id = 981001)
       or exists (select 1 from meal_slot_setting where home_id = 981001) then
        raise exception 'meal_profile MP3: Y lee tablas meal_* de H';
    end if;
    begin
        insert into meal_profile (home_id) values (981002);
        raise exception 'meal_profile MP3: authenticated insertó directo';
    exception when insufficient_privilege then null;
    end;
    begin
        update meal_profile set shopping_day = 1 where home_id = 981001;
        raise exception 'meal_profile MP3: authenticated actualizó directo';
    exception when insufficient_privilege then null;
    end;
    reset role;

    -- RPC de Y con la cabecera de H → Not Found; sin cabecera opera en su propio hogar
    perform pg_temp.as_user(6, 981001);
    perform pg_temp.fails('MP3 get con X-Home-Id ajeno', $q$select get_meal_profile()$q$, 'P0002', 'Not Found');
    perform pg_temp.fails('MP3 update con X-Home-Id ajeno', $q$select update_meal_profile('{"shopping_day":2}'::jsonb)$q$,
        'P0002', 'Not Found');
    perform pg_temp.as_user(6);
    perform pg_temp.fails('MP3 miembro de H', $q$select update_meal_profile_member(981002, '{"diet":"vegan"}'::jsonb)$q$,
        'P0002', 'Not Found');
    perform pg_temp.fails('MP3 horario de H', $q$select set_meal_schedule('[{"home_member_id":981002,"weekday":2,"slot":"dinner","status":"home"}]'::jsonb)$q$,
        'P0002', 'Not Found');
    if (get_meal_profile()->>'home_id')::bigint <> 981002
       or (get_meal_profile()->>'members')::jsonb <> '[]'::jsonb then
        raise exception 'meal_profile MP3: Y ve datos de otro hogar en su propio perfil';
    end if;
    -- lo de H sigue intacto
    if (select diet from meal_profile_member where home_member_id = 981002) <> 'vegetarian'
       or (select status from meal_schedule where home_member_id = 981002 and weekday = 2 and slot = 'dinner') <> 'out' then
        raise exception 'meal_profile MP3: Y modificó datos de H';
    end if;
    raise notice 'ok MP3: Y no lee ni escribe el perfil de H (SELECT vacío, RPC Not Found, tablas sin escritura)';
end $$;

-- ── MP4: matriz menu.* por kind (AC4) ──
do $$
declare
    v_kind member_kind;
    v_codes text;
    v_exp text;
begin
    if (select count(*) from permission) <> 29 or (select count(*) from permission where domain = 'menu') <> 5 then
        raise exception 'meal_profile MP4: catálogo %', (select count(*) from permission);
    end if;
    if (select count(*) from member_kind_default) <> 47
       or (select count(*) from member_kind_default where kind = 'adult') <> 23
       or (select count(*) from member_kind_default where kind = 'child') <> 8
       or (select count(*) from member_kind_default where kind = 'relative') <> 13
       or (select count(*) from member_kind_default where kind = 'guest') <> 3 then
        raise exception 'meal_profile MP4: defaults no son 47 (23/8/13/3)';
    end if;
    for v_kind, v_exp in values
        ('adult', 'menu.health.view,menu.plan.manage,menu.profile.edit,menu.shopping.edit,menu.view'),
        ('child', 'menu.shopping.edit,menu.view'),
        ('relative', 'menu.plan.manage,menu.shopping.edit,menu.view'),
        ('guest', '') loop
        select coalesce(string_agg(permission_code, ',' order by permission_code collate "C"), '') into v_codes
        from member_kind_default where kind = v_kind and permission_code like 'menu.%';
        if v_codes <> v_exp then
            raise exception 'meal_profile MP4: % → % (esperado %)', v_kind, v_codes, v_exp;
        end if;
    end loop;
    -- el snapshot de cada membresía del fixture = defaults del kind; el admin tiene todo sin filas
    for v_kind, v_exp in values ('adult', '981002'), ('child', '981003'), ('relative', '981004'), ('guest', '981005') loop
        if (select array_agg(permission_code order by permission_code) from membership_permission
             where home_membership_id = v_exp::bigint)
           is distinct from (select array_agg(permission_code order by permission_code) from member_kind_default
                              where kind = v_kind) then
            raise exception 'meal_profile MP4: snapshot de % distinto de member_kind_default', v_kind;
        end if;
    end loop;
    perform pg_temp.as_user(1);
    if not (fn_has_permission(981001, 'menu.view') and fn_has_permission(981001, 'menu.health.view'))
       or exists (select 1 from membership_permission where home_membership_id = 981001) then
        raise exception 'meal_profile MP4: admin sin permisos menu.* o con filas';
    end if;
    perform pg_temp.as_user(3);
    if not fn_has_permission(981001, 'menu.view') or fn_has_permission(981001, 'menu.profile.edit') then
        raise exception 'meal_profile MP4: niño con permisos incorrectos';
    end if;
    perform pg_temp.as_user(5);
    if fn_has_permission(981001, 'menu.view') or fn_has_permission(981001, 'menu.shopping.edit') then
        raise exception 'meal_profile MP4: invitado con menu.*';
    end if;
    raise notice 'ok MP4: matriz menu.* adult 23 / child 8 / relative 13 / guest 3, 29 permisos, 47 defaults';
end $$;

-- ── MP5: backfill solo añade lo que falta y conserva personalizaciones (AC4) ──
do $$
declare
    v_before bigint;
    v_after bigint;
    v_other_before text;
    v_other_after text;
begin
    -- B: personalizada (quita task.delete-like: añade routine.edit a un child y quita menu.view de B adulto)
    delete from membership_permission where home_membership_id = 981003 and permission_code like 'menu.%';
    insert into membership_permission values (981003, 'routine.edit') on conflict do nothing;
    delete from membership_permission where home_membership_id = 981002 and permission_code = 'menu.plan.manage';
    select string_agg(permission_code, ',' order by permission_code collate "C") into v_other_before
    from membership_permission where permission_code not like 'menu.%' and home_membership_id between 981002 and 981005;
    select count(*) into v_before from membership_permission where home_membership_id between 981001 and 981006;

    -- el mismo INSERT de 0043 (sección a)
    insert into membership_permission (home_membership_id, permission_code)
    select hm.id, d.permission_code
    from home_membership hm
    join home_member m on m.home_id = hm.home_id and m.app_user_id = hm.app_user_id
    join member_kind_default d on d.kind = m.kind
    where hm.role = 'member' and d.permission_code like 'menu.%'
    on conflict do nothing;

    select count(*) into v_after from membership_permission where home_membership_id between 981001 and 981006;
    select string_agg(permission_code, ',' order by permission_code collate "C") into v_other_after
    from membership_permission where permission_code not like 'menu.%' and home_membership_id between 981002 and 981005;
    if v_other_before is distinct from v_other_after then
        raise exception 'meal_profile MP5: el backfill tocó permisos no menu.* (% → %)', v_other_before, v_other_after;
    end if;
    if not exists (select 1 from membership_permission where home_membership_id = 981003 and permission_code = 'routine.edit') then
        raise exception 'meal_profile MP5: se perdió la personalización de la membresía 981003';
    end if;
    if v_after - v_before <> 3 then   -- niño: menu.view + menu.shopping.edit (2) + adulto B: menu.plan.manage (1)
        raise exception 'meal_profile MP5: el backfill añadió % filas (esperado 3)', v_after - v_before;
    end if;
    -- idempotente y sin filas para admin ni invitado
    insert into membership_permission (home_membership_id, permission_code)
    select hm.id, d.permission_code
    from home_membership hm
    join home_member m on m.home_id = hm.home_id and m.app_user_id = hm.app_user_id
    join member_kind_default d on d.kind = m.kind
    where hm.role = 'member' and d.permission_code like 'menu.%'
    on conflict do nothing;
    if (select count(*) from membership_permission where home_membership_id between 981001 and 981006) <> v_after
       or exists (select 1 from membership_permission where home_membership_id in (981001, 981005, 981006)
                  and permission_code like 'menu.%') then
        raise exception 'meal_profile MP5: backfill no idempotente o con filas para admin/invitado';
    end if;
    -- restaura el fixture (sin la personalización) para los bloques siguientes
    delete from membership_permission where home_membership_id = 981003 and permission_code = 'routine.edit';
    raise notice 'ok MP5: backfill añade solo menu.* faltantes, conserva personalizaciones, idempotente';
end $$;

-- ── MP6: bloque C propio sin menu.profile.edit (AC5) ──
do $$
begin
    perform pg_temp.as_user(1);
    perform update_meal_profile_member(981003, '{"age_band":"4-12","allergies_answered":true}'::jsonb);
    perform update_meal_profile_member(981004, '{}'::jsonb);
    perform update_meal_profile_member(981002, '{"allergies_answered":true}'::jsonb);

    -- C (niño con cuenta, sin menu.profile.edit): edita su C
    perform pg_temp.as_user(3);
    if fn_has_permission(981001, 'menu.profile.edit') then
        raise exception 'meal_profile MP6: el niño tiene menu.profile.edit';
    end if;
    perform update_meal_profile_member(981003,
        '{"dislikes":["coliflor"],"favorites":["pasta"],"quirks":"sin trozos","spice":1}'::jsonb);
    if (select dislikes from meal_profile_member where home_member_id = 981003) <> array['coliflor']
       or (select spice from meal_profile_member where home_member_id = 981003) <> 1 then
        raise exception 'meal_profile MP6: no guardó su bloque C';
    end if;
    -- bloque A/B propio → 403
    perform pg_temp.fails('MP6 B propio', $q$select update_meal_profile_member(981003, '{"diet":"vegan"}'::jsonb)$q$,
        '42501', 'Not Allowed');
    perform pg_temp.fails('MP6 A propio', $q$select update_meal_profile_member(981003, '{"age_band":"adult"}'::jsonb)$q$,
        '42501', 'Not Allowed');
    perform pg_temp.fails('MP6 mezcla C y B', $q$select update_meal_profile_member(981003, '{"spice":2,"diet":"vegan"}'::jsonb)$q$,
        '42501', 'Not Allowed');
    -- C ajeno → 403 (otro adulto, niño sin cuenta)
    perform pg_temp.fails('MP6 C de otro', $q$select update_meal_profile_member(981002, '{"spice":3}'::jsonb)$q$,
        '42501', 'Not Allowed');
    perform pg_temp.fails('MP6 C sin cuenta', $q$select update_meal_profile_member(981006, '{"spice":3}'::jsonb)$q$,
        '42501', 'Not Allowed');
    -- otros bloques del perfil de hogar → 403
    perform pg_temp.fails('MP6 perfil hogar', $q$select update_meal_profile('{"shopping_day":2}'::jsonb)$q$,
        '42501', 'Not Allowed');
    perform pg_temp.fails('MP6 horario', $q$select set_meal_schedule('[]'::jsonb)$q$, '42501', 'Not Allowed');
    perform pg_temp.fails('MP6 franjas', $q$select set_meal_slot_settings('[]'::jsonb)$q$, '42501', 'Not Allowed');

    -- D (familiar): sin menu.profile.edit, edita su C pero no el del adulto B
    perform pg_temp.as_user(4);
    perform update_meal_profile_member(981004, '{"spice":2}'::jsonb);
    perform pg_temp.fails('MP6 familiar C ajeno', $q$select update_meal_profile_member(981002, '{"spice":0}'::jsonb)$q$,
        '42501', 'Not Allowed');

    -- invitado E: ni siquiera tiene ficha → no puede crear la suya por el camino C
    perform pg_temp.as_user(5);
    perform pg_temp.fails('MP6 invitado sin ficha', $q$select update_meal_profile_member(981005, '{"spice":1}'::jsonb)$q$,
        'P0002', 'Not Found');

    -- el adulto con menu.profile.edit edita cualquier bloque de cualquiera (incluido el niño sin cuenta)
    perform pg_temp.as_user(2);
    perform update_meal_profile_member(981003, '{"diet":"vegetarian","spice":0}'::jsonb);
    perform update_meal_profile_member(981006, '{"age_band":"1-3","spice":0,"portion_size":"small"}'::jsonb);
    if (select age_band from meal_profile_member where home_member_id = 981006) <> '1-3' then
        raise exception 'meal_profile MP6: el adulto no pudo editar al niño sin cuenta';
    end if;
    raise notice 'ok MP6: C propio sin menu.profile.edit; B/A propios, C ajeno y perfil de hogar → 403';
end $$;

-- ── MP7: permisos de lectura/escritura y validación ──
do $$
declare
    v json;
begin
    perform pg_temp.as_user(5);
    perform pg_temp.fails('MP7 invitado lee', $q$select get_meal_profile()$q$, '42501', 'Not Allowed');
    perform pg_temp.as_user(3);
    v := get_meal_profile();       -- niño: menu.view
    if (v->>'can_edit')::boolean then
        raise exception 'meal_profile MP7: el niño puede editar';
    end if;
    perform pg_temp.fails('MP7 niño escribe', $q$select update_meal_profile('{"shopping_day":2}'::jsonb)$q$,
        '42501', 'Not Allowed');
    perform pg_temp.as_user(4);
    perform get_meal_profile();    -- familiar: menu.view
    perform pg_temp.fails('MP7 familiar escribe', $q$select update_meal_profile('{"shopping_day":2}'::jsonb)$q$,
        '42501', 'Not Allowed');

    -- R1-01: A1 llega dentro de get_meal_profile con menu.view, sin depender de home.view
    perform pg_temp.as_user(2);
    if fn_has_permission(981001, 'home.view') then
        raise exception 'meal_profile MP7: el fixture adulto tiene home.view (R1-01 no probaría nada)';
    end if;
    v := get_meal_profile();
    if json_array_length(v->'candidates') <> 6
       or exists (select 1 from json_array_elements(v->'candidates') c where (c->>'kind') = 'pet'
                  or (c->>'home_id')::bigint <> 981001 or (c->>'status') <> 'active')
       or not exists (select 1 from json_array_elements(v->'candidates') c
                      where (c->>'id')::bigint = 981006 and (c->>'linked')::boolean = false and (c->>'kind') = 'child')
       or not exists (select 1 from json_array_elements(v->'candidates') c
                      where (c->>'id')::bigint = 981002 and (c->>'linked')::boolean) then
        raise exception 'meal_profile MP7: candidates de A1 incorrectos %', v->'candidates';
    end if;
    perform pg_temp.as_user(3);
    if json_array_length(get_meal_profile()->'candidates') <> 6 then
        raise exception 'meal_profile MP7: el niño no recibe candidates';
    end if;
    perform pg_temp.as_user(6);    -- otro hogar: nunca ve los de H
    if exists (select 1 from json_array_elements(get_meal_profile()->'candidates') c
               where (c->>'home_id')::bigint = 981001) then
        raise exception 'meal_profile MP7: candidates de otro hogar';
    end if;

    perform pg_temp.as_user(2);    -- adulto: menu.profile.edit
    perform update_meal_profile(
        '{"shopping_day":5,"cook_minutes_weekday":30,"cook_minutes_weekend":60,"equipment":["oven","air_fryer"],
          "budget_weekly":120.5,"task_list_id":981001,"preferences":{"supermarkets":["mercadona"]}}'::jsonb);
    perform update_meal_profile('{"preferences":{"pantry":["aceite"]}}'::jsonb);   -- merge superficial
    v := get_meal_profile()->'profile';
    if (v->>'shopping_day')::int <> 5 or (v->>'budget_weekly')::numeric <> 120.5
       or (v->>'task_list_id')::bigint <> 981001
       or (v->'equipment')::jsonb is distinct from '["oven","air_fryer"]'::jsonb
       or (v->'preferences')::jsonb is distinct from '{"supermarkets":["mercadona"],"pantry":["aceite"]}'::jsonb then
        raise exception 'meal_profile MP7: perfil guardado incorrecto %', v;
    end if;
    -- null limpia un campo opcional
    perform update_meal_profile('{"task_list_id":null,"budget_weekly":null}'::jsonb);
    if (select task_list_id from meal_profile where home_id = 981001) is not null then
        raise exception 'meal_profile MP7: task_list_id no se limpió';
    end if;
    -- validación → 'Invalid meal profile'
    perform pg_temp.fails('MP7 día', $q$select update_meal_profile('{"shopping_day":9}'::jsonb)$q$, 'P0001', 'Invalid meal profile');
    perform pg_temp.fails('MP7 minutos', $q$select update_meal_profile('{"cook_minutes_weekday":20}'::jsonb)$q$, 'P0001', 'Invalid meal profile');
    perform pg_temp.fails('MP7 equipo', $q$select update_meal_profile('{"equipment":["nave"]}'::jsonb)$q$, 'P0001', 'Invalid meal profile');
    perform pg_temp.fails('MP7 presupuesto', $q$select update_meal_profile('{"budget_weekly":-1}'::jsonb)$q$, 'P0001', 'Invalid meal profile');
    perform pg_temp.fails('MP7 tipo', $q$select update_meal_profile('{"shopping_day":"lunes"}'::jsonb)$q$, 'P0001', 'Invalid meal profile');
    perform pg_temp.fails('MP7 clave', $q$select update_meal_profile('{"hack":1}'::jsonb)$q$, 'P0001', 'Invalid meal profile');
    perform pg_temp.fails('MP7 no objeto', $q$select update_meal_profile('[1]'::jsonb)$q$, 'P0001', 'Invalid meal profile');
    perform pg_temp.fails('MP7 preferences', $q$select update_meal_profile('{"preferences":[1]}'::jsonb)$q$, 'P0001', 'Invalid meal profile');
    -- lista G5 de otro hogar o inexistente: misma respuesta
    perform pg_temp.fails('MP7 lista ajena', $q$select update_meal_profile('{"task_list_id":981002}'::jsonb)$q$, 'P0001', 'Invalid meal profile');
    perform pg_temp.fails('MP7 lista inexistente', $q$select update_meal_profile('{"task_list_id":989999}'::jsonb)$q$, 'P0001', 'Invalid meal profile');
    -- R1-02: task_list_id no numérico → 400 (no 500 con el texto de Postgres)
    perform pg_temp.fails('MP7 lista texto', $q$select update_meal_profile('{"task_list_id":"abc"}'::jsonb)$q$, 'P0001', 'Invalid meal profile');
    perform pg_temp.fails('MP7 lista bool', $q$select update_meal_profile('{"task_list_id":true}'::jsonb)$q$, 'P0001', 'Invalid meal profile');
    perform pg_temp.fails('MP7 lista decimal', $q$select update_meal_profile('{"task_list_id":1.5}'::jsonb)$q$, 'P0001', 'Invalid meal profile');
    perform pg_temp.fails('MP7 lista enorme', $q$select update_meal_profile('{"task_list_id":99999999999999999999999}'::jsonb)$q$, 'P0001', 'Invalid meal profile');
    -- R1-03: límites de longitud y tamaño (texto <= 200, listas <= 50, preferences <= 8192, horario <= 500, franjas <= 5)
    perform update_meal_profile_member(981006, jsonb_build_object('quirks', repeat('a', 200), 'diet_note', repeat('b', 200),
        'dislikes', (select jsonb_agg(repeat('c', 200)) from generate_series(1, 50))));
    perform pg_temp.fails('MP7 quirks', format($q$select update_meal_profile_member(981006, jsonb_build_object('quirks', %L))$q$, repeat('a', 201)), 'P0001', 'Invalid meal profile');
    perform pg_temp.fails('MP7 diet_note', format($q$select update_meal_profile_member(981006, jsonb_build_object('diet_note', %L))$q$, repeat('a', 201)), 'P0001', 'Invalid meal profile');
    perform pg_temp.fails('MP7 dislikes elemento', format($q$select update_meal_profile_member(981006, jsonb_build_object('dislikes', jsonb_build_array(%L)))$q$, repeat('a', 201)), 'P0001', 'Invalid meal profile');
    perform pg_temp.fails('MP7 dislikes 51', $q$select update_meal_profile_member(981006, jsonb_build_object('dislikes', (select jsonb_agg('x' || g) from generate_series(1, 51) g)))$q$, 'P0001', 'Invalid meal profile');
    perform pg_temp.fails('MP7 favorites 51', $q$select update_meal_profile_member(981006, jsonb_build_object('favorites', (select jsonb_agg('x' || g) from generate_series(1, 51) g)))$q$, 'P0001', 'Invalid meal profile');
    perform pg_temp.fails('MP7 preferences miembro', format($q$select update_meal_profile_member(981006, jsonb_build_object('preferences', jsonb_build_object('k', %L)))$q$, repeat('a', 8200)), 'P0001', 'Invalid meal profile');
    perform pg_temp.fails('MP7 preferences hogar', format($q$select update_meal_profile(jsonb_build_object('preferences', jsonb_build_object('k', %L)))$q$, repeat('a', 8200)), 'P0001', 'Invalid meal profile');
    perform pg_temp.fails('MP7 preferences acumulado', format($q$select update_meal_profile(jsonb_build_object('preferences', jsonb_build_object('k', %L, 'j', %L)))$q$, repeat('a', 4100), repeat('b', 4100)), 'P0001', 'Invalid meal profile');
    perform pg_temp.fails('MP7 horario 501', $q$select set_meal_schedule((select jsonb_agg(jsonb_build_object('home_member_id', 981001, 'weekday', 1, 'slot', 'lunch', 'status', 'home')) from generate_series(1, 501)))$q$, 'P0001', 'Invalid meal profile');
    perform set_meal_schedule((select jsonb_agg(jsonb_build_object('home_member_id', 981001, 'weekday', 7, 'slot', 'snack', 'status', 'home')) from generate_series(1, 500)));
    delete from meal_schedule where home_member_id = 981001 and weekday = 7 and slot = 'snack';     -- el tope exacto (500) pasa; se limpia para MP9
    perform pg_temp.fails('MP7 franjas 6', $q$select set_meal_slot_settings((select jsonb_agg(jsonb_build_object('slot', 'lunch')) from generate_series(1, 6)))$q$, 'P0001', 'Invalid meal profile');
    -- el bloque C de la propia persona (sin menu.profile.edit) también respeta los límites
    perform pg_temp.as_user(3);
    perform pg_temp.fails('MP7 C propio quirks', format($q$select update_meal_profile_member(981003, jsonb_build_object('quirks', %L))$q$, repeat('a', 201)), 'P0001', 'Invalid meal profile');
    perform pg_temp.as_user(2);
    if (select shopping_day from meal_profile where home_id = 981001) <> 5 then
        raise exception 'meal_profile MP7: una petición inválida modificó el perfil';
    end if;
    raise notice 'ok MP7: lectura con menu.view, escritura con menu.profile.edit, validación 400, lista G5 del hogar';
end $$;

-- ── MP8: alergias B1+B2, B3/B4 ausentes, audit_log ──
do $$
declare
    v json;
    n_before bigint;
begin
    perform pg_temp.as_user(2);
    select count(*) into n_before from audit_log where home_id = 981001 and action like 'meal.%';
    perform pg_temp.fails('MP8 alérgeno', $q$select update_meal_profile_member(981002,
        '{"allergies_answered":true,"allergies":[{"allergen":"kiwi","severity":"no_traces"}]}'::jsonb)$q$,
        'P0001', 'Invalid meal profile');
    perform pg_temp.fails('MP8 gravedad', $q$select update_meal_profile_member(981002,
        '{"allergies_answered":true,"allergies":[{"allergen":"gluten","severity":"leve"}]}'::jsonb)$q$,
        'P0001', 'Invalid meal profile');
    perform pg_temp.fails('MP8 sin responder', $q$select update_meal_profile_member(981002,
        '{"allergies_answered":false,"allergies":[{"allergen":"gluten","severity":"no_traces"}]}'::jsonb)$q$,
        'P0001', 'Invalid meal profile');
    perform pg_temp.fails('MP8 dieta', $q$select update_meal_profile_member(981002, '{"diet":"carnívora"}'::jsonb)$q$,
        'P0001', 'Invalid meal profile');
    perform pg_temp.fails('MP8 picante', $q$select update_meal_profile_member(981002, '{"spice":4}'::jsonb)$q$,
        'P0001', 'Invalid meal profile');
    perform pg_temp.fails('MP8 franja de edad', $q$select update_meal_profile_member(981002, '{"age_band":"5-6"}'::jsonb)$q$,
        'P0001', 'Invalid meal profile');
    perform pg_temp.fails('MP8 objetivo', $q$select update_meal_profile_member(981002, '{"goals":["volar"]}'::jsonb)$q$,
        'P0001', 'Invalid meal profile');
    perform pg_temp.fails('MP8 B3', $q$select update_meal_profile_member(981002, '{"intolerances":["lactosa"]}'::jsonb)$q$,
        'P0001', 'Invalid meal profile');
    perform pg_temp.fails('MP8 B4', $q$select update_meal_profile_member(981002, '{"conditions":["celiaquia"]}'::jsonb)$q$,
        'P0001', 'Invalid meal profile');
    if (select count(*) from audit_log where home_id = 981001 and action like 'meal.%') <> n_before then
        raise exception 'meal_profile MP8: una petición rechazada dejó audit_log';
    end if;

    perform update_meal_profile_member(981002,
        '{"allergies_answered":true,"allergies":[{"allergen":"gluten","severity":"no_traces"},
          {"allergen":"egg","severity":"avoid_ingredient","note":"huevo crudo"}],"diet":"flexitarian",
          "goals":["more_veg"]}'::jsonb);
    v := (get_meal_profile()->'members')::json;
    if json_array_length(v) <> 4 then
        raise exception 'meal_profile MP8: miembros %', v;
    end if;
    if not exists (select 1 from json_array_elements(v) m
                    where (m->>'home_member_id')::bigint = 981002 and json_array_length(m->'allergies') = 2
                      and m->>'diet' = 'flexitarian') then
        raise exception 'meal_profile MP8: alergias no devueltas %', v;
    end if;
    if exists (select 1 from json_array_elements(v) m, json_object_keys(m) k
                where k ~ '(intolerance|condition|health)') then
        raise exception 'meal_profile MP8: el contrato expone B3/B4';
    end if;
    -- B1 a ninguna con answered=true
    perform update_meal_profile_member(981002, '{"allergies":[],"allergies_answered":true}'::jsonb);
    if (select jsonb_array_length(allergies) from meal_profile_member where home_member_id = 981002) <> 0 then
        raise exception 'meal_profile MP8: no pudo dejar alergias vacías';
    end if;
    -- audit_log: una fila por escritura, sin copiar datos de salud
    if (select count(*) from audit_log where home_id = 981001 and action = 'meal.member.update' and target_id = 981002) < 2
       or exists (select 1 from audit_log where home_id = 981001 and action like 'meal.%'
                   and payload::text ~* '(gluten|egg|huevo)')
       or not exists (select 1 from audit_log where home_id = 981001 and action = 'meal.profile.update'
                       and actor_app_user_id = 981002 and payload->'fields' ? 'shopping_day') then
        raise exception 'meal_profile MP8: audit_log incorrecto';
    end if;
    raise notice 'ok MP8: alergias validadas, B3/B4 ausentes, audit_log por escritura sin datos de salud';
end $$;

-- ── MP9: horario, franjas y eats=false ──
do $$
declare
    v json;
    n_audit bigint;
begin
    perform pg_temp.as_user(2);
    select count(*) into n_audit from audit_log where home_id = 981001 and action in ('meal.schedule.set', 'meal.slots.set');
    perform set_meal_schedule(
        '[{"home_member_id":981002,"weekday":1,"slot":"lunch","status":"out"},
          {"home_member_id":981003,"weekday":1,"slot":"lunch","status":"lunchbox"},
          {"home_member_id":981003,"weekday":1,"slot":"lunch","status":"skip"}]'::jsonb);
    v := get_meal_profile()->'schedule';
    if json_array_length(v) <> 3
       or (select status from meal_schedule where home_member_id = 981003 and weekday = 1 and slot = 'lunch') <> 'skip' then
        raise exception 'meal_profile MP9: horario %', v;
    end if;
    perform pg_temp.fails('MP9 estado', $q$select set_meal_schedule('[{"home_member_id":981002,"weekday":1,"slot":"lunch","status":"nunca"}]'::jsonb)$q$,
        'P0001', 'Invalid meal profile');
    perform pg_temp.fails('MP9 día', $q$select set_meal_schedule('[{"home_member_id":981002,"weekday":8,"slot":"lunch","status":"out"}]'::jsonb)$q$,
        'P0001', 'Invalid meal profile');
    perform pg_temp.fails('MP9 franja', $q$select set_meal_schedule('[{"home_member_id":981002,"weekday":1,"slot":"brunch","status":"out"}]'::jsonb)$q$,
        'P0001', 'Invalid meal profile');
    perform pg_temp.fails('MP9 sin miembro', $q$select set_meal_schedule('[{"weekday":1,"slot":"lunch","status":"out"}]'::jsonb)$q$,
        'P0001', 'Invalid meal profile');
    perform pg_temp.fails('MP9 no array', $q$select set_meal_schedule('{}'::jsonb)$q$, 'P0001', 'Invalid meal profile');

    perform set_meal_slot_settings('[{"slot":"snack","enabled":true,"time":"17:45"},{"slot":"dinner","time":"21:30"}]'::jsonb);
    if (select to_char(time, 'HH24:MI') from meal_slot_setting where home_id = 981001 and slot = 'snack') <> '17:45'
       or not (select enabled from meal_slot_setting where home_id = 981001 and slot = 'snack')
       or (select to_char(time, 'HH24:MI') from meal_slot_setting where home_id = 981001 and slot = 'dinner') <> '21:30'
       or not (select enabled from meal_slot_setting where home_id = 981001 and slot = 'dinner') then
        raise exception 'meal_profile MP9: franjas no guardadas';
    end if;
    perform pg_temp.fails('MP9 hora', $q$select set_meal_slot_settings('[{"slot":"lunch","time":"25:99"}]'::jsonb)$q$,
        'P0001', 'Invalid meal profile');
    perform pg_temp.fails('MP9 franja', $q$select set_meal_slot_settings('[{"slot":"brunch","enabled":true}]'::jsonb)$q$,
        'P0001', 'Invalid meal profile');
    if (select count(*) from audit_log where home_id = 981001 and action in ('meal.schedule.set', 'meal.slots.set')) <> n_audit + 2 then
        raise exception 'meal_profile MP9: audit_log de horario/franjas';
    end if;

    -- eats=false borra la ficha y su horario (cascada de la FK compuesta no aplica: se borra la ficha)
    perform update_meal_profile_member(981006, '{"eats":false}'::jsonb);
    if exists (select 1 from meal_profile_member where home_member_id = 981006) then
        raise exception 'meal_profile MP9: eats=false no borró la ficha';
    end if;
    if not exists (select 1 from audit_log where home_id = 981001 and action = 'meal.member.remove' and target_id = 981006) then
        raise exception 'meal_profile MP9: sin audit_log de baja';
    end if;
    raise notice 'ok MP9: horario y franjas guardados y validados; eats=false borra la ficha';
end $$;

-- ── MP10: grants y RLS ──
do $$
declare
    t text;
begin
    foreach t in array array['meal_profile', 'meal_profile_member', 'meal_schedule', 'meal_slot_setting'] loop
        if not (select relrowsecurity from pg_class where oid = ('public.' || t)::regclass) then
            raise exception 'meal_profile MP10: % sin RLS', t;
        end if;
        if has_table_privilege('anon', 'public.' || t, 'select,insert,update,delete')
           or has_table_privilege('authenticated', 'public.' || t, 'insert,update,delete')
           or not has_table_privilege('authenticated', 'public.' || t, 'select') then
            raise exception 'meal_profile MP10: privilegios de % incorrectos', t;
        end if;
        if exists (select 1 from pg_policy where polrelid = ('public.' || t)::regclass and polcmd <> 'r') then
            raise exception 'meal_profile MP10: % con policy de escritura', t;
        end if;
    end loop;
    foreach t in array array['get_meal_profile()', 'update_meal_profile(jsonb)', 'update_meal_profile_member(bigint,jsonb)',
                             'set_meal_schedule(jsonb)', 'set_meal_slot_settings(jsonb)'] loop
        if has_function_privilege('anon', t, 'execute') or not has_function_privilege('authenticated', t, 'execute') then
            raise exception 'meal_profile MP10: EXECUTE incorrecto en %', t;
        end if;
    end loop;
    foreach t in array array['fn_meal_profile_ensure(bigint)', 'fn_meal_member_guard()'] loop
        if has_function_privilege('anon', t, 'execute') or has_function_privilege('authenticated', t, 'execute') then
            raise exception 'meal_profile MP10: helper % accesible', t;
        end if;
    end loop;
    raise notice 'ok MP10: RLS activa, solo SELECT, RPC solo para authenticated, helpers cerrados';
end $$;

-- ── MP11: limpieza ──
select pg_temp.clean();
do $$
begin
    if exists (select 1 from app_user where id between 981001 and 981006)
       or exists (select 1 from home where id in (981001, 981002))
       or exists (select 1 from meal_profile where home_id in (981001, 981002))
       or exists (select 1 from meal_profile_member where home_id in (981001, 981002))
       or exists (select 1 from meal_slot_setting where home_id in (981001, 981002))
       or exists (select 1 from meal_schedule where home_id in (981001, 981002)) then
        raise exception 'meal_profile MP11: quedaron filas scratch';
    end if;
    raise notice 'ok MP11: 0 filas scratch';
end $$;
