# Control iOS: documento funcional (estado actual)

Relevamiento de la app gestora **Homita Control** (`apps/control-ios`, iOS 17+, SwiftUI) tal como está hoy. Pensado como entrada para un agente que diseñe wireframes y proponga mejoras de UX y UI: describe pantallas, flujos, formularios, datos y de qué endpoint sale cada cosa. No propone cambios.

Las capturas salen del simulador iPhone 17 contra el stack **local** (cuenta demo `demo@homita.example`, hogar «Hogar de Familia Demo»). Están en `docs/images/ios-auditoria/`.

## 1. Cómo se reproduce

- Config local (no commitear): `apps/control-ios/Config.xcconfig` apuntando a `http://127.0.0.1:54321`.
- Backend local: `scripts/demo.sh up` (reset y seed de la base local, `functions serve`).
- Tests de auditoría: `xcodebuild test -scheme ControlApp -destination 'platform=iOS Simulator,name=iPhone 17'`. El target `ControlAppUITests` recorre la app y adjunta una captura por pantalla.
- Las capturas se extraen del `.xcresult` con `xcrun xcresulttool export attachments`.

## 2. Actores y permisos

| Actor | Qué ve |
|---|---|
| Visitante | Bienvenida, login y registro |
| Miembro | Pestañas con sus datos. Ve Administración del hogar en solo lectura (configuración y administradores) |
| Admin del hogar | Todo: edición de configuración, miembros, invitaciones, accesos y auditoría |

El cliente solo oculta; el servidor decide (403 con mensaje de administrador).

## 3. Mapa de navegación

```
Sin sesión
└── Bienvenida ──┬── Iniciar sesión ──► Login ──► (sesión) Pestañas
                 └── Registrarse ─────► Registro (Nombre, Email, Contraseña, Código opcional)

Con sesión: barra inferior con 5 pestañas
├── Inicio      ── resumen del día; accesos rápidos a Tareas, Rutinas y Eventos; «+» (Crear › Tarea | Evento) y engranaje «Ajustes»
├── Tareas      ── segmentos [Tareas | Listas]
│   ├── Tareas: agrupadas por lista, filtro, botón «+ Nueva tarea»
│   │   └── Editor de tarea (título, lista, prioridad, fecha límite, personas)
│   └── Listas: «Nueva lista» ── Detalle de lista ── «Editar lista» / «Eliminar lista»
├── Calendario  ── segmentos [Eventos | Rutinas | Calendarios]
│   ├── Eventos: «Nuevo evento» ── Detalle de evento
│   ├── Rutinas: «Nueva rutina» ── Editor de rutina (frecuencia, hora, inicio/fin, activa)
│   └── Calendarios: «Nuevo calendario» ── Detalle de calendario
├── Menú        ── segmentos [Semana | Compra | Recetas]
└── Hogar       ── selector de hogar, miembros, «Crear invitación», «Comidas», «Administración»
    └── Administración: Configuración · Administradores · Miembros · Invitaciones · Accesos · Auditoría

Ajustes (hoja que abre el engranaje de Inicio; no es una pestaña)
├── Cuenta (nombre, email, contraseña), cerrar sesión, modo oscuro
├── Personas: «Nueva persona»
├── Inicio: orden y bloques ocultos
├── Notificaciones: avisos, widgets y pantalla de bloqueo
├── Enviar feedback
└── Unirse a un hogar con un código
```

La barra inferior, de izquierda a derecha, es Inicio, Tareas, Calendario, Menú y Hogar (`RootView.swift:155-181`). Ajustes ya no es pestaña: se abre desde el engranaje de Inicio (`InicioView.swift:215`, `RootView.swift:150`, hoja en `:201-202`); sin hogar activo el engranaje se muestra igualmente sobre la pantalla (`RootView.swift:193`).

Cambio de pestaña desde Inicio: «Tareas pendientes» abre la pestaña Tareas; «Rutinas de hoy» y «Hoy · Eventos» abren Calendario en su segmento correspondiente.

## 4. Pantallas, con captura

### 4.1 Entrada sin sesión

