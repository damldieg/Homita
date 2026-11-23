Change `menus-semana` (Homita). Fase 2 de 5: recetas, catálogo y menú semanal a mano, con «Comidas de hoy» en Inicio.

## Contexto
Requiere la fase 1 (`menus-perfil-hogar`) en master. Te paso `brief.md`. Decisión clave: **sin eventos de calendario**; el menú es un módulo propio y lo de hoy sale en Inicio.

## Qué hacer
1. Change `.dorch/changes/menus-semana/` (brief, plan de la fase, status `approved: yes`), rama `dc/menus-semana`, worktree `../Homita-menus-semana`.
2. Migración:
   - `food`: `home_id` nulo = catálogo común (solo lectura), con valor = del hogar. `name`, `name_norm`, `section`, `allergens text[]` (14 de la UE), `default_unit`, `grams_per_unit`. Semilla de **~300 alimentos en español** (fichero SQL aparte, revisable a mano) con sección y alérgenos.
   - `recipe` y `recipe_ingredient` (unidad: g, kg, ml, l, ud, cda, cdta, pizca, al gusto; `food_id` o texto libre; pasos opcionales).
   - `meal_plan` (draft → accepted → archived; `revision` sube en cada cambio; único por hogar y `week_start` no archivado) y `meal_plan_item` + `meal_plan_item_member` como en el brief. Comensales por defecto desde `meal_schedule`.
   - RPC: CRUD de recetas, `upsert_meal_plan_items` (con `p_expected_revision`: revisión vieja → error, para Kito), `accept_meal_plan`, `copy_meal_plan_week`, `check_meal_plan(plan_id)` (conflictos de alérgenos B1/B2, dieta B5 y comensal fuera) y `get_meals_today(p_date)` (casillas aceptadas con plato, franja, hora de `meal_slot_setting`, comensales, quién cocina). Permisos `menu.view` / `menu.plan.manage`.
3. Edge `api`: casos de uso en `usecases/meals.ts` y rutas aditivas (p. ej. `/recipe`, `/meal/plan`, `/meal/plan/items`, `/meal/plan/accept`, `/meal/plan/check`, `/meal/today`).
4. iOS (`Features/Meals/`, `MealsStore` @Observable, repos en `Repo/`): pestaña nueva «Menú» con selector Semana · Compra · Recetas (Compra vacía hasta la fase 3).
   - **Barra de pestañas**: hoy hay 5 (Inicio, Tareas, Calendario, Hogar, Ajustes, en `RootView.swift`) y en iPhone una sexta acaba en «Más». Aplica la opción que Damian elija (recomendada: Ajustes sale de la barra a un engranaje arriba en Inicio). Añade el destino Menú a `DeepLinkCenter`.
   - Semana: rejilla día × franjas activas, flechas entre semanas, nº de eventos por día, «fuera» según `meal_schedule`, estado borrador/aceptado, «repetir semana pasada», «copiar día».
   - Casilla: receta del recetario (filtro por franja y tiempo), texto libre, sobras o comer fuera; comensales y raciones; aviso rojo de `check_meal_plan`.
   - Recetas: lista con búsqueda y ficha con ingredientes del catálogo (autocompletar) o texto libre.
   - Inicio: tarjeta «Comidas de hoy» como **bloque nuevo** de Inicio: caso `meals` en `InicioBlock` (`Sources/HomitaShared/InicioLayout.swift`), visible en Ajustes › Inicio (`InicioSettingsView`) para ordenarla u ocultarla. `normalized` la añade al final en los iPhone que ya tienen un orden guardado; colócala tras Rutinas por defecto y cubre la migración del orden guardado en tests. Mismo estado por hora que `RoutinesTodayCard` (próxima, ahora, hecha) con la hora de cada franja; al tocar abre la receta. Se oculta si el hogar no tiene menú aceptado esa semana.

## Verificación
Check SQL: RLS entre hogares, catálogo común de solo lectura, unicidad del plan, revisión vieja rechazada, conflictos de alergia detectados, `get_meals_today` con zona horaria del hogar, rollback → reaplicar. Tests Deno de los casos de uso y `swift test`.

## Reglas
- Nada en producción: no apliques migraciones ni despliegues la Edge. Sin push ni PR (status sin `authorized: push pr gh`). Nunca merge.
- Antes de empezar, `git fetch` y comprueba el último número de migración (el 2026-11-23 master llega a 0042) y usa el siguiente libre en `supabase/migrations/`, rollback en `scripts/supabase/rollback/` y check SQL en `scripts/supabase/tests/` añadido a `scripts/supabase/ci.sh` (mismo estilo que `client_request_check.sql`).
- Rutas nuevas de `api` aditivas al contrato (D-008) y con el estilo de nombres que ya hay (`GET /recurso`, `GET /recurso/detail`, `POST /recurso/create`, `PATCH /recurso/update`, `DELETE /recurso/delete`), casos de uso en `usecases/`, tests Deno en `supabase/functions/api/tests/` y casos nuevos en `scripts/supabase/tests/cross_tenant_check.py` (B no lee ni escribe lo de A).
- Hogar de las RPC del menú y la compra: el de `X-Home-Id`; sin cabecera, la misma regla que `fn_home_for_root_create()` (hogar por defecto o único; si no, `Home header required`). El dashboard no manda cabecera. iOS: `swift test` en `apps/control-ios` (0 fallos) + `xcodebuild build -scheme ControlApp` Debug y Release.
- Commits en español, estilo `Área: frase`, con `Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>`.
- No leas `~/.homita/supabase.env` ni valores de env.

## Al terminar, infórmame de
Hash, checks, tests, capturas de Semana e Inicio si puedes, y desviaciones.
