# Control iOS: documento funcional de implementación (UX/UI)

Propuesta de mejora **evolutiva** de la app gestora Homita Control (`apps/control-ios`, iOS 17+, SwiftUI). Parte de la auditoría (`docs/ios-funcional.md`, `docs/images/ios-auditoria/`), de una **segunda pasada contra el código SwiftUI real** y del diseño «Rutinas de hoy» aportado por el usuario. Se mantienen las 5 pestañas, los segmentos y la arquitectura de datos.

- **Wireframes:** `docs/design/ios/index.html` (mapa de flujo y tabla de conexiones). 31 pantallas en `docs/design/ios/screens/<id>.html`, con estados y variantes.
- **Hechos del código:** `docs/design/ios/code-facts.md` es el contrato entre código y wireframes: qué hace hoy cada pantalla, qué se quitó de la primera pasada por no existir, qué es propuesta.
- **Sistema de diseño:** `docs/design/ios/tokens.css` y `components.css`. Paleta y tipografía del diseño del usuario (acento `#B5313F`, fuente Inter).
- **Convención:** en los wireframes la etiqueta amarilla **Nuevo** marca lo que el código actual no tiene. En este documento, cada historia lleva **[Rediseño]** (existe, mejora visual o de comportamiento) o **[Nuevo]** (no existe hoy).

## 1. Qué cambió respecto a la primera entrega

La primera pasada se hizo desde capturas que solo cubren la primera pantalla visible y mezcló lo existente con propuestas. La lectura del código corrigió esto:

| Hallazgo | Corrección |
|---|---|
| Faltaban elementos reales: «Accesos rápidos» de Inicio, alta rápida y swipe en Tareas, etiquetas de persona, panel «Personas con acceso», panel «Orden de las tareas», «Visible en», fila de personas en formularios, aviso de alarma | Incorporados en los wireframes |
| Calendario › Eventos **no es una lista por día**: es un conmutador Mes/Semana/Día con cuadrícula | Rehecho: CAL-01 con los tres modos |
| No existe **fecha de fin de evento** ni **detalle de rutina** ni **ficha de lectura** de calendario | Se quitaron. `cal-detalle-*` pasan a ser el **editor en modo edición** |
| No existe casilla «Marcar hecha» en Calendario | Quitada. En Inicio existía con marcas locales: ver decisión D-1 |
| Se inventaron: filtro por estado, flags en tarjetas de lista, «Propietaria», frases naturales en Auditoría, «Unirse con código» en Sin hogar | Quitados o marcados Nuevo |
| P-02: ¿existen las rutas de escritura de eventos y calendarios? | **Sí**: `event/create\|update\|alarm\|delete`, `calendar/create\|update\|delete\|user`, `routine/create\|update\|delete\|alarm` |
| Las capturas 52–55 eran todas el menú de Administración | Esas pantallas se diseñaron desde el código |

**Lo que el código no tiene hoy y esta propuesta añade (Nuevo):** estados de carga con skeleton, estado de error de pantalla, estado sin conexión con datos de caché, toasts con reintento, estados por horario de las rutinas, y mejoras visuales. Hoy los estados reales son: texto «Cargando…», alerta modal «Aviso / OK» y `HomeErrorView`. **Dependencia:** el sin conexión requiere una caché de lectura en la capa de repositorio; la decisión D-8 la incluye como trabajo de E0-06.

## 2. Decisiones tomadas por el usuario (2026-11-12)

