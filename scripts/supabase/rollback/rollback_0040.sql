-- rollback_0040.sql — Revierte 0040_task_list_position.sql (change lista-prioritaria-inicio).
-- Orden en prod: primero la Edge anterior (sin la ruta PATCH /task-list/order) y, antes de ejecutar esto,
-- export SELECT-only de (id, home_id, position) y confirmación del usuario: se pierde el orden elegido.
-- Restaura get_task_lists() con el cuerpo literal de 0029_acl_can_edit.sql. Idempotente (dos pasadas).
-- supabase_migrations.schema_migrations: la fila '0040' no se borra aquí.

begin;

drop function if exists reorder_task_lists(bigint[]);

-- get_task_lists: cuerpo de 0029_acl_can_edit.sql (sin position, orden por nombre).
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
            'can_edit', coalesce(tlu.role = 'owner' or tlu.can_edit, false)
        ) order by tl.name collate "C"), '[]'::json)
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

alter table task_list drop constraint if exists task_list_position_check;
alter table task_list drop column if exists position;

commit;

notify pgrst, 'reload schema';
