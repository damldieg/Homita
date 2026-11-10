-- 0021_home_permisos_audit.sql — Configuración/auditoría de permisos y cierre A-12 (fase 1.9).
-- No editar 0012–0020. Desviación D-011: cambiar el kind de un miembro vinculado exige admin,
-- porque el cambio resetea el snapshot a defaults (Q1/Q6). Locks: hogar → home_member → membresía
-- → membership_permission → audit_log (FK de actor toma KEY SHARE al final). Las mutaciones ACL
-- de 0020 serializan con fn_home_mutation_guard/remove_home_membership; altas usan ON CONFLICT y
-- adds/removes/deletes toman el conjunto ACL en orden estable. El grep de 0008–0020 confirmó que
-- fuera de estas RPC solo hay backfill histórico y create_calendar/create_task_list guardadas.
-- Rollback: scripts/supabase/rollback/rollback_0021.sql; restaura cuerpos pre-0021 de 7 RPC.

begin;

-- Última escritura de cada operación: genera una fila por código cambiado.
create or replace function fn_audit_permission_delta(
    p_home_id bigint, p_membership_id bigint, p_before text[], p_after text[],
    p_source text, p_extra jsonb default '{}'
) returns void
language plpgsql security definer set search_path = public as $$
begin
    with changes as (
        select x.code, 'home.permission.grant'::text as action, false as before_value,
               true as after_value
        from unnest(coalesce(p_after, '{}'::text[])) x(code)
        where not (x.code = any(coalesce(p_before, '{}'::text[])))
        union all
        select x.code, 'home.permission.revoke', true, false
        from unnest(coalesce(p_before, '{}'::text[])) x(code)
        where not (x.code = any(coalesce(p_after, '{}'::text[])))
    )
    insert into audit_log (home_id, actor_app_user_id, action, target_type, target_id, payload)
    select p_home_id, fn_my_user_id(), c.action, 'home_membership', p_membership_id,
           jsonb_build_object('permission_code', c.code, 'before', c.before_value,
                              'after', c.after_value, 'source', p_source) || coalesce(p_extra, '{}')
    from changes c order by c.action, c.code collate "C";
end $$;

create or replace function get_home_permissions(p_home_id bigint) returns json
language plpgsql stable security definer set search_path = public as $$
begin
    if fn_active_home_id() is not null and fn_active_home_id() <> p_home_id then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    perform fn_require_permission(p_home_id, 'home.view');
    return (
        select json_build_object(
            'catalog', (select coalesce(json_agg(json_build_object(
                'code', p.code, 'domain', p.domain, 'description', p.description
            ) order by p.code collate "C"), '[]'::json) from permission p),
            'defaults', (select coalesce(json_agg(json_build_object(
                'kind', d.kind::text, 'permissions', d.permissions
            ) order by d.kind::text collate "C"), '[]'::json)
            from (select mkd.kind, json_agg(mkd.permission_code
                       order by mkd.permission_code collate "C") as permissions
                  from member_kind_default mkd group by mkd.kind) d),
            'memberships', (select coalesce(json_agg(json_build_object(
                'membership_id', hm.id, 'app_user_id', u.id, 'name', u.name, 'email', u.email,
                'role', hm.role::text,
                'kind', (select hmb.kind::text from home_member hmb
                         where hmb.home_id = p_home_id and hmb.app_user_id = hm.app_user_id
                         order by hmb.id limit 1),
                'editable', fn_is_home_admin(p_home_id) and hm.role = 'member',
                'permissions', case when hm.role = 'admin' then
                    (select coalesce(json_agg(p.code order by p.code collate "C"), '[]'::json)
                     from permission p)
                else (select coalesce(json_agg(mp.permission_code
                                      order by mp.permission_code collate "C"), '[]'::json)
                      from membership_permission mp where mp.home_membership_id = hm.id)
                end
            ) order by hm.role::text collate "C", u.name collate "C"), '[]'::json)
            from home_membership hm join app_user u on u.id = hm.app_user_id
            where hm.home_id = p_home_id)
        )
        from home h where h.id = p_home_id
    );
end $$;