| Id | Decisión | Consecuencia de implementación |
|---|---|---|
| D-1 | Rutinas de hoy: **solo automático**, sin marca manual | Eliminar `setRoutineDone`, el círculo «Marcar … como hecha», las marcas locales por día y «Desmarcar». Una rutina pasa a «completadas» sola a los 60 min |
| D-2 | Duración fija de **60 min** en v1 | Reutiliza la ventana de `RoutineStatus` (3600 s). Duración por rutina queda como mejora futura |
| D-3 | **Paleta e Inter del diseño** del usuario | `Palette.swift` usa `#C8243B` y Geist; el diseño usa `#B5313F` e Inter. Ver E0-01: hay que migrar paleta y fuente (Inter no está en el bundle) |
| D-4 | Revisión completa contra el código | Hecha: `code-facts.md` |
| D-5 | Alcance evolutivo sobre iOS nativo y doc en `docs/` | Se mantiene la arquitectura de 5 pestañas |
| D-6 | La 5.ª pestaña se llama **«Ajustes»** (antes «Perfil») | Cambiar el `tabItem` de `RootView`, el título de `ProfileView` y los textos que citan la ruta, p. ej. «Créalas en Perfil › Personas.» → «Créalas en Ajustes › Personas.» y «acepta la invitación desde Perfil». Wireframes ya actualizados |
| D-7 | **Todo borrado pide confirmación** (incluye swipe de tareas y rutinas, papelera de personas y «Eliminar tarea») | Añadir `homitaConfirm` a esos cuatro puntos con el patrón «¿Eliminar «X»?» + consecuencia. Ver E0-07 |
| D-8 | La **caché de lectura con hora se implementa** | Pasa a ser trabajo de E0-06 (ya no es una pregunta abierta) |

## 3. Épica E0: Fundamentos transversales

Prerrequisito de las demás. Todas las historias son **[Nuevo]** salvo indicación.

| Id | Historia | Criterios de aceptación |
|---|---|---|
| E0-01 | Tokens, paleta y tipografía | Archivo de tokens con los valores de `tokens.css` (superficies, texto 1/2/3, acento `#B5313F`, `--ok/--warn/--err/--info`, estados de rutina `--now`/`--soon`, escala de espaciado de 4, radios 10/16/24/28/pill). Sustituye `Palette.accent` y la fuente por la del diseño. Modo oscuro con los mismos nombres. Ningún color ni medida literal en las vistas (hoy hay hex en `RoutinesTodayCard`) |
| E0-02 | Cabecera estándar **[Rediseño]** | Título grande pegado a la barra de estado, subtítulo opcional, hasta 2 acciones circulares de 44 pt. Elimina el hueco superior de Inicio y Hogar |
| E0-03 | Skeleton | `.skeleton()` con shimmer, desactivado con *Reduce Motion*. Misma geometría que el contenido; títulos reales, solo los datos en shimmer. Sustituye a «Cargando…» |
| E0-04 | Estado vacío **[Rediseño]** | Vista con icono, título, texto y **una** acción primaria opcional. Se conservan los textos reales (`Sin tareas`, `Sin eventos este día.`…) |
| E0-05 | Errores | (a) Error de sección: mensaje del servidor (`APIError.userMessage`) + «Reintentar» (ya existe); (b) error de pantalla completa; (c) toast con «Reintentar» para fallos de escritura en lugar de alerta «Aviso/OK»; (d) distinguir causa: sin conexión, 5xx, 401 (cierra sesión), 403 (mensaje del servidor) |
| E0-06 | Sin conexión y caché de lectura (D-8) | **Historia técnica a implementar.** (1) Capa de caché en disco por recurso (clave = ruta + `X-Home-Id` + parámetros) con marca de tiempo de la última lectura correcta, patrón stale-if-error: ante fallo de red o 5xx se devuelve el dato en caché marcado como «obsoleto». (2) Los stores exponen `lastUpdated` y un flag `isStale`. (3) Monitor de conectividad (`NWPathMonitor`) para anticipar el estado. (4) Banner bajo la cabecera con la hora del dato («Sin conexión. Mostrando datos de las 19:12.») y «Reintentar»; se oculta solo al recuperar red. (5) Las escrituras se atenúan sin conexión y al tocarlas explican por qué. (6) La caché se limpia en `signOut()` y al cambiar de hogar. (7) No se cachea nada sensible (el código de invitación sigue solo en memoria). Criterios: con red cortada Inicio, Tareas, Calendario, Hogar y Ajustes muestran datos con el banner; sin caché previa se muestra el error de pantalla. Se verifica con tests de unidad del repositorio y con el backend apagado |
| E0-07 | Confirmación destructiva **[Rediseño]** | Hoy `homitaConfirm` (diálogo nativo). Unificar textos con el patrón «¿Eliminar «X»?» + una línea de consecuencia, «Cancelar» y «Eliminar» (D-7). **Se añade confirmación [Nuevo]** a lo que hoy borra directo: swipe en tareas (lista y detalle) y en rutinas, papelera de personas y «Eliminar tarea». Wireframes: frame «Confirmar eliminación» en `TASKS-01`, `TASKS-03`, `TASKS-04`, `CAL-02` y `AJ-03` |
| E0-08 | Barra de pestañas | Reserva su espacio; el contenido nunca queda debajo. La 5.ª pestaña se llama «Ajustes» (D-6) |
| E0-09 | `accessibilityIdentifier` | Identificadores estables `<pantalla>.<elemento>`; hoy solo existe la etiqueta «Nueva persona». Actualizar `ControlAppUITests` para dejar de localizar por texto visible. Etiquetas VoiceOver en lápiz y papelera de Personas |
| E0-10 | Formularios modales **[Rediseño]** | Se conserva «Cancelar» a la izquierda y el botón de acción al pie. Validación en línea sustituye a la alerta (**Nuevo**); error de servidor conserva lo escrito |
| E0-11 | Pull-to-refresh | Ya existe en todas las listas; mantener |

