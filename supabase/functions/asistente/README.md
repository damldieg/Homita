# Edge Function `asistente` (Kito)

Asistente de IA de Homita (change `kito-asistente`, fase 1). Recibe el historial del chat y responde en
español con datos del hogar activo. Lee (skill `consulta`), explica la app (`ayuda`) y, desde el change
`kito-organizar`, escribe (skill `organizar`: crea, edita, completa y borra listas, tareas, eventos, rutinas y
calendarios). Desde `kito-menus`, la skill `menus` propone el menú semanal como borrador (ver más abajo).

## Estructura

- `index.ts`: cableado (env, Anthropic, BD de uso por RPC de service_role). Sin lógica.
- `handler.ts`: auth, hogar, validación, límite diario, fallo del modelo y respuesta. Dependencias inyectadas.
- `core.ts`: núcleo. Bucle de tool use (herramientas de una vuelta en paralelo), registro de herramientas,
  topes, selección de modelo y tratamiento de `max_tokens`/`refusal`. No conoce ninguna skill.
- `contexto.ts`: ficha `<contexto>` (fecha local, usuario, personas, hogar, calendarios, listas) que el núcleo
  antepone al último mensaje de usuario. Nunca va en `system`.
- `modelo.ts`: llamada HTTP a Anthropic con un reintento (429/529/5xx, `retry-after` ≤ 3 s) y presupuesto.
- `skills/registry.ts`: lista de skills. Añadir una skill = carpeta nueva + una línea aquí.
- `skills/consulta/`: skill de lectura (`ver_eventos`, `ver_rutinas`, `ver_tareas`, `ver_calendarios`,
  `ver_listas`, `ver_personas`). `api.ts` llama en proceso a los casos de uso de `api` con el JWT del usuario
  (RLS, ACL y hogar activo); `fechas.ts` y `compacto.ts` dan fechas ISO locales y salida compacta (tope 50).
- `skills/organizar/`: skill de escritura. La lógica de organizar (operaciones, `preparar*` por entidad, errores, fechas, `RUTAS_ORGANIZAR`) vive en `_shared/homita/organizar/` y la comparte el MCP; aquí quedan el despacho, la tarjeta HMAC y `/confirmar`. `api.ts` es el escritor (casos de uso de escritura en proceso con el JWT
  del usuario, lista blanca de rutas); `acciones.ts` registra las operaciones (las comparten las herramientas y
  `/confirmar`); `base.ts` decide ejecutar, dejar pendiente o negar; `confirmacion.ts` firma y verifica el token;
  `confirmar.ts` es `POST /asistente/confirmar`; `listas.ts`, `tareas.ts`, `eventos.ts`, `rutinas.ts` y
  `calendarios.ts` son las herramientas; `errores.ts` traduce los errores del api; `uuid.ts` deriva el
  `client_request_id`; `tiempo.ts` convierte las fechas locales.
- `skills/menus/`: skill del menú semanal (`kito-menus`). `index.ts` (prompt y registro), `intencion.ts` (cuándo
  se activa), `lectura.ts` (`leer_perfil`, `leer_semana`, `buscar_recetas`), `menu.ts` (`proponer_menu`,
  `reproponer`), `escritura.ts` (`guardar_receta`, `apuntar_compra`, `apuntar_preferencia`), `plan.ts` (forma
  compacta del plan y tarjeta `menu`) y `util.ts`.
- `tests/`: tests Deno con modelo, auth, uso y escritor falsos (puros: sin red ni lectura de disco).

## Contrato

`POST /asistente` con `Authorization: Bearer <JWT del usuario>` y `X-Home-Id: <hogar>`:

```json
{ "messages": [{ "role": "user", "content": "¿qué tengo hoy?" }], "timezone": "Europe/Madrid" }
```

