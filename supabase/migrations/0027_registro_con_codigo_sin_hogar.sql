-- 0027: el registro con código de invitación no crea hogar personal.
-- Motivo (review R1-01/R1-02): fn_auth_user_created (0014) creaba un hogar personal con membresía
-- admin en cada alta, también cuando el registro traía invitation_code; así la persona nunca veía
-- "sin hogar" y el código pendiente se perdía. La Edge valida el código y pasa solo un marcador
-- booleano (raw_user_meta_data->>'invitation_pending' = 'true'; el código en claro NO viaja a GoTrue,
-- R2-03) y aquí se omite el hogar personal si el marcador viene.
-- R2-01: en el alta sin marcador el hogar personal también nace con su home_member vinculado
-- (adult, activo) y su person 1:1, igual que create_home (0023). Sin duplicar si ya existen.
-- Aditiva: create or replace de la función; sin cambios de esquema ni de datos.
-- Rollback: scripts/supabase/rollback/rollback_0027.sql.

create or replace function fn_auth_user_created() returns trigger
language plpgsql security definer set search_path = public as $$
declare
    v_user_id bigint;
    v_name text := coalesce(new.raw_user_meta_data->>'name', split_part(coalesce(new.email, ''), '@', 1));
    v_home bigint;
    v_hm bigint;
    v_color text;
    v_pname text;
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
    if coalesce(new.raw_user_meta_data->>'invitation_pending', '') = 'true' then
        return new;  -- registro con código: sin hogar personal; acepta la invitación después
    end if;
    insert into home (name, is_personal, created_by) values ('Hogar de ' || v_name, true, v_user_id)
    returning id into v_home;
    insert into home_membership (home_id, app_user_id, role) values (v_home, v_user_id, 'admin');
    update app_user set default_home_id = v_home where id = v_user_id;
    -- Primer miembro: el propio admin (como create_home, 0023); person 1:1 vinculada.
    -- Sin fn_validate_person_fields: lanzaría con nombre vacío o >50 y abortaría el alta en auth.users.
    v_pname := left(coalesce(nullif(btrim(v_name), ''), 'Admin'), 50);
    v_color := '#6923E2';
    select id into v_hm from home_member where home_id = v_home and app_user_id = v_user_id;
    if v_hm is null then
        insert into home_member (home_id, kind, name, color, status, app_user_id, created_by)
        values (v_home, 'adult', v_pname, v_color, 'active', v_user_id, v_user_id)
        returning id into v_hm;
    end if;
    if not exists (select 1 from person where home_member_id = v_hm) then
        insert into person (user_id, home_id, home_member_id, name, color)
        values (v_user_id, v_home, v_hm, v_pname, v_color);
    end if;
    return new;
end $$;
revoke execute on function fn_auth_user_created() from public, anon, authenticated;
