# Despliegue de 0039 en prod (change `ocultar-completadas-3-dias`, D-025)

Guía para que el usuario ejecute o autorice cada paso. Nada de esto se ejecuta desde el build ni desde
un agente: cada paso que consulte prod o tenga efecto en prod requiere confirmación explícita aparte.
No usar `~/.homita/supabase.env` en pruebas locales (es prod).

**El merge a `master` aplica `0039` en prod automáticamente** (D-022). La Edge **no cambia** con este
change: no hay despliegue de funciones de la Edge. La 0039, en una transacción:

- añade la columna `task.hidden_at timestamptz` (nullable, sin default);
- la rellena en todas las completadas con `(completed_at + interval '3 days') at time zone 'UTC'`
  (backfill; no toca `completed_at`, `updated_at`, `"order"` ni `priority`);
- añade el CHECK `task_hidden_at_consistent`;
- redefine (mismas firmas y grants) `get_tasks`, `get_task_detail`,
  `complete_task`, `update_task`, `task_order`, `delete_task` y `fn_reorder_tasks`, y recrea la policy
  `task_select`.

**Efecto visible en el momento del merge:** las tareas completadas hace 3 días o más desaparecen a la
vez del marco, de Control iOS y de Control Android, y no se pueden recuperar desde ningún cliente (por
diseño, D-025). Avisar a la familia antes. P3 da la cifra exacta. Las escrituras sobre una tarea oculta
responden 500 `{"error":"Not Found"}`, igual que una inexistente (los builds viejos muestran «No
encontrado» o descartan la op de la cola; no se pierde nada).

## Orden

1. Gate de orden con git (A).
2. Pre-check SELECT-only en prod, P1–P6 (B). Cualquier diferencia bloquea el merge.
3. `pg_dump` de prod (C).
4. Gate de orden otra vez (A) y confirmación del usuario para el merge.
5. Merge de la PR (aplica 0039).
6. Gate posterior SELECT-only, G1–G7 (D). Si falla, parar y valorar el rollback (con confirmación).
7. Smoke de solo lectura (E).
8. Instalar el build de Control iOS con la recarga ante «Not Found» (no depende del orden del backend).

## A. Gate de orden (A15)

Solo lectura de git. Se ejecuta antes de abrir la PR y otra vez justo antes del merge, en el worktree
de la rama `dc/ocultar-completadas-3-dias`:

```sh
git fetch origin
git ls-tree --name-only origin/master supabase/migrations/ | grep -E '^supabase/migrations/003[78]_'
# Esperado: supabase/migrations/0037_task_priority.sql y supabase/migrations/0038_task_create_person_access.sql
git merge-base --is-ancestor origin/master HEAD && echo "rama al día con origin/master"
# Esperado: «rama al día con origin/master»
ls supabase/migrations | tail -1
# Esperado: 0039_task_hidden_at.sql
git ls-tree --name-only origin/master supabase/migrations/ | grep -E '/0039_'
# Esperado: vacío (ninguna otra 0039 en master; si aparece, renumerar antes de seguir)
```

Si algo no cumple, no se mergea.

## B. Pre-check SELECT-only (SQL editor de prod)

Solo `select`. Antes del merge debe cumplirse todo. Anotar los resultados de P3 y P6: son la
referencia del gate G.

