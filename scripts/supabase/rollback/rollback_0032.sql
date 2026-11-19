-- rollback_0032.sql — Revierte 0032_feedback_trello.sql (change feedback-trello-gate): elimina la RPC
-- homita_feedback_finalize, el índice backlog_trello_card_id_key y las columnas trello_card_id,
-- trello_card_url (backlog) y procesando_desde (feedback). En local/CI las tablas no existen: no hace nada.
--
-- AVISO: se pierden los vínculos backlog ↔ tarjeta de Trello (no se recuperan). Usar solo DESPUÉS de
-- redesplegar la función antigua de procesar-feedback (y, si se revierte, de rollback_0033): la función
-- nueva depende de la RPC y de procesando_desde.
-- supabase_migrations.schema_migrations: la fila '0032' no se borra aquí.

do $$
begin
    if to_regclass('public.feedback') is null or to_regclass('public.backlog') is null then
        raise notice 'rollback_0032: public.feedback o public.backlog no existe; nada que revertir';
        return;
    end if;
    execute 'drop function if exists public.homita_feedback_finalize(bigint, boolean, text, text, text, text)';
    execute 'drop index if exists public.backlog_trello_card_id_key';
    execute 'alter table public.backlog drop column if exists trello_card_id, drop column if exists trello_card_url';
    execute 'alter table public.feedback drop column if exists procesando_desde';
end $$;
