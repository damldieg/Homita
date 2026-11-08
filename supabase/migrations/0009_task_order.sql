-- 0009_task_order.sql — task/order: Task::moveToPosition (Task.php:282-305) (control-api).
--
-- Semántica (T2 confirmada): ids de la lista ordenados por ("order", id), quitarse a uno mismo,
-- clamp de position a [0..n], splice en esa posición, renumerar 1..n. Devuelve la forma PHP de la
-- tarea (get_task_detail). Validaciones 400 de TaskOrder.php las hace la Edge.
-- SECURITY DEFINER + guardia de membresía (TaskListUser::check → 'Not Found').

create or replace function task_order(p_id bigint, p_position integer) returns json
language plpgsql security definer set search_path = public as $$
declare
    v_me bigint := fn_my_user_id();
    v_list bigint;
    v_ids bigint[];
    v_rest bigint[];
    v_pos integer;
begin
    if v_me is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    select t.task_list_id into v_list
    from task t
    inner join task_list_user tlu on tlu.task_list_id = t.task_list_id and tlu.user_id = v_me
    where t.id = p_id;
    if v_list is null then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    select coalesce(array_agg(id order by "order", id), array[]::bigint[])
    into v_ids from task where task_list_id = v_list;
    select coalesce(array_agg(id order by ord), array[]::bigint[])
    into v_rest from unnest(v_ids) with ordinality t(id, ord)
    where id <> p_id;
    v_pos := least(greatest(p_position, 0), array_length(v_rest, 1));
    v_rest := (select array_agg(x order by ord) from (
        select elem as x, ord from unnest(v_rest[1:v_pos]) with ordinality t(elem, ord)
        union all
        select p_id, v_pos + 1
        union all
        select elem as x, ord + v_pos + 1 from unnest(v_rest[v_pos + 1:]) with ordinality t(elem, ord)
    ) s);
    for v_pos in 1 .. array_length(v_rest, 1) loop
        update task set "order" = v_pos where id = v_rest[v_pos];
    end loop;
    return get_task_detail(p_id);
end $$;

revoke execute on function task_order(bigint, integer) from public, anon;
grant execute on function task_order(bigint, integer) to authenticated;
