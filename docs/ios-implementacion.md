# Control iOS: documento funcional de implementación (UX/UI)

Propuesta de mejora **evolutiva** de la app gestora Homita Control (`apps/control-ios`, iOS 17+, SwiftUI) a partir de la auditoría de `docs/ios-funcional.md` y las capturas de `docs/images/ios-auditoria/`. Se mantienen las 5 pestañas, los segmentos y la arquitectura de datos. Cambia la jerarquía visual, los estados (vacío, carga, error, sin conexión) y la consistencia entre pantallas.

- **Wireframes:** `docs/design/ios/index.html` (mapa de flujo y tabla de conexiones). 31 pantallas en `docs/design/ios/screens/<id>.html`, cada una con 5 estados.
- **Sistema de diseño:** `docs/design/ios/tokens.css` (color, tipografía, espaciado, forma) y `components.css` (componentes de wireframe). Los valores salen de las capturas actuales.
- **Cómo leer este documento:** cada épica agrupa historias por pestaña de la barra inferior. Cada historia cita el id del wireframe donde se ve (`TASKS-01`, etc.), sus criterios de aceptación y los estados que debe cubrir. Las decisiones pendientes están en la sección 9; las historias que dependen de ellas lo indican.

## 1. Diagnóstico (qué se mejora y por qué)

Observado en las capturas actuales:

| # | Hallazgo | Evidencia | Respuesta de diseño |
|---|---|---|---|
| D1 | Hueco vertical de ~170 pt entre la barra de estado y el título en Inicio y Hogar | `100-pestana-inicio`, `40-hogar` | Cabecera compacta: título grande pegado a la barra de estado, acciones a la derecha |
| D2 | Mensaje de error «No se pudo guardar el hogar activo» fijo en la tarjeta en estado normal | `40-hogar` | Aviso descartable (toast), no contenido permanente de tarjeta |
| D3 | La barra de pestañas flotante tapa contenido; el botón «Nueva tarea» se solapa con las filas | `20-tareas-lista`, `100-pestana-inicio` | Barra que reserva su espacio; acción de alta en la cabecera, sin botón flotante sobre las filas |
| D4 | Títulos y acciones inconsistentes entre pestañas (filtro suelto en Tareas, título propio en Inicio) | capturas 100–104 | Una sola cabecera: título grande, subtítulo de contexto, hasta 2 acciones circulares a la derecha |
| D5 | Tarjetas con icono, badge y chevron repetidos; mismo peso visual todas | `100-pestana-inicio` | Un solo gesto por tarjeta (toda ella navega); la próxima tarea con cuenta atrás se destaca |
| D6 | Carrusel de dos páginas dentro de «Tareas pendientes» | `10-inicio` | Un grupo y «Ver las N» |
| D7 | Permisos de cada miembro en párrafos largos con «Ver más» | `40-hogar` | Resumen en una línea («Permisos 4 de 6») con detalle en Accesos |
| D8 | Sin estados vacíos, de error, de carga ni de conexión definidos (doc funcional §8) | — | Patrones transversales de la sección 3 |
| D9 | Los tests de UI localizan por texto visible; no hay `accessibilityIdentifier` | doc funcional §8 | Identificadores estables como parte de cada historia (sección 3, E0-06) |

## 2. Principios

1. **Evolutivo sobre iOS nativo.** HIG, SwiftUI, Dynamic Type, modo oscuro. Sin cambios de arquitectura de navegación.
2. **Una forma de hacer cada cosa.** Misma cabecera, mismo alta (hoja modal con Cancelar/Guardar), misma confirmación destructiva (hoja inferior con el nombre del elemento).
3. **El error es local.** Un fallo en una tarjeta no bloquea la pantalla. Un fallo de escritura conserva lo que el usuario escribió.
4. **Sin conexión no es un error.** Se muestran los datos en caché con la hora, y las escrituras se atenúan. Coincide con la capa de datos actual (stale-if-error).
5. **Áreas táctiles de 44 pt** y contraste AA (texto secundario ≥ 4.5:1 sobre el fondo).
6. **El cliente oculta, el servidor decide.** Las acciones de administración se ocultan, no se deshabilitan; el miembro ve Administración en solo lectura (comportamiento actual).

