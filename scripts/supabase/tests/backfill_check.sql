-- backfill_check.sql — Verificación del backfill 0013 (fase 1.3, V6; plan 1.2 §13 y §16 CA-1,
-- CA-4…CA-8, CA-11, CA-12, CA-15, CA-16; plan 1.3 T6). Se ejecuta con psql tras aplicar 0013
-- (antes de 0014/0015) sobre el estado sembrado por seed.py + backfill_fixture.sql:
--   psql -v ON_ERROR_STOP=1 -f backfill_check.sql
-- Cada bloque DO emite 'ok …' o aborta con 'backfill_check: …'. Usa home_migration.pre_* (S1) y
-- home_migration.copy_map / orphan_home_map. CA-9/CA-10/CA-13 las gestiona el ensayo (fuera).
--
-- Cubre: invariantes I1–I12 (§12), conteos §13.1 (CA-4), conjuntos §13.2 (CA-5), determinismo del
-- grafo §4.2 (CA-1), admins = owners (CA-6), huérfano (CA-7), copia cruzada (CA-8), dedupe (CA-11),
-- defaults y snapshot member legacy (CA-12), nombres §9/Q-D (CA-15) y audit target_type (CA-16).

-- ── I1–I12 (mismo SQL inline que 0013 S0/S8) ──
do $$
declare
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
begin
    execute v_check_sql into v_failed;
    if v_failed is not null then
        raise exception 'backfill_check: invariante(s) I1-I12 incumplida(s): %', v_failed;
    end if;
    raise notice 'ok backfill_check: I1-I12';
end $$;

-- ── CA-1: determinismo del grafo §4.2 (dos ejecuciones idénticas) ──
do $$
declare
    v_sql text := $q$
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
        select string_agg(u || '>' || root, ',' order by u) from (select u, min(s) as root from reach group by u) t
    $q$;
    v_a text;
    v_b text;
begin
    execute v_sql into v_a;
    execute v_sql into v_b;
    if v_a is distinct from v_b then
        raise exception 'backfill_check CA-1: grafo no determinista: % vs %', v_a, v_b;
    end if;
    raise notice 'ok backfill_check CA-1: §4.2 determinista (% filas u→root)', 1 + length(regexp_replace(v_a, '[^,]', '', 'g'));
end $$;

-- ── CA-4: conteos §13.1 (pre vs post, deltas exactos) ──
do $$
declare
    v_pre bigint;
    v_post bigint;
    v_ded_c bigint;
    v_ded_l bigint;
    v_copies bigint;
    v_resumen bigint;
