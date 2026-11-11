# Supabase (fase 1 de D-002)

Backend único del proyecto: esquema Postgres, Supabase Auth, RLS y la Edge Function `api` con el
contrato (a) PHP-compat (D-008) ruta a ruta — las 3 rutas de lectura del dashboard
(`POST /user/auth`, `GET /event`, `GET /task`) y las 43 del contrato de la app gestora (control-api).
El dashboard de producción apunta aquí desde el corte (2026-11-08); el backend PHP legacy se retiró
del repo (change `remove-php-legacy`, tag `legacy-php-final`).
Los comandos usan `supabase …`; sin CLI instalada, `npx supabase@latest …`.

> **Despliegue a producción:** prohibido `supabase db push` / `supabase functions deploy` contra el
> proyecto alojado fuera de la tarea T19 de `control-api`, que exige confirmación explícita del
> usuario. Las verificaciones se hacen en el stack local (`supabase start`); nunca escribir contra
> producción (cuenta familiar real).

## Variables de entorno (secretos: nunca en git)

| Variable | Uso |
|---|---|
| `SUPABASE_URL` | URL del proyecto (alojado o stack local) |
| `SUPABASE_ANON_KEY` | Cliente usuario (PostgREST/Edge, RLS activa) |
| `SUPABASE_SERVICE_ROLE_KEY` | Migración, seed, fixtures y materialización (BYPASSRLS) |
| `SUPABASE_DB_URL` | (opcional) psql para verificación de esquema |
| `SUPABASE_ACCESS_TOKEN` | Token personal del CLI (`login`, `link`, `migration list`, `db push`, `functions deploy`) |
| `SUPABASE_PROJECT_REF` | Ref del proyecto para `supabase link --project-ref` |
| `ALLOW_REGISTRATION` | Secreto de la función (`functions serve --env-file` o Supabase Secrets): alta abierta de usuarios (`POST user/create`). Default `false` (registro cerrado, Q3); ver `docs/SETUP.md` |

## Stack local (Docker)

```sh
supabase start                        # arranca el stack local (ver config.toml)
supabase status                       # URL y claves locales → exportarlas como env vars
supabase db reset                     # aplica supabase/migrations/ sobre la BD local
supabase functions serve api --no-verify-jwt   # sirve la Edge Function en local
supabase stop                         # para el stack
```

## Proyecto alojado (claves en env vars, nunca en git)

```sh
export SUPABASE_ACCESS_TOKEN=… SUPABASE_PROJECT_REF=…
supabase login
supabase link --project-ref "$SUPABASE_PROJECT_REF"
supabase migration list               # debe listar 0 aplicadas en proyecto limpio
supabase db push
supabase functions deploy api --no-verify-jwt  # auth manual dentro de la función
```

Variantes probadas contra el proyecto alojado (2026-11-08) con un PAT de scopes limitados:

- Si `link` falla con `Missing required permission(s): project_admin_read`, no hace falta link: usar
  `supabase db push --remote="$SUPABASE_PROJECT_REF" --yes` y
  `supabase functions deploy api --no-verify-jwt --remote="$SUPABASE_PROJECT_REF" --yes`.
- La CLI 3.x en modo agente exige `--yes` explícito para mutaciones hosted (`db push`, `functions deploy`).
- `config/auth` vía Management API (`api.supabase.com/v1/projects/<ref>/config/auth`) permite GET con el PAT
  pero el PATCH de `jwt_exp` necesita el scope `project_admin_write`; sin él, el *JWT expiry* se cambia a mano
  en el dashboard (Authentication → Settings).
- **Alta de la cuenta real** (la ejecuta el usuario con su propio email y contraseña, que no pasan por chat ni
  git): `POST $SUPABASE_URL/auth/v1/admin/users` con `SUPABASE_SERVICE_ROLE_KEY` y `email_confirm: true`;
  la respuesta JSON devuelve el `id` del usuario y el trigger `on_auth_user_created` (0004) crea su fila
  `app_user`. Comando completo (sustituye `<tu-email>`, `<tu-contraseña>` y `<tu-nombre>` al ejecutarlo;
  `~/.homita/supabase.env` es el entorno de **producción** — nunca se usa para la demo local):

  ```sh
  . ~/.homita/supabase.env
  curl -sS -X POST "$SUPABASE_URL/auth/v1/admin/users" \
    -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" \
    -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
    -H "Content-Type: application/json" \
    -d '{"email":"<tu-email>","password":"<tu-contraseña>","email_confirm":true,"user_metadata":{"name":"<tu-nombre>"}}'
  ```

