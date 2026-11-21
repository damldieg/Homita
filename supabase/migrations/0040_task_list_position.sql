-- 0040_task_list_position.sql — change lista-prioritaria-inicio: orden persistente de las listas de tareas.
--
-- * `task_list.position integer null` con check (position is null or position > 0). Global por hogar
--   (A1: no por usuario). Nullable a propósito (A9): create_task_list no se toca; las listas nuevas nacen
--   sin posición y salen al final hasta que alguien reordene. Así rollback_0035 sigue siendo independiente.
-- * Backfill determinista (A5): por hogar, row_number() ordenado por created_at, id.
-- * get_task_lists(): cuerpo de 0029_acl_can_edit.sql + clave aditiva `position` y nuevo orden
--   `position` asc (nulls last), `name` (collate "C"), `id` (A3). Ninguna otra clave cambia.
-- * reorder_task_lists(p_ids bigint[]) returns json: SECURITY DEFINER, solo authenticated. Recibe la lista
--   completa en el orden deseado (A4) y escribe position = 1..n de forma atómica. Modelo de
--   update_task_list (0029): lock del hogar, ACL propia (for share), fn_task_list_editable y permiso
--   'tasklist.manage'. No cambia updated_at ni toca sort/tareas (A12).
--   Errores: 'Not Allowed' 42501; 'Not Found' P0002 (ids vacíos, duplicados, inexistentes, de otro hogar o
--   sin ACL propia).
-- * A10: las listas del hogar que el usuario no ve conservan su position (pueden empatar con las visibles;
--   el desempate es name, id).
-- Rollback: scripts/supabase/rollback/rollback_0040.sql (se pierde el orden elegido).
-- D-022: se aplica en prod al mergear; es aditiva (columna nullable + backfill + dos funciones).

begin;

-- ─────────────────── (a) Columna y backfill ───────────────────

alter table task_list add column position integer null;
alter table task_list add constraint task_list_position_check check (position is null or position > 0);

update task_list tl set position = r.rn
from (
    select id, row_number() over (partition by home_id order by created_at, id)::integer as rn
    from task_list
) r
where r.id = tl.id;

-- ─────────────────── (b) get_task_lists con position ───────────────────

create or replace function get_task_lists() returns json
language plpgsql stable security definer set search_path = public as $$
begin
    if fn_my_user_id() is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    if fn_active_home_id() is not null then
        perform fn_require_member(fn_active_home_id());
    end if;
    return (
        select coalesce(json_agg(json_build_object(
            'id', tl.id, 'name', tl.name, 'color', tl.color, 'token', tl.token, 'sort', tl.sort,
            'created_at', to_char(tl.created_at, 'YYYY-MM-DD HH24:MI:SS'),
            'updated_at', to_char(tl.updated_at, 'YYYY-MM-DD HH24:MI:SS'),
            'widget', coalesce(tlu.widget, false)::int,
            'dashboard', coalesce(tlu.dashboard, false)::int,
            'pending_task_count', coalesce(pc.cnt, 0),
            'home_id', tl.home_id,
            'can_edit', coalesce(tlu.role = 'owner' or tlu.can_edit, false),
            'position', tl.position
        ) order by tl.position nulls last, tl.name collate "C", tl.id), '[]'::json)
        from task_list tl
        -- 1.8 (§3.3): ACL izquierda (admin sin ACL: widget/dashboard false, A-5) + visibilidad
        -- fn_visible_task_list_ids (ACL ∪ admin, Q1)
        left join task_list_user tlu on tlu.task_list_id = tl.id and tlu.user_id = fn_my_user_id()
        left join lateral (
            select count(*) as cnt from task t
            where t.task_list_id = tl.id and t.completed_at is null
        ) pc on true
        where tl.id in (select fn_visible_task_list_ids())
          and (fn_active_home_id() is null or tl.home_id = fn_active_home_id())
    );
end $$;

-- ─────────────────── (c) reorder_task_lists ───────────────────

create or replace function reorder_task_lists(p_ids bigint[]) returns json
language plpgsql security definer set search_path = public as $$
declare
    v_me bigint := fn_my_user_id();
    v_home bigint;
    v_id bigint;
    v_role user_role;
    v_homes bigint[];
    v_result json;
begin
    if v_me is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    if p_ids is null or coalesce(array_length(p_ids, 1), 0) = 0
       or array_position(p_ids, null) is not null
       or (select count(distinct x) from unnest(p_ids) x) <> array_length(p_ids, 1) then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    -- Todas existen y son del mismo hogar
    select array_agg(distinct tl.home_id) into v_homes from task_list tl where tl.id = any(p_ids);
    if (select count(*) from task_list where id = any(p_ids)) <> array_length(p_ids, 1)
       or array_length(v_homes, 1) <> 1 then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    v_home := v_homes[1];
    perform fn_home_write_lock(v_home);
    -- Orden de bloqueo determinista (id asc) en ACL y filas de task_list: dos reordenaciones concurrentes
    -- con ids en orden opuesto no se cruzan (sin deadlock).
    foreach v_id in array (select array_agg(x order by x) from unnest(p_ids) x) loop
        select role into v_role from task_list_user where task_list_id = v_id and user_id = v_me for share;
        if v_role is null then
            raise exception 'Not Found' using errcode = 'P0002';
        end if;
        if not fn_task_list_editable(v_id) or not fn_has_permission(v_home, 'tasklist.manage') then
            raise exception 'Not Allowed' using errcode = '42501';
        end if;
    end loop;
    perform 1 from task_list where id = any(p_ids) order by id for update;
    update task_list tl set position = o.ord::integer
    from unnest(p_ids) with ordinality as o(id, ord)
    where tl.id = o.id;
    select coalesce(json_agg(json_build_object('id', o.id, 'position', o.ord::integer) order by o.ord), '[]'::json)
      into v_result
      from unnest(p_ids) with ordinality as o(id, ord);
    return v_result;
end $$;

revoke all on function reorder_task_lists(bigint[]) from public, anon;
grant execute on function reorder_task_lists(bigint[]) to authenticated;

commit;

notify pgrst, 'reload schema';
