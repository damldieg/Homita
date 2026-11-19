-- feedback_trigger_check.sql — Trigger de feedback: 0031_feedback_trigger.sql (change
-- feedback-trigger-migration) y 0033_feedback_trigger_secret.sql (change feedback-trello-gate).
-- Solo BD local, tras el reset. ci.sh sustituye cada línea `-- @MIGRATION:<fichero>@` por el texto de
-- supabase/migrations/<fichero> y cada `-- @ROLLBACK:<fichero>@` por scripts/supabase/rollback/<fichero>
-- (el check no puede leer ficheros del host: psql corre dentro del contenedor y recibe stdin).
-- Cada bloque emite 'ok Fx: …' o aborta con 'feedback_trigger Fx: …'.
--
-- F1 local: public.feedback no existe tras el reset.
-- F2 local: no hay trigger homita_feedback_creation (no habría webhook hacia producción).
-- F3 re-ejecutar 0031 en local no falla y sigue sin trigger.
-- F4 con una public.feedback scratch (en transacción), 0031 dos veces deja exactamente 1 trigger
--    AFTER INSERT FOR EACH ROW, habilitado, con URL/POST/cabeceras/{}/5000 de prod. Sin inserts: no hay webhook.
-- F5 tras el rollback no queda ni la tabla ni el trigger.
-- F6 0033 en local no crea funciones ni trigger.
-- F7 con una public.feedback scratch (en transacción), 0031 y luego 0033 dos veces dejan 1 trigger AFTER
--    INSERT FOR EACH ROW habilitado que ejecuta homita_feedback_notify; las dos funciones son SECURITY
--    DEFINER con search_path="".
-- F8 ni anon, ni authenticated, ni service_role tienen EXECUTE sobre las dos funciones.
-- F9 sin secreto en Vault (se aborta si ya existe uno), dispatch devuelve null y un INSERT como
--    authenticated no falla ni encola nada.
-- F10 con vault.create_secret('local-test-no-real', …) DENTRO de la transacción: (a) si net.http_post no
--    existe o falla, el INSERT como authenticated no falla; (b) un INSERT como authenticated pide
--    exactamente 1 net.http_post con la URL de prod, cabecera x-feedback-secret, body con solo record.id y
--    timeout 30000. En local pg_net no está instalado: (b) usa un stub de net.http_post (misma firma que
--    pg_net 0.20.4) que registra los argumentos; si pg_net estuviera instalado se mira la cola real.
-- F11 rollback_0033 restaura el trigger de 0031 sin funciones; tras el rollback de la transacción no queda
--    tabla, trigger, funciones, secreto ni filas en la cola para la URL. pg_net solo envía lo confirmado:
--    no sale ninguna petición a producción.

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

-- @MIGRATION:0031_feedback_trigger.sql@

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

-- @MIGRATION:0031_feedback_trigger.sql@

-- @MIGRATION:0031_feedback_trigger.sql@

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

-- ---------------------------------------------------------------------------------------------------
-- 0033: trigger con secreto de Vault (change feedback-trello-gate)

-- @MIGRATION:0033_feedback_trigger_secret.sql@

do $$
begin
    if to_regclass('public.feedback') is not null
       or exists (select 1 from pg_trigger where tgname = 'homita_feedback_creation')
       or exists (select 1 from pg_proc where proname in ('homita_feedback_dispatch', 'homita_feedback_notify')) then
        raise exception 'feedback_trigger F6: tras ejecutar 0033 en local hay tabla, trigger o funciones';
    end if;
    raise notice 'ok F6: 0033 en local no crea funciones ni trigger';
end $$;

do $$
begin
    if exists (select 1 from vault.secrets where name = 'feedback_webhook_secret') then
        raise exception 'feedback_trigger F9: ya existe un secreto feedback_webhook_secret en Vault local; abortado';
    end if;
end $$;

begin;
create table public.feedback (id bigint generated always as identity primary key);
grant insert on public.feedback to authenticated;

-- @MIGRATION:0031_feedback_trigger.sql@

-- @MIGRATION:0033_feedback_trigger_secret.sql@

-- @MIGRATION:0033_feedback_trigger_secret.sql@

do $$
declare
    v_n int;
    v_type int2;
    v_en "char";
    v_fn regproc;
    v_bad int;
