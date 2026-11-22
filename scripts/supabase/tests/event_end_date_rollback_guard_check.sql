-- event_end_date_rollback_guard_check.sql — Guarda LIFO de rollback_0029 con 0030 aplicada (R2-02 del
-- change prioridad-tarea). Solo BD local. ci.sh lo corre dentro de la ida y vuelta anidada, justo
-- después de rollback_0035 (0037 y 0035 revertidas, 0030 aplicada), y sustituye
-- `-- @ROLLBACK:<fichero>@` por scripts/supabase/rollback/<fichero> (por stdin).
--
-- Sin la guarda, rollback_0029 con 0030 aplicada haría CREATE OR REPLACE de create_event(5 argumentos)
-- y update_event(6) junto a las firmas de 0030 (6 y 8 argumentos, con default): la llamada por nombre
-- sin p_end_date es ambigua y POST /event/create y PATCH /event/update dan 500.
--
-- E0 control: con una sobrecarga de create_event de 5 argumentos añadida a mano (en una transacción que
--    se deshace), la llamada por nombre sin p_end_date falla con 42725. Así E2 no es vacía.
-- E1 rollback_0029 aborta con la guarda de 0030 (ci.sh exige el mensaje en el log) y no cambia nada.
-- E2 tras el intento: una sola firma por RPC (la de 0030), event.end_date y task_list_user.can_edit
--    siguen, y las llamadas por nombre (con y sin p_end_date) resuelven sin ambigüedad.
--
-- El rollback corre con ON_ERROR_STOP desactivado: la guarda aborta la transacción y el resto del fichero
-- falla con «current transaction is aborted» hasta el commit (que hace ROLLBACK). Es ruido esperado. Si
-- la guarda no saltara, el rollback se confirmaría y E2 fallaría (BD local a medias: repetir ci.sh).

\set ON_ERROR_STOP 1
do $$
begin
    if inet_server_addr() is not null and host(inet_server_addr()) not in ('127.0.0.1', '::1') then
        raise exception 'event_end_date_rollback_guard_check: solo BD local (socket o loopback); servidor %', host(inet_server_addr());
    end if;
    if not exists (select 1 from information_schema.columns
                   where table_schema = 'public' and table_name = 'event' and column_name = 'end_date') then
        raise exception 'event_end_date_rollback_guard_check: 0030 no está aplicada (falta event.end_date)';
    end if;
    if exists (select 1 from information_schema.columns
               where table_schema = 'public' and table_name = 'task' and column_name = 'priority')
       or to_regclass('public.client_request') is not null then
        raise exception 'event_end_date_rollback_guard_check: se espera 0037 y 0035 revertidas (correr tras rollback_0035)';
    end if;
end $$;

-- Estado esperado con 0030 (y 0029) aplicadas; null si coincide.
create function pg_temp.e_state() returns text
language plpgsql as $$
declare
    v_sigs text[];
begin
    select array_agg(oid::regprocedure::text order by proname) into v_sigs
      from pg_proc where pronamespace = 'public'::regnamespace and proname in ('create_event', 'update_event');
    if v_sigs is distinct from array['create_event(bigint,text,text,integer,jsonb,text)',
                                     'update_event(bigint,text,text,integer,jsonb,text,text,boolean)'] then
        return format('firmas %s', v_sigs);
    end if;
    if not exists (select 1 from information_schema.columns
                   where table_schema = 'public' and table_name = 'event' and column_name = 'end_date') then
        return 'falta event.end_date';
    end if;
    if not exists (select 1 from information_schema.columns
                   where table_schema = 'public' and table_name = 'task_list_user' and column_name = 'can_edit') then
        return 'falta task_list_user.can_edit';
    end if;
    if to_regprocedure('public.set_calendar_user_access(bigint,bigint,boolean)') is null then
        return 'falta set_calendar_user_access';
    end if;
    return null;
end $$;

-- Llama por nombre y devuelve el SQLSTATE si la resolución falla (42725 ambigua, 42883 inexistente);
-- null si resolvió (cualquier otro error de la propia RPC, p. ej. sin sesión, cuenta como resuelta).
-- Cada llamada va en su subtransacción: no deja efectos.
create function pg_temp.resolve(p_kind text) returns text
language plpgsql as $$
begin
    begin
        case p_kind
            when 'create5' then
                perform create_event(p_calendar_id => -1, p_title => 'EG', p_date_at => '2026-01-01 10:00:00',
                                     p_alarm => null, p_person_ids => null);
            when 'create6' then
                perform create_event(p_calendar_id => -1, p_title => 'EG', p_date_at => '2026-01-01 10:00:00',
                                     p_alarm => null, p_person_ids => null, p_end_date => null);
            when 'update6' then
                perform update_event(p_id => -1, p_title => 'EG', p_date_at => '2026-01-01 10:00:00',
                                     p_alarm => null, p_person_ids => null, p_timezone => null);
            when 'update8' then
                perform update_event(p_id => -1, p_title => 'EG', p_date_at => '2026-01-01 10:00:00',
                                     p_alarm => null, p_person_ids => null, p_timezone => null,
                                     p_end_date => null, p_end_date_set => false);
        end case;
    exception
        when ambiguous_function or undefined_function then
            return sqlstate;
        when others then
            null;
    end;
    return null;
end $$;

-- ── E0: control de la ambigüedad ──
begin;
create function public.create_event(p_calendar_id bigint, p_title text, p_date_at text, p_alarm integer, p_person_ids jsonb)
returns json language sql as $$ select null::json $$;
do $$
begin
    if pg_temp.resolve('create5') is distinct from '42725' then
        raise exception 'event_end_date_rollback_guard E0: la llamada por nombre no fue ambigua con dos sobrecargas';
    end if;
    raise notice 'ok E0: con dos sobrecargas de create_event la llamada por nombre sin p_end_date es ambigua (42725)';
end $$;
rollback;

-- ── E1: rollback_0029 con 0030 aplicada ──
\set ON_ERROR_STOP 0
\echo '-- E1: rollback_0029 con 0030 aplicada (se espera la guarda y errores de transacción abortada)'
-- @ROLLBACK:rollback_0029.sql@
rollback;
\set ON_ERROR_STOP 1

do $$
declare
    v_err text := pg_temp.e_state();
begin
    if v_err is not null then
        raise exception 'event_end_date_rollback_guard E1: rollback_0029 cambió el esquema: %', v_err;
    end if;
    raise notice 'ok E1: rollback_0029 abortó por la guarda de 0030 y el esquema sigue con 0030';
end $$;

-- ── E2: las llamadas por nombre resuelven ──
do $$
declare
    k text;
    v text;
begin
    foreach k in array array['create5', 'create6', 'update6', 'update8'] loop
        v := pg_temp.resolve(k);
        if v is not null then
            raise exception 'event_end_date_rollback_guard E2: % no resolvió (SQLSTATE %)', k, v;
        end if;
    end loop;
    raise notice 'ok E2: una firma por RPC tras el intento; create_event y update_event por nombre resuelven';
end $$;