create or replace function get_home_audit(
    p_home_id bigint, p_limit integer default null, p_before_id bigint default null
) returns json
language plpgsql stable security definer set search_path = public as $$
declare v_limit integer := least(greatest(coalesce(p_limit, 50), 1), 200);
begin
    if fn_active_home_id() is not null and fn_active_home_id() <> p_home_id then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    perform fn_require_member(p_home_id);
    if not fn_is_home_admin(p_home_id) then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    return (
        select coalesce(json_agg(json_build_object(
            'id', q.id, 'action', q.action, 'target_type', q.target_type, 'target_id', q.target_id,
            'actor_app_user_id', q.actor_app_user_id, 'actor_name', q.actor_name,
            'payload', q.payload, 'created_at', to_char(q.created_at, 'YYYY-MM-DD HH24:MI:SS')
        ) order by q.id desc), '[]'::json)
        from (
            select a.id, a.action, a.target_type, a.target_id, a.actor_app_user_id,
                   u.name as actor_name, a.payload, a.created_at
            from audit_log a left join app_user u on u.id = a.actor_app_user_id
            where a.home_id = p_home_id and a.action like 'home.%'
              and (p_before_id is null or a.id < p_before_id)
            order by a.id desc limit v_limit
        ) q
    );
end $$;

create or replace function set_home_permissions(
    p_home_id bigint, p_membership_id bigint, p_permissions jsonb
) returns json
language plpgsql security definer set search_path = public as $$
declare
    v_before text[];
    v_after text[];
    v_granted text[];
    v_revoked text[];
begin
    if fn_my_user_id() is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    if p_home_id is null or p_membership_id is null then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    -- Validación de entrada sin locks (ifs separados: jsonb_array_length solo sobre arrays).
    if p_permissions is null then
        raise exception 'Invalid permission' using errcode = 'P0001';
    end if;
    if jsonb_typeof(p_permissions) <> 'array' then
        raise exception 'Invalid permission' using errcode = 'P0001';
    end if;
    if jsonb_array_length(p_permissions) > 100 then
        raise exception 'Invalid permission' using errcode = 'P0001';
    end if;
    if exists (select 1 from jsonb_array_elements(p_permissions) e
               where jsonb_typeof(e) <> 'string') then
        raise exception 'Invalid permission' using errcode = 'P0001';
    end if;
    if exists (select 1 from jsonb_array_elements_text(p_permissions) e(code)
               where not exists (select 1 from permission p where p.code = e.code)) then
        raise exception 'Invalid permission' using errcode = 'P0001';
    end if;
    select coalesce(array_agg(x.code order by x.code collate "C"), '{}'::text[])
      into v_after from (select distinct e.code from jsonb_array_elements_text(p_permissions) e(code)) x;

    perform fn_home_mutation_guard(p_home_id);
    perform fn_require_permission(p_home_id, 'home.permissions.manage');
    if not fn_is_home_admin(p_home_id) then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    perform 1 from home_membership hm
     where hm.id = p_membership_id and hm.home_id = p_home_id for update;
    if not found then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    if (select hm.role from home_membership hm where hm.id = p_membership_id) = 'admin' then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    select coalesce(array_agg(mp.permission_code order by mp.permission_code collate "C"), '{}'::text[])
      into v_before from membership_permission mp where mp.home_membership_id = p_membership_id;
    select coalesce(array_agg(x.code order by x.code collate "C"), '{}'::text[])
      into v_granted from unnest(v_after) x(code) where not (x.code = any(v_before));
    select coalesce(array_agg(x.code order by x.code collate "C"), '{}'::text[])
      into v_revoked from unnest(v_before) x(code) where not (x.code = any(v_after));
    if cardinality(v_granted) = 0 and cardinality(v_revoked) = 0 then
        return json_build_object('membership_id', p_membership_id, 'home_id', p_home_id,
                                 'permissions', v_before, 'granted', v_granted, 'revoked', v_revoked);
    end if;
    delete from membership_permission mp
     where mp.home_membership_id = p_membership_id and mp.permission_code = any(v_revoked);
    insert into membership_permission (home_membership_id, permission_code)
    select p_membership_id, x.code from unnest(v_granted) x(code) on conflict do nothing;
    perform fn_audit_permission_delta(p_home_id, p_membership_id, v_before, v_after, 'set');
    return json_build_object('membership_id', p_membership_id, 'home_id', p_home_id,
                             'permissions', v_after, 'granted', v_granted, 'revoked', v_revoked);
end $$;

-- Cambio de kind y snapshot se deciden con el hogar bloqueado; la lectura inicial solo decide
-- si debe adquirirse ese lock. Esto serializa los cambios ligados con baja/promoción (R1-02).
create or replace function update_home_member(
    p_id bigint, p_kind text, p_name text, p_color text, p_status text
) returns json
language plpgsql security definer set search_path = public as $$
declare
    v_home bigint;
    v_linked_pre bigint;
    v_linked bigint;
    v_kind text;
    v_name_cur text;
    v_color_cur text;
    v_status text;
    v_kind_new text;
    v_status_new text;
    v_name_new text;
    v_color_new text;
    v_changed boolean;
    v_lock_home boolean;
    v_mid bigint;
    v_role home_role;
    v_before text[];
    v_after text[];
