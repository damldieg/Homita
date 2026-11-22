# Despliegue de 0038 en prod (change `asignar-alta-lista`)

Guía para que el usuario ejecute o autorice cada paso. Nada de esto se ejecuta desde el build ni desde
un agente: cada paso con efecto en prod, o que consulte prod, requiere confirmación explícita aparte.
No usar `~/.homita/supabase.env` en pruebas locales (es prod).

**El merge a `master` aplica `0038` en prod automáticamente** (D-022). La Edge **no cambia** con este
change: no hay `supabase functions deploy`. La 0038 solo sustituye el cuerpo de
`create_task(bigint, text, jsonb, uuid, text)` (`create or replace`, misma firma de 0037) y el de
`get_persons(boolean)` (`create or replace`, misma firma y grants de 0017; el JSON añade `home_id`,
aditivo), sin DDL de tablas ni backfill.

`GET /person` pasa a incluir `home_id` en cada persona. Los clientes existentes (dashboard, Control
Android, builds viejos de iOS) ignoran claves desconocidas; Control iOS la usa para deduplicar el
selector por hogar y cuenta y la decodifica como opcional.

Efecto visible: un `POST /task/create` con `person_ids` de una persona sin cuenta o sin acceso a la
lista pasa a 400 `{"error":"Invalid person"}`. Hoy solo lo envía Control iOS. Los builds viejos de iOS
que asignen a esas personas verán el error (en línea) o descartarán la alta encolada (replay):
reconstruir la app justo antes o después del merge.

## Orden

0. **Orden de merge respecto de la PR #81:** esta PR (0038) se mergea **antes** que la #81
   (`dc/lista-prioritaria-inicio`, `0040_task_list_position.sql`). Si la 0040 llegara antes a prod, la
   0038 quedaría por debajo de la última migración remota y el auto-apply podría rechazarla o saltarla.
   Si se invierte el orden, renumerar antes la migración. La segunda PR en entrar debe rebasar sobre
   `master` y sumar sus casos en `ci.sh`, `cross_tenant_check.py` (`EXPECTED_CASES`) y
   `supabase/README.md`.
1. Confirmar que **0037 está aplicada en prod** (no basta con que esté en `master`) y el pre-check
   SELECT-only (A).
2. `pg_dump --schema-only` de la función (B).
3. Confirmación del usuario para el merge.
4. Merge de la PR (aplica 0038).
5. Verificación posterior (C). Si falla, parar y valorar `rollback_0038.sql` (con confirmación).
6. Smoke de 400 con un usuario de prueba (D).
7. Release de Control iOS con el selector filtrado.

## A. Pre-check SELECT-only (SQL editor de prod)

Solo `select`. Antes del merge debe cumplirse todo; cualquier diferencia bloquea.

```sql
-- A1. Una sola firma de create_task, la de 0037 (equivalente en psql: \df public.create_task).
select p.oid::regprocedure as firma
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname = 'create_task'
order by 1;
-- Esperado exactamente 1 fila: create_task(bigint,text,jsonb,uuid,text)

-- A2. Migraciones registradas: llega hasta 0037 (con su nombre) y 0038 no está.
select version, name from supabase_migrations.schema_migrations where version >= '0035' order by 1;
-- Esperado: 0035 client_request_idempotency, 0036 assistant_usage, 0037 task_priority. Sin 0038.

-- A3. El cuerpo vigente es el de 0037: sin el marcador 0038 y con la prioridad.
select pg_get_functiondef('public.create_task(bigint,text,jsonb,uuid,text)'::regprocedure) like '%0038:%' as tiene_0038,
       pg_get_functiondef('public.create_task(bigint,text,jsonb,uuid,text)'::regprocedure) like '%Invalid priority%' as tiene_prioridad,
       md5(pg_get_functiondef('public.create_task(bigint,text,jsonb,uuid,text)'::regprocedure)) as md5;
-- Esperado: tiene_0038 = false, tiene_prioridad = true, md5 = 91c512311639f3ff136a906b6e68b3a0
-- (el md5 del reset local 0001–0037; si difiere, comparar el cuerpo a mano con
-- supabase/migrations/0037_task_priority.sql antes de seguir).

-- A4. Grants actuales (referencia para comparar tras 0038).
select r.rolname, has_function_privilege(r.rolname, 'public.create_task(bigint,text,jsonb,uuid,text)'::regprocedure, 'execute') as puede
from pg_roles r where r.rolname in ('anon', 'authenticated')
order by 1;
-- Esperado: anon = false, authenticated = true.
```

