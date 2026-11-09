-- home_checks_compat.sql — V5j–V5p del plan 1.3 sobre 0014_home_compat.sql y
-- 0015_home_constraints.sql. Se ejecuta con psql DESPUÉS de aplicar 0014 y 0015 (E3), o tras seed
-- en E4 (estado 0001–0015 completo):
--   psql -v ON_ERROR_STOP=1 -f home_checks_compat.sql
-- Cada bloque DO emite 'ok V5x: …' o aborta con 'home_checks V5x: …'.
--
-- Cubre: V5j altas atómicas por trigger 0014(a), V5k filas nuevas de las RPC de compat con home_id
-- coherente, V5l add_*_user (D-c: 42501 para no miembro, P0002 email inexistente), V5m delete_person
-- → home_member borrado (D-d), V5n delete_routine copia solo personas activas (0014f), V5o trigger
-- de asignaciones persona↔recurso (0015 iv) y V5p fn_sync_assignments por diferencia (0015 v).
-- V5h (anti-admin diferido) vive en home_checks_admin.sh: sus casos negativos exigen un COMMIT que
-- falla, imposible de atrapar dentro de un bloque DO.
--
-- Datos scratch propios (usuarios 990001+, hogares 990001+/99001x, contenido 995xxx) borrados al
-- final. Impersonación vía set_config('request.jwt.claim.sub', …, true) (auth.uid()). El alta de
-- usuarios scratch usa session_replication_role = replica SOLO para saltarse la FK
-- app_user→auth.users y el trigger 0014(a) (V5j lo prueba aparte, en modo normal).

-- ── Preambulo scratch: usuarios 990001–990004 ──

set session_replication_role = replica;
insert into auth.users (id, email, raw_user_meta_data) values
    ('00000000-0000-4000-8000-000000000901', 'v5c-a@check.homita.example', '{"name":"V5c-A"}'),
    ('00000000-0000-4000-8000-000000000902', 'v5c-b@check.homita.example', '{"name":"V5c-B"}'),
    ('00000000-0000-4000-8000-000000000903', 'v5c-c@check.homita.example', '{"name":"V5c-C"}'),
    ('00000000-0000-4000-8000-000000000904', 'v5c-d@check.homita.example', '{"name":"V5c-D"}')
on conflict (id) do nothing;
insert into app_user (id, auth_uid, name, email) values
    (990001, '00000000-0000-4000-8000-000000000901', 'V5c-A', 'v5c-a@check.homita.example'),
    (990002, '00000000-0000-4000-8000-000000000902', 'V5c-B', 'v5c-b@check.homita.example'),
    (990003, '00000000-0000-4000-8000-000000000903', 'V5c-C', 'v5c-c@check.homita.example'),
    (990004, '00000000-0000-4000-8000-000000000904', 'V5c-D', 'v5c-d@check.homita.example')
on conflict (id) do nothing;
set session_replication_role = default;

begin;
insert into home (id, name, status, is_personal, created_by) values (990001, 'V5c Hogar A', 'active', false, 990001);
insert into home (id, name, status, is_personal, created_by) values (990002, 'V5c Hogar B', 'active', false, 990004);
insert into home_membership (home_id, app_user_id, role) values (990001, 990001, 'admin');
insert into home_membership (home_id, app_user_id, role) values (990001, 990002, 'member');
insert into home_membership (home_id, app_user_id, role) values (990002, 990004, 'admin');
update app_user set default_home_id = 990001 where id = 990001;
commit;

-- ── V5j (0014a): alta de usuario → hogar personal atómico ──

do $$
declare
    v bigint;
begin
    -- caso 1: alta nueva (el trigger crea app_user + hogar + membresía + default)
    insert into auth.users (id, email, raw_user_meta_data)
        values ('00000000-0000-4000-8000-000000000911', 'v5j-uno@check.homita.example', '{"name":"V5j-Uno"}');
    select count(*) into v
    from app_user au
    join home_membership hm on hm.app_user_id = au.id
    join home h on h.id = hm.home_id
    where au.auth_uid = '00000000-0000-4000-8000-000000000911'
      and h.is_personal = true and h.name = 'Hogar de V5j-Uno'
      and hm.role = 'admin' and au.default_home_id = hm.home_id;
    if v <> 1 then
        raise exception 'home_checks V5j: alta nueva no creó hogar personal + membresía admin + default (% filas)', v;
    end if;
    raise notice 'ok V5j: /user/create → hogar is_personal, membresía admin, default_home_id';
