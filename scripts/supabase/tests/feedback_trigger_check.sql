-- feedback_trigger_check.sql — Trigger de feedback (0031_feedback_trigger.sql, change feedback-trigger-migration).
-- Solo BD local, tras el reset 0001–0031. ci.sh sustituye cada línea `-- @MIGRATION@` por el texto de
-- 0031 (el check no puede leer ficheros del host: psql corre dentro del contenedor y recibe stdin).
-- Cada bloque emite 'ok Fx: …' o aborta con 'feedback_trigger Fx: …'.
--
-- F1 local: public.feedback no existe tras el reset.
-- F2 local: no hay trigger homita_feedback_creation (no habría webhook hacia producción).
-- F3 re-ejecutar 0031 en local no falla y sigue sin trigger.
-- F4 con una public.feedback scratch (en transacción), 0031 dos veces deja exactamente 1 trigger
--    AFTER INSERT FOR EACH ROW, habilitado, con URL/POST/cabeceras/{}/5000 de prod. Sin inserts: no hay webhook.
-- F5 tras el rollback no queda ni la tabla ni el trigger.

\set ON_ERROR_STOP 1
do $$
begin
    if inet_server_addr() is not null and host(inet_server_addr()) not in ('127.0.0.1', '::1') then
        raise exception 'feedback_trigger_check: solo BD local (socket o loopback); servidor %', host(inet_server_addr());
    end if;
end $$;

do $$
begin
    if to_regclass('public.feedback') is not null then
        raise exception 'feedback_trigger F1: public.feedback existe en local';
    end if;
    raise notice 'ok F1: public.feedback no existe en local';
    if exists (select 1 from pg_trigger where tgname = 'homita_feedback_creation') then
        raise exception 'feedback_trigger F2: el trigger existe en local';
    end if;
    raise notice 'ok F2: sin trigger homita_feedback_creation en local';
end $$;

-- @MIGRATION@

do $$
begin
    if to_regclass('public.feedback') is not null
       or exists (select 1 from pg_trigger where tgname = 'homita_feedback_creation') then
        raise exception 'feedback_trigger F3: tras re-ejecutar 0031 en local hay tabla o trigger';
    end if;
    raise notice 'ok F3: 0031 re-ejecutable en local, sin trigger';
end $$;

begin;
create table public.feedback (id bigint generated always as identity primary key);

-- @MIGRATION@

-- @MIGRATION@

do $$
declare
    v_n int;
    v_def text;
    v_type int2;
    v_en "char";
begin
    select count(*), max(pg_get_triggerdef(t.oid)), max(t.tgtype), max(t.tgenabled)
      into v_n, v_def, v_type, v_en
      from pg_trigger t
     where t.tgname = 'homita_feedback_creation' and t.tgrelid = 'public.feedback'::regclass and not t.tgisinternal;
    if v_n <> 1 then
        raise exception 'feedback_trigger F4: % triggers (esperado 1)', v_n;
    end if;
    if v_en <> 'O' or (v_type & 1) <> 1 or (v_type & 2) <> 0 or (v_type & 4) <> 4 then
        raise exception 'feedback_trigger F4: no es AFTER INSERT FOR EACH ROW habilitado (tgtype %, tgenabled %)', v_type, v_en;
    end if;
    if v_def not like '%supabase_functions.http_request(%'
       or v_def not like '%''https://jlmjeykqbspoohmtrhwb.supabase.co/functions/v1/procesar-feedback''%'
       or v_def not like '%''POST''%'
       or v_def not like '%''{"Content-type":"application/json"}''%'
       or v_def not like '%''{}''%'
       or v_def not like '%''5000''%' then
        raise exception 'feedback_trigger F4: definición distinta de prod: %', v_def;
    end if;
    raise notice 'ok F4: 1 trigger con la definición de prod e idempotente';
end $$;

rollback;

do $$
begin
    if to_regclass('public.feedback') is not null
       or exists (select 1 from pg_trigger where tgname = 'homita_feedback_creation') then
        raise exception 'feedback_trigger F5: quedan residuos tras el rollback';
    end if;
    raise notice 'ok F5: 0 residuos tras el rollback';
end $$;
