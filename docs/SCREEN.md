# Documentación de Pantallas: Planify

Planify es una aplicación de organización personal multi-usuario. Utiliza un sistema de navegación basado en una barra inferior (Bottom Navigation) y pestañas superiores (Tabs) para separar contextos de Tareas y Calendarios.

## 1. Arquitectura de Navegación Global

- **Bottom Navigation (3 secciones):**
  1. **Calendarios:** Icono `DateRange`. Ruta inicial (eventos, rutinas y calendarios).
  2. **Tareas:** Icono `CheckCircle`.
  3. **Perfil:** Icono `Person`.
- **Estilo Visual:** fondo degradado neutro claro, tarjetas de cristal translúcidas con esquinas redondeadas que agrupan las filas, tipografía sans en negrita, acento ciruela oscuro y pastillas de día "Hoy" (rojo) / "Mañana" (naranja). Los widgets usan cristal oscuro translúcido sobre el fondo de pantalla y en la pantalla de bloqueo son de solo lectura.

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

Tres pestañas superiores: **Eventos**, **Rutinas** y **Calendarios**. Eventos y rutinas están separados: cada uno tiene su propia vista mensual, listado, formulario y widget; los calendarios son compartidos por ambos.

### 4.1. Tab: Eventos (`EventListScreen` - Vista Global)
- **Propósito:** Agenda cronológica de los eventos (sin sesiones de rutina).
- **Filtros:** Filtro por Calendario específico.
- **UI:** Vista mensual con puntos de color, botón "Nuevo evento" y eventos agrupados por día; los pasados en su propia sección.
- **Tarjetas de Evento:** Muestran Título, hora, calendario y **Fecha Relativa** ("14H 52M", "3D").

### 4.2. Tab: Rutinas (`RoutinesScreen`)
- **Propósito:** Gestión de rutinas semanales.
- **Filtros:** Filtro por Calendario específico.
- **UI:** Vista mensual con las sesiones, botón "Nueva rutina" y rutinas con el mismo diseño de fila que los eventos: título, hora, días y calendario, con el tiempo hasta la próxima sesión. Las pausadas aparecen en su propia sección.
- **Permisos:** Todos los miembros del calendario pueden gestionar las rutinas.
- **Edición:** Las rutinas se editan siempre completas; pausar y borrar conservan el historial.

### 4.3. Tab: Calendarios (`DashboardScreen`)
- **Propósito:** Gestión de calendarios compartibles.
- **UI:** Listado de tarjetas con color identificativo y número de eventos próximos.
- **Modal "Nuevo calendario":** Campos `Nombre`, `Color` y `Mostrar en el widget`.

---

## 5. Gestión de Detalles y Ajustes

### 5.1. Pantalla de Tareas de una Lista (`TasksScreen` - Detalle)
- Título de la lista, icono de Ajustes.
- Entrada rápida de tareas siempre visible.

### 5.2. Pantalla de Eventos de un Calendario (`EventListScreen` - Detalle)
- Título del calendario, icono de Ajustes.
- Botón flotante (FAB) para añadir eventos.

### 5.3. Modal de Ajustes (Calendarios y Listas)
Diseño de dos pestañas internas (selector segmentado):
1. **General:** Editar Nombre, Color, y Orden (solo en listas). Botón "Guardar".
2. **Usuarios:** 
   - Campo `Email` (teclado correo) + Botón `+` (alineado a la base).
   - Lista de usuarios con su rol ("Propietario" / "Invitado") e icono de borrar para expulsar.
   - Botón inferior "Cerrar" (sin acciones secundarias para evitar confusión con el guardado del formulario general).

---

## 6. Formularios

Todos los formularios comparten la misma hoja inferior (`PlanifyFormSheet`): título, campos con el mismo estilo, interruptores sobre fondo suave y botonera fija (borrar · cancelar · guardar). Los componentes comunes están en `ui/components/FormComponents.kt`.

### 6.1. Modal "Nuevo evento"
- **Modo Manual:** Calendario (si es global), Título, Fecha y Hora (diálogos nativos) y Alarma.
- **Modo Asistente IA:** Interruptor para activar. Área de texto "Describe el evento".

### 6.2. Modal "Editar evento"
- Título, Fecha, Hora, Alarma, "Guardar" y "Borrar".

### 6.3. Modal "Nueva rutina" / "Editar rutina"
- Calendario (solo al crear), Título, Días (círculos L–D), Hora, Inicio, Fin opcional, Alarma y Activa (solo al editar).

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

### 8.2. Widget Rutinas
- Mismo diseño que el widget de calendario, pero solo con las sesiones de rutinas.
- Al pulsarlo abre la pestaña Rutinas.

### 8.3. Widget Tareas
- Cabecera con nombre de lista y flechas para rotar entre listas.
- Lista de tareas pendientes (clic en círculo para completar e hidratar).
- Botón "Gestionar Tareas" (abre la lista actual en la app).
- Caché de 1 minuto.
