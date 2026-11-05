# Widget: CalendarWidget

## Descripción
Widget de escritorio para mostrar la agenda de eventos. Ofrece una vista rápida de los próximos 7 días y la lista de eventos.

## Funcionamiento
- **Cabecera:** Muestra una barra superior con los próximos 7 días. Los días con eventos pendientes tienen un indicador rojo semitransparente con el número de eventos. Un clic general en la cabecera abre la aplicación en la vista de eventos global.
- **Lista de Eventos:** Muestra los eventos recientes o próximos. Destaca los eventos pasados oscureciéndolos, mientras que los eventos futuros conservan colores y muestran el color del calendario al que pertenecen.
- **Etiquetas de Tiempo:** Incluye tiempo relativo para los eventos venideros (e.g., "Faltan 2 horas", "En 3 días").
- **Actualización y Sincronización:**
  - El widget actualiza sus datos en segundo plano mediante `AlarmManager` usando `setAndAllowWhileIdle` cada 15 minutos para asegurar precisión incluso en modo Doze. Actualiza la lista con `notifyAppWidgetViewDataChanged`.
  - Cuando el usuario abre o reanuda la aplicación principal, se emite un broadcast con la acción `ACTION_CLEAR_CACHE` desde `onResume` en `MainActivity`. Al recibirse, se ejecuta `WidgetViewsFactory.clearCache` el cual resetea el tiempo de la última consulta y vacía la caché en memoria para forzar una sincronización y renderizado completamente actualizados.
- **Caché:** Descarga información del endpoint `/event` (vía `RetrofitClient`) con un token guardado localmente (vía `SessionManager`). Guarda estos datos usando SharedPreferences (formato JSON) para evitar peticiones redundantes.

## Endpoints Llamados (Fondo)
- `GET /event`: Listar eventos (parámetros de límite y de widget activados).

## Ficheros de Código
- `app/android/app/src/main/java/com/lito/planify/widget/CalendarWidgetProvider.kt`
- `app/android/app/src/main/java/com/lito/planify/widget/WidgetRemoteViewsService.kt`
- `app/android/app/src/main/java/com/lito/planify/util/AlarmHelper.kt`
