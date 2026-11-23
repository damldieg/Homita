Change `menus-pantalla-widget` (Homita). Fase 4 de 5: «Hoy se come» en la pantalla de pared (dashboard Android) y en un widget iOS.

## Contexto
Requiere `menus-semana` (y idealmente `menus-compra`) en master. Te paso `brief.md`. La pantalla y los widgets hoy solo leen eventos y tareas; el menú no son eventos, así que necesitan su propia tarjeta sobre `get_meals_today`. Damian pidió **ver cómo convive con lo que ya hay** antes de decidir el diseño.

Ojo, dos changes del dashboard propuestos en la auditoría del 2026-11-22 tocan lo mismo: `dashboard-sesion-hogar` (sesión del hogar, refresh del JWT) y `dashboard-hoy-legible` (rehacer Hoy, que hoy da más de la mitad a reloj y tiempo). Si alguno está en master o en curso, parte de él y no lo dupliques.

## Qué hacer
1. Change `.dorch/changes/menus-pantalla-widget/`, rama `dc/menus-pantalla-widget`, worktree `../Homita-menus-pantalla-widget`.
2. **Primero, propuesta sin código**: revisa `apps/dashboard/.../ui/TodayScreen.kt`, `App.kt` y el resto de pantallas, y `apps/control-ios/HomitaWidgets` (`RoutinesWidget`, `WidgetTheme`). Propón 2 opciones de dónde y cómo va «Hoy se come» en la pantalla (p. ej. dentro de Hoy vs. pantalla propia en la rotación) y en el widget (nuevo widget vs. dentro del de rutinas), con lo que se desplaza en cada una. **Para y espera la elección de Damian** antes de implementar.
3. Tras la elección:
   - Edge: la ruta de hoy usable por el dashboard, que llama sin `X-Home-Id` (mismo modelo de auth que `GET /event` y `GET /task`; hogar por la regla de `fn_home_for_root_create()`), sin datos de salud.
   - Android: `Api.kt` + repositorio con `DiskCache`/`CachedResource` (stale-if-error), modelo, tarjeta en Compose con `Density(1f)`; tests JUnit4 del repositorio.
   - iOS widget: nuevo proveedor con datos en el App Group como el de rutinas; se refresca al cambiar el menú y al pasar cada franja.

## Verificación
`./gradlew :app:testDebugUnitTest` y `:app:lintDebug` en `apps/dashboard`; `swift test` y build de `ControlApp` (incluye `HomitaWidgets`); ci.sh si tocas la Edge.

## Reglas
- Nada en producción: no apliques migraciones ni despliegues la Edge. Sin push ni PR (status sin `authorized: push pr gh`). Nunca merge.
- Antes de empezar, `git fetch` y comprueba el último número de migración (el 2026-11-23 master llega a 0042) y usa el siguiente libre en `supabase/migrations/`, rollback en `scripts/supabase/rollback/` y check SQL en `scripts/supabase/tests/` añadido a `scripts/supabase/ci.sh` (mismo estilo que `client_request_check.sql`).
- Rutas nuevas de `api` aditivas al contrato (D-008) y con el estilo de nombres que ya hay (`GET /recurso`, `GET /recurso/detail`, `POST /recurso/create`, `PATCH /recurso/update`, `DELETE /recurso/delete`), casos de uso en `usecases/`, tests Deno en `supabase/functions/api/tests/` y casos nuevos en `scripts/supabase/tests/cross_tenant_check.py` (B no lee ni escribe lo de A).
- Hogar de las RPC del menú y la compra: el de `X-Home-Id`; sin cabecera, la misma regla que `fn_home_for_root_create()` (hogar por defecto o único; si no, `Home header required`). El dashboard no manda cabecera. iOS: `swift test` en `apps/control-ios` (0 fallos) + `xcodebuild build -scheme ControlApp` Debug y Release.
- Commits en español, estilo `Área: frase`, con `Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>`.
- No leas `~/.homita/supabase.env` ni valores de env.

## Al terminar, infórmame de
La propuesta del paso 2 primero; después hash, tests y capturas.