- Máximo 20 mensajes, 2000 caracteres por mensaje; el último debe ser del usuario.
- El historial lo guarda la app; el servidor no lo guarda.
- Respuestas: `200 {texto, tarjetas, cambios, uso:{usados, limite}}`; `400` validación; `401` sesión; `404` hogar o
  usuario; `429` límite diario (50, sin llamar al modelo); `500` sin configuración; `502` fallo del modelo
  (el mensaje se devuelve al contador).

### Escrituras: `tarjetas` y `cambios` (aditivos)

- `cambios: [{tipo: "tarea"|"lista"|"evento"|"rutina"|"calendario", id, op: "crear"|"editar"|"borrar"}]`: lo que
  Kito ha cambiado en esta petición, para que la app recargue. Vacío si no ha escrito nada.
- `tarjetas`: vacío o una única tarjeta de confirmación:

```json
{ "tipo": "confirmacion", "id": "confirmacion", "texto": "¿Borro la lista «Pruebas» y sus tareas (2 pendientes)?",
  "acciones": [{ "op": "borrar_lista", "args": { "id": 3 }, "nombre": "Pruebas" }],
  "token": "<base64url(payload)>.<base64url(HMAC)>", "caduca": "2026-11-25T10:10:00.000Z" }
```

- Reglas: crear o editar **un** elemento se ejecuta al momento. Borrar, o cualquier escritura que no sea la única
  de la petición, no se ejecuta: queda en la tarjeta (una sola, con todas las acciones y un único token).
  La app muestra `texto` y, si el usuario acepta, envía el token a `/asistente/confirmar`; cancelar es solo de la app.
- El modelo no ve nunca el token ni las acciones (solo «propuesta enviada al usuario para confirmar»).
- Token: `payload = JSON canónico {acciones, exp, home_id, uid, v: 1}` (claves ordenadas), firmado con
  HMAC-SHA256 y `KITO_CONFIRM_SECRET`; vale 2 minutos, para ese usuario y ese hogar, máximo 20 acciones de una
  lista blanca de operaciones. Limitación conocida: el token no es de un solo uso; puede reusarse dentro de esa
  ventana (un doble toque o un reintento puede duplicar altas de evento, rutina o calendario, o reaplicar ediciones).
  El uso único requeriría una tabla (fuera de alcance). La app debe deshabilitar Aceptar tras el primer toque y no
  reintentar un 5xx sin pedir una confirmación nueva.

### `POST /asistente/confirmar`

`Authorization: Bearer <JWT>` y `X-Home-Id` como en Kito; body `{ "token": "…", "timezone": "Europe/Madrid" }`
(`timezone` opcional, `UTC` por defecto; la usan los borrados de eventos y rutinas). No llama al modelo ni gasta
cupo. Ejecuta las acciones en orden dentro del hogar activo.

| Código | Cuándo |
|---|---|
| `200 {texto, cambios}` | Todo hecho. Borrar algo que ya no existe cuenta como hecho («Ya estaba hecho») |
| `400` | Sin JSON, sin `token` o `timezone` no válida |
| `401` / `404` / `405` | Sesión, hogar y método, igual que Kito |
| `403 {error, motivo}` | Firma no válida, caducado, de otro usuario o de otro hogar: no se ejecuta nada |
| `409 {error, texto, cambios}` | Una acción ha fallado (permiso, ya no existe, error interno del api…): se para ahí; `texto` y `cambios` dicen lo que sí se hizo |
| `503` | Falta `KITO_CONFIRM_SECRET` |

### Qué hace Kito por su cuenta (defaults)

- Rutina: empieza hoy (o cuando diga el usuario) y queda activa; Kito lo dice al confirmar.
- Calendario: color `#6923E2` (el del api para listas); se comparte con personas del hogar **con cuenta** en solo
  lectura (`PATCH /calendar/user`, sin email) y con permiso de edición solo si se pide. «Solo para mí» vale.
- Tarea: si solo hay una lista editable, se usa; con varias, Kito pregunta. Igual con el calendario de eventos y rutinas.
- Fecha límite de una tarea sin hora: el final de ese día (23:59 hora local).
- Reintentos: tareas y listas llevan `client_request_id` derivado del `tool_use.id` (0035), así que un reintento
  dentro del bucle no duplica. Un reintento de la app con una petición nueva genera ids nuevos y puede duplicar.
  Eventos, rutinas y calendarios no tienen idempotencia en el api.