end $$;

set session_replication_role = replica;
insert into app_user (id, auth_uid, name, email)
    values (990010, '00000000-0000-4000-8000-000000000912', 'V5j-Dos', 'v5j-dos@check.homita.example');
set session_replication_role = default;

do $$
declare
    v bigint;
begin
    -- caso 2: app_user preexistente SIN membresía → se le crea hogar
    insert into auth.users (id, email, raw_user_meta_data)
        values ('00000000-0000-4000-8000-000000000912', 'v5j-dos@check.homita.example', '{"name":"V5j-Dos"}');
    select count(*) into v
    from app_user au
    join home_membership hm on hm.app_user_id = au.id
    where au.id = 990010 and hm.role = 'admin' and au.default_home_id = hm.home_id;
    if v <> 1 then
        raise exception 'home_checks V5j: app_user sin membresía no recibió hogar (% filas)', v;
    end if;
    raise notice 'ok V5j: app_user preexistente sin membresía → hogar creado';
end $$;

set session_replication_role = replica;
insert into app_user (id, auth_uid, name, email)
    values (990011, '00000000-0000-4000-8000-000000000913', 'V5j-Tres', 'v5j-tres@check.homita.example');
set session_replication_role = default;

begin;
insert into home (id, name, status, is_personal, created_by) values (990011, 'V5c Hogar Tres', 'active', true, 990011);
insert into home_membership (home_id, app_user_id, role) values (990011, 990011, 'admin');
commit;

do $$
declare
    v bigint;
begin
    -- caso 3: app_user preexistente CON membresía → no duplica
    insert into auth.users (id, email, raw_user_meta_data)
        values ('00000000-0000-4000-8000-000000000913', 'v5j-tres@check.homita.example', '{"name":"V5j-Tres"}');
    select count(*) into v from home_membership where app_user_id = 990011;
    if v <> 1 then
        raise exception 'home_checks V5j: usuario con membresía duplicada (% membresías)', v;
    end if;
    raise notice 'ok V5j: app_user preexistente con membresía → sin duplicar';
end $$;

-- ── V5k (0014b): filas nuevas de create_calendar/create_task_list/create_person con home_id ──

do $$
declare
    v json;
    v_cal bigint;
    v_list bigint;
    v_per bigint;
    v_home bigint;
    v_hm bigint;
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000901', true);
    v := create_calendar('V5k-Cal', '#123456', true, true);
    v_cal := (v->>'id')::bigint;
    if v_cal is null or v->>'token' is null then
        raise exception 'home_checks V5k: create_calendar JSON sin id/token: %', v;
    end if;
    select home_id into v_home from calendar where id = v_cal;
    if v_home <> 990001 then
        raise exception 'home_checks V5k: calendar.home_id=% (esperado 990001)', v_home;
    end if;
    if not exists (select 1 from calendar_user where calendar_id = v_cal and user_id = 990001
                   and role = 'owner' and home_id = 990001) then
        raise exception 'home_checks V5k: calendar_user sin home_id coherente';
    end if;
    v := create_task_list('V5k-Lista', '#222222', 'updated_at', true, true);
    v_list := (v->>'id')::bigint;
    select home_id into v_home from task_list where id = v_list;
    if v_home <> 990001 then
        raise exception 'home_checks V5k: task_list.home_id=% (esperado 990001)', v_home;
    end if;
    if not exists (select 1 from task_list_user where task_list_id = v_list and user_id = 990001
                   and role = 'owner' and home_id = 990001) then
        raise exception 'home_checks V5k: task_list_user sin home_id coherente';
    end if;
    v := create_person('V5k-Persona', '#AABBCC');
    v_per := (v->>'id')::bigint;
    select home_id, home_member_id into v_home, v_hm from person where id = v_per;
    if v_home <> 990001 or v_hm is null then
        raise exception 'home_checks V5k: person (home_id=%, home_member_id=%)', v_home, v_hm;
    end if;
    if not exists (select 1 from home_member where id = v_hm and home_id = 990001) then
        raise exception 'home_checks V5k: home_member de person con home_id distinto';
    end if;
    raise notice 'ok V5k: create_calendar/create_task_list/create_person con home_id y home_member coherentes';
