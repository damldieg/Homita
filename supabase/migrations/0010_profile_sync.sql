-- 0010_profile_sync.sql — Sincronía GoTrue → app_user en updates de perfil (control-api, R1-04).
--
-- user/update (Edge) es PUT /auth/v1/user con el JWT del usuario ({email?, password?, data:{name}}):
-- GoTrue es la fuente de verdad y este trigger sincroniza app_user.name/email/updated_at.
-- Sin DML directo sobre app_user desde el cliente (0002 no concede escritura).
-- Cambio de email: efectivo cuando GoTrue lo confirma (Q9); el trigger corre entonces.
--
-- Columnas filtradas (update of email, raw_user_meta_data): no se dispara en cada sign-in ni en
-- cambios de password (solo encrypted_password); `when (new.email is not null)` como 0004 (R1-14).
-- Grants: función no ejecutable por cliente (la ejecuta el sistema del trigger).

create or replace function fn_auth_user_updated() returns trigger
language plpgsql security definer set search_path = public as $$
begin
    update app_user
    set name = coalesce(new.raw_user_meta_data->>'name', name),
        email = new.email,
        updated_at = (now() at time zone 'UTC')
    where auth_uid = new.id;
    return new;
end $$;

create trigger on_auth_user_updated
after update of email, raw_user_meta_data on auth.users
for each row
when (new.email is not null)
execute function fn_auth_user_updated();

revoke execute on function fn_auth_user_updated() from public, anon, authenticated;
