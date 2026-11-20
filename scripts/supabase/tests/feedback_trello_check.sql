-- feedback_trello_check.sql — Migración 0033_feedback_trello.sql (change feedback-trello-gate, D-023).
-- Solo BD local, tras el reset (0031 -> 0032_feedback_schema -> 0033 -> 0034): las tablas reales
-- public.feedback/public.backlog las crea 0032_feedback_schema. ci.sh sustituye cada línea
-- `-- @MIGRATION:<fichero>@` por el texto de supabase/migrations/<fichero> y cada `-- @ROLLBACK:<fichero>@`
-- por scripts/supabase/rollback/<fichero> (psql corre dentro del contenedor y recibe stdin: no puede leer
-- ficheros del host). Cada bloque emite 'ok Bx: …' o aborta con 'feedback_trello Bx: …'.
-- Todo lo que muta va en `begin … rollback` y filtra por las filas que crea (no supone tablas vacías).
-- Los INSERT en feedback disparan el trigger de 0034, inerte sin feedback_webhook_url en Vault: si Vault
-- local ya tiene alguna entrada feedback_webhook_* el check aborta antes de tocar nada.
--
-- B1 tras el reset: backlog.trello_card_id/trello_card_url (text), índice único parcial,
--    feedback.procesando_desde (timestamptz null) y la RPC security invoker, search_path="" y bigint.
-- B2 (en transacción) 0033 dos veces más deja el mismo estado: 2 columnas, 1 índice, 1 RPC.
-- B3 EXECUTE de la RPC: false para anon/authenticated, true para service_role.
-- B4 el índice rechaza un trello_card_id duplicado y admite varios NULL.
-- B5 finalize sobre una fila no reservada (o ya procesada) lanza error y no escribe en backlog.
-- B6 crear: fila con los ids de Trello, sección/subsección/tipo del feedback, votos = 1, y el feedback
--    queda procesado con backlog_id.
-- B7 vincular a una tarjeta sin fila deja votos = 2; otro feedback vinculado deja 3 en la misma fila.
--    B7b: una fila existente con votos null, al vincular, queda en 2 (coalesce).
-- B8 (en transacción) rollback_0033 dos veces quita RPC, índice y las 3 columnas; tras el rollback de la
--    transacción el estado vuelve a ser el de B1.

\set ON_ERROR_STOP 1
do $$
begin
    if inet_server_addr() is not null and host(inet_server_addr()) not in ('127.0.0.1', '::1') then
        raise exception 'feedback_trello_check: solo BD local (socket o loopback); servidor %', host(inet_server_addr());
    end if;
    if exists (select 1 from vault.secrets where name in ('feedback_webhook_url', 'feedback_webhook_secret')) then
        raise exception 'feedback_trello_check: Vault local ya tiene feedback_webhook_url/secret (entorno contaminado); abortado';
    end if;
end $$;

-- Estado esperado tras 0033 (null = correcto; si no, la descripción del fallo).
create function pg_temp.fb_trello_state() returns text language plpgsql as $$
declare
    v_cols int;
    v_idx int;
    v_def text;
    v_fn record;
    v_n int;
begin
    select count(*) into v_cols
      from information_schema.columns
     where table_schema = 'public' and table_name = 'backlog'
       and column_name in ('trello_card_id', 'trello_card_url') and data_type = 'text';
    if v_cols <> 2 then
        return format('%s columnas trello text en backlog (esperado 2)', v_cols);
    end if;
    select count(*), max(pg_get_indexdef(i.indexrelid)) into v_idx, v_def
      from pg_index i join pg_class c on c.oid = i.indexrelid
     where i.indrelid = 'public.backlog'::regclass and c.relname = 'backlog_trello_card_id_key'
       and i.indisunique and i.indpred is not null;
    if v_idx <> 1 or v_def not like '%(trello_card_id) WHERE (trello_card_id IS NOT NULL)%' then
        return format('índice único parcial incorrecto (%s, %s)', v_idx, v_def);
    end if;
    if (select count(*) from information_schema.columns
         where table_schema = 'public' and table_name = 'feedback'
           and column_name = 'procesando_desde' and data_type = 'timestamp with time zone'
           and is_nullable = 'YES') <> 1 then
        return 'falta feedback.procesando_desde timestamptz null';
    end if;
    select count(*) into v_n from pg_proc where proname = 'homita_feedback_finalize';
    select p.prosecdef, p.proconfig, p.prorettype::regtype::text as rt into v_fn
      from pg_proc p
     where p.oid = to_regprocedure('public.homita_feedback_finalize(bigint, boolean, text, text, text, text)');
    if v_n <> 1 or v_fn.rt is null or v_fn.prosecdef or v_fn.proconfig is distinct from array['search_path=""']
       or v_fn.rt <> 'bigint' then
        return format('RPC ausente, duplicada o mal definida (n %s, %s)', v_n, v_fn);
    end if;
    return null;
