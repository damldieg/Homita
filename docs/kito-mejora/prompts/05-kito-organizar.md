Nuevo change dorch `kito-organizar` (Homita). Paso 5 de 6 de la mejora de Kito = fase 2 del plan de Kito (escrituras). Backend: Edge `asistente`. Requiere el paso 1 (`kito-calidad-consulta`) en master. Desbloquea la skill `menus` del planificador de comidas.

## Contexto
Te paso `brief.md` y `plan-kito.md` (plan de Kito del 2026-11-20), sección «Fase 2: acciones y voz»: tabla de **campos indispensables** por elemento y regla de calendarios («de quién es» = con quién se comparte, opción a de Damian). Léelos enteros. Regla de oro: Kito no tiene tablas ni RPC propias; todo va por `api/usecases/*` con el JWT del usuario (RLS, ACL `can_edit`, catálogo del hogar), así que un 403 es un 403 de verdad.

## Qué hacer
1. **Change dorch.** `.dorch/changes/kito-organizar/` (brief, plan tuyo, status `approved: yes` por las decisiones del 2026-11-20 y 2026-11-23, `authorized:` vacío). Rama `dc/kito-organizar` desde `origin/master`, worktree `../Homita-kito-organizar`.
2. **Skill `organizar`** (`skills/organizar/index.ts`, registrada en `skills/registry.ts`, núcleo intacto salvo lo del punto 4). Herramientas, cada una con `strict: true` y los campos indispensables como `required`:
   - Listas: `crear_lista`, `editar_lista`, `borrar_lista`.
   - Tareas: `crear_tarea` (título + lista; opcionales personas, prioridad, vence), `editar_tarea`, `completar_tarea` (y descompletar), `borrar_tarea`.
   - Eventos: `crear_evento` (título + inicio + calendario; opcionales fin, personas, alarma, descripción), `editar_evento`, `borrar_evento`.
   - Rutinas: `crear_rutina` (título + calendario + hora + frecuencia/días), `editar_rutina`, `borrar_rutina`.
   - Calendarios: `crear_calendario` (nombre + con quién se comparte; «solo conmigo» vale; tras crear, `POST /calendar/user` por cada cuenta y `PATCH /calendar/user` si se pide edición; sin decir permiso → solo lectura; miembros sin cuenta no se pueden añadir y Kito lo explica), `editar_calendario`, `borrar_calendario`.
   - Ediciones: la API exige campos completos (p. ej. nombre y color del calendario). La herramienta lee el elemento actual y rellena lo que no cambia; el modelo solo manda lo que cambia.
   - Revalidación en servidor: si falta un indispensable, la herramienta devuelve `{falta:["lista"]}` sin llamar a la API y Kito lo pregunta. Nombres («lista Compra», «Lucía») se resuelven a ids con la ficha de contexto o las herramientas de lectura; si hay más de uno, Kito ofrece las opciones.
   - Idempotencia: en altas que lo admiten (`client_request_id`, 0035: tareas y listas) usa un id derivado del `tool_use.id`, para que un reintento del bucle no duplique.
   - Errores del `api` traducidos: 403 «No tienes permiso de edición en {calendario/lista}.», 404 «Ya no existe.», 400 con el motivo.
3. **Confirmación**. Crear o editar **un** elemento se ejecuta directamente. Borrar cualquier cosa, o tocar más de un elemento en una petición, **no se ejecuta**: la herramienta devuelve una tarjeta `confirmacion` `{tipo:"confirmacion", id, texto:"¿Borro la lista «Compra» y sus 12 tareas?", acciones:[{op, args}], token, caduca}`.
   - `token` = HMAC-SHA256 con el secreto nuevo `KITO_CONFIRM_SECRET` sobre `{uid, home_id, acciones, exp}` (exp = 10 min), en base64url. Sin el secreto, las herramientas que necesitan confirmación responden «No puedo borrar desde aquí ahora mismo» (falla cerrada); las altas siguen funcionando.
   - Endpoint `POST /asistente/confirmar` `{token}` con el mismo Bearer y `X-Home-Id`: verifica firma, caducidad, uid y hogar; ejecuta las acciones en orden con los casos de uso; devuelve `{texto, cambios}`. **No** llama al modelo ni gasta cupo. Token reutilizado → idempotente si ya se ejecutó (guarda nada en BD: basta con que borrar lo ya borrado devuelva 404 traducido a «Ya estaba hecho»).
   - `POST /asistente/cancelar` no hace falta: cancelar es solo de la app.
4. **Núcleo**: `RunResult.tarjetas` se rellena con las tarjetas que devuelvan las herramientas (campo `tarjeta` reservado en el resultado de herramienta; el modelo recibe solo un resumen, «propuesta enviada al usuario para confirmar»). La respuesta gana `cambios: [{tipo: "tarea"|"lista"|"evento"|"rutina"|"calendario", id, op: "crear"|"editar"|"borrar"}]` para que la app recargue. Son cambios aditivos al contrato.
5. **Instrucciones de `organizar`**: pide los indispensables que falten (todos a la vez, en una frase), no inventa valores, confirma en una frase lo que ha hecho («Hecho: tarea «Comprar pan» en Compra para mañana.»), y para borrados explica que ha dejado la confirmación en pantalla. Las instrucciones de `consulta` dejan de decir «aún no puedo».
6. **Uso**: las escrituras cuentan como un mensaje normal; la confirmación no.

## Tests Deno (falsos de casos de uso)
Cada herramienta con datos completos llama al caso de uso correcto con el JWT; faltan indispensables → `{falta}` sin llamar; ambigüedad de nombre; edición rellena campos no cambiados; 403/404/400 traducidos; borrado → tarjeta con token y sin llamada al `api`; confirmar con token válido ejecuta y devuelve `cambios`; token caducado, manipulado, de otro uid o de otro hogar → 403 sin ejecutar; sin `KITO_CONFIRM_SECRET` → borrados desactivados y altas ok; reintento con mismo `tool_use.id` no duplica tareas; `cambios` y `tarjetas` en la respuesta; confirmar no consume cupo ni llama al modelo.

## Verificación
`deno check`, `deno test` de `asistente` y `scripts/supabase/ci.sh` en verde. Añade a `scripts/kito/eval.ts`: «apúntame comprar pan» (debe preguntar la lista si hay varias), «crea una tarea Llamar al dentista en Casa para el viernes», «borra la lista Pruebas», «crea un calendario Fútbol» (debe preguntar con quién se comparte), «cambia la cena del jueves a las 21:30».

## Reglas
- Nada en producción: el secreto `KITO_CONFIRM_SECRET` lo crea Damian (`supabase secrets set KITO_CONFIRM_SECRET=$(openssl rand -base64 32)`); documéntalo en el README de la función. Sin push ni PR sin `authorized: push pr gh`. Sin merge.
- Commits en español, estilo `Área: frase`, con `Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>`.
- No leas `~/.homita/supabase.env`.

## Al terminar, infórmame de
Hashes, tests, contrato nuevo (`tarjetas` de `confirmacion`, `cambios`, `/asistente/confirmar`) para el paso 6, comandos de secreto y despliegue para Damian, y desviaciones del plan.
