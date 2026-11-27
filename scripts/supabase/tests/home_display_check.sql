-- home_display_check.sql — Pantalla del hogar (0049_home_display.sql, dashboard-pantalla-hogar).
-- Solo BD local, tras el reset 0001–0049:  psql -v ON_ERROR_STOP=1 -f home_display_check.sql
-- Cada bloque DO emite 'ok Dx: …' o aborta con 'home_display Dx: …'.
--
-- Fixture (ids 994xxx, auth_uid …0941–…0949): hogar H (994001) con A admin (owner de calendario K),
-- B member con calendar.manage, C member sin permisos de calendario. Hogar O (994002) ajeno con su
-- calendario KO. Pantalla D (cuenta técnica 994004, auth …0944).
--
-- D1 link_start: código de 6 dígitos y secreto de sondeo; el código guarda solo el hash.
-- D2 claim de un código válido por A → 'ok'; el mismo código otra vez → 'Invalid link code'.
-- D3 claim por C (sin calendar.manage ni display.manage) → 'Not Allowed'.
-- D4 claim con código caducado → 'Invalid link code'.
-- D5 cinco códigos incorrectos de A en 10 min → el sexto 'Too many attempts'.
-- D6 complete: crea home_display, membresía y home_member kind display con solo lectura; el sondeo
--    devuelve 'ready' con la sesión una vez; la segunda vez 'Not Found'.
-- D7 sondeo antes de confirmar → 'pending'; vinculación caducada sin confirmar → 'expired'.
-- D8 límite de 5 pantallas activas por hogar → 'Display limit reached' en la sexta.
-- D9 update: calendario de otro hogar → 'Invalid display selection'; selección válida → calendar_user
--    con dashboard = true y role viewer; quitar un calendario borra su fila.
-- D10 revoke: sin membresía, sin selección, revoked_at puesto; otra revocación → 'Not Found'.
-- D11 la pantalla revocada no puede leer su configuración ('Not Found'); antes sí.
-- D12 fn_can_manage_displays: admin y calendar.manage sí; member sin permisos no.
-- D13 grants: anon sin ejecución de link_start ni de config; authenticated sí de claim.
-- Al final, limpieza y 'ok D-clean'.

\set ON_ERROR_STOP 1
do $$
begin
    if inet_server_addr() is not null and host(inet_server_addr()) not in ('127.0.0.1', '::1') then
        raise exception 'home_display_check: solo BD local (socket o loopback); servidor %', host(inet_server_addr());
    end if;
    if to_regprocedure('public.fn_display_link_claim(bigint,text,text)') is null then
        raise exception 'home_display_check: 0049 no está aplicada';
    end if;
end $$;

create function pg_temp.clean() returns void
language plpgsql as $$
begin
    set local session_replication_role = replica;
    delete from home_display_attempt where app_user_id between 994001 and 994009;
    -- Las vinculaciones de prueba sin hogar (D3, D4, D7, D8) también: la BD es local.
    delete from home_display_link where home_id in (994001, 994002) or home_id is null;
    delete from home_display where home_id in (994001, 994002);
    delete from calendar_user where calendar_id in (994001, 994002);
    delete from calendar where id in (994001, 994002);
    delete from membership_permission where home_membership_id between 994001 and 994009;
    delete from home_member where home_id in (994001, 994002);
    delete from home_membership where home_id in (994001, 994002);
    update app_user set default_home_id = null where id between 994001 and 994009;
    delete from home where id in (994001, 994002);
    delete from app_user where id between 994001 and 994009;
    delete from auth.users where id::text like '00000000-0000-4000-8000-00000000094%'
        or id::text like '00000000-0000-4000-8000-00000000095%';
end $$;

-- Ejecuta p_sql y exige el error p_msg (sqlstate p_state).
create function pg_temp.fails(p_label text, p_sql text, p_state text, p_msg text) returns void
language plpgsql as $$
begin
    execute p_sql;
    raise exception 'home_display %: no falló: %', p_label, p_sql;
exception when others then
    if sqlstate <> p_state or sqlerrm <> p_msg then
        raise exception 'home_display %: % % (esperado % %)', p_label, sqlstate, sqlerrm, p_state, p_msg;
    end if;
end $$;

create function pg_temp.as_user(p_n int) returns void
language sql as $$
    select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-00000000094' || p_n, true)
$$;

select pg_temp.clean();

-- ── Fixture ──
set session_replication_role = replica;
insert into auth.users (id, email, raw_user_meta_data) values
    ('00000000-0000-4000-8000-000000000941', 'hd-a@check.homita.example', '{"name":"HD-A"}'),
    ('00000000-0000-4000-8000-000000000942', 'hd-b@check.homita.example', '{"name":"HD-B"}'),
    ('00000000-0000-4000-8000-000000000943', 'hd-c@check.homita.example', '{"name":"HD-C"}'),
    ('00000000-0000-4000-8000-000000000944', 'hd-d@check.homita.example', '{"name":"HD-D"}');
