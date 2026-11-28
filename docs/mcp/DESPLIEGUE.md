# Despliegue del MCP de Claude en producción (runbook)

Guía para **aplicar a mano** en producción el MCP de Claude para Homita (fases 1-3 ya están en `master`). Este documento
no despliega nada por sí mismo: cada paso lo ejecuta Damian y **pide confirmación antes de ejecutarlo**.

## Convenciones

- **SOLO PRODUCCIÓN**: el paso toca (o lee) el proyecto alojado, GitHub o Claude. No se puede probar en local.
- **Probado en local**: el paso (o su equivalente) se ejecutó contra el stack local; ver «Prueba en local».
- **No verificable**: depende de pantallas de terceros (Supabase, GitHub, claude.ai) que pueden haber cambiado.
- Placeholders: `<PROJECT_REF>` (ref del proyecto Supabase), `<USUARIO>` (usuario de GitHub dueño del repo),
  `<URL>` = `https://<PROJECT_REF>.supabase.co`, `<ANON_KEY>` (clave pública anon). Nunca se pegan secretos
  (`service_role`, tokens de acceso) en este documento ni en git.
- Los comandos de producción de la CLI llevan el proyecto explícito y **no** usan `supabase link`. Se escriben con
  `--project-ref <PROJECT_REF>` (CLI v2); en la CLI v3 (la 3.1.0 instalada aquí) el flag es `--remote=<PROJECT_REF>`.
  Comprueba el tuyo con `supabase functions deploy --help` antes de ejecutar y sustituye el flag en todos los comandos.
- Prohibido en todo el runbook: `supabase config push` con `supabase/config.toml` (ver «Por qué no `config push`»),
  `supabase db push` y cualquier migración (el MCP no tiene ninguna).

## Resumen del orden

| # | Paso | Dónde | Marca |
|---|---|---|---|
| 0 | Prerrequisitos y decisiones | — | — |
| 1 | Anotar el estado actual de Auth (base del rollback) | Dashboard de Supabase | SOLO PRODUCCIÓN, no verificable |
| 2 | Decidir `site_url` y la caducidad del token | Decisión | — |
| 3 | Publicar la página de consentimiento (GitHub Pages) | GitHub | SOLO PRODUCCIÓN |
| 4 | Secretos `MCP_PUBLIC_URL` y `MCP_AUTH_URL` | Supabase CLI | SOLO PRODUCCIÓN |
| 5 | Desplegar la función `mcp` | Supabase CLI | SOLO PRODUCCIÓN |
| 6 | Comprobar la función (401 y metadatos) | curl | SOLO PRODUCCIÓN (curl probado en local) |
| 7 | Configurar Auth: URLs y OAuth Server | Dashboard de Supabase | SOLO PRODUCCIÓN, no verificable |
| 8 | Comprobaciones tras Auth (registro cerrado, login, metadatos) | curl | SOLO PRODUCCIÓN (curl probado en local) |
| 9 | Alta del conector en claude.ai y prueba de extremo a extremo | claude.ai | SOLO PRODUCCIÓN, no verificable |
| 10 | Revocar una conexión | iOS / claude.ai / API | Probado en local (API) |
| R | Rollback completo | varios | — |

La función se despliega (5) **antes** de activar el OAuth server (7): sin servidor OAuth no existe ningún token que la
función acepte, así que desplegarla no expone nada. Si algo falla en 5-6 se borra la función y Auth sigue intacto.

## Por qué no `config push`

`supabase/config.toml` es la configuración del **stack local**: `site_url = "http://127.0.0.1:3000"`, redirects locales,
`enable_signup = true`, `jwt_expiry = 604800` y `[auth.oauth_server]` con registro dinámico. Un `supabase config push`
con ese fichero sobrescribiría la Auth de producción: cambiaría las URLs (rompe correos y enlaces), **abriría el registro**
en Auth y fijaría la caducidad del token. Por eso Auth se configura por dashboard (paso 7). Si en el futuro se quiere
gestionar Auth por código, debe hacerse con un fichero de producción separado, revisado línea a línea, con
`supabase config diff` y un diff previo; no forma parte de este runbook.

## 0. Prerrequisitos y decisiones

