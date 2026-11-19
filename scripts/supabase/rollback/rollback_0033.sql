-- rollback_0033.sql — Revierte 0033_feedback_trigger_secret.sql (change feedback-trello-gate): elimina el
-- trigger y las funciones homita_feedback_notify / homita_feedback_dispatch y restaura el trigger EXACTO de
-- 0031 (supabase_functions.http_request, sin secreto). En local/CI no existe la tabla: no hace nada.
--
-- AVISO: 0031 no envía x-feedback-secret. Orden según supabase/README.md «Rollback»: con la pausa de Vault
-- hecha, tras redesplegar la antigua; sin pausa, ANTES del redeploy, con la función nueva desplegada (401
-- antes del claim, sin efectos). Nunca redeploy de la antigua con 0033 aplicado y el secreto cargado.
-- El secreto de Vault `feedback_webhook_secret` no se borra aquí.
-- supabase_migrations.schema_migrations: la fila '0033' no se borra aquí.

do $$
begin
    if to_regclass('public.feedback') is null then
        raise notice 'rollback_0033: public.feedback no existe; nada que revertir';
        return;
    end if;
    execute 'drop trigger if exists homita_feedback_creation on public.feedback';
    execute 'drop function if exists public.homita_feedback_notify()';
    execute 'drop function if exists public.homita_feedback_dispatch(bigint)';
    execute $t$
        create trigger homita_feedback_creation
            after insert on public.feedback
            for each row execute function supabase_functions.http_request(
                'https://jlmjeykqbspoohmtrhwb.supabase.co/functions/v1/procesar-feedback',
                'POST',
                '{"Content-type":"application/json"}',
                '{}',
                '5000')
    $t$;
end $$;