end $$;

-- ── V5l (0014b, D-c): add_calendar_user/add_task_list_user ──

do $$
declare
    v json;
    v_cal bigint;
    v_list bigint;
    v_msg text;
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000901', true);
    select id into v_cal from calendar where name = 'V5k-Cal';
    select id into v_list from task_list where name = 'V5k-Lista';
    -- email de no miembro → 42501 'Not Allowed' y sin filas nuevas
    begin
        perform add_calendar_user(v_cal, 'v5c-c@check.homita.example');
        raise exception 'home_checks V5l: add_calendar_user con no miembro no falló';
    exception
        when sqlstate '42501' then
            if sqlerrm <> 'Not Allowed' then
                raise exception 'home_checks V5l: add_calendar_user mensaje % (esperado Not Allowed)', sqlerrm;
            end if;
    end;
    if exists (select 1 from calendar_user where calendar_id = v_cal and user_id = 990003)
       or exists (select 1 from home_membership where home_id = 990001 and app_user_id = 990003) then
        raise exception 'home_checks V5l: la invitación rechazada dejó filas';
    end if;
    begin
        perform add_task_list_user(v_list, 'v5c-c@check.homita.example');
        raise exception 'home_checks V5l: add_task_list_user con no miembro no falló';
    exception
        when sqlstate '42501' then
            if sqlerrm <> 'Not Allowed' then
                raise exception 'home_checks V5l: add_task_list_user mensaje % (esperado Not Allowed)', sqlerrm;
            end if;
    end;
    if exists (select 1 from task_list_user where task_list_id = v_list and user_id = 990003) then
        raise exception 'home_checks V5l: la invitación rechazada dejó ACL';
    end if;
    -- email de miembro del hogar → 200 y ACL viewer con home_id del recurso
    v := add_calendar_user(v_cal, 'v5c-b@check.homita.example');
    if v->>'email' <> 'v5c-b@check.homita.example' then
        raise exception 'home_checks V5l: add_calendar_user miembro → %', v;
    end if;
    if not exists (select 1 from calendar_user where calendar_id = v_cal and user_id = 990002
                   and role = 'viewer' and home_id = 990001) then
        raise exception 'home_checks V5l: ACL viewer con home_id del recurso ausente (calendar)';
    end if;
    v := add_task_list_user(v_list, 'v5c-b@check.homita.example');
    if not exists (select 1 from task_list_user where task_list_id = v_list and user_id = 990002
                   and role = 'viewer' and home_id = 990001) then
        raise exception 'home_checks V5l: ACL viewer con home_id del recurso ausente (task_list)';
    end if;
    -- email inexistente → P0002 'Not Found'
    begin
        perform add_calendar_user(v_cal, 'noexiste@check.homita.example');
        raise exception 'home_checks V5l: add_calendar_user con email inexistente no falló';
    exception
        when sqlstate 'P0002' then
            if sqlerrm <> 'Not Found' then
                raise exception 'home_checks V5l: email inexistente mensaje % (esperado Not Found)', sqlerrm;
            end if;
    end;
    raise notice 'ok V5l: no miembro → Not Allowed 42501 sin filas; miembro → viewer con home_id; inexistente → Not Found P0002';
end $$;

-- ── V5m (0014c, D-d): delete_person → home_member borrado ──
-- Nota: el subcaso 'person sin home_member_id no rompe el delete' es inválido tras 0015(ii)
-- (person.home_member_id NOT NULL); fn_person_deleted tolera null (no-op) — cubierto por código.