- Supabase CLI (`supabase --version`), sesión iniciada con `supabase login` (token personal en el llavero; no en git).
- Permisos de administración sobre el repositorio de GitHub (Settings → Pages, Variables) y sobre el proyecto Supabase.
- Esta rama (o `master` con ella) revisada y fusionada: el workflow `.github/workflows/pages.yml` y `web/` tienen que
  estar en `master` para publicarlos.
- Valores públicos a mano: `<PROJECT_REF>`, `<URL>` y `<ANON_KEY>` (Dashboard → Project Settings → API).
- La cuenta familiar de producción es real: ningún comando de este runbook crea, borra ni modifica datos del hogar.

## 1. Anotar el estado actual de Auth (base del rollback)

**SOLO PRODUCCIÓN. No verificable (pantallas del dashboard).** Es solo lectura. Sin estas notas el rollback del paso 7 es impreciso.

Dashboard → Authentication, y anota (captura de pantalla o texto) en un fichero **fuera del repo**:

1. **URL Configuration**: *Site URL* y la lista de *Redirect URLs*.
2. **Email Templates**: cuerpo y asunto de cada plantilla (Confirm signup, Reset password, Magic link, Invite…).
   Mira si usan `{{ .SiteURL }}` o `{{ .ConfirmationURL }}`.
3. **Sign In / Providers → Email**: *Allow new users to sign up*, *Confirm email*, y si hay SMTP propio.
4. **Sessions / JWT** (Project Settings → JWT Keys / Authentication → Sessions): *JWT expiry* actual.
5. **OAuth Server** (beta): estado actual (esperado: desactivado).

Comprobación pública y de solo lectura (guarda la salida):

```sh
curl -s -H "apikey: <ANON_KEY>" <URL>/auth/v1/settings            # anota "disable_signup" y "mailer_autoconfirm"
curl -s <URL>/functions/v1/api/config                              # esperado: {"allow_registration":false}
```

**Rollback:** no aplica (solo lectura).

## 2. Decidir `site_url` y la caducidad del token

**Decisión, sin comandos. Hazla antes de tocar Auth.**

**`site_url` y subruta de Pages.** La URL del consentimiento es `Site URL` + `authorization_url_path`. En GitHub Pages
de un repositorio la página queda en una **subruta**:

```text
https://<USUARIO>.github.io/Homita/oauth/consent/
```

Por tanto, con Pages:

- `site_url` = `https://<USUARIO>.github.io` (el origen de Pages),
- `authorization_url_path` = `/Homita/oauth/consent` (con la subruta; Auth no admite una URL absoluta aquí).

Efectos a valorar antes (revisa lo anotado en el paso 1):

- Si los correos de Auth están en uso (confirmación, recuperar contraseña) y usan `{{ .SiteURL }}`, sus enlaces
  apuntarán a `github.io`. Hoy el registro está cerrado y la app no usa esos correos: comprueba que sigue siendo así
  antes de cambiar el `site_url`.
- Enlaces de correo ya enviados al `site_url` antiguo dejarán de funcionar.
- Alternativa: un dominio propio para la página (infra extra, fuera de este runbook). La subruta desaparece y
  `authorization_url_path` sería `/oauth/consent`.

**Caducidad del token (`jwt_expiry`).** En local es de 7 días (604800 s, el máximo); el de producción es el que anotaste en el paso 1. Medido en local: al **revocar** una
conexión el token OAuth deja de valer en el acto en el MCP (la función valida con `GET /auth/v1/user`, que comprueba
la sesión), así que la caducidad larga no deja un acceso colgado tras revocar. Aun así, un `jwt_expiry` menor reduce
la ventana si Auth cambiara ese comportamiento; es decisión tuya y **este runbook no lo cambia**.

**Rollback:** el paso es solo una decisión, no cambia nada en producción. Si decidiste algo y te arrepientes, descártalo
(no se ha aplicado todavía). Si ya cambiaste `site_url` o `jwt_expiry` en el paso 7, se deshacen allí (Authentication → URL
Configuration y Sessions, con los valores anotados en el paso 1).
**Comprobación del rollback:** en el dashboard, *Site URL*, *Redirect URLs* y *JWT expiry* coinciden con las notas del paso 1,
y `curl -s -H "apikey: <ANON_KEY>" <URL>/auth/v1/settings` da el mismo `disable_signup` que entonces.

## 3. Publicar la página de consentimiento (GitHub Pages)

