Nuevo change dorch `kito-organizar-ios` (Homita). Paso 6 de 6 de la mejora de Kito: la app pinta la confirmación de Kito y se refresca tras sus cambios. Solo Control iOS. Requiere en master los pasos 2 (`kito-chat-ios`, `KitoCardRenderer`) y 5 (`kito-organizar`, contrato de `confirmacion`, `cambios` y `/asistente/confirmar`).

## Contexto
Te paso `brief.md`. Lee el README de `supabase/functions/asistente` en master para el contrato exacto que dejó el paso 5.

## Qué hacer
1. **Change dorch.** `.dorch/changes/kito-organizar-ios/` (brief, plan tuyo, status `approved: yes` Damian 2026-11-23, `authorized:` vacío). Rama `dc/kito-organizar-ios` desde `origin/master`, worktree `../Homita-kito-organizar-ios`.
2. **Tarjeta `confirmacion`** en `KitoCardRenderer`: el texto de la propuesta y botones «Confirmar» (destructivo, rojo) y «Cancelar». Confirmar llama a `KitoAPI.confirm(token:)` → `POST asistente/confirmar`; mientras tanto, botones desactivados con progreso. Tras responder, la tarjeta queda resuelta («Hecho» / «Cancelado» / «Ha caducado, pídemelo otra vez») y ese estado se guarda en el historial, para que no se pueda confirmar dos veces ni al reabrir el chat. Caducada (`caduca` pasado) → se muestra resuelta sin llamar.
3. **Recarga tras `cambios`**: tanto en la respuesta normal como en la de confirmar. Publica los cambios (p. ej. `NotificationCenter` o un `KitoChanges` observable inyectado en el entorno) y que los stores de Tareas, Listas, Calendario/Eventos/Rutinas e Inicio recarguen lo afectado al volver a su pestaña o en el acto si están visibles. Reutiliza los métodos de recarga que ya usan los `.refreshable`; no dupliques llamadas.
4. **Avisos locales**: si el cambio afecta a tareas con fecha o eventos con alarma, vuelve a programar con `NotificationPlanner` igual que cuando se edita desde la app.
5. **Accesibilidad**: la tarjeta se anuncia con VoiceOver («Kito pide confirmación: …»), botones con etiquetas claras.

## Tests
Render de `confirmacion` por tipo; confirmar llama al endpoint una vez y guarda el estado; doble toque no duplica; caducada no llama; error 403 del confirmar → estado y texto de error; `cambios` dispara recarga de los stores afectados (con stores falsos); historial con tarjeta resuelta se recarga resuelta.

## Verificación
`swift test` (0 fallos) y `xcodebuild build -scheme ControlApp` Debug y Release. Prueba en simulador contra el stack local: «apúntame comprar pan en Compra» → aparece en Tareas sin tirar para refrescar; «borra la lista Pruebas» → tarjeta → Confirmar → desaparece.

## Reglas
- Nada en producción. Sin push ni PR sin `authorized: push pr gh`. Sin merge. Sin dependencias de terceros.
- Commits en español, estilo `Área: frase`, con `Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>`.

## Al terminar, infórmame de
Hashes, tests antes/después, builds y resultado de la prueba en simulador.