## 4. Épica E1: Inicio

Wireframe `HOME-01`. Orden real: saludo → Eventos → Tareas → Rutinas → Accesos rápidos.

| Id | Historia | Criterios de aceptación |
|---|---|---|
| E1-01 | Cabecera compacta **[Rediseño]** | «Hola, <nombre>» y fecha capitalizada, sin hueco superior. Botón ⌂ a Hogar a la derecha **[Nuevo]** |
| E1-02 | Tarjeta Eventos **[Rediseño]** | Icono, «Hoy · Eventos», contador. Fila: barra de color del calendario, título, cuenta atrás (solo de 0 a 120 min: «ahora», «en N min», «en H h», «en H h M min»), calendario y hora. Vacío «Sin eventos hoy». Navegar a Eventos por el chevron (hoy) o toda la tarjeta **[Nuevo]** |
| E1-03 | Tarjeta Tareas **[Rediseño]** | Una página por lista con pendientes, puntos de paginación, máx. 5 tareas, casilla que completa al instante, «Ver más» abre Tareas con esa lista desplegada. Vacío «Sin tareas pendientes» |
| E1-04 | **Tarjeta «Rutinas de hoy» [Nuevo]** | Diseño del usuario. Cabecera con fecha y «Ver todas ›». Progreso «N de M hechas» + estado («Falta 1», «Faltan N», «Ahora: <título>», «¡Completo!») y barra de 8 pt. Cada rutina según su estado: **aún no empieza** (>60 min, kicker «Siguiente · en 2 h 30 min» solo en la primera), **aviso** (≤60 min: ámbar, ⚠ «Empieza en N min», barra de cuenta atrás, «Faltan N min»), **en curso** (verde, punto con pulso, barra de tiempo, «Quedan N min»), **finalizada** (pasa sola a «N completadas», plegable, tachada). Variante **compacta** con anillo cuando hay 2 o más a la vez. «Todo hecho por hoy» en verde. Sin hora fija: al final. Sin marca manual (D-1) |
| E1-05 | Accesos rápidos **[Existente]** | `+ Tarea` y `+ Evento`. Sin listas: alerta «Crea una lista de tareas primero». Sin calendarios: «Crea un calendario primero» |
| E1-06 | Estados | Skeleton por tarjeta **[Nuevo]**; error por tarjeta con mensaje + «Reintentar» (existe); sin conexión **[Nuevo]**; pantallas que sustituyen Inicio: cargando hogar, sin hogar, error «No se pudo cargar tu hogar» (existen) |
| E1-07 | Accesibilidad | Saludo + fecha combinados; filas de evento combinadas; barras de progreso con `accessibilityValue`; el pulso respeta *Reduce Motion* |