| Pantalla | Captura | Qué hay | Acciones |
|---|---|---|---|
| Bienvenida | ![](images/ios-auditoria/01-bienvenida.png) | Logo «H», nombre «Homita», subtítulo «Tu panel de control familiar» | «Iniciar sesión» (primario), «Registrarse» (secundario) |
| Login | ![](images/ios-auditoria/02-login.png) | Campos Email y Contraseña | «Iniciar sesión» (se activa con datos válidos) |
| Login con error | ![](images/ios-auditoria/04-login-error.png) | Error tras credenciales incorrectas | Reintentar |
| Registro | ![](images/ios-auditoria/03-registro.png) | Nombre, Email, Contraseña (mín. 8), Código (opcional) | «Crear cuenta» |

El botón «Registrarse» solo se muestra si el backend tiene el registro activo (`allow_registration`, `WelcomeView.swift:36`).

### 4.2 Pestañas

| Pestaña | Captura | Contenido |
|---|---|---|
| Inicio | ![](images/ios-auditoria/100-pestana-inicio.png) | Resumen del día: eventos de hoy, tareas pendientes, rutinas de hoy (calculadas en cliente), accesos rápidos |
| Tareas | ![](images/ios-auditoria/101-pestana-tareas.png) | Lista de tareas agrupadas, filtro, botón «Nueva tarea» |
| Calendario | ![](images/ios-auditoria/102-pestana-calendario.png) | Segmentos Eventos, Rutinas, Calendarios |
| Menú | sin captura | Segmentos «Semana», «Compra» y «Recetas» (`MealsView.swift:26-27`) |
| Hogar | ![](images/ios-auditoria/103-pestana-hogar.png) | Hogar activo, miembros, «Crear invitación», «Comidas», Administración |

### 4.3 Inicio

| Captura | Qué muestra |
|---|---|
| ![](images/ios-auditoria/10-inicio.png) | Secciones «Hoy · Eventos», «Tareas pendientes», «Rutinas de hoy» y «ACCESOS RÁPIDOS». Tarjetas con «Ver más» |

El botón «+ Evento» del Inicio no apareció en el recorrido automático; la acción de alta de evento queda cubierta desde el segmento Eventos.

### 4.4 Tareas

| Pantalla | Captura | Qué muestra | Acciones |
|---|---|---|---|
| Tareas (lista) | ![](images/ios-auditoria/20-tareas-lista.png) | Segmento «Tareas» activo. Grupos por lista con contador (p. ej. «Casa» 3, «Compra» 5), casillas para completar, botón flotante «+ Nueva tarea» | Marcar completada, filtrar (icono de filtro), abrir tarea |
| Tareas › Listas | ![](images/ios-auditoria/23-tareas-listas.png) | Segmento «Listas» | «Nueva lista», abrir lista |
| Nueva lista | ![](images/ios-auditoria/21-form-nueva-lista.png) | Nombre, Color, Orden de las tareas, Widget, Dashboard (`TaskListEditorView.swift:78-97`) | Cancelar, Crear lista |
| Nueva tarea | ![](images/ios-auditoria/22-form-nueva-tarea.png) | Título, Lista, Prioridad, Fecha límite, Personas (`TaskEditorView.swift:110-145`) | Cancelar, Crear tarea |

Las listas tienen flags propios «Widget» y «Dashboard» (panel «Visible en»). En la lista de tareas aparecen los estados Pendientes y Completadas.

### 4.5 Calendario

| Pantalla | Captura | Qué muestra | Acciones |
|---|---|---|---|
| Eventos | ![](images/ios-auditoria/30-calendario-eventos.png) | Eventos por día con cuenta atrás (`EventCountdownLabel`) | «Nuevo evento», abrir evento |
| Rutinas | ![](images/ios-auditoria/31-calendario-rutinas.png) | Rutinas con próxima ocurrencia (`PRÓXIMA · fecha`), estado «Hecha» | «Nueva rutina», marcar hecha |
| Calendarios | ![](images/ios-auditoria/32-calendario-calendarios.png) | Calendarios con contador de próximos eventos | «Nuevo calendario», abrir |
| Nuevo evento | ![](images/ios-auditoria/34-form-nuevo-evento.png) | Título, Fecha y hora, Fecha de fin (opcional), Calendario, Aviso, Personas (`EventDetailView.swift:52-87`) | Cancelar, Crear evento |
| Nueva rutina | ![](images/ios-auditoria/35-form-nueva-rutina.png) | Título, Calendario, Frecuencia (Diaria, Semanal con días, Mensual, «Cada N»), Horario (Hora, Inicio, Fecha fin opcional), Activa, Aviso, Personas (`RoutineEditorView.swift:55-118`) | Cancelar, Crear rutina |
| Nuevo calendario | ![](images/ios-auditoria/33-form-nuevo-calendario.png) | Nombre, Color, Widget, Dashboard (`CalendarDetailView.swift:61-68`) | Cancelar, Crear calendario |

