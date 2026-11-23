-- 0042_task_due_set_null.sql — corrige task_due_set (0041, fecha-limite-vencimiento) para que un p_due_at
-- nulo sin p_clear_due no borre la fecha. Antes, `null::timestamp` daba null y el UPDATE dejaba due_at a null
-- en silencio. Ahora es 'Invalid due_at' (P0001), igual que un texto no parseable. Borrar sigue siendo
-- p_clear_due = true. Mismas firma, reglas de acceso y grants que 0041; solo cambia el control de entrada.
-- Rollback: scripts/supabase/rollback/rollback_0042.sql (restaura el cuerpo de 0041).

begin;

create or replace function task_due_set(p_id bigint, p_due_at text default null, p_clear_due boolean default false)
returns json
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
    -- 0042: sin fecha y sin borrado explícito, la llamada es inválida (antes borraba la fecha en silencio).
    if not p_clear_due then
        if p_due_at is null or p_due_at = '' then
            raise exception 'Invalid due_at' using errcode = 'P0001';
        end if;
        begin
            v_due := p_due_at::timestamp;
        exception when others then
            raise exception 'Invalid due_at' using errcode = 'P0001';
        end;
    end if;
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
