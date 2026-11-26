Change `dashboard-marcar-hecho` (Homita). Paso 4 de 5 de la mejora del dashboard de pared: completar tareas con un toque y filtrar por persona.

## Contexto
Te paso `brief.md` de `docs/dashboard-mejora/`. Cubre A2 y U4. Requiere `dashboard-hoy-legible` y `dashboard-pantalla-hogar` en master. Antes de empezar confirma con Damian la decisión abierta 1 del brief (¿la pantalla escribe?); si la respuesta es «solo lectura», haz solo el filtro por persona.

El backend ya tiene `PATCH /task/complete` con el JWT del usuario y la matriz M + E + permiso del catálogo. La pantalla actúa con la identidad elegida en el paso 3.

## Qué hacer
1. Change `.dorch/changes/dashboard-marcar-hecho/`, rama `dc/dashboard-marcar-hecho`, worktree `../Homita-dashboard-marcar-hecho`.
2. Backend: que la identidad de la pantalla pueda completar y descompletar tareas de las listas que enseña y nada más (ni crear, ni editar, ni borrar). Si hace falta un permiso nuevo del catálogo (p. ej. `task.complete`) añádelo con backfill y actualiza los checks de permisos. Registra en `audit_log` que lo hizo la pantalla. Usa la idempotencia de `client_request` (0035) para que un toque repetido sin red no duplique nada.
3. Android:
   - Casilla en cada tarea de Tareas y de cualquier bloque de tareas de Hoy; al tocar, se marca al momento (optimista) y aparece «Deshacer» 5 s; la petición sale al terminar ese tiempo. Sin red, queda en una cola en disco que se envía al volver la red; si el servidor responde 403 o 404, se revierte y se avisa.
   - Filtro por persona (U4): tocar el avatar de una persona (en «lo siguiente», en eventos, rutinas o tareas) filtra Hoy, Calendario y Tareas a lo suyo, con una píldora «Viendo: Lucía ✕»; vuelve a todos tras 2 min sin tocar.
   - Área táctil mínima 64 px; nada de diálogos del sistema.
4. Docs: el dashboard deja de ser «de solo lectura» en README y `docs/ARCHITECTURE.md`; explica qué puede escribir.

## Verificación
Tests Deno y cross-tenant (la pantalla no completa tareas de listas que no enseña ni de otro hogar; no puede editar ni borrar), check SQL si hay permiso nuevo, `scripts/supabase/ci.sh`, tests JUnit4 de la cola (optimista, deshacer, sin red, revertir en 403) y del filtro por persona. Prueba en el emulador con la demo: completar, deshacer, completar sin red y recuperar.

## Reglas
- Nada en producción: no apliques migraciones, no despliegues la Edge ni instales en el marco real. Sin push ni PR (status sin `authorized: push pr gh`). Nunca merge.
- Antes de empezar, `git fetch` y comprueba el último número de migración (el 2026-11-26 master llega a 0048) y usa el siguiente libre en `supabase/migrations/`, rollback en `scripts/supabase/rollback/` y check SQL en `scripts/supabase/tests/` añadido a `scripts/supabase/ci.sh` (mismo estilo que `client_request_check.sql`).
- Rutas nuevas de `api` aditivas al contrato (D-008), con el estilo de nombres que ya hay, casos de uso en `usecases/`, tests Deno en `supabase/functions/api/tests/` y casos nuevos en `scripts/supabase/tests/cross_tenant_check.py` (B no lee ni escribe lo de A).
- Android (`apps/dashboard`): píxeles nativos con `Density(1f)`, sin librerías nativas, minSdk 29, nada de animaciones continuas nuevas (el marco se calienta). Verificación: `./gradlew :app:testDebugUnitTest :app:lintDebug :app:assembleDebug`; tests JUnit4 de la lógica pura.
- iOS, si lo tocas: `swift test` en `apps/control-ios` (0 fallos) + `xcodebuild build -scheme ControlApp` Debug y Release.
- Actualiza `docs/ARCHITECTURE.md` y el README del dashboard con lo que cambie.
- Commits en español, estilo `Área: frase`, con `Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>`.
- No leas `~/.homita/supabase.env` ni valores de env.

## Al terminar, infórmame de
Hash, salidas de tests y ci.sh, capturas y desviaciones.
