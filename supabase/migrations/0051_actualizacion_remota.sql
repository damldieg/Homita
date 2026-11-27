-- 0051_actualizacion_remota.sql — dashboard-actualizacion-remota (A7): actualizar las apps de las pantallas sin ADB.
-- Canal por pantalla (estable | pruebas), versión instalada y último resultado de la comprobación de actualización.
-- La pantalla informa de su versión (cabeceras de /display/config y de /display/update); solo escribe su propia fila.
-- El bucket `display-releases` guarda el APK y el manifiesto por canal (estable.json, pruebas.json); lo escribe el
-- script de publicación con la clave de servicio de Damian (nunca en el repo) y lo lee solo la Edge.
-- Aditivo: no cambia ninguna función existente.

alter table home_display
    add column if not exists update_channel text not null default 'estable' check (update_channel in ('estable', 'pruebas')),
    add column if not exists app_version_code integer check (app_version_code is null or app_version_code >= 0),
    add column if not exists app_version_name text check (app_version_name is null or char_length(app_version_name) <= 40),
    add column if not exists last_update_check_at timestamptz,
    add column if not exists last_update_result text check (last_update_result is null or char_length(last_update_result) <= 200);

-- Lo que la pantalla reporta de sí misma. p_checked = true cuando es una comprobación de actualización (sella
-- last_update_check_at). Devuelve el canal que le toca.
create or replace function fn_display_report(p_version_code integer, p_version_name text, p_result text, p_checked boolean)
returns json
language plpgsql security definer set search_path = public as $$
declare v_display home_display;
begin
    select * into v_display from home_display where app_user_id = fn_my_user_id() and revoked_at is null for update;
    if not found then raise exception 'Not Found' using errcode = 'P0002'; end if;
    update home_display
    set last_seen_at = (now() at time zone 'UTC'),
        app_version_code = coalesce(p_version_code, app_version_code),
        app_version_name = coalesce(left(btrim(p_version_name), 40), app_version_name),
        last_update_result = coalesce(left(btrim(p_result), 200), last_update_result),
        last_update_check_at = case when coalesce(p_checked, false) then (now() at time zone 'UTC') else last_update_check_at end
    where id = v_display.id;
    return json_build_object('channel', v_display.update_channel);
end $$;

-- Cambio de canal desde el móvil (quien gestiona pantallas). Una sola fila; la pantalla no puede cambiarse su canal.
create or replace function fn_display_set_channel(p_home_id bigint, p_display_id bigint, p_channel text) returns json
language plpgsql security definer set search_path = public as $$
declare v_channel text := btrim(coalesce(p_channel, ''));
begin
    perform fn_home_write_lock(p_home_id);
    if not fn_can_manage_displays(p_home_id) then raise exception 'Not Allowed' using errcode = '42501'; end if;
    if v_channel not in ('estable', 'pruebas') then raise exception 'Invalid channel' using errcode = 'P0001'; end if;
    update home_display set update_channel = v_channel
    where id = p_display_id and home_id = p_home_id and revoked_at is null;
    if not found then raise exception 'Not Found' using errcode = 'P0002'; end if;
    return json_build_object('id', p_display_id, 'channel', v_channel);
end $$;

revoke all on function fn_display_report(integer, text, text, boolean) from public, anon;
revoke all on function fn_display_set_channel(bigint, bigint, text) from public, anon;
grant execute on function fn_display_report(integer, text, text, boolean) to authenticated;
grant execute on function fn_display_set_channel(bigint, bigint, text) to authenticated;

-- Bucket privado de publicaciones. Solo la Edge (clave de servicio) y el script de publicación lo tocan.
insert into storage.buckets (id, name, public) values ('display-releases', 'display-releases', false)
on conflict (id) do nothing;
