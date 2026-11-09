-- backfill_fixture.sql — Fixture de datos para ensayar 0013 (fase 1.3, E2; plan 1.3 T4/V7).
-- Se ejecuta con psql SOBRE el esquema 0001–0011 (sin tablas home) tras scripts/demo/seed.py.
-- Cubre los casos exigidos por V7: componente con 2+ admins (colisión de nombres Q-D), member
-- viewer con 17 permisos (Q-B), ACL duplicada (CA-11), calendario huérfano con evento (CA-7),
-- asignación cruzada de person (CA-8, evento y rutina) y singleton sin ACL (fallback CA-6).
--
-- Usuarios de fixture (ids fijos, sin filas en auth.users; plan 1.3 §Cuerpos (a)):
--   101 Ana (owner cal 101), 102 Luis (owner lista 101), 103 Marta (owner cal 101),
--   104 Víctor (viewer), 105 Ana (singleton sin ACL → 'Hogar de Ana').
-- CA-15: admins Ana<Luis<Marta → 'Hogar de Ana (y Luis)'; admin único Ana(105) → 'Hogar de Ana'.
--
-- Los auth_uid son uuids ficticios (sin fila en auth.users) para poder personificar usuarios por
-- psql (request.jwt.claim.sub); se insertan con session_replication_role = replica SOLO para
-- saltar la FK a auth.users (preparación de datos de test, Q-P2). El resto va en modo normal.
-- Uso: docker exec -i <db> psql -U postgres -d postgres -v ON_ERROR_STOP=1 -f backfill_fixture.sql

do $$
begin
    if to_regclass('public.home') is not null then
        raise exception 'backfill_fixture: el esquema ya tiene tablas home (0012 aplicada); '
                        'este fixture es solo para el esquema 0001-0011';
    end if;
end $$;

-- app_user de fixture (replica: solo para bypassear la FK auth_uid → auth.users)
set session_replication_role = replica;
insert into app_user (id, auth_uid, name, email, created_at, updated_at) values
    (101, '00000000-0000-4000-8000-000000000101', 'Ana',   'ana@fixture.homita.example',   '2026-01-01 00:00:00', '2026-01-01 00:00:00'),
    (102, '00000000-0000-4000-8000-000000000102', 'Luis',  'luis@fixture.homita.example',  '2026-01-01 00:00:00', '2026-01-01 00:00:00'),
    (103, '00000000-0000-4000-8000-000000000103', 'Marta', 'marta@fixture.homita.example', '2026-01-01 00:00:00', '2026-01-01 00:00:00'),
    (104, '00000000-0000-4000-8000-000000000104', 'Víctor','victor@fixture.homita.example','2026-01-01 00:00:00', '2026-01-01 00:00:00'),
    (105, '00000000-0000-4000-8000-000000000105', 'Ana',   'ana2@fixture.homita.example',  '2026-01-01 00:00:00', '2026-01-01 00:00:00');
set session_replication_role = default;

-- Componente compartida {101,102,103,104}: Ana y Marta owners del cal 101 (2 owners),
-- Luis owner de la lista 101 (con Ana de viewer: arista de componente), Víctor viewer.
insert into calendar (id, name, color, token, created_at, updated_at) values
    (101, 'Fixture Cal Ana', '#123456', 'fixture-cal-ana', '2026-01-01 00:00:00', '2026-01-01 00:00:00');
insert into calendar_user (id, calendar_id, user_id, role, created_at, widget, dashboard) values
    (101, 101, 101, 'owner',  '2026-01-01 00:00:00', true, true),
    (102, 101, 103, 'owner',  '2026-01-01 00:00:00', true, true),
    (103, 101, 101, 'viewer', '2026-01-01 00:00:00', true, true),  -- ACL duplicada de Ana (CA-11)
    (104, 101, 104, 'viewer', '2026-01-01 00:00:00', true, true);
insert into task_list (id, name, color, token, sort, created_at, updated_at) values
    (101, 'Fixture Lista Luis', '#222222', 'fixture-list-luis', 'updated_at', '2026-01-01 00:00:00', '2026-01-01 00:00:00');
insert into task_list_user (id, task_list_id, user_id, role, created_at, widget, dashboard) values
    (101, 101, 102, 'owner',  '2026-01-01 00:00:00', true, true),
    (102, 101, 101, 'viewer', '2026-01-01 00:00:00', true, true);

-- Calendario huérfano con evento (sin ACL) → home archived (CA-7)
insert into calendar (id, name, color, token, created_at, updated_at) values
    (102, 'Fixture Huérfano', '#654321', 'fixture-cal-orphan', '2026-01-01 00:00:00', '2026-01-01 00:00:00');
insert into event (id, calendar_id, title, date_at, created_at, updated_at) values
    (901, 102, 'Fixture Evento Huérfano', '2026-12-01 10:00:00', '2026-01-01 00:00:00', '2026-01-01 00:00:00');

-- Persona del singleton (105) asignada a evento y rutina de la componente compartida → cruzada
insert into person (id, user_id, name, color, created_at, updated_at) values
    (101, 105, 'Persona Ana', '#AABBCC', '2026-01-01 00:00:00', '2026-01-01 00:00:00');
insert into event (id, calendar_id, title, date_at, created_at, updated_at) values
    (902, 101, 'Fixture Evento Cruzado', '2026-12-02 10:00:00', '2026-01-01 00:00:00', '2026-01-01 00:00:00');
insert into event_person (event_id, person_id) values (902, 101);
insert into routine (id, calendar_id, title, days, time, start_date, end_date, active, available_from,
                     frequency, "interval", created_at, updated_at) values
    (901, 101, 'Fixture Rutina Cruzada', '[1]', '09:00', '2026-11-01', null, true,
     '2026-11-01 00:00:00', 'weekly', 1, '2026-01-01 00:00:00', '2026-01-01 00:00:00');
insert into routine_person (routine_id, person_id) values (901, 101);

-- Secuencias por encima de los ids fijos (0003): las altas posteriores por API no colisionan
select admin_bump_sequences();
