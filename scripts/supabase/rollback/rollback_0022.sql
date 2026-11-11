-- rollback_0022.sql — Revierte 0022_home_invitations.sql (fase 1.15).
-- 0022 no redefine ninguna función previa: basta con borrar lo creado. Índices, constraints,
-- secuencia y RLS de home_invitation caen con la tabla (se pierde el historial de invitaciones).
--
-- NO toca (R1-03 review 1.15):
-- * supabase_migrations.schema_migrations: la fila '0022' NO se borra aquí. Si queda, el siguiente
--   despliegue daría 0022 por aplicada sin sus objetos. El check final de este fichero FALLA (exit
--   ≠ 0) mientras esa fila exista, para que el operador decida (con confirmación propia) borrar el
--   registro o re-aplicar 0022. Los drops ya están confirmados cuando el check falla.
-- * Datos generados por aceptaciones ya hechas: home_membership creadas, home_member.app_user_id
--   vinculados, home_member/person creados, membership_permission (snapshots) y filas audit_log
--   home.invitation.*. Siguen en la BD tras el rollback; solo el volcado de G4 devuelve el estado
--   exacto previo (perdiendo lo escrito después).
-- * pgcrypto, add_*_user ni ninguna otra función.
-- Verificación: fnhash global de public y huella de esquema = baseline 0021 (rollback-verify.txt).

begin;
drop function if exists get_home_invitations(bigint);
drop function if exists create_home_invitation(bigint, text, bigint);
drop function if exists accept_home_invitation(text);
drop function if exists revoke_home_invitation(bigint, bigint);
drop function if exists fn_home_invitation_json(bigint);
drop table if exists home_invitation;
commit;

-- Check post-rollback (R1-03): falla si la migración 0022 sigue registrada.
do $$
begin
    if to_regclass('supabase_migrations.schema_migrations') is not null
       and exists (select 1 from supabase_migrations.schema_migrations where version = '0022') then
        raise exception 'rollback_0022: objetos borrados, pero schema_migrations aún registra 0022 (borrar el registro en un paso confirmado aparte o re-aplicar 0022)';
    end if;
end $$;
