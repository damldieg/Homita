# Documentación de Pantallas: Planify

Planify es una aplicación de organización personal multi-usuario. Utiliza un sistema de navegación basado en una barra inferior (Bottom Navigation) y pestañas superiores (Tabs) para separar contextos de Tareas y Calendarios.

## 1. Arquitectura de Navegación Global

- **Bottom Navigation (3 secciones):**
  1. **Tareas:** Icono `CheckCircle`. Ruta inicial.
  2. **Calendarios:** Icono `DateRange`.
  3. **Perfil:** Icono `Person`.
- **Estilo Visual:** Glassmorphism (fondo translúcido con desenfoque), esquinas rectas para elementos de lista (`RectangleShape`), y colores vibrantes sobre fondos claros.

---

## 2. Flujo de Autenticación

### 2.1. WelcomeScreen
- **Función:** Pantalla de aterrizaje inicial.
- **UI:** Logotipo gigante, nombre "Planify" en tipografía Display.
- **Acciones:** Botón "Iniciar sesión" (Primario), Botón "Registrarse" (Tonal, condicional según `/config`).

### 2.2. LoginScreen
- **Función:** Acceso para usuarios existentes.
- **Campos:**
  - `Email`: Teclado optimizado para correo (`@` visible).
  - `Contraseña`: Input con icono de "ojo" para alternar visibilidad.
- **Acción:** Botón "Entrar". Limpia errores al navegar atrás.

### 2.3. RegisterScreen
- **Función:** Creación de nuevas cuentas.
- **Campos:**
  - `Nombre`: Teclado con capitalización automática de palabras.
  - `Email`: Teclado optimizado para correo.
  - `Contraseña`: Input con icono de visibilidad.
- **Acción:** Botón "Registrarse".

---

## 3. Módulo de Tareas (`TasksRootScreen`)

Esta sección utiliza dos pestañas superiores:

### 3.1. Tab: Listas (`TaskListsScreen`)
- **Propósito:** Gestión de "carpetas" o contenedores de tareas (ej: Compra, Trabajo).
- **UI:** Tarjetas con indicador de color lateral izquierdo. Botón/Tarjeta de "Añadir Lista".
- **Modal "Nueva/Editar Lista":**
  - Campo `Nombre`.
  - Campo `Orden`: RadioButtons para elegir "Por Actividad" (`updated_at`) o "Alfabético" (`title`).
  - Selector `Color`: `HueColorPicker` (slider de arcoíris).

### 3.2. Tab: Tareas (`TasksScreen` - Vista Global)
- **Propósito:** Ver todos los pendientes de todas las listas.
- **Filtro:** Icono de embudo para filtrar por una lista específica o ver "Todos".
- **Añadido Rápido:** Si hay una lista filtrada, muestra un campo "Añadir nueva tarea..." con un botón `+` en la cabecera.
- **Listado:** Tareas pendientes arriba, completadas abajo (tachadas).
- **Interacción:** Checkbox para marcar/desmarcar.

---

## 4. Módulo de Calendarios (`CalendarsRootScreen`)

Dos pestañas superiores:

### 4.1. Tab: Calendarios (`DashboardScreen`)
- **Propósito:** Gestión de calendarios compartibles.
- **UI:** Listado de tarjetas con color identificativo.
- **Modal "Nuevo Calendario":** Campos `Nombre` y selector de `Color`.

### 4.2. Tab: Eventos (`EventListScreen` - Vista Global)
- **Propósito:** Agenda cronológica de todos los eventos.
- **Filtros:** Búsqueda por texto (lupa) y filtro por Calendario específico.
- **Tarjetas de Evento:** Muestran Título, Fecha (con día de semana, ej: "Lun, 20 Abr") y **Fecha Relativa** ("En 2 h", "En 15 min", "Mañana").

---

## 5. Gestión de Detalles y Ajustes

### 5.1. Pantalla de Tareas de una Lista (`TasksScreen` - Detalle)
- Título de la lista, icono de Ajustes.
- Entrada rápida de tareas siempre visible.

### 5.2. Pantalla de Eventos de un Calendario (`EventListScreen` - Detalle)
- Título del calendario, icono de Ajustes.
- Botón flotante (FAB) para añadir eventos.

### 5.3. Modal de Ajustes (Calendarios y Listas)
Diseño de dos pestañas internas:
1. **General:** Editar Nombre, Color, y Orden (solo en listas). Botón "Guardar".
2. **Usuarios:** 
   - Campo `Email` (teclado correo) + Botón `+` (alineado a la base).
   - Lista de usuarios con su rol ("Propietario" / "Invitado") e icono de borrar para expulsar.
   - Botón inferior "Cerrar" (sin acciones secundarias para evitar confusión con el guardado del formulario general).

---

## 6. Creación y Edición de Eventos

### 6.1. Modal "Nuevo Evento"
- **Modo Manual:** Título, selector de Calendario (si es global), y selector unificado de Fecha/Hora (abre diálogos nativos secuencialmente).
- **Modo Asistente IA:** Switch para activar. Área de texto grande "Describe el evento y la fecha". Icono de **Micrófono** para dictado por voz nativo.

### 6.2. Modal "Editar Evento"
- Título, Fecha/Hora, Botón "Guardar" y opción de "Borrar".

---

## 7. Perfil de Usuario (`ProfileScreen`)

- **Información:** Muestra Nombre y Email actuales.
- **Edición:** Activa campos de texto para actualizar Nombre, Email o Contraseña (con las optimizaciones de teclado antes mencionadas).
- **Crash Reporter:** Si hubo un cierre inesperado, muestra una tarjeta roja para ver o borrar el log de errores.
- **Acciones:** Botón "Guardar", "Editar" y "Salir" (limpia caché de widgets).

---

## 8. Widgets de Escritorio

### 8.1. Widget Calendario
- Vista de 7 días con números de eventos en badges rojos semi-trasparentes (90% opacidad).
- Lista de próximos eventos (clic para ir al calendario específico).
- Caché de 1 minuto.

### 8.2. Widget Tareas
- Cabecera con nombre de lista y flechas para rotar entre listas.
- Lista de tareas pendientes (clic en círculo para completar e hidratar).
- Botón "Gestionar Tareas" (abre la lista actual en la app).
- Caché de 1 minuto.
