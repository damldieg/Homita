# Hechos del código vs wireframes (contrato de la segunda pasada)

Inventario del SwiftUI real (`apps/control-ios/Sources/ControlKit`, rama base `1f48e0f`) contra los wireframes de la primera pasada. Las capturas de la auditoría solo cubren la primera pantalla visible; este documento corrige lo que faltaba o estaba inventado. **Decisiones del usuario (2026-11-12):** paleta e Inter del diseño «Rutinas de hoy»; revisión completa contra el código; rutinas en Inicio **solo automáticas** (sin marca manual); duración fija de 60 min.

## 0. Reglas para los wireframes

1. **Todo elemento real del código aparece.** Si existe hoy, el wireframe lo muestra (textos literales en español incluidos).
2. **Lo nuevo se marca.** Una funcionalidad que el código no tiene lleva `<span class="tagnew">Nuevo</span>` junto al elemento y se lista en «Cambios respecto a la app actual». Los estados skeleton / error de pantalla / sin conexión son nuevos por definición (el código solo tiene un texto «Cargando…», una alerta «Aviso/OK» y `HomeErrorView`): se explica una vez en las notas, sin etiquetar cada frame.
3. **Nada inventado.** Quitar lo que el código no hace y no es una mejora declarada (ver listas «Quitar» por épica).
4. **Los textos reales mandan** (`Sin tareas`, `Sin eventos este día.`…). Si una mejora cambia un texto, se anota como Nuevo.
5. **El «detalle» es el editor.** En iOS no hay fichas de solo lectura de evento, rutina ni calendario: tocar abre el formulario de edición. Los ids `cal-detalle-*` pasan a representar el **editor en modo edición**.
6. Errores de acción hoy = alerta modal «Aviso / OK». Los toasts con «Reintentar» son propuesta (Nuevo).
7. Pull-to-refresh existe en todas las listas: mostrarlo en las notas.
8. Guardar/Crear es un **botón al pie del formulario** («Crear tarea», «Guardar»…), con «Cancelar» a la izquierda de la barra. Mantenerlo salvo mejora declarada.
9. Colores de persona/calendario: hoy `ColorPicker` nativo libre. La paleta de muestras es propuesta (Nuevo) y debe incluir «Personalizado».

## 1. Inicio (HOME-01)

Orden real: saludo → «Hoy · Eventos» → «Tareas pendientes» → «Rutinas de hoy» → **ACCESOS RÁPIDOS** (`+ Tarea`, `+ Evento`).

- Cabecera: «Hola, <nombre de usuario>» («Hola» si vacío) y fecha «EEEEdMMMM» capitalizada. **No** hay nombre de hogar ni botón de hogar (el botón ⌂ es propuesta: Nuevo).
- Navegación de tarjetas: hoy solo el chevron (32×32, «Ir a <título>») navega; la tarjeta entera no. Hacer navegable la tarjeta entera es propuesta (Nuevo).
- Tarjeta Eventos: icono `calendar`, «Hoy · Eventos», contador en píldora. Fila: barra 4×36 con color del calendario, título, **cuenta atrás**, nombre del calendario, hora HH:mm. Cuenta atrás visible solo de 0 a 120 min: «ahora», «en N min», «en H h», «en H h M min». Vacío «Sin eventos hoy».
- Tarjeta Tareas: icono `checklist`, «Tareas pendientes», contador = todas las pendientes. **Una página por lista** con pendientes, con **puntos de paginación** (varias listas). Encabezado de lista: punto de color + nombre. Máx. **5 tareas** por lista, casilla `HomitaCheckbox` (completa al instante). Enlace «**Ver más**» abre Tareas con esa lista desplegada y las otras plegadas. Vacío «Sin tareas pendientes».
- Tarjeta Rutinas: ver §1.1.
- Accesos rápidos: `+ Tarea` (sin listas: alerta «Crea una lista de tareas primero»; con listas, hoja `TaskEditorView`), `+ Evento` (sin calendarios: alerta «Crea un calendario primero»; con calendarios, hoja `EventDetailView`).
- Estados reales: «Cargando…» por tarjeta; error por tarjeta con el mensaje del servidor + «Reintentar»; error de escritura = alerta. Cada sección falla de forma independiente.
- Pantallas completas que sustituyen Inicio (`HomeGate`): cargando hogar (`HomeLoadingView`, «Cargando hogar…»), sin hogar (`NoHomeView`), error («No se pudo cargar tu hogar» + «Reintentar»).
- **Quitar:** vacío global «Hoy no hay nada pendiente» (cada tarjeta tiene el suyo); badge «1/3» en Rutinas; «Ver las N».

