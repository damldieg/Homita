# Supabase (fase 1 de D-002)

Backend paralelo a `api/` (PHP, que sigue vivo): esquema Postgres, Supabase Auth, RLS y una Edge
Function `api` que replica el contrato de lectura del dashboard (`POST /user/auth`, `GET /event`,
`GET /task`). El dashboard de producción NO apunta aquí: solo demo/verificación (decisión Q5).
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

## Proyecto alojado (claves pendientes del usuario)

```sh
export SUPABASE_ACCESS_TOKEN=… SUPABASE_PROJECT_REF=…
supabase login
supabase link --project-ref "$SUPABASE_PROJECT_REF"
supabase migration list               # debe listar 0 aplicadas en proyecto limpio
supabase db push
supabase functions deploy api --no-verify-jwt  # auth manual dentro de la función
```

## Caducidad del JWT (Q3, R1-02)

Supabase limita la expiración del access token a **604800 s (7 días, el máximo absoluto)**. Fase 1
fija ese valor (el dashboard acepta re-login semanal: un 401 limpia la sesión, cero cambios en la
app; el refresco queda para una fase posterior):

- Stack local: `auth.jwt_expiry = 604800` en `config.toml` (reiniciar con `supabase start`).
- Proyecto alojado: Authentication → Settings → *JWT expiry* = `604800` (captura/consulta como
  evidencia de la aceptación; pendiente de acceso al proyecto).

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

Función única con router interno (`user/auth`, `event`, `task`), espejo de
`api/src/Controllers/router.php`. El pathname incluye el prefijo de montaje
(`/functions/v1/api/user/auth` llega como `/api/user/auth`) y el router lo normaliza (R1-09).
Despliegue con `--no-verify-jwt`: la autenticación es manual (cabecera `Bearer`, como
`middlewareAuth`), `p_user_id` se deriva del JWT verificado y nunca del request (R1-03).

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