## Caducidad del JWT (Q3, R1-02)

Supabase limita la expiración del access token a **604800 s (7 días, el máximo absoluto)**. Fase 1
fija ese valor (el dashboard acepta re-login semanal: un 401 limpia la sesión, cero cambios en la
app; el refresco queda para una fase posterior):

- Stack local: `auth.jwt_expiry = 604800` en `config.toml` (reiniciar con `supabase start`).
- Proyecto alojado: Authentication → Settings → *JWT expiry* = `604800` — fijado a mano por el usuario
  el 2026-11-08 y verificado el mismo día (GET `config/auth` con PAT → `jwt_exp = 604800`, y token real:
  `exp − iat` = 604800). Para re-comprobarlo: repetir ese GET (comando de arriba) o mirar
  Authentication → Settings en el dashboard.

## Orden de aplicación en proyecto limpio (R1-04)

1. `db push` de `0001`–`0003` (esquema, RLS, funciones).
2. Datos: `scripts/demo/seed_supabase.py` (demo).
3. `db push` de `0004` (trigger `auth.users` → `app_user`).
4. Deploy de la Edge Function `api`.

`0004` va después de los datos: el trigger cubre solo altas futuras.

## Migraciones

| Fichero | Contenido |
|---|---|
| `migrations/0001_schema.sql` | 3 enums + 15 tablas + índices. 10 tablas con `id bigint IDENTITY` (ids originales); 5 con PK compuesta y sin `id` (`routine_user`, `routine_exception`, `routine_event_alarm`, `event_person`, `routine_person`) |
| `migrations/0002_rls.sql` | Helpers `SECURITY DEFINER` (`fn_my_user_id`, `fn_my_calendar_ids`, `fn_my_task_list_ids`, `fn_family_user_ids`, `fn_event_in_my_calendars`, `fn_routine_in_my_calendars`) + RLS: solo SELECT con helpers, sin subconsultas a tablas RLS (R1-01); `anon` sin acceso |
| `migrations/0003_functions.sql` | `get_events`/`get_tasks` (SECURITY INVOKER, JWT del usuario) + `materialize_routines_for`/`admin_bump_sequences` (SECURITY INVOKER, solo `service_role`; `REVOKE` a `anon`/`authenticated`) |
| `migrations/0004_auth_trigger.sql` | Trigger `on auth.users insert` → `app_user` con `ON CONFLICT (auth_uid) DO NOTHING` |
| `migrations/0005_read_rpcs.sql` | RPC de lectura de la app gestora (`get_calendars`, `get_task_lists`, `get_persons`, `get_routines`, `get_*_detail`, `get_user_me`…): `SECURITY DEFINER`, guardia `fn_my_user_id()` y filtro de tenant explícito |
| `migrations/0006_write_rpcs.sql` | RPC de escritura (`create_*`, `update_*`, `delete_*`, `complete_task`, `set_event_alarm`…): `SECURITY DEFINER`, matriz owner/viewer dentro de cada RPC, mensajes PHP exactos |
| `migrations/0007_materialize_routine.sql` | `fn_materialize_one` + `materialize_routine` (materialización por rutina en escrituras). `materialize_routines_for` de 0003 queda **intacta** |
| `migrations/0008_invites.sql` | Invitación/retirada por email (`add_*_user`, `remove_*_user`), owner-only |
| `migrations/0009_task_order.sql` | `task_order` (Task::moveToPosition: splice + renumerar 1..n) |
| `migrations/0010_profile_sync.sql` | Trigger `on auth.users update` → sincronía de `app_user` (name/email) |

## Edge Function `functions/api/`

Función Deno por casos de uso, sin build step (el deploy empaqueta los imports relativos del dir
de la función). Rutas del contrato (a) PHP-compat (D-008): las 3 de lectura del dashboard y las 43
de la app gestora (41 de `ApiService.kt` + `task-list/detail` y `task/detail`). El pathname incluye el prefijo de montaje
(`/functions/v1/api/user/auth` llega como `/api/user/auth`) y la tabla exacta `{method, route} →
handler` de `index.ts` hace el dispatch (sin `endsWith`). Despliegue con `--no-verify-jwt`: la
autenticación es manual (cabecera `Bearer`, como `middlewareAuth`), el usuario se deriva del JWT
verificado y nunca del request (R1-03).

