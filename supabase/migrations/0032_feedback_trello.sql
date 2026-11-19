-- 0032_feedback_trello.sql — change feedback-trello-gate (D-021): columnas Trello en `backlog`, reserva de
-- feedback y RPC de escritura final atómica para la Edge Function `procesar-feedback`.
--
-- Contexto: `public.feedback` y `public.backlog` NO tienen DDL en este repo; solo existen en prod.
--
-- Semántica (aditiva, idempotente):
--   * Guard: si falta `public.feedback` o `public.backlog` (local/CI) avisa y sale sin crear nada.
--   * backlog.trello_card_id / trello_card_url (text) + índice único parcial sobre trello_card_id.
--   * feedback.procesando_desde (timestamptz null): la función reserva la fila con un UPDATE
--     condicional (`estado = 'pendiente' and procesando_desde is null`). `estado` no cambia de dominio
--     {pendiente, procesado, error}. Fila atascada = pendiente con procesando_desde no nulo.
--   * public.homita_feedback_finalize(...): en una transacción bloquea la fila reservada, inserta en
--     backlog (crear: votos por defecto; vincular: votos = 2) con upsert atómico del voto por
--     trello_card_id y deja el feedback en `procesado` con su backlog_id. Solo la ejecuta service_role.
--   * El DDL va en `execute` dinámico: sobre tablas inexistentes no se podría ni parsear.
-- Reversa (no automática): scripts/supabase/rollback/rollback_0032.sql.

do $$
begin
    if to_regclass('public.feedback') is null or to_regclass('public.backlog') is null then
        raise notice '0032: public.feedback o public.backlog no existe (local/CI); sin cambios';
        return;
    end if;

    execute 'alter table public.backlog
                 add column if not exists trello_card_id text,
                 add column if not exists trello_card_url text';
    execute 'create unique index if not exists backlog_trello_card_id_key
                 on public.backlog (trello_card_id) where trello_card_id is not null';
    execute 'alter table public.feedback add column if not exists procesando_desde timestamptz';

    execute $f$
        create or replace function public.homita_feedback_finalize(
            p_feedback_id bigint,
            p_crear boolean,
            p_card_id text,
            p_card_url text,
            p_titulo text,
            p_descripcion text)
        returns bigint
        language plpgsql
        security invoker
        set search_path = ''
        as $body$
        declare
            v_fb record;
            v_id bigint;
        begin
            -- Solo finaliza quien reservó: fila pendiente con procesando_desde, bloqueada hasta el commit.
            select f.id, f.seccion, f.subseccion, f.tipo
              into v_fb
              from public.feedback f
             where f.id = p_feedback_id
               and f.estado = 'pendiente'
               and f.procesando_desde is not null
               for update;
            if not found then
                raise exception 'homita_feedback_finalize: feedback % no reservado o ya procesado', p_feedback_id;
            end if;
            if p_crear is null or p_card_id is null or btrim(p_card_id) = '' then
                raise exception 'homita_feedback_finalize: p_crear y p_card_id son obligatorios';
            end if;

            if p_crear then
                insert into public.backlog (titulo, descripcion, seccion, subseccion, tipo,
                                            trello_card_id, trello_card_url)
                values (p_titulo, p_descripcion, v_fb.seccion, v_fb.subseccion, v_fb.tipo,
                        p_card_id, p_card_url)
                on conflict (trello_card_id) where trello_card_id is not null
                do update set votos = public.backlog.votos + 1
                returning id into v_id;
            else
                -- Vincular a una tarjeta sin fila: nace con 2 votos (la tarjeta original + este reporte).
                insert into public.backlog (titulo, descripcion, seccion, subseccion, tipo, votos,
                                            trello_card_id, trello_card_url)
                values (p_titulo, p_descripcion, v_fb.seccion, v_fb.subseccion, v_fb.tipo, 2,
                        p_card_id, p_card_url)
                on conflict (trello_card_id) where trello_card_id is not null
                do update set votos = public.backlog.votos + 1
                returning id into v_id;
            end if;

            update public.feedback
               set estado = 'procesado', backlog_id = v_id
             where id = p_feedback_id;
            return v_id;
        end
        $body$
    $f$;

    -- Los default privileges de `public` dan EXECUTE a anon/authenticated: revoke explícito.
    execute 'revoke all on function public.homita_feedback_finalize(bigint, boolean, text, text, text, text)
                 from public, anon, authenticated';
    execute 'grant execute on function public.homita_feedback_finalize(bigint, boolean, text, text, text, text)
                 to service_role';
end $$;
