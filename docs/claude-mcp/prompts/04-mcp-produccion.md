Nuevo change dorch `mcp-produccion` (Homita). Paso 4 de 4 del MCP de Claude. Requiere los pasos 1–3 en master.

## Contexto
Te paso `brief.md` y los informes de los pasos 1–3 (sobre todo la lista de cambios de config de producción del paso 1). Este change NO despliega nada: deja todo listo para que Damian lo aplique a mano.

## Qué hacer
1. **Change dorch.** `.dorch/changes/mcp-produccion/` (status `approved: yes`, `authorized:` vacío). Rama `dc/mcp-produccion` desde `origin/master`, worktree `../Homita-mcp-produccion`.
2. **Runbook** `docs/mcp/DESPLIEGUE.md`, paso a paso para Damian: activar el OAuth server en el proyecto de producción (dashboard o `supabase config push`, lo que corresponda), `authorization_url_path`/URL de la página publicada, registro dinámico, `supabase functions deploy mcp --no-verify-jwt`, comprobación con `curl` del 401 y de los metadatos, alta del conector en claude.ai (Ajustes → Conectores → personalizado) y prueba de extremo a extremo. Rollback de cada paso (borrar la función, apagar el OAuth server, revocar clientes).
3. **GitHub Pages**: workflow o configuración para publicar la página de consentimiento desde el repo, con `config.js` de producción sin secretos (solo URL y anon key, que son públicas). Documenta qué tiene que activar Damian en los ajustes del repo.
4. **iOS, Ajustes → «Claude»**: lista de conexiones OAuth del usuario (cliente, fecha) con «Revocar», sobre la API de Supabase Auth para grants del usuario; si esa API no existe del lado del usuario, explica la alternativa (ruta nueva en `api` o revocar desde claude.ai) y para antes de implementarla. `swift test` en `apps/control-ios` (base actual, 0 fallos); Xcode lo corre Damian.
5. **README** de `mcp` y `docs/README.md` actualizados: qué es, herramientas, seguridad (alcance, aprobación, `expected_revision`, salud) y límites conocidos.

## Verificación
`scripts/supabase/ci.sh` en verde, `swift test` en verde, y el runbook probado contra el Supabase local de principio a fin (salvo los pasos que solo existen en producción, marcados como tal).

## Reglas
- Nada en producción: ni config, ni deploy, ni Pages activado. Sin push ni PR sin `authorized: push pr gh`. Sin merge.
- Commits en español, `Área: frase`, con `Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>`.
- No leas `~/.homita/supabase.env`.

## Al terminar, infórmame de
Hashes, tests, el runbook (enlace) con los comandos exactos que tengo que ejecutar y en qué orden, y desviaciones.