begin
    select count(*) into v_ded_c from audit_log where action = 'backfill.acl_dedupe' and target_type = 'calendar_user';
    select count(*) into v_ded_l from audit_log where action = 'backfill.acl_dedupe' and target_type = 'task_list_user';
    select count(*) into v_copies from home_migration.copy_map;
    select case when exists (select 1 from home) then 1 else 0 end into v_resumen;

    select count(*) into v_pre from home_migration.pre_app_user;
    select count(*) into v_post from app_user;
    if v_pre <> v_post then
        raise exception 'backfill_check CA-4: app_user pre=% post=%', v_pre, v_post;
    end if;

    select count(*) into v_pre from home_migration.pre_calendar;
    select count(*) into v_post from calendar;
    if v_pre <> v_post then
        raise exception 'backfill_check CA-4: calendar pre=% post=%', v_pre, v_post;
    end if;

    select count(*) into v_pre from home_migration.pre_task_list;
    select count(*) into v_post from task_list;
    if v_pre <> v_post then
        raise exception 'backfill_check CA-4: task_list pre=% post=%', v_pre, v_post;
    end if;

    select count(*) into v_pre from home_migration.pre_calendar_user;
    select count(*) into v_post from calendar_user;
    if v_post <> v_pre - v_ded_c then
        raise exception 'backfill_check CA-4: calendar_user pre=% post=% dedupe=%', v_pre, v_post, v_ded_c;
    end if;

    select count(*) into v_pre from home_migration.pre_task_list_user;
    select count(*) into v_post from task_list_user;
    if v_post <> v_pre - v_ded_l then
        raise exception 'backfill_check CA-4: task_list_user pre=% post=% dedupe=%', v_pre, v_post, v_ded_l;
    end if;

    -- Filas sin cambio: event, routine, routine_exception, routine_event_alarm, event_user,
    -- routine_user, task, event_person (reasignadas), routine_person (reasignadas)
    select count(*) into v_pre from home_migration.pre_event;
    select count(*) into v_post from event;
    if v_pre <> v_post then
        raise exception 'backfill_check CA-4: event pre=% post=%', v_pre, v_post;
    end if;

    select count(*) into v_pre from home_migration.pre_routine;
    select count(*) into v_post from routine;
    if v_pre <> v_post then
        raise exception 'backfill_check CA-4: routine pre=% post=%', v_pre, v_post;
    end if;

    select count(*) into v_pre from home_migration.pre_routine_exception;
    select count(*) into v_post from routine_exception;
    if v_pre <> v_post then
        raise exception 'backfill_check CA-4: routine_exception pre=% post=%', v_pre, v_post;
    end if;

    select count(*) into v_pre from home_migration.pre_routine_event_alarm;
    select count(*) into v_post from routine_event_alarm;
    if v_pre <> v_post then
        raise exception 'backfill_check CA-4: routine_event_alarm pre=% post=%', v_pre, v_post;
    end if;

    select count(*) into v_pre from home_migration.pre_event_user;
    select count(*) into v_post from event_user;
    if v_pre <> v_post then
        raise exception 'backfill_check CA-4: event_user pre=% post=%', v_pre, v_post;
    end if;

    select count(*) into v_pre from home_migration.pre_routine_user;
    select count(*) into v_post from routine_user;
    if v_pre <> v_post then
        raise exception 'backfill_check CA-4: routine_user pre=% post=%', v_pre, v_post;
    end if;

    select count(*) into v_pre from home_migration.pre_task;
    select count(*) into v_post from task;
    if v_pre <> v_post then
        raise exception 'backfill_check CA-4: task pre=% post=%', v_pre, v_post;
    end if;

    select count(*) into v_pre from home_migration.pre_event_person;
    select count(*) into v_post from event_person;
    if v_pre <> v_post then
        raise exception 'backfill_check CA-4: event_person pre=% post=%', v_pre, v_post;
    end if;

    select count(*) into v_pre from home_migration.pre_routine_person;
    select count(*) into v_post from routine_person;
    if v_pre <> v_post then
        raise exception 'backfill_check CA-4: routine_person pre=% post=%', v_pre, v_post;
    end if;

    -- person: pre + copias; home_member = person; membership_permission = 17 × no admin
    select count(*) into v_pre from home_migration.pre_person;
    select count(*) into v_post from person;
    if v_post <> v_pre + v_copies then
        raise exception 'backfill_check CA-4: person pre=% post=% copias=%', v_pre, v_post, v_copies;
    end if;

    select count(*) into v_post from home_member;
    if v_post <> (select count(*) from person) then
        raise exception 'backfill_check CA-4: home_member=% ≠ person=%', v_post, (select count(*) from person);
    end if;

    if (select count(*) from membership_permission)
       <> 17 * (select count(*) from home_membership where role = 'member') then
        raise exception 'backfill_check CA-4: membership_permission=% ≠ 17×miembros',
            (select count(*) from membership_permission);
    end if;

    -- audit_log = dedupes + copias + 1 resumen (si hay hogares)
    select count(*) into v_post from audit_log;
    if v_post <> v_ded_c + v_ded_l + v_copies + v_resumen then
        raise exception 'backfill_check CA-4: audit_log=% ≠ dedupes+copias+resumen', v_post;
    end if;

    raise notice 'ok backfill_check CA-4: conteos §13.1 exactos';
end $$;

-- ── CA-5: conjuntos §13.2 idénticos (personas: pre ⊆ post con mismo id) ──
do $$
declare
    t text;
    v_bad text := '';
