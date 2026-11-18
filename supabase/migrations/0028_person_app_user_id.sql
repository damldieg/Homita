-- 0028: get_persons expone la cuenta vinculada de cada persona (`app_user_id`).
-- Motivo: la app de control iOS enseña la Live Activity de rutinas solo a la persona asignada a la
-- rutina con su cuenta iniciada. `person.user_id` es el CREADOR de la persona, no la cuenta vinculada;
-- la cuenta vive en home_member.app_user_id (null en mascotas y miembros sin cuenta).
-- Aditiva: create or replace de get_persons (cuerpo de 0020 + una clave nueva en el JSON). Los
-- clientes existentes ignoran claves desconocidas; grants y firma no cambian.
-- Rollback: scripts/supabase/rollback/rollback_0028.sql.

begin;

create or replace function get_persons(p_include_inactive boolean default false) returns json
language plpgsql stable security definer set search_path = public as $$
begin
    if fn_my_user_id() is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    return (
        select coalesce(json_agg(json_build_object(
            'id', p.id, 'user_id', p.user_id, 'name', p.name, 'color', p.color,
            'created_at', to_char(p.created_at, 'YYYY-MM-DD HH24:MI:SS'),
            'updated_at', to_char(p.updated_at, 'YYYY-MM-DD HH24:MI:SS'),
            'editable', p.user_id = fn_my_user_id(),
            'home_member_id', p.home_member_id,
            'kind', hm.kind::text,
            'app_user_id', hm.app_user_id
        ) order by translate(p.name, 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', 'abcdefghijklmnopqrstuvwxyz'), p.id), '[]'::json)
        from person p
        inner join home_member hm on hm.id = p.home_member_id
        -- 1.8 (§3.3, D4/Q-G): personas por HOGAR del llamante (no por familia)
        where p.home_id = any (fn_my_home_ids())
          and (p_include_inactive or hm.status = 'active')
    );
end $$;

commit;