**SOLO PRODUCCIÓN. No verificable (pantallas de GitHub).** `.github/workflows/pages.yml` ya existe con solo
`workflow_dispatch` y publica únicamente `web/`. Permisos mínimos (`contents: read`, `pages: write`, `id-token: write`);
`config.js` se genera con la URL y la anon key (públicas) y el job falla si faltan o si tienen caracteres raros.

1. Repo → **Settings → Pages → Build and deployment → Source: GitHub Actions**.
2. Repo → **Settings → Secrets and variables → Actions → pestaña Variables → New repository variable** (variables, **no** secretos):
   - `SUPABASE_URL` = `<URL>`
   - `SUPABASE_ANON_KEY` = `<ANON_KEY>`
3. Repo → **Actions → pages → Run workflow** (rama `master`). O por CLI: `gh workflow run pages.yml --ref master`.
   (No se añade `push` a `master` en `on:`; es opcional y posterior.)

Comprobación (esperado: `200` en las tres):

```sh
curl -s -o /dev/null -w "%{http_code}\n" https://<USUARIO>.github.io/Homita/oauth/consent/
curl -s -o /dev/null -w "%{http_code}\n" https://<USUARIO>.github.io/Homita/oauth/consent/config.js
curl -s https://<USUARIO>.github.io/Homita/oauth/consent/config.js     # solo SUPABASE_URL y SUPABASE_ANON_KEY
```

`https://<USUARIO>.github.io/Homita/oauth/consent` (sin barra final) redirige con `301` a la versión con barra y conserva
`?authorization_id=…` (probado en local con un servidor que simula la subruta). Las rutas de la página son relativas,
así que la subruta no necesita ajustes.

**Límite conocido:** GitHub Pages no admite cabeceras; el antiframe (clickjacking) es solo por JavaScript (ver
`supabase/functions/mcp/README.md`).

**Rollback:** Settings → Pages → Source: *None* (o «Unpublish site»); borrar las dos variables. No afecta a Supabase.

## 4. Secretos de la función

**SOLO PRODUCCIÓN.** Fijan la URL pública del recurso y el servidor de autorización que anuncia el MCP. No son
secretos sensibles, pero se guardan como secretos de la función.

```sh
supabase secrets set MCP_PUBLIC_URL=<URL>/functions/v1/mcp MCP_AUTH_URL=<URL>/auth/v1 --project-ref <PROJECT_REF>
supabase secrets list --project-ref <PROJECT_REF>         # deben aparecer MCP_PUBLIC_URL y MCP_AUTH_URL (solo resúmenes)
```

**Rollback:** `supabase secrets unset MCP_PUBLIC_URL MCP_AUTH_URL --project-ref <PROJECT_REF>` (la función vuelve a sus valores por defecto).

## 5. Desplegar la función `mcp`

**SOLO PRODUCCIÓN.** `supabase/README.md` prohíbe `functions deploy` contra producción sin confirmación explícita de
Damian: confírmalo antes. `config.toml` no se lee en el deploy, así que `--no-verify-jwt` es obligatorio (la función
valida el token ella misma; sin el flag el gateway rechazaría los tokens OAuth).

```sh
supabase functions deploy mcp --no-verify-jwt --project-ref <PROJECT_REF>
supabase functions list --project-ref <PROJECT_REF>        # mcp en estado ACTIVE
```

Solo se despliega `mcp`; **no** se despliegan `api` ni `asistente` (sin cambios en este change).

**Rollback:** `supabase functions delete mcp --project-ref <PROJECT_REF>`.

## 6. Comprobar la función (401 y metadatos)

**SOLO PRODUCCIÓN** (los mismos curl están probados contra la función local).

```sh
# Sin token: 401 con WWW-Authenticate que apunta a los metadatos
curl -i -X POST <URL>/functions/v1/mcp -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
# Metadatos del recurso protegido (sin autenticación)
curl -s <URL>/functions/v1/mcp/.well-known/oauth-protected-resource
```

Esperado: `HTTP/2 401` con `www-authenticate: Bearer resource_metadata="<URL>/functions/v1/mcp/.well-known/oauth-protected-resource"`;
el segundo devuelve `{"resource":"<URL>/functions/v1/mcp","authorization_servers":["<URL>/auth/v1"]}` (u equivalente
con esos dos valores). Si `resource` no coincide con `MCP_PUBLIC_URL`, revisa el paso 4 antes de seguir.

