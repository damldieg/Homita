-- 0015_home_constraints.sql — Constraints del modelo Home (fase 1.3; spec 1.1 §6, diseno §1.4,
-- §3.4; cuerpos aprobados en plan 1.3 r2 §Cuerpos). Tras el backfill (0013) y la compatibilidad
-- (0014): unicidades y FK compuestas (H.1), NOT NULL (H.2), trigger anti-hogar-sin-admin
-- diferido (H.3), trigger de asignaciones persona↔recurso (iv) y fn_sync_assignments por
-- diferencia (v). NO contiene dedupe de ACL (ya está en 0013 S3).
--
-- Notas:
-- * D-a: 'Not Allowed' → 42501 en fn_check_home_has_admin (convención 0005/0006/0008/0011).
-- * (iv) valida que la persona asignada sea activa y del mismo hogar que el recurso; no revalida
--   UPDATE sin cambio de person_id (histórico, diseno §1.4).
-- * (v) sustituye 0011:56-92 conservando sus pasadas 1 y 2; solo las filas NUEVAS disparan (iv).
-- * Sin rollback SQL tras esta migración (R4): solo volcado.

-- ─────────────────────── (i) Unicidades y FK compuestas (§6.H.1) ───────────────────────

alter table calendar add constraint calendar_id_home_key unique (id, home_id);
alter table task_list add constraint task_list_id_home_key unique (id, home_id);
alter table calendar_user add constraint calendar_user_calendar_user_key unique (calendar_id, user_id);
alter table task_list_user add constraint task_list_user_task_list_user_key unique (task_list_id, user_id);

alter table calendar_user add constraint calendar_user_home_fk
    foreign key (home_id, user_id) references home_membership (home_id, app_user_id) on delete cascade;
alter table calendar_user add constraint calendar_user_calendar_fk
    foreign key (calendar_id, home_id) references calendar (id, home_id) on delete cascade;
alter table task_list_user add constraint task_list_user_home_fk
    foreign key (home_id, user_id) references home_membership (home_id, app_user_id) on delete cascade;
alter table task_list_user add constraint task_list_user_task_list_fk
    foreign key (task_list_id, home_id) references task_list (id, home_id) on delete cascade;

alter table app_user add constraint app_user_default_home_fk
    foreign key (default_home_id, id) references home_membership (home_id, app_user_id)
    on delete set null (default_home_id);

alter table person add constraint person_home_member_key unique (home_member_id);
alter table person add constraint person_home_member_fk
    foreign key (home_member_id, home_id) references home_member (id, home_id);

-- ─────────────────────── (ii) NOT NULL (§6.H.2) ───────────────────────

alter table calendar alter column home_id set not null;
alter table task_list alter column home_id set not null;
alter table calendar_user alter column home_id set not null;
alter table task_list_user alter column home_id set not null;
alter table person alter column home_id set not null;
alter table person alter column home_member_id set not null;

-- ─────────────── (iii) Anti-hogar-sin-admin DEFERRABLE (§6.H.3; D-a: 42501) ───────────────
-- Invariante §3.3: un hogar 'active' tiene ≥1 home_membership admin, comprobado al COMMIT
-- (FOR UPDATE sobre home). Hogar borrado en la misma transacción o archivado: fuera.

create or replace function fn_check_home_has_admin() returns trigger
language plpgsql security definer set search_path = public as $$
declare
    v_home bigint;
    v_status home_status;
begin
    if tg_op = 'DELETE' then
        v_home := old.home_id;
    elsif tg_table_name = 'home' then
        v_home := new.id;
    else
        v_home := new.home_id;
    end if;

    select h.status into v_status from home h where h.id = v_home for update;
    if not found or v_status <> 'active' then
        return null;  -- hogar borrado en la transacción o archivado: fuera del invariante
    end if;

    if not exists (select 1 from home_membership hm where hm.home_id = v_home and hm.role = 'admin') then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    return null;
end $$;

create constraint trigger home_membership_has_admin
    after insert or update of role or delete on home_membership
    deferrable initially deferred
    for each row execute function fn_check_home_has_admin();

create constraint trigger home_status_has_admin
    after insert or update of status on home
    deferrable initially deferred
    for each row execute function fn_check_home_has_admin();

revoke execute on function fn_check_home_has_admin() from public, anon, authenticated;

