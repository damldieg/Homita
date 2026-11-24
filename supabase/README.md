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
| `TRELLO_KEY`, `TRELLO_TOKEN` | Secretos de `procesar-feedback` (Supabase Secrets): key y token de Trello; solo viajan en la cabecera `Authorization: OAuth …` |
| `TRELLO_LIST_ID` | Secreto de `procesar-feedback`: id de la lista «Feedback» del tablero Homita (destino de las tarjetas y fuente del gate) |
| `FEEDBACK_WEBHOOK_SECRET` | Secreto de `procesar-feedback`: valor que debe traer la cabecera `x-feedback-secret`. El **mismo valor** va en Vault como `feedback_webhook_secret` (lo lee el trigger de `0034`, junto con la URL `feedback_webhook_url`) |
| `ANTHROPIC_API_KEY`, `CLAUDE_MODEL` | Secretos de `procesar-feedback`: clave de Anthropic y modelo del gate (opcional; por defecto `claude-haiku-5-5`) |
| `ALLOW_REGISTRATION` | Secreto de la función (`functions serve --env-file` o Supabase Secrets): alta abierta de usuarios (`POST user/create`). Default `false` (registro cerrado, Q3); ver `docs/SETUP.md`. También gobierna el registro con `invitation_code` (no lo salta); contrato en `docs/CONTRATOS_HOME.md` (Invitaciones) |

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
| `migrations/0030_event_end_date.sql` | Fecha de fin opcional de eventos (change `event-end-date`, D-019); ver «Extensión `event.end_date`». Reversa: `scripts/supabase/rollback/rollback_0030.sql` |
| `migrations/0031_feedback_trigger.sql` | Trigger `homita_feedback_creation` (webhook a `procesar-feedback` de prod). Con guard: sale sin efecto si `public.feedback` no existe, así que en local nunca crea trigger (corre antes de 0032). Reemplazado por `0034`. Reversa: `scripts/supabase/rollback/rollback_0031.sql`, **solo sin 0034**: 0034 usa el mismo nombre de trigger, así que con 0034 aplicado (local, CI y prod tras P6) ese script borra el trigger de 0034 y el feedback nuevo deja de despacharse sin aviso. La reversa del trigger vigente es `rollback_0034.sql` (ver «Rollback») |
| `migrations/0032_feedback_schema.sql` | DDL `if not exists` de `public.backlog` y `public.feedback` (RLS + política «insertar mi feedback») para local/CI; no-op en prod, sin trigger. Precede a `0033`/`0034`, que se aplican sobre estas tablas. Ver «Feedback» |
| `migrations/0033_feedback_trello.sql` | Change `feedback-trello-gate` (D-021, D-023), aditiva: `backlog.trello_card_id`/`trello_card_url` + índice único parcial, `feedback.procesando_desde` (reserva) y RPC `homita_feedback_finalize` (escritura final atómica, upsert del voto con `coalesce(votos, 1) + 1`, solo `service_role`). Se aplica en local, CI y prod (guard defensivo si faltan las tablas). Reversa: `scripts/supabase/rollback/rollback_0033.sql` (pierde los vínculos con Trello) |
| `migrations/0034_feedback_trigger_secret.sql` | Change `feedback-trello-gate` (D-021, D-023): reemplaza el trigger de `0031` por `homita_feedback_notify` → `homita_feedback_dispatch` (SECURITY DEFINER, EXECUTE revocado a `anon`/`authenticated`/`service_role`), que lee de Vault la URL (`feedback_webhook_url`) y el secreto y encola `net.http_post` con cabecera `x-feedback-secret` y solo el id. El trigger existe en todos los entornos pero es inerte sin URL ni secreto en Vault (local/CI). Reversa: `scripts/supabase/rollback/rollback_0034.sql` (restaura `0031` solo si `feedback_webhook_url` de Vault es exactamente la URL de prod de P5; si falta o tiene otro valor no crea trigger; orden en «Rollback»: con la pausa de Vault hecha, tras redesplegar la antigua; sin pausa, ANTES del redeploy, con la función nueva desplegada. Nunca redeploy de la antigua con 0034 aplicado y el secreto cargado) |
| `migrations/0035_client_request_idempotency.sql` | Change `ios-offline-outbox-tareas` (D-024): tabla `client_request` y firma nueva de `create_task`/`create_task_list`. Ver «Idempotencia de creates (0035)». Reversa: `scripts/supabase/rollback/rollback_0035.sql`, **solo sin 0037**: revertir antes 0037 (`rollback_0037.sql`, orden LIFO). Con 0037 aplicada dejaría dos sobrecargas de `create_task` y `POST /task/create` daría 500; una guarda al inicio aborta el script en ese caso. Lo mismo vale para `rollback_0029.sql`, que exige además haber revertido 0030 (solo sin 0030 ni posteriores, orden LIFO: con 0030 aplicada dejaría dos sobrecargas de `create_event` y `update_event`); su guarda aborta también en ese caso |
| `migrations/0037_task_priority.sql` | Change `prioridad-tarea` (D-026): columna `task.priority` (`alta`/`media`/`baja`, default `media`), `priority` en las respuestas de tarea, filtro y orden opcionales en `get_tasks` y `p_priority` en `create_task`/`update_task`. Ver «Prioridad de tarea (0037)». Reversa: `scripts/supabase/rollback/rollback_0037.sql` (**pierde las prioridades**) |
| `migrations/0038_task_create_person_access.sql` | Change `asignar-alta-lista`: `create_task` (misma firma de 5 argumentos, `create or replace`) solo acepta en `p_person_ids` personas con cuenta y con fila en `task_list_user` de la lista; si no, 400 `Invalid person` sin crear la tarea. `update_task` no cambia. Ver «Acceso a la lista al crear (0038)». Reversa: `scripts/supabase/rollback/rollback_0038.sql` (restaura el cuerpo de 0037; sin datos), **antes** que `rollback_0037` (orden LIFO 0038 → 0037 → 0035). Despliegue en `supabase/DEPLOY_0038.md` |
| `migrations/0039_task_hidden_at.sql` | Change `ocultar-completadas-3-dias` (D-025): columna `task.hidden_at` (`timestamptz` nullable, `completed_at + 3 días` en UTC, CHECK `task_hidden_at_consistent`) con backfill de las completadas; `get_tasks` deja fuera las ocultas y `get_task_detail` y las escrituras sobre una oculta dan `Not Found` (500, como una inexistente). Mismas firmas y shapes; la Edge no cambia. Ver «Ocultar completadas (0039, D-025)». Reversa: `scripts/supabase/rollback/rollback_0039.sql` (solo se pierde `hidden_at`, derivable), **antes** que `rollback_0038` (orden LIFO 0039 → 0038 → 0037 → 0035; `rollback_0038` aborta mientras exista `task.hidden_at`). Despliegue en `supabase/DEPLOY_0039.md` |
| `migrations/0040_task_list_position.sql` | Change `lista-prioritaria-inicio`: `task_list.position integer null` (check `> 0`, global por hogar), backfill por hogar (`created_at, id`), `get_task_lists` con la clave aditiva `position` y orden `position` asc nulls last, `name`, `id`, y RPC `reorder_task_lists(bigint[])`. Ver «Orden de listas (0040)». Reversa: `scripts/supabase/rollback/rollback_0040.sql` (se pierde el orden elegido) |

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

## Edge Function `functions/procesar-feedback/`

La dispara el trigger `homita_feedback_creation` de `0034` al insertar en `public.feedback` y crea o
vincula la tarjeta en Trello, con el modelo como **gate** (change `feedback-trello-gate`, D-021/D-022/D-023).
El modelo solo clasifica: las llamadas a Trello y a la BD las hace el código.

