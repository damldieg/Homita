-- client_request_reapply_check.sql — Vuelta de la ida 0035 → rollback_0035.sql → 0035 (R1-01 del change
-- ios-offline-outbox-tareas). Solo BD local, después de client_request_rollback_check.sql. ci.sh sustituye
-- la línea `-- @MIGRATION:<fichero>@` por supabase/migrations/<fichero>. Cada bloque emite 'ok RAx: …' o
-- aborta con 'client_request_reapply RAx: …'. Después ci.sh vuelve a pasar client_request_check (C1-C9).
--
-- RA1 de partida está el esquema revertido (sin client_request, firmas antiguas).
-- RA2 tras volver a aplicar 0035: una sola firma por RPC, la nueva con uuid; client_request existe con RLS.

\set ON_ERROR_STOP 1
do $$
begin
    if inet_server_addr() is not null and host(inet_server_addr()) not in ('127.0.0.1', '::1') then
        raise exception 'client_request_reapply_check: solo BD local (socket o loopback); servidor %', host(inet_server_addr());
    end if;
    if to_regclass('public.client_request') is not null
       or to_regprocedure('public.create_task(bigint,text,jsonb)') is null
       or to_regprocedure('public.create_task_list(text,text,text,boolean,boolean)') is null then
        raise exception 'client_request_reapply RA1: no se parte del esquema revertido por rollback_0035';
    end if;
    raise notice 'ok RA1: se parte del esquema revertido (sin client_request, firmas antiguas)';
end $$;

-- @MIGRATION:0035_client_request_idempotency.sql@

\echo '-- \\df tras volver a aplicar 0035'
\df public.create_task*

do $$
declare
    v_sigs text[];
begin
    select array_agg(oid::regprocedure::text order by proname) into v_sigs
      from pg_proc where pronamespace = 'public'::regnamespace and proname in ('create_task', 'create_task_list');
    if v_sigs is distinct from array['create_task(bigint,text,jsonb,uuid)',
                                     'create_task_list(text,text,text,boolean,boolean,uuid)'] then
        raise exception 'client_request_reapply RA2: firmas %', v_sigs;
    end if;
    if to_regclass('public.client_request') is null
       or not (select relrowsecurity from pg_class where oid = 'public.client_request'::regclass) then
        raise exception 'client_request_reapply RA2: client_request ausente o sin RLS';
    end if;
    raise notice 'ok RA2: 0035 reaplicada: una firma nueva por RPC y client_request con RLS';
end $$;
