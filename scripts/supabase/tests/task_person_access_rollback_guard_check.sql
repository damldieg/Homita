-- task_person_access_rollback_guard_check.sql — Guarda LIFO de rollback_0037 con 0038 aplicada (A-8 del
-- change asignar-alta-lista). Solo BD local, tras el reset 0001–0038. ci.sh sustituye
-- `-- @ROLLBACK:<fichero>@` por scripts/supabase/rollback/<fichero> y lo pasa por stdin.
--
-- Sin la guarda, rollback_0037 con 0038 aplicada borra create_task(bigint,text,jsonb,uuid,text) y
-- restaura la de 4 argumentos con el cuerpo de 0035, sin error: se pierde en silencio la guarda de
-- acceso a la lista (y la prioridad). Orden LIFO válido: rollback_0038 → rollback_0037 → rollback_0035.
--
-- G38-1 rollback_0037 aborta con su guarda (ci.sh exige el mensaje en el log) y no cambia nada: una
--       sola firma por RPC (la de 0037), create_task sigue con el marcador `0038:` y task.priority sigue.
-- G38-clean estado final idéntico y 0 filas scratch (este check no crea filas).
--
-- El rollback se ejecuta con ON_ERROR_STOP desactivado: la guarda aborta la transacción y el resto del
-- fichero falla con «current transaction is aborted» hasta el commit (que hace ROLLBACK). Es ruido
-- esperado en el log. Si la guarda no saltara, el rollback se confirmaría y G38-1 fallaría (BD local a
-- medias: repetir ci.sh).

\set ON_ERROR_STOP 1
do $$
begin
    if inet_server_addr() is not null and host(inet_server_addr()) not in ('127.0.0.1', '::1') then
        raise exception 'task_person_access_rollback_guard_check: solo BD local (socket o loopback); servidor %', host(inet_server_addr());
    end if;
    -- IF anidados: el cast ::regprocedure solo se evalúa si la firma existe (OR no cortocircuita ahí).
    if to_regprocedure('public.create_task(bigint,text,jsonb,uuid,text)') is null then
        raise exception 'task_person_access_rollback_guard_check: 0038 no está aplicada (create_task sin la guarda 0038:)';
    else
        if pg_get_functiondef('public.create_task(bigint,text,jsonb,uuid,text)'::regprocedure) not like '%0038:%' then
            raise exception 'task_person_access_rollback_guard_check: 0038 no está aplicada (create_task sin la guarda 0038:)';
        end if;
    end if;
end $$;

-- Estado esperado con 0038 (y 0037) aplicadas; null si coincide.
create function pg_temp.g38_state() returns text
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
    if pg_get_functiondef('public.create_task(bigint,text,jsonb,uuid,text)'::regprocedure) not like '%0038:%' then
        return 'create_task sin la guarda 0038:';
    end if;
    if not exists (select 1 from information_schema.columns
                   where table_schema = 'public' and table_name = 'task' and column_name = 'priority') then
        return 'falta task.priority';
    end if;
    return null;
end $$;

-- ── G38-1: rollback_0037 con 0038 aplicada ──
\set ON_ERROR_STOP 0
\echo '-- G38-1: rollback_0037 con 0038 aplicada (se espera la guarda y errores de transacción abortada)'
-- @ROLLBACK:rollback_0037.sql@
rollback;
\set ON_ERROR_STOP 1

do $$
declare
    v_err text := pg_temp.g38_state();
begin
    if v_err is not null then
        raise exception 'task_person_access_rollback_guard G38-1: rollback_0037 cambió el esquema: %', v_err;
    end if;
    raise notice 'ok G38-1: rollback_0037 abortó por la guarda y el esquema sigue con 0038 (firma, guarda y priority)';
end $$;

-- ── G38-clean: estado final ──
do $$
declare
    v_err text := pg_temp.g38_state();
begin
    if v_err is not null then
        raise exception 'task_person_access_rollback_guard G38-clean: estado final distinto: %', v_err;
    end if;
    raise notice 'ok G38-clean: estado final idéntico (0 filas scratch)';
end $$;
