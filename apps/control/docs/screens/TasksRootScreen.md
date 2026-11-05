# Screen: TasksRootScreen

## Descripción
Contenedor principal para la sección de tareas. Implementa la navegación por pestañas (Tabs) superiores para alternar entre la vista de "Listas" y la vista de "Tareas" globales.

## Funcionamiento
- Utiliza un `Scaffold` con un `TopAppBar` que contiene los nombres de las pestañas.
- Gestiona el estado de la pestaña seleccionada y muestra el contenido correspondiente (`TaskListsScreen` o `TasksScreen`).

## Endpoints Llamados
- Ninguno directamente (delega en las pantallas hijas).

## Ficheros de Código
- `app/android/app/src/main/java/com/lito/planify/ui/screens/TasksRootScreen.kt`
