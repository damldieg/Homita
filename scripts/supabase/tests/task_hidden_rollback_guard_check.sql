-- task_hidden_rollback_guard_check.sql — Guarda LIFO de rollback_0038 con 0039 aplicada (change
-- ocultar-completadas-3-dias). Solo BD local, tras el reset 0001–0039. ci.sh sustituye
-- `-- @ROLLBACK:<fichero>@` por scripts/supabase/rollback/<fichero> y lo pasa por stdin.
--
-- Sin la guarda, rollback_0038 seguido de rollback_0037 con 0039 aplicada recrearía get_tasks,
-- get_task_detail y update_task sin el filtro de ocultas, con task.hidden_at todavía en la tabla.
-- Orden LIFO válido: rollback_0039 → rollback_0038 → rollback_0037 → rollback_0035.
--
-- G39-1 rollback_0038 aborta con su guarda (ci.sh exige el mensaje en el log) y no cambia nada:
--       task.hidden_at y su CHECK siguen, create_task sigue con el marcador `0038:` y las 7 funciones de
--       0039 siguen con el marcador `0039:`.
-- G39-clean estado final idéntico y 0 filas scratch (este check no crea filas).
--
-- El rollback se ejecuta con ON_ERROR_STOP desactivado: la guarda aborta la transacción y el resto del
-- fichero falla con «current transaction is aborted» hasta el commit (que hace ROLLBACK). Es ruido
-- esperado en el log. Si la guarda no saltara, el rollback se confirmaría y G39-1 fallaría (BD local a
-- medias: repetir ci.sh).

\set ON_ERROR_STOP 1
do $$
begin
    if inet_server_addr() is not null and host(inet_server_addr()) not in ('127.0.0.1', '::1') then
        raise exception 'task_hidden_rollback_guard_check: solo BD local (socket o loopback); servidor %', host(inet_server_addr());
    end if;
    if not exists (select 1 from information_schema.columns
                   where table_schema = 'public' and table_name = 'task' and column_name = 'hidden_at') then
        raise exception 'task_hidden_rollback_guard_check: 0039 no está aplicada (falta task.hidden_at)';
    end if;
end $$;

-- Estado esperado con 0039 (y 0038) aplicadas; null si coincide.
create function pg_temp.g39_state() returns text
language plpgsql as $$
declare
    v_unmarked text[];
begin
    if not exists (select 1 from information_schema.columns
                   where table_schema = 'public' and table_name = 'task' and column_name = 'hidden_at')
       or not exists (select 1 from pg_constraint where conname = 'task_hidden_at_consistent') then
        return 'falta task.hidden_at o task_hidden_at_consistent';
    end if;
    if to_regprocedure('public.create_task(bigint,text,jsonb,uuid,text)') is null
       or pg_get_functiondef('public.create_task(bigint,text,jsonb,uuid,text)'::regprocedure) not like '%0038:%' then
        return 'create_task sin la guarda 0038:';
    end if;
    select array_agg(proname::text order by proname) into v_unmarked
      from pg_proc where pronamespace = 'public'::regnamespace
       and proname in ('get_tasks', 'get_task_detail', 'complete_task', 'update_task', 'task_order',
                       'delete_task', 'fn_reorder_tasks')
       and pg_get_functiondef(oid) not like '%0039:%';
    if v_unmarked is not null then
        return format('funciones sin 0039: %s', v_unmarked);
    end if;
    return null;
end $$;

-- ── G39-1: rollback_0038 con 0039 aplicada ──
\set ON_ERROR_STOP 0
\echo '-- G39-1: rollback_0038 con 0039 aplicada (se espera la guarda y errores de transacción abortada)'
-- @ROLLBACK:rollback_0038.sql@
rollback;
\set ON_ERROR_STOP 1

do $$
declare
    v_err text := pg_temp.g39_state();
begin
    if v_err is not null then
        raise exception 'task_hidden_rollback_guard G39-1: rollback_0038 cambió el esquema: %', v_err;
    end if;
    raise notice 'ok G39-1: rollback_0038 abortó por la guarda y el esquema sigue con 0039 (hidden_at, CHECK y 0039:)';
end $$;

-- ── G39-clean: estado final ──
do $$
declare
    v_err text := pg_temp.g39_state();
begin
    if v_err is not null then
        raise exception 'task_hidden_rollback_guard G39-clean: estado final distinto: %', v_err;
    end if;
    raise notice 'ok G39-clean: estado final idéntico (0 filas scratch)';
end $$;
