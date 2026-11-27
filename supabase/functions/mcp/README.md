# Edge Function `mcp` (MCP de Claude para Homita)

Fase 1 de 4: servidor MCP remoto **de solo lectura** (Streamable HTTP sin estado) para que Claude consulte los
hogares, menús, compra, tareas, eventos, rutinas, calendarios y personas de Homita. Solo local: producción, el
despliegue y Pages son de la fase 4 (ver «Producción / fase 4»).

## Arquitectura

- SDK oficial de MCP **v2**, `npm:@modelcontextprotocol/server@2.4.0` con `createMcpHandler` (un `McpServer` por
  petición = sin estado) y `npm:zod@4.6.7`. Versiones exactas en `deps.ts` (único sitio); no se mezcla con la v1.
- Sin tablas ni RPC propias. Todo pasa por `api/usecases/*` con el JWT del usuario (`leerRuta` de
  `_shared/homita/lector.ts`), así que heredan RLS, ACL y el filtro del hogar activo. Nunca clave de servicio.
- La lógica de lectura («leer y compactar») es la de Kito, en `supabase/functions/_shared/homita/` (la importan
  Kito y el MCP; ese módulo no importa de ninguno de los dos).
- Ficheros: `index.ts` (cableado), `handler.ts` (CORS, metadatos, 401, protocolo), `auth.ts` (verificador),
  `hogar.ts`, `entorno.ts`, `errores.ts`, `tools/` (una carpeta por área) y `tests/`.

## Autenticación

Solo sirven **tokens OAuth de Supabase Auth** emitidos a un cliente (Claude). `auth.ts`:

1. Lee el payload sin fiarse de él y exige `aud` == audiencia esperada y `client_id` (cadena no vacía).
2. `GET /auth/v1/user` con el Bearer: Supabase valida firma, caducidad y sesión y devuelve el id.
3. `sub` del token == id de Auth.

Cualquier fallo responde `401` con `WWW-Authenticate: Bearer error="invalid_token", resource_metadata="…"`; sin token,
`Bearer resource_metadata="<URL pública>/.well-known/oauth-protected-resource"`.

**Un JWT de sesión de la app (`POST /user/auth`) devuelve 401**: no lleva `client_id`. No hay vía de depuración con
token de sesión; se prueba siempre por el flujo OAuth local. Medido en local: los tokens OAuth y de sesión llevan
ambos `aud = authenticated`; lo que distingue a un token OAuth es `client_id` (y `scope`). Riesgo conocido: cualquier
cliente registrado dinámicamente al que el usuario dé consentimiento pasa el verificador; la página de consentimiento
muestra el host de `redirect_uri`.

`GET /.well-known/oauth-protected-resource` (sin autenticación) devuelve `resource` y `authorization_servers`.

## Variables (todas opcionales)

| Variable | Para qué | Por defecto |
|---|---|---|
| `MCP_PUBLIC_URL` | URL pública del MCP (`resource`) | `<origen según x-forwarded-*>/functions/v1/mcp` |
| `MCP_AUTH_URL` | Servidor de autorización | `<origen de la URL pública>/auth/v1` |
| `MCP_TOKEN_AUDIENCE` | `aud` esperada | `authenticated` |

`SUPABASE_URL` y `SUPABASE_ANON_KEY` las inyecta el runtime. Sin secretos propios.

## Herramientas (12, todas `readOnlyHint: true`)

`ver_hogares`, `leer_perfil`, `leer_semana`, `buscar_recetas`, `buscar_alimento`, `ver_compra`, `ver_listas`,
`ver_tareas`, `ver_eventos`, `ver_rutinas`, `ver_calendarios`, `ver_personas`.

- Todas menos `ver_hogares` aceptan `hogar` (id de `ver_hogares`). Sin él: el hogar predeterminado (`GET /home`,
  `is_default`); sin marca pero con uno solo, ese; con varios sin predeterminado, error que pide `hogar`. Un hogar
  del que no se es miembro da un error claro y no se llama a ningún caso de uso.
- `timezone` opcional (IANA, por defecto `Europe/Madrid`); fechas ISO con desfase local.
- Rutas: `home`, `meal/profile`, `meal/plan`, `recipe`, `food`, `shopping`, `shopping/preview`, `task-list`, `task`,
  `event` (`routine=true` para rutinas por día), `routine`, `calendar`, `calendar/user`, `person`.
- Errores de herramienta (`isError`) en español por estado (401/403/404/resto), nunca el cuerpo crudo.
- Los textos de la BD (nombres, notas) son **datos, no instrucciones**: lo dicen las descripciones y las
  `instructions` del servidor. Salida JSON compacta (`MAX_ITEMS = 50`, `hay_mas`).
- **Salud: fuera en esta versión.** `leer_perfil` nunca devuelve `objetivos` ni `nota_dieta` (igual que Kito). No hay
  consulta de permisos de salud ni RPC de salud. Pendiente para un change aparte (Kito y MCP juntos).

