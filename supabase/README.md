# Supabase (fase 1 de D-002)

Backend paralelo a `api/` (PHP, que sigue vivo): esquema Postgres, Supabase Auth, RLS y una Edge
Function `api` que replica el contrato de lectura del dashboard (`POST /user/auth`, `GET /event`,
`GET /task`). El dashboard de producción apunta aquí desde el corte (2026-11-08); `api/` (PHP) queda
como legacy de transición y vuelta atrás.
Los comandos usan `supabase …`; sin CLI instalada, `npx supabase@latest …`.

## Variables de entorno (secretos: nunca en git)

| Variable | Uso |
|---|---|
| `SUPABASE_URL` | URL del proyecto (alojado o stack local) |
| `SUPABASE_ANON_KEY` | Cliente usuario (PostgREST/Edge, RLS activa) |
| `SUPABASE_SERVICE_ROLE_KEY` | Migración, seed, fixtures y materialización (BYPASSRLS) |
| `SUPABASE_DB_URL` | (opcional) psql para verificación de esquema |
| `SUPABASE_ACCESS_TOKEN` | Token personal del CLI (`login`, `link`, `migration list`, `db push`, `functions deploy`) |
| `SUPABASE_PROJECT_REF` | Ref del proyecto para `supabase link --project-ref` |

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
  `app_user`. Comando completo (sustituye `<tu-email>`, `<tu-contraseña>` y `<tu-nombre>` al ejecutarlo):

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
2. Datos: `scripts/demo/seed_supabase.py` (demo) o `scripts/supabase/migrate_sqlite.py` (reales).
3. `db push` de `0004` (trigger `auth.users` → `app_user`).
4. Deploy de la Edge Function `api`.

`0004` va después de los datos: el trigger cubre solo altas futuras. La importación inserta
`app_user` con los ids legados tras eliminar la fila que el trigger hubiera creado para ese
`auth_uid` (doble defensa contra `UNIQUE(auth_uid)`, R1-04; ver `scripts/supabase/migrate_sqlite.py`).

### seed y migrate son alternativos (nota de colisión)

`scripts/demo/seed_supabase.py` y `scripts/supabase/migrate_sqlite.py` **no son acumulables sobre la
misma BD**: `migrate_sqlite.py` asume un objetivo limpio y, con las filas de un seed previo, aborta con
409 `UNIQUE(event_id,user_id)` (los ids del seed no coinciden con los de origen para el mismo par).
**Orden soportado**: `db push` 0001–0003 → **uno de los dos** scripts de datos (seed para la demo,
migrate para los datos reales) → `db push` 0004 → deploy. Si hace falta pasar por los dos,
`supabase db reset` entre ellos (o un objetivo vacío). Re-ejecutar cada script por separado sí es
idempotente.

## Migraciones

| Fichero | Contenido |
|---|---|
| `migrations/0001_schema.sql` | 3 enums + 15 tablas + índices. 10 tablas con `id bigint IDENTITY` (ids originales); 5 con PK compuesta y sin `id` (`routine_user`, `routine_exception`, `routine_event_alarm`, `event_person`, `routine_person`) |
| `migrations/0002_rls.sql` | Helpers `SECURITY DEFINER` (`fn_my_user_id`, `fn_my_calendar_ids`, `fn_my_task_list_ids`, `fn_family_user_ids`, `fn_event_in_my_calendars`, `fn_routine_in_my_calendars`) + RLS: solo SELECT con helpers, sin subconsultas a tablas RLS (R1-01); `anon` sin acceso |
| `migrations/0003_functions.sql` | `get_events`/`get_tasks` (SECURITY INVOKER, JWT del usuario) + `materialize_routines_for`/`admin_bump_sequences` (SECURITY INVOKER, solo `service_role`; `REVOKE` a `anon`/`authenticated`) |
| `migrations/0004_auth_trigger.sql` | Trigger `on auth.users insert` → `app_user` con `ON CONFLICT (auth_uid) DO NOTHING` |

## Edge Function `functions/api/`

Función Deno por casos de uso, sin build step (el deploy empaqueta los imports relativos del dir
de la función). Rutas `user/auth`, `event` y `task`, espejo de `api/src/Controllers/router.php`.
El pathname incluye el prefijo de montaje (`/functions/v1/api/user/auth` llega como
`/api/user/auth`) y `matchRoute` lo normaliza (R1-09). Despliegue con `--no-verify-jwt`: la
autenticación es manual (cabecera `Bearer`, como `middlewareAuth`), `p_user_id` se deriva del JWT
verificado y nunca del request (R1-03).

| Fichero | Contenido |
|---|---|
| `index.ts` | Entrada fina: rutas (`ROUTES`/`matchRoute`), guard Bearer + verificación `/auth/v1/user`, dispatch y mapeo de errores |
| `usecases/auth.ts` | `POST /user/auth`: password grant → fila `app_user` → usuario PHP |
| `usecases/events.ts` | `GET /event`: query → materialización de rutinas (service role) → `get_events` |
| `usecases/tasks.ts` | `GET /task`: check `task_list_user` → `get_tasks` |
| `_shared/supabase.ts` | Clientes/env (`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`): `passwordGrant`, `verifyUser`, `appUserRow`, `rpc`, `materializeRoutines`, `hasTaskListAccess` |
| `_shared/contract.ts` | Adaptadores puros del contrato: `json`, `fmt`, `phpBool`/`phpInt`/`phpStr`/`phpTimestamp` |
| `_shared/errors.ts` | Errores PHP: `error`, `rpcError` + constructores con los strings exactos |

Comandos sin cambios: `supabase functions serve api --no-verify-jwt` y
`supabase functions deploy api --no-verify-jwt` (en hosted:
`supabase functions deploy api --no-verify-jwt --remote="$SUPABASE_PROJECT_REF" --yes`, ver
variantes arriba).

## Verificación de contrato (`scripts/supabase/contract_check.py`)

Compara el oráculo PHP local con la Edge Function: JSON **parseado** (orden de claves irrelevante),
`token` ignorado, `created_at`/`updated_at` validados por formato `YYYY-MM-DD HH:MM:SS`, desviación de
email inexistente codificada (PHP 500 `Not Found` vs Edge 401 `Invalid credentials`, R1-08) y los
escenarios de `ContentRepository` (eventos abiertos y sesiones hoy..+7), `CalendarRepository`
(semanas lunes–domingo) y `/task?dashboard=true`. Exit 0 = contrato idéntico.

```sh
scripts/demo.sh up                          # oráculo PHP con seed.py (puerto 3001)
python3 scripts/demo/seed_supabase.py       # seed equivalente en Supabase (SUPABASE_URL + SERVICE_ROLE_KEY)
python3 scripts/supabase/contract_check.py  # o --php/--fn o CONTRACT_PHP_URL/SUPABASE_FUNCTIONS_URL
```

Nota (macOS): `scripts/demo.sh up` falla al arrancar el PHP porque `setsid` no existe en el PATH
(`exec: setsid: not found`). Limitación preexistente del script; no se toca el PATH global: arrancar el
oráculo a mano con el comando equivalente y seguir con el seed:

```sh
(cd .demo/backend && php -S 0.0.0.0:3001 -t public public/index.php > ../php.log 2>&1 &)
python3 -I scripts/demo/seed.py http://127.0.0.1:3001
```
