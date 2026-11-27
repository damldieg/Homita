-- marcar_hecho_rollback_check.sql — Ida y vuelta de 0050 (rollback_0050_marcar_hecho.sql).
-- Tras el rollback: 'ok MR1' (sin complete_task de tres argumentos ni fn_is_display_for_list), 'ok MR2' (sin
-- task.complete en las pantallas) y 'ok MR3' (client_request sin kind 'task_complete'). ci.sh reaplica 0050 después.

do $$
begin
    if to_regprocedure('public.complete_task(bigint,boolean,uuid)') is not null
       or to_regprocedure('public.fn_is_display_for_list(bigint,bigint)') is not null then
        raise exception 'marcar_hecho_rollback MR1: quedan complete_task(…,uuid) o fn_is_display_for_list';
    end if;
    if to_regprocedure('public.complete_task(bigint,boolean)') is null then
        raise exception 'marcar_hecho_rollback MR1: falta complete_task de 0039';
    end if;
    raise notice 'ok MR1: complete_task vuelve a la versión de 0039';
end $$;

do $$
begin
    if exists (select 1 from membership_permission mp
               join home_membership hm on hm.id = mp.home_membership_id
               join home_member m on m.home_id = hm.home_id and m.app_user_id = hm.app_user_id
               where m.kind = 'display' and mp.permission_code = 'task.complete') then
        raise exception 'marcar_hecho_rollback MR2: quedan task.complete en pantallas';
    end if;
    raise notice 'ok MR2: las pantallas ya no completan tareas';
end $$;

do $$
begin
    if exists (select 1 from client_request where kind = 'task_complete') then
        raise exception 'marcar_hecho_rollback MR3: quedan claves task_complete';
    end if;
    raise notice 'ok MR3: sin claves de completar';
end $$;
