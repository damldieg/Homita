-- rollback_0036.sql — Revierte 0036_assistant_usage.sql (change kito-asistente).
-- Orden en prod: primero se retira la Edge Function `asistente` (deja de llamar a las RPC) y después la BD.
-- Datos: se pierden los contadores diarios y los tokens medidos; nada más depende de ellos.
-- supabase_migrations.schema_migrations: la fila '0036' no se borra aquí.

begin;

drop function if exists assistant_record_usage(bigint, date, bigint, bigint, bigint, bigint, boolean);
drop function if exists assistant_consume(bigint, text);
drop function if exists fn_assistant_daily_limit();
drop table if exists assistant_usage;

commit;

notify pgrst, 'reload schema';
