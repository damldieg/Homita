-- rollback_0055_compra_pantalla.sql — revierte 0055: vuelve a set_shopping_item_state de 0045 (sin cliente ni
-- permiso de pantalla), a fn_display_link_complete de 0050 y a los kinds de client_request de 0050, y quita
-- menu.shopping.check de las membresías y del catálogo. Idempotente. La fila '0055' de schema_migrations no se borra aquí.

begin;

-- Las filas de idempotencia del nuevo kind se borran antes de restaurar la restricción
delete from client_request where kind = 'shopping_check';
alter table client_request drop constraint if exists client_request_kind_check;
alter table client_request add constraint client_request_kind_check
    check (kind in ('task', 'task_list', 'shopping_item', 'meal_shopping_sync', 'meal_plan', 'recipe', 'task_complete'));

drop function if exists set_shopping_item_state(bigint, text, uuid);
create or replace function set_shopping_item_state(p_item_id bigint, p_state text) returns json
language plpgsql security definer set search_path = public as $$
declare
    v_me bigint := fn_my_user_id();
    v_home bigint;
    v_item shopping_item%rowtype;
begin
    if v_me is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    v_home := fn_home_for_root_create();
    perform fn_require_permission(v_home, 'menu.shopping.edit');
    perform fn_home_write_lock(v_home);
    select * into v_item from shopping_item s where s.id = p_item_id and s.home_id = v_home for update;
    if not found then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    if p_state is null or p_state <> all (array['pending', 'checked', 'skipped']) then
        raise exception 'Invalid shopping item' using errcode = 'P0001';
    end if;
    -- Un artículo oculto (cleared) no reaparece por un cambio de estado (p. ej. el replay de una cola offline).
    if v_item.cleared then
        return fn_shopping_item_json(v_item.id);
    end if;
    update shopping_item s set state = p_state,
        checked_at = case when p_state = 'pending' then null else (now() at time zone 'UTC') end,
        checked_by = case when p_state = 'pending' then null else v_me end,
        updated_at = (now() at time zone 'UTC')
    where s.id = v_item.id;
    return fn_shopping_item_json(v_item.id);
end $$;

revoke execute on function set_shopping_item_state(bigint, text) from public, anon;
grant execute on function set_shopping_item_state(bigint, text) to authenticated;

-- Vinculación de 0050 (sin menu.shopping.check)
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
    insert into membership_permission (home_membership_id, permission_code)
    values (v_membership, 'calendar.view'), (v_membership, 'task.view'), (v_membership, 'menu.view'),
           (v_membership, 'task.complete');

    insert into home_display (home_id, app_user_id, home_member_id, name, linked_by)
    values (v_link.home_id, v_app_user, v_member, v_link.display_name, v_link.claimed_by)
    returning id into v_display;
    update app_user set default_home_id = v_link.home_id where id = v_app_user and default_home_id is null;

    update home_display_link set display_id = v_display, session = p_session where id = p_link_id;
    return json_build_object('display_id', v_display);
end
$$;

delete from membership_permission where permission_code = 'menu.shopping.check';
delete from permission where code = 'menu.shopping.check';

commit;