**Reglas de negocio de rutinas (E1-04):** solo rutinas activas que tocan hoy; estado = f(hora actual, hora de inicio, ventana 60 min); en curso = inicio ≤ ahora ≤ inicio+60; sin hora fija van al final y se consideran no evaluables por horario. Eventos multi-día cuentan solo el día de inicio.

## 5. Épica E2: Tareas

Wireframes `TASKS-01` a `TASKS-05`.

| Id | Historia | Criterios de aceptación |
|---|---|---|
| E2-01 | Lista agrupada **[Rediseño]** | Grupos por lista con color, nombre, contador (pendientes + completadas). **Toda la cabecera pliega, no navega.** Dentro: pendientes y luego completadas tachadas. Fila con casilla, título y **etiquetas de persona**; tocar edita |
| E2-02 | Filtro y orden **[Existente]** | Menú de filtro **solo por lista** («Todas» + una por lista). «Editar/OK» reordena solo con lista filtrada y orden «Personalizado». Alta rápida con campo «Nueva tarea» cuando hay filtro de lista |
| E2-03 | Botón de alta **[Rediseño]** | Hoy: botón flotante «Nueva tarea» sobre las filas. Propuesta: moverlo a la cabecera para no tapar contenido **[Nuevo]** |
| E2-04 | Swipe y reorden **[Existente]** | Deslizar elimina **con confirmación [Nuevo]** (D-7, hoy sin ella); arrastrar reordena |
| E2-05 | Estados | Vacío «Sin tareas» / «Crea tu primera tarea y ponle una lista para tenerla a mano.» y la variante con filtro; skeleton, error y sin conexión **[Nuevo]** |
| E2-06 | Listas **[Rediseño]** | Tarjeta con punto de color, nombre y badge de **pendientes**; orden por nombre; botón flotante «Nueva lista». Vacío «Sin listas» / «Las listas agrupan tus tareas: compra, casa, trabajo…» |
| E2-07 | Detalle de lista **[Rediseño]** | Título inline, «Editar lista» y «Reordenar/OK»; alta rápida; «Pendientes» y «Completadas» con swipe; panel **«Personas con acceso»** (propietario: invitar por email y quitar; otros: solo lectura). No tiene «Eliminar» (vive en el editor) |
| E2-08 | Tarea (hoja) | «Título», «Lista» (solo al crear, preselecciona la primera, caso sin listas), panel «Personas» con casilla por persona, aviso «Ya existe una tarea con ese título en la lista», «Eliminar tarea» en edición |
| E2-09 | Lista (editor) | «Nombre», «Color», panel «Orden de las tareas» (Fecha de actualización, Título, Personalizado), panel «Visible en» (Widget y Dashboard, ambos activados por defecto), «Eliminar lista» con «Se eliminará la lista y todas sus tareas.» (solo propietario) |

## 6. Épica E3: Calendario

Wireframes `CAL-01` a `CAL-08`. Segmentos Eventos / Rutinas / Calendarios.

