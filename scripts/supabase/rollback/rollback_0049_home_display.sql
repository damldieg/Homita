-- rollback_0049_home_display.sql — Revierte 0049_home_display.sql (change dashboard-pantalla-hogar).
-- PIERDE DATOS: borra las pantallas del hogar (home_display y su selección), las vinculaciones pendientes y los
-- intentos, la membresía y el home_member de cada pantalla (kind 'display') y el permiso display.manage.
-- En prod, export SELECT-only y confirmación antes de ejecutar.
-- No quita el valor 'display' de member_kind: PostgreSQL no permite quitar valores de un enum. Tras el rollback no
-- queda ninguna fila con ese kind (las pantallas se borran antes).
-- Idempotente (if exists). La fila '0049' de schema_migrations no se borra aquí.

begin;

-- Las membresías y los home_member de las pantallas (solo kind display)
delete from membership_permission where home_membership_id in (
    select hm.id from home_membership hm join home_member m on m.home_id = hm.home_id and m.app_user_id = hm.app_user_id
    where m.kind = 'display');
delete from home_member where kind = 'display';
delete from home_membership hm where exists (
    select 1 from home_display d where d.app_user_id = hm.app_user_id and d.home_id = hm.home_id)
    and not exists (select 1 from home_member m where m.home_id = hm.home_id and m.app_user_id = hm.app_user_id);

drop table if exists home_display_attempt;
drop table if exists home_display_link;
drop table if exists home_display_task_list;
drop table if exists home_display_calendar;
drop table if exists home_display;

drop function if exists fn_display_config();
drop function if exists fn_display_revoke(bigint, bigint);
drop function if exists fn_display_update(bigint, bigint, text, jsonb, bigint[], bigint[]);
drop function if exists fn_display_list(bigint);
drop function if exists fn_display_link_abort(bigint);
drop function if exists fn_display_link_poll(text);
drop function if exists fn_display_link_complete(bigint, uuid, jsonb);
drop function if exists fn_display_link_claim(bigint, text, text);
drop function if exists fn_display_link_start();
drop function if exists fn_display_hash(text);
drop function if exists fn_can_manage_displays(bigint);

delete from membership_permission where permission_code = 'display.manage';
delete from permission where code = 'display.manage';

commit;