```sql
-- P1. La columna no existe todavía.
select count(*) as columnas_hidden_at
from information_schema.columns
where table_schema = 'public' and table_name = 'task' and column_name = 'hidden_at';
-- Esperado: 0.

-- P2. La última migración aplicada es 0038 y no hay ninguna 0039.
select version, name from supabase_migrations.schema_migrations where version >= '0036' order by 1;
-- Esperado exactamente: 0036 assistant_usage, 0037 task_priority, 0038 task_create_person_access.

-- P3. Cifras de tareas: total, completadas, las que se ocultarán al aplicar 0039, recientes
-- (completadas hace menos de 3 días, siguen visibles) y con completed_at en el futuro (deberían ser 0).
select count(*) as total,
       count(*) filter (where completed_at is not null) as completadas,
       count(*) filter (where completed_at <= (now() at time zone 'UTC') - interval '3 days') as a_ocultar,
       count(*) filter (where completed_at > (now() at time zone 'UTC') - interval '3 days'
                          and completed_at <= (now() at time zone 'UTC')) as recientes,
       count(*) filter (where completed_at > (now() at time zone 'UTC')) as futuras
from task;
-- Esperado: a_ocultar + recientes + futuras = completadas. Anotar a_ocultar (referencia de G3) y
-- comunicarlo a la familia. Si futuras > 0, revisar antes de seguir (esas tareas quedarían ocultas
-- más tarde de lo esperado).

-- P4. Sin drift: una sola firma por función y md5 de los cuerpos = reset local 0001–0038
-- (las mismas constantes de rollback_0039.sql y de task_hidden_rollback_check RBH2).
select p.oid::regprocedure as firma, md5(pg_get_functiondef(p.oid)) as md5
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('get_tasks', 'get_task_detail', 'complete_task', 'update_task', 'task_order',
                    'delete_task', 'fn_reorder_tasks')
order by p.oid::regprocedure::text;
-- Esperado exactamente 7 filas:
--   complete_task(bigint,boolean)                9ae29a1507fea681afbbbb95d4a91f42
--   delete_task(bigint)                          739b0765bbe2dcf4feb2978eef6840d1
--   fn_reorder_tasks(bigint)                     e011b88332da15df3e0b365e50be996f
--   get_task_detail(bigint)                      7836409cddb8166d96accf9eda9055e2
--   get_tasks(boolean,bigint,boolean,text,text)  33a865e264ce1a37b88fd5c3405cc6e8
--   task_order(bigint,integer)                   f6a3aaec2bf25d06aa401ef742d209ac
--   update_task(bigint,text,jsonb,text)          c612b928103c69af64ba185d2f6553cf

select md5(pg_get_expr(polqual, polrelid)) as md5_task_select
from pg_policy
where polrelid = 'public.task'::regclass and polname = 'task_select' and polcmd = 'r';
-- Esperado: b3d1a237c023b4ce73d89666567a1538.
-- Si algún md5 difiere (drift o versión menor de PostgreSQL distinta de la del CI), NO se mergea:
-- comparar el cuerpo a mano con la última definición (0037_task_priority.sql, 0029_acl_can_edit.sql,
-- 0006_write_rpcs.sql, 0020_home_write_guards.sql). rollback_0039 restauraría los cuerpos locales.

-- P5. Constraints actuales de task.
select conname, contype::text as tipo, convalidated
from pg_constraint
where conrelid = 'public.task'::regclass
order by 1;
-- Esperado: task_pkey (p), task_priority_check (c), task_task_list_id_fkey (f).
-- Sin task_hidden_at_consistent.

-- P6. Baseline de filas y de completed_at (referencia de G2, A6).
select count(*) as filas,
       md5(string_agg(id::text || ':' || coalesce(completed_at::text, 'null'), ',' order by id)) as md5_completed
from task;
-- Anotar filas y md5_completed. Repetir G2 en la misma herramienta (mismo DateStyle).
```

## C. `pg_dump` previo

Red de seguridad. Lo ejecuta el usuario con la cadena de conexión de prod en una variable de entorno de
su shell (nunca en git). Es de solo lectura sobre prod:

```sh
# $PROD_DB_URL: conexión directa de solo lectura al proyecto de prod.
mkdir -p ~/backups-homita
stamp=$(date +%Y%m%d-%H%M)
# Esquema y datos de las tablas de tareas.
pg_dump "$PROD_DB_URL" --no-owner \
  -t public.task -t public.task_list -t public.task_list_user -t public.task_person \
  -f ~/backups-homita/pre-0039-tareas-$stamp.sql
# Esquema de public (cuerpos de las funciones y la policy, para comparar en un rollback).
pg_dump "$PROD_DB_URL" --schema=public --schema-only --no-owner \
  -f ~/backups-homita/pre-0039-schema-$stamp.sql
grep -c "COPY public.task " ~/backups-homita/pre-0039-tareas-$stamp.sql
grep -n "FUNCTION public.complete_task(" ~/backups-homita/pre-0039-schema-$stamp.sql
```

Comprobar que los dos ficheros no están vacíos, que el primero contiene los `COPY` de las cuatro tablas
y que el segundo contiene la definición de `public.complete_task(` sin `0039:`. Guardarlos fuera del repo.

## D. Gate posterior G1–G7 (tras el merge)

Solo `select`. Si algo no cumple: parar y valorar el rollback (con confirmación del usuario).