| Fichero | Contenido |
|---|---|
| `index.ts` | Entrada fina: tabla exacta de rutas, guard Bearer + verificación `/auth/v1/user`, dispatch y mapeo de errores |
| `usecases/auth.ts` | `user/auth` (password grant + `refresh_token`), `user/create`, `user/update`, `user/me`, `config` |
| `usecases/calendars.ts`, `persons.ts`, `routines.ts`, `task-lists.ts` | CRUD del dominio vía RPC |
| `usecases/events.ts` | `GET /event` (dashboard/gestora), `event/*` CRUD; el camino `text` (Gemini) responde 400 (diferido, Q2) |
| `usecases/tasks.ts` | `GET /task`, `task/*` CRUD + `task/order` |
| `_shared/supabase.ts` | Clientes/env (`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`): `passwordGrant`, `verifyUser`, `appUserRow`, `rpc`, `materializeRoutines`, `hasTaskListAccess` |
| `_shared/contract.ts` | Adaptadores puros del contrato: `json`, `fmt`, `contractBool`/`contractInt`/`contractStr`/`contractTimestamp` |
| `_shared/errors.ts` | Errores PHP: `error`, `rpcError` + constructores con los strings exactos |
| `_shared/validate.ts` | Parsers de body PHP (`0/1` booleans, `timezone`, epoch 10 dígitos) |

Comandos sin cambios: `supabase functions serve api --no-verify-jwt` y
`supabase functions deploy api --no-verify-jwt` (en hosted:
`supabase functions deploy api --no-verify-jwt --remote="$SUPABASE_PROJECT_REF" --yes`, ver
variantes arriba).

## Verificación de contrato (`scripts/supabase/contract_check.py`)

Smoke Edge-solo: aserciones de estado/valor/forma esperada por ruta contra el contrato documentado
(sin oráculo — el backend legacy se retiró con el change `remove-php-legacy`). Cubre las 43 rutas
(incluidas `GET /config` y `PATCH /user/update`): lecturas del dashboard (escenarios de
`ContentRepository` y `CalendarRepository`, `/task?dashboard=true`), lecturas de la app gestora,
escenarios de escritura create→read→update→delete y el bloque viewer de la matriz de autorización,
con las desviaciones documentadas fijadas como valor esperado (`401` vs `500` de email inexistente,
owner-only `403`, `refresh_token`, TypeError de `calendar/create` sin color). Borra los restos `CC-%`
de ejecuciones anteriores (`reset_leftovers`, service_role local), así que es repetible sin
re-sembrar. El guard de `--fn` rechaza hosts no locales: jamás debe tocar el proyecto alojado.
Exit 0 = 43/43 rutas cubiertas sin regresión; si no, lista las rutas con regresión.

```sh
scripts/demo.sh up                          # Edge local servida + seed.py (ver «Flujo demo local»)
python3 scripts/supabase/contract_check.py  # o --fn URL o SUPABASE_FUNCTIONS_URL
```

Complementos sin oráculo: `scripts/supabase/tests/expected_shape_check.py`
(forma esperada: `refresh_token`, `config` con flag `ALLOW_REGISTRATION`, Gemini 400, alta de
usuarios; se ejecuta una vez por configuración de flag) y `scripts/supabase/tests/cross_tenant_check.py`
(aislamiento entre tenants: ~55 casos, ids ajenos → `500 Not Found`, RPC directas
`/rest/v1/rpc/*` con JWT ajeno sin fugas, owner vs viewer). Fixture:
`scripts/supabase/fixture_two_families.py` (RLS).

## Flujo demo local

1. `supabase start` (una vez; Docker arriba).
2. `scripts/demo.sh app` → reset de la BD local (`supabase db reset --local`), env local,
   `functions serve`, health, seed, build debug e install. Con `scripts/demo.sh up` solo la Edge
   servida y sembrada (sin emulador), útil para `contract_check.py`.
3. `scripts/demo.sh down` → para `functions serve`; la BD local queda intacta.
4. `supabase stop` cuando se termine (decisión del usuario).

La demo es solo local: genera su propio `.demo/functions.env` (solo `ALLOW_REGISTRATION=true`; el
runtime local inyecta `SUPABASE_URL`, `SUPABASE_ANON_KEY` y `SUPABASE_SERVICE_ROLE_KEY`) y jamás usa
`~/.homita/supabase.env`, que contiene las credenciales de producción y solo se lee para operar el
proyecto alojado (sección siguiente y README raíz).
