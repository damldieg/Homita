-- task_list_position_reapply_check.sql — Vuelta de la ida 0040 → rollback_0040.sql → 0040 (change
-- lista-prioritaria-inicio). Solo BD local, después de task_list_position_rollback_check.sql. ci.sh
-- sustituye `-- @MIGRATION:<fichero>@` por supabase/migrations/<fichero>. Cada bloque emite 'ok TAx: …'
-- o aborta con 'task_list_position_reapply TAx: …'. Después ci.sh vuelve a pasar task_list_position_check.
--
-- TA1 de partida está el esquema revertido (sin position ni reorder_task_lists).
-- TA2 tras reaplicar 0040: columna con check, backfill (ninguna lista sin posición; por hogar 1..n por
--     created_at, id), una sola firma de reorder_task_lists con grants y get_task_lists con position.

\set ON_ERROR_STOP 1
do $$
begin
    if inet_server_addr() is not null and host(inet_server_addr()) not in ('127.0.0.1', '::1') then
        raise exception 'task_list_position_reapply_check: solo BD local (socket o loopback); servidor %', host(inet_server_addr());
    end if;
    if exists (select 1 from information_schema.columns
                where table_schema = 'public' and table_name = 'task_list' and column_name = 'position')
       or to_regprocedure('public.reorder_task_lists(bigint[])') is not null then
        raise exception 'task_list_position_reapply TA1: no se parte del esquema revertido por rollback_0040';
    end if;
    raise notice 'ok TA1: se parte del esquema revertido (sin position ni reorder_task_lists)';
end $$;

-- Listas scratch (ids 997501–997503, hogar inexistente 997500; sin FK con replica) para que el backfill
-- tenga datos aunque la BD no traiga listas: created_at inverso al id para distinguir created_at de id.
set session_replication_role = replica;
insert into task_list (id, name, color, token, sort, home_id, created_at, updated_at) values
    (997501, 'TA-1', '#111111', 'ta-tok-1', 'custom', 997500, '2026-03-03 10:00:00', '2026-03-03 10:00:00'),
    (997502, 'TA-2', '#222222', 'ta-tok-2', 'custom', 997500, '2026-03-02 10:00:00', '2026-03-02 10:00:00'),
    (997503, 'TA-3', '#333333', 'ta-tok-3', 'custom', 997500, '2026-03-01 10:00:00', '2026-03-01 10:00:00');
set session_replication_role = default;

-- @MIGRATION:0040_task_list_position.sql@

do $$
declare
    v_lists int;
    v_bad int;
begin
    select count(*) into v_lists from task_list;
    if exists (select 1 from task_list where position is null) then
        raise exception 'task_list_position_reapply TA2: quedan listas sin posición tras el backfill';
    end if;
    select count(*) into v_bad from (
        select id, position, row_number() over (partition by home_id order by created_at, id) as rn from task_list
    ) q where q.position <> q.rn;
    if v_bad <> 0 then
        raise exception 'task_list_position_reapply TA2: % listas con posición distinta de created_at, id', v_bad;
    end if;
    if not exists (select 1 from pg_constraint where conrelid = 'public.task_list'::regclass and contype = 'c'
                    and pg_get_constraintdef(oid) like '%position%') then
        raise exception 'task_list_position_reapply TA2: falta el check de position';
    end if;
    if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'reorder_task_lists') <> 1
       or has_function_privilege('anon', 'public.reorder_task_lists(bigint[])', 'execute')
       or not has_function_privilege('authenticated', 'public.reorder_task_lists(bigint[])', 'execute') then
        raise exception 'task_list_position_reapply TA2: reorder_task_lists (firma o grants)';
    end if;
    if pg_get_functiondef('public.get_task_lists()'::regprocedure) not like '%''position'', tl.position%' then
        raise exception 'task_list_position_reapply TA2: get_task_lists sin position';
    end if;
    if (select string_agg(position::text, ',' order by id) from task_list where id between 997501 and 997503) <> '3,2,1' then
        raise exception 'task_list_position_reapply TA2: backfill de las listas scratch';
    end if;
    set local session_replication_role = replica;
    delete from task_list where id between 997501 and 997503;
    raise notice 'ok TA2: 0040 reaplicada: % listas con backfill 1..n por hogar, check, reorder_task_lists y get_task_lists con position', v_lists;
end $$;
