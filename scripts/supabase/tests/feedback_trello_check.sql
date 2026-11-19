-- feedback_trello_check.sql — Migración 0032_feedback_trello.sql (change feedback-trello-gate).
-- Solo BD local, tras el reset. ci.sh sustituye cada línea `-- @MIGRATION:<fichero>@` por el texto de
-- supabase/migrations/<fichero> y cada `-- @ROLLBACK:<fichero>@` por scripts/supabase/rollback/<fichero>
-- (psql corre dentro del contenedor y recibe stdin: no puede leer ficheros del host).
-- Cada bloque emite 'ok Bx: …' o aborta con 'feedback_trello Bx: …'.
--
-- B1 local: no existen feedback/backlog, ni las columnas nuevas, ni la RPC.
-- B2 re-ejecutar 0032 en local no falla y no crea nada.
-- B3 con feedback y backlog scratch (en transacción), 0032 dos veces deja 2 columnas text, 1 índice único
--    parcial, procesando_desde timestamptz y la RPC security invoker con search_path vacío.
-- B4 el índice rechaza un trello_card_id duplicado y admite varios NULL.
-- B5 finalize sobre una fila no reservada (o ya procesada) lanza error y no escribe.
-- B6 crear: inserta en backlog con los ids de Trello y deja el feedback procesado con backlog_id.
-- B7 vincular a una tarjeta sin fila deja votos = 2; otro feedback vinculado a la misma deja 3.
-- B8 EXECUTE: false para anon/authenticated, true para service_role; rollback_0032 quita todo y, tras el
--    rollback de la transacción, no quedan residuos.

\set ON_ERROR_STOP 1
do $$
begin
    if inet_server_addr() is not null and host(inet_server_addr()) not in ('127.0.0.1', '::1') then
        raise exception 'feedback_trello_check: solo BD local (socket o loopback); servidor %', host(inet_server_addr());
    end if;
end $$;

do $$
begin
    if to_regclass('public.feedback') is not null or to_regclass('public.backlog') is not null then
        raise exception 'feedback_trello B1: public.feedback o public.backlog existe en local';
    end if;
    if exists (select 1 from pg_proc where proname = 'homita_feedback_finalize') then
        raise exception 'feedback_trello B1: la RPC homita_feedback_finalize existe en local';
    end if;
    raise notice 'ok B1: sin tablas, columnas ni RPC de 0032 en local';
end $$;

-- @MIGRATION:0032_feedback_trello.sql@

do $$
begin
    if to_regclass('public.feedback') is not null or to_regclass('public.backlog') is not null
       or exists (select 1 from pg_proc where proname = 'homita_feedback_finalize') then
        raise exception 'feedback_trello B2: tras re-ejecutar 0032 en local hay tablas o RPC';
    end if;
    raise notice 'ok B2: 0032 re-ejecutable en local, sin cambios';
end $$;

begin;
-- Forma deducida de prod (A1): solo las columnas que usa la función.
create table public.feedback (
    id bigint generated always as identity primary key,
    texto text not null,
    seccion text not null,
    subseccion text,
    tipo text not null,
    estado text not null default 'pendiente',
    backlog_id bigint
);
create table public.backlog (
    id bigint generated always as identity primary key,
    titulo text not null,
    descripcion text,
    seccion text,
    subseccion text,
    tipo text,
    votos int not null default 1
);

-- @MIGRATION:0032_feedback_trello.sql@

-- @MIGRATION:0032_feedback_trello.sql@

do $$
declare
    v_cols int;
    v_idx int;
    v_def text;
    v_fn record;
begin
    select count(*) into v_cols
      from information_schema.columns
     where table_schema = 'public' and table_name = 'backlog'
       and column_name in ('trello_card_id', 'trello_card_url') and data_type = 'text';
    if v_cols <> 2 then
        raise exception 'feedback_trello B3: % columnas trello text en backlog (esperado 2)', v_cols;
    end if;
    select count(*), max(pg_get_indexdef(i.indexrelid)) into v_idx, v_def
      from pg_index i join pg_class c on c.oid = i.indexrelid
     where i.indrelid = 'public.backlog'::regclass and c.relname = 'backlog_trello_card_id_key'
       and i.indisunique and i.indpred is not null;
    if v_idx <> 1 or v_def not like '%(trello_card_id) WHERE (trello_card_id IS NOT NULL)%' then
        raise exception 'feedback_trello B3: índice único parcial incorrecto (% , %)', v_idx, v_def;
    end if;
    if not exists (select 1 from information_schema.columns
                    where table_schema = 'public' and table_name = 'feedback'
                      and column_name = 'procesando_desde' and data_type = 'timestamp with time zone'
                      and is_nullable = 'YES') then
        raise exception 'feedback_trello B3: falta feedback.procesando_desde timestamptz null';
    end if;
    select p.prosecdef, p.proconfig, p.prorettype::regtype::text as rt into v_fn
      from pg_proc p
     where p.oid = to_regprocedure('public.homita_feedback_finalize(bigint, boolean, text, text, text, text)');
    if not found or v_fn.prosecdef or v_fn.proconfig is distinct from array['search_path=""'] or v_fn.rt <> 'bigint' then
        raise exception 'feedback_trello B3: RPC ausente o mal definida (%)', v_fn;
    end if;
    raise notice 'ok B3: 0032 dos veces deja columnas, índice parcial, procesando_desde y RPC invoker';
end $$;

