# Screen: DashboardScreen

## Descripción
Muestra la lista de calendarios del usuario. Permite la gestión y compartición de los mismos.

## Funcionamiento
- Presenta tarjetas con los calendarios disponibles.
- Permite crear, editar y eliminar calendarios.
- Proporciona un modal para gestionar los usuarios invitados a cada calendario y sus roles.

## Endpoints Llamados
- `GET /calendar`: Obtener lista de calendarios.
- `POST /calendar/create`: Crear nuevo calendario.
- `PATCH /calendar/update`: Actualizar calendario.
- `DELETE /calendar/delete`: Eliminar calendario.
- `GET /calendar/user`: Listar invitados.
- `POST /calendar/user`: Invitar usuario.
- `DELETE /calendar/user`: Eliminar invitado.

## Ficheros de Código
- `app/android/app/src/main/java/com/lito/planify/ui/screens/DashboardScreen.kt`
- `app/android/app/src/main/java/com/lito/planify/viewmodel/CalendarViewModel.kt`
