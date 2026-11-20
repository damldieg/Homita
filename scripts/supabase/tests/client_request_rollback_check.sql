-- client_request_rollback_check.sql — Ida de la vuelta 0035 → rollback_0035.sql (R1-01 del change
-- ios-offline-outbox-tareas). Solo BD local, tras el reset 0001–0035. ci.sh sustituye la línea
-- `-- @ROLLBACK:<fichero>@` por scripts/supabase/rollback/<fichero> (psql corre dentro del contenedor y
-- recibe stdin: no puede leer ficheros del host). Cada bloque emite 'ok RBx: …' o aborta con
-- 'client_request_rollback RBx: …'.
--
-- NO va en transacción: el rollback se confirma de verdad, para que ci.sh pase después
-- acl_can_edit_check, permisos_matriz_check, home_checks_compat y contract_check sobre el esquema
-- revertido. client_request_reapply_check.sql vuelve a aplicar 0035 al final.
--
-- RB1 una sola firma por RPC y es la antigua: create_task(bigint,text,jsonb) y
--     create_task_list(text,text,text,boolean,boolean); ninguna función pública con p_client_request_id.
-- RB2 grants originales (0006/0025/0029): EXECUTE para authenticated; ni PUBLIC ni anon (ACL explícita,
--     no la de por defecto).
-- RB3 no existe la tabla client_request.
-- RB4 rollback_0035 una segunda vez no falla y deja el mismo estado (idempotente).

\set ON_ERROR_STOP 1
do $$
begin
    if inet_server_addr() is not null and host(inet_server_addr()) not in ('127.0.0.1', '::1') then
        raise exception 'client_request_rollback_check: solo BD local (socket o loopback); servidor %', host(inet_server_addr());
    end if;
    if to_regclass('public.client_request') is null then
        raise exception 'client_request_rollback_check: 0035 no está aplicada (falta client_request)';
    end if;
end $$;

create function pg_temp.rb_state() returns text
language plpgsql as $$
declare
    v_sigs text[];
begin
    select array_agg(oid::regprocedure::text order by proname) into v_sigs
      from pg_proc where pronamespace = 'public'::regnamespace and proname in ('create_task', 'create_task_list');
    if v_sigs is distinct from array['create_task(bigint,text,jsonb)',
                                     'create_task_list(text,text,text,boolean,boolean)'] then
        return format('RB1 firmas %s', v_sigs);
    end if;
    if exists (select 1 from pg_proc where pronamespace = 'public'::regnamespace
                and 'p_client_request_id' = any(proargnames)) then
        return 'RB1 queda una función con p_client_request_id';
    end if;
    if exists (select 1 from pg_proc p where p.oid in ('create_task(bigint,text,jsonb)'::regprocedure,
                                                       'create_task_list(text,text,text,boolean,boolean)'::regprocedure)
                and (p.proacl is null
                     or exists (select 1 from aclexplode(p.proacl) a where a.grantee = 0 and a.privilege_type = 'EXECUTE')
                     or has_function_privilege('anon', p.oid, 'execute')
                     or not has_function_privilege('authenticated', p.oid, 'execute'))) then
        return 'RB2 EXECUTE distinto del original (authenticated sí; PUBLIC y anon no)';
    end if;
    if to_regclass('public.client_request') is not null then
        return 'RB3 client_request sigue existiendo';
    end if;
    return null;
end $$;

-- @ROLLBACK:rollback_0035.sql@

\echo '-- \\df tras rollback_0035'
\df public.create_task*
select oid::regprocedure as funcion, proacl as acl
  from pg_proc where pronamespace = 'public'::regnamespace and proname in ('create_task', 'create_task_list')
 order by proname;

do $$
declare
    v_err text := pg_temp.rb_state();
begin
    if v_err is not null then
        raise exception 'client_request_rollback %', v_err;
    end if;
    raise notice 'ok RB1: una firma por RPC, la antigua (create_task(bigint,text,jsonb), create_task_list(text,text,text,boolean,boolean))';
    raise notice 'ok RB2: EXECUTE para authenticated (más postgres y service_role, como antes de 0035); sin PUBLIC ni anon';
    raise notice 'ok RB3: no existe client_request';
end $$;

-- RB4: segunda pasada.
-- @ROLLBACK:rollback_0035.sql@

do $$
declare
    v_err text := pg_temp.rb_state();
begin
    if v_err is not null then
        raise exception 'client_request_rollback RB4 (2.ª pasada): %', v_err;
    end if;
    raise notice 'ok RB4: rollback_0035 dos veces sin error y con el mismo estado';
end $$;