do $$
declare
    v bigint;
    v_hm bigint;
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000901', true);
    select id, home_member_id into v, v_hm from person where name = 'V5k-Persona';
    perform delete_person(v);
    if exists (select 1 from person where id = v) then
        raise exception 'home_checks V5m: delete_person no borró la person';
    end if;
    if exists (select 1 from home_member where id = v_hm) then
        raise exception 'home_checks V5m: home_member % no borrado por fn_person_deleted', v_hm;
    end if;
    raise notice 'ok V5m: delete_person → home_member borrado (D-d)';
end $$;

-- ── V5n (0014f): delete_routine copia solo personas activas ──

begin;
insert into home_member (id, home_id, kind, name, app_user_id, status, created_by) values
    (995001, 990001, 'adult', 'V5n-Activa', null, 'active', 990001),
    (995002, 990001, 'adult', 'V5n-Inactiva', null, 'active', 990001);
insert into person (id, user_id, name, color, home_id, home_member_id) values
    (995001, 990001, 'V5n-Activa', '#111111', 990001, 995001),
    (995002, 990001, 'V5n-Inactiva', '#222222', 990001, 995002);
insert into routine (id, calendar_id, title, days, time, start_date, end_date, active, available_from, frequency, interval)
    select 995001, id, 'V5n-Rutina', '[1, 3]'::jsonb, '09:30', '2026-06-01', null, true,
           '2026-06-01 00:00:00', 'weekly', 1
    from calendar where name = 'V5k-Cal';
insert into routine_person (routine_id, person_id) values (995001, 995001), (995001, 995002);
insert into event (id, calendar_id, title, date_at, routine_id, routine_date)
    select 995001, id, 'V5n-Pasado', '2025-01-01 10:00:00', 995001, '2025-01-01'
    from calendar where name = 'V5k-Cal';
update home_member set status = 'inactive' where id = 995002;
commit;

do $$
declare
    v json;
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000901', true);
    v := delete_routine(995001, 'Europe/Madrid');
    if coalesce(v->>'success', '') <> 'true' then
        raise exception 'home_checks V5n: delete_routine → %', v;
    end if;
    if exists (select 1 from routine where id = 995001) then
        raise exception 'home_checks V5n: la rutina no se borró';
    end if;
    if not exists (select 1 from event_person where event_id = 995001 and person_id = 995001) then
        raise exception 'home_checks V5n: persona activa no copiada al historial';
    end if;
    if exists (select 1 from event_person where event_id = 995001 and person_id = 995002) then
        raise exception 'home_checks V5n: persona inactive copiada (0014f debe filtrarla)';
    end if;
    raise notice 'ok V5n: delete_routine → copia solo de personas activas; inactive no copiada; 200';
end $$;

-- ── V5o (0015 iv): trigger persona↔recurso y update_event sin revalidar ──

begin;
insert into home_member (id, home_id, kind, name, app_user_id, status, created_by) values
    (995003, 990001, 'adult', 'V5o-Asignada', null, 'active', 990001),
    (995004, 990001, 'adult', 'V5o-Inactiva', null, 'inactive', 990001),
    (995005, 990002, 'adult', 'V5o-Cruzada', null, 'active', 990004),
    (995006, 990001, 'adult', 'V5p-Una', null, 'active', 990001),
    (995007, 990001, 'adult', 'V5p-Dos', null, 'active', 990001);
insert into person (id, user_id, name, color, home_id, home_member_id) values
    (995003, 990001, 'V5o-Asignada', '#333333', 990001, 995003),
    (995004, 990001, 'V5o-Inactiva', '#444444', 990001, 995004),
    (995005, 990004, 'V5o-Cruzada', '#555555', 990002, 995005),
    (995006, 990001, 'V5p-Una', '#666666', 990001, 995006),
    (995007, 990001, 'V5p-Dos', '#777777', 990001, 995007);
insert into event (id, calendar_id, title, date_at)
    select 995002, id, 'V5o-Evento', '2026-12-30 10:00:00' from calendar where name = 'V5k-Cal';
commit;