begin
    if fn_my_user_id() is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    select hm.home_id, hm.app_user_id into v_home, v_linked_pre
      from home_member hm where hm.id = p_id;
    if not found then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    v_lock_home := p_kind is not null and v_linked_pre is not null;
    if v_lock_home then
        perform fn_home_mutation_guard(v_home);
    end if;
    select hm.home_id, hm.app_user_id, hm.kind::text, hm.name, hm.color, hm.status::text
      into v_home, v_linked, v_kind, v_name_cur, v_color_cur, v_status
      from home_member hm where hm.id = p_id for update;
    if not found then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    if v_linked_pre is null and v_linked is not null and p_kind is not null then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    if fn_active_home_id() is not null and fn_active_home_id() <> v_home then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    perform fn_require_permission(v_home, 'home.members.manage');
    v_kind_new := coalesce(p_kind, v_kind);
    v_status_new := coalesce(p_status, v_status);
    if v_kind_new not in ('adult', 'child', 'relative', 'guest', 'pet')
       or v_status_new not in ('active', 'inactive') then
        raise exception 'Invalid member' using errcode = 'P0001';
    end if;
    if v_kind_new = 'pet' and v_linked is not null then
        raise exception 'Invalid member' using errcode = 'P0001';
    end if;
    v_changed := v_linked is not null and v_kind_new <> v_kind;
    if v_changed and not fn_is_home_admin(v_home) then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    select f.v_name, f.v_color into v_name_new, v_color_new
      from fn_validate_person_fields(coalesce(p_name, v_name_cur), coalesce(p_color, v_color_cur)) f;
    if v_changed then
        select hm.id, hm.role into v_mid, v_role from home_membership hm
         where hm.home_id = v_home and hm.app_user_id = v_linked for update;
    end if;
    update home_member
       set kind = v_kind_new::member_kind, name = v_name_new, color = v_color_new,
           status = v_status_new::member_status, updated_at = (now() at time zone 'UTC')
     where id = p_id
       and (kind::text, name, color, status::text)
           is distinct from (v_kind_new, v_name_new, v_color_new, v_status_new);
    update person set name = v_name_new, color = v_color_new, updated_at = (now() at time zone 'UTC')
     where home_member_id = p_id and (name, color) is distinct from (v_name_new, v_color_new);
    if v_changed and v_role = 'member' then
        select coalesce(array_agg(mp.permission_code order by mp.permission_code collate "C"),
                        '{}'::text[]) into v_before
          from membership_permission mp where mp.home_membership_id = v_mid;
        perform fn_seed_kind_permissions(v_mid, v_kind_new::member_kind);
        select coalesce(array_agg(mp.permission_code order by mp.permission_code collate "C"),
                        '{}'::text[]) into v_after
          from membership_permission mp where mp.home_membership_id = v_mid;
        perform fn_audit_permission_delta(v_home, v_mid, v_before, v_after, 'kind_change',
            jsonb_build_object('kind_from', v_kind, 'kind_to', v_kind_new));
    end if;
    return fn_home_member_json(p_id);
end $$;

create or replace function add_calendar_user(p_calendar_id bigint, p_email text) returns json
language plpgsql security definer set search_path = public as $$
declare
    v_me bigint := fn_my_user_id();
    v_role user_role;
    v_home bigint;
    v_target app_user%rowtype;
begin
    if v_me is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    -- 1.8 (§2.2/§2.3): lock del hogar (incluye la cabecera X-Home-Id) → ACL → owner →
    -- calendar.manage. Q3 (0014): email de no-miembro del hogar → 'Not Allowed'.
    v_home := fn_home_of_calendar(p_calendar_id);
    if v_home is null then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    perform fn_home_write_lock(v_home);
    select role into v_role from calendar_user where calendar_id = p_calendar_id and user_id = v_me for share;
    if v_role is null then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    if v_role <> 'owner' or not fn_has_permission(v_home, 'calendar.manage') then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    select * into v_target from app_user where email = p_email;
    if not found then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    if not exists (select 1 from home_membership where home_id = v_home and app_user_id = v_target.id) then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    -- A-12 (cierre): ON CONFLICT idempotente (unique calendar_user_calendar_user_key, 0015:18):
    -- dos adds concurrentes del mismo email -> 200+200, 1 fila, sin 23505->500.
    insert into calendar_user (calendar_id, user_id, role, widget, dashboard, home_id)
    values (p_calendar_id, v_target.id, 'viewer', true, true, v_home)
    on conflict (calendar_id, user_id) do nothing;
    return json_build_object(
        'id', v_target.id, 'name', v_target.name, 'email', v_target.email,
        'created_at', to_char(v_target.created_at, 'YYYY-MM-DD HH24:MI:SS'),
        'updated_at', to_char(v_target.updated_at, 'YYYY-MM-DD HH24:MI:SS'));