**Rollback:** el del paso 5.

## 7. Configurar Auth: URLs y OAuth Server

**SOLO PRODUCCIÓN. No verificable (pantallas de Supabase; la UI y la beta del OAuth Server pueden haber cambiado).**
**Confirma con Damian antes de cada punto.** Se hace por dashboard, nunca por `config push` (ver arriba).

1. **Authentication → URL Configuration**
   - *Site URL*: el origen de Pages decidido en el paso 2 (`https://<USUARIO>.github.io`).
   - *Redirect URLs*: **conserva** las que había (paso 1); añade solo lo que haga falta.
2. **Authentication → Email Templates**: solo si el paso 1 mostró que se usan; si dependían de `{{ .SiteURL }}`,
   cámbialas a una URL explícita para no romperlas. Si no se usan, no tocar.
3. **Authentication → OAuth Server** (beta): activar el servidor OAuth;
   - *Authorization Path*: `/Homita/oauth/consent` (con la subruta; se concatena al Site URL),
   - *Allow dynamic client registration*: activado (Claude se registra solo).
4. **No tocar** *Allow new users to sign up* ni el resto de proveedores: el registro sigue cerrado.

Alternativa avanzada (solo si prefieres código): `supabase config push` con un **fichero de producción separado**
(copia solo con `[auth]` mínimo), revisado línea a línea y con `supabase config diff` antes. No con `supabase/config.toml`.

**Rollback (en este orden):** desactivar el OAuth Server; restaurar *Site URL* y *Redirect URLs* a lo anotado en el paso 1;
restaurar las plantillas si se tocaron; revocar los clientes registrados (Authentication → OAuth Apps, borrar los de
«Claude»). La función `mcp` puede quedarse desplegada: sin servidor OAuth ningún token sirve.

## 8. Comprobaciones tras configurar Auth

**SOLO PRODUCCIÓN** (curl probados en local).

```sh
# El servidor de autorización publica los endpoints (authorize, token, registro dinámico)
curl -s <URL>/auth/v1/.well-known/oauth-authorization-server
# El registro de la app sigue cerrado
curl -s <URL>/functions/v1/api/config                              # {"allow_registration":false}
curl -s -H "apikey: <ANON_KEY>" <URL>/auth/v1/settings             # "disable_signup" igual que en el paso 1
# La función sigue pidiendo token
curl -s -o /dev/null -w "%{http_code}\n" -X POST <URL>/functions/v1/mcp -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'   # 401
```

Esperado: `authorization_endpoint`, `token_endpoint` y `registration_endpoint` bajo `<URL>/auth/v1/`; el registro y
`disable_signup` **idénticos** a lo anotado en el paso 1. Si cambió el registro, **para y haz el rollback del paso 7**.
Además: inicia sesión en la app (dashboard o iOS) y comprueba que sigue entrando (la sesión de la app no usa OAuth).

**Rollback:** el del paso 7.

## 9. Alta del conector en claude.ai y prueba de extremo a extremo

**SOLO PRODUCCIÓN. No verificable (claude.ai; versión de spec del cliente).**

1. claude.ai → **Ajustes → Conectores → Añadir conector personalizado**; URL: `<URL>/functions/v1/mcp`.
2. Claude abre la página de consentimiento (`https://<USUARIO>.github.io/Homita/oauth/consent/?authorization_id=…`):
   inicia sesión con tu cuenta de Homita, comprueba que el host de `redirect_uri` es de Claude y aprueba.
3. En una conversación nueva con el conector activo: «¿qué hogares tengo?» (`ver_hogares`), «¿qué hay en el menú de esta
   semana?» (`leer_semana`). Lecturas primero; las herramientas de escritura piden aprobación en el cliente. No
   hagas escrituras de prueba sobre el hogar real.
4. Comprobación en la app: iOS → **Ajustes → Claude** muestra la conexión.

**Rollback:** claude.ai → Ajustes → Conectores → quitar el conector; y revocar el acceso (paso 10).

## 10. Revocar una conexión

Tres vías equivalentes; revocar borra la sesión y los refresh tokens de ese cliente para ese usuario.

- **App iOS** (Ajustes → Claude → Revocar). Usa la API de Supabase Auth del usuario: `GET /auth/v1/user/oauth/grants`
  (lista) y `DELETE /auth/v1/user/oauth/grants?client_id=<id>` (revoca), con el Bearer del usuario. **Probado en local.**
