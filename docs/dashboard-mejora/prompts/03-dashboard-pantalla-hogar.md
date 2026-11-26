Change `dashboard-pantalla-hogar` (Homita). Paso 3 de 5 de la mejora del dashboard de pared: la pantalla pasa a ser del hogar y se vincula con un código desde el móvil.

## Contexto
Te paso `brief.md` de `docs/dashboard-mejora/` y el modelo de permisos (dos capas: ACL por calendario/lista + catálogo `fn_has_permission` del hogar; ver `docs/ARCHITECTURE.md`, matriz de autorización). Cubre A1, C1, A8, C6, Q4 y N6. Requiere `dashboard-sesion` en master.

Hoy el marco entra con email y contraseña de una persona y lee con su JWT: `GET /event?dashboard=true` y `GET /task?dashboard=true` filtran por la fila propia del ACL (`dashboard` en `calendar_user` / `task_list_user`), y `GET /meal/today` usa el hogar por defecto de esa cuenta. Es el cambio más grande de la mejora y toca BD, Edge, iOS y Android.

## Qué hacer
1. Change `.dorch/changes/dashboard-pantalla-hogar/`, rama `dc/dashboard-pantalla-hogar`, worktree `../Homita-dashboard-pantalla-hogar`.
2. **Primero, propuesta sin código** en `plan.md`, con las dos opciones de identidad de la pantalla y tu recomendación:
   - (a) **identidad propia**: cada pantalla es una cuenta técnica del hogar (usuario de GoTrue creado por el servidor y un `home_member` de un kind nuevo, p. ej. `display`, sin persona) con permisos de solo lectura más lo que pida el paso 4; su selección de calendarios y listas es suya;
   - (b) **en nombre del adulto que la vincula**: la pantalla recibe una sesión de ese adulto, limitada.
   Para cada una: tablas, cómo se filtran eventos, tareas y menú, cómo se revoca una pantalla, qué pasa si el adulto sale del hogar, impacto en el contrato D-008 y en los checks de permisos (`permisos_kind_check.sql` cuenta permisos y defaults exactos). Incluye el flujo de vinculación y los riesgos (fuerza bruta del código, código caducado, dos pantallas a la vez). **Para y espera la elección de Damian.**
3. Tras la elección, implementa:
   - BD: pantalla del hogar (`home_display` o similar: hogar, nombre, quién la vinculó, fechas, revocada) con su configuración (horario de pantalla, reloj nocturno, brillo, ubicación del tiempo, calendarios y listas que enseña) y código de vinculación de un solo uso (6 dígitos, caduca a los 10 min, tope de intentos). Permiso nuevo `display.manage` (dominio nuevo) con backfill en `membership_permission` solo de los códigos que falten, como en 0043. Rollback y check SQL.
   - Edge `api`: iniciar vinculación sin sesión (la pantalla pide un código y un secreto de sondeo), confirmar desde el móvil con `display.manage`, sondeo de la pantalla hasta recibir su sesión, listar, renombrar y revocar pantallas, y leer/escribir su configuración. Los GET de la pantalla (eventos, tareas, menú) filtran por la selección de la pantalla, sin `X-Home-Id`. Tests Deno y casos cross-tenant (una pantalla de A no ve nada de B; una revocada recibe 401).
   - iOS: en Perfil → Hogar, sección «Pantallas»: «Vincular pantalla» (introducir el código o leer el QR), lista con nombre, última conexión y «Desvincular», y ajustes de cada pantalla (horario, brillo, ubicación tomada del hogar por defecto, calendarios y listas).
   - Android: sin sesión, la pantalla enseña el código grande y un QR (genera el QR sin librerías nativas) y sondea cada 3 s mientras está visible; al vincular, guarda la sesión y aplica la configuración del servidor (la local queda como respaldo sin red). El formulario de email y contraseña queda oculto tras 5 toques en el logo, como modo técnico (Q4). En Ajustes, una caja «Diagnóstico» con versión, hogar, última sincronización de cada dato y el último error de cada endpoint (incluido el 403/400 de `/meal/today`, N6).
4. Migración de los marcos que ya existen: si hay sesión de persona guardada, sigue funcionando hasta que se vincule; documenta el paso.

## Verificación
Check SQL (código de un uso, caducidad, intentos, revocación, permisos), tests Deno, cross-tenant, `scripts/supabase/ci.sh`, tests iOS y build, tests JUnit4 (máquina de estados de la vinculación y aplicación de la configuración), y prueba completa en el emulador con la demo: vincular, cambiar el horario desde iOS, desvincular.

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
La propuesta del paso 2 primero; después hash, salidas de checks y tests, capturas del flujo de vinculación (pantalla e iOS) y desviaciones.
