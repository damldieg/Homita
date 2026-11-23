# Mejorar Kito: contexto, skills, herramientas, tono y mensaje

Pedido por Damian el 2026-11-23: antes de seguir con el planificador de comidas, mejorar el Kito que ya
existe. Auditoría hecha sobre `origin/master` aabc6f7 (Kito = fase 1: Edge `asistente` + chat iOS).
Este documento es la base de los changes `kito-calidad-consulta`, `kito-chat-ios`, `kito-voz`,
`kito-ayuda`, `kito-organizar` y `kito-organizar-ios`. Se pasa a dorch junto con el prompt de cada paso.

## Qué hay hoy en master
- `supabase/functions/asistente`: `core.ts` (bucle de tool use, `SYSTEM_BASE` de 4 líneas,
  `max_tokens: 1024`, sin `effort`, sin caché, herramientas en serie), `handler.ts` (auth, hogar, tope
  50/día con `assistant_consume`/`assistant_record_usage` de 0036, refund si falla el modelo),
  `index.ts` (fetch a Anthropic, 30 s de timeout, sin reintento), `skills/registry.ts` con **una sola
  skill**, `consulta`: `ver_eventos`, `ver_rutinas`, `ver_listas`, `ver_tareas`, `ver_personas`,
  `fecha_actual`. Todas en proceso sobre `api/usecases/*` con el JWT del usuario.
- iOS `Sources/ControlKit/Kito/`: `KitoButton`, `KitoChatView` (texto plano con `Text`, saludo fijo),
  `KitoStore`, `KitoHistoryStore` (JSON local), `KitoAPI`. `KitoReply` ignora `tarjetas`.

## Hallazgos

### Contexto
1. El modelo no sabe la fecha, ni quién es el usuario, ni cuál es su persona del hogar, ni qué
   calendarios y listas hay. Gasta vueltas (`fecha_actual`, `ver_personas`, `ver_listas`) en cada
   pregunta y no puede resolver «mis…»: por eso enseñó rutinas que no eran de Damian (fallo 2026-11-21).

### Herramientas
2. `ver_eventos` no manda `routine=false`: `GET /event` materializa rutinas y devuelve sus ocurrencias
   mezcladas. Kito llamó «evento» a una rutina (fallo 2026-11-21).
3. Devuelven el JSON crudo del `api` (hasta 20.000 caracteres por resultado): ruido, coste y latencia.
4. No hay `ver_calendarios` ni detalle de evento/tarea; `ver_tareas` no filtra por pendientes,
   vencidas (`due_at`, 0041) ni prioridad (0037), y nada filtra por persona.
5. «¿Qué rutinas tengo mañana?» no se puede responder bien: la regla de recurrencia solo vive en SQL
   (`materialize_routines_for`, 0003). Solución sin duplicar lógica: `GET /event` con `routine=true` y
   rango de fechas devuelve las ocurrencias ya materializadas.
6. Se ejecutan en serie; sin `strict: true` en los esquemas.

### Llamada al modelo
7. Haiku 5.5 piensa por defecto (adaptativo, effort por defecto `medium`) y el pensamiento cuenta en
   `max_tokens: 1024`: respuestas cortadas. `stop_reason` `max_tokens` y `refusal` no se tratan
   (Haiku 5.5 no tiene fallback de servidor ante `refusal`).
8. Sin prompt caching: `tools` + `system` son estables y se reenvían en cada vuelta de cada mensaje.
9. Sin reintento ante 429/529/5xx ni presupuesto total de la petición.

### Tono y mensaje
10. `SYSTEM_BASE` sin personalidad ni reglas de formato para móvil y voz. Las instrucciones de
    `consulta` dicen «todavía no puedo» a cualquier escritura, sin ofrecer alternativa.
11. El chat usa colores y controles del sistema en vez del tema de Homita (Damian: «muy sobrio y poco
    amable»). La app pinta Markdown en crudo (`**`, viñetas), el saludo es fijo, no hay sugerencias de preguntas,
    y los errores (429, 502, red) no suenan a Kito. No avisa cuando quedan pocos mensajes.

### Skills
12. Solo existe `consulta`. Falta `ayuda` («¿cómo comparto una lista?», del pedido original del
    2026-11-20) y `organizar` (fase 2: escrituras), de la que depende la skill `menus` del planificador.
13. `disponible()` siempre devuelve `true`; la clave `modelo` por skill sigue sin implementar.

## Tono (elegido por Damian el 2026-11-23: «Cercano y sobrio»)
Kito es Urki, el perro de la familia, hecho asistente. Habla en español de España, de tú, cercano y
alegre sin pasarse: frases cortas, va al grano, un guiño perruno ocasional como mucho (nunca «guau» en
cada mensaje, nunca emojis). Nunca se inventa datos: si no lo sabe, lo dice y propone cómo averiguarlo.
Formato para móvil y voz: 1–4 frases o una lista corta; sin tablas, sin títulos; fechas «el martes 24
a las 18:30», «hoy», «mañana».

## Orden de los changes
| # | Change | Qué | Depende de |
|---|---|---|---|
| 1 | `kito-calidad-consulta` | Ficha de contexto, herramientas compactas y nuevas, llamada al modelo robusta con caché, system prompt con tono | — |
| 2 | `kito-chat-ios` | Rediseño cálido con el tema de Homita, bienvenida y sugerencias, Markdown ligero, tarjetas con `KitoCardRenderer` (fallback a texto), mensajes de error y aviso de cupo | puede ir en paralelo a 1 |
| 3 | `kito-voz` | Dictado nativo de iOS (voz → texto) primero, y voz de Kito | 2 |
| 4 | `kito-ayuda` | Skill `ayuda`: guía de la app curada, herramienta `guia_app` | 1 |
| 5 | `kito-organizar` | Skill `organizar` (backend): crear, editar, completar y borrar con el JWT, campos indispensables, confirmación firmada, `cambios` en la respuesta | 1 |
| 6 | `kito-organizar-ios` | Tarjeta `confirmacion`, endpoint de confirmar, recarga de pestañas tras `cambios` | 2 y 5 |

Después: `resumen_dia` (fase 3 de Kito) y `kito-menus` (fase 5 del planificador, necesita 5 y 6).

## Decisiones
- Recomendado por el planner (se aplican salvo que Damian diga otra cosa): contexto en el último
  mensaje de usuario y no en `system` (los nombres del hogar son datos que escriben los usuarios, no
  instrucciones); effort `low` configurable; crear y editar un solo elemento sin confirmación, borrar o
  tocar varios elementos con tarjeta de confirmación firmada (HMAC, 10 min); la confirmación no gasta
  mensaje del cupo ni llama al modelo.
- Tono: Damian eligió «Cercano y sobrio» el 2026-11-23 (sección «Tono»).

## Reglas de siempre
Nada en producción (ni migraciones ni deploy de Edge ni secretos). Sin push ni PR sin
`authorized: push pr gh` en status.md. Nunca merge. Commits en español, estilo `Área: frase`, con
`Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>`. No leer `~/.homita/supabase.env`.
