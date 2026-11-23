# Cómo lanzar el planificador con claude CLI + dorch-claude

1. En el Mac, `cd` al repo Homita y `git fetch`.
2. Para cada fase, en orden, abre dorch-claude y pásale:
   - el prompt de la fase (`prompts/0N-*.md`),
   - `brief.md`,
   - en la fase 1, además `perfil-hogar-campos.txt`.
3. Cuando dorch termine, revisa su informe. Para push y PR añade `authorized: push pr gh` al `status.md` del change.
4. No empieces una fase hasta que la anterior esté en master (la 4 puede ir en paralelo a la 3 si te corre prisa).

Orden: 01 perfil → 02 semana → 03 compra → 04 pantalla y widget → 05 Kito (requiere la fase 2 de Kito).