do $$
declare
    v json;
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000901', true);
    -- (i) persona de otro hogar, modo normal → 'Invalid person' P0001
    begin
        insert into event_person (event_id, person_id) values (995002, 995005);
        raise exception 'home_checks V5o: event_person con persona de otro hogar no falló';
    exception
        when sqlstate 'P0001' then
            if sqlerrm <> 'Invalid person' then
                raise exception 'home_checks V5o: mensaje % (esperado Invalid person)', sqlerrm;
            end if;
    end;
    -- (ii) persona del mismo hogar inactive, fila nueva → 'Invalid person'
    begin
        insert into event_person (event_id, person_id) values (995002, 995004);
        raise exception 'home_checks V5o: event_person con persona inactive no falló';
    exception
        when sqlstate 'P0001' then
            if sqlerrm <> 'Invalid person' then
                raise exception 'home_checks V5o: mensaje % (esperado Invalid person)', sqlerrm;
            end if;
    end;
    insert into event_person (event_id, person_id) values (995002, 995003);
    update home_member set status = 'inactive' where id = 995003;
    -- (iii) update_event con persona ya asignada e inactiva → 200 (no revalida)
    v := update_event(995002, 'V5o-Evento', '2026-12-30 10:00:00', null, '[995003]'::jsonb, 'Europe/Madrid');
    if (v->>'id')::bigint <> 995002 then
        raise exception 'home_checks V5o: update_event con asignada inactiva → %', v;
    end if;
    if not exists (select 1 from event_person where event_id = 995002 and person_id = 995003) then
        raise exception 'home_checks V5o: update_event borró la asignación existente';
    end if;
    -- (iv) update_event que añade persona nueva válida → 200
    v := update_event(995002, 'V5o-Evento', '2026-12-30 10:00:00', null, '[995003, 995006]'::jsonb, 'Europe/Madrid');
    if (v->>'id')::bigint <> 995002
       or not exists (select 1 from event_person where event_id = 995002 and person_id = 995006) then
        raise exception 'home_checks V5o: update_event con persona nueva válida → %', v;
    end if;
    raise notice 'ok V5o: cross-home/inactive → Invalid person P0001; update_event sin revalidar y añadiendo válida → 200';
end $$;

-- ── V5p (0015 v): fn_sync_assignments por diferencia ──

begin;
insert into event (id, calendar_id, title, date_at)
    select 995003, id, 'V5p-Evento', '2026-12-31 10:00:00' from calendar where name = 'V5k-Cal';
insert into event_person (event_id, person_id) values (995003, 995006), (995003, 995007);
insert into routine (id, calendar_id, title, days, time, start_date, end_date, active, available_from, frequency, interval)
    select 995002, id, 'V5p-Rutina', '[1, 3]'::jsonb, '09:30', '2026-06-01', null, true,
           '2026-06-01 00:00:00', 'weekly', 1
    from calendar where name = 'V5k-Cal';
insert into routine_person (routine_id, person_id) values (995002, 995006), (995002, 995007);
commit;