begin
    select count(*), max(t.tgtype), max(t.tgenabled), max(t.tgfoid::regproc::text)::regproc
      into v_n, v_type, v_en, v_fn
      from pg_trigger t
     where t.tgname = 'homita_feedback_creation' and t.tgrelid = 'public.feedback'::regclass and not t.tgisinternal;
    if v_n <> 1 then
        raise exception 'feedback_trigger F7: % triggers (esperado 1)', v_n;
    end if;
    if v_en <> 'O' or (v_type & 1) <> 1 or (v_type & 2) <> 0 or (v_type & 4) <> 4 then
        raise exception 'feedback_trigger F7: no es AFTER INSERT FOR EACH ROW habilitado (tgtype %, tgenabled %)', v_type, v_en;
    end if;
    if v_fn <> 'public.homita_feedback_notify'::regproc then
        raise exception 'feedback_trigger F7: el trigger ejecuta % (esperado homita_feedback_notify)', v_fn;
    end if;
    select count(*) into v_bad
      from (values ('public.homita_feedback_dispatch(bigint)'), ('public.homita_feedback_notify()')) f(sig)
      left join pg_proc p on p.oid = to_regprocedure(f.sig)
     where p.oid is null or not p.prosecdef or p.proconfig is distinct from array['search_path=""'];
    if v_bad <> 0 then
        raise exception 'feedback_trigger F7: % funciones ausentes o sin SECURITY DEFINER / search_path=""', v_bad;
    end if;
    raise notice 'ok F7: 1 trigger AFTER INSERT -> homita_feedback_notify; funciones DEFINER con search_path vacío';
end $$;

do $$
declare
    v_bad text;
begin
    select string_agg(r || ' ' || f, ', ') into v_bad
      from unnest(array['anon', 'authenticated', 'service_role']) r,
           unnest(array['public.homita_feedback_dispatch(bigint)', 'public.homita_feedback_notify()']) f
     where has_function_privilege(r, f, 'execute');
    if v_bad is not null then
        raise exception 'feedback_trigger F8: EXECUTE concedido a %', v_bad;
    end if;
    raise notice 'ok F8: sin EXECUTE para anon, authenticated ni service_role';
end $$;

-- F9: sin secreto en Vault.
set local role authenticated;
insert into public.feedback default values;
reset role;

do $$
declare
    v_n int;
begin
    if public.homita_feedback_dispatch(1) is not null then
        raise exception 'feedback_trigger F9: dispatch sin secreto devolvió un id de petición';
    end if;
    if (select count(*) from public.feedback) <> 1 then
        raise exception 'feedback_trigger F9: el INSERT como authenticated no quedó';
    end if;
    -- La cola solo existe con pg_net instalado: consulta dinámica (plpgsql no resuelve la tabla si falta).
    if to_regclass('net.http_request_queue') is not null then
        execute 'select count(*) from net.http_request_queue where url = $1' into v_n
          using 'https://jlmjeykqbspoohmtrhwb.supabase.co/functions/v1/procesar-feedback';
        if v_n <> 0 then
            raise exception 'feedback_trigger F9: se encoló una petición sin secreto';
        end if;
    end if;
    raise notice 'ok F9: sin secreto el INSERT no falla y no se encola nada';
end $$;

-- F10: con secreto de prueba (solo en esta transacción).
select vault.create_secret('local-test-no-real', 'feedback_webhook_secret', 'feedback_trigger_check (rollback)') is not null as secreto_de_prueba;

-- (a) sin pg_net, net.http_post no existe: el error se traga y el INSERT sigue.
set local role authenticated;
insert into public.feedback default values;
reset role;

do $$
declare
    v_stub boolean := to_regnamespace('net') is null;
begin
    if (select count(*) from public.feedback) <> 2 then
        raise exception 'feedback_trigger F10: el INSERT con secreto como authenticated no quedó';
    end if;
    if v_stub then
        -- Stub de net.http_post con la firma de pg_net 0.20.4 (T0): registra los argumentos.
        execute 'create schema net';
        execute 'create table net.stub_calls (url text, body jsonb, params jsonb, headers jsonb, timeout_milliseconds int)';
        execute $f$
            create function net.http_post(url text, body jsonb default '{}', params jsonb default '{}',
                                          headers jsonb default '{"Content-Type": "application/json"}',
                                          timeout_milliseconds int default 5000)
            returns bigint language sql as
            'insert into net.stub_calls values (url, body, params, headers, timeout_milliseconds) returning 1::bigint'
        $f$;
    end if;
    raise notice 'ok F10a: con secreto y net.http_post % el INSERT no falla', case when v_stub then 'ausente' else 'real' end;