Las sesiones de rutina son de solo lectura; la lista «Próximas sesiones» tiene 10 elementos.

### 4.6 Hogar y administración

| Pantalla | Captura | Qué muestra |
|---|---|---|
| Hogar | ![](images/ios-auditoria/40-hogar.png) | Hogar activo, miembros («Vinculada», «Sin cuenta», tipo y estado), tarjeta «Invitar» con el botón «Crear invitación» y «Invitaciones pendientes» (solo con permiso de invitar), «Comidas», enlace «Administración» (`HogarView.swift:191-231`) |
| Administración | ![](images/ios-auditoria/41-administracion.png) | Menú con seis secciones: Configuración, Administradores, Miembros, Invitaciones, Accesos, Auditoría |
| Configuración | ![](images/ios-auditoria/50-admin-configuración.png) | Nombre del hogar y zona horaria (IANA). Solo el admin edita |
| Administradores | ![](images/ios-auditoria/51-admin-administradores.png) | Admins del hogar: «Hacer admin», «Quitar admin», «Transferir», «Salir» |
| Miembros | ![](images/ios-auditoria/52-admin-miembros.png) | Personas del hogar con color, tipo y estado. Solo el admin agrega y edita |
| Invitaciones | ![](images/ios-auditoria/53-admin-invitaciones.png) | Invitaciones pendientes; «Crear invitación», «Revocar»; el código se muestra una sola vez |
| Accesos | ![](images/ios-auditoria/54-admin-accesos.png) | «Qué puede hacer cada persona» (permisos por miembro; «Editar» abre el editor). Solo el admin (`HomeAdminViews.swift:74`) |
| Auditoría | ![](images/ios-auditoria/55-admin-auditoría.png) | Registro de cambios, paginado con «Cargar más» |

### 4.7 Ajustes

| Pantalla | Captura | Qué muestra | Acciones |
|---|---|---|---|
| Ajustes | ![](images/ios-auditoria/60-perfil.png) | Hoja que abre el engranaje de Inicio (`RootView.swift:201`). Secciones Cuenta, Familia (Personas), Inicio (orden y bloques ocultos), Notificaciones, Feedback e Invitaciones (Unirse a un hogar con un código); «Modo oscuro» y cerrar sesión (`ProfileView.swift:128-225`). La captura es de la antigua pestaña Perfil | Editar nombre, email y contraseña; cerrar sesión |
| Personas | ![](images/ios-auditoria/61-personas.png) | Personas del hogar. Las compartidas son de solo lectura | «Nueva persona» (nombre, color) |
| Unirse a un hogar | ![](images/ios-auditoria/62-unirse-hogar.png) | Desde Ajustes › «Unirse a un hogar con un código» (`ProfileView.swift:225`). Campo para el código de invitación | «Unirse» |
| Enviar feedback | sin captura | Desde Ajustes › «Enviar feedback» (`ProfileView.swift:202`). Sección, Pantalla, Acción, Tipo (Bug o Mejora) y texto (`FeedbackView.swift:21-47`) | «Enviar feedback» |

## 5. Formularios de alta: resumen

Campos según el código de cada editor (lo que aparece en las capturas está verificado). Las reglas de validación no se probaron en el simulador: se indican solo como referencia del código.

| Formulario | Campos | Endpoint de escritura (verificado en el código) |
|---|---|---|
| Tarea | Título, Lista, Prioridad, Fecha límite, Personas | `task/create` |
| Lista | Nombre, Color, Orden de las tareas, Widget, Dashboard | `task-list/create` |
| Evento | Título, Fecha y hora, Fecha de fin (opcional), Calendario, Aviso, Personas | ruta de eventos: no verificada, ver sección 6 |
| Rutina | Título, Calendario, frecuencia (Diaria, Semanal con días, Mensual), intervalo, hora, inicio, fin opcional, activa, Aviso, Personas | `routine/create` |
| Calendario | Nombre, Color, Widget, Dashboard | ruta no verificada, ver sección 6 |
| Persona | Nombre, Color | `person/create` |
| Invitación | Tipo (`adult` solo para admin, `pet` nunca), «Vincular a un miembro» (opcional, solo miembros sin cuenta), Email del invitado (`HomeAdminViews.swift:1117-1135`) | `home/invitation/create` |