```sql
-- G1. Columna y CHECK presentes.
select data_type, is_nullable, column_default
from information_schema.columns
where table_schema = 'public' and table_name = 'task' and column_name = 'hidden_at';
-- Esperado: timestamp with time zone, YES, null.
select conname, convalidated from pg_constraint
where conrelid = 'public.task'::regclass and conname = 'task_hidden_at_consistent';
-- Esperado: 1 fila, convalidated = true.

-- G2. Filas y completed_at intactos (A6): mismo resultado que P6.
select count(*) as filas,
       md5(string_agg(id::text || ':' || coalesce(completed_at::text, 'null'), ',' order by id)) as md5_completed
from task;
-- Esperado: filas y md5_completed iguales a P6 (si entre medias alguien completó, creó o borró una
-- tarea, la diferencia debe explicarse con esas tareas; revisar antes de seguir).

-- G3. Ocultas ahora frente a P3.
select count(*) filter (where hidden_at is not null and hidden_at <= now()) as ocultas,
       count(*) filter (where hidden_at > now()) as completadas_visibles
from task;
-- Esperado: ocultas ≈ a_ocultar de P3 (más las que cruzaron el umbral de 3 días entre P3 y el merge).

-- G4. Consistencia: ninguna completada sin hidden_at, ninguna pendiente con hidden_at y ninguna fuera
-- de la fórmula.
select count(*) filter (where completed_at is not null and hidden_at is null) as completadas_sin_hidden,
       count(*) filter (where completed_at is null and hidden_at is not null) as pendientes_con_hidden,
       count(*) filter (where completed_at is not null
                          and hidden_at is distinct from (completed_at + interval '3 days') at time zone 'UTC') as fuera_de_formula
from task;
-- Esperado: 0, 0, 0.

-- G5. Cuerpos nuevos = los de la 0039 del repo (md5 del reset local 0001–0039) y una firma por función.
-- ci.sh (paso «G5-md5») compara estas 8 constantes con el stack local; si difieren solo imprime «ADVERTENCIA md5».
select p.oid::regprocedure as firma, md5(pg_get_functiondef(p.oid)) as md5
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('get_tasks', 'get_task_detail', 'complete_task', 'update_task', 'task_order',
                    'delete_task', 'fn_reorder_tasks')
order by p.oid::regprocedure::text;
-- Esperado exactamente 7 filas:
--   complete_task(bigint,boolean)                ca84b060cdd0c2eb0e22940c81cd1eb4
--   delete_task(bigint)                          d2d8bbfb2fed8be9cdf4cc2e539057c9
--   fn_reorder_tasks(bigint)                     9b67310fbc6ea519a8e9b65fe721016a
--   get_task_detail(bigint)                      d488c42c25bb1225109563d319d43f74
--   get_tasks(boolean,bigint,boolean,text,text)  fd14816f900ae4210a6c7956359e319d
--   task_order(bigint,integer)                   e83eed13eab2aaa1ecb0a55941e12166
--   update_task(bigint,text,jsonb,text)          310ab29be695008761b677a47646806b
select md5(pg_get_expr(polqual, polrelid)) as md5_task_select
from pg_policy
where polrelid = 'public.task'::regclass and polname = 'task_select' and polcmd = 'r';
-- Esperado: 91c05c598ade66331b39813a06bb17c2.

-- G6. Grants iguales a los de antes (las firmas no cambian).
select r.rolname, p.oid::regprocedure as firma, has_function_privilege(r.rolname, p.oid, 'execute') as puede
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
cross join pg_roles r
where n.nspname = 'public'
  and p.proname in ('get_tasks', 'get_task_detail', 'complete_task', 'update_task', 'task_order',
                    'delete_task', 'fn_reorder_tasks')
  and r.rolname in ('anon', 'authenticated')
order by r.rolname, p.oid::regprocedure::text;
-- Esperado: anon = false en todas; authenticated = true en todas salvo fn_reorder_tasks (false).

-- G7. Migración registrada.
select version, name from supabase_migrations.schema_migrations where version >= '0038' order by 1;
-- Esperado: 0038 task_create_person_access y 0039 task_hidden_at.
```

## E. Smoke de solo lectura (usuario)

Sin escribir nada:

1. El marco ya no muestra las completadas de hace 3 días o más; las completadas recientes siguen.
2. En Control iOS, tras refrescar la pestaña Tareas y la tarjeta de Inicio, las completadas antiguas
   ya no aparecen y los recuentos de pendientes de cada lista no cambian.

## Rollback

Solo BD (la Edge no cambia): `scripts/supabase/rollback/rollback_0039.sql`, con confirmación explícita
del usuario. Antes de aplicarlo, repetir P4 contra el `pg_dump` de C si hay dudas de drift.

- Es idempotente y va en una transacción. Restaura verbatim los 7 cuerpos de antes de 0039 (mismas
  firmas, sin DROP de funciones, grants intactos) y la policy `task_select` de 0020, y después hace
  `drop constraint if exists task_hidden_at_consistent` y `drop column if exists hidden_at`.
- **Datos:** solo se pierde `hidden_at`, que se deriva de `completed_at`; reaplicar 0039 lo recalcula.
  Ninguna fila se borra ni cambia `completed_at`. Las tareas ocultas vuelven a verse y a ser editables,
  con su `"order"` congelado (cosmético; el siguiente reorden lo arregla).
- La fila `0039` de `supabase_migrations.schema_migrations` no se borra (mismo criterio que
  0035/0037/0038).
- Tras el rollback, P1 debe dar 0 y P4 las constantes de B.

**Orden LIFO obligatorio:** `rollback_0039` → `rollback_0038` → `rollback_0037` → `rollback_0035`.
`rollback_0038.sql` tiene una guarda al principio: si existe la columna `task.hidden_at` (0039
aplicada), aborta con `rollback_0038: 0039 está aplicada; revertir antes 0039 (rollback_0039.sql, orden
LIFO)` y no cambia nada. `rollback_0039.sql` aborta a su vez si faltan las firmas de 0037
(`get_tasks` de 5 argumentos o `update_task` de 4).
