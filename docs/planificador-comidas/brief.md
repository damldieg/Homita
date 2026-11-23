# Brief: planificador de comidas (Menú + Compra), manual primero y Kito después

Pedido por Damian el 2026-11-22. Documento de diseño completo (Claude Doc):
https://claude.ai/artifact/TqFXKNXcuH5WriUcBEsyLs · Diseño del perfil de hogar: `perfil-hogar-campos.txt`
(texto del doc https://claude.ai/artifact/AqwFjaMnDuDmesknjcVKCa).

## Objetivo
Un hogar planifica su menú semanal y su compra en Homita. Fase manual: la persona lo crea todo a mano.
Después, la skill `menus` de Kito propone el menú, la persona marca qué cambiar, Kito repropone solo lo
rechazado y la persona acepta. Todo lo manual sienta las bases: **app y Kito llaman a los mismos casos de
uso de `supabase/functions/api` con el JWT de la persona** (mismas RPC, permisos y validaciones).

## Decisiones de Damian (2026-11-22)
- **Sin eventos de calendario.** Pestaña nueva «Menú» (Semana · Compra · Recetas). Lo de hoy en una tarjeta
  «Comidas de hoy» en Inicio de Control iOS (como «Rutinas de hoy»), y más tarde en la pantalla de pared
  (dashboard Android) y en un widget iOS; hay que ver cómo convive con lo que ya hay.
- **Hora fija por franja** (comida 14:00, cena 21:00 por defecto), editable en el perfil.
- **Compra = tipo propio, una sola por hogar**, no tareas. Se **actualiza sola** al cambiar el menú aceptado,
  sin tocar nunca lo marcado, lo «ya lo tengo», lo añadido a mano ni las cantidades editadas; avisa de lo que
  cambió. Al generarse, la app (y luego Kito) pide **revisar ingredientes y marcar lo que ya hay**.
  Las listas de compra que hoy son tareas se quedan como están.
- **Recetas**: nombre, raciones, tiempo e ingredientes; pasos opcionales. Traer recetas con pasos es de Kito.
- **Catálogo de alimentos** sembrado (~300, español, sección del súper, 14 alérgenos UE) + texto libre.
- **Permisos**: editar y aceptar el menú = adultos y familiares; marcar la Compra = adultos, niños y familiares.
- **Tier**: todo para todos de momento.

## Supuestos pendientes de confirmar (preguntas abiertas del perfil de hogar)
- Arranque con las 7 preguntas (A1, A2, B1, B5, D1, D2 simple, E1 simple). Franjas por defecto: comida y cena.
- Editar el perfil del hogar: solo adultos. Cada persona con cuenta edita siempre sus propios gustos (bloque C).
- Datos de salud B3/B4 **fuera del piloto** (no hay política de privacidad). B1 alergias sí, obligatoria.
- Presupuesto (G1) solo orientativo. Formulario en Ajustes ahora; preguntas desde Kito en la fase 5.

## Modelo (resumen; detalle en el doc)
Perfil: `meal_profile`, `meal_profile_member` (por `home_member`, sin mascotas), `meal_schedule`,
`meal_slot_setting` (slot, enabled, time). Menú: `food`, `recipe`, `recipe_ingredient`, `meal_plan`
(draft → accepted → archived, `revision`, `shopping_revision`), `meal_plan_item` (fecha × franja × posición;
kind recipe/free_text/leftovers/eat_out; status proposed/accepted/rejected; locked; feedback; cook_member_id),
`meal_plan_item_member`. Compra: `shopping_item` (label, food_id, quantity, unit, section, origin
manual/menu/kito, plan_id + agg_key, sources, qty_overridden, state pending/checked/skipped, checked_at/by).
RPC clave: `get_meal_profile`, `check_meal_plan`, `get_meals_today`, `preview_meal_shopping`,
`sync_meal_shopping` (diff idempotente por (plan_id, agg_key)). `client_request.kind` gana `shopping_item`
y `meal_shopping_sync`. Todo con RLS por `fn_my_home_ids()`, RPC `security definer` + `fn_has_permission`
+ `audit_log` (patrón 0019/0020). Kito nunca acepta: solo escribe el borrador.

## Permisos (catálogo del hogar)
| Código | Adulto | Niño | Familiar | Invitado |
|---|---|---|---|---|
| menu.view | sí | sí | sí | no |
| menu.plan.manage | sí | no | sí | no |
| menu.shopping.edit | sí | sí | sí | no |
| menu.profile.edit | sí | no | no | no |
| menu.health.view | sí | no | no | no |

## Changes (uno por fase, cada uno usable solo)
1. `menus-perfil-hogar` · 2. `menus-semana` · 3. `menus-compra` · 4. `menus-pantalla-widget` · 5. `kito-menus`.
Prompts en `prompts/`.

## Reglas
Flujo dorch (brief/status en `.dorch/changes/<slug>/`, rama `dc/<slug>` desde `origin/master`, worktree
`../Homita-<slug>`). Nada en producción. Sin push/PR sin `authorized: push pr gh`. Nunca merge.
Commits en español `Área: frase` con `Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>`.

## Auditoría del repo (2026-11-23, master d3f36b5)
- Migraciones hasta 0042: las nuevas empiezan en 0043 o la siguiente libre.
- Los permisos se guardan por membresía (`membership_permission`): los códigos `menu.*` necesitan backfill
  por kind para los miembros que ya existen, y `permisos_kind_check.sql` cuenta 23/37 exactos.
- Inicio tiene bloques ordenables (`InicioBlock`: routines, events, tasks): «Comidas de hoy» es un bloque más.
- La barra de iOS ya tiene 5 pestañas: Menú obliga a mover una (decisión de Damian pendiente).
- `client_request.kind` solo admite task/task_list y `resource_id` es obligatorio.
- La cola sin conexión (`Offline/PendingOp`) solo cubre tareas y listas.
- Rutas con estilo `/recurso/create|update|delete`; el dashboard llama sin `X-Home-Id`
  (hogar por la regla de `fn_home_for_root_create()`).
- Kito en master: solo la skill `consulta`. La fase 5 necesita antes la fase 2 de Kito.
- Dashboard: `dashboard-sesion-hogar` y `dashboard-hoy-legible` (auditoría del 22/11) tocan lo mismo que la fase 4.
