-- task_priority_rollback_check.sql — Ida de la vuelta 0037 → rollback_0037.sql (change prioridad-tarea).
-- Solo BD local, tras el reset 0001–0037. ci.sh sustituye la línea `-- @ROLLBACK:<fichero>@` por
-- scripts/supabase/rollback/<fichero> (psql corre dentro del contenedor y recibe stdin). Cada bloque
-- emite 'ok PRx: …' o aborta con 'task_priority_rollback PRx: …'.
--
-- NO va en transacción: el rollback se confirma de verdad, para que ci.sh pase después los checks y
-- contract_check (modo pre-0037) sobre el esquema revertido y la ida y vuelta de 0035 anidada.
-- task_priority_reapply_check.sql vuelve a aplicar 0037 al final.
--
-- PR1 una sola firma por RPC y es la previa: get_tasks(boolean,bigint,boolean),
--     create_task(bigint,text,jsonb,uuid), update_task(bigint,text,jsonb); ninguna con p_priority.
-- PR2 ACL previas: EXECUTE para authenticated (y service_role en get_tasks); ni PUBLIC ni anon.
-- PR3 sin la columna task.priority ni task_priority_check; get_task_detail sin 'priority'.
-- PR4 rollback_0037 una segunda vez no falla y deja el mismo estado (idempotente).

\set ON_ERROR_STOP 1
do $$
begin
    if inet_server_addr() is not null and host(inet_server_addr()) not in ('127.0.0.1', '::1') then
        raise exception 'task_priority_rollback_check: solo BD local (socket o loopback); servidor %', host(inet_server_addr());
    end if;
    if not exists (select 1 from information_schema.columns
                   where table_schema = 'public' and table_name = 'task' and column_name = 'priority') then
        raise exception 'task_priority_rollback_check: 0037 no está aplicada (falta task.priority)';
    end if;
end $$;

create function pg_temp.pr_state() returns text
language plpgsql as $$
declare
    v_sigs text[];
begin
    select array_agg(oid::regprocedure::text order by proname) into v_sigs
      from pg_proc where pronamespace = 'public'::regnamespace and proname in ('create_task', 'get_tasks', 'update_task');
    if v_sigs is distinct from array['create_task(bigint,text,jsonb,uuid)',
                                     'get_tasks(boolean,bigint,boolean)',
                                     'update_task(bigint,text,jsonb)'] then
        return format('PR1 firmas %s', v_sigs);
    end if;
    if exists (select 1 from pg_proc where pronamespace = 'public'::regnamespace
                and 'p_priority' = any(proargnames)) then
        return 'PR1 queda una función con p_priority';
    end if;
    if exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace
                and p.proname in ('create_task', 'get_tasks', 'update_task')
                and (p.proacl is null
                     or exists (select 1 from aclexplode(p.proacl) a where a.grantee = 0 and a.privilege_type = 'EXECUTE')
                     or has_function_privilege('anon', p.oid, 'execute')
                     or not has_function_privilege('authenticated', p.oid, 'execute')))
       or not has_function_privilege('service_role', 'get_tasks(boolean,bigint,boolean)', 'execute') then
        return 'PR2 EXECUTE distinto del previo (authenticated sí, service_role en get_tasks; PUBLIC y anon no)';
    end if;
    if exists (select 1 from information_schema.columns
               where table_schema = 'public' and table_name = 'task' and column_name = 'priority')
       or exists (select 1 from pg_constraint where conname = 'task_priority_check') then
        return 'PR3 sigue la columna priority o su CHECK';
    end if;
    if pg_get_functiondef('get_task_detail(bigint)'::regprocedure) like '%priority%'
       or pg_get_functiondef('get_tasks(boolean,bigint,boolean)'::regprocedure) like '%priority%' then
        return 'PR3 get_task_detail/get_tasks siguen nombrando priority';
    end if;
    return null;
end $$;

-- @ROLLBACK:rollback_0037.sql@

\echo '-- \\df tras rollback_0037'
\df public.get_tasks
\df public.create_task
\df public.update_task

do $$
declare
    v_err text := pg_temp.pr_state();
begin
    if v_err is not null then
        raise exception 'task_priority_rollback %', v_err;
    end if;
    raise notice 'ok PR1: una firma por RPC, la previa (get_tasks de 3, create_task de 0035, update_task de 0029)';
    raise notice 'ok PR2: EXECUTE para authenticated (y service_role en get_tasks); sin PUBLIC ni anon';
    raise notice 'ok PR3: sin task.priority ni task_priority_check; lecturas sin priority';
end $$;

-- PR4: segunda pasada.
-- @ROLLBACK:rollback_0037.sql@

do $$
declare
    v_err text := pg_temp.pr_state();
begin
    if v_err is not null then
        raise exception 'task_priority_rollback PR4 (2.ª pasada): %', v_err;
    end if;
    raise notice 'ok PR4: rollback_0037 dos veces sin error y con el mismo estado';
end $$;