| Fichero | Contenido |
|---|---|
| `index.ts` | Solo cableado: cliente supabase-js (service role), `createHandler`, `Deno.serve` |
| `handler.ts` | Flujo completo (auth, reserva, gate, Trello, final, compensación); dependencias inyectadas |
| `gate.ts` | Puro: prompt, topes, `parseDecision`, plantillas de tarjeta y comentario, marcador |
| `trello.ts` | Cliente Trello con `fetch` inyectado (`listCards`, `createCard`, `addComment`, `archiveCard`) |
| `db.ts` | Interfaz `FeedbackDb` + adaptador supabase-js sin lógica (`claim`, `exists`, `getEstado`, `markError`, `finalize`) |
| `tests/*_test.ts` | `deno test` con `fetch` y `db` falsos (sin red, sin Trello ni Anthropic reales) |

**Flujo** (cada paso corta si falla):

1. **Auth:** `FEEDBACK_WEBHOOK_SECRET` vacío → 500 (falla cerrado). Cabecera `x-feedback-secret`
   ausente o distinta → 401 (comparación en tiempo constante, antes de leer el body).
2. **Body:** del payload solo se usa `record.id` (entero > 0; si no, 400). Sección, tipo y texto se
   leen de la BD. Configuración de Trello/Anthropic incompleta → 500 sin reservar.
3. **Reserva atómica:** `update feedback set procesando_desde = now() where id = … and estado =
   'pendiente' and procesando_desde is null returning …`. Solo una ejecución avanza; las demás
   responden 200 «ya procesado o en curso» (o 404 si el id no existe).
4. **Tarjetas abiertas** de `TRELLO_LIST_ID`. Si una tiene en `desc` la línea exacta
   `Homita-feedback-id: <id>` (intento anterior cuyo final falló), se reutiliza sin llamar al modelo.
5. **Gate:** instrucción en `system`; reporte y tarjetas como datos en `<reporte>`/`<tarjetas>` (JSON con
   `<` escapado), máximo 100 tarjetas (las más recientes), `name` ≤ 120, `desc` ≤ 300, reporte ≤ 2000.
   Se exige exactamente un `tool_use` (`vincular_tarjeta{card_id}` o `crear_tarjeta{titulo,
   descripcion}`); `card_id` debe ser una de las tarjetas enviadas; título a una línea ≤ 120.
6. **Trello:** `crear` → `POST /1/cards` en la lista (descripción del modelo + marcador + metadatos +
   reporte citado con `> `); `vincular` → comentario en la tarjeta con el reporte citado.
7. **Final atómico:** RPC `homita_feedback_finalize` (`0033`): inserta en `backlog` con
   `trello_card_id`/`url` (vincular a una tarjeta sin fila → `votos = 2`; ya con fila →
   `coalesce(votos, 1) + 1`, upsert atómico; `votos` es nullable) y deja el feedback `procesado` con `backlog_id`.

**Fallos:** antes de escribir en Trello (lectura de tarjetas, modelo, validación) → `estado = 'error'`
y 500, sin tocar Trello ni `backlog`. Si el final falla tras crear, se relee la fila (`getEstado`):
el error puede llegar tras el COMMIT (red o corte de PostgREST). Solo si sigue `pendiente` la tarjeta se
archiva (`closed=true`, nunca DELETE) y el feedback queda en `error`; si ya está `procesado` (o la
relectura falla) **no** se archiva y se registra un log de inconsistencia con ids (feedback, tarjeta,
backlog), para revisarlo a mano. Si el archivado también falla se registra el id de la tarjeta y el
marcador evita duplicarla al reprocesar. Tras vincular, el comentario queda
(al reprocesar se repetiría). Timeouts: 8 s Trello, 20 s Anthropic. Los logs llevan solo operación,
status e ids: nunca URL, cabeceras, body, texto del reporte ni secretos.

**URL y secreto del webhook (D-023):** el trigger los lee en cada INSERT de Vault dentro de
`homita_feedback_dispatch`; el repo no contiene ningún valor ni la URL de prod (solo queda en `0031`, ya
aplicada, y en `rollback_0034`, que la restaura). Cada condición que falla hace `return null` (sin
petición, el feedback queda `pendiente`), en este orden (`0034_feedback_trigger_secret.sql:73-108`):

- a. `feedback_webhook_url` null o `''` → notice. Es el caso normal en local/CI: la entrada es la marca de
  prod (se crea en P5) y en local no existe nunca.
- b. La URL no cumple `^https://[^/[:space:]]+/functions/v1/procesar-feedback$` → warning (frena erratas de
  esquema o de ruta; no valida el host, eso lo hace P6 comparando con la URL esperada antes de P7).
- c. `feedback_webhook_secret` null o `''` → warning (ventana P6–P7 y pausa del rollback).
- d. No existe `net.http_post(text, jsonb, jsonb, jsonb, integer)` → warning.
- e. `net.http_post` a la URL con body `{type, table, schema, record: {id}}`, cabecera
  `x-feedback-secret` y timeout 30000 ms.

Ningún error del webhook hace fallar el INSERT. Mientras pg_net no ha enviado la petición, la cabecera
está en claro en `net.http_request_queue` (el esquema `net` no está expuesto en la API REST; se revisa
en el pre-check P2). Rotación: primero `supabase secrets set FEEDBACK_WEBHOOK_SECRET=…` y después
`select vault.update_secret(id, '<nuevo>')` (ventana de 401 recuperable con el reproceso).

**Grants:** `homita_feedback_finalize` solo para `service_role`; `homita_feedback_dispatch` y
`homita_feedback_notify` sin EXECUTE para `anon`, `authenticated` ni `service_role` (solo el owner, es
decir, el SQL editor). Tras `db reset` (orden `0031` → `0032_feedback_schema` → `0033` → `0034`) las
tablas, las columnas, la RPC, las funciones y el trigger existen también en local/CI, con el trigger
inerte porque Vault no tiene la URL. Los checks prueban ese estado real en transacciones con rollback:
`feedback_trello_check.sql` B1-B8 (columnas, índice, RPC, grants, votos con `coalesce`, `rollback_0033`)
y `feedback_trigger_check.sql` F1-F12 (trigger, grants, condiciones a–e con una URL
`https://feedback-test.invalid/…` y un secreto de prueba solo dentro de la transacción; `rollback_0034`
con la URL de prueba y con la de prod en F11, ambas sin INSERT, y sin URL en F12). Ambos abortan si Vault local ya tiene alguna entrada `feedback_webhook_*`.

**Deploy:** `config.toml` declara `verify_jwt = false`; el despliegue debe ser
`supabase functions deploy procesar-feedback --no-verify-jwt` (en hosted, con
`--remote="$SUPABASE_PROJECT_REF" --yes`). Sin `--no-verify-jwt` el gateway responde 401 a todo.

### Puesta en producción (D-022): el merge aplica las migraciones