insert into app_user (id, auth_uid, name, email) values
    (994001, '00000000-0000-4000-8000-000000000941', 'HD-A', 'hd-a@check.homita.example'),
    (994002, '00000000-0000-4000-8000-000000000942', 'HD-B', 'hd-b@check.homita.example'),
    (994003, '00000000-0000-4000-8000-000000000943', 'HD-C', 'hd-c@check.homita.example'),
    (994004, '00000000-0000-4000-8000-000000000944', 'HD-D', 'hd-d@check.homita.example');
set session_replication_role = default;

begin;
insert into home (id, name, status, is_personal, created_by) values
    (994001, 'HD-Hogar H', 'active', false, 994001),
    (994002, 'HD-Hogar O', 'active', false, 994002);
insert into home_membership (id, home_id, app_user_id, role) values
    (994001, 994001, 994001, 'admin'),
    (994002, 994001, 994002, 'member'),
    (994003, 994001, 994003, 'member'),
    (994004, 994002, 994002, 'admin');
update app_user set default_home_id = 994001 where id in (994001, 994002, 994003);
insert into membership_permission (home_membership_id, permission_code) values
    (994002, 'calendar.manage'), (994002, 'calendar.view'), (994003, 'calendar.view');
insert into home_member (id, home_id, kind, name, color, app_user_id, status) values
    (994001, 994001, 'adult', 'HD-MA', '#110000', 994001, 'active'),
    (994002, 994001, 'adult', 'HD-MB', '#220000', 994002, 'active'),
    (994003, 994001, 'adult', 'HD-MC', '#330000', 994003, 'active'),
    (994004, 994002, 'adult', 'HD-MO', '#440000', 994002, 'active');
insert into calendar (id, name, color, token, home_id) values
    (994001, 'HD-K', '#6923E2', 'hd-token-994001', 994001),
    (994002, 'HD-KO', '#6923E2', 'hd-token-994002', 994002);
insert into calendar_user (calendar_id, user_id, role, widget, dashboard, home_id) values
    (994001, 994001, 'owner', true, true, 994001),
    (994002, 994002, 'owner', true, true, 994002);

commit;

-- ── D1 ──
begin;
do $$
declare v_json json;
begin
    v_json := fn_display_link_start();
    if length(v_json->>'code') <> 6 or length(v_json->>'poll_secret') <> 48 then
        raise exception 'home_display D1: forma del código o del secreto: %', v_json;
    end if;
    -- El código en claro no puede estar guardado (solo su hash)
    if exists (select 1 from home_display_link where code_hash = v_json->>'code') then
        raise exception 'home_display D1: el código se guardó en claro';
    end if;
    -- Código y secreto de prueba para los pasos siguientes (se guardan en una tabla temporal)
    create temporary table if not exists hd_codes(name text primary key, value text);
    insert into hd_codes values ('code1', v_json->>'code'), ('poll1', v_json->>'poll_secret');
    raise notice 'ok D1: código de 6 dígitos y secreto; sólo hash guardado';
end $$;
commit;

-- ── D2 ──
do $$
declare
    v_code text := (select value from hd_codes where name = 'code1');
    v_out json;
begin
    perform pg_temp.as_user(1);
    v_out := fn_display_link_claim(994001, v_code, 'Salón');
    if (v_out->>'link_id') is null then raise exception 'home_display D2: claim sin link_id'; end if;
    raise notice 'ok D2: claim de A con el código';
    if (fn_display_link_claim(994001, v_code, 'Salón'))->>'error' <> 'Invalid link code' then
        raise exception 'home_display D2b: el mismo código no se rechazó';
    end if;
    raise notice 'ok D2b: el mismo código no vuelve a usarse';
end $$;

-- ── D3 ──
do $$
declare v_code text;
begin
    perform set_config('role', 'postgres', true);
    v_code := lpad((floor(random()*1000000))::int::text, 6, '0');
    insert into home_display_link (code_hash, poll_hash, expires_at)
    values (fn_display_hash(v_code), fn_display_hash('hd-poll-d3'), (now() at time zone 'UTC') + interval '10 minutes');
    insert into hd_codes values ('code3', v_code) on conflict (name) do update set value = excluded.value;
    perform pg_temp.as_user(3);
    perform pg_temp.fails('D3', format('select fn_display_link_claim(994001, %L, ''X'')', v_code), 'P0001', 'Not Allowed');
    raise notice 'ok D3: un miembro sin permisos de calendario no vincula';
