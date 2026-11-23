Nuevo change dorch `kito-voz` (Homita). Paso 3 de 6 (adelantado por Damian el 2026-11-23) de la mejora de Kito: hablar con Kito por voz y que Kito responda con voz. Solo Control iOS (`apps/control-ios`), sin cambios de backend. Pedido de Damian el 2026-11-21. Requiere el paso 2 (`kito-chat-ios`) en master: el micro va en su barra de entrada y la limpieza para voz debe casar con su Markdown ligero.

## Decisiones (aceptadas por Damian el 2026-11-21; el 2026-11-23 pidió priorizar el dictado nativo de iOS)
Prioridad: el **dictado voz → texto** (punto 2) es lo que pidió Damian; si el change crece, entrega primero el dictado en un commit propio y la voz de Kito (punto 3) en otro.
- **Reconocimiento de voz nativo de iOS** (`Speech` + `AVAudioEngine`), idioma `es-ES`, `requiresOnDeviceRecognition = true` cuando `supportsOnDeviceRecognition` lo permita (privacidad y sin límite de Apple); si no, reconocimiento en servidor de Apple.
- **Voz de Kito con `AVSpeechSynthesizer`** (en el dispositivo, gratis, sin red). Se elige la mejor voz `es-ES` instalada: premium > enhanced > default. Sin servicios de voz en la nube en este change.
- **Cuándo habla Kito:** si el mensaje se dictó por voz, Kito responde en voz alta automáticamente. Si se escribió, no. Además, un botón de altavoz en cada respuesta para oírla, y un ajuste «Kito responde con voz: Solo si le hablo / Siempre / Nunca» (por defecto «Solo si le hablo»), guardado en `UserDefaults`.

## Qué hacer
1. Brief en `.dorch/changes/kito-voz/brief.md` con lo de arriba y los criterios de abajo; `status.md` con `approved: yes` (Damian aceptó estas decisiones el 2026-11-21). Rama `dc/kito-voz` desde `origin/master`, worktree `../Homita-kito-voz`.
2. **Dictado** (`Sources/ControlKit/Kito/KitoSpeechRecognizer.swift`, `@Observable`):
   - Botón de micrófono junto al campo de texto de `KitoChatView`. Tocar para empezar a hablar, tocar otra vez para terminar. Además termina solo tras ~1,5 s de silencio.
   - La transcripción parcial se ve en vivo en el campo de texto. Al terminar se envía sola (con `origen: .voz`). Si sale vacía, no se envía nada.
   - Indicador visual mientras escucha (micro animado o nivel de audio) y botón para cancelar sin enviar.
   - Permisos: pide los de micrófono y reconocimiento la primera vez que se pulsa el micro, no al abrir el chat. `NSMicrophoneUsageDescription` y `NSSpeechRecognitionUsageDescription` en `ControlApp/Info.plist`, con textos en español de España. Si los deniega, mensaje claro con botón a Ajustes y el micro queda desactivado.
3. **Voz de Kito** (`Sources/ControlKit/Kito/KitoSpeaker.swift`):
   - Antes de leer, limpia la respuesta para voz: sin Markdown (`**`, `#`, viñetas → pausas), sin emojis, sin URLs; las horas «09:30» se leen bien.
   - Al empezar a dictar o al cerrar el chat, Kito se calla en el acto.
   - `AVAudioSession`: `.playAndRecord` con `.defaultToSpeaker` y `.duckOthers` mientras se dicta o habla; se desactiva al terminar para devolver el audio a otras apps. Interrupciones (llamada) → parar sin errores.
4. **Modelo**: `KitoMessage` gana `origen: texto | voz` (persistido en el historial con valor por defecto `texto` para los mensajes ya guardados). `KitoStore.send` lo recibe y, según el ajuste, pide a `KitoSpeaker` que lea la respuesta.
5. **Accesibilidad**: botones de micro y altavoz con etiquetas VoiceOver («Hablar con Kito», «Escuchar respuesta», «Parar»). Con VoiceOver activo, la lectura automática se desactiva para no pisarse.
6. **Tests** (`Tests/ControlTests/KitoVoiceTests.swift`), sin audio real (protocolos inyectables para reconocedor y sintetizador):
   - Limpieza para voz: Markdown, emojis, URLs y horas.
   - Regla de cuándo habla: voz+«Solo si le hablo» → habla; texto+«Solo si le hablo» → no; «Siempre»/«Nunca».
   - Transcripción vacía → no envía; transcripción final → envía con `origen: .voz`.
   - Decodificar historial antiguo sin `origen` → `texto`.

## Verificación
- `swift test` en `apps/control-ios` en verde (base actual + nuevos, 0 fallos).
- `xcodebuild build -scheme ControlApp` Debug y Release en verde.
- Prueba en el iPhone real (el simulador no dicta bien): dictar «¿qué tengo mañana?», ver la transcripción, envío automático, respuesta hablada; escribir un mensaje → no habla; botón de altavoz; cerrar el chat mientras habla → se calla.

## Reglas
- Nada en producción. Sin push ni PR sin `authorized: push pr gh` en status.md. Sin merge.
- Commits en español, estilo `Área: frase`, con `Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>`.
- Sin dependencias de terceros (la app no tiene ninguna).

## Al terminar, infórmame de
Hashes, número de tests (antes/después), resultado de los builds y de la prueba en el iPhone, y qué voz `es-ES` eligió en el dispositivo.
