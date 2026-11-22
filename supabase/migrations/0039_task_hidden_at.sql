-- 0039_task_hidden_at.sql — change ocultar-completadas-3-dias (tarjeta [13], D-025): las tareas
-- completadas se ocultan 3 días después de completarse, sin recuperación.
--
-- * Columna task.hidden_at timestamptz nullable, sin default. Solo la escribe complete_task (en el mismo
--   UPDATE que completed_at) y el backfill de esta migración. No se expone en ninguna respuesta (S-P1):
--   las shapes de task/* no cambian (D-008).
-- * Fórmula única: hidden_at = (completed_at + interval '3 days') at time zone 'UTC'. completed_at es
--   timestamp naive en UTC; la suma se hace en UTC naive y se convierte después, así no depende del
--   TimeZone de la sesión (timestamptz + '3 days' daría 71 o 73 h en un cambio de horario). El CHECK
--   task_hidden_at_consistent la exige: no completada ⇒ hidden_at null; completada ⇒ hidden_at no nulo
--   e igual a la fórmula.
-- * Predicado «oculta»: hidden_at is not null and hidden_at <= now(). «Visible»: (hidden_at is null or
--   hidden_at > now()). Va inline sobre el valor crudo (S5), sin cron (S3).
-- * Backfill: todas las completadas reciben hidden_at con la fórmula (también las de hace menos de 3
--   días, con hidden_at futuro). No toca completed_at, updated_at, "order" ni priority; task no tiene
--   triggers.
-- * Sin recuperación (D-025): no hay ruta, RPC ni campo para restaurar. Una tarea oculta es
--   indistinguible de una inexistente: get_task_detail y las escrituras (complete_task true/false,
--   update_task, task_order, delete_task) lanzan 'Not Found' P0002 (→ 500 {"error":"Not Found"} por el
--   rpcPass de la Edge, como hoy). En las escrituras la comprobación va en la búsqueda inicial, antes del
--   lock y de la ACL, y la fila no se modifica. get_task_detail la hace después del check ACL de
--   siempre (un no miembro recibe el mismo Not Found de antes).
-- * Orden: task_order y fn_reorder_tasks excluyen las ocultas; su "order" queda congelado y la posición
--   se cuenta solo sobre tareas visibles (S-P3).
-- * Policy task_select (S-P2): además de la ACL, la lectura directa por PostgREST no devuelve ocultas.
-- * Base de cada función (la última definición vigente; sin cambios de firma ni DROP, grants intactos):
--     get_tasks(boolean,bigint,boolean,text,text)  0037_task_priority.sql:68-114
--     get_task_detail(bigint)                      0037_task_priority.sql:35-61
--     complete_task(bigint,boolean)                0029_acl_can_edit.sql:703-737
--     update_task(bigint,text,jsonb,text)          0037_task_priority.sql:197-243
--     task_order(bigint,integer)                   0029_acl_can_edit.sql:740-789
--     delete_task(bigint)                          0029_acl_can_edit.sql:792-823
--     fn_reorder_tasks(bigint)                     0006_write_rpcs.sql:37-53
--     policy task_select                           0020_home_write_guards.sql:229-231
--   Cada línea añadida lleva `-- 0039:`.
-- Rollback: scripts/supabase/rollback/rollback_0039.sql (restaura los 7 cuerpos y la policy, quita el
-- CHECK y la columna; solo se pierde hidden_at, derivable). Orden LIFO de rollbacks:
-- rollback_0039 → rollback_0038 → rollback_0037 → rollback_0035.

begin;

-- 0039: columna, backfill y CHECK de consistencia
alter table task add column hidden_at timestamptz; -- 0039:

update task set hidden_at = (completed_at + interval '3 days') at time zone 'UTC' -- 0039:
where completed_at is not null; -- 0039:

alter table task add constraint task_hidden_at_consistent check ( -- 0039:
    (completed_at is null and hidden_at is null) -- 0039:
    -- 0039: «hidden_at is not null» explícito: sin él, completada con hidden_at null daría NULL y el CHECK
    -- 0039: la aceptaría (un CHECK solo rechaza false).
    or (completed_at is not null and hidden_at is not null -- 0039:
        and hidden_at = (completed_at + interval '3 days') at time zone 'UTC') -- 0039:
); -- 0039:

-- get_tasks: cuerpo de 0037_task_priority.sql:68-114 + predicado visible sobre tk.hidden_at crudo.
create or replace function get_tasks(p_dashboard boolean default null, p_task_list_id bigint default null,
                                     p_widget boolean default null, p_priority text default null,
                                     p_sort text default null) returns json
language sql stable set search_path = public as $$
    select coalesce(
        json_agg(json_build_object(
            'id', t.id,
            'task_list_id', t.task_list_id,
            'task_list_color', t.task_list_color,
            'task_list_name', t.task_list_name,
            'title', t.title,
            'order', t."order",
            'priority', t.priority,
            'completed_at', t.completed_at,
            'created_at', t.created_at,
            'updated_at', t.updated_at,
            'persons', coalesce(fn_task_persons(t.id), '[]'::json)
        ) order by (t.completed_at is not null) asc,
                   -- 0037: con p_sort = 'priority', alta > media > baja; si no, sin efecto (constante)
                   case when p_sort = 'priority' then
                       case t.priority when 'alta' then 1 when 'media' then 2 else 3 end
                   else 0 end asc,
                   t."order" asc, t.id asc),
        '[]'::json)
    from (
        select tk.id,
               tk.task_list_id,
               tl.color as task_list_color,
               tl.name as task_list_name,
               tk.title,
               tk."order",
               tk.priority,
               to_char(tk.completed_at, 'YYYY-MM-DD HH24:MI:SS') as completed_at,
               to_char(tk.created_at, 'YYYY-MM-DD HH24:MI:SS') as created_at,
               to_char(tk.updated_at, 'YYYY-MM-DD HH24:MI:SS') as updated_at
        from task tk
        inner join task_list tl on tl.id = tk.task_list_id
        -- 1.8 (§3.3): visibilidad ACL ∪ admin (Q1)
        left join task_list_user tlu on tlu.task_list_id = tk.task_list_id and tlu.user_id = fn_my_user_id()
        where tk.task_list_id in (select fn_visible_task_list_ids())
          and (p_task_list_id is null or p_task_list_id = 0 or tk.task_list_id = p_task_list_id)
          and (p_widget is null or tlu.widget = p_widget)
          and (p_dashboard is null or tlu.dashboard = p_dashboard)
          -- 0037: filtro opcional por prioridad
          and (p_priority is null or tk.priority = p_priority)
          and (tk.hidden_at is null or tk.hidden_at > now()) -- 0039: fuera las ocultas
    ) t
$$;

-- get_task_detail: cuerpo de 0037_task_priority.sql:35-61 + oculta = Not Found (tras el check ACL).
create or replace function get_task_detail(p_id bigint) returns json
language plpgsql stable security definer set search_path = public as $$
begin
    if fn_my_user_id() is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    if not exists (
        select 1 from task t
        where t.id = p_id and t.task_list_id in (select fn_visible_task_list_ids())
    ) then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    if exists (select 1 from task t where t.id = p_id and t.hidden_at is not null and t.hidden_at <= now()) then -- 0039:
        raise exception 'Not Found' using errcode = 'P0002'; -- 0039: oculta, como inexistente
    end if; -- 0039:
    return (
        select json_build_object(
            'id', t.id, 'task_list_id', t.task_list_id, 'title', t.title,
            'completed_at', to_char(t.completed_at, 'YYYY-MM-DD HH24:MI:SS'),
            'created_at', to_char(t.created_at, 'YYYY-MM-DD HH24:MI:SS'),
            'updated_at', to_char(t.updated_at, 'YYYY-MM-DD HH24:MI:SS'),
            'order', t."order",
            'priority', t.priority,
            'task_list_color', tl.color, 'task_list_name', tl.name,
            'persons', coalesce(fn_task_persons(t.id), '[]'::json))
        from task t
        inner join task_list tl on tl.id = t.task_list_id
        where t.id = p_id
    );
end $$;

-- complete_task: cuerpo de 0029_acl_can_edit.sql:703-737 + oculta = Not Found + hidden_at en el UPDATE.
create or replace function complete_task(p_id bigint, p_completed boolean) returns json
language plpgsql security definer set search_path = public as $$
declare
    v_me bigint := fn_my_user_id();
    v_list bigint;
    v_home bigint;
    v_role user_role;
begin
    if v_me is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    -- 1.8 (§2.2/§2.3): lock (hogar de la tarea) → ACL → task.complete
    select t.task_list_id into v_list from task t where t.id = p_id
      and (t.hidden_at is null or t.hidden_at > now()); -- 0039: una oculta es Not Found
    if v_list is null then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    v_home := fn_home_of_task_list(v_list);
    perform fn_home_write_lock(v_home);
    select role into v_role from task_list_user where task_list_id = v_list and user_id = v_me for share;
    if v_role is null then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    -- 0029 (E2): tope adicional, permiso de edición en el ACL (owner o can_edit)
    if not fn_task_list_editable(v_list) then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    if not fn_has_permission(v_home, 'task.complete') then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    update task
    set completed_at = case when p_completed then (now() at time zone 'UTC') else null end,
        hidden_at = case when p_completed then ((now() at time zone 'UTC') + interval '3 days') at time zone 'UTC' else null end, -- 0039:
        updated_at = (now() at time zone 'UTC')
    where id = p_id;
    return get_task_detail(p_id);
end $$;

-- update_task: cuerpo de 0037_task_priority.sql:197-243 + oculta = Not Found.
create or replace function update_task(p_id bigint, p_title text, p_person_ids jsonb default null,
                                       p_priority text default null) returns json
language plpgsql security definer set search_path = public as $$
declare
    v_me bigint := fn_my_user_id();
    v_list bigint;
    v_home bigint;
    v_role user_role;
begin
    if v_me is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    -- H0: espejo de phpEmpty (usecases/tasks.ts:65)
    if p_title is null or p_title = '' or p_title = '0' then
        raise exception 'Task ID and title are required' using errcode = 'P0001';
    end if;
    -- 0037: prioridad opcional (null → se conserva); fuera de las tres opciones → 400 en la Edge
    if p_priority is not null and p_priority not in ('alta', 'media', 'baja') then
        raise exception 'Invalid priority' using errcode = 'P0001';
    end if;
    -- 1.8 (§2.2/§2.3): validación → lock (hogar de la tarea) → ACL → task.edit
    select t.task_list_id into v_list from task t where t.id = p_id
      and (t.hidden_at is null or t.hidden_at > now()); -- 0039: una oculta es Not Found
    if v_list is null then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    v_home := fn_home_of_task_list(v_list);
    perform fn_home_write_lock(v_home);
    select role into v_role from task_list_user where task_list_id = v_list and user_id = v_me for share;
    if v_role is null then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    -- 0029 (E2): tope adicional, permiso de edición en el ACL (owner o can_edit)
    if not fn_task_list_editable(v_list) then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    if not fn_has_permission(v_home, 'task.edit') then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    update task set title = p_title, priority = coalesce(p_priority, priority),
                    updated_at = (now() at time zone 'UTC')
    where id = p_id;
    if p_person_ids is not null then
        perform fn_sync_assignments('task_person', 'task_id', p_id, p_person_ids);
    end if;
    perform fn_reorder_tasks(v_list);
    return get_task_detail(p_id);
end $$;

-- task_order: cuerpo de 0029_acl_can_edit.sql:740-789 + oculta = Not Found + ranking solo de visibles.
create or replace function task_order(p_id bigint, p_position integer) returns json
language plpgsql security definer set search_path = public as $$
declare
    v_me bigint := fn_my_user_id();
    v_list bigint;
    v_ids bigint[];
    v_rest bigint[];
    v_pos integer;
    v_home bigint;
    v_role user_role;
begin
    if v_me is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    -- 1.8 (§2.2/§2.3): lock (hogar de la tarea) → ACL → task.edit
    select t.task_list_id into v_list from task t where t.id = p_id
      and (t.hidden_at is null or t.hidden_at > now()); -- 0039: una oculta es Not Found
    if v_list is null then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    v_home := fn_home_of_task_list(v_list);
    perform fn_home_write_lock(v_home);
    select role into v_role from task_list_user where task_list_id = v_list and user_id = v_me for share;
    if v_role is null then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    -- 0029 (E2): tope adicional, permiso de edición en el ACL (owner o can_edit)
    if not fn_task_list_editable(v_list) then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    if not fn_has_permission(v_home, 'task.edit') then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    select coalesce(array_agg(id order by "order", id), array[]::bigint[])
    into v_ids from task where task_list_id = v_list
      and (hidden_at is null or hidden_at > now()); -- 0039: las ocultas no cuentan ni se renumeran
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

-- delete_task: cuerpo de 0029_acl_can_edit.sql:792-823 + oculta = Not Found (sin borrado).
create or replace function delete_task(p_id bigint) returns json
language plpgsql security definer set search_path = public as $$
declare
    v_me bigint := fn_my_user_id();
    v_list bigint;
    v_home bigint;
    v_role user_role;
begin
    if v_me is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    -- 1.8 (§2.2/§2.3): lock (hogar de la tarea) → ACL → task.delete
    select t.task_list_id into v_list from task t where t.id = p_id
      and (t.hidden_at is null or t.hidden_at > now()); -- 0039: una oculta es Not Found
    if v_list is null then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    v_home := fn_home_of_task_list(v_list);
    perform fn_home_write_lock(v_home);
    select role into v_role from task_list_user where task_list_id = v_list and user_id = v_me for share;
    if v_role is null then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    -- 0029 (E2): tope adicional, permiso de edición en el ACL (owner o can_edit)
    if not fn_task_list_editable(v_list) then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    if not fn_has_permission(v_home, 'task.delete') then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    delete from task where id = p_id;
    return '{"success":true}'::json;
end $$;

-- fn_reorder_tasks: cuerpo de 0006_write_rpcs.sql:37-53 + ranking solo de visibles (ocultas congeladas).
create or replace function fn_reorder_tasks(p_task_list_id bigint) returns void
language plpgsql security definer set search_path = public as $$
begin
    update task t
    set "order" = ranked.rn
    from (
        select t2.id, row_number() over (
            order by case when tl.sort = 'title' then t2.title end asc,
                     case when tl.sort in ('updated_at', 'custom') then t2.updated_at end desc,
                     t2.id
        ) as rn
        from task t2
        inner join task_list tl on tl.id = t2.task_list_id
        where t2.task_list_id = p_task_list_id
          and (t2.hidden_at is null or t2.hidden_at > now()) -- 0039: las ocultas no se renumeran
    ) ranked
    where t.id = ranked.id and t.task_list_id = p_task_list_id;
end $$;

-- policy task_select: la de 0020_home_write_guards.sql:229-231 + predicado visible (S-P2).
drop policy if exists task_select on task;
create policy task_select on task for select to authenticated
    using (task_list_id in (select fn_visible_task_list_ids())
           and (hidden_at is null or hidden_at > now())); -- 0039:

commit;

notify pgrst, 'reload schema';
