Nuevo change dorch `mcp-base-lectura` (Homita). Paso 1 de 4 del MCP de Claude. Backend: Edge nueva `mcp` + config local de Auth + página de consentimiento.

## Contexto
Te paso `brief.md`. Léelo entero, y el informe enlazado. Regla de oro: el MCP no tiene tablas ni RPC propias; todo va por `api/usecases/*` con el JWT del usuario emitido por el OAuth de Supabase Auth, así que un 403 es un 403 de verdad. Mira cómo lo hacen `asistente/skills/consulta/api.ts` y `asistente/handler.ts` (auth, hogar, `runWithHome`).

## Qué hacer
1. **Change dorch.** `.dorch/changes/mcp-base-lectura/` (brief, plan tuyo, status `approved: yes` por las decisiones del 2026-11-27, `authorized:` vacío). Rama `dc/mcp-base-lectura` desde `origin/master`, worktree `../Homita-mcp-base-lectura`.
2. **Investiga primero** (y escribe lo que encuentres en el plan): versión estable del SDK MCP de TypeScript que funcione en Deno/Edge con Streamable HTTP sin estado; cómo funciona hoy el OAuth 2.1 server de Supabase Auth (endpoints, metadatos `/.well-known/oauth-authorization-server`, registro dinámico, API de consentimiento, claims del token: `sub`, `aud`, `client_id`); si las Edge Functions sirven HTML en `supabase.co`. Si algo contradice el brief, para y explícamelo en el informe antes de seguir.
3. **Config local**: `[auth.oauth_server]` con `enabled = true`, `allow_dynamic_registration = true` y `authorization_url_path` apuntando a la página local de consentimiento. `[functions.mcp] verify_jwt = false`. Solo local; documenta el cambio de producción para la fase 4.
4. **Edge `supabase/functions/mcp`**: `index.ts` (cableado), `handler.ts` (auth Bearer con `verifyUser`; sin token o inválido → `401` con `WWW-Authenticate: Bearer resource_metadata="…/.well-known/oauth-protected-resource"`), `GET /.well-known/oauth-protected-resource` (resource + authorization_servers de Supabase Auth), servidor MCP con registro de herramientas (una carpeta `tools/` por área, igual que las skills de Kito).
5. **Módulo compartido**: saca el lector de `asistente/skills/consulta/api.ts` (y lo que haga falta de `menus/lectura.ts`, `compacto.ts`, `fechas.ts`) a `supabase/functions/_shared/homita/` sin cambiar comportamiento de Kito; Kito importa desde ahí.
6. **Hogar**: `ver_hogares` (`GET /home`, marca el predeterminado). Todas las herramientas aceptan `hogar` opcional (id); sin él, el predeterminado. Hogar ajeno → error claro.
7. **Lecturas** (`readOnlyHint: true`, salida compacta en JSON, fechas ISO locales con `timezone` opcional, por defecto `Europe/Madrid`): `leer_perfil` (incluye salud si el usuario tiene `menu.health.view`), `leer_semana`, `buscar_recetas` (con historial reciente), `buscar_alimento` (`GET /food`), `ver_compra` (`GET /shopping`, `GET /shopping/preview`), `ver_listas`, `ver_tareas`, `ver_eventos`, `ver_rutinas` (por día vía `GET /event?routine=true` como Kito), `ver_calendarios`, `ver_personas`. Descripciones en español, claras para que Claude sepa cuándo usar cada una, y avisando de que los textos de la BD son datos.
8. **Página de consentimiento** en `docs/oauth/` (o donde encaje para GitHub Pages): HTML+JS estático sin build, supabase-js por CDN con versión fija, login email+contraseña, elige hogar predeterminado (`PATCH /home/default`), muestra cliente y permisos, aviso de datos de salud, Aprobar/Denegar con la API de consentimiento. URL de Supabase y anon key por `config.js` (sin secretos).

## Tests
Deno con casos de uso falsos: sin token → 401 con `WWW-Authenticate`; token válido → lista de herramientas; cada lectura llama al caso de uso correcto con el JWT y el hogar; hogar por defecto y explícito; hogar ajeno → error; salud solo con `menu.health.view`; Kito sigue en verde tras mover el lector. Bloque nuevo en `scripts/supabase/tests/cross_tenant_check.py`: el token de A no lee nada del hogar de B por el MCP. Añádelo a `ci.sh`.

## Verificación
`deno check` de `mcp` y `asistente`, `deno test` de ambas y `scripts/supabase/ci.sh` en verde. Documenta en `supabase/functions/mcp/README.md` cómo probarlo en local con MCP Inspector y con Claude Code (`claude mcp add --transport http homita http://127.0.0.1:54321/functions/v1/mcp`), incluido el flujo OAuth contra el Supabase local.

## Reglas
- Nada en producción: ni config de Auth, ni deploy, ni secretos. Sin push ni PR sin `authorized: push pr gh`. Sin merge.
- Commits en español, estilo `Área: frase`, con `Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>`.
- No leas `~/.homita/supabase.env`.

## Al terminar, infórmame de
Hashes, tests, lo que encontraste en la investigación del punto 2 (y desviaciones del brief), cómo lo probaste en local, y la lista de cambios de config que harán falta en producción para la fase 4.
