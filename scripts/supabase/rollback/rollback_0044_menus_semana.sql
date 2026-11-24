-- rollback_0044_menus_semana.sql — Revierte 0044_menus_semana.sql (change menus-semana).
-- PIERDE DATOS: borra food (catálogo común y alimentos propios), recipe, recipe_ingredient, meal_plan,
-- meal_plan_item y meal_plan_item_member. En prod, export SELECT-only y confirmación antes de ejecutar.
-- El catálogo común sale de supabase/seed/food_es.sql: se recarga tras reaplicar 0044.
-- Idempotente (if exists). Orden: RPC, tablas hijas antes que las padres (con sus triggers, índices y
-- policies), helpers. No toca los permisos menu.* (son de 0043) ni borra las filas meal.* de audit_log.
-- La fila '0044' de schema_migrations no se borra aquí.
-- Orden LIFO: va ANTES que rollback_0043 (esta migración usa meal_profile, meal_schedule y home_member).

begin;

drop trigger if exists meal_profile_week_guard on meal_profile;
drop function if exists fn_meal_profile_week_guard();

drop function if exists search_food(text, integer);
drop function if exists create_food(text, text, jsonb, text, numeric);
drop function if exists update_food(bigint, jsonb);
drop function if exists delete_food(bigint);
drop function if exists list_recipes(text, text, integer);
drop function if exists get_recipe(bigint);
drop function if exists create_recipe(text, integer, integer, jsonb, jsonb, jsonb);
drop function if exists update_recipe(bigint, jsonb);
drop function if exists delete_recipe(bigint);
drop function if exists get_meal_plan(date);
drop function if exists upsert_meal_plan_items(date, integer, jsonb, bigint[]);
drop function if exists accept_meal_plan(bigint, integer);
drop function if exists archive_meal_plan(bigint);
drop function if exists copy_meal_plan_week(date, date);
drop function if exists check_meal_plan(bigint);
drop function if exists get_meals_today(date);

drop table if exists meal_plan_item_member;
drop table if exists meal_plan_item;
drop table if exists meal_plan;
drop table if exists recipe_ingredient;
drop table if exists recipe;
drop table if exists food;

drop function if exists fn_meal_food_json(bigint);
drop function if exists fn_meal_recipe_json(bigint);
drop function if exists fn_meal_recipe_set_ingredients(bigint, bigint, jsonb);
drop function if exists fn_meal_plan_json(bigint);
drop function if exists fn_meal_week_of(bigint, date);
drop function if exists fn_meal_food_before();
drop function if exists fn_meal_food_allergens_valid(text[]);
drop function if exists fn_meal_norm(text);

commit;