begin
    -- Tablas con id: conjuntos de ids idénticos
    foreach t in array array['app_user', 'calendar', 'task_list', 'event', 'routine', 'event_user', 'task'] loop
        execute format(
            'select case when exists (select id from %I except select id from home_migration.pre_%I)'
            '          or exists (select id from home_migration.pre_%I except select id from %I)'
            '     then %L else %L end', t, t, t, t, t, '')
        into t;
        if t <> '' then
            v_bad := v_bad || t || ' ';
        end if;
    end loop;
    -- Tablas con PK compuesta: pares clave idénticos
    if exists (select routine_id, routine_date from routine_exception
               except select routine_id, routine_date from home_migration.pre_routine_exception)
       or exists (select routine_id, routine_date from home_migration.pre_routine_exception
                  except select routine_id, routine_date from routine_exception) then
        v_bad := v_bad || 'routine_exception ';
    end if;
    if exists (select routine_id, routine_date, user_id from routine_event_alarm
               except select routine_id, routine_date, user_id from home_migration.pre_routine_event_alarm)
       or exists (select routine_id, routine_date, user_id from home_migration.pre_routine_event_alarm
                  except select routine_id, routine_date, user_id from routine_event_alarm) then
        v_bad := v_bad || 'routine_event_alarm ';
    end if;
    if exists (select routine_id, user_id from routine_user
               except select routine_id, user_id from home_migration.pre_routine_user)
       or exists (select routine_id, user_id from home_migration.pre_routine_user
                  except select routine_id, user_id from routine_user) then
        v_bad := v_bad || 'routine_user ';
    end if;
    if v_bad <> '' then
        raise exception 'backfill_check CA-5: conjuntos distintos pre vs post: %', v_bad;
    end if;
    if exists (select id from home_migration.pre_person except select id from person) then
        raise exception 'backfill_check CA-5: personas pre ⊄ post';
    end if;
    -- Rol por (recurso, usuario): el ganador (owner primero) es idéntico pre vs post
    if exists (
        select 1 from (
            select distinct on (calendar_id, user_id) calendar_id, user_id, role
            from home_migration.pre_calendar_user
            order by calendar_id, user_id, (case when role = 'owner' then 0 else 1 end), id
        ) p
        full outer join (
            select distinct on (calendar_id, user_id) calendar_id, user_id, role
            from calendar_user
            order by calendar_id, user_id, (case when role = 'owner' then 0 else 1 end), id
        ) q using (calendar_id, user_id)
        where p.role is distinct from q.role
    ) then
        raise exception 'backfill_check CA-5: rol por (calendario, usuario) distinto pre vs post';
    end if;
    if exists (
        select 1 from (
            select distinct on (task_list_id, user_id) task_list_id, user_id, role
            from home_migration.pre_task_list_user
            order by task_list_id, user_id, (case when role = 'owner' then 0 else 1 end), id
        ) p
        full outer join (
            select distinct on (task_list_id, user_id) task_list_id, user_id, role
            from task_list_user
            order by task_list_id, user_id, (case when role = 'owner' then 0 else 1 end), id
        ) q using (task_list_id, user_id)
        where p.role is distinct from q.role
    ) then
        raise exception 'backfill_check CA-5: rol por (lista, usuario) distinto pre vs post';
    end if;
    raise notice 'ok backfill_check CA-5: conjuntos §13.2 idénticos (personas pre ⊆ post)';
end $$;

-- ── CA-6: admin(H) = owners exactos (fixture: Ana/Luis/Marta) + fallback reportado ──
do $$
declare
    v_admins text;
begin
    select string_agg(hm.app_user_id::text, ',' order by hm.app_user_id) into v_admins
    from home_membership hm
    where hm.home_id = (select id from home where name = 'Hogar de Ana (y Luis)') and hm.role = 'admin';
    if v_admins <> '101,102,103' then
        raise exception 'backfill_check CA-6: admins del hogar compartido = % (esperado 101,102,103)', v_admins;
    end if;
    if exists (select 1 from home_membership hm
               where hm.home_id = (select id from home where name = 'Hogar de Ana (y Luis)')
                 and hm.app_user_id = 104 and hm.role <> 'member') then
        raise exception 'backfill_check CA-6: Víctor no es member';
    end if;
    -- fallback (CA-6): el singleton sin ACL tiene admin (marcado en el notice de 0013)
    if not exists (select 1 from home_membership hm
                   where hm.home_id = (select id from home where name = 'Hogar de Ana') and hm.role = 'admin') then
        raise exception 'backfill_check CA-6: el singleton sin ACL no tiene admin (fallback)';
    end if;
    raise notice 'ok backfill_check CA-6: admin(H) = owners (fallback en singleton)';
end $$;

-- ── CA-7: calendario huérfano → home archived, sin miembros, en orphan_home_map, eventos intactos ──
do $$
declare
    v_home bigint;
begin
    select home_id into v_home from home_migration.orphan_home_map where kind = 'calendar' and resource_id = 102;
    if v_home is null then
        raise exception 'backfill_check CA-7: calendario 102 sin orphan_home_map';
    end if;
    if not exists (select 1 from home where id = v_home and status = 'archived' and not is_personal) then
        raise exception 'backfill_check CA-7: el home del huérfano no es archived';
    end if;
    if exists (select 1 from home_membership where home_id = v_home) then
        raise exception 'backfill_check CA-7: el home del huérfano tiene miembros';
    end if;
    if (select home_id from calendar where id = 102) is distinct from v_home then
        raise exception 'backfill_check CA-7: calendar 102 sin el home del huérfano';
    end if;
    if not exists (select 1 from event where id = 901 and calendar_id = 102) then
        raise exception 'backfill_check CA-7: el evento del huérfano no existe';
    end if;
    raise notice 'ok backfill_check CA-7: huérfano archived sin miembros con evento intacto';
end $$;

-- ── CA-8: asignación cruzada → copia en el home destino, orig intacta, conteos iguales ──
do $$
declare
    v_copy bigint;
    v_orig_home bigint;
