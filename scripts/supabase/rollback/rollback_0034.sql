-- rollback_0034.sql — Revierte 0034_feedback_trigger_secret.sql (change feedback-trello-gate, D-023): elimina
-- el trigger y las funciones homita_feedback_notify / homita_feedback_dispatch y, SOLO si la entrada
-- `feedback_webhook_url` de Vault (marca de prod, P5) es EXACTAMENTE
-- https://jlmjeykqbspoohmtrhwb.supabase.co/functions/v1/procesar-feedback (la URL que P5 carga, P6 verifica
-- y este script restaura), restaura el trigger EXACTO de 0031 (supabase_functions.http_request, sin secreto).
-- Si la entrada falta o tiene otro valor (local/CI, o un Vault local con una URL de prueba o de túnel que
-- cumple la regex de 0034) avisa y no crea ningún trigger: un rollback fuera de prod no deja un trigger que
-- apunte a prod salvo que alguien haya cargado a propósito la URL de prod en su Vault local.
--
-- AVISO: 0031 no envía x-feedback-secret. Orden según supabase/README.md «Rollback»: con la pausa de Vault
-- hecha, tras redesplegar la antigua; sin pausa, ANTES del redeploy, con la función nueva desplegada (401
-- antes del claim, sin efectos). Nunca redeploy de la antigua con 0034 aplicado y el secreto cargado.
-- NO borrar ni modificar `feedback_webhook_url` de Vault: sin ella (o con otro valor) este rollback no
-- restaura 0031 y el feedback nuevo queda sin despacho (se ve en la revisión manual). El secreto
-- `feedback_webhook_secret` tampoco se borra aquí.
-- supabase_migrations.schema_migrations: la fila '0034' no se borra aquí.

do $$
declare
    v_prod_url constant text := 'https://jlmjeykqbspoohmtrhwb.supabase.co/functions/v1/procesar-feedback';
begin
    if to_regclass('public.feedback') is null then
        raise notice 'rollback_0034: public.feedback no existe; nada que revertir';
        return;
    end if;
    execute 'drop trigger if exists homita_feedback_creation on public.feedback';
    execute 'drop function if exists public.homita_feedback_notify()';
    execute 'drop function if exists public.homita_feedback_dispatch(bigint)';
    if not exists (select 1 from vault.decrypted_secrets where name = 'feedback_webhook_url') then
        raise notice 'rollback_0034: sin feedback_webhook_url en Vault (local/CI); no se restaura el trigger de 0031';
        return;
    end if;
    if not exists (select 1 from vault.decrypted_secrets
                    where name = 'feedback_webhook_url' and decrypted_secret = v_prod_url) then
        raise notice 'rollback_0034: feedback_webhook_url de Vault no es la URL de prod; no se restaura el trigger de 0031';
        return;
    end if;
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
