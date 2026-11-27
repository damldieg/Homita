# Acelerar el CI de Homita y que los agentes corran solo lo afectado

Informe con cifras y decisiones: https://claude.ai/artifact/C7vBSt2gXA9dzzJdbN9jWB

1. En el Mac, `cd` al repo Homita y `git fetch`.
2. Abrí dorch-claude y pasale `prompts/01-ci-rapido.md` junto con `brief.md`.
3. Cuando termine, revisá el informe. Para push y PR, agregá `authorized: push pr gh` al `status.md` del change.
4. Con la 01 en master, antes de lanzar la 02 corré vos (solo lectura, desde tu terminal):
   `supabase migration list --linked` y anotá la última migración que figura como aplicada en remoto.
   Ese número va en el hueco `PROD_HEAD` del prompt 02.
5. Lanzá `prompts/02-ci-affected.md` igual que la 01.

Orden: 01 ci-rapido (solo workflow y flags, ~12 → 5–6 min por PR de backend) → 02 ci-affected (ci.sh modular, `--affected`, ~3–4 min por PR; agente local entre 15 s y 3 min).
La fase 3 (jobs en paralelo, CI de Android/iOS) queda para después, si hace falta.
