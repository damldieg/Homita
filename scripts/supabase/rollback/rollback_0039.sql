-- rollback_0039.sql — Revierte 0039_task_hidden_at.sql (change ocultar-completadas-3-dias, D-025).
-- create or replace (mismas firmas, sin DROP; los grants se conservan) de los 7 cuerpos vigentes antes
-- de 0039, verbatim (pg_get_functiondef del reset local 0001–0038):
--   get_tasks(boolean,bigint,boolean,text,text)  0037_task_priority.sql:68-114
--   get_task_detail(bigint)                      0037_task_priority.sql:35-61
--   complete_task(bigint,boolean)                0029_acl_can_edit.sql:703-737
--   update_task(bigint,text,jsonb,text)          0037_task_priority.sql:197-243
--   task_order(bigint,integer)                   0029_acl_can_edit.sql:740-789
--   delete_task(bigint)                          0029_acl_can_edit.sql:792-823
--   fn_reorder_tasks(bigint)                     0006_write_rpcs.sql:37-53
-- y la policy task_select de 0020_home_write_guards.sql:229-231; después quita el CHECK
-- task_hidden_at_consistent y la columna task.hidden_at.
-- md5(pg_get_functiondef) de esos cuerpos en supabase/postgres:17.* (lo comprueba
-- task_hidden_rollback_check RBH2; mismas constantes en DEPLOY_0039.md P4):
--   get_tasks 33a865e264ce1a37b88fd5c3405cc6e8      get_task_detail 7836409cddb8166d96accf9eda9055e2
--   complete_task 9ae29a1507fea681afbbbb95d4a91f42  update_task c612b928103c69af64ba185d2f6553cf
--   task_order f6a3aaec2bf25d06aa401ef742d209ac     delete_task 739b0765bbe2dcf4feb2978eef6840d1
--   fn_reorder_tasks e011b88332da15df3e0b365e50be996f
--   policy task_select md5(pg_get_expr(polqual)) b3d1a237c023b4ce73d89666567a1538
-- Idempotente: se puede aplicar dos veces.
--
-- DATOS: solo se pierde task.hidden_at, que se deriva de completed_at (completed_at + 3 días en UTC);
-- reaplicar 0039 lo recalcula con el backfill. Ninguna fila se borra ni cambia completed_at. Tras el
-- rollback las tareas ocultas vuelven a verse y a ser editables, con su "order" congelado (cosmético;
-- el siguiente reorden lo arregla).
-- Orden en prod: solo BD (la Edge no cambia con 0039).
-- supabase_migrations.schema_migrations: la fila '0039' no se borra aquí (mismo criterio que 0035/0037/0038).
-- Orden LIFO: este script va ANTES de rollback_0038.sql
-- (rollback_0039 → rollback_0038 → rollback_0037 → rollback_0035); rollback_0038 aborta mientras exista
-- task.hidden_at. La guarda del principio aborta si faltan las firmas de 0037 (get_tasks de 5
-- argumentos o update_task de 4): un create or replace dejaría entonces una sobrecarga nueva.

begin;

do $$
begin
    if to_regprocedure('public.get_tasks(boolean,bigint,boolean,text,text)') is null
       or to_regprocedure('public.update_task(bigint,text,jsonb,text)') is null then
        raise exception 'rollback_0039: faltan get_tasks(boolean,bigint,boolean,text,text) o update_task(bigint,text,jsonb,text) (¿0037 revertida?); nada que revertir sin 0037 (orden LIFO)';
    end if;
end $$;

CREATE OR REPLACE FUNCTION public.get_tasks(p_dashboard boolean DEFAULT NULL::boolean, p_task_list_id bigint DEFAULT NULL::bigint, p_widget boolean DEFAULT NULL::boolean, p_priority text DEFAULT NULL::text, p_sort text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
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
    ) t
$function$
;

CREATE OR REPLACE FUNCTION public.get_task_detail(p_id bigint)
 RETURNS json
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
end $function$
;

CREATE OR REPLACE FUNCTION public.complete_task(p_id bigint, p_completed boolean)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
    select t.task_list_id into v_list from task t where t.id = p_id;
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
        updated_at = (now() at time zone 'UTC')
    where id = p_id;
    return get_task_detail(p_id);
end $function$
;

CREATE OR REPLACE FUNCTION public.update_task(p_id bigint, p_title text, p_person_ids jsonb DEFAULT NULL::jsonb, p_priority text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
    select t.task_list_id into v_list from task t where t.id = p_id;
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
end $function$
;

CREATE OR REPLACE FUNCTION public.task_order(p_id bigint, p_position integer)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
    select t.task_list_id into v_list from task t where t.id = p_id;
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
end $function$
;

CREATE OR REPLACE FUNCTION public.delete_task(p_id bigint)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
    select t.task_list_id into v_list from task t where t.id = p_id;
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
end $function$
;

CREATE OR REPLACE FUNCTION public.fn_reorder_tasks(p_task_list_id bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
    ) ranked
    where t.id = ranked.id and t.task_list_id = p_task_list_id;
end $function$
;

-- policy task_select de 0020_home_write_guards.sql:229-231 (sin el predicado de ocultas).
drop policy if exists task_select on task;
create policy task_select on task for select to authenticated
    using (task_list_id in (select fn_visible_task_list_ids()));

alter table task drop constraint if exists task_hidden_at_consistent;
alter table task drop column if exists hidden_at;

commit;

notify pgrst, 'reload schema';
