-- rollback_0028.sql — Revierte 0028_person_app_user_id.sql.
-- Restaura get_persons tal como la define 0020_home_write_guards (copia literal, sin `app_user_id`).
-- supabase_migrations.schema_migrations: la fila '0028' no se borra aquí.

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
            'kind', hm.kind::text
        ) order by translate(p.name, 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', 'abcdefghijklmnopqrstuvwxyz'), p.id), '[]'::json)
        from person p
        inner join home_member hm on hm.id = p.home_member_id
        -- 1.8 (§3.3, D4/Q-G): personas por HOGAR del llamante (no por familia)
        where p.home_id = any (fn_my_home_ids())
          and (p_include_inactive or hm.status = 'active')
    );
end $$;

commit;