### 1.1 Tarjeta «Rutinas de hoy» (diseño del usuario, artifact «Homita – Rutinas de hoy»)

Card radio 28. Cabecera: icono `arrow.triangle.2.circlepath` en baldosa de acento, «Rutinas de hoy», fecha, «Ver todas ›» (44 pt, abre Calendario › Rutinas). Progreso: «N de M hechas» + «Falta 1 / Faltan N / Ahora: <título> / ¡Completo!» y barra de 8 pt.

Estado de cada rutina = f(hora actual, hora de inicio), **sin marca manual** (cambio respecto al código, que hoy guarda marcas locales «hecha» y tiene un círculo «Marcar … como hecha»; se elimina):

| Estado | Regla | Aspecto |
|---|---|---|
| Aún no empieza | > 60 min antes | Fondo `--far-bg`, borde fino, kicker «Siguiente · en 2 h 30 min» (solo la primera) |
| Aviso | ≤ 60 min antes | Fondo ámbar, borde 2 px, icono ⚠ + «Empieza en N min», barra de cuenta atrás y «Empieza a las HH:MM · Faltan N min» |
| En curso | inicio ≤ ahora ≤ inicio + 60 min | Fondo verde, borde 2 px, punto con pulso + «En curso», barra de tiempo transcurrido y «Hasta las HH:MM · Quedan N min» |
| Finalizada | ahora > inicio + 60 min | Pasa sola a «N completadas» (plegable, por defecto desplegada): círculo verde con ✓, título tachado, persona y hora |

Varias a la vez → variante **compacta**: anillo de progreso de 44 pt en lugar de barra; a la derecha hora y «Quedan N min» / «Empieza en N min». Todo hecho: banner verde «Todo hecho por hoy». Avatares de persona con inicial. Sin hora fija: al final.

## 2. Tareas (TASKS-01…05)

**TASKS-01 Lista.** Cabecera: menú de **filtro por lista** («Todas» + una por lista; **no** hay filtro por estado) y «Editar/OK» (reordenar, solo con una lista filtrada y orden «Personalizado»). Botón flotante «Nueva tarea» solo si hay tareas (mover a la cabecera es propuesta: Nuevo). Con lista filtrada: **campo de alta rápida** «Nueva tarea» + `plus.circle.fill`. Grupos por lista: cabecera-botón con chevron + nombre + contador (pendientes + completadas) + color; **toda la cabecera pliega, no navega**. Dentro del grupo: pendientes y luego **completadas tachadas**. Fila: casilla + título + **etiquetas de persona asignada** (badges de color con nombre); tocar = editar; **deslizar para eliminar sin confirmación**. Deep link desde Inicio: despliega solo esa lista. Vacío: «Sin tareas» / «Crea tu primera tarea y ponle una lista para tenerla a mano.» (con filtro: «Esta lista no tiene tareas todavía.») + «Nueva tarea». Cargando «Cargando tareas…».
- **Quitar:** subtítulo «Pendientes · Todas las listas», «+» en cabecera como existente, hoja de filtros por estado/«Aplicar»/«Restablecer», nombre de grupo que navega.

**TASKS-02 Listas.** Sección «Listas» con contador. Tarjeta: punto de color 14 pt, nombre, badge con **tareas pendientes**; navega al detalle. Orden: nombre ascendente. Botón flotante «Nueva lista» (solo si hay listas). Vacío «Sin listas» / «Las listas agrupan tus tareas: compra, casa, trabajo…» + «Nueva lista». **Quitar:** flags Widget/Dashboard en la tarjeta.

**TASKS-03 Detalle de lista.** Título inline = nombre. Barra: «Editar lista» y «Reordenar/OK». **Alta rápida** arriba. Secciones «Pendientes» y «Completadas» con contador; swipe eliminar; reorden solo pendientes con orden «Personalizado». Filas con etiquetas de persona. Vacío: tarjeta «Sin tareas». **Panel «Personas con acceso»** (compartir la lista): filas nombre + email + badge «Propietario» / «Solo lectura»; el propietario ve botón quitar por fila (no la propia), campo «Email a invitar» y «Invitar». **Quitar:** «Eliminar lista» en el detalle (vive en el editor de lista).