| Id | Historia | Criterios de aceptación |
|---|---|---|
| E3-01 | Eventos Mes/Semana/Día **[Rediseño]** | Conmutador Mes/Semana/Día (defecto Mes), cabecera `‹ rango ›`, cuadrícula L M X J V S D (lunes primero) con hasta 3 puntos de color por día, día seleccionado en círculo de acento, lista del día debajo. «+» en la barra, fecha por defecto = día seleccionado a la hora en punto |
| E3-02 | Fila de evento | Barra de color, fecha-hora, título, cuenta atrás (0–120 min), personas asignadas, marca «Sesión de rutina» |
| E3-03 | Rutinas **[Rediseño]** | Swipe elimina con confirmación **[Nuevo]** (D-7). Separadores «Hoy», «Mañana», «Próxima semana» con contador. Estados por horario: **caducada** (gris, tachada, ✓ «Hecha»), **en curso**, normal; badge «Activa»/«Pausada»; «PRÓXIMA · fecha-hora». Toque = editor. **Sin casilla «Marcar hecha»** |
| E3-04 | Calendarios | Tarjeta con punto, nombre y nº de próximos eventos; tarjeta «Nuevo calendario» al pie (el «+» en cabecera es **[Nuevo]**) |
| E3-05 | Evento (editor) | «Título», «Fecha y hora» (sin fin), «Calendario» (radios al crear; fijo al editar), panel «Aviso» con 7 opciones y su nota, panel «Personas». Eliminar: «Se eliminará el evento.» o, si es sesión de rutina, «Solo se cancelará esta sesión de la rutina.» |
| E3-06 | Rutina (editor) | «Frecuencia» (radios Diaria/Semanal/Mensual), «Cada N» (1–99), círculos de días solo en Semanal (≥1), «Horario», «Estado» (Activa), «Aviso», «Personas». Resumen en lenguaje natural **[Nuevo]**. Validación (alerta): «Revisa la frecuencia, el intervalo, los días y el rango de fechas» |
| E3-07 | Calendario (editor) | «Nombre», «Color», «Visible en»; en edición: panel «Eventos y rutinas», «Personas con acceso» y «Eliminar calendario» («Se eliminará el calendario con sus eventos.», solo propietario) |
| E3-08 | Estados | Skeleton, error y sin conexión **[Nuevo]** en las tres listas; vacíos reales de cada una |

## 7. Épica E4: Hogar

Wireframes `HOGAR-01` a `HOGAR-09`.

| Id | Historia | Criterios de aceptación |
|---|---|---|
| E4-01 | Hogar y miembros **[Rediseño]** | «Hogar activo» con una fila por hogar (tocar cambia de hogar); «Miembros» con permisos en texto y hoja «Permisos del hogar»; tarjeta «Invitar» (si `canInvite`) con «Invitaciones pendientes»; «Administración» siempre visible |
| E4-02 | Aviso de hogar activo no guardado | Hoy texto fijo en la tarjeta. Pasar a toast descartable **[Nuevo]** (P-10) |
| E4-03 | Sin hogar **[Rediseño]** | Creación inline con nombre; invitación pendiente («Tienes una invitación», «Aceptar invitación», «Ahora no») |
| E4-04 | Menú Administración | Seis filas con icono. Visibilidad: Configuración, Administradores, Miembros siempre; Invitaciones si admin o `home.invite`; Accesos y Auditoría solo admin. Resúmenes de una línea **[Nuevo]** |
| E4-05 | Configuración | Nombre y zona horaria (hoja con buscador IANA); miembro en solo lectura; «Registro» (Creado/Actualizado); «Guardar cambios» |
| E4-06 | Administradores | Un panel «Personas del hogar» con hasta 3 chips por fila (Quitar admin, Quitar, Hacer admin, Transferir) y «Salir»; confirmaciones con textos reales; último admin sin acciones destructivas |
| E4-07 | Miembros | Lista plana y editor (nombre, color, tipo Adulto/Niño/Familiar/Invitado/Mascota, estado, cuenta); confirmación al cambiar tipo de un vinculado |
| E4-08 | Invitaciones | Pendientes con «Revocar»; hoja de creación (tipo, vincular a miembro, email); hoja de código **una sola vez** con «Copiar código», «Enviar por WhatsApp» y «Compartir invitación» |
| E4-09 | Accesos | Lista por persona y editor en hoja por dominio con interruptores; «Restablecer a tipo»; «Qué cubre cada tipo». Guardar solo con cambios |
| E4-10 | Auditoría | Páginas de 50, «Cargar más»; mejoras de legibilidad (frases naturales, filtros) **[Nuevo]** y a decidir con el backend |
| E4-11 | Estados de administración | Skeleton, error y sin conexión **[Nuevo]** en las pantallas |

