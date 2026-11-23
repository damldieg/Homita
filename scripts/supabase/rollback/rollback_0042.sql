-- rollback_0042.sql — Revierte 0042_task_due_set_null.sql: vuelve el cuerpo de task_due_set de 0041
-- (un p_due_at nulo sin p_clear_due vuelve a borrar la fecha). Sin pérdida de datos.

begin;

create or replace function task_due_set(p_id bigint, p_due_at text default null, p_clear_due boolean default false)
returns json -- 0041:
language plpgsql security definer set search_path = public as $$
declare
    v_me bigint := fn_my_user_id();
    v_list bigint;
    v_home bigint;
    v_role user_role;
    v_due timestamp;
begin
    if v_me is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    -- Fecha: p_clear_due gana; si no, p_due_at es obligatorio y debe ser un timestamp válido.
    if not p_clear_due then
        begin
            v_due := p_due_at::timestamp;
        exception when others then
            raise exception 'Invalid due_at' using errcode = 'P0001';
        end;
    end if;
    -- validación → lock (hogar de la tarea) → ACL → task.edit, como update_task (0039)
    select t.task_list_id into v_list from task t where t.id = p_id
      and (t.hidden_at is null or t.hidden_at > now());
    if v_list is null then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    v_home := fn_home_of_task_list(v_list);
    perform fn_home_write_lock(v_home);
    select role into v_role from task_list_user where task_list_id = v_list and user_id = v_me for share;
    if v_role is null then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    if not fn_task_list_editable(v_list) then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    if not fn_has_permission(v_home, 'task.edit') then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    update task set due_at = case when p_clear_due then null else v_due end
    where id = p_id;
    return get_task_detail(p_id);
end $$;

commit;

notify pgrst, 'reload schema';
