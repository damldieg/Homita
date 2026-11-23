# Cómo lanzar la mejora de Kito con claude CLI + dorch-claude

1. En el Mac, `cd` al repo Homita y `git fetch`.
2. Para cada paso, en orden, abre dorch-claude y pásale:
   - el prompt del paso (`prompts/0N-*.md`),
   - `brief.md` de esta carpeta,
   - en los pasos 5 y 6, además `/mnt/project-files/kito-asistente/dorch-change/plan.md` (plan de Kito del 2026-11-20; está también en `.dorch/changes/kito-asistente/plan.md` si lo conservas) (tabla de campos indispensables).
3. Cuando dorch termine, revisa su informe. Para push y PR añade `authorized: push pr gh` al `status.md` del change.
4. No empieces un paso hasta que los que necesita estén en master (ver la tabla «Orden» del brief).
   El 1 y el 2 pueden ir en paralelo; el 3 (voz) solo necesita el 2.

Orden: 01 calidad (backend) ∥ 02 chat iOS → 03 voz (dictado nativo) → 04 ayuda → 05 organizar (backend) → 06 organizar iOS.

Estos prompts sustituyen a los antiguos `02-calidad-consulta` y `03-voz` de la carpeta del proyecto (descartados).
