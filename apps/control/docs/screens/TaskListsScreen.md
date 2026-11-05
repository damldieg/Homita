# Screen: TaskListsScreen

## Descripción
Muestra la lista de contenedores de tareas (listas de tareas) del usuario. Permite crear, editar y compartir estas listas.

## Funcionamiento
- Lista las carpetas de tareas con sus colores identificativos.
- Al hacer clic en una lista, navega al detalle de tareas de esa lista.
- Permite abrir un diálogo para crear o editar una lista (Nombre, Color, Ordenación).
- Gestiona la compartición de listas mediante un modal de usuarios invitados.

## Endpoints Llamados
- `GET /task-list`: Obtener todas las listas.
- `POST /task-list/create`: Crear nueva lista.
- `PATCH /task-list/update`: Actualizar lista existente.
- `DELETE /task-list/delete`: Eliminar lista.
- `GET /task-list/user`: Ver usuarios con acceso.
- `POST /task-list/user`: Invitar usuario por email.
- `DELETE /task-list/user`: Revocar acceso a un usuario.

## Ficheros de Código
- `app/android/app/src/main/java/com/lito/planify/ui/screens/TaskListsScreen.kt`
- `app/android/app/src/main/java/com/lito/planify/viewmodel/TaskListViewModel.kt`
