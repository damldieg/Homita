# Despliegue de 0035 en prod (change `ios-offline-outbox-tareas`, D-024)

Guía para que el usuario ejecute o autorice cada paso. Nada de esto se ejecuta desde el build ni desde
un agente: cada paso con efecto en prod requiere confirmación explícita aparte. No usar
`~/.homita/supabase.env` en pruebas locales (es prod).

**El merge a `master` aplica `0035` en prod automáticamente** (R17), pero no despliega la Edge.
Orden obligatorio: BD primero, Edge después (R18). Si la Edge nueva va antes, los creates con
`client_request_id` fallan por función inexistente.

## Orden

1. Pre-check SELECT-only (A).
2. `pg_dump` previo (B).
3. Confirmación del usuario para el merge.
4. Merge de la PR (aplica 0035).
5. Verificación posterior de 0035 (C). Si falla, parar y valorar `rollback_0035.sql`.
6. `supabase functions deploy api` con confirmación aparte.
7. Smoke (D).

## A. Pre-check SELECT-only (SQL editor de prod)

Solo `select`. Antes del merge debe cumplirse todo; cualquier diferencia bloquea.

```sql
-- A1. Firmas actuales: debe haber exactamente UNA por función, las de antes de 0035.
select p.oid::regprocedure as firma
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname in ('create_task', 'create_task_list')
order by 1;
-- Esperado:
--   create_task(bigint,text,jsonb)
--   create_task_list(text,text,text,boolean,boolean)

-- A2. client_request no existe (debe devolver NULL).
select to_regclass('public.client_request');

-- A3. 0035 no está registrada (0 filas).
select version from supabase_migrations.schema_migrations where version >= '0034' order by 1;
-- Esperado: como mucho 0034 (si el historial usa otro formato de versión, comparar con 0034 y 0033).

-- A4. Grants actuales de las dos RPC (referencia para comparar tras 0035).
select p.oid::regprocedure as firma, r.rolname, has_function_privilege(r.rolname, p.oid, 'execute') as puede
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
cross join (select rolname from pg_roles where rolname in ('anon', 'authenticated', 'service_role')) r
where n.nspname = 'public' and p.proname in ('create_task', 'create_task_list')
order by 1, 2;
-- Esperado: authenticated = true, anon = false.
```

## B. Plan de `pg_dump` previo

Red de seguridad (el `drop function` de 0035 sustituye las funciones de prod). Lo ejecuta el usuario con
la cadena de conexión de prod en una variable de entorno de su shell (nunca en git):

```sh
# Solo lectura. $PROD_DB_URL: conexión directa de solo lectura al proyecto de prod.
mkdir -p ~/backups-homita
pg_dump "$PROD_DB_URL" --schema=public --schema-only --no-owner \
  -f ~/backups-homita/pre-0035-schema-$(date +%Y%m%d-%H%M).sql
pg_dump "$PROD_DB_URL" --schema=public --data-only --no-owner \
  -t public.task -t public.task_list -t public.task_list_user \
  -f ~/backups-homita/pre-0035-tasks-data-$(date +%Y%m%d-%H%M).sql
```

Comprobar que los ficheros no están vacíos y que el de esquema contiene `CREATE FUNCTION public.create_task`
y `public.create_task_list` con las firmas viejas. Guardarlos fuera del repo.

## C. Gate de verificación posterior (tras el merge)

Solo `select`. Todo debe cumplirse antes de desplegar la Edge.

```sql
-- C1. Una sola firma por RPC (sin overloads: si hay dos, PostgREST da ambigüedad y se rompen
--     todos los altas, también desde Android).
select p.oid::regprocedure as firma
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname in ('create_task', 'create_task_list')
order by 1;
-- Esperado exactamente 2 filas:
--   create_task(bigint,text,jsonb,uuid)
--   create_task_list(text,text,text,boolean,boolean,uuid)
-- (equivalente en psql: \df public.create_task* )

-- C2. Grants de las RPC: authenticated puede, anon y public no.
select p.oid::regprocedure as firma, r.rolname, has_function_privilege(r.rolname, p.oid, 'execute') as puede
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
cross join (select rolname from pg_roles where rolname in ('anon', 'authenticated')) r
where n.nspname = 'public' and p.proname in ('create_task', 'create_task_list')
order by 1, 2;
-- Esperado: authenticated = true, anon = false en ambas.

-- C3. client_request existe, con RLS activada y sin grants a anon/authenticated.
select c.relname, c.relrowsecurity as rls_activa
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relname = 'client_request';
-- Esperado: 1 fila, rls_activa = true.

select count(*) as policies from pg_policies where schemaname = 'public' and tablename = 'client_request';
-- Esperado: 0.

select grantee, privilege_type from information_schema.role_table_grants
where table_schema = 'public' and table_name = 'client_request' and grantee in ('anon', 'authenticated', 'PUBLIC');
-- Esperado: 0 filas.

-- C4. Estructura de la tabla: PK (app_user_id, client_request_id) y check de kind.
select conname, pg_get_constraintdef(oid) from pg_constraint where conrelid = 'public.client_request'::regclass;
-- Esperado: PK + check kind in ('task','task_list') + FK a app_user.

-- C5. Migración registrada.
select version from supabase_migrations.schema_migrations where version >= '0034' order by 1;
-- Esperado: 0034 y 0035.
```

Si C1 muestra dos firmas, o C2/C3 no cumplen: no desplegar la Edge; aplicar el `drop` de la firma vieja o
`scripts/supabase/rollback/rollback_0035.sql` (con confirmación del usuario) y repetir C.

## D. Smoke tras el deploy de la Edge (confirmación aparte)

1. `supabase functions deploy api --no-verify-jwt --remote="$SUPABASE_PROJECT_REF" --yes` (ver
   `supabase/README.md`, con confirmación explícita del usuario).
2. **Create sin clave (compatibilidad Android y Edge antigua):** con la cuenta del propio usuario,
   crear una tarea y una lista sin `client_request_id` (desde la app Android o una llamada a
   `POST /task/create` y `POST /task-list/create` sin la clave). Debe responder 201 con la forma de
   siempre. Borrar después el recurso de prueba. Confirmar que no hay fila nueva en `client_request`:
   ```sql
   select count(*) from client_request;  -- sin cambios respecto a antes del smoke
   ```
3. **Create con clave (iOS nuevo):** crear una tarea desde la app iOS; debe aparecer una fila nueva:
   ```sql
   select kind, resource_id, created_at from client_request order by created_at desc limit 5;
   ```
   Opcional: repetir la misma petición con el mismo `client_request_id`; debe devolver 201 con el mismo
   `id` y no crear una segunda tarea.
4. Borrar los recursos de prueba creados.

## Rollback

Orden: revertir antes la Edge (deja de enviar `p_client_request_id`) y después la BD con
`scripts/supabase/rollback/rollback_0035.sql`. Se pierden solo las claves de idempotencia; los recursos
creados se conservan. El `pg_dump` de B es la red de seguridad.
