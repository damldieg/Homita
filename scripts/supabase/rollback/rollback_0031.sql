-- rollback_0031.sql — Revierte 0031_feedback_trigger.sql (change feedback-trigger-migration):
-- elimina el trigger homita_feedback_creation de public.feedback si la tabla existe
-- (en local/CI no existe y no hace nada). Ojo: en prod deja de procesarse el feedback nuevo.
-- supabase_migrations.schema_migrations: la fila '0031' no se borra aquí.

do $$
begin
    if to_regclass('public.feedback') is null then
        raise notice 'rollback_0031: public.feedback no existe; nada que revertir';
        return;
    end if;
    execute 'drop trigger if exists homita_feedback_creation on public.feedback';
end $$;
