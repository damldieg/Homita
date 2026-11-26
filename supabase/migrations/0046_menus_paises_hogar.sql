-- 0046_menus_paises_hogar.sql — change menus-paises-hogar (fase 4 de 5 del planificador de comidas):
-- el hogar elige de qué países quiere recetas (lo usará Kito en la fase 5). Una sola transacción.
-- Aditiva (D-008): una columna y dos funciones redefinidas; sin permisos ni rutas nuevas (lectura
-- `menu.view`, escritura `menu.profile.edit`).
--
-- * meal_profile.countries text[] not null default '{}': códigos ISO 3166-1 alfa-2 en mayúsculas de la
--   lista cerrada de 51 países de fn_meal_countries_valid (sin duplicados, máx. 51); vacío es válido.
-- * update_meal_profile acepta `countries` (array JSON de textos; no array o elementos no textuales y
--   códigos fuera de lista → 'Invalid meal profile', 400); los repetidos se colapsan conservando el orden.
-- * get_meal_profile lo devuelve en `profile.countries`.
-- * RLS: sin cambios (la columna cuelga de meal_profile, solo SELECT para authenticated bajo menu.view).
--
-- Rollback: scripts/supabase/rollback/rollback_0046_menus_paises_hogar.sql (borra la columna y restaura
-- las funciones de 0043).

begin;

create or replace function fn_meal_countries_valid(a text[]) returns boolean
language sql immutable as $$
    select a is not null and cardinality(a) <= 51
       and not exists (select 1 from unnest(a) v where v is null or v <> all (array['ES', 'AR', 'MX', 'CO', 'CL', 'PE', 'UY', 'VE', 'EC', 'BO', 'PY', 'CR', 'PA', 'DO', 'GT', 'HN', 'SV', 'NI', 'CU', 'PR', 'IT', 'FR', 'DE', 'PT', 'GB', 'US', 'MA', 'TR', 'CN', 'JP', 'IN', 'MY', 'PH', 'GR', 'NL', 'BE', 'SE', 'PL', 'RO', 'UA', 'RU', 'LB', 'SY', 'EG', 'DZ', 'TN', 'ET', 'NG', 'SN', 'CI', 'BR']::text[]))
       and cardinality(a) = (select count(distinct v) from unnest(a) v)
$$;

-- jsonb array de textos → text[] sin repetidos (primera aparición manda). El llamador ya validó la forma.
create or replace function fn_meal_countries_normalize(j jsonb) returns text[]
language sql immutable as $$
    select coalesce(array_agg(v order by n), array[]::text[]) from (
        select v, min(n) as n from jsonb_array_elements_text(j) with ordinality as t (v, n) group by v) x
$$;

alter table meal_profile
    add column countries text[] not null default array[]::text[]
        constraint meal_profile_countries_check check (fn_meal_countries_valid(countries));

revoke all on function fn_meal_countries_valid(text[]), fn_meal_countries_normalize(jsonb) from public, anon, authenticated;

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
                'group_by_section', p.group_by_section, 'countries', p.countries, 'preferences', p.preferences,
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
            'candidates', (select coalesce(json_agg(json_build_object(
                'id', c.id, 'home_id', c.home_id, 'kind', c.kind, 'name', c.name, 'color', c.color,
                'status', c.status, 'linked', c.app_user_id is not null)
                order by c.name collate "C", c.id), '[]'::json)
                from home_member c where c.home_id = h.id and c.kind <> 'pet' and c.status = 'active'),
            'schedule', (select coalesce(json_agg(json_build_object(
                'home_member_id', sc.home_member_id, 'weekday', sc.weekday, 'slot', sc.slot, 'status', sc.status)
                order by sc.home_member_id, sc.weekday, sc.slot), '[]'::json)
                from meal_schedule sc where sc.home_id = h.id)
        ) from home h where h.id = v_home
    );
end $$;

create or replace function update_meal_profile(p_data jsonb) returns json
language plpgsql security definer set search_path = public as $$
declare
    v_home bigint;
    v_keys text[] := array['week_start_day', 'shopping_day', 'cook_minutes_weekday', 'cook_minutes_weekend',
        'cook_skill', 'equipment', 'freezer_space', 'repeat_policy', 'leftovers', 'dessert',
        'budget_weekly', 'task_list_id', 'group_by_section', 'countries', 'preferences'];
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
        if jsonb_typeof(p_data->'task_list_id') <> 'number' or (p_data->>'task_list_id') !~ '^[0-9]{1,18}$' then
            raise exception 'Invalid meal profile' using errcode = 'P0001';
        end if;
        select tl.id into v_list from task_list tl
        where tl.id = (p_data->>'task_list_id')::bigint and tl.home_id = v_home;
        if v_list is null then
            raise exception 'Invalid meal profile' using errcode = 'P0001';
        end if;
    end if;
    -- países (lista cerrada ISO 3166-1 alfa-2): array de textos; la lista vacía es válida
    if p_data ? 'countries' and (jsonb_typeof(p_data->'countries') <> 'array'
       or exists (select 1 from jsonb_array_elements(p_data->'countries') e where jsonb_typeof(e) <> 'string')) then
        raise exception 'Invalid meal profile' using errcode = 'P0001';
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
            countries = case when p_data ? 'countries' then fn_meal_countries_normalize(p_data->'countries') else p.countries end,
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

commit;
