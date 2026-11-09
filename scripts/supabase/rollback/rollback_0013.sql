-- rollback_0013.sql — Rollback B del backfill 0013 (fase 1.3, V8; plan 1.2 §14 R3-B).
-- Revierte 0013 dejando el estado igual al snapshot pre (CA-13). Precondición (R3-B): 0014 y 0015
-- NO aplicadas. Se ejecuta en UNA transacción:
--   psql -v ON_ERROR_STOP=1 -f rollback_0013.sql
-- Orden exacto (§14 R3-B): (1) verificación CA-13 contra home_migration.pre_* al final y schema
-- conservado como evidencia; (2) reinsertar ACL borradas desde audit_log con id original (payload);
-- (3) mover event_person/routine_person de la copia al original (copy_map); (4) borrar personas
-- copia y sus home_member; (5) poner a NULL las columnas home_id/home_member_id/default_home_id;
-- (6) borrar membership_permission, home_membership y home_member restantes; (7) borrar el
-- audit_log de backfill (antes de home: FK RESTRICT); (8) borrar home (archived, luego el resto).
-- Tras B, home_migration se conserva hasta re-ejecutar 0013 (que lo recrea en S1).

begin;

-- ── Precondiciones (§14 R3-B) ──
do $$
begin
    if to_regclass('home_migration.pre_app_user') is null then
        raise exception 'rollback_0013: falta home_migration.pre_* (0013 no aplicada)';
    end if;
    if to_regprocedure('fn_person_deleted()') is not null then
        raise exception 'rollback_0013: 0014 ya aplicada (fn_person_deleted); precondición R3-B';
    end if;
    if exists (select 1 from pg_trigger where tgname in ('event_person_check', 'routine_person_check')) then
        raise exception 'rollback_0013: 0015 ya aplicada (trigger de asignaciones); precondición R3-B';
    end if;
    raise notice 'rollback_0013: precondiciones OK (0014/0015 sin aplicar)';
end $$;

-- ── (2) Reinsertar ACL borradas en el dedupe (§6) desde audit_log, con id original (payload) ──
insert into calendar_user (id, calendar_id, user_id, role, created_at, widget, dashboard)
select (al.payload->>'id')::bigint,
       (al.payload->>'resource_id')::bigint,
       (al.payload->>'user_id')::bigint,
       (al.payload->>'role')::user_role,
       coalesce((select pc.created_at from home_migration.pre_calendar_user pc
                 where pc.id = (al.payload->>'id')::bigint), (now() at time zone 'UTC')),
       (al.payload->>'widget')::boolean,
       (al.payload->>'dashboard')::boolean
from audit_log al
where al.action = 'backfill.acl_dedupe' and al.target_type = 'calendar_user';

insert into task_list_user (id, task_list_id, user_id, role, created_at, widget, dashboard)
select (al.payload->>'id')::bigint,
       (al.payload->>'resource_id')::bigint,
       (al.payload->>'user_id')::bigint,
       (al.payload->>'role')::user_role,
       coalesce((select pt.created_at from home_migration.pre_task_list_user pt
                 where pt.id = (al.payload->>'id')::bigint), (now() at time zone 'UTC')),
       (al.payload->>'widget')::boolean,
       (al.payload->>'dashboard')::boolean
from audit_log al
where al.action = 'backfill.acl_dedupe' and al.target_type = 'task_list_user';

-- ── (3) Mover asignaciones de la copia al original (copy_map) ──
update event_person ep
set person_id = cm.orig_person_id
from home_migration.copy_map cm
where ep.person_id = cm.copy_person_id;

update routine_person rp
set person_id = cm.orig_person_id
from home_migration.copy_map cm
where rp.person_id = cm.copy_person_id;

-- ── (4) Borrar personas copia y sus home_member ──
create temp table _rollback_copy_hm (home_member_id bigint) on commit drop;
insert into _rollback_copy_hm
select p.home_member_id
from person p
join home_migration.copy_map cm on cm.copy_person_id = p.id;
delete from person p using home_migration.copy_map cm where p.id = cm.copy_person_id;
delete from home_member m using _rollback_copy_hm r where m.id = r.home_member_id;

-- ── (5) Columnas de hogar a NULL (0012 las creó nullables) ──
update calendar set home_id = null;
update task_list set home_id = null;
update calendar_user set home_id = null;
update task_list_user set home_id = null;
update person set home_id = null, home_member_id = null;
update app_user set default_home_id = null;

