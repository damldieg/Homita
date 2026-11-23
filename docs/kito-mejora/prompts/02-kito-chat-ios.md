Nuevo change dorch `kito-chat-ios` (Homita). Paso 2 de 6 de la mejora de Kito: cómo se ve y cómo habla Kito en la app. Damian (2026-11-23): «el chat es muy sobrio y poco amable»; el objetivo es que sea cálido y con la identidad de Homita. Solo Control iOS (`apps/control-ios`), sin cambios de backend. Puede ir en paralelo al paso 1.

## Contexto
Te paso `brief.md` (hallazgos 11 y 13, propuesta de tono). Código actual en `Sources/ControlKit/Kito/` (`KitoChatView`, `KitoStore`, `KitoModels`, `KitoAPI`, `KitoHistoryStore`, `KitoButton`). El contrato de la Edge ya devuelve `{texto, tarjetas, uso:{usados, limite}}`; hoy la app ignora `tarjetas`.

## Hallazgo
`KitoChatView` usa colores y controles del sistema (`Color.accentColor.opacity(0.18)`, `Color.secondary.opacity(0.12)`, `.roundedBorder`, `ProgressView`), mientras el resto de la app usa el tema de Homita (`Theme/Palette.swift`: fondo crema `background`, `surface`, `accent` terracota, `accentSoft`, `sage`, `ink`; componentes de `Theme/HomitaUI.swift` y `HomitaComponents.swift`: `HomitaCard`, `HomitaChipButton`, `HomitaEmptyState`, `HomitaToast`; fuentes de `HomitaFont`). El chat parece otra app.

## Qué hacer
1. **Change dorch.** `.dorch/changes/kito-chat-ios/` con `brief.md`, `plan.md` tuyo y `status.md` (`approved: yes`, Damian 2026-11-23; `authorized:` vacío). Rama `dc/kito-chat-ios` desde `origin/master`, worktree `../Homita-kito-chat-ios`.
2. **Diseño con el tema de Homita** (lo más importante de este paso):
   - Fondo `Palette.background`; burbujas de Kito en `surface` con borde `line` y avatar redondo de Urki (28 pt) a la izquierda, agrupando mensajes seguidos (avatar solo en el último del grupo); burbujas del usuario en `accentSoft` con texto `ink`, esquinas de 18 pt con la esquina de la «cola» más cerrada.
   - Cabecera propia: avatar de Urki (36 pt), «Kito» y debajo «Tu ayudante de casa» en `inkSoft`; botón cerrar y menú (borrar conversación) con el estilo de la app.
   - Barra de entrada: campo redondeado en `surface` sobre `backgroundSunken`, botón de enviar circular `accent` que solo se activa con texto, y hueco reservado a la izquierda del enviar para el micro del paso 3.
   - Fuentes de `HomitaFont`, separación entre grupos, fecha relativa («Hoy», «Ayer») como separador cuando cambia el día.
   - Animación suave al entrar cada mensaje (respetando «Reducir movimiento») y háptico ligero al recibir respuesta.
   - Modo oscuro correcto con los tokens de `Palette` (nada de colores fijos).
   - Si el asset `UrkiAvatar` falta, el mismo fallback de huella que `KitoButton`.
3. **Bienvenida** (chat vacío): avatar grande de Urki, «¡Hola, {nombre}! Soy Kito.» y una línea amable de qué sabe hacer hoy (p. ej. «Pregúntame qué tienes hoy, qué hay pendiente o cómo se hace algo en Homita.»). Saludo según la hora («Buenos días», «Buenas tardes», «Buenas noches»). Debajo, 3–4 **sugerencias** tocables que se envían al tocarlas: «¿Qué tengo hoy?», «¿Qué tareas tengo pendientes?», «¿Qué rutinas tengo mañana?», «¿Qué hay en la lista de la compra?». Las sugerencias salen de una lista en código (`KitoSuggestions`) para poder cambiarlas por skill más adelante.
4. **Burbujas**: Markdown ligero con `AttributedString(markdown:, options: .inlineOnlyPreservingWhitespace)` (negrita, cursiva, enlaces) y listas con guiones mostradas como lista; si el parseo falla, texto plano. Avatar pequeño de Urki junto a las respuestas. Hora del mensaje en accesibilidad, no visible.
5. **Escribiendo…**: en vez del `ProgressView` suelto, una burbuja de Kito con tres puntos animados («Kito está pensando»), respetando «Reducir movimiento».
6. **Mensajes de error con la voz de Kito**, en `KitoStore.message(for:)` y en la UI como burbuja de sistema (no texto rojo suelto), con botón «Reintentar» que reenvía el último mensaje sin duplicarlo en el historial: 429 «Por hoy ya hemos hablado mucho. Mañana sigo aquí.», 502/5xx «Me he despistado un momento. ¿Lo intentamos otra vez?», red «Ahora mismo no tengo conexión.», 404 hogar, sesión caducada. Los textos en un solo sitio.
7. **Aviso de cupo**: cuando `uso.limite - uso.usados <= 10`, una línea discreta bajo la entrada: «Te quedan N mensajes hoy.»
8. **Tarjetas** (base para los pasos 5–6 y para menús): `KitoReply` decodifica `tarjetas` como `[KitoCard]` con `tipo` y payload libre (`[String: JSONValue]`). `KitoCardRenderer` elige vista por `tipo`; un tipo desconocido se muestra como su campo `texto` o se omite, nunca rompe el decode. Las tarjetas se guardan en el historial con el mensaje (historial antiguo sin tarjetas sigue cargando). En este paso no hay ningún tipo concreto todavía; añade uno de prueba solo en tests.
9. **Historial**: botón «Borrar conversación» en la barra del chat (con confirmación), que limpia el historial local de ese usuario y hogar.
10. **Accesibilidad**: etiquetas VoiceOver en sugerencias, reintentar y borrar; Dynamic Type sin cortes.

## Tests (`Tests/ControlTests/KitoTests.swift` o nuevo `KitoChatTests.swift`)
- Decode de `KitoReply` con tarjetas de tipo conocido, desconocido y sin `tarjetas`.
- Historial antiguo sin tarjetas → carga.
- Textos de error por código.
- Reintentar no duplica el mensaje del usuario.
- Aviso de cupo en el umbral (10 sí, 11 no).
- Markdown: negrita y lista → atribuidos; texto inválido → plano.

## Verificación
`swift test` en `apps/control-ios` en verde (base actual + nuevos, 0 fallos) y `xcodebuild build -scheme ControlApp` Debug y Release en verde. Capturas del chat vacío, con conversación y con error en el simulador, en modo claro y oscuro.

## Reglas
- Nada en producción. Sin push ni PR sin `authorized: push pr gh` en status.md. Sin merge. Sin dependencias de terceros.
- Commits en español, estilo `Área: frase`, con `Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>`.

## Al terminar, infórmame de
Hashes, tests antes/después, builds y las capturas.