## 6. Datos y conexiones con el backend

Todas las rutas van a la Edge Function `api` (contrato PHP-compat). Las autenticadas envían `X-Home-Id` salvo `GET home`, `POST home/create` y `PATCH home/default`.

| Área | Lectura | Escritura |
|---|---|---|
| Sesión | `user/auth`, `GET /config` | `user/create`, `user/update` |
| Hogares | `home`, `home/detail`, `home/membership`, `home/audit`, `home/invitation`, `home/member` | `home/create`, `home/update`, `home/default`, `home/member/create`, `home/member/update`, `home/membership/role`, `home/membership/transfer`, `home/invitation/create`, `home/invitation/revoke`, `home/invitation/accept` |
| Permisos | `home/permission` | `home/permission` (set) |
| Tareas | `task`, `task/detail`, `task-list`, `task-list/detail`, `task-list/user` | `task/create`, `task/update`, `task/complete`, `task/order`, `task/delete`, `task-list/create`, `task-list/update`, `task-list/delete` |
| Eventos | `event` (según la búsqueda de rutas del código; filtros por fecha) | Escritura de eventos: no localizada en la búsqueda; revisar `EventRepository.swift` antes de usarla |
| Rutinas | `routine`, `routine/detail` | `routine/create`, `routine/update`, `routine/delete`, `routine/alarm` |
| Calendarios | `calendar`, `calendar/user` | Escritura de calendarios: no localizada en la búsqueda; revisar `CalendarRepository.swift` |
| Personas | `person` | `person/create`, `person/update`, `person/delete` |

Qué se calcula en cliente: rutinas de hoy y «Más próximas» (próxima ocurrencia futura), agrupación de tareas por lista, cuenta atrás de eventos (hora local del reloj del dispositivo).

Persistencia local: el token de sesión y el hogar activo van en Keychain (`active_home_id`). El código de invitación se muestra una vez, vive solo en memoria y no se persiste.

## 7. Estado y comportamiento a tener en cuenta

- **Hogar activo.** Tras login, `HomeContextStore` carga `GET home` y fija el hogar. Sin hogares, las pestañas muestran «Crear hogar» (`NoHomeView.swift:24`); Ajustes sigue disponible desde el engranaje (`RootView.swift:193`). Cambiar de hogar reconstruye las pestañas.
- **Permisos.** Hay ocultamiento en cliente y validación en servidor. Un miembro no ve acciones de administración.
- **Hogar personal.** Se puede renombrar. Transferir, quitar y salir no se ofrecen.
- **Cierre de sesión.** Pasa por `AppServices.signOut()`, que limpia el hogar activo.
- **Notificaciones.** No hay avisos en v1: las alarmas se guardan en el servidor pero el iPhone no avisa.
- **Eventos del calendario por día:** cabecera con flechas y selector de fecha, tira de la semana y lista del día; solo eventos (las sesiones de rutina se ven en el segmento Rutinas). Sin vista de mes.
- **Sin widgets, push ni iPad.** Distribución por side-load (firma gratuita, caduca a los 7 días).

## 8. Límites de esta captura

- **Sin estados vacíos ni de error forzados.** El recorrido automático usa el hogar demo, con datos. Los estados «Sin tareas», «Sin eventos», «Sin rutinas», «Sin miembros» y los de error de red no están capturados. Hace falta una segunda pasada con un hogar vacío y con el backend apagado.
- **«+ Evento» en Inicio** no se localizó en el recorrido; el alta de evento sí está capturada desde Calendario.
- **Sin `accessibilityIdentifier`.** Los tests localizan controles por texto visible, así que cambiar un título rompe el recorrido.
- **Una sola cuenta** (demo, admin). No se capturó la vista de un miembro sin permisos de administración.
- **Un solo tamaño** de simulador (iPhone 17). Falta comprobar iPhone chico y Pro Max.
- Algunos textos (p. ej. la confirmación de «Eliminar» y el contenido de los menús de opciones) no se abrieron.