-- ─────────────── (iv) Trigger de asignaciones persona↔recurso (diseno §1.4, §3.4) ───────────────
-- Toda asignación NUEVA exige persona activa y del mismo hogar que el recurso. UPDATE sin cambio
-- de person_id no revalida (histórico).

create or replace function fn_check_assignment_person() returns trigger
language plpgsql security definer set search_path = public as $$
declare
    v_res_home bigint;
    v_ok boolean;
begin
    if tg_op = 'UPDATE' and new.person_id = old.person_id then
        return new;  -- sin cambio de persona: no revalidar (histórico, diseno §1.4)
    end if;
    if tg_table_name = 'event_person' then
        select c.home_id into v_res_home from event e join calendar c on c.id = e.calendar_id where e.id = new.event_id;
    else
        select c.home_id into v_res_home from routine r join calendar c on c.id = r.calendar_id where r.id = new.routine_id;
    end if;
    select exists (
        select 1 from person p join home_member hm on hm.id = p.home_member_id
        where p.id = new.person_id and p.home_id = v_res_home and hm.status = 'active'
    ) into v_ok;
    if not coalesce(v_ok, false) then
        raise exception 'Invalid person' using errcode = 'P0001';
    end if;
    return new;
end $$;
create trigger event_person_check before insert or update of person_id on event_person
    for each row execute function fn_check_assignment_person();
create trigger routine_person_check before insert or update of person_id on routine_person
    for each row execute function fn_check_assignment_person();
revoke execute on function fn_check_assignment_person() from public, anon, authenticated;

-- ─────────────── (v) fn_sync_assignments por diferencia (diseno §1.4) ───────────────
-- Sustituye 0011:56-92 (sus pasadas 1 y 2 se conservan sin cambio): en vez de delete-all +
-- insert-all, borra solo los ausentes e inserta solo los nuevos → update_event/update_routine no
-- revalidan personas ya asignada (inactivas incluidas) y el trigger (iv) solo ve filas nuevas.

create or replace function fn_sync_assignments(p_table text, p_column text, p_id bigint, p_person_ids jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare
    v_bad boolean;
begin
    -- Pasada 1 (solo jsonb, sin cast): la lista es un array de enteros positivos en rango bigint
    if p_person_ids is not null then
        if jsonb_typeof(p_person_ids) <> 'array' then
            raise exception 'Invalid person' using errcode = 'P0001';
        end if;
        if exists (
            select 1 from jsonb_array_elements(p_person_ids) e
            where jsonb_typeof(e) <> 'number'
               or (e #>> '{}') !~ '^[1-9][0-9]{0,17}$'
        ) then
            raise exception 'Invalid person' using errcode = 'P0001';
        end if;
    end if;
    -- Pasada 2 (cast ::bigint seguro): solo filas nuevas; la persona debe existir y ser visible
    if p_person_ids is not null then
        execute format(
            'select exists (select 1 from jsonb_array_elements($1) e' ||
            ' where not exists (select 1 from %I t where t.%I = $2 and t.person_id = (e #>> ''{}'')::bigint)' ||
            ' and not exists (select 1 from person p where p.id = (e #>> ''{}'')::bigint' ||
            ' and p.user_id = any (fn_family_user_ids())))',
            p_table, p_column)
        into v_bad using p_person_ids, p_id;
        if v_bad then
            raise exception 'Invalid person' using errcode = 'P0001';
        end if;
    end if;
    -- Borrado por diferencia: solo las ausentes de la lista (null = '[]' → borra todo)
    execute format(
        'delete from %I where %I = $1 and person_id <> all' ||
        ' (select (value #>> ''{}'')::bigint from jsonb_array_elements(coalesce($2, ''[]''::jsonb)))',
        p_table, p_column)
    using p_id, p_person_ids;
    -- Inserción solo de nuevas: solo ellas disparan el trigger (iv)
    execute format(
        'insert into %I (%I, person_id) select $1, s.x from' ||
        ' (select (value #>> ''{}'')::bigint as x from jsonb_array_elements(coalesce($2, ''[]''::jsonb))) s' ||
        ' where not exists (select 1 from %I t where t.%I = $1 and t.person_id = s.x)',
        p_table, p_column, p_table, p_column)
    using p_id, p_person_ids;
end $$;
