# Edge Function `mcp` (MCP de Claude para Homita)

Servidor MCP remoto (Streamable HTTP sin estado) para que Claude consulte los hogares, menús, compra, tareas, eventos,
rutinas, calendarios y personas de Homita (fase 1, solo lectura) y **escriba el menú semanal, las recetas, los
alimentos, la compra y las preferencias** (fase 2: 8 herramientas de escritura). Solo local: producción, el despliegue
y Pages son de la fase 4 (ver «Producción / fase 4»). Las herramientas de organizar (listas, tareas, eventos) son de la fase 3.

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

## Herramientas de lectura (12, todas `readOnlyHint: true`)

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

## Herramientas de escritura (fase 2: 8)

Todas aceptan `hogar` y `timezone`, devuelven JSON compacto en español y marcan `isError: true` en lo que no se hizo.
`readOnlyHint: false`, `openWorldHint: false`, `destructiveHint: false` salvo `aceptar_menu` (`true`).

| Herramienta | Qué hace |
|---|---|
| `guardar_receta` | Receta nueva con pasos e **ingredientes obligatorios** (`alimento_id` o `texto` que coincida exacto con el catálogo; si no, error que pide `crear_alimento`). Idempotente. |
| `crear_alimento` | Alta en el catálogo del hogar; si ya existe uno con ese nombre lo reutiliza (`creado: false`). |
| `guardar_borrador` | Borrador (origen Kito) de un rango de casillas, un plan por semana. Solo casillas libres. |
| `cambiar_casillas` | Cambia casillas libres o `rejected` de un plan (`plan_id` + `expected_revision`). |
| `aceptar_menu` | Acepta el menú (`destructiveHint: true`). Exige `plan_id`, `expected_revision` y `fecha` (un día de la semana del plan). |
| `apuntar_compra` | Hasta 20 artículos. Éxito parcial (`apuntados`, `fallos`). |
| `marcar_comprado` | `checked`, `pending` (desmarcar) o `skipped` (ya lo tengo), hasta 50 ids. Idempotente. |
| `apuntar_preferencia` | `no_le_gusta` (C1), `le_encanta` (C2) o `picante` (C4, 0-3); exige `confirmado_por_usuario: true`; no toca manías (C3). |

**Ciclo del menú.** Claude lee (`leer_perfil`, `leer_semana`, `buscar_recetas`) → guarda recetas y alimentos nuevos
ANTES (para que la Compra salga completa) → `guardar_borrador` → la persona lo revisa → `cambiar_casillas` si pide
cambios → `aceptar_menu` solo con un sí explícito. El MCP no llama a ningún modelo: valida, escribe con el JWT del
usuario **dentro de `runInHome`** (tras `resolverHogar`, que comprueba que es miembro), comprueba y devuelve.

**Lista blanca de escritura propia** (`escritor.ts`): las 4 rutas comunes de menús (`PATCH meal/plan/items`,
`POST recipe/create`, `POST shopping/item/create`, `PATCH meal/profile/member`, de `_shared/homita/escritor.ts`) más
`POST meal/plan/accept`, `POST food/create` y `PATCH shopping/item/check`. **Kito no tiene `accept`**: su lista blanca
(`asistente/skills/organizar/api.ts`) sigue sin él y hay tests que lo fijan. Las reglas de seguridad (comprobación de
conflictos y bloqueo por «sin comprobar» con dieta o alergias, casillas libres, `locked`) tienen una sola copia en
`_shared/homita/` que usan Kito y el MCP.

**`guardar_borrador`.** Solo rellena casillas libres: no borra nada, no toca `locked` ni casillas ocupadas, y salta las
semanas aceptadas o hechas por la persona (`origin ≠ kito` con casillas) con aviso. Cruzar semanas = un plan por
semana, sin transacción entre ellas: se informa por semana (`escrito`, `ya_estaba`, `saltada`, `fallo`) y si una falla las
demás siguen. Reintento idempotente (`client_request_id` por contenido y revisión, prefijo `mcp-`). Devuelve los
conflictos por semana; el borrador se guarda aunque los haya, pero no se puede aceptar así.

**`cambiar_casillas`.** Más estricto que «cualquier casilla»: solo toca casillas libres o marcadas `rejected` por la
persona; las bloqueadas y las ocupadas con un plato normal vuelven en `rechazadas` con el motivo. La revisión la envía quien
llama (así detecta que el plan cambió desde que se mostró): si no coincide no escribe y devuelve `plan_vigente`. Un plan
aceptado no se edita. Una semana por llamada (el api solo busca el plan por semana).

**`aceptar_menu` y su (no) atomicidad.** El «sí» del usuario lo exigen la descripción de la herramienta y
`destructiveHint`; el servidor no ve la conversación. `accept_meal_plan` solo comprueba la revisión, no los conflictos. Por
eso, en la misma invocación: (1) lee el plan; (2) `check_meal_plan` + regla «sin comprobar» justo antes; con conflictos NO
acepta; (3) `accept` con la revisión que vio la persona (un 409 devuelve `plan_vigente` y no se reintenta); (4) resumen de la
Compra generada; (5) segunda comprobación: si apareciera un conflicto (un cambio ajeno al plan, que no sube la revisión) se
acepta igualmente (no hay deshacer) con `avisos`/`conflictos_tras_aceptar`. Riesgo residual: la ventana entre (2) y (3).