end $$;

do $$
declare
    v_err text := pg_temp.fb_trello_state();
begin
    if v_err is not null then
        raise exception 'feedback_trello B1: %', v_err;
    end if;
    raise notice 'ok B1: tras el reset hay columnas trello, índice parcial, procesando_desde y RPC invoker';
end $$;

-- B2: 0033 dos veces más, en transacción.
begin;

-- @MIGRATION:0033_feedback_trello.sql@

-- @MIGRATION:0033_feedback_trello.sql@

do $$
declare
    v_err text := pg_temp.fb_trello_state();
begin
    if v_err is not null then
        raise exception 'feedback_trello B2: tras 0033 x2: %', v_err;
    end if;
    raise notice 'ok B2: 0033 dos veces más deja 2 columnas, 1 índice y 1 RPC';
end $$;

rollback;

do $$
declare
    v_sig text := 'public.homita_feedback_finalize(bigint, boolean, text, text, text, text)';
begin
    if has_function_privilege('anon', v_sig, 'execute') or has_function_privilege('authenticated', v_sig, 'execute')
       or not has_function_privilege('service_role', v_sig, 'execute') then
        raise exception 'feedback_trello B3: grants de la RPC incorrectos';
    end if;
    raise notice 'ok B3: EXECUTE de la RPC solo para service_role';
end $$;

-- B4–B7 mutan backlog/feedback: una transacción con rollback al final.
begin;

do $$
declare
    v_n int;
begin
    insert into public.backlog (titulo, trello_card_id) values ('b4 a', 'T-b4-dup');
    begin
        insert into public.backlog (titulo, trello_card_id) values ('b4 b', 'T-b4-dup');
        raise exception 'feedback_trello B4: el índice admitió un trello_card_id duplicado';
    exception when unique_violation then
        null;
    end;
    insert into public.backlog (titulo) values ('b4 n1'), ('b4 n2');
    select count(*) into v_n from public.backlog where titulo in ('b4 n1', 'b4 n2') and trello_card_id is null;
    if v_n <> 2 then
        raise exception 'feedback_trello B4: no se admitieron varios NULL (%)', v_n;
    end if;
    delete from public.backlog where titulo in ('b4 a', 'b4 b', 'b4 n1', 'b4 n2');
    raise notice 'ok B4: trello_card_id único y varios NULL admitidos';
end $$;

do $$
declare
    v_id bigint;
begin
    insert into public.feedback (texto, seccion, tipo) values ('b5 sin reservar', 'S', 'bug') returning id into v_id;
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
    if exists (select 1 from public.backlog where trello_card_id = 'T-b5') then
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
    values ('b6 nuevo', 'Compras', 'Lista', 'mejora', now()) returning id into v_fb;
    v_bl := public.homita_feedback_finalize(v_fb, true, 'T-b6-new', 'https://trello.com/c/new', 'Título', 'Desc');
    select * into v_row from public.backlog where id = v_bl;
    if v_row.trello_card_id is distinct from 'T-b6-new' or v_row.trello_card_url is distinct from 'https://trello.com/c/new'
       or v_row.titulo is distinct from 'Título' or v_row.descripcion is distinct from 'Desc'
       or v_row.seccion is distinct from 'Compras' or v_row.subseccion is distinct from 'Lista'
       or v_row.tipo is distinct from 'mejora' or v_row.votos is distinct from 1 then
        raise exception 'feedback_trello B6: fila de backlog incorrecta (%)', v_row;
    end if;
    if not exists (select 1 from public.feedback where id = v_fb and estado = 'procesado' and backlog_id = v_bl) then
        raise exception 'feedback_trello B6: feedback no quedó procesado con backlog_id';
    end if;
    raise notice 'ok B6: crear inserta con ids de Trello, votos = 1 y deja procesado + backlog_id';