## 3. Épica E0: Fundamentos transversales

Prerrequisito de las demás épicas. Sin E0 las épicas E1–E5 no pueden cumplir sus estados.

| Id | Historia | Criterios de aceptación | Wireframe |
|---|---|---|---|
| E0-01 | Tokens de diseño | Como desarrollador, tengo un archivo de tokens (colores `bg`, `surface`, `accent`, `ok`, `warn`, `err`, `info`, texto 1/2/3; escala tipográfica; espaciado de 4 en 4; radios 10/16/24/pill). Valores de `tokens.css`. Modo oscuro con los mismos nombres. Ningún color ni medida literal en las vistas | `tokens.css` |
| E0-02 | Cabecera estándar | Vista reutilizable con título grande, subtítulo opcional y hasta 2 botones circulares de 44 pt. Se contrae al hacer scroll (comportamiento nativo). Sin hueco superior | Todas |
| E0-03 | Skeleton | Modificador `.skeleton()` con shimmer; desactivado con *Reduce Motion*. Cada pantalla con lista define su skeleton con la misma geometría que el contenido real; títulos y segmentos reales, solo los datos en shimmer. No se usa spinner a pantalla completa | Estado 3 de cada pantalla |
| E0-04 | Estado vacío | Vista con icono, título, texto de una línea y **una** acción primaria opcional | Estado 2 |
| E0-05 | Estados de error | (a) `InlineError` en tarjeta o sección con «Reintentar»; (b) `ErrorState` a pantalla completa cuando no hay nada que mostrar; (c) `Toast` para fallos de escritura con «Reintentar»; (d) mensaje distingue causa: sin conexión, servidor (5xx), sesión caducada (401, cierra sesión), sin permiso (403 con el mensaje del servidor) | Estado 4 |
| E0-06 | Sin conexión | `OfflineBanner` bajo la cabecera con la hora del dato en caché («Mostrando datos de las 19:42») y «Reintentar». Lo alimenta la marca de tiempo de `DiskCache`. Con la red de vuelta se oculta solo. Las acciones de escritura se atenúan y explican por qué al tocarlas | Estado 5 |
| E0-07 | Hoja de confirmación | `ConfirmSheet` con el nombre del elemento, consecuencia en una línea, «Eliminar» (destructivo) y «Cancelar». Usada en todas las eliminaciones y revocaciones | `tasks-detalle-lista` e6 y otras |
| E0-08 | Barra de pestañas | Reserva su espacio: el contenido nunca queda debajo. Etiquetas e iconos nativos. Badge opcional (ver decisión P-05) | Todas |
| E0-09 | Identificadores de accesibilidad | `accessibilityIdentifier` estable en cada control interactivo y fila, con formato `<pantalla>.<elemento>` (p. ej. `tasks.add`). Se actualiza `ControlAppUITests` para usarlos en vez del texto visible | — |
| E0-10 | Formularios modales | Hoja con «Cancelar» a la izquierda y acción a la derecha (desactivada hasta que el formulario es válido). Validación en línea bajo el campo. Estado «guardando» con indicador en el botón y campos bloqueados. Error de servidor arriba conservando lo escrito. Descartar con cambios pide confirmación | `*-form-*` |

**Dependencias técnicas:** E0-06 requiere exponer la fecha de la última lectura exitosa desde `CachedResource` (hoy el repositorio no la publica a la UI). Sin eso, el banner no puede mostrar la hora.

## 4. Épica E1: Inicio

Pantalla: `HOME-01` (`screens/home-inicio.html`).

