-- task_priority_rollback_guard_check.sql — Guardas LIFO de rollback_0035 y rollback_0029 con 0037
-- aplicada (R1-02 del change prioridad-tarea). Solo BD local, tras el reset 0001–0037. ci.sh sustituye
-- `-- @ROLLBACK:<fichero>@` por scripts/supabase/rollback/<fichero> y lo pasa por stdin.
--
-- Sin las guardas, rollback_0035 (o rollback_0029) con 0037 aplicada deja create_task(bigint,text,jsonb)
-- junto a create_task(bigint,text,jsonb,uuid,text): la llamada por nombre de la Edge
-- ({p_task_list_id, p_title, p_person_ids}) es ambigua y POST /task/create da 500.
--
-- G0 control: con una sobrecarga de 3 argumentos añadida a mano (en una transacción que se deshace),
--    la llamada por nombre de la Edge falla con 42725 (función no única). Así G3 no es vacía.
-- G1 rollback_0035 aborta con su guarda (ci.sh exige el mensaje en el log) y no cambia nada.
-- G2 rollback_0029 aborta con su guarda (ídem) y no cambia nada.
-- G3 tras los dos intentos: una sola firma por RPC (la de 0037), task.priority y client_request
--    siguen, y las llamadas por nombre que hace la Edge para POST /task/create y PATCH /task/update
--    resuelven y devuelven la tarea (sin ambigüedad). ci.sh corre después contract_check.py, que
--    exige 201 en POST /task/create y 200 en PATCH /task/update por la Edge sobre este esquema.
--
-- Los rollbacks se ejecutan con ON_ERROR_STOP desactivado: la guarda aborta la transacción y el resto
-- del fichero falla con «current transaction is aborted» hasta el commit (que hace ROLLBACK). Es ruido
-- esperado en el log. Si una guarda no saltara, el rollback se confirmaría y G3 fallaría (BD local a
-- medias: repetir ci.sh).

\set ON_ERROR_STOP 1
do $$
begin
    if inet_server_addr() is not null and host(inet_server_addr()) not in ('127.0.0.1', '::1') then
        raise exception 'task_priority_rollback_guard_check: solo BD local (socket o loopback); servidor %', host(inet_server_addr());
    end if;
    if not exists (select 1 from information_schema.columns
                   where table_schema = 'public' and table_name = 'task' and column_name = 'priority') then
        raise exception 'task_priority_rollback_guard_check: 0037 no está aplicada (falta task.priority)';
    end if;
end $$;

create function pg_temp.clean() returns void
language plpgsql as $$
begin
    set local session_replication_role = replica;
    delete from task_person where task_id in (select t.id from task t join task_list tl on tl.id = t.task_list_id
                                              where tl.home_id = 993101);
    delete from task where task_list_id in (select id from task_list where home_id = 993101);
    delete from task_list_user where task_list_id in (select id from task_list where home_id = 993101);
    delete from task_list where home_id = 993101;
    delete from home_membership where home_id = 993101;
    delete from audit_log where home_id = 993101;
    update app_user set default_home_id = null where id = 993101;
    delete from home where id = 993101;
    delete from app_user where id = 993101;
    delete from auth.users where id = '00000000-0000-4000-8000-000000000939';
end $$;

create function pg_temp.as_a() returns void
language sql as $$
    select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000939', true)
$$;

-- Estado esperado con 0037 (y 0035, 0029) aplicadas; null si coincide.
create function pg_temp.g_state() returns text
language plpgsql as $$
declare
    v_sigs text[];
begin
    select array_agg(oid::regprocedure::text order by proname) into v_sigs
      from pg_proc where pronamespace = 'public'::regnamespace and proname in ('create_task', 'get_tasks', 'update_task');
    if v_sigs is distinct from array['create_task(bigint,text,jsonb,uuid,text)',
                                     'get_tasks(boolean,bigint,boolean,text,text)',
                                     'update_task(bigint,text,jsonb,text)'] then
        return format('firmas %s', v_sigs);
    end if;
    if not exists (select 1 from information_schema.columns
                   where table_schema = 'public' and table_name = 'task' and column_name = 'priority') then
        return 'falta task.priority';
    end if;
    if to_regclass('public.client_request') is null then
        return 'falta client_request';
    end if;
    if not exists (select 1 from information_schema.columns
                   where table_schema = 'public' and table_name = 'task_list_user' and column_name = 'can_edit') then
        return 'falta task_list_user.can_edit';
    end if;
    return null;
end $$;

select pg_temp.clean();

