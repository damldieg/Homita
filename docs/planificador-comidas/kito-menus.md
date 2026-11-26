# Kito y el menú semanal (skill `menus`)

Fase 5 del planificador de comidas (change `kito-menus`). Kito propone el menú de la semana como **borrador**,
la persona marca los platos que quiere cambiar, Kito repropone solo esos y la persona **acepta en la app**.
Kito nunca acepta un menú.

## Flujo

1. La persona pide un menú («proponme el menú de la semana»). La petición activa la skill `menus` por intención
   (menú, comidas, cenas, almuerzos, recetas de la semana) y se usa `KITO_MODEL_MENUS` (o `KITO_MODEL`).
2. Kito lee el perfil del hogar (`leer_perfil`), la semana (`leer_semana`: eventos y días fuera) y el recetario
   (`buscar_recetas`), pregunta como máximo 2 cosas de perfil (siempre con «ahora no») y llama a `proponer_menu`.
3. `proponer_menu` guarda el borrador con `origin = kito` y, si `check_meal_plan` da 0 conflictos
   (alergia, intolerancia, dieta, persona fuera), deja la tarjeta `menu`. Con conflictos no hay tarjeta: Kito
   corrige y reintenta, o explica que no encuentra alternativa.
4. En la tarjeta, la persona marca platos a cambiar (estado `rejected`, con motivo). «Pedir cambios» devuelve eso
   a Kito, que llama a `reproponer` solo con esas casillas.
5. La persona pulsa «Aceptar» en la app (`POST /meal/plan/accept`). Kito recuerda revisar los ingredientes en la
   Compra y marcar lo que ya hay en casa.

## Herramientas

| Herramienta | Qué hace |
| --- | --- |
| `leer_perfil` | Personas, alergias, dietas, gustos, franjas y países del hogar. Sin datos de salud si falta `menu.health.view`. Tolera que no haya países. |
| `leer_semana` | Eventos y personas fuera por día, plan existente de la semana con el estado de cada casilla. |
| `buscar_recetas` | Recetario del hogar e historial reciente (para no repetir). |
| `proponer_menu` | Crea o actualiza el borrador de la semana (`upsert_meal_plan_items`, `origin = kito`, `client_request_id`, `expected_revision`) y comprueba conflictos. |
| `reproponer` | Cambia solo casillas `rejected`; respeta `locked` y planes aceptados; usa la revisión vigente. |
| `guardar_receta` | Guarda una receta con pasos (obligatorios), `origin = kito`, idempotente. |
| `apuntar_compra` | Apunta artículos a la Compra, solo si la persona lo pide. |
| `apuntar_preferencia` | Apunta lo que no gusta (C1), lo que encanta (C2) o el picante (C4), solo tras preguntar y con `confirmado_por_usuario = true`. |

## Garantías (servidor)

- Migración `0048_menus_kito.sql`: `origin` (`user` | `kito`) en plan y receta, `client_request_id` idempotente en
  `upsert_meal_plan_items` y `create_recipe`, y estado por casilla `meal_plan_item.state` (`rejected` | `locked`).
- Con `origin = kito`: un plan aceptado no se edita, las casillas `locked` no se modifican ni se borran, Kito no
  puede poner `locked` y una receta de Kito exige pasos.
- `accept` no está en la lista de rutas de Kito ni en la confirmación HMAC de `organizar`: la skill no puede aceptar.
- Reintentos: `proponer_menu` y `reproponer` derivan el `client_request_id` del contenido y de la revisión; si las
  casillas libres ya coinciden con lo propuesto, `proponer_menu` no vuelve a escribir.

## Configuración y límites

- `KITO_MODEL_MENUS`: opcional; solo se usa si la petición tiene intención de menú. Sin él, `KITO_MODEL`.
- La skill pide hasta 8 rondas de herramientas (`maxRondas`), por encima de las 6 habituales.
- Tests: `supabase/functions/asistente/tests/menus_*_test.ts` (Deno, mundo falso) y el bloque XK de
  `scripts/supabase/tests/cross_tenant_check.py` (B no lee ni escribe el plan, la receta ni el `client_request` de A).