end $$;

-- ── D4 ──
do $$
declare v_code text := '123456';
begin
    perform set_config('role', 'postgres', true);
    insert into home_display_link (code_hash, poll_hash, expires_at)
    values (fn_display_hash(v_code), fn_display_hash('hd-poll-d4'), (now() at time zone 'UTC') - interval '1 minute');
    perform pg_temp.as_user(1);
    if (fn_display_link_claim(994001, v_code, 'X'))->>'error' <> 'Invalid link code' then
        raise exception 'home_display D4: código caducado aceptado';
    end if;
    raise notice 'ok D4: código caducado no vincula';
end $$;

-- ── D5 ──
do $$
begin
    perform set_config('role', 'postgres', true);
    perform pg_temp.as_user(2);
    -- B tiene calendar.manage: cinco fallos y el sexto ya no se intenta
    for i in 1..5 loop
        if (fn_display_link_claim(994001, '000000', 'X'))->>'error' <> 'Invalid link code' then
            raise exception 'home_display D5: intento % no rechazado', i;
        end if;
    end loop;
    if (fn_display_link_claim(994001, '000001', 'X'))->>'error' <> 'Too many attempts' then
        raise exception 'home_display D5: el sexto intento no se bloquea';
    end if;
    raise notice 'ok D5: cinco fallos en 10 min bloquean el sexto intento';
end $$;

-- ── D6 ──
do $$
declare
    v_link bigint;
    v_out json;
    v_display bigint;
    v_poll text := (select value from hd_codes where name = 'poll1');
begin
    perform set_config('role', 'postgres', true);
    -- Pendiente antes de confirmar: el sondeo dice pending
    if (fn_display_link_poll(v_poll))->>'status' <> 'pending' then
        raise exception 'home_display D6: el sondeo antes de confirmar no dice pending';
    end if;
    select id into v_link from home_display_link where code_hash = fn_display_hash((select value from hd_codes where name = 'code1'));
    v_out := fn_display_link_complete(v_link, '00000000-0000-4000-8000-000000000944', '{"token":"t","refresh_token":"r"}'::jsonb);
    v_display := (v_out->>'display_id')::bigint;
    if not exists (select 1 from home_member where home_id = 994001 and kind = 'display' and app_user_id = 994004) then
        raise exception 'home_display D6: no hay home_member de kind display';
    end if;
    if (select count(*) from membership_permission mp join home_membership hm on hm.id = mp.home_membership_id
        where hm.home_id = 994001 and hm.app_user_id = 994004 and mp.permission_code like '%.manage') <> 0 then
        raise exception 'home_display D6: la pantalla tiene permisos de escritura';
    end if;
    if (fn_display_link_poll(v_poll))->>'status' <> 'ready' then
        raise exception 'home_display D6: el sondeo no entrega la sesión';
    end if;
    perform pg_temp.fails('D6b', format('select fn_display_link_poll(%L)', v_poll), 'P0001', 'Not Found');
    raise notice 'ok D6: pantalla creada con solo lectura; sesión entregada una vez';
    insert into hd_codes values ('display', v_display::text) on conflict (name) do update set value = excluded.value;
end $$;

-- ── D7 ──
do $$
declare v_code text := '654321';
begin
    perform set_config('role', 'postgres', true);
    insert into home_display_link (code_hash, poll_hash, expires_at)
    values (fn_display_hash(v_code), fn_display_hash('hd-poll-d7'), (now() at time zone 'UTC') - interval '1 minute');
    if (fn_display_link_poll('hd-poll-d7'))->>'status' <> 'expired' then
        raise exception 'home_display D7: vinculación caducada no dice expired';
    end if;
    raise notice 'ok D7: pending antes de confirmar y expired después de caducar';
end $$;

-- ── D9 (antes del límite, para usar la pantalla D) ──
do $$
declare v_display bigint := (select value::bigint from hd_codes where name = 'display');
begin
    perform set_config('role', 'postgres', true);
    perform pg_temp.as_user(2);
    perform pg_temp.fails('D9a', format('select fn_display_update(994001, %s, ''Salón'', ''{}''::jsonb, array[994002], array[]::bigint[])', v_display),
        'P0001', 'Invalid display selection');
    perform fn_display_update(994001, v_display, 'Salón', '{"brightness":0.5}'::jsonb, array[994001], array[]::bigint[]);
    if not exists (select 1 from calendar_user where calendar_id = 994001 and user_id = 994004 and dashboard and role = 'viewer') then
        raise exception 'home_display D9: la selección no creó la fila de calendar_user';
    end if;
    perform fn_display_update(994001, v_display, 'Salón', null, array[]::bigint[], array[]::bigint[]);
    if exists (select 1 from calendar_user where calendar_id = 994001 and user_id = 994004) then
        raise exception 'home_display D9: quitar el calendario no borró su fila';
    end if;
    perform fn_display_update(994001, v_display, 'Salón', null, array[994001], array[]::bigint[]);
    raise notice 'ok D9: selección entre hogares rechazada; selección válida refleja calendar_user';
