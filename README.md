# Planify - Android App 📅 ✅

Bienvenido a **Planify**, una aplicación moderna y elegante para la organización personal y multi-usuario. Gestiona tus tareas, colabora en listas compartidas, organiza calendarios y añade eventos usando Inteligencia Artificial y reconocimiento de voz nativo.

## ✨ Características Principales

*   **Autenticación**: Registro e inicio de sesión seguros.
*   **Gestión de Tareas (Tasks)**: Crea listas de tareas, organízalas por orden alfabético o actividad, y marca tareas como completadas.
*   **Calendarios Compartidos**: Crea múltiples calendarios, asígnales colores e invita a otros usuarios a colaborar.
*   **Creación de Eventos con IA**: Describe tu evento mediante texto o voz y deja que la Inteligencia Artificial rellene los datos y fechas por ti.
*   **Personalización y Diseño**: Interfaz moderna usando _Glassmorphism_, selector de colores en arcoíris y tipografías cuidadas.
*   **Widgets de Escritorio**: Consulta tus próximos eventos en el widget de 7 días, o marca tareas directamente desde la pantalla de inicio de tu dispositivo.
*   **Multi-usuario**: Invita a amigos o compañeros de trabajo a listas de tareas y calendarios usando su email.

---

## 🧩 Ecosistema Planify

| Repositorio | Qué es |
|---|---|
| [Planify-Backend](https://github.com/eusonlito/Planify-Backend) | API en PHP y SQLite con los datos de todos |
| [Planify-APP](https://github.com/eusonlito/Planify-APP) | App Android para crear y gestionar calendarios, eventos, rutinas y tareas |
| [Planify-Dashboard](https://github.com/eusonlito/Planify-Dashboard) | Pantalla de pared de solo lectura en un marco digital Android, con la misma cuenta |

---

## 📸 Capturas de Pantalla

### Bienvenida y Autenticación
<p align="center">
  <img src="design/App-Welcome.png" width="24%" />
  <img src="design/Auth-Login.png" width="24%" />
  <img src="design/Auth-Signup.png" width="24%" />
  <img src="design/User-Profile.png" width="24%" />
</p>

### Gestión de Tareas
<p align="center">
  <img src="design/Task-List-List.png" width="24%" />
  <img src="design/Task-List-Detail.png" width="24%" />
  <img src="design/Task-List-All.png" width="24%" />
  <img src="design/Task-List-Create.png" width="24%" />
</p>

### Calendarios y Eventos
<p align="center">
  <img src="design/Calendar-List.png" width="24%" />
  <img src="design/Calendar-Detail.png" width="24%" />
  <img src="design/Calendar-Event-Create.png" width="24%" />
  <img src="design/Calendar-Event-Create-AI.png" width="24%" />
</p>

### Colaboración y Widgets
<p align="center">
  <img src="design/Calendar-User-Update.png" width="24%" />
  <img src="design/Calendar-Widget.png" width="24%" />
  <img src="design/Task-Widget.png" width="24%" />
</p>

---

## 🚀 Requisitos Previos

*   [Android Studio](https://developer.android.com/studio) en una versión compatible con Android Gradle Plugin 9.4, con el SDK de Android 37 instalado.
*   **JDK 17** o superior.
*   Un emulador Android o dispositivo físico ejecutando Android 8.0 (API 26) o superior.
*   Para que la aplicación funcione, es indispensable tener el **Backend** configurado y en ejecución.

## 🛠️ Instalación y Ejecución

El proyecto está dividido en dos partes: el Backend (PHP) y la App de Android (Kotlin).

### 1. Despliegue del Backend
El backend está construido con PHP 8.5 y SQLite. Consulta el repositorio oficial en [Planify-Backend (GitHub)](https://github.com/eusonlito/Planify-Backend) para obtener las instrucciones detalladas de instalación, configuración y ejecución de la base de datos.

### 2. Ejecutar la Aplicación Android

1. **Abrir en Android Studio:**
   Abre el directorio `app/` directamente con Android Studio. Gradle comenzará a descargar las dependencias automáticamente.

2. **Configuración de la URL del Servidor:**
   Asegúrate de que la aplicación esté apuntando a la URL correcta del backend local (generalmente definida en el archivo `local.properties` o en las constantes del proyecto).

3. **Lanzar la App (Android Studio):**
   Selecciona tu dispositivo/emulador en Android Studio y presiona el botón **Run** (▶️) o usa el atajo `Shift + F10`.

---

## 🏗️ Arquitectura y Documentación

Planify ha sido desarrollada nativamente para Android priorizando una arquitectura escalable:

*   **Navegación:** _Bottom Navigation_ global con _Tabs_ superiores para separar módulos de Tareas y Calendarios.
*   **Estilo UI:** Fuerte énfasis en _Glassmorphism_ (desenfoque) y _Material Design_ adaptado para crear un estilo visual consistente y "limpio".
*   Para entender en detalle la arquitectura visual y el enrutamiento interno de las pantallas, revisa el archivo de **[Documentación de Pantallas (SCREEN.md)](docs/SCREEN.md)**.
*   Para información del consumo de APIs, consulta la [Documentación de la API del Backend](https://github.com/eusonlito/Planify-Backend/blob/main/docs/API.md).

---

## 🤝 Contribuir
Al contribuir al desarrollo de la aplicación, por favor asegúrate de respetar las convenciones de nomenclatura, mantener un código limpio e hidratar el diseño base definido en las capturas de pantalla de la carpeta `design/`.

## Rutinas

La pestaña Rutinas (dentro de Calendarios, junto a Eventos y Calendarios) permite repetir cada X días, semanas o meses (por ejemplo, lunes y viernes cada 2 semanas) a una hora común, con fecha de inicio, fin opcional, estado activo y aviso personal. Todos los miembros del calendario pueden gestionar sus rutinas. Eventos y rutinas están separados: cada uno tiene su vista mensual, listado, formulario y widget. Las rutinas se editan completas y los cambios conservan el historial.

Despliega primero la API y aplica `backend/migrations/0006_routine.sql` y `0009_routine_frequency.sql` con el comando de migración del backend. La API genera los próximos 90 días al sincronizar; los avisos del móvil necesitan conexión periódica para renovar ese horizonte. La hora es local y sigue la zona del móvil.

El móvil programa los 450 avisos más próximos y conserva el resto en caché. Cada aviso repone la cola sin necesitar conexión; sincronizar o reiniciar también la renueva.

## Personas

Desde Perfil se crean personas (por ejemplo, los miembros de la familia) con nombre y color, y se asignan una o varias a cada evento o rutina. Las ven y asignan todos los usuarios que comparten algún calendario con quien las creó; solo el creador puede editarlas o borrarlas. Las sesiones de una rutina muestran las personas de la rutina. Requiere la migración `backend/migrations/0007_person.sql`.

## Scripts locales

Los scripts de `scripts/` son locales y están excluidos de Git:

* `scripts/install.sh`: compila el APK release y lo instala en teléfonos conectados por USB.
* `scripts/emulator.sh`: compila e instala la versión debug en el emulador.
* `scripts/git-reset`: utilidad general para reiniciar el historial de un repositorio Git; no despliega la app ni el backend.

El despliegue del backend corresponde a `../backend/scripts/install.sh`. Los scripts de instalación y emulador resuelven sus rutas desde su ubicación, por lo que pueden ejecutarse desde cualquier directorio.
