-- 0018_home_membership_admin.sql — Administradores múltiples (fase 1.6; plan 1.6 §3). Una sola
-- transacción. NO modifica 0001–0017 ni datos (A-9: sin backfill). Sin tablas, columnas, índices
-- ni constraints nuevos. Triggers de 0015 intactos (A-10): el COMMIT sigue validando el invariante
-- anti-hogar-sin-admin (backstop); cada RPC hace su pre-check explícito para devolver 403 en la
-- llamada.
--
-- Contenido:
-- * Helpers internos §3.3 (sin grant a authenticated): fn_home_mutation_guard (lock FOR UPDATE
--   sobre home como primera sentencia + archived/not-found + cabecera + fn_require_member),
--   fn_admin_count_excluding, fn_is_sole_owner_somewhere (A-7: degradar no toca ACL) y
--   fn_seed_member_legacy (snapshot member legacy17 de 0013 S4:351-356; idempotente, Q-1a).
-- * RPC nuevas §3.4 (3): set_home_membership_role (PATCH /home/membership/role),
--   transfer_home_admin (POST /home/membership/transfer; atómico §3.3 del diseño) y
--   remove_home_membership (DELETE /home/membership; salir/expulsar, Q-2a: expulsión solo admin).
--   Orden obligatorio §3.1: entrada sin tocar datos (ids nulos → 'Not Found' P0002, rol null-safe
--   con coalesce → 'Invalid role' P0001; T15) → fn_home_mutation_guard → membresía objetivo
--   'for update' filtrando home_id → admin del llamante → invariantes (último admin, owner único,
--   último hogar D13) → escritura (en remove_home_membership el lock de app_user va entre el
--   guard y la membresía: ver «Orden de locks»). Convención D-a: 'Not Found' = P0002, 'Not Allowed' = 42501,
--   'Invalid role' e 'Invalid membership' = P0001 (nuevos en RPC_STATUS de la Edge). Q-3a: un
--   único mensaje 'Not Allowed' para último admin, owner único, último hogar y no admin.
-- * Redefiniciones aditivas §3.4 (solo lectura): get_calendar_users y get_task_list_users con la
--   clave nueva 'home_role' (rol de home_membership del hogar del recurso, A-11: join, no se
--   persiste). add_calendar_user y add_task_list_user INTACTOS (0014b): la plantilla USER no
--   cambia (D-008); sin 'home_role' en POST /calendar/user ni POST /task-list/user.
-- * Grants §3.5: 3 RPC nuevas a authenticated con revoke obligatorio a public/anon; los 4
--   helpers sin ejecución externa (solo los llaman las RPC SECURITY DEFINER); las redefinidas
--   conservan sus grants (create or replace).
--
-- Orden de locks (R1-01/R2-01, code-review): hogar (fn_home_mutation_guard, FOR UPDATE) →
-- usuario (app_user FOR UPDATE, solo remove_home_membership) → membresía (home_membership FOR
-- UPDATE). Verificación estática de los 3 flujos: set_home_membership_role = hogar → membresía
-- (una fila; sin app_user); transfer_home_admin = hogar → membresía (caller) → membresía
-- (destino), ambas del mismo hogar (sin app_user); remove_home_membership = hogar → usuario →
-- membresía → paso 8 con RI FOR KEY SHARE sobre otra membresía del MISMO usuario (ya con el lock
-- de usuario tomado). set_default_home (0016:126-140) toma usuario → membresía (UPDATE app_user
-- y su RI FOR KEY SHARE): mismo orden usuario→membresía, sin AB-BA — el caso límite (default ya
-- reasignado) degrada a error FK determinista 23503, no a 40P01. Nadie toma un lock de membresía
-- antes que el de usuario, así que dos remove del mismo usuario no pueden ciclar (se serializan
-- en app_user); el trigger 0015 (diferido) solo re-toma el lock de hogar al COMMIT dentro de la
-- misma transacción que ya lo retiene por el guard; add_*_user (0014b) solo toma FOR KEY SHARE
-- sobre la membresía (sin home ni app_user). Sin ciclos en el inventario de locks.
--
-- Efectos en cascada al borrar home_membership (0012/0015, sin cambios): membership_permission
-- (cascade), calendar_user/task_list_user del hogar del usuario (FK compuesta cascade), y
-- home_member.app_user_id → NULL (SET NULL; el miembro se conserva, §5.2). Q4 de 1.5 queda
-- cerrada: la revocación de acceso es remove_home_membership.
--
-- Rollback: scripts/supabase/rollback/rollback_0018.sql (cuerpos previos de get_calendar_users y
-- get_task_list_users copiados byte a byte de 0005). Precondición del rollback: sin membresías
-- modificadas desde el volcado de G4 (plan §7).

