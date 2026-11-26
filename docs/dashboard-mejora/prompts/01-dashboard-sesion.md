Change `dashboard-sesion` (Homita). Paso 1 de 5 de la mejora del dashboard de pared: que la sesión no caduque cada semana (U1).

## Contexto
Te paso `brief.md` de `docs/dashboard-mejora/`. Hoy el dashboard guarda solo el JWT de Supabase (7 días) en `Store.token`; un 401 llama a `logout()` y la pared se queda en el login. `POST /user/auth` ya devuelve `refresh_token` (aditivo), pero el dashboard lo ignora. iOS refresca contra GoTrue directo (`AuthService.swift`), lo que necesita la URL de Supabase y la anon key; el dashboard solo conoce `homita.baseUrl` de la Edge `api`.

## Qué hacer
1. Change `.dorch/changes/dashboard-sesion/` (`brief.md` = el que te paso, `plan.md` tuyo, `status.md` con `approved: yes` y `authorized:` vacío). Rama `dc/dashboard-sesion` desde `origin/master`, worktree `../Homita-dashboard-sesion`.
2. Edge `api`: ruta aditiva `POST /user/refresh` `{refresh_token}` → `{token, refresh_token}` (mismo formato que `user/auth`), que llama a GoTrue con la configuración de la propia función. Errores: token inválido o revocado → 401 `{"error":"Invalid refresh token"}`. Así el dashboard no necesita la anon key. Si ves una forma mejor ya existente en el repo, propónla en el plan antes de implementarla.
3. Android:
   - `UserResponse` con `refresh_token`; `Store` guarda `refreshToken` (y lo borra en `logout`).
   - Refresco proactivo: al arrancar y en el bucle de `run()`, si al JWT le quedan menos de 24 h (lee `exp` del payload sin validar firma). Refresco reactivo: ante un 401, un solo intento de refresco y repetir la petición; solo si el refresco devuelve 401 se cierra la sesión.
   - Sin red o con error 5xx en el refresco: no cerrar sesión; seguir pintando la caché y reintentar en el siguiente ciclo.
   - Dos refrescos nunca en paralelo (un `Mutex`), igual que `CachedResource`.
   - Si al final hay que volver a entrar, mensaje claro en el login («La sesión de esta pantalla ha caducado») en vez del formulario sin más.
4. Docs: quita «re-login semanal» de `docs/ARCHITECTURE.md` y explica el refresco.

## Verificación
Tests JUnit4 de la decisión de refrescar (exp lejano, < 24 h, caducado, sin exp), del reintento único tras 401 y de que un error de red no cierra sesión. Tests Deno de `/user/refresh` (ok, token inválido, sin cuerpo) y `scripts/supabase/ci.sh`. Prueba manual en el emulador con la demo (`scripts/demo.sh app`) forzando un JWT caducado.

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
Hash del commit, salida de tests y ci.sh, cómo forzaste la caducidad en la prueba manual y cualquier desviación del plan.