**TASKS-04 Tarea.** Hoja «Nueva tarea» / «Editar tarea». Campos: «Título»; «Lista» (radios, **solo al crear**; preselecciona la primera; sin listas: «Todavía no tienes listas. Crea una en la pestaña Listas para añadir tareas.»); panel **«Personas»** con contador (casilla + color + nombre; vacío «Aún no tienes personas. Créalas en Perfil › Personas.»). Botón «Crear tarea»/«Guardar»; edición añade «Eliminar tarea» (sin confirmación hoy; confirmación = Nuevo). Aviso «Ya existe una tarea con ese título en la lista» (solo al crear). **Quitar:** mensajes de validación en línea (Nuevo si se mantienen).

**TASKS-05 Lista (editor).** «Nueva lista» / «Editar lista». Panel «Lista»: «Nombre», «Color» (ColorPicker nativo). Panel **«Orden de las tareas»**: «Fecha de actualización» (defecto), «Título», «Personalizado» + nota «Podrás reordenar las tareas con el botón Editar.». Panel **«Visible en»**: toggles «Widget» y «Dashboard», **ambos activados por defecto**. Botón «Crear lista»/«Guardar»; edición añade «Eliminar lista» + confirmación «Se eliminará la lista y todas sus tareas.» (solo propietario, cascada). Resuelve P-03: **se borran sus tareas**.

## 3. Calendario (CAL-01…08)

Resuelve P-02: **existen** las rutas de escritura: `event/create|update|alarm|delete`, `calendar/create|update|delete|user`, `routine/create|update|delete|alarm`.

**CAL-01 Eventos.** **No es una lista agrupada por día.** Conmutador **Mes | Semana | Día** (defecto Mes); cabecera `‹ rango ›` con título «Noviembre 2026» / «12 nov – 18 nov» / «Jueves 12 noviembre»; **cuadrícula** L M X J V S D (lunes primero), celdas 34 pt, día seleccionado en círculo de acento, hasta 3 puntos de color por día, días fuera de mes atenuados; debajo, la **lista del día seleccionado** (cabecera = día + contador). Fila de evento: barra de color 5 pt, fecha-hora, título, cuenta atrás (0–120 min, color acento), personas asignadas, marca «Sesión de rutina» si viene de una rutina. «+» en la barra («Nuevo evento»; fecha por defecto = día seleccionado a la hora en punto). Vacío del día: «Sin eventos este día.» + «Nuevo evento». Cargando «Cargando calendario…». **Quitar:** vista solo-lista, nombre de calendario en la fila, etiquetas «Hoy/Mañana» (esas son de Rutinas).

**CAL-02 Rutinas.** Separadores **«Hoy», «Mañana», «Próxima semana»** con contador (se omiten vacíos). Reglas: **«Hoy» lista todas las rutinas que tocan hoy** (por sesión generada o, si no la hay, por su regla; en curso, por empezar o caducadas; activas y pausadas), con hora fija primero, sin hora después y las caducadas al final. «Mañana» por fecha de la próxima sesión (o por regla sin sesiones); «Próxima semana» el resto, sin repetir lo que ya sale en Hoy. Estado por horario (ventana 60 min): **caducada** (fondo gris, opacidad .7, título tachado, icono ✓ «Hecha»), **en curso** (fondo de acento suave), normal. Fila: barra de color del calendario, título, hora o «Sin hora», etiquetas de persona, «PRÓXIMA · fecha-hora», badge **«Activa» (verde) / «Pausada» (gris)** siempre. Toque = editor. **Deslizar para eliminar sin confirmación.** «+» («Nueva rutina»). Vacío: «Sin rutinas» / «Las rutinas repiten eventos cada día, semana o mes sin que las vuelvas a escribir.» + «Nueva rutina». **Quitar:** casilla «Marcar hecha» y toast asociado (no existe); badge «1/2».

**CAL-03 Calendarios.** Sección «Calendarios» con contador; tarjeta: punto 14 pt, nombre, badge con nº de **próximos eventos**; **no hay «+» en la cabecera**: hay tarjeta «Nuevo calendario» (+) al pie (el «+» en cabecera es Nuevo). Vacío «Sin calendarios» / «Los calendarios agrupan eventos y rutinas por color, como Trabajo o Familia.» + «Nuevo calendario».

