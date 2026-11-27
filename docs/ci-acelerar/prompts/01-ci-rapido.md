Nuevo change dorch `ci-rapido` (Homita). Paso 1 de 2 para acelerar el CI. Solo toca el workflow, `ci.sh`, `demo.sh` y `cross_tenant_check.py`. No cambia ningún test ni ningún conteo.

## Contexto
Te paso `brief.md` con las cifras medidas y las decisiones de Damian. Hoy `edge-tests` tarda ~12 min en todos los PRs; ~7,5 min son los bucles de carreras de `cross_tenant_check.py`.

## Qué hacer
1. **Change dorch.** `.dorch/changes/ci-rapido/` (status `approved: yes`, `authorized:` vacío). Rama `dc/ci-rapido` desde `origin/master`, worktree `../Homita-ci-rapido`.
2. **Gate por rutas** en `.github/workflows/edge-tests.yml`, sin acciones de terceros nuevas:
   - Job `changes`: `git diff --name-only` entre la base del PR y el HEAD (checkout con la profundidad justa o `git fetch` de la base). Salida `backend=true` si cambia algo de `supabase/**`, `scripts/supabase/**`, `scripts/menus/**`, `scripts/demo.sh`, `scripts/demo/**` o `.github/workflows/**`.
   - El job pesado pasa a llamarse `edge-suite` y corre solo si `backend == 'true'` o si el perfil es `full`.
   - Job resumen llamado exactamente `edge-tests` (`if: always()`, `needs: [changes, edge-suite]`): verde si `edge-suite` salió `success` o `skipped`, rojo en cualquier otro caso. Así, si `edge-tests` es check requerido, sigue funcionando.
3. **Perfiles.** Disparadores: `pull_request` (incluye `labeled` para reaccionar a la etiqueta), `schedule` con cron `0 2 * * *` y `workflow_dispatch`. Perfil `full` en schedule, dispatch o con la etiqueta `ci-full` en el PR; `pr` en el resto. Con `pr`: `A12_ITERS=3`, `INV_ITERS=3`, `F1_ITERS=3`, `TDL_ITERS=3`. Con `full`: los valores por defecto de hoy. Mantené `concurrency` con `cancel-in-progress` (en schedule usá un grupo propio para que no cancele PRs).
4. **`TDL_ITERS`** en `scripts/supabase/tests/cross_tenant_check.py`: el bucle T-DL fijo en 20 (`for i in range(20 if not XT_ONLY else 0)`, ~línea 1360) pasa a leer `TDL_ITERS` (por defecto 20). El texto del check que dice «200 iteraciones (10 pares × 20)» se calcula con la variable. Confirmá que `EXPECTED_CASES` (379) no cambia con 3 ni con 20 iteraciones.
5. **Quitar el paso `postgresql-client-17 (PGDG)`** del workflow y su comentario de cabecera. `ci.sh` ya solo imprime `psql --version` si existe.
6. **Sin doble aplicación de migraciones.** Si `ci.sh` acaba de hacer `supabase start` en esta ejecución, llama a `demo.sh up` con `DEMO_SKIP_RESET=1`. `demo.sh` respeta esa variable y se salta solo `supabase db reset --local` (el resto, Edge y seed, igual). En local, con el stack ya levantado, el reset se sigue haciendo como hoy.
7. **Docs.** Cabecera del workflow, `supabase/README.md` (sección del CI) y la línea de CI en `AGENTS.md`: perfiles, etiqueta `ci-full`, nightly y variables de iteraciones.

## Verificación
- `actionlint`, `yamllint .github/workflows`, `shellcheck scripts/supabase/ci.sh scripts/demo.sh`.
- `scripts/supabase/ci.sh` en local dos veces: con `A12_ITERS=3 INV_ITERS=3 F1_ITERS=3 TDL_ITERS=3` y sin variables. Las dos en verde con contract 595/595 y cross_tenant 379/379. Anotá la duración de cada una y la de `cross_tenant_check.py` sola.

## Reglas
- Nada en producción. Sin push ni PR sin `authorized: push pr gh`. Sin merge.
- Commits en español, `Área: frase`, con `Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>`.
- No leas `~/.homita/supabase.env`.

## Al terminar, infórmame de
Hashes, salidas de lint, las duraciones medidas (antes y después, `cross_tenant` por separado), y desviaciones. Si hacés el PR (con autorización), decime cuánto tardó el run de GitHub y si el job resumen `edge-tests` quedó verde. Recordame que, si quiero, puedo marcar `edge-tests` como check requerido en la protección de `master`.