## 8. Épica E5: Ajustes (antes «Perfil») y acceso

Wireframes `AJ-01` a `AJ-05` y `AUTH-01` a `AUTH-03`.

| Id | Historia | Criterios de aceptación |
|---|---|---|
| E5-01 | Ajustes **[Rediseño]** | Título «Ajustes» (D-6). Tarjetas Cuenta (edición inline), Familia (Personas) e Invitaciones («Unirse a un hogar con un código»); «Cerrar sesión» con confirmación «¿Cerrar sesión en este iPhone?»; pie de firma gratuita. Sin hogar activo, Personas e Invitaciones siguen visibles. Avatar, versión y lista agrupada son **[Nuevo]** |
| E5-02 | Editar cuenta **[Nuevo como pantalla]** | Hoy el formulario es inline (nombre 3-50, email, contraseña ≥ 8 opcional). Extraerlo a hoja es propuesta |
| E5-03 | Personas | Fila con lápiz y papelera (borrar con confirmación **[Nuevo]**, D-7), compartidas de solo lectura, vacío «Sin personas» |
| E5-04 | Persona (hoja) | «Nombre (1-50)», «Color» (ColorPicker; muestras fijas = **[Nuevo]**), «Crear persona»/«Guardar» |
| E5-05 | Unirse | Código de 32 caracteres, nota «Solo sirve una vez y caduca a los 7 días», éxito inline «Te has unido a <hogar>» |
| E5-06 | Bienvenida | «Registrarse» solo si `allow_registration`; sin pantalla de comprobación de sesión (restauración síncrona) |
| E5-07 | Login | Tarjeta «Cuenta», «Entrando…», error por alerta con el mensaje del servidor |
| E5-08 | Registro | Tarjeta «Cuenta» (nombre 3-50, email, contraseña ≥ 8) y «Código de invitación» (32 caracteres, opcional); tres mensajes de error de código; tras crear, la invitación queda pendiente y se acepta después |

### Estado de Hogar y Ajustes (2026-11-13)

Auditoría de E4 y E5 contra el código y cierre de lo que faltaba. Hecho:

- **Sin conexión por pantalla (E0-06.5):** `homitaRequiresNetwork()` atenúa y desactiva los botones que escriben (guardar, crear, revocar, restablecer, unirse, iniciar sesión, registrarse, crear hogar). El motivo lo da el banner global.
- **E4-02:** el aviso de hogar activo no guardado es un toast descartable (P-10).
- **E4-04:** el menú Administración muestra resúmenes reales («2 administradores», «3 miembros», «1 pendiente»). Si un resumen falla pone «No se pudo cargar» sin tumbar los demás; mientras carga se ve el subtítulo fijo.
- **E4-05/08/10:** «Creado», «Actualizado», «caduca» y la fecha de auditoría usan `DateDisplay` (antes, texto crudo del servidor).
- **E4-10:** la auditoría tiene filtros «Todo», «Acción ▾» y «Persona ▾» sobre las entradas ya cargadas (el servidor no filtra).
- **E5-03/04:** Personas pinta el error de la primera carga con «Reintentar»; el editor de persona tiene «Eliminar persona» con confirmación.
- **E5-05:** tras unirse con un código aparece «Ver el hogar», que lleva a la pestaña Hogar.
- **E5-01/02:** «Guardar cambios» de la cuenta se activa solo si hay cambios.
- **E0-09:** identificadores `<pantalla>.<elemento>` en Bienvenida, Login, Registro, Sin hogar, Hogar, Administración, Auditoría, Ajustes, Unirse y editores. Los tests de UI siguen localizando por texto: migrarlos es trabajo aparte.

Decisiones tomadas para cerrar los puntos abiertos:

