-- 0033_feedback_trigger_secret.sql — change feedback-trello-gate (D-021): el trigger de feedback envía el
-- secreto compartido (cabecera x-feedback-secret) que exige procesar-feedback. Reemplaza el trigger de 0031.
--
-- El secreto NO está en el repo: se lee en cada INSERT de Vault (`feedback_webhook_secret`), que el
-- usuario carga a mano en prod (`select vault.create_secret('<valor>', 'feedback_webhook_secret')`) con el
-- mismo valor que FEEDBACK_WEBHOOK_SECRET de la función.
--
-- Semántica:
--   * Guard: si `public.feedback` no existe (local/CI) avisa y sale: ni funciones ni trigger.
--   * public.homita_feedback_dispatch(p_id) SECURITY DEFINER: lee el secreto de vault.decrypted_secrets;
--     sin secreto -> warning y null (no hay petición, el feedback queda pendiente). Si no, encola
--     net.http_post a la función con body {type, table, schema, record: {id}} (solo el id) y timeout 30000.
--   * public.homita_feedback_notify() SECURITY DEFINER (obligatorio: quien inserta no tiene EXECUTE sobre
--     dispatch): llama a dispatch y convierte cualquier error en warning. El INSERT nunca falla.
--   * EXECUTE revocado a public, anon, authenticated y service_role en las dos funciones (solo el owner;
--     un trigger no comprueba EXECUTE al dispararse).
--   * Trigger homita_feedback_creation (mismo nombre que 0031): drop + create AFTER INSERT FOR EACH ROW.
--   * Idempotente. DDL en `execute` dinámico (sobre una tabla inexistente no se podría ni parsear).
--
-- Supuestos (T0, 2026-11-19, catálogo del stack local supabase/postgres:17.11.0.018; doc oficial sin
-- consultar en vivo):
--   - net.http_post(url text, body jsonb, params jsonb, headers jsonb, timeout_milliseconds integer)
--     returns bigint (pg_net 0.20.4): encola en net.http_request_queue (tabla UNLOGGED); en una transacción
--     con rollback la fila desaparece. Que el worker solo envía filas confirmadas y no reintenta sale de la
--     doc de pg_net, no verificado en vivo. En local pg_net está disponible pero NO instalado.
--   - vault.decrypted_secrets existe y `postgres` tiene SELECT; vault.create_secret(text, text, text, uuid).
--   - Con pg_net recién creado, anon/authenticated tienen USAGE en `net` y la cola concede a PUBLIC: el
--     secreto queda legible en la cola mientras no se envía para quien pueda ejecutar SQL (net no está
--     expuesto en la API REST). Se revisa en el pre-check de prod (P2).
-- Reproceso manual (SQL editor, sin exponer el secreto), de a uno, esperando a que la fila quede
-- procesado/error antes de la siguiente; nunca sin `limit 1` (ver supabase/README.md «Runbook»):
--   select id, public.homita_feedback_dispatch(id) from public.feedback
--    where estado = 'pendiente' and procesando_desde is null
--    order by id limit 1;
-- Reversa (no automática): scripts/supabase/rollback/rollback_0033.sql. Orden según supabase/README.md
-- «Rollback»: con la pausa de Vault hecha, tras redesplegar la antigua; sin pausa, ANTES del redeploy, con
-- la función nueva desplegada (401 antes del claim, sin efectos). Nunca redeploy de la antigua con 0033
-- aplicado y el secreto cargado.

do $$
begin
    if to_regclass('public.feedback') is null then
        raise notice '0033: public.feedback no existe (local/CI); sin funciones ni trigger';
        return;
    end if;

    execute $f$
        create or replace function public.homita_feedback_dispatch(p_id bigint)
        returns bigint
        language plpgsql
        security definer
        set search_path = ''
        as $body$
        declare
            v_secret text;
        begin
            select ds.decrypted_secret
              into v_secret
              from vault.decrypted_secrets ds
             where ds.name = 'feedback_webhook_secret';
            if v_secret is null or v_secret = '' then
                raise warning 'homita_feedback_dispatch: falta el secreto feedback_webhook_secret en Vault; feedback % queda pendiente', p_id;
                return null;
            end if;
            return net.http_post(
                url := 'https://jlmjeykqbspoohmtrhwb.supabase.co/functions/v1/procesar-feedback',
                body := jsonb_build_object(
                    'type', 'INSERT',
                    'table', 'feedback',
                    'schema', 'public',
                    'record', jsonb_build_object('id', p_id)),
                params := '{}'::jsonb,
                headers := jsonb_build_object(
                    'Content-Type', 'application/json',
                    'x-feedback-secret', v_secret),
                timeout_milliseconds := 30000);
        end
        $body$
    $f$;

    execute $f$
        create or replace function public.homita_feedback_notify()
        returns trigger
        language plpgsql
        security definer
        set search_path = ''
        as $body$
        begin
            begin
                perform public.homita_feedback_dispatch(new.id);
            exception when others then
                raise warning 'homita_feedback_notify: no se pudo encolar feedback %: %', new.id, sqlerrm;
            end;
            return new;
        end
        $body$
    $f$;

    execute 'revoke all on function public.homita_feedback_dispatch(bigint)
                 from public, anon, authenticated, service_role';
    execute 'revoke all on function public.homita_feedback_notify()
                 from public, anon, authenticated, service_role';

    execute 'drop trigger if exists homita_feedback_creation on public.feedback';
    execute 'create trigger homita_feedback_creation
                 after insert on public.feedback
                 for each row execute function public.homita_feedback_notify()';
end $$;
