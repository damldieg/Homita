Change `menus-perfil-hogar` (Homita). Fase 1 de 5 del planificador de comidas: perfil de hogar y franjas.

## Contexto
Te paso `brief.md` (decisiones de Damian del 2026-11-22 y modelo) y `perfil-hogar-campos.txt` (los ~40 campos del perfil en 8 bloques, A–H). Léelos enteros. Esta fase solo guarda el perfil; el menú llega en la fase 2.

## Qué hacer
1. Crea el change: `.dorch/changes/menus-perfil-hogar/` con `brief.md` (el que te paso), un `plan.md` tuyo para esta fase y `status.md` con `approved: yes` (decisiones del 2026-11-22; los supuestos del brief los confirma Damian en este paso) y `authorized:` vacío. Rama `dc/menus-perfil-hogar` desde `origin/master`, worktree `../Homita-menus-perfil-hogar`.
2. Migración:
   - `meal_profile` (1 por hogar): D1, D3, E1–E6, F1–F7, G1–G6, H2. Restricciones duras en columnas tipadas con check; preferencias en `preferences jsonb` con `schema_version`.
   - `meal_profile_member` (por `home_member`, nunca `kind = 'pet'`): A2, A3, B1 + B2 (gravedad por alérgeno), B5, B6, C1–C4. **Sin B3/B4** en el piloto (dejar hueco documentado).
   - `meal_schedule` (miembro × día × franja: home/out/skip/lunchbox), por defecto todos en casa.
   - `meal_slot_setting` (slot `breakfast|midmorning|lunch|snack|dinner`, enabled, time). Por defecto comida 14:00 y cena 21:00 activas.
   - Permisos `menu.view`, `menu.plan.manage`, `menu.shopping.edit`, `menu.profile.edit`, `menu.health.view` (dominio `menu`) en `permission` + `member_kind_default` según la tabla del brief.
   - **Backfill** de `membership_permission`: los permisos están materializados por membresía, así que hay que dar los códigos nuevos a las membresías no admin que ya existen según el `kind` de su `home_member`. Solo insertar los códigos `menu.*` que falten; **no** llamar a `fn_seed_kind_permissions`, que reemplaza el snapshot y borraría permisos personalizados. Los admin ya lo tienen todo por `fn_has_permission`.
   - Actualiza los checks que cuentan el catálogo: `permisos_kind_check.sql` espera hoy 23 permisos y 37 defaults exactos (P1), y revisa `permisos_matriz_check.sql` y `permisos_config_check.sql`.
   - RPC: `get_meal_profile()` (hogar activo) y escrituras `update_meal_profile`, `update_meal_profile_member`, `set_meal_schedule`, `set_meal_slot_settings`, con `fn_has_permission` y `audit_log`. Excepción: cada persona con cuenta puede editar su propio bloque C sin `menu.profile.edit`.
3. Edge `api`: casos de uso en `usecases/meals.ts` y rutas (p. ej. `GET /meal/profile`, `PATCH /meal/profile`, `PATCH /meal/profile/member`, `PUT /meal/schedule`, `PUT /meal/slots`). Kito los reutilizará en proceso, así que nada de lógica en el handler.
4. iOS: etiqueta del dominio `menu` → «Menú» en `HomeAdminAccess.domainLabel` (pantalla de permisos de Hogar). Ajustes → «Perfil de hogar», como sección más junto a `InicioSettingsView` y `NotificationSettingsView` en `ProfileView`. Primer paso con las 7 preguntas de arranque (A1 son casillas de los miembros del hogar), después el formulario completo por bloques, y la hora de cada franja. Cada pregunta opcional tiene «ahora no».

## Verificación
Check SQL con: RLS entre hogares, matriz de permisos por kind, excepción del bloque C, mascotas rechazadas, valores por defecto de franjas, rollback → reaplicar en verde. `scripts/supabase/ci.sh` completo.

## Reglas
- Nada en producción: no apliques migraciones ni despliegues la Edge. Sin push ni PR (status sin `authorized: push pr gh`). Nunca merge.
- Antes de empezar, `git fetch` y comprueba el último número de migración (el 2026-11-23 master llega a 0042) y usa el siguiente libre en `supabase/migrations/`, rollback en `scripts/supabase/rollback/` y check SQL en `scripts/supabase/tests/` añadido a `scripts/supabase/ci.sh` (mismo estilo que `client_request_check.sql`).
- Rutas nuevas de `api` aditivas al contrato (D-008) y con el estilo de nombres que ya hay (`GET /recurso`, `GET /recurso/detail`, `POST /recurso/create`, `PATCH /recurso/update`, `DELETE /recurso/delete`), casos de uso en `usecases/`, tests Deno en `supabase/functions/api/tests/` y casos nuevos en `scripts/supabase/tests/cross_tenant_check.py` (B no lee ni escribe lo de A).
- Hogar de las RPC del menú y la compra: el de `X-Home-Id`; sin cabecera, la misma regla que `fn_home_for_root_create()` (hogar por defecto o único; si no, `Home header required`). El dashboard no manda cabecera. iOS: `swift test` en `apps/control-ios` (0 fallos) + `xcodebuild build -scheme ControlApp` Debug y Release.
- Commits en español, estilo `Área: frase`, con `Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>`.
- No leas `~/.homita/supabase.env` ni valores de env.

## Al terminar, infórmame de
Hash del commit, salida de los checks y de ci.sh, tests iOS, y cualquier desviación del plan.
