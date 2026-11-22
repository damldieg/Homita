-- task_hidden_rollback_check.sql — Ida de la vuelta 0039 → rollback_0039.sql (change
-- ocultar-completadas-3-dias). Solo BD local, tras el reset 0001–0039. ci.sh sustituye la línea
-- `-- @ROLLBACK:<fichero>@` por scripts/supabase/rollback/<fichero> (psql corre dentro del contenedor y
-- recibe stdin). Cada bloque emite 'ok RBHn: …' o aborta con 'task_hidden_rollback RBHn: …'.
--
-- NO va en transacción: el rollback se confirma de verdad, para que ci.sh pase después los checks y
-- contract_check (modo pre-0039) sobre el esquema revertido y la ida y vuelta de 0038 anidada.
-- task_hidden_reapply_check.sql vuelve a aplicar 0039 al final.
--
-- RBH1 no existe task.hidden_at ni task_hidden_at_consistent.
-- RBH2 md5(pg_get_functiondef) de las 7 funciones (firmas vigentes de 0037/0029/0006) y
--      md5(pg_get_expr(polqual)) de task_select = constantes del reset 0001–0038 (las mismas de la
--      cabecera de rollback_0039.sql y de DEPLOY_0039.md P4). Una firma por función.
-- RBH3 grants iguales: EXECUTE para authenticated en las 6 RPC públicas (y service_role en get_tasks);
--      ni PUBLIC ni anon; fn_reorder_tasks sin authenticated.
-- RBH4 una tarea completada a −5 d (oculta antes del rollback) vuelve a salir en get_tasks y lleva
--      priority (filtro previo restaurado); get_task_detail la devuelve.
-- RBH5 rollback_0039 una segunda vez no falla y deja el mismo estado.
--
-- Fixture (ids 9992xx, auth_uid …1011): se borra al final.

\set ON_ERROR_STOP 1
do $$
begin
    if inet_server_addr() is not null and host(inet_server_addr()) not in ('127.0.0.1', '::1') then
        raise exception 'task_hidden_rollback_check: solo BD local (socket o loopback); servidor %', host(inet_server_addr());
    end if;
    if not exists (select 1 from information_schema.columns
                   where table_schema = 'public' and table_name = 'task' and column_name = 'hidden_at') then
        raise exception 'task_hidden_rollback_check: 0039 no está aplicada (falta task.hidden_at)';
    end if;
end $$;

create function pg_temp.clean() returns void
language plpgsql as $$
begin
    set local session_replication_role = replica;
    delete from task where task_list_id in (select id from task_list where home_id = 999201);
    delete from task_list_user where task_list_id in (select id from task_list where home_id = 999201);
    delete from task_list where home_id = 999201;
    delete from home_membership where home_id = 999201;
    delete from audit_log where home_id = 999201;
    update app_user set default_home_id = null where id = 999201;
    delete from home where id = 999201;
    delete from app_user where id = 999201;
    delete from auth.users where id = '00000000-0000-4000-8000-000000001011';
end $$;

create function pg_temp.rbh_state() returns text
language plpgsql as $$
declare
    v_want text[][] := array[
        ['complete_task(bigint,boolean)', '9ae29a1507fea681afbbbb95d4a91f42'],
        ['delete_task(bigint)', '739b0765bbe2dcf4feb2978eef6840d1'],
        ['fn_reorder_tasks(bigint)', 'e011b88332da15df3e0b365e50be996f'],
        ['get_task_detail(bigint)', '7836409cddb8166d96accf9eda9055e2'],
        ['get_tasks(boolean,bigint,boolean,text,text)', '33a865e264ce1a37b88fd5c3405cc6e8'],
        ['task_order(bigint,integer)', 'f6a3aaec2bf25d06aa401ef742d209ac'],
        ['update_task(bigint,text,jsonb,text)', 'c612b928103c69af64ba185d2f6553cf']];
    v_got text[][];
    v_md5 text;
