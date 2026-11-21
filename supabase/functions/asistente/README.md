# Edge Function `asistente` (Kito)

Asistente de IA de Homita (change `kito-asistente`, fase 1). Recibe el historial del chat y responde en
español con datos del hogar activo. Solo lectura en esta fase.

## Estructura

- `index.ts`: cableado (env, Anthropic, BD de uso por RPC de service_role). Sin lógica.
- `handler.ts`: auth, hogar, validación, límite diario, fallo del modelo y respuesta. Dependencias inyectadas.
- `core.ts`: núcleo. Bucle de tool use, registro de herramientas y topes. No conoce ninguna skill.
- `skills/registry.ts`: lista de skills. Añadir una skill = carpeta nueva + una línea aquí.
- `skills/consulta/`: skill de lectura (eventos, rutinas, listas, tareas, personas, fecha). Las herramientas
  llaman en proceso a los casos de uso de `api` con el JWT del usuario (RLS, ACL y hogar activo).
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

## Despliegue (lo ejecuta Damian; no se despliega desde el repo)

```sh
supabase secrets set KITO_MODEL=claude-haiku-5-5        # opcional
supabase functions deploy asistente --no-verify-jwt
```

Requiere antes la migración `0036_assistant_usage` (`supabase/migrations/`). Para retirar la función en
producción: primero `supabase functions delete asistente`, después `scripts/supabase/rollback/rollback_0036.sql`.

## Tests

```sh
deno check supabase/functions/asistente/index.ts
deno test --no-prompt --allow-env supabase/functions/asistente/tests/
```

`ci.sh` ejecuta estos checks junto con el resto de la suite local.

## Límites conocidos (fase 1)

- Las herramientas de fecha de eventos convierten `AAAA-MM-DD` a medianoche de la zona del usuario.
- La clave `modelo` por skill (p. ej. `KITO_MODEL_MENUS`) aún no está implementada; todas usan `KITO_MODEL`.
- Sin tarjetas estructuradas: solo texto (`tarjetas: []`). Llegan con la fase 2.
