-- task_list_position_rollback_check.sql — Ida de la vuelta 0040 → rollback_0040.sql (change
-- lista-prioritaria-inicio). Solo BD local, tras el reset 0001–0040. ci.sh sustituye la línea
-- `-- @ROLLBACK:<fichero>@` por scripts/supabase/rollback/<fichero>. Cada bloque emite 'ok TRx: …' o
-- aborta con 'task_list_position_rollback TRx: …'.
--
-- NO va en transacción: el rollback se confirma de verdad para que ci.sh pase después los checks que usan
-- get_task_lists sobre el esquema revertido. task_list_position_reapply_check.sql vuelve a aplicar 0040.
--
-- TR1 no existe task_list.position ni reorder_task_lists.
-- TR2 get_task_lists vuelve al cuerpo de 0029: una firma, sin 'position', orden por nombre, grants intactos.
-- TR3 rollback_0040 una segunda vez no falla y deja el mismo estado (idempotente).

\set ON_ERROR_STOP 1
do $$
begin
    if inet_server_addr() is not null and host(inet_server_addr()) not in ('127.0.0.1', '::1') then
        raise exception 'task_list_position_rollback_check: solo BD local (socket o loopback); servidor %', host(inet_server_addr());
    end if;
    if not exists (select 1 from information_schema.columns
                    where table_schema = 'public' and table_name = 'task_list' and column_name = 'position') then
        raise exception 'task_list_position_rollback_check: 0040 no está aplicada (falta task_list.position)';
    end if;
end $$;

create function pg_temp.tr_state() returns text
language plpgsql as $$
declare
    v_def text;
begin
    if exists (select 1 from information_schema.columns
                where table_schema = 'public' and table_name = 'task_list' and column_name = 'position') then
        return 'TR1 task_list.position sigue existiendo';
    end if;
    if exists (select 1 from pg_proc where pronamespace = 'public'::regnamespace and proname = 'reorder_task_lists') then
        return 'TR1 reorder_task_lists sigue existiendo';
    end if;
    if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'get_task_lists') <> 1 then
        return 'TR2 get_task_lists no tiene una sola firma';
    end if;
    v_def := pg_get_functiondef('public.get_task_lists()'::regprocedure);
    if v_def like '%position%' or v_def not like '%order by tl.name collate "C")%' then
        return 'TR2 get_task_lists no es el cuerpo de 0029';
    end if;
    if has_function_privilege('anon', 'public.get_task_lists()'::regprocedure, 'execute')
       or not has_function_privilege('authenticated', 'public.get_task_lists()'::regprocedure, 'execute') then
        return 'TR2 EXECUTE de get_task_lists distinto del original (authenticated sí; anon no)';
    end if;
    return null;
end $$;

-- @ROLLBACK:rollback_0040.sql@

do $$
declare
    v_err text := pg_temp.tr_state();
begin
    if v_err is not null then
        raise exception 'task_list_position_rollback %', v_err;
    end if;
    raise notice 'ok TR1: sin task_list.position ni reorder_task_lists';
    raise notice 'ok TR2: get_task_lists con el cuerpo de 0029 (sin position, orden por nombre) y sus grants';
end $$;

-- TR3: segunda pasada.
-- @ROLLBACK:rollback_0040.sql@

do $$
declare
    v_err text := pg_temp.tr_state();
begin
    if v_err is not null then
        raise exception 'task_list_position_rollback TR3 (2.ª pasada): %', v_err;
    end if;
    raise notice 'ok TR3: rollback_0040 dos veces sin error y con el mismo estado';
end $$;