El merge a `master` aplica `0033`–`0034` en prod (`0031`/`0032` ya las aplicó el PR #69), pero no
despliega la función. Ningún paso es parte
del build y cada uno requiere confirmación explícita del usuario (nunca con `~/.homita/supabase.env`
en pruebas). **P1–P5 van antes del merge**; el secreto de Vault se carga **después** del deploy de la
función nueva (P7), no antes del merge (corrección R1-01, actualización de D-022); la URL de Vault sí
se carga antes del merge (P5, D-023):

1. **P1.** Confirmar que el merge a `master` sigue aplicando solo migraciones (no Edge Functions).
2. **P2.** Pre-check SELECT-only en el SQL editor de prod: columnas, constraints y triggers de
   `feedback` y `backlog`, contrastadas con `0032_feedback_schema.sql` (escrita a partir del volcado de
   prod; cualquier diferencia de columnas, checks o nullability bloquea); extensiones `pg_net` y `supabase_vault`; `oid::regprocedure` de `net.http_post`;
   `has_table_privilege` sobre `vault.decrypted_secrets` y `net.http_request_queue` para el rol que
   aplica migraciones, `anon`, `authenticated` y `public`; schemas expuestos de la API (Dashboard →
   API settings / `pgrst.db_schemas`); policies de `feedback` (¿quién puede insertar?); `count(*)` de
   `feedback` por `estado`. Además:
   - `has_table_privilege('service_role', …)`: INSERT y UPDATE en `public.backlog`, UPDATE en
     `public.feedback` (`homita_feedback_finalize` es `security invoker`);
   - `backlog.votos`: anotar default y nullability (`column_default`, `is_nullable`); que sea nullable
     no bloquea, el upsert usa `coalesce(votos, 1) + 1`;
   - si `backlog.seccion`, `subseccion` y `tipo` son NOT NULL o no (`is_nullable`);
   - `select version from supabase_migrations.schema_migrations where version >= '0030' order by 1`
     tiene que dar exactamente `0030`, `0031` y `0032`; si ya hay `0033` o `0034`, **no se mergea**;
   - `select name from vault.secrets where name like 'feedback_webhook%'` tiene que dar 0 filas (ni
     `feedback_webhook_url` ni `feedback_webhook_secret` todavía);
   - policies de `feedback`: se espera solo «insertar mi feedback» para `authenticated`.

   **Go/no-go (R1-03):** si `has_table_privilege(r, 'net.http_request_queue', 'select')` es true
   para `r` en `anon`, `authenticated` o `public`, o si `net` figura en los schemas expuestos de la
   API, **no se mergea** hasta decidir el remedio por escrito: revoke de SELECT en la cola a esos roles
   (si pg_net lo admite sin romper el worker) o aceptar el riesgo de forma explícita (el secreto del
   webhook es legible en la cola hasta el envío). Si `service_role` no tiene los privilegios de arriba,
   o si las columnas difieren de `0032_feedback_schema.sql` (A1), tampoco: se ajusta el plan antes.

   **Aceptación escrita (2026-11-20, resultado del pre-check P2 en prod):**
   - `net.http_request_queue` es legible por `anon`/`authenticated` (PUBLIC con todos los
     privilegios y USAGE en el schema `net`), pero `net` **no** está en «Exposed schemas» (solo
     `graph_public` y `public`), así que la API REST no llega a la cola. Riesgo aceptado por el
     usuario; el secreto sigue siendo rotable (ver rotación).
   - En prod `backlog.votos` es `NOT NULL default 1` y `created_at` admite nulos en ambas tablas,
     distinto de `0032_feedback_schema.sql`. Diferencia benigna aceptada por el usuario: la RPC usa
     `coalesce(votos, 1) + 1` y no depende de `created_at`.

   **Privilegios de Vault (R2-01, R2-02):**
   ```sql
   select p.oid::regprocedure, has_function_privilege(current_user, p.oid, 'execute')
     from pg_proc p
    where p.pronamespace = 'vault'::regnamespace
      and p.proname in ('create_secret', 'update_secret');
   ```
   Sin EXECUTE en `vault.create_secret(text,text,text,uuid)` **no se mergea** (P7 depende de él y,
   tras el merge, todos los feedback nuevos se quedarían `pendiente`). Sin EXECUTE en
   `vault.update_secret` no se puede pausar el despacho: el rollback usa entonces el orden
   alternativo (ver «Rollback»), que es seguro; no bloquea el merge, pero se anota.

   **Owner de las funciones de migración (R2-02):** el reproceso (P8 y runbook) llama a
   `homita_feedback_dispatch`, con EXECUTE revocado a PUBLIC: solo lo ejecuta su owner, que será el
   rol con el que el auto-deploy aplica migraciones. Se mide con funciones de una migración anterior
   aplicada igual (0030):
   ```sql
   select p.proname, p.proowner::regrole as owner, current_user,
          pg_has_role(current_user, p.proowner, 'member') as editor_es_miembro
     from pg_proc p
    where p.pronamespace = 'public'::regnamespace
      and p.proname in ('create_event', 'update_event');
   ```
   - **Go** si `owner = current_user`: el reproceso se ejecuta tal cual desde el SQL editor.
   - **Go** si el owner es otro rol pero `editor_es_miembro` es true: el reproceso se ejecuta con
     `set role <owner>;` … `reset role;` en la misma sesión del editor.
   - **No-go** en cualquier otro caso (p. ej. owner `supabase_admin` sin membresía): no se mergea hasta
     fijar por escrito otra vía. Opciones: una migración posterior (la aplica el mismo rol owner) que
     conceda EXECUTE sobre `homita_feedback_dispatch(bigint)` solo al rol del editor; o invocar la
     función desde la terminal del usuario, una fila cada vez, con
     `curl -H "x-feedback-secret: $FEEDBACK_WEBHOOK_SECRET" -d '{"record":{"id":<id>}}' …` (el secreto
     sale de la base de datos al entorno local del usuario; la decisión es suya).

   **Reproceso en serie (R2-04):** con el `count(*)` por `estado`, anotar cuántos `pendiente` hay. P8 y
   el runbook reprocesan siempre de a uno (ver «Runbook»): así varios reportes del mismo problema se
   vinculan a una sola tarjeta en lugar de crear una por reporte.
3. **P3.** `pg_dump` de prod.
4. **P4.** Crear la lista «Feedback» en el tablero Homita y anotar su id.
5. **P5.** `supabase secrets set TRELLO_KEY TRELLO_TOKEN TRELLO_LIST_ID FEEDBACK_WEBHOOK_SECRET
   ANTHROPIC_API_KEY` (secretos de la función; la antigua los ignora). Después, en el SQL editor, la URL
   (marca de prod, D-023):
   `select vault.create_secret('https://jlmjeykqbspoohmtrhwb.supabase.co/functions/v1/procesar-feedback', 'feedback_webhook_url', 'URL de procesar-feedback (marca de prod)');`
   Es inocua: 0034 todavía no existe y, cuando exista, no despacha sin secreto. El secreto
   `feedback_webhook_secret` **no** se crea aquí (R1-01).
6. **P6.** Merge del PR (aplica `0033`–`0034`). Sin secreto en Vault, `homita_feedback_dispatch` no
   encola nada (warning «falta el secreto») y cada feedback nuevo queda `pendiente` con
   `procesando_desde` null: la función antigua no recibe ninguna llamada. Verificar `migration list`,
   que el trigger ejecuta `homita_feedback_notify`, `prosecdef`, los grants, que `prosrc` de `dispatch`
   no contiene la URL, que
   `select decrypted_secret from vault.decrypted_secrets where name = 'feedback_webhook_url'` es la URL
   de P5, que no existe `feedback_webhook_secret` y
   `select proowner::regrole from pg_proc where oid =
   'public.homita_feedback_dispatch(bigint)'::regprocedure`, que tiene que coincidir con el owner
   medido en P2 (el go/no-go ya se decidió allí, antes del merge). Si no coincide, parar antes de P7
   y aplicar la vía alternativa fijada en P2.
7. **P7.** `supabase functions deploy procesar-feedback --no-verify-jwt`; **después**
   `select vault.create_secret('<mismo valor que FEEDBACK_WEBHOOK_SECRET>', 'feedback_webhook_secret');`
   y smoke con un feedback de prueba por cada rama (crear y vincular). Desde ese momento el trigger
   despacha sin reaplicar migraciones. Si el smoke queda `pendiente` con el notice «falta
   feedback_webhook_url», faltó P5: crear la URL y reprocesar con P8.
8. **P8.** Reprocesar con el runbook los `pendiente` acumulados entre P6 y P7 y los atascados,
   **de a uno** (`order by id limit 1`) y esperando a que cada fila quede `procesado` o `error` antes
   del siguiente: un `dispatch` masivo lanza N invocaciones que leen la lista de tarjetas a la vez y
   duplican tarjetas para reportes del mismo problema (R2-04).
9. **P9.** Completar `.dorch/po-board.md` con el nombre y el id reales de la lista.

**La función antigua no procesa como antes con 0034:** lee `seccion`, `subseccion`, `tipo` y `texto`
del payload, y 0034 solo envía `record.id`. Si recibiera una llamada de 0034 clasificaría
«undefined» y podría insertar en `backlog` una fila inventada, votar un `backlog_id` arbitrario y
marcar el feedback `procesado` (el reporte real se pierde para el gate). Por eso el secreto de Vault
no se carga hasta que la función nueva está desplegada.

### Runbook (pg_net no reintenta)

```sql
-- Respuestas fallidas de las últimas ~6 h (TTL de net._http_response)
select id, status_code, timed_out, error_msg, created from net._http_response
 where status_code is distinct from 200 order by created desc;
-- Pendientes (sin reservar o atascadas: procesando_desde no nulo) y en error
select id, estado, procesando_desde from public.feedback
 where estado = 'pendiente' or estado = 'error' order by id;
-- Liberar atascadas o en error tras revisar la causa (y, si se creó tarjeta, Trello).
-- El guard nunca toca filas `procesado` (finalize no limpia procesando_desde).
update public.feedback set estado = 'pendiente', procesando_desde = null
 where id in (…)
   and (estado = 'error' or (estado = 'pendiente' and procesando_desde is not null));
-- Reproceso sin exponer el secreto, DE A UNO (si el owner es otro rol: set role, ver P2)
select id, public.homita_feedback_dispatch(id) from public.feedback
 where estado = 'pendiente' and procesando_desde is null
 order by id limit 1;
-- Antes de repetir la anterior, esperar a que esa fila quede `procesado` o `error`
select id, estado, procesando_desde from public.feedback where id = <id>;
```

Nunca reprocesar con un `dispatch` sin `limit 1`: las invocaciones en paralelo leen la lista de tarjetas
antes de que las demás creen las suyas y duplican tarjetas. Si la fila sigue `pendiente` con
`procesando_desde` null pasado ~1 min, la llamada no llegó a reservar (401, 5xx, timeout): revisar
`net._http_response` y parar; repetir la consulta volvería a elegir el mismo id.

### Rollback (en este orden)

1. **Pausar el despacho** vaciando el secreto con la API de Vault (solo si P2 mostró EXECUTE en
   `vault.update_secret`):
   `select vault.update_secret(id, '') from vault.decrypted_secrets where name = 'feedback_webhook_secret';`
   `dispatch` trata `''` como ausente (`if v_secret is null or v_secret = ''`, `0034:89`). Comprobar
   que `select decrypted_secret = '' from vault.decrypted_secrets where name = 'feedback_webhook_secret'`
   da true. Desde aquí los feedback nuevos quedan `pendiente` sin llamar a ninguna función.
2. Redeploy de la función **antigua** (desde `master` previo al merge).
3. `scripts/supabase/rollback/rollback_0034.sql` **obligatorio** tras el paso 2: la función antigua
   necesita el payload completo de 0031 (ver arriba). Restaura 0031 porque `feedback_webhook_url` de
   Vault es exactamente la URL de prod (P5, verificada en P6). Comprobar después que el trigger ejecuta
   `supabase_functions.http_request`: si el script avisó «no es la URL de prod» o «sin
   feedback_webhook_url», no hay trigger.
4. `scripts/supabase/rollback/rollback_0033.sql` (pierde `trello_card_id`/`trello_card_url`).
5. Los `pendiente` acumulados desde el paso 1 no los reenvía el trigger de 0031 (solo actúa en
   INSERT): revisarlos a mano.

**Si no se puede pausar** (sin EXECUTE en `vault.update_secret`, el paso 1 falla o la comprobación no
da true), el orden obligatorio es otro: **`rollback_0034` ANTES del redeploy** de la función antigua.
Nunca redeploy de la antigua con 0034 aplicado y el secreto cargado: cada INSERT le llegaría solo con
`record.id` (ver arriba).
1. `rollback_0034.sql` con la función nueva aún desplegada: el trigger de 0031 no envía secreto y todo
   responde 401. La auth falla antes del `claim` (`handler.ts`), así que las filas quedan `pendiente`
   sin efectos en Trello ni en `backlog`. **Comprobar a continuación que el trigger existe**
   (`select tgname, pg_get_triggerdef(oid) from pg_trigger where tgname = 'homita_feedback_creation'`
   debe mostrar `supabase_functions.http_request`): si `feedback_webhook_url` en Vault falta o difiere de
   la URL de prod, `rollback_0034` solo avisa y deja 0 triggers; en ese caso no seguir con el paso 2 y
   restaurar el trigger de 0031 a mano.
2. Redeploy de la función **antigua**.
3. `rollback_0033.sql`.
4. Revisar a mano los `pendiente` acumulados desde el paso 1.

La entrada `feedback_webhook_url` de Vault **no se borra ni se modifica** en ningún rollback: es la marca
que necesita `rollback_0034` para restaurar 0031, y solo cuenta si su valor es exactamente
`https://jlmjeykqbspoohmtrhwb.supabase.co/functions/v1/procesar-feedback`. Así un Vault local con una URL
de prueba o de túnel (válida para la regex de 0034) no hace que `rollback_0034` deje en local un trigger
que apunte a prod. Si alguien la borra o la cambia, `rollback_0034` no restaura 0031 y el feedback nuevo
queda sin despacho (se ve en la revisión manual). Las tarjetas creadas solo se archivan y los
comentarios permanecen.

## Extensión `event.end_date` (0030, D-019)

Desviación **aditiva** del contrato PHP-compat (D-008), como `refresh_token`: el evento manual admite
un fin opcional de varios días. No existe en el backend PHP original ni cambia rutas ni shapes
existentes; solo añade la clave `end_date` a las respuestas de evento.

- **Dato:** `event.end_date date` nullable (solo día `YYYY-MM-DD`, inclusive; mismo criterio que
  `routine.end_date`). Null = evento de un día. Sin backfill.
- **Lectura:** `GET /event` y `GET /event/detail` devuelven siempre `end_date` (null si no hay).
- **Escritura:** `POST /event/create` acepta `end_date` opcional. `PATCH /event/update` distingue
  clave **ausente** (conserva el fin guardado; los clientes antiguos no lo borran) de clave
  **presente** (valor = fija; `null` o `""` = borra). La Edge lo traduce a
  `p_end_date` + `p_end_date_set` de la RPC `update_event`; las firmas antiguas de
  `create_event`/`update_event` se sustituyen por las nuevas (parámetros con `DEFAULT`, las llamadas
  antiguas siguen valiendo). Mismo `403 {"error":"Not Allowed"}` para el viewer.
- **Validación (RN-2):** fin anterior al día de `date_at` → `400 {"error":"End date cannot be before
  start date"}`; formato o fecha inválidos → `400 {"error":"Invalid end date"}`. Se valida en la Edge,
  en la RPC (llamada directa) y en el formulario de iOS. Con `update` sin `end_date` y un
  `date_at` nuevo, el fin guardado se revalida contra el nuevo inicio.
- **Rutinas (RN-4):** un evento con `routine_id` no acepta fin (`400 Routine events cannot have an
  end date`); la materialización de rutinas no cambia.
- **Listado (RN-5):** `GET /event?start_date&end_date` incluye el evento si su rango
  `[date_at, end_date + 1 día)` se solapa con el pedido. Sin `end_date` el predicado es el mismo de
  antes (`date_at` dentro del rango), así que los resultados de eventos de un día no cambian. Orden
  por `date_at` intacto.
- **En curso (D-020):** por RN-5, un evento multi-día ya empezado llega a `GET /event` con un
  `date_at` anterior al rango pedido (p. ej. 10-20 nov consultado desde el 15). El backend no
  cambia: la clasificación «en curso» (`end_date` no nulo y ESTRICTAMENTE posterior a `día(date_at)`,
  y `día(date_at) <= hoy <= end_date`; un `end_date` igual al día de inicio es un evento de un solo día,
  se trata como sin fin y no muestra rango; RN-2 sigue permitiendo `end_date == día(date_at)`) es
  del cliente, por día y con la zona horaria del dispositivo (nunca la del servidor). La app iOS
  (`EventStore.ongoing`, sección «En curso» de la pestaña Eventos) y el dashboard Android
  (bloque «En curso» de la tarjeta de eventos de Hoy) lo sacan de «Próximos» y «Pasados».
  Los eventos sin `end_date` no cambian.
- **Fuera de alcance:** las vistas por día (Agenda/Inicio de iOS, vista semanal y puntos del mes
  del dashboard) siguen mostrando el evento solo en su día de inicio; la app iOS muestra el rango
  («10 nov → 20 nov») en la fila del evento y en el editor.

## Orden de listas (0040)

Change `lista-prioritaria-inicio`. Las listas de tareas tienen un orden persistente por hogar que usa Inicio
(la lista con `position` menor va primero).

- **Columna:** `task_list.position integer null` con check `position is null or position > 0`. Es global por
  hogar (no por usuario). Nullable a propósito: `create_task_list` no cambia y las listas nuevas nacen sin
  posición y salen al final hasta que alguien reordene. El backfill de la migración numera 1..n por hogar
  según `created_at, id`.
- **`GET /task-list`:** cada elemento lleva la clave aditiva `position` (int o `null`) y la lista viene
  ordenada por `position` (nulls last), `name` y `id`. El resto del shape no cambia; `GET /task-list/detail` y
  las respuestas de create/update tampoco.
- **`PATCH /task-list/order`** (ruta **aditiva**, D-008: fuera de las 43 rutas legacy; sin `X-Home-Id`, D-012):
  body `{"ids": [3, 1, 2]}` = ids en el orden deseado (lista completa, sin duplicados); respuesta 200
  `[{"id": 3, "position": 1}, …]`. Atómica (RPC `reorder_task_lists`): exige, para cada lista, ACL propia,
  permiso de edición (owner o `can_edit`) y `tasklist.manage`, como `update_task_list`; si una falla no cambia
  ninguna. No cambia `updated_at`. Errores: `ids` ausente, vacío, con duplicados o no enteros → 400
  `Task list IDs are required`; viewer sin `can_edit` o sin `tasklist.manage` → 403 `Not Allowed`; id inexistente,
  de otro hogar, sin ACL o de otro tenant → 500 `Not Found`. Las listas del hogar que el usuario no ve conservan su
  `position` (pueden empatar con las visibles; desempata `name, id`).
- **Despliegue:** el merge aplica 0040 en prod (D-022) y después se despliega la Edge (ruta nueva). Con la Edge
  nueva y sin la RPC, `PATCH /task-list/order` daría 500; `GET /task-list` sigue funcionando.
- **Rollback:** orden Edge anterior → export SELECT-only de `(id, home_id, position)` → `rollback_0040.sql`
  (borra `reorder_task_lists` y la columna y restaura el cuerpo de `get_task_lists` de 0029; idempotente; la fila
  `0040` de `schema_migrations` no se borra).
- **Pruebas:** `task_list_position_check.sql` (`ok TP1..TP8`), ida y vuelta en `ci.sh`
  (`task_list_position_rollback_check.sql` `ok TR1..TR3` y `task_list_position_reapply_check.sql` `ok TA1..TA2`),
  test Deno `functions/api/tests/task_list_order_test.ts`, 17 casos en `contract_check.py` (`CASES_POSITION`) y
  7 en `cross_tenant_check.py`.

## Idempotencia de creates (0035, D-024)

Change `ios-offline-outbox-tareas`. La cola offline de Control iOS reintenta los creates de tarea y de
lista; para que un reintento (por ejemplo tras una respuesta perdida) no duplique el recurso, el
cliente envía un `client_request_id` (UUID) y el servidor lo deduplica.

- **Tabla `client_request`:** `(app_user_id, client_request_id uuid, kind, resource_id, created_at)`,
  PK `(app_user_id, client_request_id)`. `kind` es `task` o `task_list`. La clave es por usuario, no por
  hogar. RLS activada sin policies y sin grants a `anon`/`authenticated`: solo la tocan las RPC
  `SECURITY DEFINER`. Sin limpieza en la fase 1 (volumen bajo; purga de filas de más de 30 días
  pendiente).
- **Firmas nuevas:** `create_task(bigint, text, jsonb, uuid)` y
  `create_task_list(text, text, text, boolean, boolean, uuid)`, con `p_client_request_id uuid default null`
  al final. La migración hace `drop` de la firma anterior en la misma transacción para no dejar dos
  overloads (PostgREST daría error de ambigüedad y se romperían todos los altas, también desde
  Android). Las llamadas existentes siguen valiendo gracias al default.
- **Semántica con clave no nula** (siempre después de las guardas del alta original): clave ya usada
  con el mismo `kind` devuelve el recurso con el mismo JSON y la Edge responde 201 igual que el alta,
  sin insertar; recurso ya borrado o no visible, `Not Found`; clave usada con otro `kind`,
  `Invalid client_request_id` (400). Sin clave el comportamiento es idéntico al anterior (Android, Edge
  antigua).
- **Rollback:** `scripts/supabase/rollback/rollback_0035.sql` borra las firmas nuevas, restaura las
  anteriores (`create_task` de 0029, `create_task_list` de 0020) y borra `client_request`. Se pierden
  solo las claves de idempotencia; los recursos creados se conservan, y tras el rollback un create
  reintentado podría duplicar. Revertir antes la Edge y después la BD. La fila `0035` de
  `supabase_migrations.schema_migrations` no se borra.
- **Orden de despliegue (el merge aplica la migración en prod):** primero la BD (merge, que aplica
  0035) y verificar; después `supabase functions deploy api`. Si la Edge nueva va antes que 0035, los
  creates con `client_request_id` fallan por función inexistente. El cliente iOS nuevo es compatible con
  la Edge y la BD antiguas (la Edge antigua ignora la clave, sin idempotencia). Pre-check, `pg_dump` y
  verificación en `supabase/DEPLOY_0035.md`.
- **Tests:**
  - Edge (sin BD ni red, `fetch` falso): el `deno test` necesita `--allow-env` porque el test fija
    `SUPABASE_URL` y las claves con `Deno.env.set`:
    `deno test --no-prompt --allow-env supabase/functions/api/tests/client_request_test.ts`
  - BD: `scripts/supabase/tests/client_request_check.sql` contra el stack local.

## Prioridad de tarea (0037, D-026)

Change `prioridad-tarea`. Extensión aditiva de D-008 en `task`: cada tarea tiene una prioridad `alta`,
`media` o `baja`. Ningún cliente antiguo cambia de comportamiento.

- **Columna:** `task.priority text not null default 'media'` con `task_priority_check`. El default es
  constante: las filas existentes quedan en `media` sin reescribir la tabla ni tocar `updated_at`.
- **Lecturas:** `get_task_detail` y `get_tasks` añaden `priority`, así que todas las respuestas de tarea
  (`GET /task`, `GET /task/detail`, create, update, complete y order) llevan la clave.
- **`GET /task`:** `priority=alta|media|baja` filtra (otro valor → 400 `{"error":"Invalid priority"}`);
  `sort=priority` ordena las pendientes alta > media > baja (desempate por `order` e `id`) con las
  completadas al final; otro `sort` se ignora. Sin estos parámetros el orden es el de siempre. Los
  clientes (iOS y el marco) ordenan y filtran en cliente: la API lo ofrece para clientes futuros.
- **Escrituras:** `priority` opcional en `POST /task/create` (ausente → `media`) y `PATCH /task/update`
  (ausente → se conserva). Solo `alta`, `media` o `baja` exactos; `""`, números o `"ALTA"` → 400
  `Invalid priority` (la Edge valida antes de la RPC y la RPC repite la barrera, tras el título). El
  replay idempotente de 0035 devuelve la tarea original e ignora la prioridad del reenvío.
- **Firmas:** `get_tasks(boolean, bigint, boolean, text, text)`, `create_task(bigint, text, jsonb, uuid, text)`
  y `update_task(bigint, text, jsonb, text)`, con drop de las anteriores (un solo objeto por RPC, sin
  ambigüedad en PostgREST). Las llamadas existentes por nombre o posición siguen resolviendo.
- **Despliegue:** la Edge solo manda `p_priority`/`p_sort` si el cliente los envía. La Edge antigua
  funciona sobre la BD con 0037 (ignora `priority` y todo sale en `media`). La Edge nueva sobre la BD
  sin 0037 solo funciona con clientes que no envían `priority` (el marco y Planify-APP). La app iOS de
  este change **siempre** manda `priority` al crear (el editor arranca en `media` y la cola offline la
  guarda), así que con ella instalada la Edge nueva **requiere 0037**: sin la columna, PostgREST no
  encuentra `create_task` con `p_priority` y todas las altas desde iOS fallan, también las encoladas.
  Orden obligatorio: merge (aplica 0037) y verificación SELECT-only; después
  `supabase functions deploy api`; después la release de los clientes. Nunca la Edge nueva antes que
  0037, y en un rollback, siempre la Edge anterior antes que `rollback_0037` (ver «Rollback»).
- **Kito (`asistente`):** la skill `consulta` (`ver_tareas`) reutiliza `handleTask` de
  `api/usecases/tasks.ts` sin `priority` ni `sort`: su llamada a la RPC no cambia y su salida gana la
  clave `priority`. Kito se despliega aparte y empaqueta su propia copia de `api/usecases`; no hace
  falta redesplegarlo para este change.
- **Rollback:** `scripts/supabase/rollback/rollback_0037.sql` (idempotente) borra las firmas nuevas,
  restaura las previas (`get_tasks`/`get_task_detail` de 0024, `create_task` de 0035, `update_task` de
  0029) y hace `drop column priority`. **Se pierden todas las prioridades:** antes, en modo SELECT-only,
  exportar `select id, priority from task where priority <> 'media'` (o `pg_dump`). Orden en prod:
  Edge anterior → export → `rollback_0037`. La fila `0037` de `supabase_migrations.schema_migrations`
  no se borra.
- **Tests:**
  - Edge (sin BD ni red): `deno test --no-prompt --allow-env supabase/functions/api/tests/task_priority_test.ts`.
  - BD: `scripts/supabase/tests/task_priority_check.sql` (P1–P10); rollback y reaplicación en
    `task_priority_rollback_check.sql` (PR1–PR4) y `task_priority_reapply_check.sql` (PA1–PA3), que
    `ci.sh` corre en la ida y vuelta anidada.
  - Contrato: `contract_check.py` (bloque de prioridad; `CONTRACT_SCHEMA=pre-0037` para la BD revertida)
    y `cross_tenant_check.py` (+3 casos).

## Acceso a la lista al crear (0038)

Change `asignar-alta-lista` (Control iOS: selector de personas en los tres puntos de alta de tarea).

- **Regla:** al crear una tarea, cada id de `person_ids` debe ser una persona con cuenta
  (`home_member.app_user_id` no nulo) y con fila en `task_list_user` de la lista (owner o viewer, con
  o sin `can_edit`). Si alguna no cumple, `create_task` lanza `Invalid person` (P0001, 400 en la Edge)
  y no crea la tarea ni la fila de `client_request`. Sin `person_ids`, con `null` o con `[]` no cambia nada.
- **Solo el alta:** `update_task` no se toca (las asignaciones de edición siguen la regla de siempre:
  persona activa del hogar).
- **Orden en `create_task`:** título → `Invalid priority` → lock → ACL del llamante → `task.create` →
  idempotencia (un reenvío con la misma clave de una tarea ya creada devuelve la existente) → guarda
  0038 → insert. La prioridad inválida gana a la persona sin acceso.
- **Firma:** la de 0037, `create_task(bigint, text, jsonb, uuid, text)`, con `create or replace` (sin
  drop ni sobrecarga nueva). La Edge no cambia.
- **Offline:** si una alta encolada llega con una persona que ya no tiene acceso, el cliente iOS filtra
  con un roster fresco y reenvía con la misma clave (último escalón: sin personas) y avisa; el servidor
  siempre rechaza.
- **Rollback:** `scripts/supabase/rollback/rollback_0038.sql` (idempotente) restaura el `create_task`
  de 0037 con sus grants; aborta si no existe la firma de 5 argumentos. No toca datos. La fila `0038` de
  `supabase_migrations.schema_migrations` no se borra. Orden LIFO: `rollback_0038` → `rollback_0037` →
  `rollback_0035`.
- **Tests:** `scripts/supabase/tests/task_person_access_check.sql` (A1–A9); rollback y reaplicación en
  `task_person_access_rollback_check.sql` (RB38-1..4) y `task_person_access_reapply_check.sql`
  (RA38-1), que `ci.sh` corre en una ida y vuelta por fuera de la de 0037; `cross_tenant_check.py`
  (XT-AL1..XT-AL4, +4 casos).

## Ocultar completadas (0039, D-025)

Change `ocultar-completadas-3-dias` (tarjeta [13]). Una tarea completada se oculta 3 días después de
completarse, en todos los clientes a la vez (marco, Control iOS y Control Android), porque el filtro va
en la BD. **Sin recuperación:** no hay ruta, RPC, parámetro ni UI para restaurar una oculta.

- **Columna:** `task.hidden_at timestamptz` nullable, sin default. No se expone en ninguna respuesta: las
  shapes de `task/*` no cambian (D-008, sin desviación).
- **Fórmula única:** `hidden_at = (completed_at + interval '3 days') at time zone 'UTC'`. `completed_at`
  es `timestamp` naive en UTC; sumar en UTC naive y convertir después no depende del `TimeZone` de la
  sesión (`timestamptz + '3 days'` daría 71 o 73 h en un cambio de horario). El CHECK
  `task_hidden_at_consistent` la exige: pendiente ⇒ `hidden_at` null; completada ⇒ `hidden_at` igual a la
  fórmula.
- **Escritura:** solo `complete_task`, en el mismo UPDATE que `completed_at`: completar o re-completar
  recalcula `hidden_at`; descompletar lo limpia. El backfill de la migración rellena todas las
  completadas (también las recientes, con `hidden_at` futuro) sin tocar `completed_at`, `updated_at`,
  `"order"` ni `priority`.
- **Predicado:** oculta = `hidden_at is not null and hidden_at <= now()`; visible = `hidden_at is null or
  hidden_at > now()`. Inline sobre el valor crudo, sin cron.
- **Lecturas:** `get_tasks` (`GET /task`, con o sin filtros, `priority` y `sort`) no devuelve ocultas.
  `GET /task-list` cuenta pendientes, así que su `pending_task_count` no cambia. La policy `task_select`
  tampoco devuelve ocultas por PostgREST (defensa en profundidad; ningún cliente la usa).
- **Errores:** `GET /task/detail` de una oculta y `PATCH /task/complete` (`completed` true o false),
  `PATCH /task/update`, `PATCH /task/order` y `DELETE /task/delete` sobre una oculta responden 500
  `{"error":"Not Found"}`, el mismo cuerpo que una tarea inexistente (sin oráculo, también entre
  tenants). La comprobación va antes del lock y de la ACL y la fila no cambia. `update_task` sigue
  validando título y prioridad antes de buscar la tarea.
- **Orden:** `task_order` y `fn_reorder_tasks` excluyen las ocultas: `position` cuenta solo las visibles y
  el `"order"` de las ocultas queda congelado.
- **Clientes:** la cola offline de iOS ya trata «Not Found» (delete = ack, resto = descarte con aviso «ya
  no existe»). En línea, Control iOS recarga las tareas ante un «Not Found» para que la oculta
  desaparezca; un delete con «Not Found» cuenta como hecho, también en «Eliminar completadas».
- **Rollback:** `scripts/supabase/rollback/rollback_0039.sql` (idempotente, solo BD) restaura verbatim los
  7 cuerpos previos (`get_tasks`, `get_task_detail` y `update_task` de 0037; `complete_task`,
  `task_order` y `delete_task` de 0029; `fn_reorder_tasks` de 0006) y la policy de 0020, y quita el
  CHECK y la columna. Solo se pierde `hidden_at`, que reaplicar 0039 recalcula. Las ocultas vuelven a
  verse con su `"order"` congelado. La fila `0039` de `supabase_migrations.schema_migrations` no se
  borra. **Orden LIFO:** `rollback_0039` → `rollback_0038` → `rollback_0037` → `rollback_0035`;
  `rollback_0038` aborta mientras exista `task.hidden_at`.
- **Tests:** `scripts/supabase/tests/task_hidden_check.sql` (H1–H12); rollback y reaplicación en
  `task_hidden_rollback_check.sql` (RBH1–RBH5) y `task_hidden_reapply_check.sql` (RAH1–RAH3), que
  `ci.sh` corre en una ida y vuelta por fuera de la de 0038; guarda LIFO en
  `task_hidden_rollback_guard_check.sql` (G39-1); `contract_check.py` (bloque de ocultas, +32;
  `CONTRACT_SCHEMA=pre-0039` para la BD revertida) y `cross_tenant_check.py` (+9 casos XH). iOS:
  `TasksStoreHiddenTests`, `PendingOverlayTests` y `OutboxReplayerTests`.
- **Despliegue:** `supabase/DEPLOY_0039.md` (solo BD; sin `functions deploy`).

## Feedback (`POST /feedback`, change control-ios-feedback)

Ruta **aditiva** (D-008): fuera de las 43 rutas legacy y de `EXPECTED_CASES`. La app Control iOS la usa
desde Ajustes («Enviar feedback») para reportar un bug o proponer una mejora.

- **Request:** `POST /feedback` con Bearer (cualquier miembro autenticado; sin `X-Home-Id`) y body JSON
  `{"seccion","subseccion","tipo","texto"}`. `seccion` ∈ Inicio, Tareas, Calendario, Hogar, Ajustes, Acceso,
  General / otro; `tipo` ∈ `bug`, `mejora`; `texto` 1..2000 caracteres tras recortar; `subseccion` opcional con
  formato `"<pantalla>: <acción>"` (máx. 100 unidades UTF-16). El cliente no envía `user_id`.
- **Catálogo (change feedback-selectores-arquitectura):** sección › pantalla › acción, en
  `FEEDBACK_CATALOG` (`_shared/validate.ts`). El valor enviado es el nombre visible en la app (con
  mayúsculas). La Edge parte `subseccion` por el **último** `": "` y exige que la pantalla sea de la sección y
  la acción de esa pantalla (admite espacios, `/` y paréntesis: `Lectura`, `Edición`); por eso ningún nombre contiene
  `": "`. Una pantalla alcanzable desde varios sitios lleva el camino desde la raíz de la sección con ` › `
  (`Detalle de lista › Editar tarea`). Alta y edición son pantallas separadas (`Nueva tarea` / `Editar tarea`) y la acción de guardar usa el texto del botón en cada modo; lo que no tiene texto visible (gestos, iconos, pantallas sin título) lleva un nombre descriptivo convencional. «Acceso» agrupa las pantallas fuera de las pestañas y «General /
  otro» las pantallas sin acciones propias (acción única `General`).
- **Compat transitoria (catálogo 2026-11-19):** la Edge acepta además los pares viejos (sub-área en minúscula de
  la sección + `ver|crear|editar|eliminar`; `resumen del día` solo `ver`) para apps instaladas. Se retira en un
  cambio posterior. Registros viejos de `feedback`/`backlog` no se tocan.
- **Fixture y sincronía:** `functions/api/tests/fixtures/feedback_catalog.json` es la referencia única. El
  catálogo de la Edge y `FeedbackCatalog.swift` se mantienen a mano y sus tests comparan igualdad exacta contra el
  fixture (`deno test --no-prompt --allow-env functions/api/tests/feedback_test.ts` y
  `swift test --filter FeedbackTests` en `apps/control-ios`). Al cambiar la app: editar fixture, Edge y
  cliente en el mismo cambio; desplegar la Edge antes de distribuir la app.
- **Respuesta:** `201 {"ok":true}`. Errores: `400` validación (`{"error":"Invalid tipo"}`…), `401` sin
  token, `403 {"error":"Feedback not allowed"}` si la RLS rechaza. *Desviación del plan:* no devuelve el `id`, porque la tabla solo
  tiene política de INSERT (como en prod) y `RETURNING` exige SELECT; el insert va con `return=minimal`.
- **Inserción:** PostgREST con el JWT del usuario (RLS «insertar mi feedback»; `user_id` = `auth.uid()` por
  defecto). No usa service role.
- **Orden 0031 -> 0032 -> 0033 -> 0034 y advertencia del trigger:** en un `db reset` local 0031 corre antes
  que 0032, ve la tabla inexistente y sale sin trigger; 0032 crea las tablas sin trigger; 0033 añade columnas
  y RPC, y 0034 crea el trigger `homita_feedback_creation` → `homita_feedback_notify`, inerte sin URL ni
  secreto en Vault (ver «Edge Function `functions/procesar-feedback/`»). **No reaplicar 0031 a mano en local
  con la tabla creada**: sustituiría el trigger inerte por uno que apunta a la función de **producción**. Si
  pasa, reaplicar 0034 o hacer `db reset`.
- **Producción:** hecho (el PR #69 aplicó 0031/0032 con el auto-deploy). La puesta en marcha de
  `procesar-feedback` sigue P1–P9 de «Puesta en producción (D-022)».
- **Pruebas:** `supabase/functions/api/tests/feedback_test.ts` (Deno), bloque `scenario_feedback` de
  `contract_check.py` (8 casos propios, `FEEDBACK_EXPECTED`; no cuentan en el 502/502) y bloque `FB` de `cross_tenant_check.py`
  (4 casos: no suplantar `user_id`, no leer feedback ajeno).

## Menús de la semana (0044) y semilla de alimentos

`migrations/0044_menus_semana.sql` (change `menus-semana`, fase 2 del planificador de comidas) crea el
catálogo de alimentos (`food`), las recetas (`recipe`, `recipe_ingredient`) y el menú semanal
(`meal_plan`, `meal_plan_item`, `meal_plan_item_member`), con RPC para todo (lectura `menu.view`,
escritura `menu.plan.manage`; sin permisos nuevos). RLS solo de lectura: toda escritura pasa por RPC.
Reversa: `scripts/supabase/rollback/rollback_0044_menus_semana.sql` (**pierde recetas, menús y
catálogo**), **antes** que `rollback_0043_meal_profile.sql` (orden LIFO).

**El catálogo común NO va en la migración.** Está en `supabase/seed/food_es.sql` (~300 alimentos en
español con `home_id` nulo, sección, alérgenos de la UE y unidad por defecto; una fila por línea para
revisarlo a mano). Es idempotente (`on conflict … do nothing` contra `food_common_name_uq`): se puede
cargar varias veces sin duplicar.

- **CI / local:** `scripts/supabase/ci.sh` lo carga justo después de aplicar las migraciones y antes de
  los checks del menú (`menu_semana_check.sql`).
- **Producción (paso manual, no se ha ejecutado nada):** tras aplicar 0044, cargar el seed una vez con
  `psql "$DATABASE_URL" -f supabase/seed/food_es.sql`. Sin él la migración funciona igual, pero el
  catálogo común queda vacío: las recetas se pueden escribir con texto libre y el autocompletar de
  ingredientes no devuelve nada hasta cargarlo. Recordarlo al desplegar. El rollback de 0044 borra las
  tablas y con ellas el catálogo: tras reaplicar 0044 hay que volver a cargar el seed.

Errores nuevos de las RPC (la Edge los mapea): `Invalid recipe`, `Invalid food`, `Invalid meal plan`
(400), `Stale meal plan revision` y `Meal plan exists` (409, ver `_shared/errors.ts`).

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
Exit 0 = 43/43 rutas legacy cubiertas sin regresión (más la ruta aditiva `PATCH /task-list/order`, 0040, cuyos casos suman al total); si no, lista las rutas con regresión.

```sh
scripts/demo.sh up                          # Edge local servida + seed.py (ver «Flujo demo local»)
python3 scripts/supabase/contract_check.py  # o --fn URL o SUPABASE_FUNCTIONS_URL
```

Complementos sin oráculo: `scripts/supabase/tests/expected_shape_check.py`
(forma esperada: `refresh_token`, `config` con flag `ALLOW_REGISTRATION`, Gemini 400, alta de
usuarios; se ejecuta una vez por configuración de flag) y `scripts/supabase/tests/cross_tenant_check.py`
(aislamiento entre tenants: 289 casos —`EXPECTED_CASES` en el script—, ids ajenos → `500 Not Found`, RPC directas
`/rest/v1/rpc/*` con JWT ajeno sin fugas, owner vs viewer). Fixture:
`scripts/supabase/fixture_two_families.py` (RLS).

## CI de la Edge (`.github/workflows/edge-tests.yml`)

Primer CI del repo, solo para la Edge y su BD. En cada pull request a `master` un job levanta un
stack Supabase local y efímero en `ubuntu-latest` y corre `scripts/supabase/ci.sh`:

1. `supabase start -x studio,imgproxy,vector,logflare,mailpit` y comprobación de que la BD es
   `supabase/postgres:17.*` y la API es local (127.0.0.1/localhost).
2. `scripts/demo.sh up`: db reset (migraciones), `functions serve api` con `ALLOW_REGISTRATION=true`
   y seed. Es el único reset.
3. `deno check` de `procesar-feedback/index.ts` y `asistente/index.ts`, y `deno test` de
   `procesar-feedback/tests/` y `asistente/tests/` (mocks, sin red ni secretos; asistente con
   `--allow-env`; `ok | N passed | 0 failed`).
4. SQL `invitaciones_check.sql` (`ok N1..N22`), `home_checks_compat.sql` (`ok V5j..V5p`),
   `acl_can_edit_check.sql` (`ok K1..K8`), `permisos_matriz_check.sql` (29 `ok M`: M1, M1b, M2..M27 y M8b),
   `client_request_check.sql` (`ok C1..C9`), `assistant_usage_check.sql` (`ok U1..U7`),
   `task_priority_check.sql` (`ok P1..P10`), `task_person_access_check.sql` (`ok A1..A9`),
   `task_hidden_check.sql` (`ok H1..H12`),
   `feedback_trello_check.sql` (`ok B1..B8`, B7b dentro de B7) y `feedback_trigger_check.sql` (`ok F1..F12`). Los dos
   últimos reciben las migraciones y los rollbacks expandidos desde los marcadores
   `-- @MIGRATION:<fichero>@` / `-- @ROLLBACK:<fichero>@`; F10 usa un stub de `net.http_post` porque el
   stack local no instala `pg_net` (si estuviera, mira la cola real).
   Además `task_list_position_check.sql` (`ok TP1..TP8`, 0040) y el test Deno de `PATCH /task-list/order`
   (`api/tests/task_list_order_test.ts`, con `--allow-env`).
5. `contract_check.py` completo (`581/581`: 502 + 30 de prioridad + 32 de ocultas + 17 de la ruta aditiva `PATCH /task-list/order`; `CONTRACT_ONLY` y `CONTRACT_SCHEMA` se anulan).
6. `cross_tenant_check.py` (`289/289`; sale 1 si hay un fallo o si el número de casos no es
   `EXPECTED_CASES`).
7. Ida y vuelta exterior 0039 → `rollback_0039` → [la de 0038 de abajo] → 0039:
   `task_hidden_rollback_check.sql` (`ok RBH1..RBH5`) y, sobre el esquema sin 0039, `P1..P10`, `A1..A9`,
   `C1..C9`, `K1..K8` y `contract_check.py` en modo `CONTRACT_SCHEMA=pre-0039` (`549/549`); al salir,
   `task_hidden_reapply_check.sql` (`ok RAH1..RAH3`), `H1..H12` y `contract_check.py` completo. Va por
   fuera porque la de 0038/0037 reaplica `get_tasks`, `get_task_detail` y `update_task` sin el filtro.
   Antes del paso 5, junto a `G0..G3` y `G38-1`, `task_hidden_rollback_guard_check.sql` (`ok G39-1`)
   comprueba con 0039 aplicada que `rollback_0038` aborta sin tocar nada.
   Dentro, la ida y vuelta 0038 → `rollback_0038` → [la de 0037 de abajo] → 0038:
   `task_person_access_rollback_check.sql` (`ok RB38-1..RB38-4`), `C1..C9`, `K1..K8` y `P1..P10` sobre
   el esquema sin 0038; al salir, `task_person_access_reapply_check.sql` (`ok RA38-1`), `A1..A9` y
   `contract_check.py` completo (antes se borran las filas de `client_request` de tareas que ya no
   existen: el replay de prioridad usa una clave fija). Va por fuera porque reaplicar 0037 deja `create_task` sin la guarda.
   Dentro, la ida y vuelta anidada 0037 → `rollback_0037` → (0035 → `rollback_0035` → 0035) → 0037:
   `task_priority_rollback_check.sql` (`ok PR1..PR4`), checks y `contract_check.py` en modo
   `CONTRACT_SCHEMA=pre-0037` (`519/519`) sobre el esquema revertido; dentro, la de 0035
   (`ok RB1..RB4`, los mismos checks, `event_end_date_rollback_guard_check.sql` (`ok E0..E2`: con 0030
   aplicada la guarda de `rollback_0029` aborta sin tocar nada), `ok RA1..RA2` y `C1..C9`); al final `task_priority_reapply_check.sql`
   (`ok PA1..PA3`), `P1..P10`, `C1..C9` y `contract_check.py` completo otra vez. La de 0035 va dentro
   porque `rollback_0035` borra `create_task(bigint, text, jsonb, uuid)`, que con 0037 ya no existe.
   Antes del paso 5, `task_priority_rollback_guard_check.sql` (`ok G0..G3`) comprueba con 0037 aplicada
   que las guardas de `rollback_0035` y `rollback_0029` abortan sin tocar nada y que las llamadas por
   nombre de la Edge a `create_task`/`update_task` resuelven sin ambigüedad; el `contract_check.py` del
   paso 5 lo confirma por la Edge (`POST /task/create` 201, `PATCH /task/update` 200).

8. Ida y vuelta 0040 → `rollback_0040.sql` → 0040, en serie tras las anteriores: `task_list_position_rollback_check.sql`
   (`ok TR1..TR3`), checks sobre el esquema revertido (`contract_check.py` con `CONTRACT_POSITION=0` = `564/564`
   sin `position`) y reaplicación con `task_list_position_reapply_check.sql` (`ok TA1..TA2`) y `TP1..TP8` otra vez.

Se ejecutan todas las suites aunque una falle y el job falla si falla cualquiera; ante fallo se
suben `.demo/ci/` (logs, `serve.log`, `supabase status`). Versiones fijadas: Supabase CLI 3.1.0,
Deno 2.9.8 (`denoland/setup-deno` v2.0.5), `postgresql-client-17` (PGDG) y acciones por SHA. Sin secretos ni `~/.homita/supabase.env`: las
claves son las del stack local (`supabase status -o env`). psql va por
`docker exec -i supabase_db_homita-api psql -U postgres -d postgres` (socket Unix): las guardas
de host de los tests (socket o loopback, sin override) no admiten la IP del contenedor.

Reproducir en local (Docker arriba, CLI 3.1.0; resetea la BD local):

```sh
scripts/supabase/ci.sh
```

Lint del workflow: `actionlint`, `yamllint .github/workflows`, `shellcheck scripts/supabase/ci.sh`.

Pendiente del primer run real en GitHub (no verificable en local): versión de Docker, memoria y
tiempo de arranque del runner; que `supabase/setup-cli` resuelva la 3.1.0; la instalación apt de
PGDG; flakiness de las pruebas de concurrencia de `cross_tenant_check` (carreras con `pg_sleep`);
y los permisos de `GITHUB_TOKEN` (solo `contents: read`). Los tests Android siguen siendo manuales.

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
