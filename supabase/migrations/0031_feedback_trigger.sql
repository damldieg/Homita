-- 0031_feedback_trigger.sql — change feedback-trigger-migration: versiona el trigger que hoy solo
-- existe en producción y que dispara la Edge Function `procesar-feedback` al insertar feedback.
--
-- Contexto: `public.feedback` (y `backlog`) NO tienen DDL en este repo; solo existen en prod.
-- El trigger `homita_feedback_creation` llama por HTTP (supabase_functions.http_request) a la
-- función de prod, así que en local/CI no debe existir: dispararía un webhook a producción.
--
-- Semántica:
--   * Guard: si `public.feedback` no existe (local/CI) la migración avisa y sale sin crear nada.
--   * Si existe (prod): drop + create del trigger con la definición actual de prod
--     (AFTER INSERT, FOR EACH ROW, POST, cabecera JSON, timeout 5000 ms). Resultado efectivo en
--     prod: sin cambio. Idempotente (se puede re-ejecutar).
--   * El DDL va en `execute` dinámico: sobre una tabla inexistente no se podría ni parsear.
-- Reversa (no automática): scripts/supabase/rollback/rollback_0031.sql.

do $$
begin
    if to_regclass('public.feedback') is null then
        raise notice '0031: public.feedback no existe (local/CI); sin trigger';
        return;
    end if;

    execute 'drop trigger if exists homita_feedback_creation on public.feedback';
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
