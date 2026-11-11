-- rollback_0027.sql — Revierte 0027_registro_con_codigo_sin_hogar.sql (change hogar-admin-miembro).
-- Restaura fn_auth_user_created tal como la define 0014_home_compat.sql (copia literal): sin la rama
-- de invitación pendiente y sin home_member/person en el hogar personal.
-- NO borra los home_member/person creados por el trigger mientras 0027 estuvo aplicada.
-- supabase_migrations.schema_migrations: la fila '0027' no se borra aquí; el check final FALLA
-- mientras exista, para que el operador decida (borrar el registro o re-aplicar 0027).

begin;

create or replace function fn_auth_user_created() returns trigger
language plpgsql security definer set search_path = public as $$
declare
    v_user_id bigint;
    v_name text := coalesce(new.raw_user_meta_data->>'name', split_part(coalesce(new.email, ''), '@', 1));
    v_home bigint;
begin
    insert into app_user (auth_uid, name, email, created_at, updated_at)
    values (new.id, v_name, new.email, (now() at time zone 'UTC'), (now() at time zone 'UTC'))
    on conflict (auth_uid) do nothing
    returning id into v_user_id;
    if v_user_id is null then
        select id into v_user_id from app_user where auth_uid = new.id;
    end if;
    if exists (select 1 from home_membership where app_user_id = v_user_id) then
        return new;  -- ya tiene hogar (usuario previo o re-ejecución): no duplicar
    end if;
    insert into home (name, is_personal, created_by) values ('Hogar de ' || v_name, true, v_user_id)
    returning id into v_home;
    insert into home_membership (home_id, app_user_id, role) values (v_home, v_user_id, 'admin');
    update app_user set default_home_id = v_home where id = v_user_id;
    return new;
end $$;
revoke execute on function fn_auth_user_created() from public, anon, authenticated;

commit;

-- Check post-rollback: falla si la migración 0027 sigue registrada.
do $$
begin
    if to_regclass('supabase_migrations.schema_migrations') is not null
       and exists (select 1 from supabase_migrations.schema_migrations where version = '0027') then
        raise exception 'rollback_0027: función revertida, pero schema_migrations aún registra 0027 (borrar el registro en un paso confirmado aparte o re-aplicar 0027)';
    end if;
end $$;