end $$;

-- ── D11 (antes de revocar) ──
do $$
declare v_cfg json;
begin
    perform pg_temp.as_user(4);
    v_cfg := fn_display_config();
    if (v_cfg->>'name') <> 'Salón' or (v_cfg->'calendar_ids')::text <> '[994001]' then
        raise exception 'home_display D11: configuración de la pantalla: %', v_cfg;
    end if;
    raise notice 'ok D11a: la pantalla lee su configuración';
end $$;

-- ── D10 ──
do $$
declare v_display bigint := (select value::bigint from hd_codes where name = 'display');
begin
    perform set_config('role', 'postgres', true);
    perform pg_temp.as_user(1);
    perform fn_display_revoke(994001, v_display);
    if exists (select 1 from home_membership where home_id = 994001 and app_user_id = 994004)
       or exists (select 1 from calendar_user where user_id = 994004)
       or exists (select 1 from home_display where id = v_display and revoked_at is null) then
        raise exception 'home_display D10: la revocación dejó membresía, selección o pantalla activa';
    end if;
    perform pg_temp.fails('D10b', format('select fn_display_revoke(994001, %s)', v_display), 'P0001', 'Not Found');
    raise notice 'ok D10: revocada sin membresía ni selección; segunda revocación Not Found';
end $$;

-- ── D11 (después de revocar) ──
do $$
begin
    perform pg_temp.as_user(4);
    perform pg_temp.fails('D11b', 'select fn_display_config()', 'P0001', 'Not Found');
    raise notice 'ok D11b: la pantalla revocada no lee su configuración';
end $$;

-- ── D8 (límite) ──
do $$
declare v_g int;
begin
    perform set_config('role', 'postgres', true);
    set local session_replication_role = replica;
    for v_g in 0..4 loop
        insert into auth.users (id, email) values
            (('00000000-0000-4000-8000-00000000095' || v_g)::uuid, 'hd-p' || (v_g + 1) || '@check.homita.example');
        insert into app_user (id, auth_uid, name, email) values
            (994005 + v_g, ('00000000-0000-4000-8000-00000000095' || v_g)::uuid, 'HD-P' || (v_g + 1), 'hd-p' || (v_g + 1) || '@check.homita.example');
        insert into home_display (home_id, app_user_id, name, linked_by)
        values (994001, 994005 + v_g, 'HD-P' || (v_g + 1), 994001);
    end loop;
    set local session_replication_role = origin;
    insert into home_display_link (code_hash, poll_hash, expires_at)
    values (fn_display_hash('777777'), fn_display_hash('hd-poll-d8'), (now() at time zone 'UTC') + interval '10 minutes');
    perform pg_temp.as_user(1);
    perform pg_temp.fails('D8', 'select fn_display_link_claim(994001, ''777777'', ''X'')', 'P0001', 'Display limit reached');
    raise notice 'ok D8: sexta pantalla activa rechazada (la revocada no cuenta)';
end $$;

-- ── D12 ──
do $$
begin
    perform pg_temp.as_user(1);
    if not fn_can_manage_displays(994001) then raise exception 'home_display D12: el admin no gestiona pantallas'; end if;
    perform pg_temp.as_user(2);
    if not fn_can_manage_displays(994001) then raise exception 'home_display D12: calendar.manage no gestiona pantallas'; end if;
    perform pg_temp.as_user(3);
    if fn_can_manage_displays(994001) then raise exception 'home_display D12: member sin permisos gestiona pantallas'; end if;
    raise notice 'ok D12: admin y calendar.manage gestionan; member sin permisos no';
end $$;

-- ── D13 ──
do $$
begin
    if has_function_privilege('anon', 'public.fn_display_link_start()', 'EXECUTE')
       or has_function_privilege('anon', 'public.fn_display_config()', 'EXECUTE')
       or has_function_privilege('authenticated', 'public.fn_display_link_start()', 'EXECUTE') then
        raise exception 'home_display D13: grants de link_start/config demasiado amplios';
    end if;
    if not has_function_privilege('authenticated', 'public.fn_display_link_claim(bigint,text,text)', 'EXECUTE') then
        raise exception 'home_display D13: authenticated no puede vincular';
    end if;
    raise notice 'ok D13: grants de la vinculación';
end $$;

-- ── Limpieza ──
do $$
begin
    perform pg_temp.clean();
    raise notice 'ok D-clean';
end $$;