## Secretos

- `ANTHROPIC_API_KEY`: obligatorio. Sin él la función responde 500 y no consume el contador (falla cerrada).
  Ya existe para `procesar-feedback`.
- `KITO_MODEL`: opcional, por defecto `claude-haiku-5-5`. No usar `CLAUDE_MODEL` (es del feedback).
- `KITO_CONFIRM_SECRET`: opcional pero necesario para borrar y para confirmar. Firma las tarjetas de confirmación.
  Sin él, Kito responde «No puedo borrar desde aquí ahora mismo», las altas siguen funcionando y
  `/asistente/confirmar` responde 503 (falla cerrada).
- `KITO_MODEL_MENUS`: opcional. Modelo de la skill `menus`, solo cuando la petición tiene intención de menú; sin
  él, `KITO_MODEL`.
- `KITO_EFFORT`: opcional, `low` | `medium` | `high`. Por defecto `low` (el de Haiku 5.5 sería `medium`). Vacío o
  inválido cae a `low` y deja un aviso en el log sin el valor.

## Regla del modelo por skill

Una skill puede declarar `modelo`: el **nombre de un secreto** (p. ej. `KITO_MODEL_MENUS`). Si la skill también
declara `intencion` (expresión sobre los últimos mensajes) y la petición encaja, entra en la petición y se usa
ese secreto cuando existe y no está vacío. Sin intención, solo cuenta si es la única skill disponible. En
cualquier otro caso (sin declarar, secreto ausente o vacío) se usa `KITO_MODEL`. `menus` declara
`KITO_MODEL_MENUS` con intención de menú (menú, comidas, cenas, almuerzos, recetas de la semana); «semana» suelta
no la activa.

## Skill `menus` (kito-menus)

Kito propone el menú de la semana como **borrador** (`origin = kito`), la persona marca platos a cambiar en la
tarjeta `menu`, Kito repropone solo lo rechazado y la persona **acepta en la app**. Kito nunca acepta:
`POST /meal/plan/accept` no está en las rutas de Kito (`organizar/api.ts`) ni en la confirmación HMAC.

- Lectura: `leer_perfil` (sin salud si falta `menu.health.view`; tolera que no haya países), `leer_semana`,
  `buscar_recetas` (con `ya_tomados`).
- `proponer_menu`: una llamada con la semana entera. Guarda con `PATCH /meal/plan/items` (`origin`,
  `client_request_id` derivado del contenido y de la revisión, `expected_revision`), respeta casillas `locked` y no
  toca un plan aceptado ni uno hecho por la persona; si las casillas libres ya coinciden tras un reintento, no
  escribe de nuevo. Después `check_meal_plan`: solo con 0 conflictos emite la tarjeta `menu` (con conflictos no hay
  tarjeta y el modelo recibe cuáles son).
- `proponer_menu` con `rango` (`{desde:{fecha,franja}, hasta:{fecha,franja}}`, ambos inclusive; sustituye a `semana`):
  planifica solo ese tramo, aunque cruce dos semanas (un plan por semana, una tarjeta `menu-<semana>` por plan).
  Kito convierte el lenguaje natural a fechas con `hoy` de `leer_perfil` («esta noche» = cena, «a mediodía» =
  comida); `resolverRango` (`util.ts`) lo expande en casillas según las franjas activas. Solo rellena huecos: no
  borra nada, no toca casillas con comida, bloqueadas ni fuera del rango, y salta con aviso la semana aceptada o
  hecha por la persona. Franja desactivada en un extremo: aviso y sin casilla.
- `reproponer`: solo casillas `rejected` (con motivo), con la revisión vigente; no toca `locked` ni aceptadas.
- `guardar_receta` (pasos obligatorios, idempotente), `apuntar_compra` (solo si la persona lo pide) y
  `apuntar_preferencia` (C1/C2/C4, solo con `confirmado_por_usuario = true` tras preguntar).