## B. `pg_dump` previo de la función

Red de seguridad. Lo ejecuta el usuario con la cadena de conexión de prod en una variable de entorno de
su shell (nunca en git):

```sh
# Solo lectura. $PROD_DB_URL: conexión directa de solo lectura al proyecto de prod.
mkdir -p ~/backups-homita
pg_dump "$PROD_DB_URL" --schema=public --schema-only --no-owner \
  -f ~/backups-homita/pre-0038-schema-$(date +%Y%m%d-%H%M).sql
grep -n "FUNCTION public.create_task(" ~/backups-homita/pre-0038-schema-*.sql
```

Comprobar que el fichero no está vacío y que contiene `CREATE FUNCTION public.create_task(` con la firma
de 5 argumentos y sin `0038:`. Guardarlo fuera del repo. No hace falta volcar datos: la 0038 no toca filas.

## C. Verificación posterior (tras el merge)

Solo `select`.

```sql
-- C1. Sigue habiendo una sola firma (sin sobrecarga nueva).
select p.oid::regprocedure as firma
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname = 'create_task';
-- Esperado exactamente 1 fila: create_task(bigint,text,jsonb,uuid,text)

-- C2. La guarda está aplicada (marcador 0038:) y la prioridad sigue.
select pg_get_functiondef('public.create_task(bigint,text,jsonb,uuid,text)'::regprocedure) like '%0038:%' as tiene_0038,
       pg_get_functiondef('public.create_task(bigint,text,jsonb,uuid,text)'::regprocedure) like '%Invalid priority%' as tiene_prioridad;
-- Esperado: true, true.

-- C3. Grants iguales a A4.
select r.rolname, has_function_privilege(r.rolname, 'public.create_task(bigint,text,jsonb,uuid,text)'::regprocedure, 'execute') as puede
from pg_roles r where r.rolname in ('anon', 'authenticated')
order by 1;
-- Esperado: anon = false, authenticated = true.

-- C4. Migración registrada.
select version, name from supabase_migrations.schema_migrations where version >= '0037' order by 1;
-- Esperado: 0037 task_priority y 0038 task_create_person_access.
```

Si C1 muestra dos firmas o C2 no cumple: parar y, con confirmación del usuario, aplicar
`scripts/supabase/rollback/rollback_0038.sql` y repetir A3.

## D. Smoke de 400 (confirmación aparte)

Con un usuario de prueba (no con datos reales de otro usuario), en una lista suya:

1. `POST /task/create` con `person_ids` de una persona del hogar **sin cuenta** → 400
   `{"error":"Invalid person"}`. Comprobar que no se creó la tarea.
2. `POST /task/create` con `person_ids` de la propia persona del usuario (con cuenta y owner de la
   lista) → 201 con esa persona en `persons`. Borrar después la tarea de prueba.
3. `POST /task/create` sin `person_ids` → 201 (sin cambios). Borrar la tarea de prueba.

## Rollback

Solo BD (la Edge no cambia): `scripts/supabase/rollback/rollback_0038.sql`, con confirmación del
usuario. Es idempotente, no toca datos y restaura el `create_task` de 0037 y el `get_persons` de 0028
(sin `home_id`) con los mismos grants. Aborta
si no existe `create_task(bigint,text,jsonb,uuid,text)`. La fila `0038` de
`supabase_migrations.schema_migrations` no se borra.

**Orden LIFO obligatorio:** `rollback_0038` → `rollback_0037` → `rollback_0035`. `rollback_0037.sql`
tiene una guarda al principio: si `create_task` contiene el marcador `0038:` (la 0038 está aplicada),
aborta la transacción con `rollback_0037: 0038 está aplicada; revertir antes 0038 (rollback_0038.sql,
orden LIFO)` y no cambia nada. Revertir siempre antes la 0038. Si la firma de 5 argumentos ya no existe,
la guarda no salta y el script sigue siendo idempotente.
