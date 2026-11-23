# Edge Function `asistente` (Kito)

Asistente de IA de Homita (change `kito-asistente`, fase 1). Recibe el historial del chat y responde en
español con datos del hogar activo. Solo lectura en esta fase.

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
- `tests/`: tests Deno con modelo, auth y uso falsos.

## Contrato

`POST /asistente` con `Authorization: Bearer <JWT del usuario>` y `X-Home-Id: <hogar>`:

```json
{ "messages": [{ "role": "user", "content": "¿qué tengo hoy?" }], "timezone": "Europe/Madrid" }
```

- Máximo 20 mensajes, 2000 caracteres por mensaje; el último debe ser del usuario.
- El historial lo guarda la app; el servidor no lo guarda.
- Respuestas: `200 {texto, tarjetas, uso:{usados, limite}}`; `400` validación; `401` sesión; `404` hogar o
  usuario; `429` límite diario (50, sin llamar al modelo); `500` sin configuración; `502` fallo del modelo
  (el mensaje se devuelve al contador).

## Secretos

- `ANTHROPIC_API_KEY`: obligatorio. Sin él la función responde 500 y no consume el contador (falla cerrada).
  Ya existe para `procesar-feedback`.
- `KITO_MODEL`: opcional, por defecto `claude-haiku-5-5`. No usar `CLAUDE_MODEL` (es del feedback).
- `KITO_EFFORT`: opcional, `low` | `medium` | `high`. Por defecto `low` (el de Haiku 5.5 sería `medium`). Vacío o
  inválido cae a `low` y deja un aviso en el log sin el valor.

## Regla del modelo por skill

Una skill puede declarar `modelo`: el **nombre de un secreto** (p. ej. `KITO_MODEL_MENUS`). Si hay una única
skill disponible en la petición, declara `modelo` y ese secreto existe y no está vacío, se usa ese modelo. En
cualquier otro caso (sin declarar, secreto ausente o vacío, o varias skills disponibles) se usa `KITO_MODEL`.

## Llamada al modelo

`max_tokens` 4096; `output_config.effort` desde `KITO_EFFORT`; sin `temperature`, `top_p`, `top_k` ni `thinking`
(el pensamiento adaptativo es el de por defecto). `system` es una lista de bloques con `cache_control`
(`ephemeral`) en el último; las herramientas van ordenadas por nombre y con `strict: true`. La ficha de contexto
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

Diez preguntas fijas; por cada una escribe respuesta, vueltas, herramientas, tokens de entrada/salida/caché y
latencia. Para comparar con master, copia el script a un checkout de master y ejecútalo allí con `--out master.json`.

## Despliegue (lo ejecuta Damian; no se despliega desde el repo)

```sh
supabase secrets set KITO_MODEL=claude-haiku-5-5        # opcional
supabase secrets set KITO_EFFORT=low                     # opcional (low | medium | high)
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
- Sin tarjetas estructuradas: solo texto (`tarjetas: []`). Llegan con la fase 2.