do $$
begin
    insert into public.backlog (titulo, trello_card_id) values ('a', 'T-dup');
    begin
        insert into public.backlog (titulo, trello_card_id) values ('b', 'T-dup');
        raise exception 'feedback_trello B4: el índice admitió un trello_card_id duplicado';
    exception when unique_violation then
        null;
    end;
    insert into public.backlog (titulo) values ('n1'), ('n2');
    delete from public.backlog;
    raise notice 'ok B4: trello_card_id único y varios NULL admitidos';
end $$;

do $$
declare
    v_id bigint;
begin
    insert into public.feedback (texto, seccion, tipo) values ('sin reservar', 'S', 'bug') returning id into v_id;
    begin
        perform public.homita_feedback_finalize(v_id, true, 'T-b5', 'u', 't', 'd');
        raise exception 'feedback_trello B5: finalize aceptó una fila no reservada';
    exception when others then
        if sqlerrm not like 'homita_feedback_finalize: feedback % no reservado%' then
            raise;
        end if;
    end;
    update public.feedback set estado = 'procesado', procesando_desde = now() where id = v_id;
    begin
        perform public.homita_feedback_finalize(v_id, true, 'T-b5', 'u', 't', 'd');
        raise exception 'feedback_trello B5: finalize aceptó una fila ya procesada';
    exception when others then
        if sqlerrm not like 'homita_feedback_finalize: feedback % no reservado%' then
            raise;
        end if;
    end;
    if exists (select 1 from public.backlog) then
        raise exception 'feedback_trello B5: finalize fallido escribió en backlog';
    end if;
    raise notice 'ok B5: finalize sin reserva lanza error y no escribe';
end $$;

do $$
declare
    v_fb bigint;
    v_bl bigint;
    v_row record;
begin
    insert into public.feedback (texto, seccion, subseccion, tipo, procesando_desde)
    values ('nuevo', 'Compras', 'Lista', 'bug', now()) returning id into v_fb;
    v_bl := public.homita_feedback_finalize(v_fb, true, 'T-new', 'https://trello.com/c/new', 'Título', 'Desc');
    select * into v_row from public.backlog where id = v_bl;
    if v_row.trello_card_id <> 'T-new' or v_row.trello_card_url <> 'https://trello.com/c/new'
       or v_row.titulo <> 'Título' or v_row.descripcion <> 'Desc' or v_row.seccion <> 'Compras'
       or v_row.subseccion <> 'Lista' or v_row.tipo <> 'bug' or v_row.votos <> 1 then
        raise exception 'feedback_trello B6: fila de backlog incorrecta (%)', v_row;
    end if;
    if not exists (select 1 from public.feedback where id = v_fb and estado = 'procesado' and backlog_id = v_bl) then
        raise exception 'feedback_trello B6: feedback no quedó procesado con backlog_id';
    end if;
    raise notice 'ok B6: crear inserta con ids de Trello y deja procesado + backlog_id';
end $$;

do $$
declare
    v_fb1 bigint;
    v_fb2 bigint;
    v_bl1 bigint;
    v_bl2 bigint;
begin
    insert into public.feedback (texto, seccion, tipo, procesando_desde) values ('uno', 'S', 'idea', now()) returning id into v_fb1;
    insert into public.feedback (texto, seccion, tipo, procesando_desde) values ('dos', 'S', 'idea', now()) returning id into v_fb2;
    v_bl1 := public.homita_feedback_finalize(v_fb1, false, 'T-old', 'https://trello.com/c/old', 'Vieja', 'd');
    if (select votos from public.backlog where id = v_bl1) <> 2 then
        raise exception 'feedback_trello B7: vincular sin fila no dejó votos = 2';
    end if;
    v_bl2 := public.homita_feedback_finalize(v_fb2, false, 'T-old', 'https://trello.com/c/old', 'Vieja', 'd');
    if v_bl2 <> v_bl1 or (select votos from public.backlog where id = v_bl1) <> 3
       or (select count(*) from public.backlog where trello_card_id = 'T-old') <> 1 then
        raise exception 'feedback_trello B7: segundo vínculo no sumó el voto en la misma fila';
    end if;
    if (select count(*) from public.feedback where id in (v_fb1, v_fb2) and estado = 'procesado' and backlog_id = v_bl1) <> 2 then
        raise exception 'feedback_trello B7: los feedbacks no quedaron procesados';
    end if;
    raise notice 'ok B7: vincular sin fila deja votos = 2 y otro vínculo deja 3';
end $$;

do $$
declare
    v_sig text := 'public.homita_feedback_finalize(bigint, boolean, text, text, text, text)';
begin
    if has_function_privilege('anon', v_sig, 'execute') or has_function_privilege('authenticated', v_sig, 'execute')
       or not has_function_privilege('service_role', v_sig, 'execute') then
        raise exception 'feedback_trello B8: grants de la RPC incorrectos';
    end if;
end $$;

-- @ROLLBACK:rollback_0032.sql@

-- @ROLLBACK:rollback_0032.sql@

do $$
begin
    if exists (select 1 from pg_proc where proname = 'homita_feedback_finalize')
       or to_regclass('public.backlog_trello_card_id_key') is not null
       or exists (select 1 from information_schema.columns
                   where table_schema = 'public'
                     and column_name in ('trello_card_id', 'trello_card_url', 'procesando_desde')) then
        raise exception 'feedback_trello B8: rollback_0032 dejó residuos';
    end if;
end $$;

rollback;

do $$
begin
    if to_regclass('public.feedback') is not null or to_regclass('public.backlog') is not null
       or exists (select 1 from pg_proc where proname = 'homita_feedback_finalize') then
        raise exception 'feedback_trello B8: quedan residuos tras el rollback';
    end if;
    raise notice 'ok B8: EXECUTE solo service_role; rollback_0032 limpio y 0 residuos';
end $$;
