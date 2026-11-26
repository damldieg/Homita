-- 0047_menus_recetas_precargadas.sql — change menus-recetas-precargadas: recetas comunes (home_id nulo)
-- por país, de solo lectura para los hogares. Una sola transacción, aditiva sobre 0044/0045.
-- Nada toca 0001–0046 ni los permisos (28 / 47 como antes).
--
-- * recipe.country: código ISO de dos letras en mayúsculas, nulo en las recetas del hogar. recipe.home_id
--   y recipe_ingredient.home_id pasan a admitir nulo: una receta común no tiene hogar. Las recetas
--   comunes exigen país (check) y son únicas por (name, country) (índice parcial, base del seed idempotente
--   supabase/seed/recetas_precargadas.sql, que NO va en esta migración).
-- * RLS: recipe y recipe_ingredient se leen también con home_id nulo (cualquier usuario autenticado, como
--   el catálogo común de food). Sin policies ni grants de escritura: solo escribe el rol de servicio (seed).
-- * list_recipes y get_recipe devuelven también las recetas comunes; fn_meal_recipe_json añade `home_id` y
--   `country`. update_recipe, delete_recipe y la planificación siguen exigiendo una receta del hogar:
--   una receta común responde Not Found / Invalid (no se edita ni se borra).
--
-- Rollback: scripts/supabase/rollback/rollback_0047_menus_recetas_precargadas.sql (borra las recetas comunes).

begin;

alter table recipe add column country text check (country ~ '^[A-Z]{2}$');
alter table recipe alter column home_id drop not null;
alter table recipe add constraint recipe_common_country_ck check (home_id is not null or country is not null);
alter table recipe_ingredient alter column home_id drop not null;
create unique index recipe_common_name_country_uq on recipe (name, country) where home_id is null;

drop policy recipe_select on recipe;
create policy recipe_select on recipe for select to authenticated
    using (home_id is null
           or (home_id = any (fn_my_home_ids()) and fn_has_permission(home_id, 'menu.view')));
drop policy recipe_ingredient_select on recipe_ingredient;
create policy recipe_ingredient_select on recipe_ingredient for select to authenticated
    using (home_id is null
           or (home_id = any (fn_my_home_ids()) and fn_has_permission(home_id, 'menu.view')));

-- Cuerpo de 0045 (con `optional`) más `home_id` y `country`. Los grants (solo internas) se conservan.
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

-- p_slot: recetas sugeridas para esa franja o sin franja indicada. p_max_minutes: solo las que
-- declaran un tiempo <= p_max_minutes. Incluye las del hogar y las comunes (home_id nulo).
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
            'id', r.id, 'home_id', r.home_id, 'country', r.country,
            'name', r.name, 'servings', r.servings, 'minutes', r.minutes, 'slots', r.slots)
            order by fn_meal_norm(r.name), r.id), '[]'::json)
        from recipe r
        where (r.home_id = v_home or r.home_id is null)
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
    if not exists (select 1 from recipe where id = p_id and (home_id = v_home or home_id is null)) then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    return fn_meal_recipe_json(p_id);
end $$;

commit;
