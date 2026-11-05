# Screen: EventListScreen

## Descripción
Muestra la agenda cronológica de eventos. Permite la visualización global o por calendario, así como la creación de eventos de forma manual o asistida por IA.

## Funcionamiento
- Muestra una lista de eventos próximos y pasados.
- **Creación Manual:** Permite introducir título, fecha, hora y alarma de forma explícita.
- **Asistente IA:** El usuario puede describir el evento (ej: "Cena con Juan mañana a las 8pm") y la aplicación utiliza Gemini en el backend para extraer el título y la fecha/hora. Incluye soporte para dictado por voz.
- Permite buscar eventos por texto y filtrar por calendario.
- Gestión de alarmas (recordatorios) para cada evento.

## Endpoints Llamados
- `GET /event`: Listar eventos (con filtros de búsqueda, fechas y calendario).
- `POST /event/create`: Crear evento (envía campo `text` para IA o campos manuales).
- `PATCH /event/update`: Actualizar evento.
- `DELETE /event/delete`: Eliminar evento.
- `PATCH /event/alarm`: Configurar recordatorio.

## Ficheros de Código
- `app/android/app/src/main/java/com/lito/planify/ui/screens/EventListScreen.kt`
- `app/android/app/src/main/java/com/lito/planify/viewmodel/EventViewModel.kt`
- `backend/src/Controllers/EventCreate.php` (Lógica de IA)
- `backend/src/Utils/GeminiClient.php` (Integración con Gemini)