| Id | Historia | Criterios de aceptación |
|---|---|---|
| E1-01 | Cabecera compacta de Inicio | Dado un usuario con sesión, cuando abre Inicio, entonces ve «Hola, <nombre>» y la fecha con el nombre del hogar, sin hueco superior. A la derecha, un botón de hogar abre `HOGAR-01` |
| E1-02 | Tarjeta destacada de eventos | La tarjeta «Hoy · Eventos» lleva borde de acento y lista los eventos de hoy con hora y persona/calendario. El próximo evento muestra la cuenta atrás en color de acento («en 22 min») usando el reloj de referencia existente. Toda la tarjeta abre Calendario › Eventos |
| E1-03 | Tareas pendientes sin carrusel | La tarjeta muestra el primer grupo (hasta 3 tareas), el contador total en el badge y «Ver las N». Se pueden marcar tareas desde la tarjeta. Toda la tarjeta abre Tareas |
| E1-04 | Rutinas de hoy | Muestra las rutinas del día calculadas en cliente con estado Hecha/pendiente y el contador «hechas/total». Marcar hecha desde la tarjeta. Abre Calendario › Rutinas |
| E1-05 | Estado vacío del día | Sin eventos, tareas ni rutinas para hoy: un único estado vacío «Hoy no hay nada pendiente» con «Añadir un evento» y «Nueva tarea» |
| E1-06 | Skeleton | Tres tarjetas con la geometría de las reales mientras cargan |
| E1-07 | Error parcial | Si falla una de las tres fuentes, solo esa tarjeta muestra `InlineError` con «Reintentar». Un fallo al marcar una tarea abre un toast con reintento y revierte la casilla |
| E1-08 | Sin conexión | Banner con la hora de los datos y las tarjetas en caché. Las casillas se atenúan |

**Conexiones:** Inicio → Tareas (`TASKS-01`), Eventos (`CAL-01`), Rutinas (`CAL-02`), Hogar (`HOGAR-01`); atajos del estado vacío → `CAL-05`, `TASKS-04`.

**Nota de la auditoría:** el botón «+ Evento» de Inicio no apareció en el recorrido automático. La propuesta lo reemplaza por las acciones del estado vacío y por el alta desde Calendario; confirmar en P-07.

## 5. Épica E2: Tareas

Pantallas: `TASKS-01` a `TASKS-05`.

| Id | Historia | Criterios de aceptación | Wireframe |
|---|---|---|---|
| E2-01 | Cabecera de Tareas con acciones | El botón de filtro y «+» (nueva tarea) van en la cabecera. Desaparece el botón flotante «Nueva tarea» que tapaba las filas. El subtítulo resume el filtro activo («Pendientes · Todas las listas») | `TASKS-01` |
| E2-02 | Lista agrupada | Grupos por lista con punto de color, nombre y contador; plegables; las filas son tarjetas con casilla de 26 pt. Completar anima la fila y actualiza el contador | `TASKS-01` |
| E2-03 | Hoja de filtros | Estado (Pendientes/Completadas) y lista. Aplicar actualiza el subtítulo; hay «Restablecer» | `TASKS-01` e6 |
| E2-04 | Vacío, carga, error, sin conexión de la lista | Vacío: «No tienes tareas pendientes» con «Nueva tarea». Skeleton de dos grupos. Error de lista: `ErrorState`. Error al completar: toast con reintento y reversión. Sin conexión: banner y casillas atenuadas | `TASKS-01` |
| E2-05 | Segmento Listas | Cada lista muestra color, contador de pendientes y los flags Widget/Dashboard como etiquetas. «+» abre `TASKS-05`. Tocar abre el detalle | `TASKS-02` |
| E2-06 | Detalle de lista | Tareas de la lista, «Editar lista», «Eliminar lista» con `ConfirmSheet` que nombra la lista y avisa de qué pasa con sus tareas (ver P-03) | `TASKS-03` |
| E2-07 | Alta y edición de tarea | Título (obligatorio) y Lista. Preselecciona la lista del grupo desde el que se abrió (ver P-04). Hoja modal según E0-10 | `TASKS-04` |
| E2-08 | Alta y edición de lista | Nombre (obligatorio, validación de duplicado), Color, Widget, Dashboard. Selector de color de paleta fija (ver P-06) | `TASKS-05` |
| E2-09 | Hogar vacío | Si no hay hogar activo, la pestaña muestra `HOGAR-02` con «Crear hogar» (comportamiento actual) con el nuevo diseño | `HOGAR-02` |

**Backend:** `task/create|update|complete|order|delete`, `task-list/create|update|delete` (verificados en el código). Sin cambios de contrato.

## 6. Épica E3: Calendario

Pantallas: `CAL-01` a `CAL-08`.

