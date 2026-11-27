Nuevo change dorch `mcp-menus-escritura` (Homita). Paso 2 de 4 del MCP de Claude. Requiere `mcp-base-lectura` en master.

## Contexto
Te paso `brief.md`. Lee también `docs/planificador-comidas/kito-menus.md` y `asistente/skills/menus/` enteros: el ciclo borrador → cambios → aceptar ya existe para Kito. Aquí quien planifica es Claude (el cliente), así que el MCP no llama a ningún modelo: guarda, comprueba y devuelve.

## Qué hacer
1. **Change dorch.** `.dorch/changes/mcp-menus-escritura/` (status `approved: yes`, `authorized:` vacío). Rama `dc/mcp-menus-escritura` desde `origin/master`, worktree `../Homita-mcp-menus-escritura`.
2. **Módulo compartido**: saca a `_shared/homita/` lo reutilizable de `skills/menus` (`resolverRango`, forma compacta del plan, `client_request_id` derivado de contenido + revisión, comprobación de casillas libres) y del escritor de `skills/organizar/api.ts` (lista blanca de rutas). Kito sin cambios de comportamiento; su lista blanca sigue SIN `meal/plan/accept`. El MCP tiene su propia lista blanca, que sí incluye accept.
3. **Herramientas**:
   - `guardar_borrador` `{rango:{desde:{fecha,franja}, hasta:{fecha,franja}}, casillas:[{fecha, franja, tipo: receta|texto|sobras|fuera, receta_id?, titulo?, raciones?, personas?}]}`: rellena solo casillas libres del rango (`PATCH /meal/plan/items`, `origin = 'kito'`, `expected_revision`, `client_request_id`), un plan por semana si cruza dos, salta semanas aceptadas o hechas por la persona con aviso; después `GET /meal/plan/check`. Devuelve por semana `{plan_id, revision, casillas, conflictos, enlace_app?}`.
   - `cambiar_casillas` `{plan_id, expected_revision, cambios:[…]}`: cambia solo esas casillas; respeta `locked`; 409 → devuelve el plan vigente para que Claude lo vuelva a mostrar.
   - `aceptar_menu` `{plan_id, expected_revision}` → `POST /meal/plan/accept`; `destructiveHint: true`; devuelve el resumen de la Compra generada. Con conflictos abiertos, no acepta y lo dice.
   - `guardar_receta` `{nombre, raciones, minutos, franjas?, pasos[], ingredientes:[{alimento_id?, texto?, cantidad?, unidad?}]}` → `POST /recipe/create`, idempotente; pasos e ingredientes obligatorios.
   - `crear_alimento` → `POST /food/create` (catálogo del hogar, con sección y alérgenos si se conocen).
   - `apuntar_compra`, `marcar_comprado` (`PATCH /shopping/item/check`, también desmarcar), `apuntar_preferencia` (C1/C2/C4, con `confirmado_por_usuario`).
4. **Descripciones para Claude** (son el «prompt» del MCP, cuídalas): recetario + historial primero; completar con platos de fuera (conocimiento propio o búsqueda web) dándolos de alta con `guardar_receta` + ingredientes ANTES de `guardar_borrador`, para que salga la Compra; `texto` solo para cosas sueltas; enseñar el borrador como tabla día × franja; nunca `aceptar_menu` sin un «sí» explícito del usuario en esa conversación.

## Tests
Deno con mundo falso (reusa `tests/menus_util.ts` si encaja): rango que cruza semanas; no pisa casillas ocupadas, `locked` ni aceptadas; reintento idempotente; conflictos devueltos; 409 por revisión; accept con revisión correcta, vieja y con conflictos; receta sin pasos o sin ingredientes → error; alimento nuevo; Kito sigue sin poder aceptar (test explícito). Cross-tenant: A no escribe plan, receta ni compra de B por el MCP.

## Verificación
`deno check`, `deno test` de `mcp` y `asistente`, `scripts/supabase/ci.sh` en verde. En local con Claude Code: «haceme el menú del lunes al domingo, el jueves ceno fuera», cambiar una cena, aceptar, y ver la Compra en la app.

## Reglas
- Nada en producción. Sin push ni PR sin `authorized: push pr gh`. Sin merge.
- Commits en español, `Área: frase`, con `Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>`.
- No leas `~/.homita/supabase.env`.

## Al terminar, infórmame de
Hashes, tests, cómo quedó el módulo compartido, la prueba en local y desviaciones del brief.
