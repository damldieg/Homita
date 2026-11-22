-- task_hidden_reapply_check.sql — Vuelta de la ida 0039 → rollback_0039.sql → 0039 (change
-- ocultar-completadas-3-dias), con prueba real del backfill. Solo BD local, después de
-- task_hidden_rollback_check.sql y de la ida y vuelta anidada de 0038. ci.sh sustituye la línea
-- `-- @MIGRATION:<fichero>@` por supabase/migrations/<fichero>. Emite 'ok RAHn: …' o aborta con
-- 'task_hidden_reapply RAHn: …'. Después ci.sh vuelve a pasar task_hidden_check (H1-H12) y
-- contract_check completo.
--
-- RAH1 de partida, el esquema revertido (sin task.hidden_at) con 0038 aplicada (create_task con el
--      marcador `0038:`). Se insertan fixtures (completadas a −5 d y −1 d y una pendiente) y se guarda
--      count y md5 de (id, completed_at, title, updated_at, "order", priority) de TODA task.
-- RAH2 tras aplicar 0039, hidden_at = (completed_at + 3 d) at time zone 'UTC' en las dos completadas y
--      null en la pendiente (A4); la de −5 d queda fuera de get_tasks y la de −1 d dentro.
-- RAH3 count y md5 idénticos a los de antes de la migración (A6).
--
-- Fixture (ids 9993xx, auth_uid …1021): se borra al final.

\set ON_ERROR_STOP 1
do $$
begin
    if inet_server_addr() is not null and host(inet_server_addr()) not in ('127.0.0.1', '::1') then
        raise exception 'task_hidden_reapply_check: solo BD local (socket o loopback); servidor %', host(inet_server_addr());
    end if;
end $$;

create function pg_temp.clean() returns void
language plpgsql as $$
begin
    set local session_replication_role = replica;
    delete from task where task_list_id in (select id from task_list where home_id = 999301);
    delete from task_list_user where task_list_id in (select id from task_list where home_id = 999301);
    delete from task_list where home_id = 999301;
    delete from home_membership where home_id = 999301;
    delete from audit_log where home_id = 999301;
    update app_user set default_home_id = null where id = 999301;
    delete from home where id = 999301;
    delete from app_user where id = 999301;
    delete from auth.users where id = '00000000-0000-4000-8000-000000001021';
end $$;

-- ── RAH1: esquema de partida ──
do $$
begin
    if exists (select 1 from information_schema.columns
               where table_schema = 'public' and table_name = 'task' and column_name = 'hidden_at') then
        raise exception 'task_hidden_reapply RAH1: no se parte del esquema revertido (task.hidden_at existe)';
    end if;
    if to_regprocedure('public.create_task(bigint,text,jsonb,uuid,text)') is null then
        raise exception 'task_hidden_reapply RAH1: falta create_task de 5 argumentos (0037/0038 no aplicadas)';
    end if;
    if pg_get_functiondef('public.create_task(bigint,text,jsonb,uuid,text)'::regprocedure) not like '%0038:%' then
        raise exception 'task_hidden_reapply RAH1: 0038 no está aplicada (create_task sin la guarda 0038:)';
    end if;
end $$;

select pg_temp.clean();

set session_replication_role = replica;
insert into auth.users (id, email, raw_user_meta_data) values
    ('00000000-0000-4000-8000-000000001021', 'tha-a@check.homita.example', '{"name":"THA-A"}');
insert into app_user (id, auth_uid, name, email) values
    (999301, '00000000-0000-4000-8000-000000001021', 'THA-A', 'tha-a@check.homita.example');
set session_replication_role = default;

begin;
insert into home (id, name, status, is_personal, created_by) values (999301, 'THA-Hogar', 'active', false, 999301);
insert into home_membership (id, home_id, app_user_id, role) values (999301, 999301, 999301, 'admin');
update app_user set default_home_id = 999301 where id = 999301;
insert into task_list (id, name, color, token, sort, home_id) values (999301, 'THA-L', '#222222', 'tha-tok-1', 'custom', 999301);
insert into task_list_user (task_list_id, user_id, role, widget, dashboard, home_id) values (999301, 999301, 'owner', true, true, 999301);
insert into task (id, task_list_id, title, completed_at, "order", priority) values
    (999301, 999301, 'THA-5d', (now() at time zone 'UTC') - interval '5 days', 1, 'alta'),
    (999302, 999301, 'THA-1d', (now() at time zone 'UTC') - interval '1 day', 2, 'media'),
    (999303, 999301, 'THA-Pend', null, 3, 'baja');
commit;

create temp table rah_before as
    select count(*) as n,
           md5(string_agg(row(id, completed_at, title, updated_at, "order", priority)::text, '|' order by id)) as h
    from task;

do $$
begin
    raise notice 'ok RAH1: esquema revertido (sin hidden_at, con 0038); fixtures y baseline de % tareas', (select n from rah_before);
end $$;

-- @MIGRATION:0039_task_hidden_at.sql@

-- ── RAH2: backfill ──
do $$
declare
    v_ids bigint[];
begin
    if exists (select 1 from task where id in (999301, 999302)
               and hidden_at is distinct from (completed_at + interval '3 days') at time zone 'UTC')
       or (select hidden_at from task where id = 999303) is not null then
        raise exception 'task_hidden_reapply RAH2: backfill incorrecto %',
            (select array_agg(row(id, completed_at, hidden_at)::text) from task where id between 999301 and 999303);
    end if;
    if exists (select 1 from task where completed_at is not null and hidden_at is null) then
        raise exception 'task_hidden_reapply RAH2: quedan completadas sin hidden_at';
    end if;
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000001021', true);
    select array_agg((e->>'id')::bigint order by (e->>'id')::bigint) into v_ids
      from json_array_elements(get_tasks(p_task_list_id => 999301)) e;
    if v_ids is distinct from array[999302, 999303]::bigint[] then
        raise exception 'task_hidden_reapply RAH2: get_tasks tras el backfill %', v_ids;
    end if;
    raise notice 'ok RAH2: backfill hidden_at = completed_at + 3 d (UTC) en las completadas, null en la pendiente; la de −5 d oculta y la de −1 d visible';
end $$;

-- ── RAH3: count y md5 intactos ──
do $$
declare
    v_n bigint;
    v_h text;
begin
    select count(*), md5(string_agg(row(id, completed_at, title, updated_at, "order", priority)::text, '|' order by id))
      into v_n, v_h from task;
    if v_n is distinct from (select n from rah_before) or v_h is distinct from (select h from rah_before) then
        raise exception 'task_hidden_reapply RAH3: count/md5 % % (antes %)', v_n, v_h, (select row(n, h)::text from rah_before);
    end if;
    raise notice 'ok RAH3: count (%) y md5 de (id, completed_at, title, updated_at, order, priority) idénticos', v_n;
end $$;

select pg_temp.clean();
drop table rah_before;
