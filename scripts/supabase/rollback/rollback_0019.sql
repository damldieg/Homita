-- rollback_0019.sql — Rollback de 0019_home_permisos_kind.sql (fase 1.7, T6; plan §7).
-- Revierte 0019 sin tocar datos: borra el único objeto nuevo, fn_seed_kind_permissions (y sus
-- grants: al borrar la función desaparecen). 0019 no modifica funciones ni datos de 0001–0018
-- (A-7), así que no hay cuerpos que restaurar ni triggers/constraints que quitar.
-- El snapshot de membership_permission ya escrito por el helper (si lo hay) se conserva: revertir
-- el helper no deshace seeds aplicados (igual que rollback_0018 con promote/demote). Alternativa
-- de datos: el volcado de G4 (plan §7).
-- Precondición: sin llamadas a fn_seed_kind_permissions desde el volcado de G4 (o asumir sus
-- efectos). Re-aplicar 0019 tras el rollback es idempotente (create or replace + aserciones).
-- Uso: psql -v ON_ERROR_STOP=1 -1 -f rollback_0019.sql

begin;

drop function if exists fn_seed_kind_permissions(bigint, member_kind);

commit;
