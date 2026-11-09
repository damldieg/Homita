-- 0013_home_backfill.sql — Backfill del modelo Home sobre los datos existentes (fase 1.3;
-- spec 1.2 §3, §4, §6–§13, §16). Crea el Home inicial de cada usuario existente y asocia sus
-- recursos sin pérdida de datos: componentes conexas de calendarios/listas (§4), admins = owners
-- (§5), dedupe de ACL con log (§6), membresías y permisos snapshot member legacy 17 (Q-B),
-- home_id de recursos (S5), home_member 1:1 por person (§7.1), copias cruzadas (§7.2),
-- invariantes I1–I12 (§12) y resumen `backfill.home.v1` (S9).
--
-- Notas:
-- * Transacción propia (Q-P4): `begin…commit` explícitos; si un paso falla, nada persiste (R2).
-- * S0 guard (§3): si ya existe alguna home_membership, ejecuta I1–I12 inline (sin comp ni temp
--   tables) → notice 'backfill ya aplicado' → return. Fail-safe: si un invariante falla, aborta.
-- * S1 recrea el schema home_migration (snapshot pre/post, copy_map, orphan_home_map) y S10 lo
--   revoca a anon/authenticated. Tras rollback (rollback_0013.sql) el schema se conserva como
--   evidencia y esta migración lo recrea al re-ejecutarse.
-- * Los nombres de hogar siguen §9 (Q-D): 'Hogar de X' / 'Hogar de X (y Y)' con los dos admins de
--   menor id; huérfanos: 'Sin asignar · calendario|lista <id>' (archived, sin miembros).
-- * Invariantes en texto único (v_check_sql) reutilizado por S0 y S8 (inline, sin temp tables).

begin;

