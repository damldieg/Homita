-- feedback_trigger_check.sql — Trigger de feedback: 0031_feedback_trigger.sql (change
-- feedback-trigger-migration) y 0034_feedback_trigger_secret.sql (change feedback-trello-gate, D-023).
-- Solo BD local, tras el reset (0031 -> 0032_feedback_schema -> 0033 -> 0034): public.feedback es la tabla
-- real de 0032_feedback_schema y el trigger es el de 0034, inerte sin URL ni secreto en Vault.
-- ci.sh sustituye cada línea `-- @MIGRATION:<fichero>@` por el texto de supabase/migrations/<fichero> y
-- cada `-- @ROLLBACK:<fichero>@` por scripts/supabase/rollback/<fichero> (el check no puede leer ficheros
-- del host: psql corre dentro del contenedor y recibe stdin). Cada bloque emite 'ok Fx: …' o aborta con
-- 'feedback_trigger Fx: …'.
--
-- Reglas: aborta si Vault local ya tiene feedback_webhook_url/secret; todo lo que muta va en
-- `begin … rollback`; la URL https://feedback-test.invalid/functions/v1/procesar-feedback y el secreto
-- local-test-no-real solo existen dentro de esas transacciones (la URL de prod solo entra en Vault en la de
-- F11, después del último INSERT, para ejercitar rollback_0034); NINGÚN INSERT con el trigger de 0031
-- presente (dispararía supabase_functions.http_request hacia prod). Los INSERT van como `authenticated` con
-- los claims de un usuario existente en auth.users (seed de demo.sh up; si no hay ninguno, aborta).
-- pg_net solo envía lo confirmado: con el rollback no sale ninguna petición.
--
-- F1 tras el reset: 1 trigger homita_feedback_creation en public.feedback, AFTER INSERT FOR EACH ROW,
--    habilitado, que ejecuta public.homita_feedback_notify.
-- F2 ningún trigger usa supabase_functions.http_request ni la URL de prod; Vault sin entradas
--    feedback_webhook_*; prosrc de dispatch sin la URL de prod.
-- F3 (txn) sin URL ni secreto: INSERT como authenticated no falla, dispatch(id) devuelve null y no hay nada
--    en la cola (si existe) ni stub.
-- F4 (txn, sin INSERT) 0031 dos veces sobre la tabla real deja 1 trigger con la definición exacta de prod.
-- F5 tras el rollback de F4 el trigger vuelve a ser el de F1.
-- F6 (txn) 0034 dos veces deja el estado de F1 y las dos funciones SECURITY DEFINER con search_path="".
-- F7 ni anon, ni authenticated, ni service_role tienen EXECUTE sobre las dos funciones.
-- F8 (txn, con stub de net.http_post) no hay llamada: sin URL con secreto; solo URL sin secreto (P6–P7);
--    URL + secreto '' (pausa del rollback); URL inválida (http:// u otra ruta) + secreto.
-- F9 (txn) URL de prueba + secreto, sin net.http_post: el INSERT no falla y dispatch devuelve null.
-- F10 (misma txn) con stub de net.http_post (firma de pg_net 0.20.4) o pg_net real: un INSERT como
--    authenticated hace 1 llamada con la URL de prueba, x-feedback-secret, body con solo record.id,
--    params {} y 30000 ms.
-- F11 (misma txn, URL presente, sin INSERT) con la URL de prueba en Vault (válida para la regex de 0034
--    pero distinta de la de prod), rollback_0034 quita trigger y funciones y NO crea el de 0031; con la URL
--    de prod en Vault (solo dentro de la txn), rollback_0034 restaura el trigger exacto de 0031.
-- F12 (txn nueva, sin URL) rollback_0034 quita trigger y funciones y NO crea el de 0031. Tras el rollback:
--    estado de F1, Vault sin entradas, sin schema `net` del stub y sin filas en la cola para la URL de
--    prueba ni la de prod.

\set ON_ERROR_STOP 1
do $$
begin
    if inet_server_addr() is not null and host(inet_server_addr()) not in ('127.0.0.1', '::1') then
        raise exception 'feedback_trigger_check: solo BD local (socket o loopback); servidor %', host(inet_server_addr());
    end if;
    if exists (select 1 from vault.secrets where name in ('feedback_webhook_url', 'feedback_webhook_secret')) then
        raise exception 'feedback_trigger_check: Vault local ya tiene feedback_webhook_url/secret (entorno contaminado); abortado';
    end if;
    if not exists (select 1 from auth.users) then
        raise exception 'feedback_trigger_check: no hay usuarios en auth.users (¿falta el seed de demo.sh up?)';
    end if;
end $$;

-- Estado de F1 (null = correcto; si no, la descripción del fallo).
create function pg_temp.fb_trigger_state() returns text language plpgsql as $$
declare
    v_n int;
    v_type int2;
    v_en "char";
    v_fn text;
begin
    select count(*), max(t.tgtype), max(t.tgenabled), max(t.tgfoid::regproc::text)
      into v_n, v_type, v_en, v_fn
      from pg_trigger t
     where t.tgname = 'homita_feedback_creation' and not t.tgisinternal;
    if v_n <> 1 or not exists (select 1 from pg_trigger t
                                where t.tgname = 'homita_feedback_creation'
                                  and t.tgrelid = 'public.feedback'::regclass) then
        return format('%s triggers homita_feedback_creation (esperado 1, en public.feedback)', v_n);
    end if;
    if v_en <> 'O' or (v_type & 1) <> 1 or (v_type & 2) <> 0 or (v_type & 4) <> 4 then
        return format('no es AFTER INSERT FOR EACH ROW habilitado (tgtype %s, tgenabled %s)', v_type, v_en);
    end if;
    if v_fn is distinct from 'homita_feedback_notify' and v_fn is distinct from 'public.homita_feedback_notify' then
        return format('el trigger ejecuta %s (esperado public.homita_feedback_notify)', v_fn);
    end if;
    return null;
end $$;

-- ¿El trigger es exactamente el de 0031? (null = sí).
create function pg_temp.fb_is_0031() returns text language plpgsql as $$
declare
    v_n int;
    v_def text;
begin
    select count(*), max(pg_get_triggerdef(t.oid)) into v_n, v_def
      from pg_trigger t
     where t.tgname = 'homita_feedback_creation' and t.tgrelid = 'public.feedback'::regclass and not t.tgisinternal;
    if v_n <> 1 or v_def is distinct from
        'CREATE TRIGGER homita_feedback_creation AFTER INSERT ON public.feedback FOR EACH ROW EXECUTE FUNCTION '
        || 'supabase_functions.http_request(''https://jlmjeykqbspoohmtrhwb.supabase.co/functions/v1/procesar-feedback'', '
        || '''POST'', ''{"Content-type":"application/json"}'', ''{}'', ''5000'')' then
        return format('%s triggers; definición: %s', v_n, v_def);
    end if;
    return null;
end $$;

-- Llamadas observables a net.http_post: el stub registra todas; con pg_net real se mira la cola.
create function pg_temp.fb_calls() returns int language plpgsql as $$
declare
    v_n int := 0;
begin
    if to_regclass('net.stub_calls') is not null then
        execute 'select count(*) from net.stub_calls' into v_n;
    elsif to_regclass('net.http_request_queue') is not null then
        execute 'select count(*) from net.http_request_queue
                  where url like ''%feedback-test.invalid%'' or url like ''%jlmjeykqbspoohmtrhwb%''' into v_n;
    end if;
    return v_n;
end $$;

-- Stub de net.http_post con la firma de pg_net 0.20.4 (T0) si pg_net no está instalado. Devuelve si lo creó.
create function pg_temp.fb_install_stub() returns boolean language plpgsql as $$
begin
    if to_regnamespace('net') is not null then
        return false;
    end if;
    execute 'create schema net';
    execute 'create table net.stub_calls (url text, body jsonb, params jsonb, headers jsonb, timeout_milliseconds int)';
    execute $f$
        create function net.http_post(url text, body jsonb default '{}', params jsonb default '{}',
                                      headers jsonb default '{"Content-Type": "application/json"}',
                                      timeout_milliseconds int default 5000)
        returns bigint language sql as
        'insert into net.stub_calls values (url, body, params, headers, timeout_milliseconds) returning 1::bigint'
    $f$;
    return true;
end $$;

-- Claims de un usuario existente (auth.uid() para la policy «insertar mi feedback»), local a la transacción.
create function pg_temp.fb_claims() returns void language plpgsql as $$
declare
    v_uid uuid;
begin
    select id into v_uid from auth.users order by created_at, id limit 1;
    if v_uid is null then
        raise exception 'feedback_trigger_check: no hay usuarios en auth.users';
    end if;
    perform set_config('request.jwt.claims',
                       json_build_object('sub', v_uid, 'role', 'authenticated')::text, true);
end $$;

-- Cambia (o crea) una entrada de Vault dentro de la transacción en curso.
create function pg_temp.fb_vault(p_name text, p_value text) returns void language plpgsql as $$
declare
    v_id uuid;
begin
    select id into v_id from vault.secrets where name = p_name;
    if v_id is null then
        perform vault.create_secret(p_value, p_name, 'feedback_trigger_check (rollback)');
    else
        perform vault.update_secret(v_id, p_value);
    end if;
end $$;

do $$
declare
    v_err text := pg_temp.fb_trigger_state();
begin
    if v_err is not null then
        raise exception 'feedback_trigger F1: %', v_err;
    end if;
    raise notice 'ok F1: 1 trigger AFTER INSERT en public.feedback -> homita_feedback_notify';
end $$;

do $$
begin
    if exists (select 1 from pg_trigger t
                where not t.tgisinternal
                  and (t.tgrelid = 'public.feedback'::regclass
                       and pg_get_triggerdef(t.oid) like '%supabase_functions.http_request%'
                       or pg_get_triggerdef(t.oid) like '%jlmjeykqbspoohmtrhwb%')) then
        raise exception 'feedback_trigger F2: hay un trigger con http_request o con la URL de prod';
    end if;
    if exists (select 1 from vault.secrets where name like 'feedback_webhook%') then
        raise exception 'feedback_trigger F2: Vault local tiene entradas feedback_webhook_*';
    end if;
    if not exists (select 1 from pg_proc where proname = 'homita_feedback_dispatch')
       or exists (select 1 from pg_proc where proname = 'homita_feedback_dispatch'
                                         and prosrc like '%jlmjeykqbspoohmtrhwb%') then
        raise exception 'feedback_trigger F2: dispatch ausente o con la URL de prod en el código';
    end if;
    raise notice 'ok F2: sin http_request ni URL de prod en triggers ni en dispatch; Vault sin feedback_webhook_*';
end $$;

-- F3: sin URL ni secreto.
begin;
select pg_temp.fb_claims();
set local role authenticated;
insert into public.feedback (seccion, tipo, texto) values ('check', 'bug', 'fbtrig F3');
reset role;

do $$
declare
    v_id bigint;
begin
    select max(id) into v_id from public.feedback where texto = 'fbtrig F3';
    if v_id is null then
        raise exception 'feedback_trigger F3: el INSERT como authenticated no quedó';
    end if;
    if public.homita_feedback_dispatch(v_id) is not null then
        raise exception 'feedback_trigger F3: dispatch sin URL ni secreto devolvió un id de petición';
    end if;
    if pg_temp.fb_calls() <> 0 then
        raise exception 'feedback_trigger F3: hay llamadas sin URL ni secreto';
    end if;
    raise notice 'ok F3: sin URL ni secreto el INSERT no falla, dispatch devuelve null y no hay llamadas';
end $$;
rollback;

-- F4: 0031 dos veces sobre la tabla real, SIN INSERT.
begin;

-- @MIGRATION:0031_feedback_trigger.sql@

-- @MIGRATION:0031_feedback_trigger.sql@

do $$
declare
    v_err text := pg_temp.fb_is_0031();
begin
    if v_err is not null then
        raise exception 'feedback_trigger F4: 0031 x2 no deja el trigger de prod: %', v_err;
    end if;
    raise notice 'ok F4: 0031 x2 deja 1 trigger con la definición exacta de prod (sin INSERT)';
end $$;
rollback;

do $$
declare
    v_err text := pg_temp.fb_trigger_state();
begin
    if v_err is not null then
        raise exception 'feedback_trigger F5: tras el rollback de F4: %', v_err;
    end if;
    raise notice 'ok F5: tras el rollback, el trigger vuelve a ser el de 0034 (sin residuos de 0031)';
end $$;

-- F6: 0034 dos veces.
begin;

-- @MIGRATION:0034_feedback_trigger_secret.sql@

-- @MIGRATION:0034_feedback_trigger_secret.sql@

do $$
declare
    v_err text := pg_temp.fb_trigger_state();
    v_bad int;
begin
    if v_err is not null then
        raise exception 'feedback_trigger F6: tras 0034 x2: %', v_err;
    end if;
    select count(*) into v_bad
      from (values ('public.homita_feedback_dispatch(bigint)'), ('public.homita_feedback_notify()')) f(sig)
      left join pg_proc p on p.oid = to_regprocedure(f.sig)
     where p.oid is null or not p.prosecdef or p.proconfig is distinct from array['search_path=""'];
    if v_bad <> 0 or (select count(*) from pg_proc
                       where proname in ('homita_feedback_dispatch', 'homita_feedback_notify')) <> 2 then
        raise exception 'feedback_trigger F6: funciones ausentes, duplicadas o sin SECURITY DEFINER / search_path=""';
    end if;
    raise notice 'ok F6: 0034 x2 deja el estado de F1; funciones DEFINER con search_path vacío';
end $$;
rollback;

do $$
declare
    v_bad text;
begin
    select string_agg(r || ' ' || f, ', ') into v_bad
      from unnest(array['anon', 'authenticated', 'service_role']) r,
           unnest(array['public.homita_feedback_dispatch(bigint)', 'public.homita_feedback_notify()']) f
     where has_function_privilege(r, f, 'execute');
    if v_bad is not null then
        raise exception 'feedback_trigger F7: EXECUTE concedido a %', v_bad;
    end if;
    raise notice 'ok F7: sin EXECUTE para anon, authenticated ni service_role';
end $$;

-- F8: casos de URL/secreto con el stub instalado (o pg_net real): ninguno llama.
begin;
select pg_temp.fb_install_stub() as stub_f8;
select pg_temp.fb_claims();

-- (1) sin URL, con secreto y net.http_post: el guard es la URL.
select pg_temp.fb_vault('feedback_webhook_secret', 'local-test-no-real');
set local role authenticated;
insert into public.feedback (seccion, tipo, texto) values ('check', 'bug', 'fbtrig F8.1');
reset role;
do $$ begin
    if pg_temp.fb_calls() <> 0 then raise exception 'feedback_trigger F8: llamada sin URL en Vault'; end if;
end $$;

-- (2) solo URL de prueba, secreto vacío (pausa del rollback).
select pg_temp.fb_vault('feedback_webhook_url', 'https://feedback-test.invalid/functions/v1/procesar-feedback');
select pg_temp.fb_vault('feedback_webhook_secret', '');
set local role authenticated;
insert into public.feedback (seccion, tipo, texto) values ('check', 'mejora', 'fbtrig F8.2');
reset role;
do $$ begin
    if pg_temp.fb_calls() <> 0 then raise exception 'feedback_trigger F8: llamada con secreto vacío'; end if;
end $$;

-- (3) solo URL, sin secreto (ventana P6–P7).
delete from vault.secrets where name = 'feedback_webhook_secret';
set local role authenticated;
insert into public.feedback (seccion, tipo, texto) values ('check', 'bug', 'fbtrig F8.3');
reset role;
do $$ begin
    if pg_temp.fb_calls() <> 0 then raise exception 'feedback_trigger F8: llamada sin secreto'; end if;
end $$;

-- (4) URL inválida (http://) y (5) otra ruta, con secreto.
select pg_temp.fb_vault('feedback_webhook_secret', 'local-test-no-real');
select pg_temp.fb_vault('feedback_webhook_url', 'http://feedback-test.invalid/functions/v1/procesar-feedback');
set local role authenticated;
insert into public.feedback (seccion, tipo, texto) values ('check', 'bug', 'fbtrig F8.4');
reset role;
select pg_temp.fb_vault('feedback_webhook_url', 'https://feedback-test.invalid/functions/v1/otra');
set local role authenticated;
insert into public.feedback (seccion, tipo, texto) values ('check', 'bug', 'fbtrig F8.5');
reset role;

do $$
begin
    if pg_temp.fb_calls() <> 0 then
        raise exception 'feedback_trigger F8: llamada con URL inválida';
    end if;
    if (select count(*) from public.feedback where texto like 'fbtrig F8.%') <> 5 then
        raise exception 'feedback_trigger F8: algún INSERT como authenticated no quedó';
    end if;
    raise notice 'ok F8: sin llamada sin URL, con secreto vacío, sin secreto ni con URL inválida';
end $$;
rollback;

-- F9–F11: URL de prueba + secreto de prueba, solo en esta transacción.
begin;
select pg_temp.fb_claims();
select pg_temp.fb_vault('feedback_webhook_url', 'https://feedback-test.invalid/functions/v1/procesar-feedback');
select pg_temp.fb_vault('feedback_webhook_secret', 'local-test-no-real');

-- F9: sin net.http_post (pg_net no instalado en local).
set local role authenticated;
insert into public.feedback (seccion, tipo, texto) values ('check', 'bug', 'fbtrig F9');
reset role;

do $$
declare
    v_id bigint;
begin
    select max(id) into v_id from public.feedback where texto = 'fbtrig F9';
    if v_id is null then
        raise exception 'feedback_trigger F9: el INSERT como authenticated no quedó';
    end if;
    if to_regprocedure('net.http_post(text, jsonb, jsonb, jsonb, integer)') is null then
        if public.homita_feedback_dispatch(v_id) is not null then
            raise exception 'feedback_trigger F9: dispatch sin net.http_post devolvió un id';
        end if;
        raise notice 'ok F9: con URL y secreto pero sin net.http_post, el INSERT no falla y dispatch devuelve null';
    else
        raise notice 'ok F9: pg_net instalado (no aplica la ausencia de net.http_post); el INSERT no falla';
    end if;
end $$;

-- F10: con stub (o pg_net real).
select pg_temp.fb_install_stub() as stub_f10;
set local role authenticated;
insert into public.feedback (seccion, tipo, texto) values ('check', 'mejora', 'fbtrig F10');
reset role;

do $$
declare
    v_id bigint := (select max(id) from public.feedback where texto = 'fbtrig F10');
    v_n int;
    v_r record;
    v_url constant text := 'https://feedback-test.invalid/functions/v1/procesar-feedback';
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
        raise notice 'ok F10: 1 net.http_post (stub: pg_net no instalado en local) con URL de prueba, x-feedback-secret, record.id, {} y 30000';
    else
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
        raise notice 'ok F10: 1 fila en net.http_request_queue (pg_net real) con URL de prueba, POST, x-feedback-secret, record.id y 30000';
    end if;
end $$;

-- F11: rollback_0034 con URL en Vault. Sin INSERT a partir de aquí (con el trigger de 0031 presente no se
-- inserta nunca). Primero con la URL de prueba (no es la de prod): no restaura 0031.
-- @ROLLBACK:rollback_0034.sql@

do $$
begin
    if exists (select 1 from pg_trigger where tgname = 'homita_feedback_creation')
       or exists (select 1 from pg_proc where proname in ('homita_feedback_dispatch', 'homita_feedback_notify')) then
        raise exception 'feedback_trigger F11: con una URL distinta de la de prod, rollback_0034 dejó trigger o funciones';
    end if;
end $$;

-- Después con la URL de prod (simula prod; solo dentro de esta transacción, sin INSERT): restaura 0031.
select pg_temp.fb_vault('feedback_webhook_url', 'https://jlmjeykqbspoohmtrhwb.supabase.co/functions/v1/procesar-feedback');
-- @ROLLBACK:rollback_0034.sql@

do $$
declare
    v_err text := pg_temp.fb_is_0031();
begin
    if v_err is not null then
        raise exception 'feedback_trigger F11: rollback_0034 no restauró el trigger exacto de 0031: %', v_err;
    end if;
    if exists (select 1 from pg_proc where proname in ('homita_feedback_dispatch', 'homita_feedback_notify')) then
        raise exception 'feedback_trigger F11: rollback_0034 no quitó las funciones';
    end if;
    raise notice 'ok F11: con URL de prueba en Vault rollback_0034 no restaura 0031; con la URL de prod restaura el trigger exacto de 0031 y quita las funciones';
end $$;
rollback;

-- F12: rollback_0034 sin URL en Vault (local/CI): no crea el trigger de 0031.
begin;

-- @ROLLBACK:rollback_0034.sql@

do $$
begin
    if exists (select 1 from pg_trigger where tgname = 'homita_feedback_creation')
       or exists (select 1 from pg_proc where proname in ('homita_feedback_dispatch', 'homita_feedback_notify')) then
        raise exception 'feedback_trigger F12: sin URL, rollback_0034 dejó trigger o funciones';
    end if;
end $$;
rollback;

do $$
declare
    v_err text := pg_temp.fb_trigger_state();
    v_n int;
begin
    if v_err is not null then
        raise exception 'feedback_trigger F12: al final el estado no es el de F1: %', v_err;
    end if;
    if exists (select 1 from vault.secrets where name like 'feedback_webhook%') then
        raise exception 'feedback_trigger F12: quedan entradas feedback_webhook_* en Vault';
    end if;
    if to_regclass('net.stub_calls') is not null
       or (to_regnamespace('net') is not null and to_regclass('net.http_request_queue') is null) then
        raise exception 'feedback_trigger F12: queda el schema net del stub';
    end if;
    if to_regclass('net.http_request_queue') is not null then
        execute 'select count(*) from net.http_request_queue
                  where url like ''%feedback-test.invalid%'' or url like ''%jlmjeykqbspoohmtrhwb%''' into v_n;
        if v_n <> 0 then
            raise exception 'feedback_trigger F12: quedan peticiones de prueba o a prod en la cola de pg_net';
        end if;
    end if;
    if exists (select 1 from public.feedback where texto like 'fbtrig F%') then
        raise exception 'feedback_trigger F12: quedan filas de prueba en public.feedback';
    end if;
    raise notice 'ok F12: sin URL, rollback_0034 no crea el trigger de 0031; al final, estado de F1, Vault, net y cola limpios';
end $$;
