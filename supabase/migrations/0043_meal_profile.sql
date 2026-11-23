-- 0043_meal_profile.sql — change menus-perfil-hogar (fase 1 de 5 del planificador de comidas):
-- perfil de hogar, perfil por miembro, semana tipo y franjas horarias. Una sola transacción.
-- Rutas Edge /meal/* aditivas (D-008); nada toca 0001–0042.
--
-- Matriz de permisos `menu.*` por kind (T1, tabla de docs/planificador-comidas/brief.md; el admin
-- los tiene todos por fn_has_permission, sin filas en membership_permission):
--   código               adult  child  relative  guest
--   menu.view             sí     sí      sí       no
--   menu.plan.manage      sí     no      sí       no
--   menu.shopping.edit    sí     sí      sí       no
--   menu.profile.edit     sí     no      no       no
--   menu.health.view      sí     no      no       no
-- Cifras: permission 23 → 28; member_kind_default 37 → 47 (+10): adult 18 → 23, child 6 → 8,
-- relative 10 → 13, guest 3 → 3 (adult +5, child +2, relative +3 = +10; 37 + 10 = 47).
--
-- Contenido:
-- * Tablas meal_profile (1 por hogar), meal_profile_member (por home_member que come; nunca pet),
--   meal_schedule (miembro × día × franja) y meal_slot_setting (franja, activa, hora). Restricciones
--   duras (B1, B2, B5, D2, franjas, A2, rangos) en columnas tipadas con check; preferencias blandas
--   en `preferences jsonb` + `schema_version`.
-- * B3/B4 (intolerancias y condiciones médicas) quedan FUERA del piloto: sin columnas ni UI. Hueco
--   documentado: se añadirán como columnas propias (dato de salud, RGPD) y se leerán con
--   `menu.health.view`, que ya existe en el catálogo.
-- * RLS: solo SELECT para authenticated (miembro del hogar con menu.view); sin policies de escritura.
--   Escribe solo RPC security definer con fn_has_permission + audit_log.
-- * Valores por defecto: perfil y franjas (comida 14:00 y cena 21:00 activas) se siembran de forma
--   perezosa con fn_meal_profile_ensure, llamada desde las RPC; no hay trigger sobre `home`.
-- * Backfill de membership_permission: solo códigos menu.*, solo role = member, `on conflict do
--   nothing`, por el kind de su home_member. NO se llama a fn_seed_kind_permissions (reemplaza el
--   snapshot). Membresías sin home_member vinculado no tienen kind: no reciben menu.* (solo admin).
--
-- Rollback: scripts/supabase/rollback/rollback_0043_meal_profile.sql (borra las tablas y sus datos).

begin;

-- ─────────────────── (a) Catálogo de permisos y defaults por kind ───────────────────

insert into permission (code, domain, description) values
    ('menu.view', 'menu', 'Ver el perfil de comidas y los menús'),
    ('menu.plan.manage', 'menu', 'Pedir, cambiar y aceptar menús'),
    ('menu.shopping.edit', 'menu', 'Marcar la compra del menú'),
    ('menu.profile.edit', 'menu', 'Editar el perfil de comidas del hogar y de cualquier miembro'),
    ('menu.health.view', 'menu', 'Ver los datos de salud del perfil de comidas de otros miembros');

insert into member_kind_default (kind, permission_code)
select 'adult'::member_kind, c from unnest(array[
    'menu.view', 'menu.plan.manage', 'menu.shopping.edit', 'menu.profile.edit', 'menu.health.view']) as c
union all
select 'child'::member_kind, c from unnest(array['menu.view', 'menu.shopping.edit']) as c
union all
select 'relative'::member_kind, c from unnest(array[
    'menu.view', 'menu.plan.manage', 'menu.shopping.edit']) as c;

-- Backfill: añade a las membresías `member` existentes solo los menu.* que les faltan, según el kind
-- de su home_member vinculado (patrón 0012). No toca ningún otro código ni borra nada.
insert into membership_permission (home_membership_id, permission_code)
select hm.id, d.permission_code
from home_membership hm
join home_member m on m.home_id = hm.home_id and m.app_user_id = hm.app_user_id
join member_kind_default d on d.kind = m.kind
where hm.role = 'member' and d.permission_code like 'menu.%'
on conflict do nothing;

-- ─────────────────── (b) Validadores inmutables ───────────────────

-- B1 + B2: [{"allergen": <14 de la UE | other>, "severity": no_traces | avoid_ingredient, "note"?}]
create or replace function fn_meal_allergies_valid(a jsonb) returns boolean
language sql immutable as $$
    select case when jsonb_typeof(a) = 'array' then not exists (
        select 1 from jsonb_array_elements(a) e
        where jsonb_typeof(e) <> 'object'
           or coalesce(e->>'allergen', '') <> all (array[
                'gluten', 'crustaceans', 'egg', 'fish', 'peanut', 'soy', 'milk', 'tree_nuts', 'celery',
                'mustard', 'sesame', 'sulphites', 'lupin', 'molluscs', 'other'])
           or coalesce(e->>'severity', '') <> all (array['no_traces', 'avoid_ingredient'])
    ) else false end
$$;

create or replace function fn_meal_jsonb_to_text_array(j jsonb) returns text[]
language sql immutable as $$
    select coalesce(array_agg(v), array[]::text[]) from jsonb_array_elements_text(j) v
$$;

-- ─────────────────── (c) Tablas ───────────────────

-- Hogar (D1 va en meal_slot_setting): D3, E1–E6, F1–F7, G1–G6, H2.
create table meal_profile (
    home_id bigint primary key references home (id) on delete cascade,
    week_start_day smallint not null default 1 check (week_start_day between 1 and 7),     -- D3 (1 = lunes)
    shopping_day smallint not null default 6 check (shopping_day between 1 and 7),         -- D3 (6 = sábado)
    cook_minutes_weekday smallint check (cook_minutes_weekday in (15, 30, 45, 60)),        -- E1 simple
    cook_minutes_weekend smallint check (cook_minutes_weekend in (15, 30, 45, 60)),        -- E1 simple
    cook_skill text check (cook_skill in ('basic', 'medium', 'advanced')),                 -- E2
    equipment text[] not null default array['stove', 'oven', 'microwave']::text[]          -- E5
        check (equipment <@ array['oven', 'microwave', 'induction', 'gas', 'stove', 'robot', 'pressure_cooker',
                                  'air_fryer', 'slow_cooker', 'griddle', 'blender', 'barbecue']::text[]),
    freezer_space text check (freezer_space in ('little', 'normal', 'lots')),              -- E6
    repeat_policy text check (repeat_policy in ('never_2_weeks', 'once_week', 'any')),     -- F3
    leftovers text check (leftovers in ('use', 'no')),                                     -- F6
    dessert text check (dessert in ('fruit', 'dairy', 'sweet_weekend', 'none')),           -- F7
    budget_weekly numeric(8, 2) check (budget_weekly >= 0),                                -- G1 orientativo, EUR
    task_list_id bigint references task_list (id) on delete set null,                      -- G5
    group_by_section boolean not null default true,                                        -- G6
    -- E3, E4, F1, F2, F4, F5, G2, G3, G4, H2 y lo que crezca: preferencias blandas
    preferences jsonb not null default '{}'::jsonb check (jsonb_typeof(preferences) = 'object'),
    schema_version integer not null default 1,
    created_at timestamp without time zone not null default (now() at time zone 'UTC'),
    updated_at timestamp without time zone not null default (now() at time zone 'UTC')
);

-- Persona que come en casa (A1: existir aquí = comer). A2, A3, B1+B2, B5, B6, C1–C4. Sin B3/B4.
create table meal_profile_member (
    home_member_id bigint primary key,
    home_id bigint not null,
    age_band text not null default 'adult'
        check (age_band in ('0-1', '1-3', '4-12', '13-17', 'adult', '65+')),               -- A2
    portion_size text check (portion_size in ('small', 'normal', 'large')),               -- A3
    allergies_answered boolean not null default false,                                     -- B1 obligatoria
    allergies jsonb not null default '[]'::jsonb check (fn_meal_allergies_valid(allergies)),  -- B1 + B2
    diet text not null default 'omnivore' check (diet in (                                 -- B5
        'omnivore', 'flexitarian', 'pescatarian', 'vegetarian', 'vegan', 'no_pork', 'halal', 'kosher', 'other')),
    diet_note text,
    goals text[] not null default array[]::text[]                                          -- B6
        check (goals <@ array['more_veg', 'less_red_meat', 'less_ultraprocessed', 'lose_weight',
                              'more_protein']::text[]),
    dislikes text[] not null default array[]::text[],                                      -- C1
    favorites text[] not null default array[]::text[],                                     -- C2
    quirks text,                                                                           -- C3
    spice smallint check (spice between 0 and 3),                                          -- C4
    preferences jsonb not null default '{}'::jsonb check (jsonb_typeof(preferences) = 'object'),
    schema_version integer not null default 1,
    created_at timestamp without time zone not null default (now() at time zone 'UTC'),
    updated_at timestamp without time zone not null default (now() at time zone 'UTC'),
    constraint meal_profile_member_allergies_answered
        check (allergies_answered or jsonb_array_length(allergies) = 0),
    constraint meal_profile_member_member_fk foreign key (home_member_id, home_id)
        references home_member (id, home_id) on delete cascade
);
create index meal_profile_member_home_idx on meal_profile_member (home_id);

-- D2/D4/D5: miembro × día (1 = lunes) × franja. Sin fila = en casa (por defecto todos en casa).
create table meal_schedule (
    home_member_id bigint not null,
    home_id bigint not null,
    weekday smallint not null check (weekday between 1 and 7),
    slot text not null check (slot in ('breakfast', 'midmorning', 'lunch', 'snack', 'dinner')),
    status text not null default 'home' check (status in ('home', 'out', 'skip', 'lunchbox')),
    updated_at timestamp without time zone not null default (now() at time zone 'UTC'),
    primary key (home_member_id, weekday, slot),
    constraint meal_schedule_member_fk foreign key (home_member_id, home_id)
        references home_member (id, home_id) on delete cascade
);
create index meal_schedule_home_idx on meal_schedule (home_id);

-- D1: franjas del hogar; la hora es local (home.timezone) y se guarda sin zona.
create table meal_slot_setting (
    home_id bigint not null references home (id) on delete cascade,
    slot text not null check (slot in ('breakfast', 'midmorning', 'lunch', 'snack', 'dinner')),
    enabled boolean not null default false,
    time time without time zone not null,
    updated_at timestamp without time zone not null default (now() at time zone 'UTC'),
    primary key (home_id, slot)
);

-- Mascotas fuera (un CHECK no puede mirar otra tabla) y pertenencia al hogar (la FK compuesta ya la
-- exige; el trigger devuelve un error claro y cubre el UPDATE de home_member_id).
create or replace function fn_meal_member_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare
    v_kind member_kind;
    v_home bigint;
begin
    select hm.kind, hm.home_id into v_kind, v_home from home_member hm where hm.id = new.home_member_id;
    if not found or v_home is distinct from new.home_id then
        raise exception 'Invalid member' using errcode = 'P0001';
    end if;
    if v_kind = 'pet' then
        raise exception 'Invalid member' using errcode = 'P0001';
    end if;
    return new;
end $$;

create trigger meal_profile_member_guard before insert or update on meal_profile_member
    for each row execute function fn_meal_member_guard();
create trigger meal_schedule_guard before insert or update on meal_schedule
    for each row execute function fn_meal_member_guard();

-- RLS: solo lectura para authenticated (miembro del hogar con menu.view); sin policies de escritura.
alter table meal_profile enable row level security;
alter table meal_profile_member enable row level security;
alter table meal_schedule enable row level security;
alter table meal_slot_setting enable row level security;
revoke all on meal_profile, meal_profile_member, meal_schedule, meal_slot_setting
    from public, anon, authenticated;
grant select on meal_profile, meal_profile_member, meal_schedule, meal_slot_setting to authenticated;

create policy meal_profile_select on meal_profile for select to authenticated
    using (home_id = any (fn_my_home_ids()) and fn_has_permission(home_id, 'menu.view'));
create policy meal_profile_member_select on meal_profile_member for select to authenticated
    using (home_id = any (fn_my_home_ids()) and fn_has_permission(home_id, 'menu.view'));
create policy meal_schedule_select on meal_schedule for select to authenticated
    using (home_id = any (fn_my_home_ids()) and fn_has_permission(home_id, 'menu.view'));
create policy meal_slot_setting_select on meal_slot_setting for select to authenticated
    using (home_id = any (fn_my_home_ids()) and fn_has_permission(home_id, 'menu.view'));

-- ─────────────────── (d) Alta perezosa de perfil y franjas ───────────────────

create or replace function fn_meal_profile_ensure(p_home_id bigint) returns void
language plpgsql security definer set search_path = public as $$
begin
    insert into meal_profile (home_id) values (p_home_id) on conflict do nothing;
    insert into meal_slot_setting (home_id, slot, enabled, time)
    select p_home_id, s.slot, s.enabled, s.time::time
    from (values ('breakfast', false, '08:00'), ('midmorning', false, '11:00'), ('lunch', true, '14:00'),
                 ('snack', false, '17:30'), ('dinner', true, '21:00')) as s (slot, enabled, time)
    on conflict do nothing;
end $$;

-- ─────────────────── (e) RPC ───────────────────

-- Lectura: menu.view obligatorio. B1/B2 viajan con menu.view; B3/B4 no existen en el piloto (el
-- contrato ya los omite). El hogar es el de X-Home-Id o el de fn_home_for_root_create().
create or replace function get_meal_profile() returns json
language plpgsql security definer set search_path = public as $$
declare
    v_home bigint;
begin
    if fn_my_user_id() is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    v_home := fn_home_for_root_create();
    perform fn_require_permission(v_home, 'menu.view');
    perform fn_meal_profile_ensure(v_home);
    return (
        select json_build_object(
            'home_id', h.id,
            'timezone', h.timezone,
            'can_edit', fn_has_permission(h.id, 'menu.profile.edit'),
            'profile', (select json_build_object(
                'week_start_day', p.week_start_day, 'shopping_day', p.shopping_day,
                'cook_minutes_weekday', p.cook_minutes_weekday, 'cook_minutes_weekend', p.cook_minutes_weekend,
                'cook_skill', p.cook_skill, 'equipment', p.equipment, 'freezer_space', p.freezer_space,
                'repeat_policy', p.repeat_policy, 'leftovers', p.leftovers, 'dessert', p.dessert,
                'budget_weekly', p.budget_weekly, 'task_list_id', p.task_list_id,
                'group_by_section', p.group_by_section, 'preferences', p.preferences,
                'schema_version', p.schema_version)
                from meal_profile p where p.home_id = h.id),
            'slots', (select coalesce(json_agg(json_build_object(
                'slot', s.slot, 'enabled', s.enabled, 'time', to_char(s.time, 'HH24:MI'))
                order by array_position(array['breakfast', 'midmorning', 'lunch', 'snack', 'dinner'], s.slot)),
                '[]'::json) from meal_slot_setting s where s.home_id = h.id),
            'members', (select coalesce(json_agg(json_build_object(
                'home_member_id', m.id, 'name', m.name, 'kind', m.kind, 'color', m.color,
                'linked', m.app_user_id is not null,
                'is_me', m.app_user_id is not null and m.app_user_id = fn_my_user_id(),
                'age_band', pm.age_band, 'portion_size', pm.portion_size,
                'allergies_answered', pm.allergies_answered, 'allergies', pm.allergies,
                'diet', pm.diet, 'diet_note', pm.diet_note, 'goals', pm.goals,
                'dislikes', pm.dislikes, 'favorites', pm.favorites, 'quirks', pm.quirks, 'spice', pm.spice,
                'preferences', pm.preferences) order by m.name collate "C", m.id), '[]'::json)
                from meal_profile_member pm join home_member m on m.id = pm.home_member_id
                where pm.home_id = h.id),
            'schedule', (select coalesce(json_agg(json_build_object(
                'home_member_id', sc.home_member_id, 'weekday', sc.weekday, 'slot', sc.slot, 'status', sc.status)
                order by sc.home_member_id, sc.weekday, sc.slot), '[]'::json)
                from meal_schedule sc where sc.home_id = h.id)
        ) from home h where h.id = v_home
    );
end $$;

-- Escribe (D3, E, F, G, H2). Solo menu.profile.edit. p_data: claves tipadas + `preferences` (merge).
create or replace function update_meal_profile(p_data jsonb) returns json
language plpgsql security definer set search_path = public as $$
declare
    v_home bigint;
    v_keys text[] := array['week_start_day', 'shopping_day', 'cook_minutes_weekday', 'cook_minutes_weekend',
        'cook_skill', 'equipment', 'freezer_space', 'repeat_policy', 'leftovers', 'dessert',
        'budget_weekly', 'task_list_id', 'group_by_section', 'preferences'];
    v_list bigint;
begin
    if fn_my_user_id() is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    v_home := fn_home_for_root_create();
    perform fn_require_permission(v_home, 'menu.profile.edit');
    if p_data is null or jsonb_typeof(p_data) <> 'object' then
        raise exception 'Invalid meal profile' using errcode = 'P0001';
    end if;
    if exists (select 1 from jsonb_object_keys(p_data) k where k <> all (v_keys)) then
        raise exception 'Invalid meal profile' using errcode = 'P0001';
    end if;
    perform fn_home_write_lock(v_home);
    perform fn_meal_profile_ensure(v_home);
    if p_data ? 'task_list_id' and jsonb_typeof(p_data->'task_list_id') <> 'null' then
        -- G5: la lista debe ser del hogar (misma respuesta si no existe o es de otro hogar)
        select tl.id into v_list from task_list tl
        where tl.id = (p_data->>'task_list_id')::bigint and tl.home_id = v_home;
        if v_list is null then
            raise exception 'Invalid meal profile' using errcode = 'P0001';
        end if;
    end if;
    if p_data ? 'preferences' and jsonb_typeof(p_data->'preferences') <> 'object' then
        raise exception 'Invalid meal profile' using errcode = 'P0001';
    end if;
    begin
        update meal_profile p set
            week_start_day = case when p_data ? 'week_start_day' then (p_data->>'week_start_day')::smallint else p.week_start_day end,
            shopping_day = case when p_data ? 'shopping_day' then (p_data->>'shopping_day')::smallint else p.shopping_day end,
            cook_minutes_weekday = case when p_data ? 'cook_minutes_weekday' then (p_data->>'cook_minutes_weekday')::smallint else p.cook_minutes_weekday end,
            cook_minutes_weekend = case when p_data ? 'cook_minutes_weekend' then (p_data->>'cook_minutes_weekend')::smallint else p.cook_minutes_weekend end,
            cook_skill = case when p_data ? 'cook_skill' then p_data->>'cook_skill' else p.cook_skill end,
            equipment = case when p_data ? 'equipment' then fn_meal_jsonb_to_text_array(p_data->'equipment') else p.equipment end,
            freezer_space = case when p_data ? 'freezer_space' then p_data->>'freezer_space' else p.freezer_space end,
            repeat_policy = case when p_data ? 'repeat_policy' then p_data->>'repeat_policy' else p.repeat_policy end,
            leftovers = case when p_data ? 'leftovers' then p_data->>'leftovers' else p.leftovers end,
            dessert = case when p_data ? 'dessert' then p_data->>'dessert' else p.dessert end,
            budget_weekly = case when p_data ? 'budget_weekly' then (p_data->>'budget_weekly')::numeric else p.budget_weekly end,
            task_list_id = case when p_data ? 'task_list_id' then (p_data->>'task_list_id')::bigint else p.task_list_id end,
            group_by_section = case when p_data ? 'group_by_section' then (p_data->>'group_by_section')::boolean else p.group_by_section end,
            preferences = case when p_data ? 'preferences' then p.preferences || (p_data->'preferences') else p.preferences end,
            updated_at = (now() at time zone 'UTC')
        where p.home_id = v_home;
    exception when check_violation or not_null_violation or invalid_text_representation
        or numeric_value_out_of_range or invalid_parameter_value or datatype_mismatch then
        raise exception 'Invalid meal profile' using errcode = 'P0001';
    end;
    insert into audit_log (home_id, actor_app_user_id, action, target_type, target_id, payload)
    values (v_home, fn_my_user_id(), 'meal.profile.update', 'meal_profile', v_home,
            jsonb_build_object('fields', (select coalesce(jsonb_agg(k order by k), '[]'::jsonb)
                                          from jsonb_object_keys(p_data) k)));
    return json_build_object('success', true);
end $$;

-- Escribe el perfil de un miembro que come (A2, A3, B1+B2, B5, B6, C1–C4). Crea la fila si no existe
-- (marcar «come» en A1). Con `eats = false` borra la ficha. Permiso menu.profile.edit; excepción:
-- la persona con cuenta edita solo su bloque C (dislikes, favorites, quirks, spice) sin él.
create or replace function update_meal_profile_member(p_member_id bigint, p_data jsonb) returns json
language plpgsql security definer set search_path = public as $$
declare
    v_home bigint;
    v_mhome bigint;
    v_kind member_kind;
    v_linked bigint;
    v_exists boolean;
    v_keys text[] := array['eats', 'age_band', 'portion_size', 'allergies_answered', 'allergies', 'diet',
        'diet_note', 'goals', 'dislikes', 'favorites', 'quirks', 'spice', 'preferences'];
    v_block_c text[] := array['dislikes', 'favorites', 'quirks', 'spice'];
    v_age text;
begin
    if fn_my_user_id() is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    v_home := fn_home_for_root_create();
    perform fn_require_member(v_home);
    select hm.home_id, hm.kind, hm.app_user_id into v_mhome, v_kind, v_linked
    from home_member hm where hm.id = p_member_id;
    -- miembro inexistente o de otro hogar: misma respuesta
    if v_mhome is null or v_mhome <> v_home then
        raise exception 'Not Found' using errcode = 'P0002';
    end if;
    if p_data is null or jsonb_typeof(p_data) <> 'object' then
        raise exception 'Invalid meal profile' using errcode = 'P0001';
    end if;
    if exists (select 1 from jsonb_object_keys(p_data) k where k <> all (v_keys)) then
        raise exception 'Invalid meal profile' using errcode = 'P0001';
    end if;
    if v_kind = 'pet' then
        raise exception 'Invalid member' using errcode = 'P0001';
    end if;
    select exists (select 1 from meal_profile_member where home_member_id = p_member_id) into v_exists;
    if not fn_has_permission(v_home, 'menu.profile.edit') then
        -- excepción del bloque C: la propia persona, solo C1–C4, y su ficha ya existe
        if v_linked is null or v_linked is distinct from fn_my_user_id()
           or exists (select 1 from jsonb_object_keys(p_data) k where k <> all (v_block_c)) then
            raise exception 'Not Allowed' using errcode = '42501';
        end if;
        if not v_exists then
            raise exception 'Not Found' using errcode = 'P0002';
        end if;
    end if;
    perform fn_home_write_lock(v_home);
    perform fn_meal_profile_ensure(v_home);
    if p_data ? 'preferences' and jsonb_typeof(p_data->'preferences') <> 'object' then
        raise exception 'Invalid meal profile' using errcode = 'P0001';
    end if;
    if p_data ? 'eats' and jsonb_typeof(p_data->'eats') = 'boolean' and not (p_data->>'eats')::boolean then
        delete from meal_profile_member where home_member_id = p_member_id;
        insert into audit_log (home_id, actor_app_user_id, action, target_type, target_id, payload)
        values (v_home, fn_my_user_id(), 'meal.member.remove', 'home_member', p_member_id, '{}'::jsonb);
        return json_build_object('success', true, 'eats', false);
    end if;
    if p_data ? 'eats' and jsonb_typeof(p_data->'eats') <> 'boolean' then
        raise exception 'Invalid meal profile' using errcode = 'P0001';
    end if;
    begin
        if not v_exists then
            v_age := case v_kind when 'child' then '4-12' else 'adult' end;
            insert into meal_profile_member (home_member_id, home_id, age_band)
            values (p_member_id, v_home, coalesce(p_data->>'age_band', v_age));
        end if;
        update meal_profile_member m set
            age_band = case when p_data ? 'age_band' then p_data->>'age_band' else m.age_band end,
            portion_size = case when p_data ? 'portion_size' then p_data->>'portion_size' else m.portion_size end,
            allergies_answered = case when p_data ? 'allergies_answered' then (p_data->>'allergies_answered')::boolean else m.allergies_answered end,
            allergies = case when p_data ? 'allergies' then p_data->'allergies' else m.allergies end,
            diet = case when p_data ? 'diet' then p_data->>'diet' else m.diet end,
            diet_note = case when p_data ? 'diet_note' then p_data->>'diet_note' else m.diet_note end,
            goals = case when p_data ? 'goals' then fn_meal_jsonb_to_text_array(p_data->'goals') else m.goals end,
            dislikes = case when p_data ? 'dislikes' then fn_meal_jsonb_to_text_array(p_data->'dislikes') else m.dislikes end,
            favorites = case when p_data ? 'favorites' then fn_meal_jsonb_to_text_array(p_data->'favorites') else m.favorites end,
            quirks = case when p_data ? 'quirks' then p_data->>'quirks' else m.quirks end,
            spice = case when p_data ? 'spice' then (p_data->>'spice')::smallint else m.spice end,
            preferences = case when p_data ? 'preferences' then m.preferences || (p_data->'preferences') else m.preferences end,
            updated_at = (now() at time zone 'UTC')
        where m.home_member_id = p_member_id;
    exception when check_violation or not_null_violation or invalid_text_representation
        or numeric_value_out_of_range or invalid_parameter_value or datatype_mismatch then
        raise exception 'Invalid meal profile' using errcode = 'P0001';
    end;
    -- solo nombres de campo en el audit (B1/B2 son datos de salud: no se copian a audit_log)
    insert into audit_log (home_id, actor_app_user_id, action, target_type, target_id, payload)
    values (v_home, fn_my_user_id(), 'meal.member.update', 'home_member', p_member_id,
            jsonb_build_object('fields', (select coalesce(jsonb_agg(k order by k), '[]'::jsonb)
                                          from jsonb_object_keys(p_data) k)));
    return json_build_object('success', true, 'eats', true);
end $$;

-- D2/D4/D5: p_entries = [{"home_member_id", "weekday" 1-7, "slot", "status"}]. Upsert; menu.profile.edit.
create or replace function set_meal_schedule(p_entries jsonb) returns json
language plpgsql security definer set search_path = public as $$
declare
    v_home bigint;
    v_e jsonb;
    v_mid bigint;
    v_n integer := 0;
begin
    if fn_my_user_id() is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    v_home := fn_home_for_root_create();
    perform fn_require_permission(v_home, 'menu.profile.edit');
    if p_entries is null or jsonb_typeof(p_entries) <> 'array' then
        raise exception 'Invalid meal profile' using errcode = 'P0001';
    end if;
    perform fn_home_write_lock(v_home);
    perform fn_meal_profile_ensure(v_home);
    begin
        for v_e in select e from jsonb_array_elements(p_entries) e loop
            if jsonb_typeof(v_e) <> 'object' or coalesce(jsonb_typeof(v_e->'home_member_id'), '') <> 'number' then
                raise exception 'Invalid meal profile' using errcode = 'P0001';
            end if;
            v_mid := (v_e->>'home_member_id')::bigint;
            -- miembro de otro hogar o inexistente: misma respuesta (404)
            if not exists (select 1 from home_member hm where hm.id = v_mid and hm.home_id = v_home) then
                raise exception 'Not Found' using errcode = 'P0002';
            end if;
            insert into meal_schedule (home_member_id, home_id, weekday, slot, status)
            values (v_mid, v_home, (v_e->>'weekday')::smallint, v_e->>'slot', coalesce(v_e->>'status', 'home'))
            on conflict (home_member_id, weekday, slot)
            do update set status = excluded.status, updated_at = (now() at time zone 'UTC');
            v_n := v_n + 1;
        end loop;
    exception when check_violation or not_null_violation or invalid_text_representation
        or numeric_value_out_of_range or invalid_parameter_value or datatype_mismatch then
        raise exception 'Invalid meal profile' using errcode = 'P0001';
    end;
    insert into audit_log (home_id, actor_app_user_id, action, target_type, target_id, payload)
    values (v_home, fn_my_user_id(), 'meal.schedule.set', 'meal_profile', v_home,
            jsonb_build_object('entries', v_n));
    return json_build_object('success', true, 'entries', v_n);
end $$;

-- D1: p_slots = [{"slot", "enabled"?, "time"?}]. Las franjas ya existen (ensure); menu.profile.edit.
create or replace function set_meal_slot_settings(p_slots jsonb) returns json
language plpgsql security definer set search_path = public as $$
declare
    v_home bigint;
    v_s jsonb;
    v_n integer := 0;
begin
    if fn_my_user_id() is null then
        raise exception 'Not Allowed' using errcode = '42501';
    end if;
    v_home := fn_home_for_root_create();
    perform fn_require_permission(v_home, 'menu.profile.edit');
    if p_slots is null or jsonb_typeof(p_slots) <> 'array' then
        raise exception 'Invalid meal profile' using errcode = 'P0001';
    end if;
    perform fn_home_write_lock(v_home);
    perform fn_meal_profile_ensure(v_home);
    begin
        for v_s in select e from jsonb_array_elements(p_slots) e loop
            if jsonb_typeof(v_s) <> 'object' then
                raise exception 'Invalid meal profile' using errcode = 'P0001';
            end if;
            update meal_slot_setting s set
                enabled = case when v_s ? 'enabled' then (v_s->>'enabled')::boolean else s.enabled end,
                time = case when v_s ? 'time' then (v_s->>'time')::time else s.time end,
                updated_at = (now() at time zone 'UTC')
            where s.home_id = v_home and s.slot = v_s->>'slot';
            if not found then
                raise exception 'Invalid meal profile' using errcode = 'P0001';
            end if;
            v_n := v_n + 1;
        end loop;
    exception when check_violation or not_null_violation or invalid_text_representation
        or numeric_value_out_of_range or invalid_parameter_value or datatype_mismatch
        or invalid_datetime_format or datetime_field_overflow then
        raise exception 'Invalid meal profile' using errcode = 'P0001';
    end;
    insert into audit_log (home_id, actor_app_user_id, action, target_type, target_id, payload)
    values (v_home, fn_my_user_id(), 'meal.slots.set', 'meal_profile', v_home,
            jsonb_build_object('slots', v_n));
    return json_build_object('success', true, 'slots', v_n);
end $$;

-- Grants: helpers internos sin acceso externo; RPC solo para authenticated.
revoke all on function fn_meal_profile_ensure(bigint), fn_meal_member_guard(),
    fn_meal_allergies_valid(jsonb), fn_meal_jsonb_to_text_array(jsonb) from public, anon, authenticated;
revoke all on function get_meal_profile(), update_meal_profile(jsonb), update_meal_profile_member(bigint, jsonb),
    set_meal_schedule(jsonb), set_meal_slot_settings(jsonb) from public, anon;
grant execute on function get_meal_profile(), update_meal_profile(jsonb), update_meal_profile_member(bigint, jsonb),
    set_meal_schedule(jsonb), set_meal_slot_settings(jsonb) to authenticated;
-- el check de alergias lo evalúa Postgres como owner de la tabla; los validadores no necesitan grant

-- ─────────────────── (f) Aserciones de catálogo ───────────────────

do $$
declare
    v_n bigint;
begin
    select count(*) into v_n from permission;
    if v_n <> 28 then raise exception 'Aserción 0043: permission = % (esperado 28)', v_n; end if;
    select count(*) into v_n from member_kind_default;
    if v_n <> 47 then raise exception 'Aserción 0043: member_kind_default = % (esperado 47)', v_n; end if;
    if (select count(*) from member_kind_default where kind = 'adult') <> 23
       or (select count(*) from member_kind_default where kind = 'child') <> 8
       or (select count(*) from member_kind_default where kind = 'relative') <> 13
       or (select count(*) from member_kind_default where kind = 'guest') <> 3 then
        raise exception 'Aserción 0043: defaults por kind distintos de 23/8/13/3';
    end if;
end $$;

commit;
