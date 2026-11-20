-- assistant_usage_check.sql — Tope diario y medición de tokens de Kito (0036_assistant_usage.sql).
-- Solo BD local, tras el reset 0001–0036:  psql -v ON_ERROR_STOP=1 -f assistant_usage_check.sql
-- Cada bloque DO emite 'ok Ux: …' o aborta con 'assistant_usage Ux: …'.
--
-- Fixture (ids 993001–993002, auth_uid …0931–…0932): dos usuarios sin hogar compartido.
--
-- U1 50 consumos permitidos (used 1..50), el 51 → allowed=false sin sumar; la fila queda en 50.
-- U2 el contador es por usuario: el otro usuario empieza en 1.
-- U3 el día es la fecha local de la zona pedida; zona inválida o nula → 'Invalid timezone'.
-- U4 record_usage suma tokens; p_refund devuelve el mensaje (y libera hueco bajo el tope).
-- U5 tokens negativos o nulos → 'Invalid usage'; día sin fila → 'Not Found'; usuario inexistente → 'Not Found'.
-- U6 permisos: tabla con RLS sin policies y sin privilegios para anon/authenticated; RPC solo service_role.
-- U7 0 filas scratch al terminar.

\set ON_ERROR_STOP 1
do $$
begin
    if inet_server_addr() is not null and host(inet_server_addr()) not in ('127.0.0.1', '::1') then
        raise exception 'assistant_usage_check: solo BD local (socket o loopback); servidor %', host(inet_server_addr());
    end if;
end $$;

create function pg_temp.clean() returns void
language plpgsql as $$
begin
    set local session_replication_role = replica;
    delete from assistant_usage where app_user_id between 993001 and 993002;
    delete from app_user where id between 993001 and 993002;
    delete from auth.users where id in (
        '00000000-0000-4000-8000-000000000931', '00000000-0000-4000-8000-000000000932');
end $$;

-- Ejecuta p_sql y exige el error p_msg (sqlstate p_state).
create function pg_temp.fails(p_label text, p_sql text, p_state text, p_msg text) returns void
language plpgsql as $$
begin
    execute p_sql;
    raise exception 'assistant_usage %: no falló: %', p_label, p_sql;
exception when others then
    if sqlstate <> p_state or sqlerrm <> p_msg then
        raise exception 'assistant_usage %: % % (esperado % %)', p_label, sqlstate, sqlerrm, p_state, p_msg;
    end if;
end $$;

select pg_temp.clean();

-- ── Fixture ──
set session_replication_role = replica;
insert into auth.users (id, email, raw_user_meta_data) values
    ('00000000-0000-4000-8000-000000000931', 'au-a@check.homita.example', '{"name":"AU-A"}'),
    ('00000000-0000-4000-8000-000000000932', 'au-b@check.homita.example', '{"name":"AU-B"}');
insert into app_user (id, auth_uid, name, email) values
    (993001, '00000000-0000-4000-8000-000000000931', 'AU-A', 'au-a@check.homita.example'),
    (993002, '00000000-0000-4000-8000-000000000932', 'AU-B', 'au-b@check.homita.example');
set session_replication_role = default;

set role service_role;

do $$
declare
    r json;
    i int;
begin
    for i in 1..50 loop
        r := assistant_consume(993001, 'Europe/Madrid');
        if (r ->> 'allowed')::boolean is not true or (r ->> 'used')::int <> i or (r ->> 'limit')::int <> 50 then
            raise exception 'assistant_usage U1: consumo % → %', i, r;
        end if;
    end loop;
    r := assistant_consume(993001, 'Europe/Madrid');
    if (r ->> 'allowed')::boolean is not false or (r ->> 'used')::int <> 50 then
        raise exception 'assistant_usage U1: el 51 → %', r;
    end if;
    if (select messages from assistant_usage where app_user_id = 993001) <> 50 then
        raise exception 'assistant_usage U1: la fila no quedó en 50';
    end if;
    raise notice 'ok U1: 50 permitidos, el 51 denegado sin sumar';
end $$;

do $$
declare r json;
begin
    r := assistant_consume(993002, 'Europe/Madrid');
    if (r ->> 'allowed')::boolean is not true or (r ->> 'used')::int <> 1 then
        raise exception 'assistant_usage U2: otro usuario → %', r;
    end if;
    raise notice 'ok U2: contador por usuario';
end $$;

