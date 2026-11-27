-- rollback_0053_pantallas_canal_version.sql — revierte 0053: vuelve a la fn_display_list de 0049 (sin canal ni versión).
-- Idempotente. La fila '0053' de schema_migrations no se borra aquí.

begin;

create or replace function fn_display_list(p_home_id bigint) returns json
language plpgsql stable security definer set search_path = public as $$
begin
    perform fn_require_member(p_home_id);
    return coalesce((
        select json_agg(json_build_object(
            'id', d.id, 'name', d.name, 'settings', d.settings,
            'last_seen_at', to_char(d.last_seen_at, 'YYYY-MM-DD HH24:MI:SS'),
            'calendar_ids', coalesce((select json_agg(c.calendar_id order by c.calendar_id)
                                      from home_display_calendar c where c.display_id = d.id), '[]'::json),
            'task_list_ids', coalesce((select json_agg(t.task_list_id order by t.task_list_id)
                                       from home_display_task_list t where t.display_id = d.id), '[]'::json)
        ) order by d.id)
        from home_display d where d.home_id = p_home_id and d.revoked_at is null
    ), '[]'::json);
end
$$;

commit;
