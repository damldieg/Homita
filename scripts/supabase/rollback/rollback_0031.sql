-- rollback_0031.sql — Revierte 0031_feedback_trigger.sql (change feedback-trigger-migration):
-- elimina el trigger homita_feedback_creation de public.feedback si la tabla existe. Desde
-- 0032_feedback_schema la tabla existe también en local/CI, así que el drop se ejecuta en todos los entornos.
--
-- AVISO (tras 0034_feedback_trigger_secret): 0034 reemplaza el trigger de 0031 con el MISMO nombre
-- (homita_feedback_creation -> homita_feedback_notify). Con 0034 aplicado (local, CI y prod tras P6) este
-- script NO revierte 0031: borra el trigger de 0034, deja huérfanas homita_feedback_notify/_dispatch y el
-- feedback nuevo deja de despacharse sin ningún warning (las filas quedan `pendiente`). En local, además,
-- F1 de feedback_trigger_check.sql falla hasta un `db reset`.
-- No usar este script después de 0034: la reversa del trigger vigente es rollback_0034.sql, en el orden de
-- supabase/README.md «Rollback». Este fichero solo vale para un entorno con 0031 y sin 0034.
-- supabase_migrations.schema_migrations: la fila '0031' no se borra aquí.

do $$
begin
    if to_regclass('public.feedback') is null then
        raise notice 'rollback_0031: public.feedback no existe; nada que revertir';
        return;
    end if;
    execute 'drop trigger if exists homita_feedback_creation on public.feedback';
end $$;
