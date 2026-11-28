-- 0054_display_acl.sql — R1-04 de la revisión de dashboard-pantalla-hogar: fn_display_update exige permiso de edición
-- sobre cada calendario y lista que la pantalla añade (no solo que sean del hogar). Redefine la función de 0049 (misma
-- firma: create or replace conserva los GRANT/REVOKE). Aditiva. Idempotente.

create or replace function fn_display_update(p_home_id bigint, p_display_id bigint, p_name text,
    p_settings jsonb, p_calendar_ids bigint[], p_task_list_ids bigint[]) returns json
language plpgsql security definer set search_path = public as $$
declare
    v_display home_display;
    v_name text := btrim(coalesce(p_name, ''));
    v_cal bigint[] := coalesce(p_calendar_ids, '{}');
    v_tl bigint[] := coalesce(p_task_list_ids, '{}');
begin
    if not fn_can_manage_displays(p_home_id) then raise exception 'Not Allowed'; end if;
    select * into v_display from home_display where id = p_display_id and home_id = p_home_id and revoked_at is null for update;
    if not found then raise exception 'Not Found'; end if;
    if v_name = '' or char_length(v_name) > 50 then raise exception 'Name is required (max 50 characters)'; end if;
    if p_settings is not null and jsonb_typeof(p_settings) <> 'object' then raise exception 'Invalid display settings'; end if;
    -- Solo calendarios y listas del propio hogar
    if exists (select 1 from unnest(v_cal) c where not exists (select 1 from calendar where id = c and home_id = p_home_id))
       or exists (select 1 from unnest(v_tl) t where not exists (select 1 from task_list where id = t and home_id = p_home_id)) then
        raise exception 'Invalid display selection';
    end if;

    -- R1-04 (0054): quien llama solo AÑADE calendarios y listas sobre los que tiene permiso de edición (dueño o can_edit),
    -- como el resto de la app. Los que ya estaban en la selección se conservan aunque ya no los pueda editar.
    if exists (select 1 from unnest(v_cal) c
               where c not in (select calendar_id from home_display_calendar where display_id = p_display_id)
                 and not fn_calendar_editable(c))
       or exists (select 1 from unnest(v_tl) t
               where t not in (select task_list_id from home_display_task_list where display_id = p_display_id)
                 and not fn_task_list_editable(t)) then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;

    update home_display
    set name = v_name, settings = coalesce(p_settings, settings), updated_at = (now() at time zone 'UTC')
    where id = p_display_id;

    -- Calendarios: quitar los que sobran y añadir los nuevos (viewer, con dashboard)
    delete from calendar_user cu
    where cu.user_id = v_display.app_user_id and cu.calendar_id not in (select unnest(v_cal));
    insert into calendar_user (calendar_id, user_id, role, widget, dashboard, home_id)
    select c, v_display.app_user_id, 'viewer', false, true, p_home_id from unnest(v_cal) c
    on conflict do nothing;
    update calendar_user set dashboard = true where user_id = v_display.app_user_id and calendar_id in (select unnest(v_cal));
    delete from home_display_calendar where display_id = p_display_id;
    insert into home_display_calendar (display_id, calendar_id) select p_display_id, c from unnest(v_cal) c;

    -- Listas: igual
    delete from task_list_user tu
    where tu.user_id = v_display.app_user_id and tu.task_list_id not in (select unnest(v_tl));
    insert into task_list_user (task_list_id, user_id, role, widget, dashboard, home_id)
    select t, v_display.app_user_id, 'viewer', false, true, p_home_id from unnest(v_tl) t
    on conflict do nothing;
    update task_list_user set dashboard = true where user_id = v_display.app_user_id and task_list_id in (select unnest(v_tl));
    delete from home_display_task_list where display_id = p_display_id;
    insert into home_display_task_list (display_id, task_list_id) select p_display_id, t from unnest(v_tl) t;

    return json_build_object('id', p_display_id);
end
$$;
