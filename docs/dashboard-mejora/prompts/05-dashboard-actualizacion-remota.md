Change `dashboard-actualizacion-remota` (Homita). Paso 5 de 5 de la mejora del dashboard de pared: actualizar la app de las pantallas sin ADB.

## Contexto
Te paso `brief.md` de `docs/dashboard-mejora/`. Cubre A7. Requiere `dashboard-pantalla-hogar` en master (la caja «Diagnóstico» y la identidad de la pantalla). Hoy la app se instala y actualiza por ADB con `scripts/install.sh`; para entregar pantallas a otros hogares (piloto de 10–15 hogares, luego 20–30 tablets) hace falta actualizarlas a distancia. La app es Device Owner en modo quiosco, lo que permite instalar APK con `PackageInstaller` sin intervención.

## Qué hacer
1. Change `.dorch/changes/dashboard-actualizacion-remota/`, rama `dc/dashboard-actualizacion-remota`, worktree `../Homita-dashboard-actualizacion-remota`.
2. **Primero, propuesta sin código** en `plan.md`: dónde se publica la APK y su manifiesto (Releases de GitHub del repo, Supabase Storage u otro), cómo se firma y se verifica (SHA-256 del manifiesto + misma firma de la app), canales (estable / pruebas por pantalla), cuándo se instala (solo fuera del horario de pantalla) y cómo se vuelve atrás si la nueva versión no arranca. Ten en cuenta 1 GB de RAM, Wi-Fi de 2,4 GHz y el RTC sin hora hasta NTP. **Para y espera la elección de Damian.**
3. Tras la elección, implementa:
   - Android: comprobación diaria del manifiesto, descarga en segundo plano con reanudación, verificación de hash y firma, instalación con `PackageInstaller` como Device Owner fuera de horario, y versión, canal y resultado de la última comprobación en «Diagnóstico».
   - Informe al servidor de versión y última conexión de cada pantalla (para verlo en iOS, en «Pantallas»), si la opción elegida lo incluye.
   - Script o workflow para publicar una versión (build release, hash, manifiesto) sin secretos en el repo; la firma la hace Damian en su Mac.
   - Documenta en `docs/SETUP.md` cómo publicar, cómo poner una pantalla en el canal de pruebas y cómo volver a la versión anterior por ADB si todo falla.

## Verificación
Tests JUnit4 del manifiesto (versión nueva, igual, hash malo, firma distinta, dentro del horario), prueba en el emulador como Device Owner (`adb shell dpm set-device-owner …`) instalando una versión +1 servida en local, y `scripts/supabase/ci.sh` si tocas la Edge.

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
La propuesta del paso 2 primero; después hash, tests, cómo probaste la instalación y desviaciones.
