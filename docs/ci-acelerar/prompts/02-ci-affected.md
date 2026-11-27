Nuevo change dorch `ci-affected` (Homita). Paso 2 de 2 para acelerar el CI. Requiere `ci-rapido` en master.

PROD_HEAD = ____  (Damian: la última migración aplicada en producción según `supabase migration list --linked`, que corrés vos. Si está vacío, pará y pedímelo; no lo consultes vos.)

## Contexto
Te paso `brief.md` y el informe de `ci-rapido`. Objetivo: que `ci.sh` corra solo lo que afecta al cambio, que las idas y vueltas de rollback de migraciones ya desplegadas salgan del PR y queden en el nightly, y que los agentes tengan un único comando de tests.

## Qué hacer
1. **Change dorch.** `.dorch/changes/ci-affected/` (status `approved: yes`, `authorized:` vacío). Rama `dc/ci-affected` desde `origin/master`, worktree `../Homita-ci-affected`.
2. **Línea base antes de tocar nada.** En master, `scripts/supabase/ci.sh` completo (perfil full). Guardá la lista ordenada de ids `ok …` de todos los logs de `.demo/ci/` y los conteos. Es la referencia de la equivalencia.
3. **`ci.sh` modular** sin cambiar ningún test:
   - `scripts/supabase/ci/lib.sh`: `step`, `run`, `expect_log`, `sql`, `sql_expanded` y el arranque del stack con sus guardas (API_URL local, imagen `postgres:17.*`).
   - `scripts/supabase/ci/suites/*.sh`, una suite por pieza: `deno-feedback`, `deno-asistente`, `deno-api`, `seeds`, `contract`, `cross-tenant` y una `mNNNN-<slug>.sh` por migración con sus checks SQL y tests Deno propios. Cada suite declara si necesita el stack y de qué suites depende.
   - Idas y vueltas: cada migración mayor que `PROD_HEAD` tiene la suya (rollback → check de rollback → reaplicar → checks otra vez), revirtiendo de la más nueva a la más vieja (LIFO). La cadena anidada actual de 0035–0050 pasa a la suite `rollbacks-legacy` y corre solo en `--full`, o si el diff toca alguno de sus rollbacks o checks.
   - `ci.sh` queda como orquestador: `--full` (todo, en el orden de hoy), `--affected [--base <ref>]` (por defecto `origin/master`), `--only <suite,…>`, `--list` (qué correría y por qué) y `--force`.
4. **Selección por rutas** en `scripts/supabase/ci/affected.sh`. Archivos: `git diff --name-only $(git merge-base <base> HEAD)` más cambios sin commitear y sin seguimiento. Mapa:
   - `supabase/functions/procesar-feedback/**` → `deno-feedback` (sin stack).
   - `supabase/functions/asistente/**` → `deno-asistente` (sin stack).
   - `supabase/functions/api/**` → `deno-api` + `contract` + `cross-tenant`.
   - `supabase/migrations/NNNN_*`, `scripts/supabase/rollback/rollback_NNNN*`, o un check de `scripts/supabase/tests/` de esa migración → `mNNNN` + su ida y vuelta + `contract` + `cross-tenant`.
   - `supabase/seed/**`, `scripts/menus/**` → `seeds` y los checks que dependen de ellos.
   - `ci.sh`, `scripts/supabase/ci/**`, `contract_check.py`, `fixture_two_families.py`, `supabase/config.toml`, `scripts/demo.sh`, `scripts/demo/**`, `.github/workflows/**` → `--full`.
   - Un archivo bajo `supabase/` o `scripts/supabase/` que no esté en el mapa → `--full` y aviso, nunca «nada».
5. **Último verde.** Al terminar en verde, `ci.sh` guarda en `.demo/ci/last-pass` un hash de los ficheros que miró más las suites que corrió. Si se relanza con el mismo hash, imprime «sin cambios desde el último verde» y sale 0, salvo con `--force`.
6. **`scripts/test-affected.sh`**, el comando único para agentes: `scripts/supabase/ci.sh --affected` si hay cambios de backend; `swift test` en `apps/control-ios` si cambia `apps/control-ios/**`, más `xcodebuild build -scheme ControlApp` Debug y Release si cambian `ControlApp/`, `HomitaWidgets/` o el `.xcodeproj` (sin Xcode, lo dice y sigue); `./gradlew :app:testDebugUnitTest :app:lintDebug` en `apps/dashboard` o `apps/control` según cuál cambie. Al final, un resumen con qué corrió, cuánto tardó cada parte y qué se saltó.
7. **Workflow.** Perfil `pr`: `ci.sh --affected --base origin/${{ github.base_ref }}` (con la base disponible en el checkout). Perfil `full` (nightly, dispatch, etiqueta `ci-full`): `ci.sh --full`. El gate y el job resumen de `ci-rapido` no cambian.
8. **`supabase/PROD_HEAD`** con el número de arriba, y en `supabase/README.md` la regla: al desplegar una migración en producción, Damian sube `PROD_HEAD` en el mismo PR de despliegue o justo después.
9. **Reglas en `AGENTS.md`** (y nota para las plantillas de prompts de dorch): mientras iterás, `scripts/test-affected.sh`; si una suite falla, re-correr solo esa con `ci.sh --only`; `--full` solo si tocaste la infraestructura del CI o el orden de rollbacks; en el informe, qué suites corrieron. Una migración nueva añade su `suites/mNNNN-<slug>.sh` en vez de editar `ci.sh`.

## Verificación
- `ci.sh --full` en la rama: los mismos ids `ok …` y conteos que la línea base del paso 2 (diff vacío de las listas ordenadas). Duración anotada.
- `ci.sh --list` y `--affected` con cuatro diffs de prueba (en ramas descartables o con `--base` apuntando a commits viejos): solo un test de `asistente`; solo `0050_marcar_hecho.sql`; solo un `.swift`; solo un `.md`. Anotá qué suites eligió y cuánto tardó cada uno.
- Relanzar sin cambios: responde «sin cambios desde el último verde».
- `shellcheck` de todos los `.sh` nuevos, `actionlint`, `yamllint .github/workflows`.

## Reglas
- Nada en producción: no consultes ni apliques nada remoto, `PROD_HEAD` lo da Damian. Sin push ni PR sin `authorized: push pr gh`. Sin merge.
- Commits en español, `Área: frase`, con `Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>`.
- No leas `~/.homita/supabase.env`.

## Al terminar, infórmame de
Hashes, el diff de la equivalencia (vacío o qué difiere y por qué), las duraciones de `--full` y de los cuatro diffs de prueba, y desviaciones. Si hacés el PR (con autorización), cuánto tardó el run de GitHub.
