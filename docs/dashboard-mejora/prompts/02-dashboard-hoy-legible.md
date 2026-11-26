Change `dashboard-hoy-legible` (Homita). Paso 2 de 5 de la mejora del dashboard de pared: Hoy legible a 2–3 metros, menos duplicados y avisos de vencimiento correctos.

## Contexto
Te paso `brief.md` de `docs/dashboard-mejora/`. Cubre U2, U3, U5–U9, C2, C4, C5, Q1–Q3, Q5 y N1–N5. Solo Android, sin backend (si U8 necesita que `GET /task?dashboard=true` devuelva `persons`, comprueba primero si ya llegan desde 0024 y, si no, para y dímelo). Puede ir en paralelo a `dashboard-sesion`.

Damian quiere **ver el diseño antes de implementarlo**.

## Qué hacer
1. Change `.dorch/changes/dashboard-hoy-legible/`, rama `dc/dashboard-hoy-legible`, worktree `../Homita-dashboard-hoy-legible`.
2. **Primero, propuesta sin código.** Lee `ui/TodayScreen.kt`, `App.kt`, `CalendarScreen.kt`, `TasksScreen.kt`, `WeatherScreen.kt`, `SettingsScreen.kt`, `MealsTodayState.kt` y `TaskDue.kt`. Propón 2 distribuciones de Hoy en 1920×1200 (bocetos en ASCII o capturas del emulador con datos de demo) que:
   - den el bloque principal a la agenda de hoy (eventos, rutinas, comidas) y reduzcan reloj y tiempo (U2);
   - den sitio propio a «Hoy se come» con todas las franjas del día (N5);
   - metan el aviso de vencimiento sin añadir una fila que quite alto a todo (N3);
   - sustituyan el mes de puntos por «próximos 3 días» (C2) o justifiquen mantenerlo.
   Para cada una, di qué se mueve o desaparece. **Para y espera la elección de Damian.**
3. Tras la elección, implementa:
   - Tamaños: mínimo ~24 px en lo que se lee de pie (horas, títulos de rutina, chips de persona); lo pasado atenuado sin bajar de un contraste legible (U3).
   - Aviso de vencimiento (`TaskDue`): incluir vencidas («Vencida hace 2 h», en el color de acento) hasta que se completen (N1); fecha relativa «Hoy 19:00», «Mañana 19:00», «vie 4 dic 19:00» y solo con menos de 48 h (N2); «Cerrar» con área táctil de 64 px y cierre guardado en `Store` por tarea + `due_at`, para que no vuelva tras reiniciar (N4).
   - Calendario: rutinas que se repiten todos los días de la semana resumidas en una línea («+3 rutinas diarias») en vez de listadas (U5).
   - Barra lateral: etiqueta corta bajo cada icono; «sincronizar» pasa a Ajustes y en la barra queda el estado (U6, C4, Q5); el reloj pequeño de la barra se oculta en Hoy (Q3).
   - «Actualizado hace X» cuando los datos tengan más de 15 min o falle la red (U7).
   - Tareas: personas de cada tarea con sus colores y orden fijo por prioridad dentro de cada lista; quita la barra de chips de orden y filtro (U8, C5). Conserva el filtro guardado en `Store` solo si se usa para el filtro por persona del paso 4; si no, bórralo.
   - Ajustes: Wi-Fi, Ajustes de Android, Cerrar sesión y Apagar tras una pulsación larga de 2 s, con texto que lo explique (U9).
   - Tiempo: quita la segunda página (días 8–14) y pide solo 8 días a Open-Meteo (Q1). Si la distribución elegida saca Tiempo de la barra (Q2), su detalle se abre tocando la tarjeta del tiempo en Hoy.

## Verificación
Tests JUnit4 de `TaskDue` (vencida, < 48 h, > 48 h, cierre persistido), del resumen de rutinas diarias y de «actualizado hace». Capturas nuevas en el emulador con `scripts/demo.sh app` para `docs/images/` (today, calendar, tasks, settings) y README actualizado. Mide en el emulador que no sube el uso de CPU en reposo.

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
La propuesta del paso 2 primero; después hash, tests, capturas y desviaciones.
