-- rollback_0043_meal_profile.sql — Revierte 0043_meal_profile.sql (change menus-perfil-hogar).
-- PIERDE DATOS: borra meal_profile, meal_profile_member (alergias incluidas), meal_schedule y
-- meal_slot_setting. Fase sin uso previo; en prod, export SELECT-only y confirmación antes de ejecutar.
-- Idempotente (if exists / delete sin filas). Orden: RPC, tablas (con sus triggers) (con sus policies), helpers,
-- membership_permission menu.%, member_kind_default menu.% y permission menu.% (FK de 0012).
-- audit_log conserva las filas meal.* (histórico del hogar). La fila '0043' de schema_migrations no se
-- borra aquí.

begin;

drop function if exists get_meal_profile();
drop function if exists update_meal_profile(jsonb);
drop function if exists update_meal_profile_member(bigint, jsonb);
drop function if exists set_meal_schedule(jsonb);
drop function if exists set_meal_slot_settings(jsonb);

-- los triggers meal_*_guard caen con sus tablas
drop table if exists meal_schedule;
drop table if exists meal_profile_member;
drop table if exists meal_slot_setting;
drop table if exists meal_profile;

drop function if exists fn_meal_profile_ensure(bigint);
drop function if exists fn_meal_member_guard();
drop function if exists fn_meal_allergies_valid(jsonb);
drop function if exists fn_meal_jsonb_to_text_array(jsonb);

delete from membership_permission where permission_code like 'menu.%';
delete from member_kind_default where permission_code like 'menu.%';
delete from permission where code like 'menu.%';

commit;