- Rondas: `maxRondas = 8` (por encima de las 6 habituales).
- Tests: `tests/menus_*_test.ts` con el mundo falso de `tests/menus_util.ts`. Más detalle en
  `docs/planificador-comidas/kito-menus.md`.

## Llamada al modelo

`max_tokens` 4096; `output_config.effort` desde `KITO_EFFORT`; sin `temperature`, `top_p`, `top_k` ni `thinking`
(el pensamiento adaptativo es el de por defecto). `system` es una lista de bloques con `cache_control`
(`ephemeral`) en el último; las herramientas van ordenadas por nombre y con `strict: true` (las de `organizar` van con `strict: false`: la API
limita las herramientas strict de toda la petición a 20, 24 parámetros opcionales y 16 uniones, y el servidor
revalida igualmente cada argumento). La ficha de contexto
va en el último mensaje de usuario, así que `tools` + `system` forman un prefijo estable para la caché de prompt
(mínimo cacheable de Haiku 5.5: 512 tokens; el prefijo actual ronda los 1800).
Un `stop_reason` `max_tokens` devuelve el texto con una nota; `refusal` devuelve «Con eso no te puedo ayudar.»
sin reintentar y **no gasta cupo** (se devuelve el mensaje). Un 429/529/5xx se reintenta una vez; con dos fallos
o con el presupuesto de 60 s agotado, 502 y el mensaje se devuelve al cupo.

## Evaluación (la ejecuta una persona; gasta tokens reales)

```sh
# Supabase local en marcha (supabase start + scripts/demo.sh) y variables según la cabecera del script
deno run --allow-env --allow-net=127.0.0.1,localhost,api.anthropic.com scripts/kito/eval.ts --out rama.json
deno run --allow-read scripts/kito/eval.ts --comparar master.json rama.json
```

Diecinueve preguntas fijas (las cinco últimas, de `organizar`, ESCRIBEN en el Supabase local); por cada una escribe respuesta, vueltas, herramientas, tokens de entrada/salida/caché y
latencia. Para comparar con master, copia el script a un checkout de master y ejecútalo allí con `--out master.json`.

## Despliegue (lo ejecuta Damian; no se despliega desde el repo)

```sh
supabase secrets set KITO_MODEL=claude-haiku-5-5        # opcional
supabase secrets set KITO_EFFORT=low                     # opcional (low | medium | high)
supabase secrets set KITO_CONFIRM_SECRET=$(openssl rand -base64 32)   # firma de confirmaciones (borrados)
supabase functions deploy asistente --no-verify-jwt
```

Requiere antes la migración `0036_assistant_usage` (`supabase/migrations/`). Para retirar la función en
producción: primero `supabase functions delete asistente`, después `scripts/supabase/rollback/rollback_0036.sql`.
Rollback de este change: redesplegar el commit anterior (`supabase functions deploy asistente --no-verify-jwt`).

## Tests

```sh
deno check supabase/functions/asistente/index.ts
deno test --no-prompt --allow-env supabase/functions/asistente/tests/
```

`ci.sh` ejecuta estos checks junto con el resto de la suite local.

## Límites conocidos

- `date_at` de los eventos es hora local de pared: los rangos se mandan como epoch «de pared» (ver `fechas.ts`).
  `due_at` de las tareas es UTC y se muestra convertido a la zona del usuario.
- El presupuesto de 60 s se comprueba entre vueltas y en cada llamada al modelo; una herramienta colgada no se
  corta por sí sola.
- La descripción de un evento no se puede guardar (el api no la admite). Un evento no tiene hora de fin, solo
  último día.
- Las confirmaciones no se pueden cancelar en el servidor (cancelar es de la app) y el token puede reutilizarse
  hasta que caduque: las altas con `client_request_id` son idempotentes y borrar lo ya borrado se da por hecho.