begin
    select copy_person_id into v_copy from home_migration.copy_map where orig_person_id = 101;
    if v_copy is null then
        raise exception 'backfill_check CA-8: sin copia para person 101';
    end if;
    if not exists (select 1 from event_person where event_id = 902 and person_id = v_copy)
       or not exists (select 1 from routine_person where routine_id = 901 and person_id = v_copy) then
        raise exception 'backfill_check CA-8: las asignaciones no apuntan a la copia';
    end if;
    select home_id into v_orig_home from person where id = 101;
    if v_orig_home = (select home_id from person where id = v_copy) then
        raise exception 'backfill_check CA-8: la copia está en el home de la original';
    end if;
    if not exists (select 1 from person where id = 101 and name = 'Persona Ana') then
        raise exception 'backfill_check CA-8: la persona original no está intacta';
    end if;
    raise notice 'ok backfill_check CA-8: copia cruzada (orig % intacta → copia %)', 101, v_copy;
end $$;

-- ── CA-11: dedupe conserva owner y registra la viewer eliminada ──
do $$
begin
    if exists (select 1 from calendar_user where calendar_id = 101 and user_id = 101 and role <> 'owner') then
        raise exception 'backfill_check CA-11: la fila conservada de Ana no es owner';
    end if;
    if (select count(*) from calendar_user where calendar_id = 101 and user_id = 101) <> 1 then
        raise exception 'backfill_check CA-11: ACL de Ana no deduplicada';
    end if;
    if not exists (select 1 from audit_log
                   where action = 'backfill.acl_dedupe' and target_type = 'calendar_user' and target_id = 103) then
        raise exception 'backfill_check CA-11: falta el log de la viewer eliminada (id 103)';
    end if;
    raise notice 'ok backfill_check CA-11: dedupe conserva owner y loggea la viewer (id 103)';
end $$;

-- ── CA-12: default_home_id = única membresía; admin sin permisos; member 17 con home.view ──
do $$
begin
    if exists (select 1 from app_user u
               where u.default_home_id is distinct from
                     (select hm.home_id from home_membership hm where hm.app_user_id = u.id)) then
        raise exception 'backfill_check CA-12: default_home_id ≠ membresía';
    end if;
    if exists (select 1 from membership_permission mp
               join home_membership hm on hm.id = mp.home_membership_id
               where hm.role = 'admin') then
        raise exception 'backfill_check CA-12: admin con filas en membership_permission';
    end if;
    if (select count(*) from membership_permission mp
        join home_membership hm on hm.id = mp.home_membership_id
        where hm.app_user_id = 104) <> 17 then
        raise exception 'backfill_check CA-12: el member no tiene 17 permisos';
    end if;
    if not exists (select 1 from membership_permission mp
                   join home_membership hm on hm.id = mp.home_membership_id
                   where hm.app_user_id = 104 and mp.permission_code = 'home.view') then
        raise exception 'backfill_check CA-12: al member le falta home.view (Q-B)';
    end if;
    raise notice 'ok backfill_check CA-12: defaults y snapshot member legacy (17 con home.view)';
end $$;

-- ── CA-15: nombres §9 (Q-D) ──
do $$
declare
    v_name text;
begin
    -- Regla genérica en todo home activo: 'Hogar de X (y Y)' con los dos admins de menor id
    if exists (
        select 1 from home h
        where h.status = 'active' and h.name <> (
            'Hogar de ' ||
            (select u.name from home_membership hm join app_user u on u.id = hm.app_user_id
             where hm.home_id = h.id and hm.role = 'admin' order by hm.app_user_id limit 1) ||
            coalesce(' (y ' || (select u.name from home_membership hm join app_user u on u.id = hm.app_user_id
                                where hm.home_id = h.id and hm.role = 'admin'
                                order by hm.app_user_id offset 1 limit 1) || ')', ''))
    ) then
        raise exception 'backfill_check CA-15: nombre fuera de la regla §9';
    end if;
    select name into v_name from home where name = 'Hogar de Ana (y Luis)';
    if v_name is null then
        raise exception 'backfill_check CA-15: falta ''Hogar de Ana (y Luis)'' (Ana<Luis<Marta)';
    end if;
    select name into v_name from home where name = 'Hogar de Ana';
    if v_name is null then
        raise exception 'backfill_check CA-15: falta ''Hogar de Ana'' (admin único)';
    end if;
    raise notice 'ok backfill_check CA-15: nombres §9 (''Hogar de Ana (y Luis)'', ''Hogar de Ana'')';
end $$;

-- ── CA-16: toda fila de audit_log de 0013 tiene target_type ──
do $$
begin
    if exists (select 1 from audit_log where action like 'backfill.%' and target_type is null) then
        raise exception 'backfill_check CA-16: audit_log sin target_type';
    end if;
    raise notice 'ok backfill_check CA-16: audit_log con target_type';
end $$;

select 'backfill_check: TODO OK' as resultado;
