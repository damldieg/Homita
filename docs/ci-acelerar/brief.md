# Brief: acelerar el CI y tests por cambio

## Problema (medido 2026-11-27, runs 79 y 80 de edge-tests)
- `edge-tests` tarda ~12 min en todos los PRs, toquen backend o no (14 de los últimos 30 no tocaban backend).
- `cross_tenant_check.py` ~7,5 min: bucles de carreras (T-DL 10 pares × 20 fijo en el código, TDL-A12 15 × `A12_ITERS=20`, F1 e INV con 10). El número de casos (379) no depende de las iteraciones.
- Idas y vueltas de rollback 0035–0050 en orden LIFO con `contract_check.py` completo 10 veces (~17 s cada una): ~3 min.
- `supabase start` 42 s; el paso `postgresql-client-17` (10–18 s) no se usa (los tests van por `docker exec … psql`); las 50 migraciones se aplican dos veces (start y `db reset` de `demo.sh up`, ~11 s).
- `ci.sh` (803 líneas) se tocó en 34 commits en dos semanas y genera conflictos de merge.
- En local, cada agente corre `ci.sh` entero aunque toque un solo test de Deno.

## Decisiones de Damian (2026-11-27: «lo que recomiendes»)
1. Gate que siempre reporta un check, sirva o no `edge-tests` como check requerido: el job pesado cambia de nombre y un job resumen conserva el nombre `edge-tests`.
2. En PR, estrés reducido (3 iteraciones por bucle). Completo cada noche y en PRs con la etiqueta `ci-full`.
3. Nightly a las 03:00 de España: cron `0 2 * * *` (UTC; en verano cae a las 04:00, aceptable).
4. `PROD_HEAD` = última migración aplicada en producción; la consulta Damian a mano (`supabase migration list --linked`). Los agentes no consultan producción.
5. Un único comando para los agentes, `scripts/test-affected.sh`, que cubre Supabase, iOS (`swift test` y, si cambia `ControlApp`, `xcodebuild` Debug/Release) y Android (Gradle) según lo tocado.

## Fuera de alcance
Jobs en paralelo, CI de Android/iOS en Actions, caché de imágenes Docker (no compensa: el pull tarda ~20 s).

## Criterio de aceptación global
- PR sin backend: check `edge-tests` verde en <1 min.
- PR de backend: ~5–6 min tras la 01, ~3–4 min tras la 02.
- `--full` sigue dando exactamente los mismos ids `ok …` y conteos que hoy (contract 595/595, cross_tenant 379/379).