do $$
declare
    -- I1–I12 (§12): devuelve los nombres de invariantes incumplidos (null = todo correcto).
    v_check_sql text := $check$
        with recursive
        edge(u1, u2) as (
            select a.user_id, b.user_id
            from calendar_user a join calendar_user b on b.calendar_id = a.calendar_id
            union
            select a.user_id, b.user_id
            from task_list_user a join task_list_user b on b.task_list_id = a.task_list_id
        ),
        reach(s, u) as (
            select id, id from app_user
            union
            select r.s, e.u2 from reach r join edge e on e.u1 = r.u
        ),
        comp(u, root) as (
            select u, min(s) as root from reach group by u
        ),
        checks(name, ok) as (
            select 'I1', not exists (select 1 from calendar where home_id is null)
                      and not exists (select 1 from task_list where home_id is null)
            union all
            select 'I2', not exists (
                        select 1 from calendar_user cu join calendar c on c.id = cu.calendar_id
                        where cu.home_id is distinct from c.home_id
                           or not exists (select 1 from home_membership hm
                                          where hm.home_id = cu.home_id and hm.app_user_id = cu.user_id))
                    and not exists (
                        select 1 from task_list_user tu join task_list tl on tl.id = tu.task_list_id
                        where tu.home_id is distinct from tl.home_id
                           or not exists (select 1 from home_membership hm
                                          where hm.home_id = tu.home_id and hm.app_user_id = tu.user_id))
            union all
            select 'I3', not exists (
                        select 1 from home h
                        where h.status = 'active'
                          and not exists (select 1 from home_membership hm
                                          where hm.home_id = h.id and hm.role = 'admin'))
            union all
            select 'I4', not exists (
                        select 1 from calendar_user cu
                        where cu.role = 'owner'
                          and not exists (select 1 from home_membership hm
                                          where hm.home_id = cu.home_id and hm.app_user_id = cu.user_id
                                            and hm.role = 'admin'))
                    and not exists (
                        select 1 from task_list_user tu
                        where tu.role = 'owner'
                          and not exists (select 1 from home_membership hm
                                          where hm.home_id = tu.home_id and hm.app_user_id = tu.user_id
                                            and hm.role = 'admin'))
            union all
            select 'I5', not exists (
                        select 1 from person p
                        where p.home_member_id is null or p.home_id is null
                           or not exists (select 1 from home_member m
                                          where m.id = p.home_member_id and m.home_id = p.home_id))
                    and not exists (
                        select 1 from home_member m
                        where not exists (select 1 from person p where p.home_member_id = m.id))
                    and not exists (
                        select 1 from person p1 join person p2
                            on p1.home_member_id = p2.home_member_id and p1.id < p2.id)
            union all
            select 'I6', not exists (
                        select 1 from app_user u
                        where (select count(*) from home_membership hm
                               where hm.app_user_id = u.id) <> 1
                           or u.default_home_id is distinct from
                              (select hm.home_id from home_membership hm where hm.app_user_id = u.id))
            union all
            select 'I7', not exists (
                        select 1 from event_person ep
                        join event e on e.id = ep.event_id
                        join calendar c on c.id = e.calendar_id
                        join person p on p.id = ep.person_id
                        where c.home_id is distinct from p.home_id)
                    and not exists (
                        select 1 from routine_person rp
                        join routine ro on ro.id = rp.routine_id
                        join calendar c on c.id = ro.calendar_id
                        join person p on p.id = rp.person_id
                        where c.home_id is distinct from p.home_id)
            union all
            select 'I8', not exists (select 1 from calendar_user
                                     group by calendar_id, user_id having count(*) > 1)
                    and not exists (select 1 from task_list_user
                                    group by task_list_id, user_id having count(*) > 1)
            union all
            select 'I9', (select count(*) from home_membership) = (select count(*) from app_user)
            union all
            select 'I10', not exists (
                        select 1 from home_membership hm
                        where hm.role = 'admin'
                          and not exists (select 1 from calendar_user cu
                                          join calendar c on c.id = cu.calendar_id
                                          where cu.user_id = hm.app_user_id and cu.role = 'owner'
                                            and c.home_id = hm.home_id)
                          and not exists (select 1 from task_list_user tu
                                          join task_list tl on tl.id = tu.task_list_id
                                          where tu.user_id = hm.app_user_id and tu.role = 'owner'
                                            and tl.home_id = hm.home_id)
                          and (exists (select 1 from calendar_user cu
                                       join calendar c on c.id = cu.calendar_id
                                       where c.home_id = hm.home_id and cu.role = 'owner')
                            or exists (select 1 from task_list_user tu
                                       join task_list tl on tl.id = tu.task_list_id
                                       where tl.home_id = hm.home_id and tu.role = 'owner')))
            union all
            select 'I11', not exists (
                        select 1 from membership_permission mp
                        join home_membership hm on hm.id = mp.home_membership_id
                        where hm.role = 'admin')
                    and not exists (
                        select 1 from home_membership hm
                        where hm.role = 'member'
                          and (select count(*) from membership_permission mp
                               where mp.home_membership_id = hm.id) <> 17)
                    and not exists (
                        select 1 from membership_permission mp
                        where not exists (select 1 from permission pe where pe.code = mp.permission_code))
            union all
            select 'I12', (select count(*) from home)
                        = (select count(distinct root) from comp)
                        + (select count(*) from home_migration.orphan_home_map)
                    and not exists (
                        select 1 from home h
                        where h.status = 'archived'
                          and exists (select 1 from home_membership hm where hm.home_id = h.id))
        )
        select string_agg(name, ',' order by name) from checks where not ok
    $check$;
    v_failed text;
    v_rec record;
    v_home bigint;
    v_hm bigint;
    v_copy bigint;
    v_user bigint;
    v_n_ep bigint;
    v_n_rp bigint;
