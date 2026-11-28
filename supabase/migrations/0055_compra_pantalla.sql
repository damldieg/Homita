-- 0055_compra_pantalla.sql — La pantalla marca la compra del menú (dashboard-menu-compra, fase B).
-- Decisión de Damian (28-11): la Compra de la pared marca artículos como comprados, solo marcar y desmarcar.
-- * Permiso nuevo `menu.shopping.check`: pending ↔ checked. No crea, no edita cantidades, no borra y no pone
--   `skipped` («ya lo tengo» sigue exigiendo menu.shopping.edit).
-- * set_shopping_item_state gana p_client_request_id (idempotencia del reenvío sin red, kind 'shopping_check') y
--   registra en audit_log con source 'display' cuando lo hace una pantalla.
-- * Las pantallas vinculadas (0049/0050) ganan menu.shopping.check; las ya vinculadas, por backfill.
-- Rollback: scripts/supabase/rollback/rollback_0055_compra_pantalla.sql.

insert into permission (code, domain, description) values
    ('menu.shopping.check', 'menu', 'Marcar o desmarcar artículos de la compra (sin crear, editar, borrar ni saltar)')
on conflict (code) do nothing;

-- Pantallas: membresía con la marca de compra (el resto de permisos de display no cambia).
insert into membership_permission (home_membership_id, permission_code)
select hm.id, 'menu.shopping.check'
from home_display d
join home_membership hm on hm.home_id = d.home_id and hm.app_user_id = d.app_user_id
where d.revoked_at is null
on conflict do nothing;

alter table client_request drop constraint if exists client_request_kind_check;
alter table client_request add constraint client_request_kind_check
    check (kind in ('task', 'task_list', 'shopping_item', 'meal_shopping_sync', 'meal_plan', 'recipe', 'task_complete', 'shopping_check'));

-- Vinculación de pantallas nuevas: lectura, completar tareas y marcar la compra (0050 + menu.shopping.check).
create or replace function fn_display_link_complete(p_link_id bigint, p_auth_uid uuid, p_session jsonb) returns json
language plpgsql security definer set search_path = public as $$
declare
    v_link home_display_link;
    v_app_user bigint;
    v_membership bigint;
    v_member bigint;
    v_display bigint;
begin
    select * into v_link from home_display_link where id = p_link_id for update;
    if not found or v_link.claimed_at is null or v_link.display_id is not null then
        raise exception 'Not Found';
    end if;
    select id into v_app_user from app_user where auth_uid = p_auth_uid;
    if v_app_user is null then raise exception 'Not Found'; end if;

    insert into home_membership (home_id, app_user_id, role)
    values (v_link.home_id, v_app_user, 'member')
    returning id into v_membership;
    insert into home_member (home_id, kind, name, app_user_id)
    values (v_link.home_id, 'display', v_link.display_name, v_app_user)
    returning id into v_member;
    -- Solo lectura, completar tareas y marcar la compra (0055): nada de crear, editar ni borrar.
    insert into membership_permission (home_membership_id, permission_code)
    values (v_membership, 'calendar.view'), (v_membership, 'task.view'), (v_membership, 'menu.view'),
           (v_membership, 'task.complete'), (v_membership, 'menu.shopping.check');

    insert into home_display (home_id, app_user_id, home_member_id, name, linked_by)
    values (v_link.home_id, v_app_user, v_member, v_link.display_name, v_link.claimed_by)
    returning id into v_display;
    -- Hogar por defecto de la cuenta: las lecturas de la pantalla (menú de hoy) sin cabecera lo usan
    update app_user set default_home_id = v_link.home_id where id = v_app_user and default_home_id is null;

    update home_display_link set display_id = v_display, session = p_session where id = p_link_id;
    return json_build_object('display_id', v_display);
end
$$;

-- Marcar (checked), desmarcar (pending) o «ya lo tengo» (skipped). Idempotente con p_client_request_id.
-- La pantalla solo puede pending ↔ checked, en su propio hogar.
drop function if exists set_shopping_item_state(bigint, text);
create or replace function set_shopping_item_state(p_item_id bigint, p_state text, p_client_request_id uuid default null)
returns json
language plpgsql security definer set search_path = public as $$
declare
    v_me bigint := fn_my_user_id();
    v_home bigint;
    v_item shopping_item%rowtype;
    v_display boolean;
    v_kind text;
    v_id bigint;
begin
    if v_me is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    v_home := fn_home_for_root_create();
    if p_state is null or p_state <> all (array['pending', 'checked', 'skipped']) then
        raise exception 'Invalid shopping item' using errcode = 'P0001';
    end if;
    -- «ya lo tengo» exige edición; marcar o desmarcar basta con menu.shopping.check (las pantallas).
    if p_state = 'skipped' or not fn_has_permission(v_home, 'menu.shopping.edit') then
        if p_state = 'skipped' then
            perform fn_require_permission(v_home, 'menu.shopping.edit');
        else
            perform fn_require_permission(v_home, 'menu.shopping.check');
        end if;
    end if;
    perform fn_home_write_lock(v_home);
    select * into v_item from shopping_item s where s.id = p_item_id and s.home_id = v_home for update;
    if not found then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    -- Un artículo oculto (cleared) no reaparece por un cambio de estado (replay de una cola offline).
    if v_item.cleared then
        return fn_shopping_item_json(v_item.id);
    end if;
    v_display := exists (select 1 from home_display d
                         where d.app_user_id = v_me and d.home_id = v_home and d.revoked_at is null);
    -- Idempotencia (0055): una clave ya usada para este artículo no vuelve a cambiar nada.
    if p_client_request_id is not null then
        perform pg_advisory_xact_lock(hashtextextended('client_request:' || v_me || ':' || p_client_request_id::text, 0));
        select cr.kind, cr.resource_id into v_kind, v_id from client_request cr
        where cr.app_user_id = v_me and cr.client_request_id = p_client_request_id;
        if v_kind is not null then
            if v_kind <> 'shopping_check' or v_id <> p_item_id then
                raise exception 'Invalid client_request_id' using errcode = 'P0001';
            end if;
            return fn_shopping_item_json(p_item_id);
        end if;
    end if;
    update shopping_item s set state = p_state,
        checked_at = case when p_state = 'pending' then null else (now() at time zone 'UTC') end,
        checked_by = case when p_state = 'pending' then null else v_me end,
        updated_at = (now() at time zone 'UTC')
    where s.id = v_item.id;
    if p_client_request_id is not null then
        insert into client_request (app_user_id, client_request_id, kind, resource_id)
        values (v_me, p_client_request_id, 'shopping_check', p_item_id);
    end if;
    if v_display then
        insert into audit_log (home_id, actor_app_user_id, action, target_type, target_id, payload)
        values (v_home, v_me, case when p_state = 'checked' then 'shopping.check' else 'shopping.uncheck' end,
                'shopping_item', p_item_id, jsonb_build_object('source', 'display', 'state', p_state));
    end if;
    return fn_shopping_item_json(v_item.id);
end
$$;

revoke execute on function set_shopping_item_state(bigint, text, uuid) from public, anon;
grant execute on function set_shopping_item_state(bigint, text, uuid) to authenticated;