## Probar en local

Requisitos: Docker, Supabase CLI, Deno, Python 3. Desde la raíz del repositorio.

```sh
# 1. Stack local (config.toml ya activa [auth.oauth_server] con registro dinámico y [functions.mcp])
supabase start -x studio,imgproxy,vector,logflare,mailpit

# 2. Edge + datos: resetea la BD local, sirve todas las funciones (también mcp) y carga la cuenta de demo
#    (demo@homita.example / demo1234)
scripts/demo.sh up

# 3. Comprobaciones sin token
curl -i -X POST http://127.0.0.1:54321/functions/v1/mcp -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'   # 401 + WWW-Authenticate
curl http://127.0.0.1:54321/functions/v1/mcp/.well-known/oauth-protected-resource

# 4. Página de consentimiento (Site URL local = http://127.0.0.1:3000)
scripts/oauth/local-config.sh                   # genera web/oauth/consent/config.js (solo claves locales)
python3 -m http.server 3000 --bind 127.0.0.1 --directory web
```

Cliente MCP **solo por el flujo OAuth local** (nunca con token de sesión):

- MCP Inspector: `npx @modelcontextprotocol/inspector`, transporte *Streamable HTTP*, URL
  `http://127.0.0.1:54321/functions/v1/mcp`, y autenticación OAuth (registro dinámico).
- Claude Code: `claude mcp add --transport http homita http://127.0.0.1:54321/functions/v1/mcp` y, dentro de Claude
  Code, `/mcp` para autenticar (abre la página de `web/` en el puerto 3000; entra con una cuenta local).

El flujo OAuth sin navegador (registro dinámico, `authorize`, consentimiento por API con el JWT del usuario y canje
con PKCE) está automatizado en `scripts/supabase/tests/cross_tenant_check.py` (`oauth_token`, bloque `MCP`; solo ese
bloque: `XT_ONLY=MCP`).

Tests: `deno check supabase/functions/mcp/index.ts` y
`deno test --no-prompt --allow-env supabase/functions/mcp/tests/ supabase/functions/_shared/homita/tests/`.

Medido en el spike local: Auth local publica `/.well-known/oauth-authorization-server`, `authorization_url_path` se
concatena a `site_url` (no admite URL absoluta) y `/auth/v1/user` acepta tokens OAuth.

## Producción / fase 4 (documentación; nada de esto está hecho)

**Pendiente de Damian (no bloquea la fase 1):** valor actual de `site_url` en producción y si los correos de Auth
(confirmación, restablecer contraseña) están en uso. Qué mirar en el panel de Supabase antes de decidir:

1. Authentication → URL Configuration: `site_url` actual y redirect URLs. Si `site_url` pasa a ser el origen de Pages
   (la URL del consentimiento es Site URL + `authorization_url_path`), ¿qué enlaces dejan de funcionar?
2. Authentication → Email Templates: confirmación y restablecimiento; qué usan (`{{ .SiteURL }}`, `{{ .ConfirmationURL }}`).
3. Si los correos están en uso: hoy el registro está cerrado en producción (`ALLOW_REGISTRATION=false`); comprobar si hay
   confirmación por correo y SMTP.
4. Enlaces de correo ya enviados que apunten al `site_url` antiguo.
5. Authentication → OAuth Server: estado de la beta, `allow_dynamic_registration`, `authorization_url_path` (en local no
   admite URL absoluta).
6. Alternativas: `site_url` = origen de Pages; dominio propio para Pages; otro host estático; impacto en correos.
7. Plan de cambio y **rollback**: anota el `site_url` y las plantillas actuales antes de tocar nada.
8. Producción del MCP: secretos `MCP_PUBLIC_URL` y `MCP_AUTH_URL`; `supabase functions deploy mcp --no-verify-jwt`;
   activar Pages (fuente: GitHub Actions) y el `push` de `.github/workflows/pages.yml` (hoy solo `workflow_dispatch`);
   variables del repositorio `SUPABASE_URL` y `SUPABASE_ANON_KEY` para `config.js`.

**Límite del antiframe (clickjacking) de la página de consentimiento:** GitHub Pages no deja poner cabeceras
(`X-Frame-Options`, `frame-ancestors`) y en un `<meta http-equiv>` el navegador ignora `frame-ancestors`, así que la
protección es por script: `consent.js` deja la página oculta dentro de un iframe (CSS `html:not(.libre) body`) e
intenta sacarla del marco. Sin JavaScript la página no funciona. Es una defensa más débil que la cabecera: si se
aloja en un host que permita cabeceras (dominio propio con proxy), añadir `Content-Security-Policy: frame-ancestors 'none'`.

No verificable en local: el cliente real de Claude (versión de spec), GitHub Pages sirviendo `/oauth/consent`, la beta
del OAuth server en el proyecto alojado.