**Idempotencia de la compra.** `apuntar_compra` deduplica por artículo normalizado y **día local** del usuario: reintentar es
seguro dentro del mismo día; apuntar lo mismo otro día crea otro artículo. `marcar_comprado` es idempotente por naturaleza.

**Fuera de la herramienta:** archivar, copiar un menú, el horario, las manías (C3) y los datos de salud. No hay `enlace_app`
(sin URL pública estable de la app).

## Herramientas de organizar (fase 3: 17)

Escriben lo que organiza Homita (listas, tareas, eventos, rutinas, calendarios) con el JWT del usuario dentro de `runInHome`.
`readOnlyHint: false`, `openWorldHint: false`; `destructiveHint: true` solo en los cinco `borrar_*` (y en `aceptar_menu`).
Todas aceptan `hogar` y `timezone`. Los ids salen de `ver_*`; solo los destinos (lista de una tarea, calendario de un evento o
rutina) se resuelven en el servidor: con varios editables y sin indicar, la respuesta es `{falta:["lista"|"calendario"], opciones}`.

| Herramienta | Qué hace |
|---|---|
| `crear_lista`, `editar_lista`, `borrar_lista` | Lista de tareas. Editar rellena `sort`, `widget` y `dashboard`. |
| `crear_tarea`, `editar_tarea`, `completar_tarea`, `borrar_tarea` | Tareas (`vence` en hora local; se fija con un segundo PATCH y, si falla, sale en `avisos`). `completar_tarea` con `completada:false` la desmarca. |
| `crear_evento`, `editar_evento`, `borrar_evento` | Eventos. Editar conserva la alarma. Sin descripción ni alarma. |
| `crear_rutina`, `editar_rutina`, `borrar_rutina` | Rutinas (empiezan hoy y quedan activas salvo `desde`). Editar reenvía la rutina completa; `hasta:""` = no termina; las personas asignadas se conservan. |
| `crear_calendario`, `editar_calendario`, `compartir_calendario`, `borrar_calendario` | Calendarios. Se crea con `solo_yo` o `compartir_con`; compartir solo con personas **con cuenta** (`ver_personas`), por defecto en solo lectura. |

**Misma lógica que Kito.** Las reglas (qué falta, qué se rellena al editar, qué cuerpo recibe cada caso de uso, cómo se traducen
los errores) viven en `_shared/homita/organizar/` (funciones `preparar*`); Kito y el MCP envían los mismos cuerpos al api
(`tests/organizar_paridad_test.ts` lo comprueba contra la caracterización de Kito). El MCP no llama a ningún modelo.

**Respuestas.** Éxito `{ok, hecho, id, …, avisos?}`. «Falta» es contenido normal (Claude debe preguntar), no `isError`. Validación o
error del api → `isError` con un texto en español (403 con el nombre, 404 «Ya no existe.», 400 con el motivo).

**Borrar y `confirmado`.** Los `borrar_*` no borran sin `confirmado: true`: sin él devuelven `{ejecutado:false,
requiere_confirmacion:true, se_borraria}` y no llaman al api. **Es una protección blanda**: lo pone el modelo y no prueba que la
persona dijera sí; la barrera real es `destructiveHint`, que hace que el cliente pida aprobación, más las descripciones y las
instrucciones del servidor. `borrar_lista` dice las tareas totales (pendientes y hechas, la cascada borra todas; las hechas hace
más de tres días que la app ya no muestra se borran también). `borrar_calendario` borra sus eventos y rutinas. Borrar algo que
ya no existe es éxito (`ya_estaba:true`).

**Idempotencia.** `crear_lista` y `crear_tarea` mandan `client_request_id` = UUID de (usuario, hogar, herramienta, cuerpo ya
resuelto, minuto), con prefijo `mcp-organizar`: repetir la misma llamada en el mismo minuto no duplica. Límites: un reintento que
cruza el minuto duplica; dos altas idénticas e intencionadas en el mismo minuto colapsan en una; si lo creado se borra y se
repite el alta idéntica en el mismo minuto, el api responde «Not Found» («Ya no existe.»): esperar un minuto o cambiar algo.
`completar_tarea` no manda clave (fijar un estado ya es idempotente). **Eventos, rutinas y calendarios no tienen idempotencia en
el api**: si un alta falla sin saberse si se hizo, comprobar con `ver_*` antes de reintentar.

**`crear_calendario` no es atómico.** Crea el calendario y luego comparte con `PATCH calendar/user`; si ese paso falla el
calendario queda creado y sale en `avisos` (`compartir_calendario` permite reintentarlo). Si alguna persona no tiene cuenta no
se crea nada.

**Ediciones last-write-wins.** Los `update_*` no tienen `expected_revision`: el último que escribe gana (`editar_rutina` reenvía
el estado completo y puede pisar un cambio concurrente entre su lectura y su escritura).

**Fuera de alcance:** alarmas (`alarma_min` no se expone), administración del hogar, invitaciones, revocar acceso a un
calendario y compartir con personas sin cuenta.

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

**Pendiente de Damian (no bloquea las fases 1 y 2):** valor actual de `site_url` en producción y si los correos de Auth
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