begin
    if exists (select 1 from information_schema.columns
               where table_schema = 'public' and table_name = 'task' and column_name = 'hidden_at')
       or exists (select 1 from pg_constraint where conname = 'task_hidden_at_consistent') then
        return 'RBH1 sigue task.hidden_at o task_hidden_at_consistent';
    end if;
    select array_agg(array[oid::regprocedure::text, md5(pg_get_functiondef(oid))] order by oid::regprocedure::text)
      into v_got
      from pg_proc where pronamespace = 'public'::regnamespace
       and proname in ('get_tasks', 'get_task_detail', 'complete_task', 'update_task', 'task_order',
                       'delete_task', 'fn_reorder_tasks');
    if v_got is distinct from v_want then
        return format('RBH2 firmas/md5 %s', v_got);
    end if;
    select md5(pg_get_expr(polqual, polrelid)) into v_md5
      from pg_policy where polrelid = 'public.task'::regclass and polname = 'task_select' and polcmd = 'r';
    if v_md5 is distinct from 'b3d1a237c023b4ce73d89666567a1538' then
        return format('RBH2 policy task_select md5 %s', v_md5);
    end if;
    if exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace
                and p.proname in ('get_tasks', 'get_task_detail', 'complete_task', 'update_task', 'task_order', 'delete_task')
                and (p.proacl is null
                     or exists (select 1 from aclexplode(p.proacl) a where a.grantee = 0 and a.privilege_type = 'EXECUTE')
                     or has_function_privilege('anon', p.oid, 'execute')
                     or not has_function_privilege('authenticated', p.oid, 'execute')))
       or not has_function_privilege('service_role', 'get_tasks(boolean,bigint,boolean,text,text)', 'execute')
       or has_function_privilege('authenticated', 'fn_reorder_tasks(bigint)', 'execute')
       or has_function_privilege('anon', 'fn_reorder_tasks(bigint)', 'execute') then
        return 'RBH3 EXECUTE distinto del previo';
    end if;
    return null;
end $$;

select pg_temp.clean();

-- ── Fixture con 0039: una completada a −5 d (oculta) ──
set session_replication_role = replica;
insert into auth.users (id, email, raw_user_meta_data) values
    ('00000000-0000-4000-8000-000000001011', 'thr-a@check.homita.example', '{"name":"THR-A"}');
insert into app_user (id, auth_uid, name, email) values
    (999201, '00000000-0000-4000-8000-000000001011', 'THR-A', 'thr-a@check.homita.example');
set session_replication_role = default;

begin;
insert into home (id, name, status, is_personal, created_by) values (999201, 'THR-Hogar', 'active', false, 999201);
insert into home_membership (id, home_id, app_user_id, role) values (999201, 999201, 999201, 'admin');
update app_user set default_home_id = 999201 where id = 999201;
insert into task_list (id, name, color, token, sort, home_id) values (999201, 'THR-L', '#222222', 'thr-tok-1', 'custom', 999201);
insert into task_list_user (task_list_id, user_id, role, widget, dashboard, home_id) values (999201, 999201, 'owner', true, true, 999201);
insert into task (id, task_list_id, title, completed_at, hidden_at, priority) values
    (999201, 999201, 'THR-Vieja', (now() at time zone 'UTC') - interval '5 days',
     (((now() at time zone 'UTC') - interval '5 days') + interval '3 days') at time zone 'UTC', 'alta');
commit;

do $$
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000001011', true);
    if json_array_length(get_tasks(p_task_list_id => 999201)) <> 0 then
        raise exception 'task_hidden_rollback: con 0039 la tarea a −5 d debería estar oculta';
    end if;
end $$;

-- @ROLLBACK:rollback_0039.sql@

\echo '-- \\df tras rollback_0039'
\df public.get_tasks
\df public.update_task

do $$
declare
    v_err text := pg_temp.rbh_state();
begin
    if v_err is not null then
        raise exception 'task_hidden_rollback %', v_err;
    end if;
    raise notice 'ok RBH1: sin task.hidden_at ni task_hidden_at_consistent';
    raise notice 'ok RBH2: md5 de las 7 funciones (firmas vigentes) y de task_select = constantes de 0001–0038';
    raise notice 'ok RBH3: EXECUTE para authenticated (y service_role en get_tasks); sin PUBLIC ni anon';
end $$;

-- ── RBH4: la de −5 d vuelve a verse ──
do $$
declare
    v json;
begin
    perform set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000001011', true);
    v := get_tasks(p_task_list_id => 999201);
    if json_array_length(v) <> 1 or (v->0->>'id')::bigint <> 999201 or v->0->>'priority' is distinct from 'alta' then
        raise exception 'task_hidden_rollback RBH4: get_tasks %', v;
    end if;
    if (get_task_detail(999201)->>'id')::bigint <> 999201 then
        raise exception 'task_hidden_rollback RBH4: get_task_detail no la devuelve';
    end if;
    raise notice 'ok RBH4: la completada a −5 d vuelve a salir en get_tasks (con priority) y en get_task_detail';
end $$;

-- RBH5: segunda pasada.
-- @ROLLBACK:rollback_0039.sql@

do $$
declare
    v_err text := pg_temp.rbh_state();
begin
    if v_err is not null then
        raise exception 'task_hidden_rollback RBH5 (2.ª pasada): %', v_err;
    end if;
    raise notice 'ok RBH5: rollback_0039 dos veces sin error y con el mismo estado';
end $$;

select pg_temp.clean();