- Los errores de escritura de Administración **siguen en alerta «Aviso / OK»** (los wireframes HOGAR-03…09 lo describen así); el toast con «Reintentar» queda para Tareas, Calendario y Personas.
- La validación de Hogar **sigue en alerta**, no en línea (HOGAR-04 y HOGAR-06 lo piden así). Personas ya valida el nombre en línea.
- **«Guardar» de Accesos se queda en la barra superior**, como cualquier editor modal de la app, y se desactiva sin cambios.
- La **edición de cuenta sigue inline** en Ajustes (AJ-01 es el contrato; AJ-02 era propuesta).
- El **interruptor «Modo oscuro»** de Ajustes se mantiene (no estaba en el wireframe).
- Ajustes **no necesita skeleton**: la sesión se restaura de forma síncrona y no hay nada que cargar.

## 9. Decisiones y preguntas abiertas

Cerradas: P-01 (la pestaña pasa a «Ajustes», D-6), P-02 (rutas de escritura existen), P-03 (borrar lista borra sus tareas), P-08 (el contador de próximos de calendarios es un número suelto), P-12 (la auditoría no filtra en servidor: es parámetro `before_id`/`limit` solamente), P-19 (confirmación en todos los borrados, D-7), P-21 (la caché de lectura se implementa, D-8).

| Id | Pregunta | Supuesto en los wireframes | Afecta |
|---|---|---|---|
| P-05 | ¿Badge numérico en pestañas? | No | E0-08 |
| P-06 | ¿Muestras de color fijas o solo `ColorPicker`? | Muestras + «Personalizado», marcado Nuevo | E2-09, E3-07, E5-04 |
| P-10 | Aviso de hogar activo: ¿se descarta solo? | Toast descartable | E4-02 |
| P-13 | ¿Pedir contraseña actual al cambiarla? | No (el código no lo hace) | E5-02 |
| P-15 | ¿Cerrar sesión sin conexión? | Sí, es local | E5-01 |
| P-17 | Login con error: ¿se conserva la contraseña? | El código no la limpia | E5-07 |
| P-20 | Inter no está en el bundle (hoy Geist): ¿se incorpora Inter o se usa SF Pro? | Inter, según el diseño | E0-01 |
| P-22 | Al quitar la marca manual de rutinas (D-1): ¿se migra o se descarta el estado local existente? | Se descarta (es local por día) | E1-04 |
| P-23 | Auditoría con frases naturales: ¿lo genera el cliente o el servidor? | Cliente, sobre `action` y `payload` | E4-10 |

## 10. Orden de implementación sugerido

1. **E0** (tokens y fuente, cabecera, estados, identificadores). Sin esto no hay base común.
2. **E1 Inicio**: tarjeta Rutinas de hoy (mayor valor, diseño cerrado) y limpieza de cabecera.
3. **E2 Tareas**: casi todo es existente que se rediseña.
4. **E3 Calendario** (rutas de escritura verificadas): rediseño de lista y editores.
5. **E4 Hogar** y **E5 Ajustes/acceso**.

Cada épica en rama propia, con `swift test` de ControlKit y `xcodebuild test` en verde. Con los identificadores de E0-09 se pueden ampliar los tests de UI para cubrir vacío y error con un hogar vacío y con el backend apagado (segunda pasada pendiente de la auditoría).

## 11. Límites

- **Baja fidelidad.** Los iconos y glifos son marcadores, no SF Symbols definitivos. Renderizados en navegador a 390 × 844 pt, sin dispositivo; faltan iPhone chico y Pro Max.
- **Textos de error de servidor** de los wireframes son ejemplos salvo los que `code-facts.md` cita del código.
- **Layout de Semana y Día** (CAL-01) se infirió: el código solo fija la cabecera de rango y la lista del día.
- **Formato del código de invitación** lo genera el servidor; el ejemplo es ilustrativo.
- **Orden de «Hoy» en Rutinas** (con hora, sin hora, caducadas al final) es una lectura de la regla de `RoutineStore`; confirmar con una prueba.
- No se tocó código Swift ni backend.