end $$;

-- (b) INSERT como authenticated con net.http_post disponible (stub o pg_net real).
set local role authenticated;
insert into public.feedback default values;
reset role;

do $$
declare
    v_id bigint := (select max(id) from public.feedback);
    v_n int;
    v_r record;
    v_url constant text := 'https://jlmjeykqbspoohmtrhwb.supabase.co/functions/v1/procesar-feedback';
    v_body jsonb;
begin
    v_body := jsonb_build_object('type', 'INSERT', 'table', 'feedback', 'schema', 'public',
                                 'record', jsonb_build_object('id', v_id));
    if to_regclass('net.stub_calls') is not null then
        select count(*) into v_n from net.stub_calls;
        select * into v_r from net.stub_calls;
        if v_n <> 1 or v_r.url <> v_url or v_r.body <> v_body or v_r.params <> '{}'::jsonb
           or v_r.headers <> '{"Content-Type": "application/json", "x-feedback-secret": "local-test-no-real"}'::jsonb
           or v_r.timeout_milliseconds <> 30000 then
            raise exception 'feedback_trigger F10: llamada a net.http_post incorrecta (n %, %)', v_n, v_r;
        end if;
        raise notice 'ok F10: 1 net.http_post (stub: pg_net no instalado en local) con URL, x-feedback-secret, record.id y 30000';
    else
        -- Con pg_net real, el INSERT de (a) también encola: se mira la fila del último id.
        execute 'select count(*) from net.http_request_queue q
                  where q.url = $1 and convert_from(q.body, ''utf8'')::jsonb = $2' into v_n using v_url, v_body;
        execute 'select q.method::text as method, q.headers, convert_from(q.body, ''utf8'')::jsonb as body,
                        q.timeout_milliseconds
                   from net.http_request_queue q
                  where q.url = $1 and convert_from(q.body, ''utf8'')::jsonb = $2' into v_r using v_url, v_body;
        if v_n <> 1 or v_r.method <> 'POST' or v_r.body <> v_body
           or v_r.headers ->> 'x-feedback-secret' is distinct from 'local-test-no-real'
           or v_r.timeout_milliseconds <> 30000 then
            raise exception 'feedback_trigger F10: cola de pg_net incorrecta (n %, %)', v_n, v_r;
        end if;
        raise notice 'ok F10: 1 fila en net.http_request_queue (pg_net real) con URL, POST, x-feedback-secret, record.id y 30000';
    end if;
end $$;

-- F11: rollback_0033 dentro de la transacción y luego rollback de todo.
-- @ROLLBACK:rollback_0033.sql@

do $$
declare
    v_def text;
begin
    select pg_get_triggerdef(t.oid) into v_def
      from pg_trigger t
     where t.tgname = 'homita_feedback_creation' and t.tgrelid = 'public.feedback'::regclass;
    if exists (select 1 from pg_proc where proname in ('homita_feedback_dispatch', 'homita_feedback_notify'))
       or v_def is null
       or v_def not like '%supabase_functions.http_request(%'
       or v_def not like '%''https://jlmjeykqbspoohmtrhwb.supabase.co/functions/v1/procesar-feedback''%'
       or v_def not like '%''5000''%' then
        raise exception 'feedback_trigger F11: rollback_0033 no restauró el trigger de 0031 (%)', v_def;
    end if;
end $$;

rollback;

do $$
declare
    v_n int;
begin
    if to_regclass('public.feedback') is not null
       or exists (select 1 from pg_trigger where tgname = 'homita_feedback_creation')
       or exists (select 1 from pg_proc where proname in ('homita_feedback_dispatch', 'homita_feedback_notify'))
       or exists (select 1 from vault.secrets where name = 'feedback_webhook_secret')
       or to_regnamespace('net') is not null and to_regclass('net.http_request_queue') is null then
        raise exception 'feedback_trigger F11: quedan residuos tras el rollback';
    end if;
    if to_regclass('net.http_request_queue') is not null then
        execute 'select count(*) from net.http_request_queue where url = $1' into v_n
          using 'https://jlmjeykqbspoohmtrhwb.supabase.co/functions/v1/procesar-feedback';
        if v_n <> 0 then
            raise exception 'feedback_trigger F11: quedan peticiones a prod en la cola de pg_net';
        end if;
    end if;
    raise notice 'ok F11: rollback_0033 restaura 0031; 0 residuos (tabla, trigger, funciones, secreto, cola)';
end $$;
