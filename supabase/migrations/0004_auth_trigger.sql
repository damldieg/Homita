-- 0004_auth_trigger.sql — Altas futuras: cada fila nueva en auth.users crea su app_user.
-- Se aplica DESPUÉS de importar datos (tasks 8/9): la importación inserta app_user con los ids
-- legados y el trigger solo debe cubrir altas posteriores (R1-04).
--
-- ON CONFLICT (auth_uid) DO NOTHING: salvaguarda si el trigger corre cuando ya existe la fila
-- (p. ej. 0004 aplicado antes de importar). La importación, además, elimina la fila que el
-- trigger hubiera creado para ese auth_uid antes de insertar la suya (doble defensa).

create or replace function fn_auth_user_created() returns trigger
language plpgsql security definer set search_path = public as $$
begin
    insert into app_user (auth_uid, name, email, created_at, updated_at)
    values (
        new.id,
        coalesce(new.raw_user_meta_data->>'name', split_part(coalesce(new.email, ''), '@', 1)),
        new.email,
        (now() at time zone 'UTC'),
        (now() at time zone 'UTC')
    )
    on conflict (auth_uid) do nothing;
    return new;
end $$;

-- R1-14: `when (new.email is not null)`: identidades sin email (phone/anonymous) no deben abortar
-- el alta; con email NULL el trigger se salta (app_user.email es NOT NULL y PHP siempre lo tuvo).
create trigger on_auth_user_created
after insert on auth.users
for each row
when (new.email is not null)
execute function fn_auth_user_created();