do $$
declare
    v json;
    -- event_person/routine_person no tienen columna id (solo el par FK); la identidad de fila se
    -- compara con xmin: estable ⟺ la fila no se borró+reinsertó (interpretación V5p en status.md).
    v_before text[];
    v_after text[];
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000901', true);
    select array_agg(xmin::text order by person_id) into v_before from event_person where event_id = 995003;
    v := update_event(995003, 'V5p-Evento', '2026-12-31 10:00:00', null, '[995006, 995007]'::jsonb, 'Europe/Madrid');
    select array_agg(xmin::text order by person_id) into v_after from event_person where event_id = 995003;
    if v_before <> v_after then
        raise exception 'home_checks V5p: update_event con lista idéntica reinsertó filas (% → %)', v_before, v_after;
    end if;
    v := update_event(995003, 'V5p-Evento', '2026-12-31 10:00:00', null, '[995006]'::jsonb, 'Europe/Madrid');
    select array_agg(xmin::text order by person_id) into v_after from event_person where event_id = 995003;
    if v_after <> array[v_before[1]] or array_length(v_after, 1) <> 1 then
        raise exception 'home_checks V5p: update_event quitando una persona → filas % (esperado solo la de 995006)', v_after;
    end if;
    select array_agg(xmin::text order by person_id) into v_before from routine_person where routine_id = 995002;
    v := update_routine(995002, 'V5p-Rutina', 'weekly', 1, '[1, 3]'::jsonb, '09:30', '2026-06-01', null, true,
                        '[995006, 995007]'::jsonb, 'Europe/Madrid');
    select array_agg(xmin::text order by person_id) into v_after from routine_person where routine_id = 995002;
    if v_before <> v_after then
        raise exception 'home_checks V5p: update_routine con lista idéntica reinsertó filas (% → %)', v_before, v_after;
    end if;
    v := update_routine(995002, 'V5p-Rutina', 'weekly', 1, '[1, 3]'::jsonb, '09:30', '2026-06-01', null, true,
                        '[995006]'::jsonb, 'Europe/Madrid');
    select array_agg(xmin::text order by person_id) into v_after from routine_person where routine_id = 995002;
    if v_after <> array[v_before[1]] or array_length(v_after, 1) <> 1 then
        raise exception 'home_checks V5p: update_routine quitando una persona → filas % (esperado solo la de 995006)', v_after;
    end if;
    raise notice 'ok V5p: lista idéntica → filas estables (xmin, sin delete+reinsert); quitar una persona → solo esa fila borrada';
end $$;

-- ── Limpieza scratch (una transacción, orden de dependencias) ──

do $$
begin
    set local session_replication_role = replica;
    delete from event_person where event_id in (
        select e.id from event e join calendar c on c.id = e.calendar_id where c.name = 'V5k-Cal')
        or person_id in (995001, 995002, 995003, 995004, 995005, 995006, 995007);
    delete from routine_person where routine_id in (995001, 995002)
        or person_id in (995001, 995002, 995003, 995004, 995005, 995006, 995007);
    delete from routine_exception where routine_id in (995001, 995002);
    delete from routine_event_alarm where routine_id in (995001, 995002);
    delete from routine_user where routine_id in (995001, 995002);
    delete from event_user where event_id in (
        select e.id from event e join calendar c on c.id = e.calendar_id where c.name = 'V5k-Cal');
    delete from event where calendar_id in (select id from calendar where name = 'V5k-Cal');
    delete from routine where id in (995001, 995002);
    delete from task where task_list_id in (select id from task_list where name = 'V5k-Lista');
    delete from task_list_user where home_id in (990001, 990002);
    delete from calendar_user where home_id in (990001, 990002);
    delete from person where id in (995001, 995002, 995003, 995004, 995005, 995006, 995007)
        or home_id in (990001, 990002, 990011);
    delete from task_list where name = 'V5k-Lista' or home_id in (990001, 990002);
    delete from calendar where name = 'V5k-Cal' or home_id in (990001, 990002);
    delete from home_member where home_id in (990001, 990002, 990011);
    delete from membership_permission where home_membership_id in
        (select id from home_membership where home_id in (990001, 990002, 990011)
            or app_user_id in (990001, 990002, 990003, 990004, 990010, 990011));
    delete from home_membership where home_id in (990001, 990002, 990011)
        or app_user_id in (990001, 990002, 990003, 990004, 990010, 990011)
        or home_id in (select id from home where name like 'Hogar de V5j-%');
    delete from audit_log where home_id in (990001, 990002, 990011);
    delete from home where id in (990001, 990002, 990011) or name like 'Hogar de V5j-%';
    delete from app_user where id in (990001, 990002, 990003, 990004, 990010, 990011)
        or email like 'v5j-%@check.homita.example';
    delete from auth.users where id in (
        '00000000-0000-4000-8000-000000000901', '00000000-0000-4000-8000-000000000902',
        '00000000-0000-4000-8000-000000000903', '00000000-0000-4000-8000-000000000904',
        '00000000-0000-4000-8000-000000000911', '00000000-0000-4000-8000-000000000912',
        '00000000-0000-4000-8000-000000000913');
    set local session_replication_role = default;
end $$;