begin;

-- ─────────────────── (a) Helpers internos §3.3 (sin grants externos) ───────────────────

-- Lock + pertenencia + cabecera. Toda RPC de membresía la llama primero (§3.1 paso 2): serializa
-- las operaciones de membresía de un hogar hasta el COMMIT (mismo lock que el trigger de 0015,
-- que lo re-toma al COMMIT dentro de la misma transacción sin bloquear). A-5: hogar archived →
-- 'Not Found'.
create or replace function fn_home_mutation_guard(p_home_id bigint) returns void
language plpgsql security definer set search_path = public as $$
declare v_status home_status;
begin
    select h.status into v_status from home h where h.id = p_home_id for update;
    if not found or v_status = 'archived' then
        raise exception 'Not Found' using errcode = 'P0002';   -- A-5
    end if;
    if fn_active_home_id() is not null and fn_active_home_id() <> p_home_id then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    perform fn_require_member(p_home_id);
end $$;

-- Admins del hogar distintos de p_membership_id (llamar DESPUÉS del lock). READ COMMITTED: cada
-- sentencia toma snapshot nuevo, así el conteo ve los COMMIT de la transacción que tenía el lock.
create or replace function fn_admin_count_excluding(p_home_id bigint, p_membership_id bigint) returns integer
language sql stable security definer set search_path = public as $$
    select count(*)::int from home_membership
    where home_id = p_home_id and role = 'admin' and id <> p_membership_id
$$;

-- ¿La membresía es ACL 'owner' única de algún recurso del hogar? (§3.3; A-7/Q-4a: degradar no
-- bloquea por owner, pero salir/expulsar sí: transferir la propiedad antes).
-- R1-02 (code-review ronda 1): limitación conocida TOCTOU — este chequeo y el delete de
-- remove_home_membership no lockean calendar_user/task_list_user, así que un remove_calendar_user
-- /remove_task_list_user concurrente (0008, fuera del alcance de 1.6) puede bajar el nº de owners
-- entre el chequeo y el delete y dejar un recurso sin owner. Clase preexistente (0008 ya la tenía
-- con sus propias salidas); a cubrir en 1.9 junto con los mutadores de ACL de 0008.
create or replace function fn_is_sole_owner_somewhere(p_home_id bigint, p_app_user_id bigint) returns boolean
language sql stable security definer set search_path = public as $$
    select exists (
        select 1 from calendar_user cu
        where cu.home_id = p_home_id and cu.user_id = p_app_user_id and cu.role = 'owner'
          and not exists (select 1 from calendar_user o where o.calendar_id = cu.calendar_id
                          and o.role = 'owner' and o.user_id <> cu.user_id))
    or exists (
        select 1 from task_list_user tu
        where tu.home_id = p_home_id and tu.user_id = p_app_user_id and tu.role = 'owner'
          and not exists (select 1 from task_list_user o where o.task_list_id = tu.task_list_id
                          and o.role = 'owner' and o.user_id <> tu.user_id))
$$;