end $$;

create or replace function add_task_list_user(p_task_list_id bigint, p_email text) returns json
language plpgsql security definer set search_path = public as $$
declare
    v_me bigint := fn_my_user_id();
    v_role user_role;
    v_home bigint;
    v_target app_user%rowtype;
begin
    if v_me is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    -- 1.8 (§2.2/§2.3): lock del hogar (incluye la cabecera X-Home-Id) → ACL → owner →
    -- tasklist.manage. Q3 (0014): email de no-miembro del hogar → 'Not Allowed'.
    v_home := fn_home_of_task_list(p_task_list_id);
    if v_home is null then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    perform fn_home_write_lock(v_home);
    select role into v_role from task_list_user where task_list_id = p_task_list_id and user_id = v_me for share;
    if v_role is null then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    if v_role <> 'owner' or not fn_has_permission(v_home, 'tasklist.manage') then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    select * into v_target from app_user where email = p_email;
    if not found then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    if not exists (select 1 from home_membership where home_id = v_home and app_user_id = v_target.id) then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    -- A-12 (cierre): ON CONFLICT idempotente (unique task_list_user_task_list_user_key, 0015:19):
    -- dos adds concurrentes del mismo email -> 200+200, 1 fila, sin 23505->500.
    insert into task_list_user (task_list_id, user_id, role, widget, dashboard, home_id)
    values (p_task_list_id, v_target.id, 'viewer', true, true, v_home)
    on conflict (task_list_id, user_id) do nothing;
    return json_build_object(
        'id', v_target.id, 'name', v_target.name, 'email', v_target.email,
        'created_at', to_char(v_target.created_at, 'YYYY-MM-DD HH24:MI:SS'),
        'updated_at', to_char(v_target.updated_at, 'YYYY-MM-DD HH24:MI:SS'));
end $$;

create or replace function remove_calendar_user(p_calendar_id bigint, p_user_id bigint) returns json
language plpgsql security definer set search_path = public as $$
declare
    v_me bigint := fn_my_user_id();
    v_role user_role;
    v_home bigint;
begin
    if v_me is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    -- 1.8 (§2.2/§2.3): lock → ACL → último owner (403) → self (400) → owner (403) →
    -- calendar.manage (403). El último owner va ANTES del self: su autoretiro recibe 403 (M14) y
    -- el de un owner con reemplazo sigue recibiendo 400 (contrato, R1-07).
    v_home := fn_home_of_calendar(p_calendar_id);
    if v_home is null then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    perform fn_home_write_lock(v_home);
    -- A-12 (cierre): (i) el llamante debe tener fila ACL sin lock (un no-ACL no bloquea filas
    -- ajenas); (ii) el conjunto ACL se bloquea en orden de id (FOR UPDATE sobre el Sort);
    -- (iii) relectura de v_role ya sin FOR SHARE (se elimina: FOR SHARE propio + FOR UPDATE del
    -- conjunto = ciclo de mejora de lock entre dos removes). El resto del cuerpo es igual.
    select role into v_role from calendar_user where calendar_id = p_calendar_id and user_id = v_me;
    if v_role is null then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    perform 1 from calendar_user where calendar_id = p_calendar_id order by id for update;
    select role into v_role from calendar_user where calendar_id = p_calendar_id and user_id = v_me;
    if v_role is null then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    if exists (select 1 from calendar_user
               where calendar_id = p_calendar_id and user_id = p_user_id and role = 'owner')
       and not exists (select 1 from calendar_user
                       where calendar_id = p_calendar_id and role = 'owner' and user_id <> p_user_id) then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    if p_user_id = v_me then
        raise exception 'User cannot remove themselves' using errcode = 'P0001';
    end if;
    if v_role <> 'owner' or not fn_has_permission(v_home, 'calendar.manage') then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    delete from calendar_user where calendar_id = p_calendar_id and user_id = p_user_id;
    return '{"status":"ok"}'::json;
end $$;