**CAL-04 Calendario (modo edición, antes «detalle»).** Mismo formulario que el alta, más: panel «Calendario» («Nombre», «Color»), **«Visible en»** (Widget, Dashboard, ambos activados por defecto), panel **«Eventos y rutinas»** con contador (mezcla eventos futuros —título + fecha-hora— y rutinas —«Rutina · HH:mm»—; vacío «No hay eventos ni rutinas vinculados a este calendario.»), botón «Guardar», panel **«Personas con acceso»** (igual que en listas de tareas), «Eliminar calendario» + confirmación «Se eliminará el calendario con sus eventos.» (solo propietario).

**CAL-05 Evento.** «Nuevo evento»/«Editar evento». Panel «Evento»: «Título», selector «Fecha y hora» (**sin fecha de fin**: el modelo no la tiene), «Calendario» (radios al crear; en edición, texto fijo no editable). Panel **«Aviso»** (campana): «Sin aviso», «Justo antes», «10/20/30/40/60 min antes» + nota «La alarma se guarda en el servidor. El aviso en este iPhone llegará con las notificaciones (fase 3).». Panel **«Personas»** (casilla; vacío «Aún no tienes personas. Créalas en Perfil › Personas.»). Botón «Crear evento»/«Guardar»; edición: «Eliminar evento» + confirmación «Se eliminará el evento.» (sesión de rutina: «Solo se cancelará esta sesión de la rutina.»). Validación (alerta): «El título es obligatorio», «La fecha es obligatoria».

**CAL-06 Rutina.** Paneles: «Rutina» («Título», «Calendario» radios solo al crear); **«Frecuencia»** (radios Diaria/Semanal/Mensual; Stepper «Cada N día(s)/semana(s)/mes(es)» 1–99; **fila de 7 círculos L M X J V S D** solo si Semanal, ≥1 día); «Horario» (Hora, Inicio, toggle «Fecha fin» → «Fin»); «Estado» (toggle «Activa»); «Aviso»; «Personas»; botón «Crear rutina»/«Guardar»; edición «Eliminar rutina» + «Se eliminará la rutina y sus sesiones futuras.». Error de validación (alerta): «Revisa la frecuencia, el intervalo, los días y el rango de fechas». **Nuevo:** resumen en lenguaje natural bajo la frecuencia.

**CAL-07 Calendario (alta).** Ver CAL-04 sin los paneles de edición.

**CAL-08 Rutina (modo edición, antes «detalle»).** Mismo editor CAL-06 con datos. **Quitar:** «Próximas sesiones», resumen de solo lectura y «No quedan sesiones» (no existen). Las sesiones son eventos con «Sesión de rutina»; editar una crea una excepción.

## 4. Hogar (HOGAR-01…09)

**HOGAR-01.** Orden: título → «Hogar activo» → «Miembros» → tarjeta **«Invitar»** (si `canInvite`) → «Administración» (siempre visible; solo título + chevron). «Hogar activo»: **una fila por hogar**, siempre visible (nombre, «Administrador»/«Miembro», badge «Activo»; tocar cambia de hogar), header con contador, sin hoja. Error persistir hogar activo: texto fijo «No se pudo guardar el hogar activo: seguirá activo en esta sesión, pero al reabrir la app volverá el predeterminado.» (pasar a toast = Nuevo). Miembros: avatar inicial, nombre, badge «tú», «Tipo · Rol» (rol solo cuentas), permisos como **texto** (3 primeros, «Ver más» → hoja **«Permisos del hogar»** con la lista completa y «Cerrar»). Tipos: Adulto/Niño/Familiar/Invitado/Mascota. No hay badges «Vinculada/Sin cuenta» aquí. Tarjeta Invitar: «Invitar», «Crea un código de invitación y compártelo. Solo se muestra al crearlo.», «Crear invitación», fila «Invitaciones pendientes». Vacío «Sin miembros»; error = texto del servidor + «Reintentar». **Quitar:** «Permisos 4 de 6», «Tus permisos…», subtítulo y badge «Solo lectura» en Administración. El miembro ve permisos de todos.