begin
    -- CA-10: ACL con usuario inexistente en app_user (solo posible con replica, la FK normal lo
    -- impide) → invariante roto ANTES de S4, donde el FK crudo de home_membership lo daría con un
    -- mensaje ininteligible. Se comprueba antes del guard S0 para cubrir también la re-ejecución.
    select string_agg(distinct x.user_id::text, ', ') into v_failed
    from (
        select cu.user_id from calendar_user cu
        where not exists (select 1 from app_user u where u.id = cu.user_id)
        union all
        select tu.user_id from task_list_user tu
        where not exists (select 1 from app_user u where u.id = tu.user_id)
    ) x;
    if v_failed is not null then
        raise exception 'backfill invariant: user_id % no existe en app_user', v_failed;
    end if;

    -- S0 (§3): guard de idempotencia — ya aplicado → invariantes inline → notice → return
    if exists (select 1 from home_membership) then
        execute v_check_sql into v_failed;
        if v_failed is not null then
            raise exception 'backfill invariant: %', v_failed;
        end if;
        raise notice 'backfill ya aplicado';
        return;
    end if;

    -- S1 (§11): schema de trabajo + snapshot PRE (§13) + mapas persistentes
    execute 'drop schema if exists home_migration cascade';
    execute 'create schema home_migration';
    create table home_migration.pre_app_user as select * from app_user;
    create table home_migration.pre_calendar as select * from calendar;
    create table home_migration.pre_task_list as select * from task_list;
    create table home_migration.pre_calendar_user as select * from calendar_user;
    create table home_migration.pre_task_list_user as select * from task_list_user;
    create table home_migration.pre_event as select * from event;
    create table home_migration.pre_routine as select * from routine;
    create table home_migration.pre_routine_exception as select * from routine_exception;
    create table home_migration.pre_routine_event_alarm as select * from routine_event_alarm;
    create table home_migration.pre_event_user as select * from event_user;
    create table home_migration.pre_routine_user as select * from routine_user;
    create table home_migration.pre_task as select * from task;
    create table home_migration.pre_event_person as select * from event_person;
    create table home_migration.pre_routine_person as select * from routine_person;
    create table home_migration.pre_person as select * from person;
    create table home_migration.copy_map (
        orig_person_id bigint not null,
        home_id bigint not null,
        copy_person_id bigint not null,
        primary key (orig_person_id, home_id)
    );
    create table home_migration.orphan_home_map (
        kind text not null check (kind in ('calendar', 'task_list')),
        resource_id bigint not null,
        home_id bigint not null,
        primary key (kind, resource_id)
    );

    -- S2 (§4): componentes conexas, admins (§5) y homes
    create temp table comp (u bigint primary key, root bigint) on commit drop;
    insert into comp (u, root)
    with recursive
    edge(u1, u2) as (
        select a.user_id, b.user_id
        from calendar_user a join calendar_user b on b.calendar_id = a.calendar_id
        union
        select a.user_id, b.user_id
        from task_list_user a join task_list_user b on b.task_list_id = a.task_list_id
    ),
    reach(s, u) as (
        select id, id from app_user
        union
        select r.s, e.u2 from reach r join edge e on e.u1 = r.u
    )
    select u, min(s) as root from reach group by u;

    create temp table adm (root bigint not null, app_user_id bigint not null,
                           primary key (root, app_user_id)) on commit drop;
    -- S2b: admin(H) = owners de ≥1 recurso de H (D3)
    insert into adm (root, app_user_id)
    select distinct c.root, c.u
    from comp c
    where exists (select 1 from calendar_user cu where cu.user_id = c.u and cu.role = 'owner')
       or exists (select 1 from task_list_user tu where tu.user_id = c.u and tu.role = 'owner');
    -- S2b: fallback sin owner (§5): más filas ACL (calendarios+listas), empate → menor id (CA-6)
    for v_rec in
        select c.root as r,
               (select c2.u from comp c2
                where c2.root = c.root
                order by (select count(*) from calendar_user cu where cu.user_id = c2.u)
                       + (select count(*) from task_list_user tu where tu.user_id = c2.u) desc,
                       c2.u asc
                limit 1) as u
        from (select distinct root from comp c
              where not exists (select 1 from adm a where a.root = c.root)) c
    loop
        raise notice 'backfill: componente % sin owner, admin por fallback (usuario %)', v_rec.r, v_rec.u;
        insert into adm (root, app_user_id) values (v_rec.r, v_rec.u);
    end loop;

    -- S2c: homes de componentes en orden de raíz (G3), nombre §9 (Q-D)
    create temp table home_map (root bigint primary key, home_id bigint not null) on commit drop;
    for v_rec in
        select c.root as r,
               (select count(*) from comp c2 where c2.root = c.root) as n_users,
               (select a.app_user_id from adm a where a.root = c.root
                order by a.app_user_id limit 1) as admin1,
               (select a.app_user_id from adm a where a.root = c.root
                order by a.app_user_id offset 1 limit 1) as admin2
        from (select distinct root from comp c) c
        order by c.root
    loop
        insert into home (name, is_personal, created_by)
        values (
            'Hogar de ' || (select u.name from app_user u where u.id = v_rec.admin1)
            || coalesce(' (y ' || (select u.name from app_user u where u.id = v_rec.admin2) || ')', ''),
            v_rec.n_users = 1,
            v_rec.admin1)
        returning id into v_home;
        insert into home_map (root, home_id) values (v_rec.r, v_home);
    end loop;

    -- S2d: homes archived de huérfanos (G5): sin ACL, sin miembros, orden tipo e id
    for v_rec in
        select x.kind, x.rid from (
            select 'calendar'::text as kind, c.id as rid, 1 as ord
            from calendar c
            where not exists (select 1 from calendar_user cu where cu.calendar_id = c.id)
            union all
            select 'task_list', tl.id, 2
            from task_list tl
            where not exists (select 1 from task_list_user tu where tu.task_list_id = tl.id)
        ) x order by x.ord, x.rid
    loop
        insert into home (name, status, is_personal, created_by)
        values (case when v_rec.kind = 'calendar' then 'Sin asignar · calendario '
                     else 'Sin asignar · lista ' end || v_rec.rid,
                'archived', false, null)
        returning id into v_home;
        insert into home_migration.orphan_home_map (kind, resource_id, home_id)
        values (v_rec.kind, v_rec.rid, v_home);
    end loop;

    -- S3 (§6): dedupe de ACL — se conserva owner primero, luego menor id; el resto va a audit_log
    for v_rec in
        select cu.id, 'calendar_user'::text as kind, cu.calendar_id as resource_id,
               cu.user_id, cu.role, cu.widget, cu.dashboard
        from calendar_user cu
        where cu.id <> (
            select distinct on (c2.calendar_id, c2.user_id) c2.id
            from calendar_user c2
            where c2.calendar_id = cu.calendar_id and c2.user_id = cu.user_id
            order by c2.calendar_id, c2.user_id, (case when c2.role = 'owner' then 0 else 1 end), c2.id)
        union all
        select tu.id, 'task_list_user', tu.task_list_id, tu.user_id, tu.role, tu.widget, tu.dashboard
        from task_list_user tu
        where tu.id <> (
            select distinct on (t2.task_list_id, t2.user_id) t2.id
            from task_list_user t2
            where t2.task_list_id = tu.task_list_id and t2.user_id = tu.user_id
            order by t2.task_list_id, t2.user_id, (case when t2.role = 'owner' then 0 else 1 end), t2.id)
    loop
        select hm.home_id into v_home
        from home_map hm
        where hm.root = (select c.root from comp c where c.u = v_rec.user_id);
        insert into audit_log (home_id, actor_app_user_id, action, target_type, target_id, payload)
        values (v_home, null, 'backfill.acl_dedupe', v_rec.kind, v_rec.id,
                jsonb_build_object('table', v_rec.kind, 'id', v_rec.id,
                                   'resource_id', v_rec.resource_id, 'user_id', v_rec.user_id,
                                   'role', v_rec.role, 'widget', v_rec.widget, 'dashboard', v_rec.dashboard));
        if v_rec.kind = 'calendar_user' then
            delete from calendar_user where id = v_rec.id;
        else
            delete from task_list_user where id = v_rec.id;
        end if;
    end loop;

    -- S4 (§10): una membresía por usuario; snapshot member legacy 17 (Q-B) solo a no admin (A4);
    -- default_home_id = esa membresía
    insert into home_membership (home_id, app_user_id, role)
    select hm.home_id, c.u,
           case when exists (select 1 from adm a where a.root = c.root and a.app_user_id = c.u)
                then 'admin'::home_role else 'member'::home_role end
    from comp c
    join home_map hm on hm.root = c.root;

    insert into membership_permission (home_membership_id, permission_code)
    select hm.id, x.code
    from home_membership hm
    cross join unnest(array[
        'home.view',
        'calendar.view', 'task.view', 'routine.view',
        'task.create', 'task.edit', 'task.complete', 'task.assign', 'task.delete',
        'event.create', 'event.edit', 'event.delete', 'event.assign',
        'routine.create', 'routine.edit', 'routine.delete', 'routine.assign']) as x(code)
    where hm.role = 'member';

    update app_user u
    set default_home_id = (select hm.home_id from home_membership hm where hm.app_user_id = u.id);

    -- S5 (§11): home_id de recursos y de ACL
    update calendar c
    set home_id = coalesce(
        (select ohm.home_id from home_migration.orphan_home_map ohm
         where ohm.kind = 'calendar' and ohm.resource_id = c.id),
        (select hm.home_id from home_map hm
         where hm.root = (select c2.root from comp c2
                          join calendar_user cu on cu.user_id = c2.u
                          where cu.calendar_id = c.id limit 1)));
    update task_list tl
    set home_id = coalesce(
        (select ohm.home_id from home_migration.orphan_home_map ohm
         where ohm.kind = 'task_list' and ohm.resource_id = tl.id),
        (select hm.home_id from home_map hm
         where hm.root = (select c2.root from comp c2
                          join task_list_user tu on tu.user_id = c2.u
                          where tu.task_list_id = tl.id limit 1)));
    update calendar_user cu
    set home_id = (select c.home_id from calendar c where c.id = cu.calendar_id);
    update task_list_user tu
    set home_id = (select tl.home_id from task_list tl where tl.id = tu.task_list_id);

    -- S6 (§7.1): home_member 1:1 por person (adult, sin cuenta); person.home_id y home_member_id
    for v_rec in
        select p.id as pid, p.user_id, p.name, p.color, hm.home_id as hid
        from person p
        join comp c on c.u = p.user_id
        join home_map hm on hm.root = c.root
        order by p.id
    loop
        insert into home_member (home_id, kind, name, color, app_user_id, status, created_by)
        values (v_rec.hid, 'adult', v_rec.name, v_rec.color, null, 'active', v_rec.user_id)
        returning id into v_hm;
        update person set home_id = v_rec.hid, home_member_id = v_hm where id = v_rec.pid;
    end loop;

    -- S7 (§7.2): copias cruzadas — una copia por par (persona, home destino), reutilizada
    for v_rec in
        select x.orig_id, x.dest_home, x.pname, x.pcolor, x.puser from (
            select distinct p.id as orig_id, c.home_id as dest_home,
                            p.name as pname, p.color as pcolor, p.user_id as puser
            from event_person ep
            join event e on e.id = ep.event_id
            join calendar c on c.id = e.calendar_id
            join person p on p.id = ep.person_id
            where c.home_id is distinct from p.home_id
            union
            select distinct p.id, c.home_id, p.name, p.color, p.user_id
            from routine_person rp
            join routine ro on ro.id = rp.routine_id
            join calendar c on c.id = ro.calendar_id
            join person p on p.id = rp.person_id
            where c.home_id is distinct from p.home_id
        ) x
        order by x.orig_id, x.dest_home
    loop
        select cm.copy_person_id into v_copy
        from home_migration.copy_map cm
        where cm.orig_person_id = v_rec.orig_id and cm.home_id = v_rec.dest_home;
        if v_copy is null then
            select count(*) into v_n_ep
            from event_person ep
            join event e on e.id = ep.event_id
            join calendar c on c.id = e.calendar_id
            where ep.person_id = v_rec.orig_id and c.home_id = v_rec.dest_home;
            select count(*) into v_n_rp
            from routine_person rp
            join routine ro on ro.id = rp.routine_id
            join calendar c on c.id = ro.calendar_id
            where rp.person_id = v_rec.orig_id and c.home_id = v_rec.dest_home;
            -- A-10: user_id = admin con menor id del home destino; si archived, creador original
            if (select h.status from home h where h.id = v_rec.dest_home) = 'active' then
                select min(a.app_user_id) into v_user
                from adm a
                join home_map hm on hm.root = a.root
                where hm.home_id = v_rec.dest_home;
            else
                v_user := v_rec.puser;
            end if;
            insert into home_member (home_id, kind, name, color, app_user_id, status, created_by)
            values (v_rec.dest_home, 'adult', v_rec.pname, v_rec.pcolor, null, 'active', v_user)
            returning id into v_hm;
            insert into person (user_id, home_id, home_member_id, name, color)
            values (v_user, v_rec.dest_home, v_hm, v_rec.pname, v_rec.pcolor)
            returning id into v_copy;
            insert into home_migration.copy_map (orig_person_id, home_id, copy_person_id)
            values (v_rec.orig_id, v_rec.dest_home, v_copy);
            insert into audit_log (home_id, actor_app_user_id, action, target_type, target_id, payload)
            values (v_rec.dest_home, null, 'backfill.cross_person_copy', 'person', v_copy,
                    jsonb_build_object('orig', v_rec.orig_id, 'copy', v_copy,
                                       'n_event_person', v_n_ep, 'n_routine_person', v_n_rp));
        end if;
    end loop;
    -- Reasignación de asignaciones cruzadas a la copia (§7.2.2): sin borrar filas
    update event_person ep
    set person_id = cm.copy_person_id
    from home_migration.copy_map cm
    where ep.person_id = cm.orig_person_id
      and cm.home_id = (select c.home_id from event e join calendar c on c.id = e.calendar_id
                        where e.id = ep.event_id);
    update routine_person rp
    set person_id = cm.copy_person_id
    from home_migration.copy_map cm
    where rp.person_id = cm.orig_person_id
      and cm.home_id = (select c.home_id from routine ro join calendar c on c.id = ro.calendar_id
                        where ro.id = rp.routine_id);

    -- S8 (§12): invariantes I1–I12 (mismo SQL inline que S0)
    execute v_check_sql into v_failed;
    if v_failed is not null then
        raise exception 'backfill invariant: %', v_failed;
    end if;

    -- S9 (§11): snapshot POST + resumen `backfill.home.v1` (sin usuarios ni recursos → no inserta)
    create table home_migration.post_app_user as select * from app_user;
    create table home_migration.post_calendar as select * from calendar;
    create table home_migration.post_task_list as select * from task_list;
    create table home_migration.post_calendar_user as select * from calendar_user;
    create table home_migration.post_task_list_user as select * from task_list_user;
    create table home_migration.post_event as select * from event;
    create table home_migration.post_routine as select * from routine;
    create table home_migration.post_routine_exception as select * from routine_exception;
    create table home_migration.post_routine_event_alarm as select * from routine_event_alarm;
    create table home_migration.post_event_user as select * from event_user;
    create table home_migration.post_routine_user as select * from routine_user;
    create table home_migration.post_task as select * from task;
    create table home_migration.post_event_person as select * from event_person;
    create table home_migration.post_routine_person as select * from routine_person;
    create table home_migration.post_person as select * from person;
    if exists (select 1 from home) then
        insert into audit_log (home_id, actor_app_user_id, action, target_type, target_id, payload)
        select h.id, null, 'backfill.home.v1', 'home', h.id,
               jsonb_build_object(
                   'homes_personal', (select count(*) from home where is_personal),
                   'homes_shared', (select count(*) from home where not is_personal and status = 'active'),
                   'homes_orphan', (select count(*) from home where status = 'archived'),
                   'memberships', (select count(*) from home_membership),
                   'persons', (select count(*) from person),
                   'copies', (select count(*) from home_migration.copy_map),
                   'acl_dedupes', (select count(*) from audit_log where action = 'backfill.acl_dedupe'),
                   'orphans', (select count(*) from home_migration.orphan_home_map))
        from home h order by h.id limit 1;
    end if;

    -- S10 (§11): schema de trabajo fuera del alcance de clientes
    execute 'revoke all on all tables in schema home_migration from public, anon, authenticated';
end $$;

commit;
