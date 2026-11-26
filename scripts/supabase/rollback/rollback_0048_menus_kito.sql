-- rollback_0048_menus_kito.sql — Revierte 0048_menus_kito.sql (change kito-menus).
-- PIERDE DATOS: borra meal_plan.origin, recipe.origin, meal_plan_item.state y las filas client_request de
-- los kinds 'meal_plan' y 'recipe'. En prod, export SELECT-only y confirmación antes de ejecutar.
-- Restaura fn_meal_recipe_json con el cuerpo de 0047 (home_id y country), upsert_meal_plan_items con el de 0045, create_recipe y
-- fn_meal_plan_json con el de 0044, y el check de client_request.kind al de 0045.
-- Idempotente (if exists). La fila '0048' de schema_migrations no se borra aquí.
-- Orden LIFO: va ANTES que rollback_0047, rollback_0046 y rollback_0045.

begin;

drop function if exists upsert_meal_plan_items(date, integer, jsonb, bigint[], uuid, text);
drop function if exists create_recipe(text, integer, integer, jsonb, jsonb, jsonb, uuid, text);

create or replace function fn_meal_plan_json(p_id bigint) returns json
language sql stable security definer set search_path = public as $$
    select json_build_object(
        'id', p.id, 'week_start', p.week_start, 'status', p.status, 'revision', p.revision,
        'accepted_at', p.accepted_at, 'accepted_by', p.accepted_by, 'updated_at', p.updated_at,
        'items', (select coalesce(json_agg(json_build_object(
                'id', i.id, 'day', i.day, 'slot', i.slot, 'position', i.position, 'kind', i.kind,
                'recipe_id', i.recipe_id, 'title', i.title, 'servings', i.servings,
                'cook_member_id', i.cook_member_id,
                'members', (select coalesce(json_agg(m.member_id order by m.member_id), '[]'::json)
                            from meal_plan_item_member m where m.item_id = i.id))
                order by i.day, array_position(array['breakfast', 'midmorning', 'lunch', 'snack', 'dinner'], i.slot),
                         i.position, i.id), '[]'::json)
            from meal_plan_item i where i.plan_id = p.id),
        -- casillas que check_meal_plan no puede evaluar (R1-05): texto libre, sobras, receta borrada,
        -- sin ingredientes o con alguno sin food_id. «Sin avisos» solo vale para las demás.
        'unchecked_item_ids', (select coalesce(json_agg(i.id order by i.id), '[]'::json)
            from meal_plan_item i
            where i.plan_id = p.id
              and (i.kind in ('free_text', 'leftovers')
                   or (i.kind = 'recipe'
                       and (i.recipe_id is null
                            or not exists (select 1 from recipe_ingredient g where g.recipe_id = i.recipe_id)
                            or exists (select 1 from recipe_ingredient g where g.recipe_id = i.recipe_id and g.food_id is null))))))
    from meal_plan p where p.id = p_id
$$;

create or replace function fn_meal_recipe_json(p_id bigint) returns json
language sql stable security definer set search_path = public as $$
    select json_build_object(
        'id', r.id, 'home_id', r.home_id, 'country', r.country,
        'name', r.name, 'servings', r.servings, 'minutes', r.minutes, 'slots', r.slots,
        'steps', r.steps, 'created_by', r.created_by, 'updated_at', r.updated_at,
        'ingredients', (select coalesce(json_agg(json_build_object(
                'id', i.id, 'position', i.position, 'food_id', i.food_id, 'label', i.label,
                'quantity', i.quantity, 'unit', i.unit, 'optional', i.optional) order by i.position, i.id), '[]'::json)
            from recipe_ingredient i where i.recipe_id = r.id),
        'allergens', (select coalesce(json_agg(a order by a), '[]'::json) from (
                select distinct unnest(f.allergens) as a from recipe_ingredient i
                join food f on f.id = i.food_id where i.recipe_id = r.id) x))
    from recipe r where r.id = p_id
$$;

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
    -- 0045 (decisión 3): si el plan estaba aceptado antes de la edición, la compra refleja el último menú
    -- aunque el plan vuelva a draft; un plan que no estaba aceptado no genera compra.
    if v_plan.status = 'accepted' or (v_plan.status = 'draft' and exists (
            select 1 from shopping_item s where s.plan_id = v_plan.id and s.origin = 'menu')) then
        perform fn_meal_shopping_sync(v_home, v_plan.id);
    end if;
    return fn_meal_plan_json(v_plan.id);
end $$;

create or replace function create_recipe(p_name text, p_servings integer default 2, p_minutes integer default null,
    p_slots jsonb default null, p_steps jsonb default null, p_ingredients jsonb default null) returns json
language plpgsql security definer set search_path = public as $$
declare
    v_home bigint;
    v_id bigint;
begin
    if fn_my_user_id() is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    v_home := fn_home_for_root_create();
    perform fn_require_permission(v_home, 'menu.plan.manage');
    if p_name is null or (p_slots is not null and jsonb_typeof(p_slots) <> 'array')
       or (p_steps is not null and jsonb_typeof(p_steps) <> 'array') then
        raise exception 'Invalid recipe' using errcode = 'P0001';
    end if;
    perform fn_home_write_lock(v_home);
    begin
        insert into recipe (home_id, name, servings, minutes, slots, steps, created_by)
        values (v_home, btrim(p_name), coalesce(p_servings, 2), p_minutes,
                case when p_slots is null then array[]::text[] else fn_meal_jsonb_to_text_array(p_slots) end,
                case when p_steps is null then null else fn_meal_jsonb_to_text_array(p_steps) end,
                fn_my_user_id())
        returning id into v_id;
        perform fn_meal_recipe_set_ingredients(v_home, v_id, coalesce(p_ingredients, '[]'::jsonb));
    exception when check_violation or not_null_violation or unique_violation or invalid_text_representation
        or numeric_value_out_of_range or invalid_parameter_value or datatype_mismatch then
        raise exception 'Invalid recipe' using errcode = 'P0001';
    end;
    insert into audit_log (home_id, actor_app_user_id, action, target_type, target_id, payload)
    values (v_home, fn_my_user_id(), 'meal.recipe.create', 'recipe', v_id, '{}'::jsonb);
    return fn_meal_recipe_json(v_id);
end $$;

revoke all on function upsert_meal_plan_items(date, integer, jsonb, bigint[]),
    create_recipe(text, integer, integer, jsonb, jsonb, jsonb) from public, anon;
grant execute on function upsert_meal_plan_items(date, integer, jsonb, bigint[]),
    create_recipe(text, integer, integer, jsonb, jsonb, jsonb) to authenticated;

delete from client_request where kind in ('meal_plan', 'recipe');
alter table client_request drop constraint if exists client_request_kind_check;
alter table client_request add constraint client_request_kind_check
    check (kind in ('task', 'task_list', 'shopping_item', 'meal_shopping_sync'));

alter table meal_plan_item drop column if exists state;
alter table recipe drop column if exists origin;
alter table meal_plan drop column if exists origin;

commit;
