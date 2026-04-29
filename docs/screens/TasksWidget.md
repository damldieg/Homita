# Widget: TasksWidget

## Descripción
Widget de escritorio para visualizar y gestionar las tareas pendientes.

## Funcionamiento
- **Cabecera:** Muestra el título de la lista de tareas actualmente seleccionada, el conteo de tareas y un color representativo. Dispone de botones para rotar interactivamente a través de todas las listas de tareas del usuario sin abrir la aplicación principal (`ACTION_NEXT_LIST` y `ACTION_PREV_LIST`).
- **Lista de Tareas:** Muestra tareas de la lista seleccionada.
- **Interacción:** Las tareas se pueden marcar directamente como completadas tocando el círculo; esto envía una petición rápida al servidor y refleja la confirmación visual en el widget, sin necesidad de lanzar la aplicación completa.
- **Actualización:** Se nutre de actualizaciones planificadas cada 15 minutos mediadas por `AlarmManager` (`setAndAllowWhileIdle`) para asegurar que el contenido está sincronizado con el backend, incluso si el dispositivo entra en reposo.

## Endpoints Llamados (Fondo / Clicks)
- `GET /task`: Para refrescar todas las tareas incompletas en segundo plano.
- `GET /task-list`: Para recopilar la estructura de las listas del usuario y habilitar la paginación.
- `PATCH /task/complete`: Para completar una tarea tras interactuar con ella directamente desde la lista del widget.

## Ficheros de Código
- `app/android/app/src/main/java/com/lito/planify/widget/TasksWidgetProvider.kt`
- `app/android/app/src/main/java/com/lito/planify/widget/TasksWidgetRemoteViewsService.kt`
- `app/android/app/src/main/java/com/lito/planify/util/AlarmHelper.kt`
