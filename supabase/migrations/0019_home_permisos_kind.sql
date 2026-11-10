-- 0019_home_permisos_kind.sql — Permisos granulares por kind (fase 1.7; plan 1.7 §3). Una sola
-- transacción. NO modifica 0001–0018 ni datos (A-7: `permission` y `member_kind_default`
-- intactos). Sin tablas, columnas, índices, constraints ni triggers nuevos. Sin rutas Edge ni
-- cambio de contrato (D-008): los permisos efectivos ya salen en GET /home/membership (0016).
--
-- Contenido:
-- * fn_seed_kind_permissions (§3.1): snapshot de `membership_permission` por kind — reemplaza,
--   no suma: el snapshot queda exactamente igual a `member_kind_default` del kind. Guardias
--   null-safe/defensa en profundidad (R1-01/R1-02 del review ronda 1): `p_membership_id` null →
--   'Not Found' P0002; `p_kind` null o 'pet' → 'Invalid member' P0001 (pet no tiene cuenta,
--   §3.2; sin borrado silencioso del snapshot); membresía inexistente → 'Not Found' P0002; rol
--   ≠ 'member' (admin) → 'Not Allowed' 42501. Así A4 (un admin no recibe filas) queda garantizada
--   por construcción desde cualquier llamador futuro (1.15), no solo por convención. Sin grants
--   externos: solo lo llaman RPC SECURITY DEFINER (1.15).
-- * Aserciones de seed (§3.2): bloque `do $$…$$` final que aborta si `permission` ≠ 23 (0012 §F),
--   `member_kind_default` ≠ 37, algún conjunto por kind difiere de las listas literales de §5.5
--   (+A9) o hay filas en `membership_permission` de membresías admin (A4). Motivo (R7): detecta
--   un seed alterado por psql antes de usarlo.
--
-- Interacción (§3.3): ningún trigger de 0015 se dispara sobre `membership_permission` (solo
-- `home_membership`, `home`, `event_person`/`routine_person`). El helper no toma locks propios:
-- su FK (0012) toma FOR KEY SHARE sobre la fila de `home_membership` y el DELETE/INSERT lockea
-- `membership_permission`, respetando el orden de 0018: hogar (guard del llamador, FOR UPDATE) →
-- `home_membership` → `membership_permission`, sin `app_user` ni ciclos. El llamador (1.15) llama
-- antes a fn_home_mutation_guard (A-5: archived → 'Not Found'). Sin trigger sobre
-- `home_member.app_user_id` (A-3): el snapshot lo escribe explícitamente la RPC de vinculación.
--
-- Sin cambios (§3.4): fn_has_permission, fn_require_permission, fn_seed_member_legacy (0018),
-- get_home_memberships, get_persons y las RPC de 0016/0017/0018. update_home_member (0017) con
-- cambio de `kind` NO re-snapshotea (Q-B: los permisos se ajustan en 1.9).
--
-- Rollback: scripts/supabase/rollback/rollback_0019.sql (drop del helper; sin datos).

begin;

-- ─────────────────── (a) Helper de snapshot por kind (§3.1) ───────────────────

create or replace function fn_seed_kind_permissions(p_membership_id bigint, p_kind member_kind)
returns void language plpgsql security definer set search_path = public as $$
declare v_role home_role;
begin
    -- R1-01 (review): null-safe como 0017/0018; sin borrado silencioso del snapshot.
    if p_membership_id is null then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    if p_kind is null or p_kind = 'pet' then
        raise exception 'Invalid member' using errcode = 'P0001';   -- pet no tiene cuenta (§3.2)
    end if;
    -- R1-02 (review): existencia y rol en el propio helper (blinda A4: admin = 0 filas).
    select hm.role into v_role from home_membership hm where hm.id = p_membership_id;
    if v_role is null then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    if v_role <> 'member' then
        raise exception 'Not Allowed' using errcode = '42501';      -- un admin no recibe snapshot
    end if;
    delete from membership_permission where home_membership_id = p_membership_id;
    insert into membership_permission (home_membership_id, permission_code)
    select p_membership_id, d.permission_code
    from member_kind_default d where d.kind = p_kind;
end $$;

revoke execute on function fn_seed_kind_permissions(bigint, member_kind)
    from public, anon, authenticated;

-- ─────────────────── (b) Aserciones de seed (§3.2) ───────────────────
-- Listas literales de §5.5 (orden collate "C", el mismo oráculo que permisos_kind_check.sql).

do $$
declare
    v_n bigint;
    v_set text;
    v_exp text;
begin
    select count(*) into v_n from permission;
    if v_n <> 23 then
        raise exception 'Aserción 0019: permission = % (esperado 23)', v_n;
    end if;
    select count(*) into v_n from member_kind_default;
    if v_n <> 37 then
        raise exception 'Aserción 0019: member_kind_default = % (esperado 37)', v_n;
    end if;

    v_exp := array_to_string(array[
        'calendar.manage', 'calendar.view', 'event.assign', 'event.create', 'event.delete',
        'event.edit', 'routine.assign', 'routine.create', 'routine.delete', 'routine.edit',
        'routine.view', 'task.assign', 'task.complete', 'task.create', 'task.delete',
        'task.edit', 'task.view', 'tasklist.manage'], ',');
    select coalesce(string_agg(permission_code, ',' order by permission_code collate "C"), '')
      into v_set from member_kind_default where kind = 'adult';
    if v_set <> v_exp then
        raise exception 'Aserción 0019: adult ≠ §5.5 (%, esperado %)', v_set, v_exp;
    end if;

    v_exp := array_to_string(array[
        'calendar.view', 'home.view', 'routine.view', 'task.complete', 'task.create',
        'task.view'], ',');
    select coalesce(string_agg(permission_code, ',' order by permission_code collate "C"), '')
      into v_set from member_kind_default where kind = 'child';
    if v_set <> v_exp then
        raise exception 'Aserción 0019: child ≠ §5.5 (%, esperado %)', v_set, v_exp;
    end if;

    v_exp := array_to_string(array[
        'calendar.view', 'event.create', 'event.edit', 'home.view', 'routine.view',
        'task.assign', 'task.complete', 'task.create', 'task.edit', 'task.view'], ',');
    select coalesce(string_agg(permission_code, ',' order by permission_code collate "C"), '')
      into v_set from member_kind_default where kind = 'relative';
    if v_set <> v_exp then
        raise exception 'Aserción 0019: relative ≠ §5.5 (%, esperado %)', v_set, v_exp;
    end if;

    v_exp := array_to_string(array[
        'calendar.view', 'task.complete', 'task.view'], ',');
    select coalesce(string_agg(permission_code, ',' order by permission_code collate "C"), '')
      into v_set from member_kind_default where kind = 'guest';
    if v_set <> v_exp then
        raise exception 'Aserción 0019: guest ≠ §5.5 (%, esperado %)', v_set, v_exp;
    end if;

    select count(*) into v_n from member_kind_default where kind = 'pet';
    if v_n <> 0 then
        raise exception 'Aserción 0019: pet con % filas (esperado 0)', v_n;
    end if;

    select count(*) into v_n
      from membership_permission mp
      join home_membership hm on hm.id = mp.home_membership_id
     where hm.role = 'admin';
    if v_n <> 0 then
        raise exception 'Aserción 0019: % filas de membership_permission en membresías admin (A4)', v_n;
    end if;
    raise notice 'ok aserciones 0019: catálogo 23/37, conjuntos §5.5 por kind, admin = 0 filas';
end $$;

commit;
