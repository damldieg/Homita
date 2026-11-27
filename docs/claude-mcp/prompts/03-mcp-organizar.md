Nuevo change dorch `mcp-organizar` (Homita). Paso 3 de 4 del MCP de Claude. Requiere `mcp-base-lectura` en master (puede ir en paralelo a `mcp-menus-escritura`).

## Contexto
Te paso `brief.md`. Lee `asistente/skills/organizar/` entero (herramientas, `acciones.ts`, `errores.ts`, `uuid.ts`, `tiempo.ts`) y su sección del README de `asistente`: las reglas de campos indispensables, ediciones que rellenan lo que no cambia, calendarios («de quién es» = con quién se comparte) y errores traducidos ya están resueltas para Kito.

## Qué hacer
1. **Change dorch.** `.dorch/changes/mcp-organizar/` (status `approved: yes`, `authorized:` vacío). Rama `dc/mcp-organizar` desde `origin/master`, worktree `../Homita-mcp-organizar`.
2. **Módulo compartido**: mueve `acciones.ts` y la lógica de las herramientas de `organizar` a `_shared/homita/` para que Kito y el MCP ejecuten exactamente las mismas operaciones. Kito sigue igual (tarjeta de confirmación HMAC, `/asistente/confirmar`); sus tests en verde.
3. **Herramientas MCP**: listas (`crear_lista`, `editar_lista`, `borrar_lista`), tareas (`crear_tarea`, `editar_tarea`, `completar_tarea` con desmarcar, `borrar_tarea`), eventos (`crear_evento`, `editar_evento`, `borrar_evento`), rutinas (`crear_rutina`, `editar_rutina`, `borrar_rutina`), calendarios (`crear_calendario`, `editar_calendario`, `compartir_calendario`, `borrar_calendario`). Mismos indispensables como `required`; falta algo → `{falta:[…]}` sin llamar al api; nombres → ids con las lecturas, y si hay varios, devolver opciones.
4. **Confirmación en el MCP**: no hay tarjeta HMAC. Borrar lleva `destructiveHint: true` (Claude pide aprobación) y la herramienta exige `confirmado: true`; sin él devuelve qué se borraría («la lista Pruebas y sus 2 tareas pendientes») sin ejecutar, para que Claude lo diga y pregunte. Crear y editar se ejecutan con `destructiveHint: false`. Varias escrituras en una petición = varias llamadas (Claude las encadena).
5. **Idempotencia**: tareas y listas con `client_request_id` derivado de los argumentos (no hay `tool_use.id` aquí: usa un hash estable de usuario + hogar + argumentos + minuto). Documenta que eventos, rutinas y calendarios no tienen idempotencia en el api.
6. Fuera: alarmas (`/event/alarm`, `/routine/alarm`), administración del hogar, invitaciones y pantallas. Las lecturas ya existen desde el paso 1.

## Tests
Deno con escritor falso: cada herramienta llama al caso de uso correcto con el JWT; faltan indispensables; ambigüedad de nombre; edición rellena campos; 403/404/400 traducidos; borrar sin `confirmado` no ejecuta y describe, con `confirmado` ejecuta; reintento de tarea/lista no duplica; compartir calendario solo con miembros con cuenta. Cross-tenant: A no crea, edita ni borra nada de B por el MCP. Kito en verde.

## Verificación
`deno check`, `deno test` de `mcp` y `asistente`, `scripts/supabase/ci.sh` en verde. En local con Claude Code: «creame una lista Viaje con 3 tareas», «marcá hecha Comprar pan», «creá un calendario Fútbol compartido con Lucía en solo lectura», «borrá la lista Pruebas».

## Reglas
- Nada en producción. Sin push ni PR sin `authorized: push pr gh`. Sin merge.
- Commits en español, `Área: frase`, con `Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>`.
- No leas `~/.homita/supabase.env`.

## Al terminar, infórmame de
Hashes, tests, qué se movió al módulo compartido, la prueba en local y desviaciones del brief.
