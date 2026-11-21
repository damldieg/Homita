-- task_priority_reapply_check.sql — Vuelta de la ida 0037 → rollback_0037.sql → 0037 (change
-- prioridad-tarea). Solo BD local, después de task_priority_rollback_check.sql (y de la ida y vuelta
-- de 0035 anidada). ci.sh sustituye la línea `-- @MIGRATION:<fichero>@` por
-- supabase/migrations/<fichero>. Cada bloque emite 'ok PAx: …' o aborta con 'task_priority_reapply PAx: …'.
-- Después ci.sh vuelve a pasar task_priority_check (P1-P10), client_request_check (C1-C9) y contract_check.
--
-- PA1 de partida está el esquema revertido (sin task.priority, firmas previas); se insertan tareas
--     sin la columna (como las de prod antes de 0037).
-- PA2 tras reaplicar 0037: esas filas quedan en 'media' con updated_at sin cambios (backfill por
--     default constante, sin reescribir updated_at).
-- PA3 una sola firma por RPC, la nueva.

\set ON_ERROR_STOP 1
do $$
begin
    if inet_server_addr() is not null and host(inet_server_addr()) not in ('127.0.0.1', '::1') then
        raise exception 'task_priority_reapply_check: solo BD local (socket o loopback); servidor %', host(inet_server_addr());
    end if;
    if exists (select 1 from information_schema.columns
               where table_schema = 'public' and table_name = 'task' and column_name = 'priority')
       or to_regprocedure('public.get_tasks(boolean,bigint,boolean)') is null
       or to_regprocedure('public.create_task(bigint,text,jsonb,uuid)') is null
       or to_regprocedure('public.update_task(bigint,text,jsonb)') is null then
        raise exception 'task_priority_reapply PA1: no se parte del esquema revertido por rollback_0037';
    end if;
    if not exists (select 1 from task_list) then
        raise exception 'task_priority_reapply PA1: sin listas donde insertar (¿seed?)';
    end if;
end $$;

-- Filas "antiguas": sin triggers (replica) para fijar updated_at a un valor conocido.
create temp table pa_rows as select 0::bigint as id, null::timestamp as updated_at limit 0;
set session_replication_role = replica;
with ins as (
    insert into task (task_list_id, title, updated_at)
    select (select id from task_list order by id limit 1), 'PA-Antigua ' || g, timestamp '2026-01-02 03:04:05'
    from generate_series(1, 3) g
    returning id, updated_at
)
insert into pa_rows select id, updated_at from ins;
set session_replication_role = default;
do $$
begin
    if (select count(*) from pa_rows) <> 3 then
        raise exception 'task_priority_reapply PA1: no se insertaron las filas antiguas';
    end if;
    raise notice 'ok PA1: esquema revertido (sin task.priority, firmas previas); 3 tareas insertadas sin la columna';
end $$;

-- @MIGRATION:0037_task_priority.sql@

\echo '-- \\df tras volver a aplicar 0037'
\df public.get_tasks
\df public.create_task
\df public.update_task

do $$
begin
    if exists (select 1 from pa_rows r join task t on t.id = r.id
               where t.priority is distinct from 'media' or t.updated_at is distinct from r.updated_at)
       or (select count(*) from task t join pa_rows r on r.id = t.id) <> 3 then
        raise exception 'task_priority_reapply PA2: filas antiguas sin media o con updated_at cambiado';
    end if;
    if exists (select 1 from task where priority is null or priority not in ('alta', 'media', 'baja')) then
        raise exception 'task_priority_reapply PA2: filas con prioridad inválida';
    end if;
    raise notice 'ok PA2: las filas previas quedan en media con updated_at sin cambios';
end $$;

do $$
declare
    v_sigs text[];
begin
    select array_agg(oid::regprocedure::text order by proname) into v_sigs
      from pg_proc where pronamespace = 'public'::regnamespace and proname in ('create_task', 'get_tasks', 'update_task');
    if v_sigs is distinct from array['create_task(bigint,text,jsonb,uuid,text)',
                                     'get_tasks(boolean,bigint,boolean,text,text)',
                                     'update_task(bigint,text,jsonb,text)'] then
        raise exception 'task_priority_reapply PA3: firmas %', v_sigs;
    end if;
    raise notice 'ok PA3: 0037 reaplicada: una firma nueva por RPC';
end $$;

-- Limpieza de las filas del check.
set session_replication_role = replica;
delete from task where id in (select id from pa_rows);
set session_replication_role = default;