end $$;

do $$
declare
    v_fb1 bigint;
    v_fb2 bigint;
    v_fb3 bigint;
    v_bl1 bigint;
    v_bl2 bigint;
    v_bl3 bigint;
    v_old bigint;
begin
    insert into public.feedback (texto, seccion, tipo, procesando_desde) values ('b7 uno', 'S', 'bug', now()) returning id into v_fb1;
    insert into public.feedback (texto, seccion, tipo, procesando_desde) values ('b7 dos', 'S', 'bug', now()) returning id into v_fb2;
    v_bl1 := public.homita_feedback_finalize(v_fb1, false, 'T-b7-old', 'https://trello.com/c/old', 'Vieja', 'd');
    if (select votos from public.backlog where id = v_bl1) is distinct from 2 then
        raise exception 'feedback_trello B7: vincular sin fila no dejó votos = 2';
    end if;
    v_bl2 := public.homita_feedback_finalize(v_fb2, false, 'T-b7-old', 'https://trello.com/c/old', 'Vieja', 'd');
    if v_bl2 <> v_bl1 or (select votos from public.backlog where id = v_bl1) is distinct from 3
       or (select count(*) from public.backlog where trello_card_id = 'T-b7-old') <> 1 then
        raise exception 'feedback_trello B7: segundo vínculo no sumó el voto en la misma fila';
    end if;
    if (select count(*) from public.feedback where id in (v_fb1, v_fb2) and estado = 'procesado' and backlog_id = v_bl1) <> 2 then
        raise exception 'feedback_trello B7: los feedbacks no quedaron procesados';
    end if;

    -- B7b: fila existente con votos null (votos es nullable en 0032_feedback_schema y en prod).
    insert into public.backlog (titulo, votos, trello_card_id) values ('b7b nula', null, 'T-b7b-null') returning id into v_old;
    insert into public.feedback (texto, seccion, tipo, procesando_desde) values ('b7b', 'S', 'mejora', now()) returning id into v_fb3;
    v_bl3 := public.homita_feedback_finalize(v_fb3, false, 'T-b7b-null', 'https://trello.com/c/null', 'Nula', 'd');
    if v_bl3 <> v_old or (select votos from public.backlog where id = v_old) is distinct from 2 then
        raise exception 'feedback_trello B7b: vincular a una fila con votos null no dejó 2 (%)',
            (select votos from public.backlog where id = v_old);
    end if;
    raise notice 'ok B7: vincular sin fila deja votos = 2 y otro vínculo deja 3; B7b votos null -> 2';
end $$;

rollback;

-- B8: rollback_0033 dos veces, en transacción.
begin;

-- @ROLLBACK:rollback_0033.sql@

-- @ROLLBACK:rollback_0033.sql@

do $$
begin
    if exists (select 1 from pg_proc where proname = 'homita_feedback_finalize')
       or to_regclass('public.backlog_trello_card_id_key') is not null
       or exists (select 1 from information_schema.columns
                   where table_schema = 'public' and table_name in ('backlog', 'feedback')
                     and column_name in ('trello_card_id', 'trello_card_url', 'procesando_desde')) then
        raise exception 'feedback_trello B8: rollback_0033 dejó residuos';
    end if;
end $$;

rollback;

do $$
declare
    v_err text := pg_temp.fb_trello_state();
begin
    if v_err is not null then
        raise exception 'feedback_trello B8: tras el rollback el estado no es el de B1: %', v_err;
    end if;
    if exists (select 1 from public.backlog where trello_card_id like 'T-b%' or titulo like 'b4 %')
       or exists (select 1 from public.feedback where texto like 'b5 %' or texto like 'b6 %' or texto like 'b7%') then
        raise exception 'feedback_trello B8: quedan filas de prueba tras el rollback';
    end if;
    raise notice 'ok B8: rollback_0033 x2 quita RPC, índice y columnas; tras el rollback, estado de B1 sin filas de prueba';
end $$;