| Id | Historia | Criterios de aceptación | Wireframe |
|---|---|---|---|
| E3-01 | Eventos por día | Segmento Eventos con eventos agrupados por día; cada fila con barra de color de la persona o calendario, título, hora y cuenta atrás cuando aplica. «+» en la cabecera. Tocar un evento abre `CAL-05` en modo edición | `CAL-01` |
| E3-02 | Rutinas con próxima ocurrencia | Cada rutina muestra «PRÓXIMA · fecha», hora y estado. La casilla Hecha es un control independiente de la fila, con área táctil propia. Tocar la fila abre `CAL-08` | `CAL-02` |
| E3-03 | Calendarios | Lista con color, nombre y contador de próximos eventos (rango por definir, P-08). «+» abre `CAL-07` | `CAL-03` |
| E3-04 | Detalle de calendario | Nombre, color, flags Widget/Dashboard, próximos eventos, Editar y Eliminar con `ConfirmSheet` (ver P-09) | `CAL-04` |
| E3-05 | Formulario de evento | Título, inicio y fin (el backend ya soporta fin, change `event-end-date`), Calendario, personas asignadas como chips de color, Aviso. Modo edición con «Eliminar evento» y confirmación | `CAL-05` |
| E3-06 | Formulario de rutina | Título, Calendario, frecuencia (Diaria/Semanal/Mensual), «Cada N» con stepper, hora, inicio, fin opcional y Activa. Un **resumen en lenguaje natural** bajo la frecuencia («Cada 2 semanas a las 19:00») que se actualiza en vivo | `CAL-06` |
| E3-07 | Formulario de calendario | Nombre, Color, Widget, Dashboard | `CAL-07` |
| E3-08 | Detalle de rutina | Resumen, alarma, próximas sesiones de solo lectura (10), Editar y Eliminar con confirmación | `CAL-08` |
| E3-09 | Estados de las listas | Los 5 estados en `CAL-01`, `CAL-02` y `CAL-03`: vacío con acción de alta, skeleton, error, sin conexión | `CAL-01..03` |
| E3-10 | (Opcional, fuera de la primera entrega) Vista Semana | Selector Lista/Semana en Eventos. Solo propuesta en las notas de `CAL-01`; el doc funcional indica que v1 no tiene vista mensual ni semanal | `CAL-01` notas |

**Riesgo de backend (bloquea E3-01, E3-05 y E3-07 hasta resolverse):** el documento funcional §6 no localiza las rutas de **escritura** de eventos ni de calendarios. Antes de implementar hay que revisar `EventRepository.swift` y `CalendarRepository.swift`. Si no existen, el alta de eventos y de calendarios desde iOS requiere trabajo de backend previo (fuera del alcance de este documento).

## 7. Épica E4: Hogar

Pantallas: `HOGAR-01` a `HOGAR-09`. Las capturas 52 a 55 de la auditoría resultaron ser todas el menú de Administración, no las pantallas reales, por lo que `HOGAR-06` a `HOGAR-09` se diseñaron desde el código y el documento funcional. Conviene repetir esas capturas antes de implementar.

