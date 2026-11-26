-- rollback_0047_menus_recetas_precargadas.sql — Revierte 0047_menus_recetas_precargadas.sql (change
-- menus-recetas-precargadas).
-- PIERDE DATOS: borra las recetas comunes (home_id nulo) y sus ingredientes, y la columna recipe.country.
-- Las recetas de los hogares no se tocan. El seed supabase/seed/recetas_precargadas.sql se recarga tras
-- reaplicar 0047. En prod, export SELECT-only y confirmación antes de ejecutar.
-- Restaura fn_meal_recipe_json (0045), list_recipes y get_recipe (0044), las policies de 0044 y los NOT NULL.
-- Idempotente (if exists). La fila '0047' de schema_migrations no se borra aquí.
-- Orden LIFO: va ANTES que rollback_0045 y rollback_0044 (el cuerpo de fn_meal_recipe_json lee `optional`).

begin;

delete from recipe_ingredient where home_id is null;
delete from recipe where home_id is null;

create or replace function fn_meal_recipe_json(p_id bigint) returns json
language sql stable security definer set search_path = public as $$
    select json_build_object(
        'id', r.id, 'name', r.name, 'servings', r.servings, 'minutes', r.minutes, 'slots', r.slots,
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

create or replace function list_recipes(p_q text default null, p_slot text default null,
    p_max_minutes integer default null) returns json
language plpgsql security definer set search_path = public as $$
declare
    v_home bigint;
    v_q text := fn_meal_norm(coalesce(p_q, ''));
begin
    if fn_my_user_id() is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    v_home := fn_home_for_root_create();
    perform fn_require_permission(v_home, 'menu.view');
    if p_slot is not null and p_slot <> all (array['breakfast', 'midmorning', 'lunch', 'snack', 'dinner']) then
        raise exception 'Invalid recipe' using errcode = 'P0001';
    end if;
    return (select coalesce(json_agg(json_build_object(
            'id', r.id, 'name', r.name, 'servings', r.servings, 'minutes', r.minutes, 'slots', r.slots)
            order by fn_meal_norm(r.name), r.id), '[]'::json)
        from recipe r
        where r.home_id = v_home
          and (v_q = '' or position(v_q in fn_meal_norm(r.name)) > 0)
          and (p_slot is null or cardinality(r.slots) = 0 or p_slot = any (r.slots))
          and (p_max_minutes is null or r.minutes <= p_max_minutes));
end $$;

create or replace function get_recipe(p_id bigint) returns json
language plpgsql security definer set search_path = public as $$
declare
    v_home bigint;
begin
    if fn_my_user_id() is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    v_home := fn_home_for_root_create();
    perform fn_require_permission(v_home, 'menu.view');
    if not exists (select 1 from recipe where id = p_id and home_id = v_home) then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    return fn_meal_recipe_json(p_id);
end $$;

drop policy if exists recipe_select on recipe;
create policy recipe_select on recipe for select to authenticated
    using (home_id = any (fn_my_home_ids()) and fn_has_permission(home_id, 'menu.view'));
drop policy if exists recipe_ingredient_select on recipe_ingredient;
create policy recipe_ingredient_select on recipe_ingredient for select to authenticated
    using (home_id = any (fn_my_home_ids()) and fn_has_permission(home_id, 'menu.view'));

drop index if exists recipe_common_name_country_uq;
alter table recipe drop constraint if exists recipe_common_country_ck;
alter table recipe alter column home_id set not null;
alter table recipe_ingredient alter column home_id set not null;
alter table recipe drop column if exists country;

commit;
