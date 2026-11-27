-- 0053_pantallas_canal_version.sql — dashboard-pantallas-canal (paso 2): GET /home/display (fn_display_list) devuelve el
-- canal, la versión instalada y el último resultado de actualización de cada pantalla (0051). Quien gestiona ve lo que
-- PATCH /home/display/channel cambia, y la versión que reporta la pantalla. Aditiva: solo añade campos al JSON; los
-- permisos (revoke/grant) se conservan porque es create or replace de la misma firma.

create or replace function fn_display_list(p_home_id bigint) returns json
language plpgsql stable security definer set search_path = public as $$
begin
    perform fn_require_member(p_home_id);
    return coalesce((
        select json_agg(json_build_object(
            'id', d.id, 'name', d.name, 'settings', d.settings,
            'last_seen_at', to_char(d.last_seen_at, 'YYYY-MM-DD HH24:MI:SS'),
            'update_channel', d.update_channel,
            'app_version_code', d.app_version_code,
            'app_version_name', d.app_version_name,
            'last_update_check_at', to_char(d.last_update_check_at, 'YYYY-MM-DD HH24:MI:SS'),
            'last_update_result', d.last_update_result,
            'calendar_ids', coalesce((select json_agg(c.calendar_id order by c.calendar_id)
                                      from home_display_calendar c where c.display_id = d.id), '[]'::json),
            'task_list_ids', coalesce((select json_agg(t.task_list_id order by t.task_list_id)
                                       from home_display_task_list t where t.display_id = d.id), '[]'::json)
        ) order by d.id)
        from home_display d where d.home_id = p_home_id and d.revoked_at is null
    ), '[]'::json);
end
$$;