-- ── Fixture ──
set session_replication_role = replica;
insert into auth.users (id, email, raw_user_meta_data) values
    ('00000000-0000-4000-8000-000000000939', 'tg-a@check.homita.example', '{"name":"TG-A"}');
insert into app_user (id, auth_uid, name, email) values
    (993101, '00000000-0000-4000-8000-000000000939', 'TG-A', 'tg-a@check.homita.example');
set session_replication_role = default;

begin;
insert into home (id, name, status, is_personal, created_by) values (993101, 'TG-Hogar', 'active', false, 993101);
insert into home_membership (id, home_id, app_user_id, role) values (993101, 993101, 993101, 'admin');
update app_user set default_home_id = 993101 where id = 993101;
insert into task_list (id, name, color, token, sort, home_id) values (993101, 'TG-L', '#222222', 'tg-tok-1', 'custom', 993101);
insert into task_list_user (task_list_id, user_id, role, widget, dashboard, home_id) values (993101, 993101, 'owner', true, true, 993101);
commit;

-- ── G0: control de la ambigüedad ──
begin;
create function public.create_task(p_task_list_id bigint, p_title text, p_person_ids jsonb default null)
returns json language sql as $$ select null::json $$;
do $$
begin
    perform pg_temp.as_a();
    begin
        perform create_task(p_task_list_id => 993101, p_title => 'TG-Ambigua', p_person_ids => null);
        raise exception 'task_priority_rollback_guard G0: la llamada por nombre no fue ambigua con dos sobrecargas';
    exception when ambiguous_function then
        null;
    end;
    raise notice 'ok G0: con dos sobrecargas de create_task la llamada por nombre de la Edge es ambigua (42725)';
end $$;
rollback;

-- ── G1: rollback_0035 con 0037 aplicada ──
\set ON_ERROR_STOP 0
\echo '-- G1: rollback_0035 con 0037 aplicada (se espera la guarda y errores de transacción abortada)'
-- @ROLLBACK:rollback_0035.sql@
rollback;
\set ON_ERROR_STOP 1

do $$
declare
    v_err text := pg_temp.g_state();
begin
    if v_err is not null then
        raise exception 'task_priority_rollback_guard G1: rollback_0035 cambió el esquema: %', v_err;
    end if;
    raise notice 'ok G1: rollback_0035 abortó por la guarda y el esquema sigue con 0037';
end $$;

-- ── G2: rollback_0029 con 0037 aplicada ──
\set ON_ERROR_STOP 0
\echo '-- G2: rollback_0029 con 0037 aplicada (se espera la guarda y errores de transacción abortada)'
-- @ROLLBACK:rollback_0029.sql@
rollback;
\set ON_ERROR_STOP 1

do $$
declare
    v_err text := pg_temp.g_state();
begin
    if v_err is not null then
        raise exception 'task_priority_rollback_guard G2: rollback_0029 cambió el esquema: %', v_err;
    end if;
    raise notice 'ok G2: rollback_0029 abortó por la guarda y el esquema sigue con 0037';
end $$;

-- ── G3: las llamadas de la Edge resuelven ──
do $$
declare
    v json;
    u json;
begin
    perform pg_temp.as_a();
    -- Mismo payload que tasks.ts para POST /task/create sin prioridad y con ella.
    v := create_task(p_task_list_id => 993101, p_title => 'TG-Crear', p_person_ids => null);
    if v is null or v->>'title' <> 'TG-Crear' or v->>'priority' <> 'media' then
        raise exception 'task_priority_rollback_guard G3: create_task por nombre devolvió %', v;
    end if;
    v := create_task(p_task_list_id => 993101, p_title => 'TG-Alta', p_person_ids => null, p_priority => 'alta');
    if v->>'priority' <> 'alta' then
        raise exception 'task_priority_rollback_guard G3: create_task con prioridad devolvió %', v;
    end if;
    -- PATCH /task/update.
    u := update_task(p_id => (v->>'id')::bigint, p_title => 'TG-Alta 2', p_person_ids => null);
    if u->>'title' <> 'TG-Alta 2' or u->>'priority' <> 'alta' then
        raise exception 'task_priority_rollback_guard G3: update_task por nombre devolvió %', u;
    end if;
    raise notice 'ok G3: una firma por RPC tras los intentos; create_task y update_task por nombre resuelven';
end $$;

-- ── Limpieza ──
select pg_temp.clean();
do $$
begin
    if exists (select 1 from app_user where id = 993101) or exists (select 1 from home where id = 993101) then
        raise exception 'task_priority_rollback_guard: quedaron filas scratch';
    end if;
    raise notice 'ok G-clean: 0 filas scratch';
end $$;