**HOGAR-02 Sin hogar.** Panel «No tienes ningún hogar» / «Crea uno para empezar a usar tareas y calendarios.», campo «Nombre del hogar», «Crear hogar» (solo `name`, sin zona horaria). Si hay invitación pendiente: panel «Tienes una invitación» / «Aceptarla te une al hogar. Hasta que la aceptes, la invitación queda en espera.» + «Aceptar invitación» y «Ahora no». **Quitar:** «Unirse con código» (vive en Perfil). Resuelve el destino de «Crear hogar».

**HOGAR-03 Administración.** Título = nombre del hogar. Filas con icono: Configuración (`gearshape`), Administradores (`person.badge.key`), Miembros (`person.2`), Invitaciones (`envelope.badge`), Accesos (`lock.shield`), Auditoría (`list.bullet.clipboard`). **Visibilidad:** Configuración, Administradores y Miembros siempre; Invitaciones si admin o miembro con `home.invite`; Accesos y Auditoría **solo admin** (ocultas). Los resúmenes de una línea son Nuevo.

**HOGAR-04 Configuración.** Pantalla empujada. «Hogar»: admin = «Nombre» + fila «Zona horaria» (abre hoja con buscador IANA, check, «Cerrar»); miembro = filas de solo lectura. Hogar personal: nota «Hogar personal». Panel «Registro»: «Creado», «Actualizado». Botón «Guardar cambios» (siempre activo). Validación (alerta): «El nombre es obligatorio», «El nombre admite como máximo 50 caracteres», «Zona horaria no válida». Tras guardar no cierra.

**HOGAR-05 Administradores.** **Un solo panel «Personas del hogar»** (contador): nombre, «(tú)», badge «Administrador»/«Miembro», email, y **hasta 3 chips de acción por fila**: «Quitar admin», «Quitar», «Hacer admin», «Transferir»; «Salir» en la fila propia (no personal). Último admin: se ocultan Quitar admin/Quitar/Salir. Confirmaciones (diálogo nativo): «¿Quitar a X del hogar?», «¿Salir de este hogar?», «¿Transferir la administración a X? Pasarás a ser miembro.», «¿Quitar el rol de administrador a X?»; «Hacer admin» sin confirmación. Errores: «No se puede completar la acción: el hogar debe conservar al menos un administrador». Miembro: solo «Salir». **Quitar:** «Propietaria», paneles separados.

**HOGAR-06 Miembros.** Panel «Miembros» con contador; fila: punto de color 14 pt, nombre, «Tipo · Estado · Vinculada|Sin cuenta», inactivo opacidad .6; lista plana. Admin: tocar = editor, «+»; miembro: solo lectura. Editor (hoja «Nuevo miembro»/«Editar miembro»): «Nombre (1-50)», «Color», «Tipo» (radios; Mascota oculta si vinculado), edición: «Estado» (radios Activo/Inactivo) y fila «Cuenta». Botón «Agregar»/«Guardar». Confirmación al cambiar tipo de vinculado: «Cambiar el tipo restablece los permisos de esta persona a los valores del nuevo tipo». Vacío «Sin miembros».

**HOGAR-07 Invitaciones.** Panel «Pendientes» con contador; fila: nombre del miembro o tipo, «[email · ]Tipo · caduca <fecha>», chip «Revocar» («¿Revocar la invitación? El código dejará de funcionar.»). «+» siempre visible. Vacío «Sin invitaciones pendientes». **Crear** (hoja «Nueva invitación»): panel «Tipo» (Adulto solo admin, Mascota nunca), «Vincular a un miembro (opcional)» (radio «Ninguno» + miembros sin cuenta; nota «Solo miembros sin cuenta. Al aceptar, la cuenta queda vinculada a ese miembro.»), «Email del invitado» (nota «La invitación solo se puede aceptar con esta cuenta de email…»), botón «Crear». **Código** (hoja «Invitación creada», «Listo»): código en monoespaciado, «Solo se muestra una vez. Compártelo con la persona invitada; caduca en 7 días.», «Copiar código», **«Enviar por WhatsApp»**, «Compartir invitación».

**HOGAR-08 Accesos (solo admin).** Panel «Accesos por persona»: nombre, «Administrador: todos los accesos» o «N accesos», motivo de bloqueo, chip «Editar». Panel «Qué cubre cada tipo». Editor = **hoja por persona**: un panel por dominio con un interruptor por permiso (descripción + código en mono); «Restablecer a tipo» + «Se sobrescribirán los accesos personalizados de X con los de su tipo.»; «Guardar» solo con cambios. Aviso «Este miembro tiene accesos no reconocidos…».