create or replace function remove_task_list_user(p_task_list_id bigint, p_user_id bigint) returns json
language plpgsql security definer set search_path = public as $$
declare
    v_me bigint := fn_my_user_id();
    v_role user_role;
    v_home bigint;
begin
    if v_me is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    -- 1.8 (§2.2/§2.3): lock → ACL → último owner (403) → self (400) → owner (403) →
    -- tasklist.manage (403). El último owner va ANTES del self (M14).
    v_home := fn_home_of_task_list(p_task_list_id);
    if v_home is null then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    perform fn_home_write_lock(v_home);
    -- A-12 (cierre): (i) el llamante debe tener fila ACL sin lock (un no-ACL no bloquea filas
    -- ajenas); (ii) el conjunto ACL se bloquea en orden de id (FOR UPDATE sobre el Sort);
    -- (iii) relectura de v_role ya sin FOR SHARE (se elimina: FOR SHARE propio + FOR UPDATE del
    -- conjunto = ciclo de mejora de lock entre dos removes). El resto del cuerpo es igual.
    select role into v_role from task_list_user where task_list_id = p_task_list_id and user_id = v_me;
    if v_role is null then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    perform 1 from task_list_user where task_list_id = p_task_list_id order by id for update;
    select role into v_role from task_list_user where task_list_id = p_task_list_id and user_id = v_me;
    if v_role is null then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    if exists (select 1 from task_list_user
               where task_list_id = p_task_list_id and user_id = p_user_id and role = 'owner')
       and not exists (select 1 from task_list_user
                       where task_list_id = p_task_list_id and role = 'owner' and user_id <> p_user_id) then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    if p_user_id = v_me then
        raise exception 'User cannot remove themselves' using errcode = 'P0001';
    end if;
    if v_role <> 'owner' or not fn_has_permission(v_home, 'tasklist.manage') then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    delete from task_list_user where task_list_id = p_task_list_id and user_id = p_user_id;
    return '{"status":"ok"}'::json;
end $$;

create or replace function delete_calendar(p_id bigint) returns json
language plpgsql security definer set search_path = public as $$
declare
    v_me bigint := fn_my_user_id();
    v_role user_role;
    v_home bigint;
begin
    if v_me is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    -- 1.8 (§2.2/§2.3): lock del hogar primero → ACL tras el lock (for share) → owner → permiso
    v_home := fn_home_of_calendar(p_id);
    if v_home is null then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    perform fn_home_write_lock(v_home);
    -- A-6: set-lock ordenado del conjunto ACL (en vez de FOR SHARE de la fila propia); el
    -- delete cascada filas ACL en orden fisico y ciclaba con el set-lock de remove_*_user.
    perform 1 from calendar_user where calendar_id = p_id order by id for update;
    select role into v_role from calendar_user where calendar_id = p_id and user_id = v_me;
    if v_role is null then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    if v_role <> 'owner' or not fn_has_permission(v_home, 'calendar.manage') then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    delete from calendar where id = p_id;
    return '{"success":true}'::json;
end $$;

create or replace function delete_task_list(p_id bigint) returns json
language plpgsql security definer set search_path = public as $$
declare
    v_me bigint := fn_my_user_id();
    v_role user_role;
    v_home bigint;
begin
    if v_me is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    -- 1.8 (§2.2/§2.3): lock del hogar primero → ACL tras el lock (for share) → owner → permiso
    v_home := fn_home_of_task_list(p_id);
    if v_home is null then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    perform fn_home_write_lock(v_home);
    -- A-6: set-lock ordenado del conjunto ACL (en vez de FOR SHARE de la fila propia); el
    -- delete cascada filas ACL en orden fisico y ciclaba con el set-lock de remove_*_user.
    perform 1 from task_list_user where task_list_id = p_id order by id for update;
    select role into v_role from task_list_user where task_list_id = p_id and user_id = v_me;
    if v_role is null then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    if v_role <> 'owner' or not fn_has_permission(v_home, 'tasklist.manage') then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    delete from task_list where id = p_id;
    return '{"success":true}'::json;
end $$;

revoke all on function get_home_permissions(bigint),
    set_home_permissions(bigint, bigint, jsonb), get_home_audit(bigint, integer, bigint)
    from public, anon;
grant execute on function get_home_permissions(bigint),
    set_home_permissions(bigint, bigint, jsonb), get_home_audit(bigint, integer, bigint)
    to authenticated;
revoke execute on function fn_audit_permission_delta(bigint, bigint, text[], text[], text, jsonb)
    from public, anon, authenticated;

commit;