| Id | Historia | Criterios de aceptación | Wireframe |
|---|---|---|---|
| E4-01 | Hogar y miembros | Tarjeta «Hogar activo» (con selector si hay varios hogares) y lista de miembros con avatar, tipo, estado (Vinculada/Sin cuenta) y rol. Permisos en una línea («Permisos 4 de 6») que lleva a Accesos. «Invitar» como acción secundaria visible solo si el usuario puede invitar | `HOGAR-01` |
| E4-02 | Aviso de hogar activo no guardado | El mensaje actual pasa a toast descartable que no ocupa espacio en la tarjeta (ver P-10: duración) | `HOGAR-01` |
| E4-03 | Vista de miembro sin permisos | Sin «Invitar». «Administración» visible pero en solo lectura, con etiqueta «Solo lectura». Se verifica el comportamiento actual (el cliente oculta, el servidor decide) | `HOGAR-01` e6 |
| E4-04 | Sin hogar | Pantalla con «Crear hogar» y «Unirse con código» (este último abre `AJ-05`). Se reutiliza en Tareas y Calendario cuando no hay hogar | `HOGAR-02` |
| E4-05 | Menú Administración | Seis filas con icono y resumen de una línea (p. ej. «Invitaciones · 2 pendientes»). Versión de miembro en solo lectura | `HOGAR-03` |
| E4-06 | Configuración del hogar | Nombre y zona horaria IANA con selector buscable. Solo el admin edita; el hogar personal solo se renombra | `HOGAR-04` |
| E4-07 | Administradores | Hacer admin, Quitar admin, Transferir propiedad, Salir. Cada acción con `ConfirmSheet` (ver P-11 sobre «Quitar admin») | `HOGAR-05` |
| E4-08 | Miembros | Lista con color, tipo y estado; alta de miembro en hoja; solo el admin agrega y edita | `HOGAR-06` |
| E4-09 | Invitaciones | Invitaciones pendientes; crear (email, tipo; `adult` solo admin, `pet` nunca); el **código se muestra una sola vez** en una hoja con copiar y compartir y aviso de que no se volverá a ver; revocar con confirmación | `HOGAR-07` |
| E4-10 | Accesos | Permisos por miembro agrupados por área con interruptores y barra de guardado fija al pie; error de guardado conserva los cambios | `HOGAR-08` |
| E4-11 | Auditoría | Registro paginado con «Cargar más», con skeleton, error al cargar más sin perder lo ya cargado y filtro opcional (cliente o servidor, ver P-12) | `HOGAR-09` |
| E4-12 | Estados de las pantallas de administración | Cada una cubre carga, error y sin conexión. Las escrituras de administración se atenúan sin conexión | `HOGAR-03..09` |

**Backend:** rutas `home/*` verificadas en el doc funcional §6. Sin cambios de contrato previstos.

## 8. Épica E5: Ajustes (pestaña «Perfil» actual)

Pantallas: `AJ-01` a `AJ-05`, más acceso sin sesión (`AUTH-01` a `AUTH-03`), que se agrupa aquí por no pertenecer a ninguna pestaña.

| Id | Historia | Criterios de aceptación | Wireframe |
|---|---|---|---|
| E5-01 | Lista agrupada de Ajustes | Secciones al estilo de Ajustes de iOS: Cuenta, Familia, Hogares, Sesión. Avatar, nombre y email arriba. Versión de la app al pie. Etiqueta de la pestaña «Ajustes» (decisión P-01) | `AJ-01` |
| E5-02 | Editar cuenta | Nombre, email y contraseña (mín. 8 con indicador de fuerza). Error de email ya usado. Pedir contraseña actual para cambiarla (P-13) | `AJ-02` |
| E5-03 | Personas | Lista con color; las compartidas son de solo lectura con candado y explicación (P-14). «+» abre `AJ-04` | `AJ-03` |
| E5-04 | Alta y edición de persona | Nombre y Color; edición con «Eliminar persona» y confirmación | `AJ-04` |
| E5-05 | Unirse a un hogar | Campo de código; errores diferenciados: código inválido, vencido, ya eres miembro; éxito lleva a `HOGAR-01` | `AJ-05` |
| E5-06 | Cerrar sesión | Confirmación en hoja inferior; limpia el hogar activo (`AppServices.signOut()`). Comportamiento sin conexión en P-15 | `AJ-01` e6 |
| E5-07 | Bienvenida | Logo, nombre, dos botones. Estado «Registro cerrado en producción» (`allow_registration=false`): no se ofrece «Registrarse», se explica que se necesita invitación. Estado de error al restaurar sesión con reintento | `AUTH-01` |
| E5-08 | Iniciar sesión | Email y contraseña con mostrar/ocultar; errores en línea sin perder lo escrito; carga con indicador en el botón | `AUTH-02` |
| E5-09 | Registro | Nombre, email, contraseña (mín. 8), código opcional; errores en línea (email registrado, contraseña corta) | `AUTH-03` |
| E5-10 | Estados de Ajustes | Cada pantalla cubre sus 5 estados; sin hogar activo, la sección Hogares se oculta y el acceso a unirse queda en `HOGAR-02` (P-16) | `AJ-*` |

## 9. Decisiones y preguntas abiertas

Las dudas que surgieron al diseñar. Cada una indica qué historia bloquea y el supuesto adoptado en el wireframe.