do $$
declare r json;
begin
    r := assistant_consume(993002, 'Pacific/Kiritimati');
    if (r ->> 'day')::date <> (now() at time zone 'Pacific/Kiritimati')::date then
        raise exception 'assistant_usage U3: día % no es la fecha local', r ->> 'day';
    end if;
    perform pg_temp.fails('U3 zona inválida', $q$select assistant_consume(993002, 'Marte/Olympus')$q$, 'P0001', 'Invalid timezone');
    perform pg_temp.fails('U3 zona nula', $q$select assistant_consume(993002, null)$q$, 'P0001', 'Invalid timezone');
    raise notice 'ok U3: día local según la zona; zona inválida o nula rechazada';
end $$;

do $$
declare
    v_day date := (now() at time zone 'Europe/Madrid')::date;
    u assistant_usage;
    r json;
begin
    perform assistant_record_usage(993001, v_day, 12000, 800, 3000, 500);
    perform assistant_record_usage(993001, v_day, 1000, 200);
    select * into u from assistant_usage where app_user_id = 993001 and day = v_day;
    if u.input_tokens <> 13000 or u.output_tokens <> 1000 or u.cache_read_tokens <> 3000
       or u.cache_write_tokens <> 500 or u.messages <> 50 then
        raise exception 'assistant_usage U4: sumas % % % % %', u.input_tokens, u.output_tokens,
            u.cache_read_tokens, u.cache_write_tokens, u.messages;
    end if;
    perform assistant_record_usage(993001, v_day, 0, 0, 0, 0, true);
    if (select messages from assistant_usage where app_user_id = 993001 and day = v_day) <> 49 then
        raise exception 'assistant_usage U4: el refund no devolvió el mensaje';
    end if;
    r := assistant_consume(993001, 'Europe/Madrid');
    if (r ->> 'allowed')::boolean is not true or (r ->> 'used')::int <> 50 then
        raise exception 'assistant_usage U4: tras refund → %', r;
    end if;
    raise notice 'ok U4: tokens sumados; refund libera hueco';
end $$;

do $$
begin
    perform pg_temp.fails('U5 negativo', format('select assistant_record_usage(993001, %L, -1, 0)',
        (now() at time zone 'Europe/Madrid')::date), 'P0001', 'Invalid usage');
    perform pg_temp.fails('U5 nulo', format('select assistant_record_usage(993001, %L, 1, null)',
        (now() at time zone 'Europe/Madrid')::date), 'P0001', 'Invalid usage');
    perform pg_temp.fails('U5 sin fila', $q$select assistant_record_usage(993001, '2000-01-01', 1, 1)$q$, 'P0002', 'Not Found');
    perform pg_temp.fails('U5 usuario', $q$select assistant_consume(999999999, 'Europe/Madrid')$q$, 'P0002', 'Not Found');
    raise notice 'ok U5: entradas inválidas rechazadas';
end $$;

reset role;

do $$
declare
    rl text;
begin
    if not (select relrowsecurity from pg_class where oid = 'assistant_usage'::regclass) then
        raise exception 'assistant_usage U6: RLS desactivada';
    end if;
    if exists (select 1 from pg_policies where tablename = 'assistant_usage') then
        raise exception 'assistant_usage U6: hay policies';
    end if;
    foreach rl in array array['anon', 'authenticated'] loop
        if has_table_privilege(rl, 'assistant_usage', 'select') or has_table_privilege(rl, 'assistant_usage', 'insert')
           or has_table_privilege(rl, 'assistant_usage', 'update') or has_table_privilege(rl, 'assistant_usage', 'delete') then
            raise exception 'assistant_usage U6: % tiene privilegios en la tabla', rl;
        end if;
        if has_function_privilege(rl, 'assistant_consume(bigint, text)', 'execute')
           or has_function_privilege(rl, 'assistant_record_usage(bigint, date, bigint, bigint, bigint, bigint, boolean)', 'execute')
           or has_function_privilege(rl, 'fn_assistant_daily_limit()', 'execute') then
            raise exception 'assistant_usage U6: % puede ejecutar las RPC', rl;
        end if;
    end loop;
    if not has_function_privilege('service_role', 'assistant_consume(bigint, text)', 'execute') then
        raise exception 'assistant_usage U6: service_role sin EXECUTE';
    end if;
    raise notice 'ok U6: solo service_role';
end $$;

select pg_temp.clean();

do $$
begin
    if exists (select 1 from assistant_usage where app_user_id between 993001 and 993002)
       or exists (select 1 from app_user where id between 993001 and 993002) then
        raise exception 'assistant_usage U7: quedan filas scratch';
    end if;
    raise notice 'ok U7: 0 filas scratch';
end $$;