-- Snapshot member legacy17 (literal de 0013 S4:351-356; sin *.manage, con home.view). Idempotente
-- (on conflict do nothing). Q-1a: degradar/transferir al caller siembra este snapshot (A-6).
create or replace function fn_seed_member_legacy(p_membership_id bigint) returns void
language sql security definer set search_path = public as $$
    insert into membership_permission (home_membership_id, permission_code)
    select p_membership_id, x.code
    from unnest(array[
        'home.view',
        'calendar.view', 'task.view', 'routine.view',
        'task.create', 'task.edit', 'task.complete', 'task.assign', 'task.delete',
        'event.create', 'event.edit', 'event.delete', 'event.assign',
        'routine.create', 'routine.edit', 'routine.delete', 'routine.assign']) as x(code)
    on conflict do nothing
$$;

revoke execute on function fn_home_mutation_guard(bigint), fn_admin_count_excluding(bigint, bigint),
    fn_is_sole_owner_somewhere(bigint, bigint), fn_seed_member_legacy(bigint)
    from public, anon, authenticated;

-- ─────────────────── (b) RPC nuevas §3.4 (/home/membership/*) ───────────────────

-- PATCH /home/membership/role: designar/degradar admin (§3.4). Idempotente si el rol ya coincide.
-- Promover borra el snapshot (A-6, un admin no tiene filas); degradar siembra legacy17 (Q-1a).
-- Último admin no puede degradarse (§3.4 paso 7). Devuelve membership_id/home_id/app_user_id/role.
create or replace function set_home_membership_role(
    p_home_id bigint, p_membership_id bigint, p_role text
) returns json
language plpgsql security definer set search_path = public as $$
declare
    v_me bigint := fn_my_user_id();
    v_t home_membership%rowtype;
begin
    if v_me is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    -- §3.1 paso 1: entrada sin tocar datos. Ids nulos → 'Not Found' (T15); rol con coalesce
    -- null-safe ('' no está en la lista; `not in` con null sería UNKNOWN y no lanzaría).
    if p_home_id is null or p_membership_id is null then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    if coalesce(p_role, '') not in ('admin', 'member') then
        raise exception 'Invalid role' using errcode = 'P0001';
    end if;
    perform fn_home_mutation_guard(p_home_id);
    select * into v_t from home_membership
     where id = p_membership_id and home_id = p_home_id for update;
    if not found then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    if not fn_is_home_admin(p_home_id) then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    if v_t.role = p_role::home_role then  -- idempotente: estado actual, sin escritura
        return json_build_object('membership_id', v_t.id, 'home_id', v_t.home_id,
                                 'app_user_id', v_t.app_user_id, 'role', v_t.role::text);
    end if;
    if p_role = 'member' and fn_admin_count_excluding(p_home_id, v_t.id) = 0 then
        raise exception 'Not Allowed' using errcode = '42501';  -- último admin
    end if;
    if p_role = 'admin' then
        update home_membership set role = 'admin', updated_at = (now() at time zone 'UTC')
         where id = v_t.id;
        delete from membership_permission where home_membership_id = v_t.id;  -- A-6
    else
        update home_membership set role = 'member', updated_at = (now() at time zone 'UTC')
         where id = v_t.id;
        perform fn_seed_member_legacy(v_t.id);  -- A-6
    end if;
    return json_build_object('membership_id', v_t.id, 'home_id', v_t.home_id,
                             'app_user_id', v_t.app_user_id, 'role', p_role);
end $$;

-- POST /home/membership/transfer: transferencia de administración atómica (§3.3 del diseño;
-- §2.1: set_role ×2 no es atómico). Promote del destino y demote del caller en una transacción;
-- el destino es admin antes del demote, así el invariante se cumple y el trigger 0015 es
-- backstop (§3.4 paso 8). A-5b: transferir a la propia membresía → 'Invalid membership'.
create or replace function transfer_home_admin(
    p_home_id bigint, p_to_membership_id bigint
) returns json
language plpgsql security definer set search_path = public as $$
declare
    v_me bigint := fn_my_user_id();
    v_from home_membership%rowtype;
    v_to home_membership%rowtype;
begin
    if v_me is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    if p_home_id is null or p_to_membership_id is null then
        raise exception 'Not Found' using errcode = 'P0002';  -- sin tocar datos (T15)
    end if;
    perform fn_home_mutation_guard(p_home_id);
    select * into v_from from home_membership
     where app_user_id = v_me and home_id = p_home_id for update;
    if not found then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    if v_from.role <> 'admin' then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    select * into v_to from home_membership
     where id = p_to_membership_id and home_id = p_home_id for update;
    if not found then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    if v_to.id = v_from.id then
        raise exception 'Invalid membership' using errcode = 'P0001';  -- A-5b
    end if;
    if v_to.role <> 'admin' then  -- promote (ya admin → no-op)
        update home_membership set role = 'admin', updated_at = (now() at time zone 'UTC')
         where id = v_to.id;
        delete from membership_permission where home_membership_id = v_to.id;
    end if;
    update home_membership set role = 'member', updated_at = (now() at time zone 'UTC')
     where id = v_from.id;
    perform fn_seed_member_legacy(v_from.id);  -- A-6
    return json_build_object('from_membership_id', v_from.id, 'to_membership_id', v_to.id);
end $$;

-- DELETE /home/membership: salir (propia) o expulsar (ajena, solo admin; §5.2, Q-2a). Bloqueos:
-- último admin (§3.4 paso 5), owner único de un recurso (paso 6, §3.3: transferir antes) y
-- último hogar (paso 7, D13; serializado por usuario con lock de app_user ANTES del de la
-- membresía: R1-01/R2-01, orden hogar → usuario → membresía). Paso 8:
-- default_home_id se reasigna ANTES del delete (la FK
-- (default_home_id, id) → home_membership hace SET NULL y dejaría al usuario sin defecto con
-- varios hogares → 'Home header required' en altas raíz; R2). Cascadas A-8 en el delete.
create or replace function remove_home_membership(
    p_home_id bigint, p_membership_id bigint
) returns json
language plpgsql security definer set search_path = public as $$
declare
    v_me bigint := fn_my_user_id();
    v_t home_membership%rowtype;
begin
    if v_me is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    if p_home_id is null or p_membership_id is null then
        raise exception 'Not Found' using errcode = 'P0002';  -- sin tocar datos (T15)
    end if;
    perform fn_home_mutation_guard(p_home_id);
    -- R2-01 (code-review ronda 2): lock de app_user ANTES del lock de la membresía — orden total
    -- hogar → usuario → membresía (ver «Orden de locks» en la cabecera). Con el lock después de
    -- la membresía había dos ventanas de deadlock 40P01: (1) remove ∥ remove — el paso 8 toma FOR
    -- KEY SHARE sobre la otra membresía del usuario mientras el segundo remove la tenía FOR
    -- UPDATE y esperaba app_user; (2) remove ∥ set_default_home (0016:138; orden usuario →
    -- membresía invertido). R1-01 se mantiene: el conteo D13 va después de este lock y queda
    -- serializado por usuario. El id del usuario se lee sin lock (home_membership.app_user_id es
    -- inmutable) para no tomar la fila de membresía antes de tiempo.
    perform 1 from app_user
     where id = (select hm.app_user_id from home_membership hm
                 where hm.id = p_membership_id and hm.home_id = p_home_id)
       for update;
    select * into v_t from home_membership
     where id = p_membership_id and home_id = p_home_id for update;
    if not found then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    if v_t.app_user_id <> v_me and not fn_is_home_admin(p_home_id) then
        raise exception 'Not Allowed' using errcode = '42501';  -- expulsión solo admin
    end if;
    if v_t.role = 'admin' and fn_admin_count_excluding(p_home_id, v_t.id) = 0 then
        raise exception 'Not Allowed' using errcode = '42501';  -- último admin
    end if;
    if fn_is_sole_owner_somewhere(p_home_id, v_t.app_user_id) then
        raise exception 'Not Allowed' using errcode = '42501';  -- §3.3: transferir la propiedad
    end if;
    -- Conteo D13 serializado por el lock de app_user de arriba (R1-01): el perdedor de la carrera
    -- cross-home espera en ese lock y, al retomar aquí (READ COMMITTED, snapshot nuevo por
    -- sentencia), ve el delete ya confirmado → 1 hogar → 'Not Allowed'.
    if (select count(*) from home_membership hm
        join home h on h.id = hm.home_id and h.status = 'active'
        where hm.app_user_id = v_t.app_user_id) = 1 then
        raise exception 'Not Allowed' using errcode = '42501';  -- D13: no dejar sin hogar
    end if;
    -- Reasignar default ANTES del delete (mismo filtro 'active' que el paso 7: ambos pasos ven el
    -- mismo conjunto de hogares). Orden: personal primero, luego joined_at, luego id.
    update app_user set updated_at = (now() at time zone 'UTC'), default_home_id = (
        select hm.home_id from home_membership hm
        join home h on h.id = hm.home_id and h.status = 'active'
        where hm.app_user_id = v_t.app_user_id and hm.home_id <> p_home_id
        order by h.is_personal desc, hm.joined_at, hm.id limit 1)
    where id = v_t.app_user_id and default_home_id = p_home_id;
    delete from home_membership where id = v_t.id;
    return '{"success":true}'::json;
end $$;

-- ─────────────────── (c) Redefiniciones aditivas: 'home_role' (§3.4, A-11) ───────────────────
-- Cuerpo de 0005:74-91 / 0005:120-137 copiado byte a byte + una clave 'home_role' por usuario
-- (rol de home_membership del hogar del recurso; nunca null: calendar_user/task_list_user.home_id
-- → home_membership por FK compuesta de 0015). Ningún otro cambio.

create or replace function get_calendar_users(p_calendar_id bigint) returns json
language plpgsql stable security definer set search_path = public as $$
begin
    if fn_my_user_id() is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    if not exists (select 1 from calendar_user where calendar_id = p_calendar_id and user_id = fn_my_user_id()) then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    return (
        select coalesce(json_agg(json_build_object(
            'cu_id', cu.id, 'user_id', u.id, 'name', u.name, 'email', u.email, 'role', cu.role,
            'home_role', (select hm.role::text from home_membership hm
                          where hm.home_id = cu.home_id and hm.app_user_id = cu.user_id)
        ) order by (cu.role::text) collate "C", u.name collate "C"), '[]'::json)
        from calendar_user cu
        inner join app_user u on u.id = cu.user_id
        where cu.calendar_id = p_calendar_id
    );
end $$;

create or replace function get_task_list_users(p_task_list_id bigint) returns json
language plpgsql stable security definer set search_path = public as $$
begin
    if fn_my_user_id() is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    if not exists (select 1 from task_list_user where task_list_id = p_task_list_id and user_id = fn_my_user_id()) then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    return (
        select coalesce(json_agg(json_build_object(
            'tlu_id', tlu.id, 'user_id', u.id, 'name', u.name, 'email', u.email, 'role', tlu.role,
            'home_role', (select hm.role::text from home_membership hm
                          where hm.home_id = tlu.home_id and hm.app_user_id = tlu.user_id)
        ) order by (tlu.role::text) collate "C", u.name collate "C"), '[]'::json)
        from task_list_user tlu
        inner join app_user u on u.id = tlu.user_id
        where tlu.task_list_id = p_task_list_id
    );
end $$;

-- ─────────────────── (d) Grants §3.5 ───────────────────
-- Solo las 3 RPC nuevas para authenticated; revoke obligatorio a public/anon ('create' concede
-- EXECUTE a PUBLIC por defecto). Las redefinidas conservan sus grants (create or replace).
-- add_calendar_user/add_task_list_user sin cambios (0014b:177,217; plantilla USER intacta).

revoke all on function set_home_membership_role(bigint, bigint, text) from public, anon;
revoke all on function transfer_home_admin(bigint, bigint) from public, anon;
revoke all on function remove_home_membership(bigint, bigint) from public, anon;
grant execute on function set_home_membership_role(bigint, bigint, text) to authenticated;
grant execute on function transfer_home_admin(bigint, bigint) to authenticated;
grant execute on function remove_home_membership(bigint, bigint) to authenticated;

commit;
