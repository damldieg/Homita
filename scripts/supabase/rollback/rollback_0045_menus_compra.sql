-- rollback_0045_menus_compra.sql — Revierte 0045_menus_compra.sql (change menus-compra).
-- PIERDE DATOS: borra shopping_item (la Compra del hogar), las columnas recipe_ingredient.optional y
-- meal_plan.shopping_revision, y las filas client_request de los kinds 'shopping_item' y
-- 'meal_shopping_sync'. En prod, export SELECT-only y confirmación antes de ejecutar.
-- Restaura upsert_meal_plan_items y accept_meal_plan con el cuerpo de 0044 (sin la sincronización de la
-- compra ni el campo shopping_sync) y el check de client_request.kind a ('task', 'task_list').
-- Idempotente (if exists). La fila '0045' de schema_migrations no se borra aquí. No toca los permisos
-- menu.* ni borra las filas shopping.* de audit_log.
-- Orden LIFO: va ANTES que rollback_0044 (shopping_item referencia meal_plan y food).

begin;

-- Cuerpos de 0044 (los grants de 0044 se conservan con create or replace).
-- Las recetas se restauran antes de borrar la columna optional (fn_meal_recipe_json la lee).
create or replace function fn_meal_recipe_json(p_id bigint) returns json
language sql stable security definer set search_path = public as $$
    select json_build_object(
        'id', r.id, 'name', r.name, 'servings', r.servings, 'minutes', r.minutes, 'slots', r.slots,
        'steps', r.steps, 'created_by', r.created_by, 'updated_at', r.updated_at,
        'ingredients', (select coalesce(json_agg(json_build_object(
                'id', i.id, 'position', i.position, 'food_id', i.food_id, 'label', i.label,
                'quantity', i.quantity, 'unit', i.unit) order by i.position, i.id), '[]'::json)
            from recipe_ingredient i where i.recipe_id = r.id),
        'allergens', (select coalesce(json_agg(a order by a), '[]'::json) from (
                select distinct unnest(f.allergens) as a from recipe_ingredient i
                join food f on f.id = i.food_id where i.recipe_id = r.id) x))
    from recipe r where r.id = p_id
$$;

