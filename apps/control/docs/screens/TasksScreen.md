# Screen: TasksScreen

## Descripción
Muestra las tareas individuales. Puede funcionar en modo "Global" (todas las tareas de todas las listas) o en modo "Detalle de Lista" (tareas de una lista específica).

## Funcionamiento
- Filtra tareas por lista si se proporciona un ID.
- Permite crear tareas rápidamente mediante un campo de texto en la cabecera (solo en modo lista).
- Muestra las tareas divididas en Pendientes y Completadas (tachadas).
- Permite marcar tareas como completadas, eliminarlas o reordenarlas.
- En modo lista, permite acceder a los ajustes de la lista.

## Endpoints Llamados
- `GET /task`: Listar tareas (opcionalmente filtradas por `task_list_id`).
- `POST /task/create`: Crear tarea.
- `PATCH /task/complete`: Alternar estado de completado.
- `PATCH /task/order`: Cambiar orden de las tareas.
- `DELETE /task/delete`: Eliminar tarea.

## Ficheros de Código
- `app/android/app/src/main/java/com/lito/planify/ui/screens/TasksScreen.kt`
- `app/android/app/src/main/java/com/lito/planify/viewmodel/TaskViewModel.kt`
