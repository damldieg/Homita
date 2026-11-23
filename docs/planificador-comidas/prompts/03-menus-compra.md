Change `menus-compra` (Homita). Fase 3 de 5: la Compra como subsección propia del Menú, sincronizada sola con el menú aceptado.

## Contexto
Requiere `menus-semana` en master. Te paso `brief.md`. Decisiones: **una sola Compra por hogar, no tareas**; se actualiza sola al cambiar el menú aceptado sin tocar lo marcado, lo «ya lo tengo», lo manual ni cantidades editadas; al generarse pide revisar ingredientes.

## Qué hacer
1. Change `.dorch/changes/menus-compra/`, rama `dc/menus-compra`, worktree `../Homita-menus-compra`.
2. Migración:
   - `shopping_item` como en el brief. Índice único parcial `(plan_id, agg_key)` para los de origen `menu`.
   - `preview_meal_shopping(plan_id)`: suma servidor. Factor = comensales (ración A3) / `recipe.servings`; salta `optional`, «al gusto» y despensa básica G3; agrupa por `food_id` (o `name_norm`) + familia de unidad (g/kg → g, ml/l → ml, ud aparte, `grams_per_unit` si existe); redondeo comprable; `sources` con los platos.
   - `sync_meal_shopping(plan_id, p_client_request_id)`: diff en una transacción (crea pendientes que faltan, actualiza cantidad de pendientes sin `qty_overridden`, borra pendientes que ya no salen, nunca toca checked/skipped/manual); guarda `shopping_revision`; devuelve `{added, updated, removed}`. Se llama desde `accept_meal_plan` y desde `upsert_meal_plan_items` cuando el plan está aceptado, en la misma transacción.
   - CRUD de artículos (`create_shopping_item` con `p_client_request_id`, marcar/desmarcar, «ya lo tengo», editar cantidad → `qty_overridden`, borrar, vaciar comprados) con `menu.shopping.edit`.
   - `client_request.kind` admite `shopping_item` y `meal_shopping_sync`: el check de 0035 es `kind in ('task', 'task_list')` y `resource_id` es `not null` (para la sync usa el `plan_id`). Revisa también `client_request_check.sql`.
3. Edge `api`: `usecases/shopping.ts` y rutas aditivas (`/shopping`, `/shopping/item`, `/shopping/item/check`…).
4. iOS: subsección Compra (`ShoppingStore`): por sección, tocar marca, añadir a mano con autocompletar del catálogo, «para qué plato es», aviso de cambios («+2 −1») y, al generarse, banner «Revisa los ingredientes y marca los que ya tengas» que lleva a un modo revisión con «ya lo tengo». Paso de Aceptar en Semana con resumen de lo que entra. **Sin conexión**: extiende `Offline/` para alta, marcar y desmarcar artículos, como las tareas: casos nuevos en `PendingOp.Kind` (hoy solo tareas y listas), su replay en `OutboxReplayer`, compactación en `OutboxCompactor` y pintado en `PendingOverlay`, con `client_request_id` en las altas.

## Verificación
Check SQL: suma con conversiones y despensa, sync dos veces = sin cambios, mismo `client_request_id` = mismo resultado, marcados y manuales intactos tras cambiar el menú, permisos (niño marca, invitado no). Tests Deno del diff. `swift test` incluida la cola sin conexión.

## Reglas
- Nada en producción: no apliques migraciones ni despliegues la Edge. Sin push ni PR (status sin `authorized: push pr gh`). Nunca merge.
- Antes de empezar, `git fetch` y comprueba el último número de migración (el 2026-11-23 master llega a 0042) y usa el siguiente libre en `supabase/migrations/`, rollback en `scripts/supabase/rollback/` y check SQL en `scripts/supabase/tests/` añadido a `scripts/supabase/ci.sh` (mismo estilo que `client_request_check.sql`).
- Rutas nuevas de `api` aditivas al contrato (D-008) y con el estilo de nombres que ya hay (`GET /recurso`, `GET /recurso/detail`, `POST /recurso/create`, `PATCH /recurso/update`, `DELETE /recurso/delete`), casos de uso en `usecases/`, tests Deno en `supabase/functions/api/tests/` y casos nuevos en `scripts/supabase/tests/cross_tenant_check.py` (B no lee ni escribe lo de A).
- Hogar de las RPC del menú y la compra: el de `X-Home-Id`; sin cabecera, la misma regla que `fn_home_for_root_create()` (hogar por defecto o único; si no, `Home header required`). El dashboard no manda cabecera. iOS: `swift test` en `apps/control-ios` (0 fallos) + `xcodebuild build -scheme ControlApp` Debug y Release.
- Commits en español, estilo `Área: frase`, con `Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>`.
- No leas `~/.homita/supabase.env` ni valores de env.

## Al terminar, infórmame de
Hash, checks, tests y desviaciones.
