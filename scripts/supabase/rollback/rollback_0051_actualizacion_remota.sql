-- rollback_0051_actualizacion_remota.sql — revierte 0051_actualizacion_remota.sql (change dashboard-actualizacion-remota).
-- Quita las funciones y las columnas nuevas de home_display. El bucket `display-releases` NO se borra aquí: puede tener
-- APKs publicados y borrar un bucket con objetos falla. Idempotente. La fila '0051' de schema_migrations no se borra aquí.

begin;

drop function if exists fn_display_set_channel(bigint, bigint, text);
drop function if exists fn_display_report(integer, text, text, boolean);

alter table home_display
    drop column if exists update_channel,
    drop column if exists app_version_code,
    drop column if exists app_version_name,
    drop column if exists last_update_check_at,
    drop column if exists last_update_result;

commit;
