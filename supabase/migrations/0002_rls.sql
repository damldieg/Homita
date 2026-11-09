-- 0002_rls.sql — RLS espejo de la autorización PHP (fase 1: solo lectura).
--
-- Helpers SECURITY DEFINER (R1-01): las policies los usan SOLO a ellos — ninguna policy contiene
-- subconsultas sobre tablas con RLS — para eliminar la `infinite recursion` de la matriz previa
-- (auto-referencia de calendar_user/task_list_user y ciclo app_user ↔ calendar_user).
-- `REVOKE EXECUTE FROM PUBLIC, anon` + `GRANT EXECUTE TO authenticated`.
-- Sin policies de INSERT/UPDATE/DELETE: `authenticated` no escribe (hoy las escrituras viven en
-- PHP); `anon` sin grants sobre las tablas ni las secuencias.

create or replace function fn_my_user_id() returns bigint
language sql stable security definer set search_path = public as $$
    select id from app_user where auth_uid = auth.uid()
$$;

create or replace function fn_my_calendar_ids() returns bigint[]
language sql stable security definer set search_path = public as $$
    select coalesce(array_agg(calendar_id), array[]::bigint[])
    from calendar_user where user_id = fn_my_user_id()
$$;

create or replace function fn_my_task_list_ids() returns bigint[]
language sql stable security definer set search_path = public as $$
    select coalesce(array_agg(task_list_id), array[]::bigint[])
    from task_list_user where user_id = fn_my_user_id()
$$;

-- Mi id ∪ los usuarios que comparten ≥1 calendario conmigo: exactamente Person::VISIBLE (la
-- "familia" de Homita (modelo compatible Planify-Backend, histórico); no existe tabla family).
create or replace function fn_family_user_ids() returns bigint[]
language sql stable security definer set search_path = public as $$
    select coalesce(array_agg(distinct member), array[]::bigint[])
    from (
        select fn_my_user_id() as member
        union
        select cu2.user_id
        from calendar_user cu1
        inner join calendar_user cu2 on cu2.calendar_id = cu1.calendar_id
        where cu1.user_id = fn_my_user_id()
    ) members
    where member is not null
$$;

-- R1-11: los lookups que devolvían el calendar_id de eventos/rutinas (también los de otras
-- familias: fuga de metadatos vía PostgREST) se sustituyen por helpers booleanos: solo responden
-- si el elemento está en MIS calendarios (guardia fn_my_calendar_ids), sin revelar ids ajenos.
create or replace function fn_event_in_my_calendars(p_event_id bigint) returns boolean
language sql stable security definer set search_path = public as $$
    select exists (
        select 1 from event
        where id = p_event_id and calendar_id = any (fn_my_calendar_ids())
    )
$$;

create or replace function fn_routine_in_my_calendars(p_routine_id bigint) returns boolean
language sql stable security definer set search_path = public as $$
    select exists (
        select 1 from routine
        where id = p_routine_id and calendar_id = any (fn_my_calendar_ids())
    )
$$;

drop function if exists fn_event_calendar_id(bigint);
drop function if exists fn_routine_calendar_id(bigint);

revoke execute on function fn_my_user_id() from public, anon;
revoke execute on function fn_my_calendar_ids() from public, anon;
revoke execute on function fn_my_task_list_ids() from public, anon;
revoke execute on function fn_family_user_ids() from public, anon;
revoke execute on function fn_event_in_my_calendars(bigint) from public, anon;
revoke execute on function fn_routine_in_my_calendars(bigint) from public, anon;
grant execute on function fn_my_user_id() to authenticated;
grant execute on function fn_my_calendar_ids() to authenticated;
grant execute on function fn_my_task_list_ids() to authenticated;
grant execute on function fn_family_user_ids() to authenticated;
grant execute on function fn_event_in_my_calendars(bigint) to authenticated;
grant execute on function fn_routine_in_my_calendars(bigint) to authenticated;

alter table app_user enable row level security;
alter table calendar enable row level security;
alter table calendar_user enable row level security;
alter table event enable row level security;
alter table event_user enable row level security;
alter table task_list enable row level security;
alter table task_list_user enable row level security;
alter table task enable row level security;
alter table routine enable row level security;
alter table routine_user enable row level security;
alter table routine_exception enable row level security;
alter table routine_event_alarm enable row level security;
alter table person enable row level security;
alter table event_person enable row level security;
alter table routine_person enable row level security;

create policy app_user_select on app_user for select to authenticated
    using (id = any (fn_family_user_ids()));

create policy calendar_select on calendar for select to authenticated
    using (id = any (fn_my_calendar_ids()));

create policy calendar_user_select on calendar_user for select to authenticated
    using (user_id = fn_my_user_id() or calendar_id = any (fn_my_calendar_ids()));

create policy event_select on event for select to authenticated
    using (calendar_id = any (fn_my_calendar_ids()));

create policy event_user_select on event_user for select to authenticated
    using (user_id = fn_my_user_id() or fn_event_in_my_calendars(event_id));

create policy task_list_select on task_list for select to authenticated
    using (id = any (fn_my_task_list_ids()));

create policy task_list_user_select on task_list_user for select to authenticated
    using (user_id = fn_my_user_id() or task_list_id = any (fn_my_task_list_ids()));

create policy task_select on task for select to authenticated
    using (task_list_id = any (fn_my_task_list_ids()));

create policy routine_select on routine for select to authenticated
    using (calendar_id = any (fn_my_calendar_ids()));

create policy routine_user_select on routine_user for select to authenticated
    using (user_id = fn_my_user_id() or fn_routine_in_my_calendars(routine_id));

create policy routine_exception_select on routine_exception for select to authenticated
    using (fn_routine_in_my_calendars(routine_id));

create policy routine_event_alarm_select on routine_event_alarm for select to authenticated
    using (fn_routine_in_my_calendars(routine_id));

create policy person_select on person for select to authenticated
    using (user_id = any (fn_family_user_ids()));

create policy event_person_select on event_person for select to authenticated
    using (fn_event_in_my_calendars(event_id));

create policy routine_person_select on routine_person for select to authenticated
    using (fn_routine_in_my_calendars(routine_id));

-- anon sin acceso a los datos (las policies ya lo cubren; esto cierra los grants por defecto).
revoke all on all tables in schema public from anon;
revoke all on all sequences in schema public from anon;
grant select on all tables in schema public to authenticated;