create or replace function fn_meal_recipe_set_ingredients(p_home bigint, p_recipe bigint, p_ing jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare
    v_e jsonb;
    v_pos integer := 0;
    v_food bigint;
    v_fname text;
    v_label text;
    v_qty numeric;
    v_unit text;
begin
    if p_ing is null or jsonb_typeof(p_ing) <> 'array' or jsonb_array_length(p_ing) > 60 then
        raise exception 'Invalid recipe' using errcode = 'P0001';
    end if;
    delete from recipe_ingredient where recipe_id = p_recipe;
    for v_e in select e from jsonb_array_elements(p_ing) e loop
        if jsonb_typeof(v_e) <> 'object' then
            raise exception 'Invalid recipe' using errcode = 'P0001';
        end if;
        v_food := null;
        v_fname := null;
        if coalesce(jsonb_typeof(v_e->'food_id'), 'null') not in ('null', 'number') then
            raise exception 'Invalid recipe' using errcode = 'P0001';
        end if;
        if jsonb_typeof(v_e->'food_id') = 'number' then
            if (v_e->>'food_id') !~ '^[0-9]{1,18}$' then
                raise exception 'Invalid recipe' using errcode = 'P0001';
            end if;
            -- alimento del catálogo común o del propio hogar; cualquier otro, misma respuesta
            select f.id, f.name into v_food, v_fname from food f
            where f.id = (v_e->>'food_id')::bigint and (f.home_id is null or f.home_id = p_home);
            if v_food is null then
                raise exception 'Invalid recipe' using errcode = 'P0001';
            end if;
        end if;
        if coalesce(jsonb_typeof(v_e->'label'), 'null') not in ('null', 'string')
           or coalesce(jsonb_typeof(v_e->'unit'), 'null') not in ('null', 'string')
           or coalesce(jsonb_typeof(v_e->'quantity'), 'null') not in ('null', 'number') then
            raise exception 'Invalid recipe' using errcode = 'P0001';
        end if;
        v_label := coalesce(nullif(btrim(v_e->>'label'), ''), v_fname);
        v_qty := (v_e->>'quantity')::numeric;
        v_unit := coalesce(v_e->>'unit', 'ud');
        insert into recipe_ingredient (recipe_id, home_id, position, food_id, label, quantity, unit)
        values (p_recipe, p_home, v_pos, v_food, v_label, v_qty, v_unit);
        v_pos := v_pos + 1;
    end loop;
end $$;

create or replace function upsert_meal_plan_items(p_week_start date, p_expected_revision integer,
    p_items jsonb default null, p_delete_ids bigint[] default null) returns json
language plpgsql security definer set search_path = public as $$
declare
    v_home bigint;
    v_plan meal_plan%rowtype;
    v_e jsonb;
    v_item bigint;
    v_old meal_plan_item%rowtype;
    v_day date;
    v_slot text;
    v_kind text;
    v_pos integer;
    v_recipe bigint;
    v_title text;
    v_serv integer;
    v_cook bigint;
    v_rname text;
    v_rserv integer;
    v_members bigint[];
    v_m jsonb;
    v_n integer := 0;
    v_del integer := 0;
    v_keys text[] := array['id', 'day', 'slot', 'position', 'kind', 'recipe_id', 'title', 'servings',
        'cook_member_id', 'members'];
begin
    if fn_my_user_id() is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    v_home := fn_home_for_root_create();
    perform fn_require_permission(v_home, 'menu.plan.manage');
    if p_week_start is null or p_expected_revision is null or p_expected_revision < 0
       or (p_items is not null and (jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) > 200))
       or coalesce(cardinality(p_delete_ids), 0) > 200 then
        raise exception 'Invalid meal plan' using errcode = 'P0001';
    end if;
    perform fn_home_write_lock(v_home);
    perform fn_meal_profile_ensure(v_home);
    if extract(isodow from p_week_start)::integer <> (select p.week_start_day from meal_profile p where p.home_id = v_home) then
        raise exception 'Invalid meal plan' using errcode = 'P0001';
    end if;
    select * into v_plan from meal_plan p
    where p.home_id = v_home and p.week_start = p_week_start and p.status <> 'archived' for update;
    if not found then
        if p_expected_revision <> 0 then
            raise exception 'Stale meal plan revision' using errcode = 'P0001';
        end if;
        begin
            insert into meal_plan (home_id, week_start, revision) values (v_home, p_week_start, 0)
            returning * into v_plan;
        exception when unique_violation then
            raise exception 'Stale meal plan revision' using errcode = 'P0001';
        end;
    elsif v_plan.revision <> p_expected_revision then
        raise exception 'Stale meal plan revision' using errcode = 'P0001';
    end if;

    begin
        if p_delete_ids is not null then
            delete from meal_plan_item where plan_id = v_plan.id and id = any (p_delete_ids);
            get diagnostics v_del = row_count;
        end if;
        for v_e in select e from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) e loop
            if jsonb_typeof(v_e) <> 'object' or exists (select 1 from jsonb_object_keys(v_e) k where k <> all (v_keys))
               or coalesce(jsonb_typeof(v_e->'day'), '') <> 'string'
               or coalesce(jsonb_typeof(v_e->'slot'), '') <> 'string'
               or coalesce(jsonb_typeof(v_e->'kind'), '') <> 'string'
               or coalesce(jsonb_typeof(v_e->'position'), 'number') <> 'number'
               or coalesce(jsonb_typeof(v_e->'recipe_id'), 'null') not in ('null', 'number')
               or coalesce(jsonb_typeof(v_e->'title'), 'null') not in ('null', 'string')
               or coalesce(jsonb_typeof(v_e->'servings'), 'null') not in ('null', 'number')
               or coalesce(jsonb_typeof(v_e->'cook_member_id'), 'null') not in ('null', 'number')
               or coalesce(jsonb_typeof(v_e->'id'), 'number') <> 'number'
               or (v_e ? 'members' and jsonb_typeof(v_e->'members') <> 'array') then
                raise exception 'Invalid meal plan' using errcode = 'P0001';
            end if;
            v_day := (v_e->>'day')::date;
            v_slot := v_e->>'slot';
            v_kind := v_e->>'kind';
            v_pos := coalesce((v_e->>'position')::integer, 0);
            v_recipe := (v_e->>'recipe_id')::bigint;
            v_title := btrim(coalesce(v_e->>'title', ''));
            v_serv := (v_e->>'servings')::integer;
            v_cook := (v_e->>'cook_member_id')::bigint;
            if v_day < p_week_start or v_day > p_week_start + 6
               or v_kind <> all (array['recipe', 'free_text', 'leftovers', 'eat_out']) then
                raise exception 'Invalid meal plan' using errcode = 'P0001';
            end if;
            -- casilla existente del propio plan (otra o de otro hogar: misma respuesta)
            v_item := null;
            if v_e ? 'id' then
                select * into v_old from meal_plan_item i
                where i.id = (v_e->>'id')::bigint and i.plan_id = v_plan.id;
                if not found then
                    raise exception 'Invalid meal plan' using errcode = 'P0001';
                end if;
                v_item := v_old.id;
            end if;
            if v_kind = 'recipe' then
                if v_recipe is not null then
                    select r.name, r.servings into v_rname, v_rserv from recipe r
                    where r.id = v_recipe and r.home_id = v_home;
                    if not found then
                        raise exception 'Invalid meal plan' using errcode = 'P0001';
                    end if;
                    v_title := v_rname;
                    v_serv := coalesce(v_serv, v_rserv);
                elsif v_item is not null and v_old.kind = 'recipe' and v_old.recipe_id is null then
                    -- receta borrada: la casilla conserva su título
                    v_title := coalesce(nullif(v_title, ''), v_old.title);
                else
                    raise exception 'Invalid meal plan' using errcode = 'P0001';
                end if;
            elsif v_recipe is not null or (v_kind = 'free_text' and v_title = '') then
                raise exception 'Invalid meal plan' using errcode = 'P0001';
            end if;
            if v_cook is not null and not exists (
                    select 1 from home_member hm where hm.id = v_cook and hm.home_id = v_home and hm.kind <> 'pet') then
                raise exception 'Invalid meal plan' using errcode = 'P0001';
            end if;
            -- comensales
            v_members := null;
            if v_e ? 'members' then
                v_members := array[]::bigint[];
                for v_m in select m from jsonb_array_elements(v_e->'members') m loop
                    if jsonb_typeof(v_m) <> 'number' or (v_m #>> '{}') !~ '^[0-9]{1,18}$' then
                        raise exception 'Invalid meal plan' using errcode = 'P0001';
                    end if;
                    v_members := v_members || (v_m #>> '{}')::bigint;
                end loop;
                if exists (select 1 from unnest(v_members) x
                           where not exists (select 1 from home_member hm
                                             where hm.id = x and hm.home_id = v_home and hm.kind <> 'pet')) then
                    raise exception 'Invalid meal plan' using errcode = 'P0001';
                end if;
            elsif v_item is null then
                select coalesce(array_agg(pm.home_member_id order by pm.home_member_id), array[]::bigint[])
                into v_members from meal_profile_member pm
                where pm.home_id = v_home
                  and not exists (select 1 from meal_schedule s
                                  where s.home_member_id = pm.home_member_id
                                    and s.weekday = extract(isodow from v_day)::integer
                                    and s.slot = v_slot and s.status <> 'home');
            end if;
            if v_item is null then
                insert into meal_plan_item (plan_id, home_id, day, slot, position, kind, recipe_id, title, servings, cook_member_id)
                values (v_plan.id, v_home, v_day, v_slot, v_pos, v_kind, v_recipe, v_title, v_serv, v_cook)
                returning id into v_item;
            else
                update meal_plan_item i set day = v_day, slot = v_slot, position = v_pos, kind = v_kind,
                    recipe_id = v_recipe, title = v_title, servings = v_serv, cook_member_id = v_cook
                where i.id = v_item;
            end if;
            if v_members is not null then
                delete from meal_plan_item_member where item_id = v_item;
                insert into meal_plan_item_member (item_id, home_id, member_id)
                select v_item, v_home, x from (select distinct unnest(v_members) as x) d;
            end if;
            v_n := v_n + 1;
        end loop;
        -- la unicidad (plan, día, franja, posición) se difiere para permitir intercambios dentro de la llamada
        set constraints meal_plan_item_pos_uq immediate;
        set constraints meal_plan_item_pos_uq deferred;
    exception when check_violation or not_null_violation or unique_violation or foreign_key_violation
        or invalid_text_representation or numeric_value_out_of_range or invalid_parameter_value
        or datatype_mismatch or invalid_datetime_format or datetime_field_overflow then
        raise exception 'Invalid meal plan' using errcode = 'P0001';
    end;

    update meal_plan p set status = 'draft', accepted_at = null, accepted_by = null,
        revision = p.revision + 1, updated_at = (now() at time zone 'UTC')
    where p.id = v_plan.id;
    insert into audit_log (home_id, actor_app_user_id, action, target_type, target_id, payload)
    values (v_home, fn_my_user_id(), 'meal.plan.update', 'meal_plan', v_plan.id,
            jsonb_build_object('week_start', p_week_start, 'items', v_n, 'deleted', v_del));
    return fn_meal_plan_json(v_plan.id);
end $$;


create or replace function accept_meal_plan(p_plan_id bigint, p_expected_revision integer) returns json
language plpgsql security definer set search_path = public as $$
declare
    v_home bigint;
    v_plan meal_plan%rowtype;
begin
    if fn_my_user_id() is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    v_home := fn_home_for_root_create();
    perform fn_require_permission(v_home, 'menu.plan.manage');
    perform fn_home_write_lock(v_home);
    select * into v_plan from meal_plan p where p.id = p_plan_id and p.home_id = v_home for update;
    if not found then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    -- R1-02: la revisión va antes que el estado, así una segunda aceptación concurrente (el plan ya
    -- está accepted y con otra revisión) recibe 'Stale meal plan revision' (409) y no 'Invalid meal plan'.
    if p_expected_revision is distinct from v_plan.revision then
        raise exception 'Stale meal plan revision' using errcode = 'P0001';
    end if;
    if v_plan.status <> 'draft' then
        raise exception 'Invalid meal plan' using errcode = 'P0001';
    end if;
    if not exists (select 1 from meal_plan_item i where i.plan_id = v_plan.id) then
        raise exception 'Invalid meal plan' using errcode = 'P0001';
    end if;
    update meal_plan p set status = 'accepted', accepted_at = (now() at time zone 'UTC'),
        accepted_by = fn_my_user_id(), revision = p.revision + 1, updated_at = (now() at time zone 'UTC')
    where p.id = v_plan.id;
    insert into audit_log (home_id, actor_app_user_id, action, target_type, target_id, payload)
    values (v_home, fn_my_user_id(), 'meal.plan.accept', 'meal_plan', v_plan.id,
            jsonb_build_object('week_start', v_plan.week_start));
    return fn_meal_plan_json(v_plan.id);
end $$;


drop function if exists sync_meal_shopping(bigint, uuid);
drop function if exists fn_meal_shopping_sync(bigint, bigint);
drop function if exists preview_meal_shopping(bigint);
drop function if exists list_shopping();
drop function if exists create_shopping_item(text, numeric, text, text, bigint, uuid);
drop function if exists set_shopping_item_state(bigint, text);
drop function if exists update_shopping_item_qty(bigint, numeric, text);
drop function if exists delete_shopping_item(bigint);
drop function if exists clear_checked_shopping();
drop function if exists fn_shopping_item_json(bigint);
drop function if exists fn_meal_shopping_calc(bigint);
drop function if exists fn_meal_shopping_round(numeric, text);
drop function if exists fn_meal_pantry_basic_names();

drop table if exists shopping_item;

alter table meal_plan drop column if exists shopping_revision;
alter table recipe_ingredient drop column if exists optional;

do $$
declare
    v_c text;
begin
    if to_regclass('public.client_request') is not null then
        delete from client_request where kind in ('shopping_item', 'meal_shopping_sync');
        alter table client_request drop column if exists result;
        for v_c in select c.conname from pg_constraint c
                   where c.conrelid = 'public.client_request'::regclass and c.contype = 'c'
                     and pg_get_constraintdef(c.oid) like '%kind%' loop
            execute format('alter table client_request drop constraint %I', v_c);
        end loop;
        alter table client_request add constraint client_request_kind_check check (kind in ('task', 'task_list'));
    end if;
end $$;

commit;