- **claude.ai**: Ajustes → Conectores → quitar el conector (no garantiza revocar el grant en Supabase: revisa en iOS o por API).
- **API** (para comprobar, p. ej. en local o con un JWT del usuario):

```sh
curl -s <URL>/auth/v1/user/oauth/grants -H "apikey: <ANON_KEY>" -H "Authorization: Bearer <JWT_DEL_USUARIO>"
curl -s -X DELETE "<URL>/auth/v1/user/oauth/grants?client_id=<CLIENT_ID>" -H "apikey: <ANON_KEY>" -H "Authorization: Bearer <JWT_DEL_USUARIO>"   # 204
```

Medido en local tras revocar: el token OAuth da `403` en `GET /auth/v1/user` (así que el MCP responde `401`), el
refresh token da `400 refresh_token_not_found` y la lista de grants queda vacía.

**Rollback:** revocar no se puede deshacer (el grant y su refresh token se borran). Para recuperar el acceso, el usuario
vuelve a conectar el conector desde claude.ai (paso 9) y aprueba otra vez en la página de consentimiento; se crea un grant nuevo.
**Comprobación del rollback:** tras reconectar, `GET <URL>/auth/v1/user/oauth/grants` (con el JWT del usuario) vuelve a
listar el cliente y iOS → Ajustes › Claude lo muestra; una herramienta de solo lectura (`ver_hogares`) responde en claude.ai.
Si lo que querías deshacer era una revocación por error de un cliente ajeno, no hay nada que restaurar: ese cliente queda revocado.

## R. Rollback completo (orden inverso)

1. Quitar el conector en claude.ai y revocar los grants (paso 10) o borrar los clientes OAuth (paso 7).
2. Desactivar el OAuth Server; restaurar *Site URL*, *Redirect URLs* y plantillas (paso 7, con lo anotado en el paso 1).
3. `supabase functions delete mcp --project-ref <PROJECT_REF>`.
4. `supabase secrets unset MCP_PUBLIC_URL MCP_AUTH_URL --project-ref <PROJECT_REF>`.
5. Pages: Source *None* y borrar las variables.
6. Comprobar: `curl -s <URL>/functions/v1/api/config` → `{"allow_registration":false}` y que la app inicia sesión.

## Prueba en local

Los pasos con curl y el flujo OAuth se probaron contra el stack local (no contra producción). Reproducción, desde la
raíz del repo, sin `~/.homita/supabase.env`:

```sh
supabase start -x studio,imgproxy,vector,logflare,mailpit
scripts/demo.sh up                                   # reset de la BD local, Edge (api y mcp) y datos de demo
# Equivalente al paso 6 (local)
curl -i -X POST http://127.0.0.1:54321/functions/v1/mcp -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
curl -s http://127.0.0.1:54321/functions/v1/mcp/.well-known/oauth-protected-resource
# Equivalente al paso 8 (local)
curl -s http://127.0.0.1:54321/auth/v1/.well-known/oauth-authorization-server
# Página de consentimiento bajo una subruta, como en Pages
scripts/oauth/local-config.sh                        # config.js local (gitignored)
mkdir -p /tmp/pages-sim && ln -sfn "$PWD/web" /tmp/pages-sim/Homita
python3 -m http.server 3100 --bind 127.0.0.1 --directory /tmp/pages-sim &
curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:3100/Homita/oauth/consent/
```

El flujo OAuth completo (registro dinámico, authorize, consentimiento, canje con PKCE) lo automatiza el bloque `MCP` de
`scripts/supabase/tests/cross_tenant_check.py`, que corre `scripts/supabase/ci.sh` sobre un stack efímero. **No lo
ejecutes a mano con variables de entorno de producción**: esa suite escribe y borra datos.

El registro de la prueba (qué se ejecutó y con qué salida) está en `.dorch/changes/mcp-produccion/status.md`.

## No verificado aquí

- Pantallas actuales del dashboard de Supabase (URL Configuration, Email Templates, OAuth Server beta) y de GitHub/claude.ai.
- Comportamiento real de GitHub Pages sirviendo la página, y la versión de spec del cliente de Claude.
- Que `supabase functions deploy` y `supabase secrets set` funcionen con la CLI y la sesión de Damian.