**HOGAR-09 Auditoría (solo admin).** Filas: acción técnica, «<actor o Sistema> · <fecha>», líneas del payload. Páginas de **50** con «Cargar más». Sin vacío, sin filtros, sin contador. Miembro: «Solo un administrador puede ver la auditoría». **Quitar:** frases naturales, filtros, avatar (mejoras = Nuevo si se mantienen).

## 5. Ajustes (pestaña «Perfil») y acceso (AJ-01…05, AUTH-01…03)

**AJ-01 Perfil.** Tres tarjetas: **Cuenta** (formulario inline: «Nombre», «Email», «Nueva contraseña (opcional, mínimo 8)», «Guardar cambios»; nombre 3-50), **Familia** (fila «Personas»), **Invitaciones** («Unirse a un hogar con un código»). **Sin hogar activo, Personas e Invitaciones siguen visibles.** «Cerrar sesión» botón secundario ancho completo → «¿Cerrar sesión en este iPhone?» [Cerrar sesión]. Pie: «Con firma gratuita la app caduca a los 7 días; reinstálala y vuelve a iniciar sesión.». Guardando: overlay «Guardando…». **Nuevo:** avatar, versión, lista agrupada, pantalla de edición de cuenta (AJ-02 es propuesta: hoy es inline).

**AJ-03 Personas.** Sección «Personas» con contador; fila: círculo 14 pt, nombre, **lápiz y papelera** (papelera borra **sin confirmación**); compartidas: badge «Compartida (solo lectura)» sin acciones. Vacío «Sin personas». «+» «Nueva persona». Pull-to-refresh.

**AJ-04 Persona.** Hoja «Nueva persona»/«Editar persona»; panel «Persona»; «Nombre (1-50)», «Color» (ColorPicker; defecto `#6923E2`); «Crear persona»/«Guardar». Error (alerta): «El nombre debe tener 1-50 caracteres y el color formato #RRGGBB». «Eliminar» dentro del formulario es Nuevo.

**AJ-05 Unirse.** Panel «Código de invitación» (placeholder «32 caracteres»), nota «Pídeselo a un administrador del hogar. Solo sirve una vez y caduca a los 7 días.», botón «Unirse» (activo con código de 32 caracteres). Éxito **inline** «Listo — Te has unido a <hogar>»; el hogar pasa a activo. Cargando «Uniéndote…».

**AUTH-01 Bienvenida.** Logo «H» 96 pt (`Palette.warm`), «Homita», «Tu panel de control familiar», «Iniciar sesión», «Registrarse» **solo si `allow_registration`** (si no, no hay botón ni texto). La sesión se restaura **sincrónicamente** desde Keychain: **no hay pantalla de comprobación de sesión.** **Quitar:** «Comprobando tu sesión…» y «Registro cerrado» con enlace (Nuevo si se propone).

**AUTH-02 Login.** Tarjeta «Cuenta»: «Email», «Contraseña», «Iniciar sesión» (activo con ambos no vacíos). Error = alerta con el mensaje del servidor. Cargando «Entrando…».

**AUTH-03 Registro.** Tarjeta «Cuenta»: «Nombre» (3-50), «Email», «Contraseña (mínimo 8)». Tarjeta «Código de invitación»: «Código (opcional)» (32 caracteres) + «Si te invitaron a un hogar, usa el email de la invitación. Sin código, se crea una cuenta nueva.». «Crear cuenta». Errores (alerta): 404 «El código de invitación no es válido, ya se usó o ha caducado», 403 «La invitación se envió a otro email. Usa el email de la invitación», 400 «Ya tienes cuenta: inicia sesión y acepta la invitación desde Perfil». Tras crear, la invitación queda **pendiente** y se acepta después. Cargando «Creando cuenta…».

## 6. Pestañas

Pestañas reales: Inicio (`house`), Tareas (`checklist`), Calendario (`calendar`), Hogar (`person.2`), **Perfil** (`person.crop.circle`). **Decisión del usuario: la 5.ª pestaña pasa a llamarse «Ajustes»** (los wireframes ya la muestran así). Los textos del código que citan «Perfil» (p. ej. «Créalas en Perfil › Personas.») deben actualizarse a «Ajustes».
