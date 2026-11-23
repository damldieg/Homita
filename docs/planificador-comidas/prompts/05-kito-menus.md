Change `kito-menus` (Homita). Fase 5 de 5: skill `menus` de Kito sobre lo que ya existe.

## Contexto
Requiere las fases 1–3 en master y Kito con su núcleo de skills (`supabase/functions/asistente`, `skills/registry.ts`, `KitoCardRenderer` en iOS). Te paso `brief.md` y el plan de Kito. Regla de oro: **Kito no tiene tablas ni RPC propias**; sus herramientas llaman en proceso a `usecases/meals.ts` y `usecases/shopping.ts` con el JWT de la persona. **Kito nunca acepta**: devuelve una tarjeta `menu` y acepta la app al tocar.

Ojo: el 2026-11-23 master solo tiene la skill `consulta` (fase 1 de Kito). Esta fase necesita antes la fase 2 de Kito (escrituras con el JWT del usuario y tarjetas de confirmación). Si no está en master, para y avisa.

## Qué hacer
1. Change `.dorch/changes/kito-menus/`, rama `dc/kito-menus`, worktree `../Homita-kito-menus`.
2. `skills/menus/index.ts` con herramientas: `leer_perfil` (sin salud si falta `menu.health.view`), `leer_semana` (eventos + `meal_schedule`; marca días fuera y lo confirma), `buscar_recetas` (recetario + historial para no repetir, F3), `proponer_menu` y `reproponer` (solo casillas `rejected`, respeta `locked` y aceptadas; `origin = kito`, `p_expected_revision`, `client_request_id`), `guardar_receta` (recetas que Kito busca o crea, **con pasos**, `origin = kito`), `apuntar_compra`, `apuntar_preferencia` (C1/C2/C4, siempre tras preguntar). Antes de mostrar la tarjeta, `check_meal_plan` debe dar 0 conflictos.
3. Máximo 2 preguntas de perfil por menú, con «ahora no». Tras aceptar, Kito recuerda revisar ingredientes y marcar lo que ya hay.
4. Modelo con secreto `KITO_MODEL_MENUS` (si falta, `KITO_MODEL`). Prepara la comparación Haiku 5.5 vs Sonnet 5.5 sobre 10–20 hogares de ejemplo (fixtures) con conflictos, repeticiones y coste en tokens, para que Damian decida.
5. iOS: tarjeta `menu` en `KitoCardRenderer` (semana, marcar platos a cambiar con motivo, «Aceptar»), que llama a los mismos endpoints que la pestaña Menú.

## Verificación
Tests Deno de la skill con casos de uso falsos (reintentos sin duplicar, revisión vieja, conflicto de alergia bloquea la tarjeta, repropuesta solo de rechazados). `swift test`. Informe de la comparación de modelos.

## Reglas
- Nada en producción: no apliques migraciones ni despliegues la Edge. Sin push ni PR (status sin `authorized: push pr gh`). Nunca merge.
- Antes de empezar, `git fetch` y comprueba el último número de migración (el 2026-11-23 master llega a 0042) y usa el siguiente libre en `supabase/migrations/`, rollback en `scripts/supabase/rollback/` y check SQL en `scripts/supabase/tests/` añadido a `scripts/supabase/ci.sh` (mismo estilo que `client_request_check.sql`).
- Rutas nuevas de `api` aditivas al contrato (D-008) y con el estilo de nombres que ya hay (`GET /recurso`, `GET /recurso/detail`, `POST /recurso/create`, `PATCH /recurso/update`, `DELETE /recurso/delete`), casos de uso en `usecases/`, tests Deno en `supabase/functions/api/tests/` y casos nuevos en `scripts/supabase/tests/cross_tenant_check.py` (B no lee ni escribe lo de A).
- Hogar de las RPC del menú y la compra: el de `X-Home-Id`; sin cabecera, la misma regla que `fn_home_for_root_create()` (hogar por defecto o único; si no, `Home header required`). El dashboard no manda cabecera. iOS: `swift test` en `apps/control-ios` (0 fallos) + `xcodebuild build -scheme ControlApp` Debug y Release.
- Commits en español, estilo `Área: frase`, con `Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>`.
- No leas `~/.homita/supabase.env` ni valores de env.

## Al terminar, infórmame de
Hash, tests, tabla de la comparación y desviaciones.
