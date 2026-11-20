-- 0036_assistant_usage.sql — change kito-asistente (respuestas de Damian del 2026-11-20): tope diario de
-- mensajes a Kito por usuario y medición de tokens para conocer el coste real por hogar.
--
-- * Tabla `assistant_usage(app_user_id, day, messages, input_tokens, output_tokens, cache_read_tokens,
--   cache_write_tokens, updated_at)`, PK (app_user_id, day). `day` es la fecha local del usuario (zona
--   IANA que manda la app). RLS activada sin policies y sin grants a anon/authenticated (patrón D-014).
-- * Tope en un solo sitio: fn_assistant_daily_limit() = 50 (los tiers lo cambiarán aquí).
-- * Las RPC son SOLO de service_role: las llama la Edge Function `asistente` con el app_user.id que
--   deriva del JWT verificado. Un usuario no puede tocar su contador ni sus tokens desde PostgREST.
--   - assistant_consume(p_app_user_id, p_timezone) suma 1 mensaje de forma atómica si cabe en el tope
--     y devuelve {allowed, used, limit, day}. Con el tope alcanzado no suma (allowed = false).
--   - assistant_record_usage(p_app_user_id, p_day, p_input, p_output, p_cache_read, p_cache_write,
--     p_refund) suma los tokens de la respuesta; p_refund = true devuelve el mensaje (fallo del modelo:
--     no cuenta para el tope).
-- Errores: zona inválida → 'Invalid timezone' P0001; tokens negativos → 'Invalid usage' P0001.
-- Rollback: scripts/supabase/rollback/rollback_0036.sql.

begin;

-- ─────────────────── (a) Tabla de uso diario ───────────────────

create table assistant_usage (
    app_user_id bigint not null references app_user (id) on delete cascade,
    day date not null,
    messages integer not null default 0 check (messages >= 0),
    input_tokens bigint not null default 0 check (input_tokens >= 0),
    output_tokens bigint not null default 0 check (output_tokens >= 0),
    cache_read_tokens bigint not null default 0 check (cache_read_tokens >= 0),
    cache_write_tokens bigint not null default 0 check (cache_write_tokens >= 0),
    updated_at timestamptz not null default now(),
    primary key (app_user_id, day)
);

alter table assistant_usage enable row level security;
revoke all on table assistant_usage from public, anon, authenticated;
grant select, insert, update on table assistant_usage to service_role;

-- ─────────────────── (b) Tope diario ───────────────────

create function fn_assistant_daily_limit() returns integer
language sql immutable as $$ select 50 $$;

revoke execute on function fn_assistant_daily_limit() from public, anon, authenticated;
grant execute on function fn_assistant_daily_limit() to service_role;

-- ─────────────────── (c) Consumir un mensaje ───────────────────

create function assistant_consume(p_app_user_id bigint, p_timezone text) returns json
language plpgsql security definer set search_path = public as $$
declare
    v_limit integer := fn_assistant_daily_limit();
    v_day date;
    v_used integer;
begin
    if p_timezone is null or not exists (select 1 from pg_timezone_names where name = p_timezone) then
        raise exception 'Invalid timezone' using errcode = 'P0001';
    end if;
    if p_app_user_id is null or not exists (select 1 from app_user where id = p_app_user_id) then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    v_day := (now() at time zone p_timezone)::date;
    -- Atómico: el upsert solo suma si aún cabe; con el tope alcanzado no devuelve fila.
    insert into assistant_usage as u (app_user_id, day, messages) values (p_app_user_id, v_day, 1)
    on conflict (app_user_id, day) do update set messages = u.messages + 1, updated_at = now()
        where u.messages < v_limit
    returning u.messages into v_used;
    if v_used is null then
        return json_build_object('allowed', false, 'used', v_limit, 'limit', v_limit, 'day', v_day);
    end if;
    return json_build_object('allowed', true, 'used', v_used, 'limit', v_limit, 'day', v_day);
end $$;

revoke execute on function assistant_consume(bigint, text) from public, anon, authenticated;
grant execute on function assistant_consume(bigint, text) to service_role;

-- ─────────────────── (d) Registrar tokens (y devolver el mensaje si falló) ───────────────────

create function assistant_record_usage(p_app_user_id bigint, p_day date, p_input bigint, p_output bigint,
                                       p_cache_read bigint default 0, p_cache_write bigint default 0,
                                       p_refund boolean default false) returns void
language plpgsql security definer set search_path = public as $$
begin
    if p_input < 0 or p_output < 0 or p_cache_read < 0 or p_cache_write < 0
       or p_input is null or p_output is null or p_cache_read is null or p_cache_write is null then
        raise exception 'Invalid usage' using errcode = 'P0001';
    end if;
    update assistant_usage set
        input_tokens = input_tokens + p_input,
        output_tokens = output_tokens + p_output,
        cache_read_tokens = cache_read_tokens + p_cache_read,
        cache_write_tokens = cache_write_tokens + p_cache_write,
        messages = case when coalesce(p_refund, false) then greatest(messages - 1, 0) else messages end,
        updated_at = now()
    where app_user_id = p_app_user_id and day = p_day;
    if not found then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
end $$;

revoke execute on function assistant_record_usage(bigint, date, bigint, bigint, bigint, bigint, boolean)
    from public, anon, authenticated;
grant execute on function assistant_record_usage(bigint, date, bigint, bigint, bigint, bigint, boolean)
    to service_role;

commit;

notify pgrst, 'reload schema';