-- ── (6) Membresías, permisos y miembros restantes ──
delete from membership_permission;
delete from home_membership;
delete from home_member;

-- ── (7) audit_log de backfill (FK RESTRICT a home: antes que home) ──
delete from audit_log where action like 'backfill.%';

-- ── (8) Homes: archived primero, luego componentes ──
delete from home where status = 'archived';
delete from home;

-- ── (1) CA-13: conteos y conjuntos = snapshot pre (home_migration se conserva como evidencia) ──
do $$
declare
    t text;
    v_bad text := '';
    v_pre bigint;
    v_post bigint;
begin
    foreach t in array array['app_user', 'calendar', 'task_list', 'calendar_user', 'task_list_user',
                             'event', 'routine', 'event_user', 'task', 'person'] loop
        execute format('select count(*) from home_migration.pre_%I', t) into v_pre;
        execute format('select count(*) from %I', t) into v_post;
        if v_pre <> v_post then
            v_bad := v_bad || t || '(' || v_pre || '≠' || v_post || ') ';
        end if;
        execute format(
            'select case when exists (select id from %I except select id from home_migration.pre_%I)'
            '          or exists (select id from home_migration.pre_%I except select id from %I)'
            '     then %L else %L end', t, t, t, t, t, '')
        into t;
        if t <> '' then
            v_bad := v_bad || t || '(set) ';
        end if;
    end loop;
    if exists (select routine_id, routine_date from routine_exception
               except select routine_id, routine_date from home_migration.pre_routine_exception)
       or exists (select routine_id, routine_date from home_migration.pre_routine_exception
                  except select routine_id, routine_date from routine_exception)
       or (select count(*) from routine_exception) <> (select count(*) from home_migration.pre_routine_exception) then
        v_bad := v_bad || 'routine_exception ';
    end if;
    if exists (select routine_id, routine_date, user_id from routine_event_alarm
               except select routine_id, routine_date, user_id from home_migration.pre_routine_event_alarm)
       or exists (select routine_id, routine_date, user_id from home_migration.pre_routine_event_alarm
                  except select routine_id, routine_date, user_id from routine_event_alarm)
       or (select count(*) from routine_event_alarm) <> (select count(*) from home_migration.pre_routine_event_alarm) then
        v_bad := v_bad || 'routine_event_alarm ';
    end if;
    if exists (select routine_id, user_id from routine_user
               except select routine_id, user_id from home_migration.pre_routine_user)
       or exists (select routine_id, user_id from home_migration.pre_routine_user
                  except select routine_id, user_id from routine_user)
       or (select count(*) from routine_user) <> (select count(*) from home_migration.pre_routine_user) then
        v_bad := v_bad || 'routine_user ';
    end if;
    if exists (select event_id, person_id from event_person
               except select event_id, person_id from home_migration.pre_event_person)
       or exists (select event_id, person_id from home_migration.pre_event_person
                  except select event_id, person_id from event_person) then
        v_bad := v_bad || 'event_person ';
    end if;
    if exists (select routine_id, person_id from routine_person
               except select routine_id, person_id from home_migration.pre_routine_person)
       or exists (select routine_id, person_id from home_migration.pre_routine_person
                  except select routine_id, person_id from routine_person) then
        v_bad := v_bad || 'routine_person ';
    end if;
    if (select count(*) from home) <> 0 or (select count(*) from home_membership) <> 0
       or (select count(*) from home_member) <> 0 or (select count(*) from membership_permission) <> 0
       or (select count(*) from audit_log) <> 0 then
        v_bad := v_bad || 'tablas-home-no-vacías ';
    end if;
    if exists (select 1 from calendar where home_id is not null)
       or exists (select 1 from task_list where home_id is not null)
       or exists (select 1 from calendar_user where home_id is not null)
       or exists (select 1 from task_list_user where home_id is not null)
       or exists (select 1 from person where home_id is not null or home_member_id is not null)
       or exists (select 1 from app_user where default_home_id is not null) then
        v_bad := v_bad || 'columnas-home-no-null ';
    end if;
    if v_bad <> '' then
        raise exception 'rollback_0013 CA-13: estado ≠ snapshot pre: %', v_bad;
    end if;
    raise notice 'rollback_0013 CA-13: conteos y conjuntos = snapshot pre';
end $$;

commit;
