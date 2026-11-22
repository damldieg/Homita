-- precheck_0037.sql — Pre-check SELECT-only antes del merge de 0037_task_priority.sql (change
-- prioridad-tarea, gate G1). Solo lecturas: la transacción es READ ONLY, así que cualquier DML/DDL
-- fallaría. Se ejecuta SOLO con la aprobación explícita del usuario (G1) y la salida se guarda en
-- .dorch/changes/prioridad-tarea/ para el go/no-go.
--
-- Uso (Session pooler; sin credenciales en git):  psql "$DB_URL" -X -v ON_ERROR_STOP=1 -f precheck_0037.sql
--
-- Esperado para GO:
--   Q1 última migración aplicada = 0036 (assistant_usage); ninguna 0037 ni posterior.
--   Q2 task sin columna priority ni constraint task_priority_check.
--   Q3 una sola firma por RPC: get_tasks(boolean,bigint,boolean), get_task_detail(bigint),
--      create_task(bigint,text,jsonb,uuid), update_task(bigint,text,jsonb); ACL y owner iguales a
--      los de local ({postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}, postgres).
--   Q4 ninguna vista ni objeto dependiente de task fuera de lo conocido (pg_depend/pg_views).
--   Q5 recuento de tareas (referencia para la verificación post-merge).

begin transaction read only;

\echo '== Q1 últimas migraciones'
select version, name from supabase_migrations.schema_migrations order by version desc limit 3;

\echo '== Q2 columna y constraint de prioridad (esperado: 0 filas)'
select column_name, data_type, is_nullable, column_default
  from information_schema.columns
 where table_schema = 'public' and table_name = 'task' and column_name = 'priority';
select conname from pg_constraint where conrelid = 'public.task'::regclass and conname = 'task_priority_check';

\echo '== Q3 firmas, ACL y owner de las RPC de tarea'
select p.oid::regprocedure as funcion, p.proacl as acl, pg_get_userbyid(p.proowner) as owner,
       p.prosecdef as security_definer
  from pg_proc p
 where p.pronamespace = 'public'::regnamespace
   and p.proname in ('get_tasks', 'get_task_detail', 'create_task', 'update_task')
 order by p.proname, p.oid::regprocedure::text;

\echo '== Q4 vistas que leen task y objetos dependientes de su fila de pg_class'
select schemaname, viewname from pg_views
 where schemaname not in ('pg_catalog', 'information_schema') and definition ~* '\mtask\M';
select classid::regclass as catalogo, objid, deptype
  from pg_depend
 where refobjid = 'public.task'::regclass and classid <> 'pg_class'::regclass
   and deptype = 'n'  -- dependencias normales: vistas (pg_rewrite), funciones BEGIN ATOMIC…
 order by 1, 2;

\echo '== Q5 recuento de tareas'
select count(*) as tareas from task;

rollback;