| Id | Pregunta | Supuesto en el wireframe | Afecta |
|---|---|---|---|
| P-01 | ¿Renombrar la pestaña «Perfil» a «Ajustes»? | Sí, los wireframes la muestran como «Ajustes» | E5-01, E0-08 |
| P-02 | ¿Existen las rutas de escritura de eventos y calendarios? (doc funcional §6) | Sí; hay que verificar `EventRepository.swift` y `CalendarRepository.swift` | E3-01, E3-05, E3-07 |
| P-03 | Al eliminar una lista, ¿se borran sus tareas o pasan a otra lista? | La hoja avisa de que se borran | E2-06 |
| P-04 | ¿Preselecciona la lista en «Nueva tarea»? | Sí, la del grupo de origen | E2-07 |
| P-05 | ¿Badge numérico en alguna pestaña (tareas pendientes)? | No | E0-08 |
| P-06 | ¿Paleta de color fija o selector libre? | Paleta fija de 5 a 8 colores | E2-08, E3-07, E5-04 |
| P-07 | ¿Se mantiene «+ Evento» en Inicio? | Se sustituye por acciones del estado vacío y alta desde Calendario | E1-05 |
| P-08 | ¿Qué rango cuenta el «N próximos» de un calendario? | Próximos 7 días | E3-03 |
| P-09 | Al eliminar un calendario, ¿qué pasa con sus eventos y rutinas? ¿Editar y eliminar son solo de admin? | Se avisa de que se eliminan; acciones ocultas para miembros | E3-04 |
| P-10 | Aviso de hogar activo no guardado: ¿se descarta solo o persiste hasta resolverse? | Se descarta tras 5 s y reintenta al volver a primer plano | E4-02 |
| P-11 | «Quitar admin»: ¿con confirmación o directo? | Con confirmación | E4-07 |
| P-12 | Filtro de auditoría: ¿en cliente o parámetro de `home/audit`? | En cliente sobre lo ya cargado | E4-11 |
| P-13 | ¿Pedir contraseña actual al cambiarla? | Sí | E5-02 |
| P-14 | ¿Las personas «compartidas» son las que vienen de otro hogar? | Sí | E5-03 |
| P-15 | ¿Se permite cerrar sesión sin conexión? | Sí; es una operación local | E5-06 |
| P-16 | Sin hogar, ¿dónde queda «Unirse»? | En `HOGAR-02` y en Ajustes | E5-10 |
| P-17 | En el login con error, ¿se conserva la contraseña escrita o se borra por seguridad? | Se conserva el email y se borra la contraseña (**revisar**: el wireframe actual conserva ambos) | E5-08 |
| P-18 | Color del logo «H» (naranja de la captura no tiene token) | Se usa `--warn` provisional; definir token de marca | E5-07, E0-01 |

## 10. Orden de implementación sugerido

1. **E0** (tokens, cabecera, estados, sin conexión, identificadores). Sin esto no hay base común.
2. **E2 Tareas** y **E1 Inicio**: los datos ya están verificados y es donde más se nota la mejora (D1, D3, D5, D6).
3. **E4 Hogar** (D2, D7 y administración), con las capturas 52–55 repetidas antes.
4. **E5 Ajustes** y acceso.
5. **E3 Calendario**, al final por el riesgo P-02. Si faltan rutas de escritura, entregar antes solo las vistas de lectura (E3-01 a E3-04, E3-09).

Cada épica se entrega en una rama propia con `swift test` de ControlKit y `xcodebuild test` del esquema `ControlApp` en verde. Los identificadores de E0-09 permiten ampliar los tests de UI para cubrir los estados vacío y de error con un hogar vacío y con el backend apagado, que es la segunda pasada pendiente de la auditoría.

## 11. Límites de este trabajo

- **Wireframes de baja fidelidad.** Son referencias de estructura, jerarquía y estados, no maquetas finales: iconos y glifos son marcadores, no los SF Symbols definitivos.
- **No se probó en dispositivo.** Todo se revisó en el navegador a 390 × 844 pt. Faltan iPhone chico y Pro Max.
- **Capturas 52–55 incorrectas** (ver E4). Contenido de esas pantallas deducido del código.
- **Rutas de escritura de eventos y calendarios no verificadas** (P-02).
- **Datos de ejemplo** de la cuenta demo, con textos de error propuestos que requieren revisión de redacción.
- No se tocó código Swift ni backend.
