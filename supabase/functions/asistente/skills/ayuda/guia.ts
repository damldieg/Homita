// Guía de la app para la skill `ayuda`: secciones cortas, escritas para usuarios, con los nombres de pantallas y
// botones tal como aparecen en la app. Datos puros (sin lógica).
//
// Fuente: el código de `apps/control-ios` (no `docs/ios-funcional.md`, que puede ir por detrás). Referencias:
// RootView.swift (pestañas y Ajustes), TaskEditorView/TaskListEditorView/TaskListDetailView, EventDetailView,
// RoutineEditorView, CalendarDetailView, HogarView, HomeAdminViews, ProfileView, FeedbackCatalog,
// NotificationSettingsView, WelcomeView/LoginView/RegisterView. Si la app cambia, se cambia aquí y en el test de
// cobertura (tests/ayuda_cobertura_test.ts).
//
// Reglas: `texto` ≤ ~600 caracteres; `palabras` = sinónimos y variantes que el usuario podría escribir (se
// normalizan al buscar, así que da igual acentos y mayúsculas); `id` único.

export interface Seccion {
    id: string;
    titulo: string;
    palabras: string[];
    texto: string;
}

export const GUIA: Seccion[] = [
    {
        id: "navegacion",
        titulo: "Pestañas de la app",
        palabras: ["pestañas", "menu", "barra", "pantallas", "navegar", "donde esta", "secciones", "inicio", "ajustes"],
        texto:
            "La barra de abajo tiene cinco pestañas: Inicio, Tareas, Calendario, Menú (comidas y compra) y Hogar. " +
            "Ajustes no es una pestaña: se abre con el engranaje de arriba a la derecha en Inicio.",
    },
    {
        id: "inicio",
        titulo: "Inicio",
        palabras: ["inicio", "pantalla de inicio", "resumen", "hoy", "dia", "accesos", "crear rapido", "engranaje", "tarjetas", "bloques"],
        texto:
            "Inicio resume el día: «Hoy · Eventos», «Tareas pendientes» y «Rutinas de hoy». Arriba a la derecha " +
            "tiene el botón «+» (Crear › Tarea o Evento) y el engranaje de Ajustes. Para ordenar u ocultar bloques: " +
            "Ajustes › Inicio › Orden y bloques ocultos.",
    },
    {
        id: "tareas",
        titulo: "Pestaña Tareas",
        palabras: ["pendientes", "filtrar", "mis tareas", "completar", "marcar hecha", "ver tareas", "agrupadas"],
        texto:
            "Tareas tiene dos segmentos: «Tareas» (agrupadas por lista) y «Listas». En «Tareas» marcas una tarea como " +
            "hecha tocando su casilla, la abres tocándola, y con el icono de filtro eliges «Mis tareas», una persona " +
            "o una lista. El «+» de arriba crea una tarea; el «+» de cada grupo la crea en esa lista.",
    },
    {
        id: "tarea-nueva",
        titulo: "Crear una tarea",
        palabras: ["nueva tarea", "anadir tarea", "agregar tarea", "crear tarea", "apuntar", "pendiente"],
        texto:
            "Tareas › «+» (arriba) › Nueva tarea: escribe el Título, elige la Lista, y si quieres la Prioridad, la " +
            "Fecha límite y las Personas. Pulsa «Crear tarea». Más rápido: dentro de una lista (Tareas › Listas › la " +
            "lista) escribe en el campo «Nueva tarea» y pulsa el «+». También desde Inicio › «+» › Tarea. " +
            "Hace falta tener al menos una lista.",
    },
    {
        id: "tarea-editar",
        titulo: "Editar, completar o borrar una tarea",
        palabras: ["editar tarea", "modificar tarea", "cambiar tarea", "borrar tarea", "eliminar tarea", "quitar tarea", "completar", "hecha"],
        texto:
            "Para completarla toca su casilla. Para editarla, tócala: se abre «Editar tarea» (Título, Prioridad, Fecha " +
            "límite, Personas) y pulsas «Guardar». Para borrarla, desliza la fila hacia la izquierda o usa «Eliminar " +
            "tarea» dentro de la edición; te pedirá confirmar. Una tarea no se puede mover a otra lista. En una lista, " +
            "el icono de papelera de «Completadas» borra todas las hechas.",
    },
    {
        id: "tarea-prioridad-fecha",
        titulo: "Prioridad y fecha límite de una tarea",
        palabras: ["prioridad", "alta", "media", "baja", "urgente", "fecha limite", "vencimiento", "vence", "plazo", "caduca", "ordenar"],
        texto:
            "En el editor de la tarea (Nueva tarea o Editar tarea) elige la Prioridad (Alta, Media o Baja; por defecto " +
            "Media). Activa «Fecha límite» y elige cuándo «Vence» (día y hora). En Tareas, el icono de ordenar y " +
            "filtrar de arriba permite ordenar por prioridad o ver solo una.",
    },
    {
        id: "listas",
        titulo: "Listas de tareas",
        palabras: ["listas", "ver listas", "listado", "mis listas", "tareas listas", "lista de la compra"],
        texto:
            "Tareas › segmento «Listas» muestra tus listas con el número de tareas pendientes. Tócala para abrirla: " +
            "ves sus tareas «Pendientes» y «Completadas», puedes añadir tareas, y abajo están las «Personas con " +
            "acceso». La lista de la compra de comidas es otra cosa: está en Menú › Compra.",
    },
    {
        id: "lista-nueva",
        titulo: "Crear una lista",
        palabras: ["nueva lista", "crear lista", "anadir lista", "agregar lista", "hacer una lista"],
        texto:
            "Tareas › segmento «Listas» › «Nueva lista». Escribe el Nombre, elige el Color y el Orden de las tareas " +
            "(Fecha de actualización, Título o Personalizado), y decide si se ve en Widget y Dashboard. Pulsa «Crear lista».",
    },
    {
        id: "lista-editar",
        titulo: "Editar o borrar una lista",
        palabras: ["editar lista", "modificar lista", "renombrar lista", "cambiar nombre lista", "borrar lista", "eliminar lista", "quitar lista", "reordenar"],
        texto:
            "Tareas › Listas › abre la lista › «Editar lista». Cambia Nombre, Color, Orden o dónde se ve y pulsa " +
            "«Guardar»; «Eliminar lista» la borra con todas sus tareas (te pide confirmar). Nombre, color, orden y " +
            "borrado son solo de quien creó la lista. Con orden Personalizado aparece «Reordenar» para mover tareas.",
    },
    {
        id: "compartir-lista",
        titulo: "Compartir una lista y dar permiso de edición",
        palabras: [
            "compartir lista", "compartir una lista", "comparto lista", "dar acceso", "permiso", "permisos", "edicion", "lectura",
            "solo lectura", "invitar a una lista", "quien ve la lista", "compartir con",
        ],
        texto:
            "Tareas › Listas › abre la lista › baja a «Personas con acceso». Si eres el propietario, junto a cada " +
            "persona del hogar con cuenta pulsa «Dar acceso» y elige «Lectura» (solo ve) o «Edición» (puede cambiar). " +
            "También puedes escribir un email en «Email a invitar» y pulsar «Invitar». Quitar a alguien: el icono de " +
            "persona con un menos. Si no eres el propietario, solo ves los permisos.",
    },
    {
        id: "asignar-personas",
        titulo: "Asignar personas a tareas, eventos y rutinas",
        palabras: ["asignar", "asignacion", "responsable", "encargado", "quien hace", "personas", "mencionar", "para quien"],
        texto:
            "En los editores de tarea, evento y rutina hay un panel «Personas»: marca las que corresponda. Las " +
            "personas se crean en Ajustes › Personas. Al crear una tarea solo se ofrecen las personas con cuenta y " +
            "acceso a esa lista. En el campo rápido de una lista también hay un selector de personas junto al «+».",
    },
    {
        id: "calendario",
        titulo: "Pestaña Calendario",
        palabras: ["agenda", "semana", "dia", "ver eventos", "elegir fecha", "calendario"],
        texto:
            "Calendario tiene tres segmentos: «Eventos», «Rutinas» y «Calendarios». En Eventos ves el día elegido con " +
            "la tira de la semana, flechas para cambiar de semana, «Hoy» y el selector de fecha («Elegir fecha»). " +
            "Los eventos se agrupan en calendarios y las rutinas son cosas que se repiten.",
    },
    {
        id: "evento-nuevo",
        titulo: "Crear un evento",
        palabras: ["nuevo evento", "crear evento", "anadir evento", "agregar evento", "cita", "agendar", "reunion", "cumpleanos", "apuntar evento"],
        texto:
            "Calendario › segmento «Eventos» › «Nuevo evento» (o Inicio › «+» › Evento). Escribe el Título, la Fecha y " +
            "hora, y si dura varios días activa «Fecha de fin». Elige el Calendario, el Aviso (Sin aviso, Justo antes o " +
            "10 a 60 min antes) y las Personas. Pulsa «Crear evento». Hace falta tener al menos un calendario.",
    },
    {
        id: "evento-editar",
        titulo: "Editar o borrar un evento",
        palabras: ["editar evento", "modificar evento", "cambiar evento", "mover evento", "cambiar fecha", "borrar evento", "eliminar evento", "cancelar evento", "quitar evento"],
        texto:
            "Calendario › Eventos › toca el evento: se abre «Editar evento». Cambia Título, Fecha y hora, Fecha de fin, " +
            "Aviso o Personas y pulsa «Guardar». «Eliminar evento» lo borra (pide confirmar). El calendario de un " +
            "evento ya creado no se puede cambiar.",
    },
    {
        id: "rutinas",
        titulo: "Rutinas",
        palabras: ["rutinas", "ver rutinas", "habitos", "repetir", "repeticion", "proxima", "hecha", "pausada"],
        texto:
            "Calendario › segmento «Rutinas» lista las rutinas con su próxima vez («PRÓXIMA») y si están «Activa» o " +
            "«Pausada». Una rutina es algo que se repite (por ejemplo, sacar al perro cada mañana); un evento ocurre " +
            "una vez en una fecha. En Inicio, «Rutinas de hoy» muestra las de hoy.",
    },
    {
        id: "rutina-nueva",
        titulo: "Crear una rutina",
        palabras: ["nueva rutina", "crear rutina", "anadir rutina", "agregar rutina", "repetir cada", "diaria", "semanal", "mensual", "frecuencia", "horario"],
        texto:
            "Calendario › «Rutinas» › «+» (arriba) › Nueva rutina. Escribe el Título y elige el Calendario. En " +
            "Frecuencia pon Diaria, Semanal (con los días) o Mensual y «Cada N». En Horario fija la Hora, el Inicio y, " +
            "si quieres, «Fecha fin». Deja «Activa» marcada, elige Aviso y Personas, y pulsa «Crear rutina».",
    },
    {
        id: "rutina-editar",
        titulo: "Editar o borrar una rutina",
        palabras: ["editar rutina", "modificar rutina", "cambiar rutina", "pausar rutina", "borrar rutina", "eliminar rutina", "quitar rutina", "desactivar"],
        texto:
            "Calendario › Rutinas › toca la rutina: «Editar rutina». Cambia lo que quieras (para pausarla, desmarca " +
            "«Activa») y pulsa «Guardar». Para borrarla, «Eliminar rutina» dentro de la edición o desliza la fila; " +
            "se borra con sus sesiones futuras y pide confirmar.",
    },
    {
        id: "calendarios",
        titulo: "Calendarios",
        palabras: ["calendarios", "ver calendarios", "mis calendarios", "agendas"],
        texto:
            "Calendario › segmento «Calendarios» lista tus calendarios con el número de eventos próximos. Tócalo para " +
            "abrirlo: ves sus eventos y rutinas, y puedes editarlo, compartirlo o borrarlo. Cada evento y cada " +
            "rutina pertenece a un calendario.",
    },
    {
        id: "calendario-nuevo",
        titulo: "Crear un calendario",
        palabras: ["nuevo calendario", "crear calendario", "anadir calendario", "agregar calendario", "agenda nueva"],
        texto:
            "Calendario › segmento «Calendarios» › «Nuevo calendario». Escribe el Nombre, elige el Color y decide si " +
            "se ve en Widget y Dashboard. Pulsa «Crear calendario».",
    },
    {
        id: "calendario-editar",
        titulo: "Editar o borrar un calendario",
        palabras: ["editar calendario", "modificar calendario", "renombrar calendario", "borrar calendario", "eliminar calendario", "quitar calendario"],
        texto:
            "Calendario › Calendarios › toca el calendario: «Editar calendario». Cambia Nombre, Color o dónde se ve y " +
            "pulsa «Guardar». «Eliminar calendario» lo borra junto con sus eventos y pide confirmar.",
    },
    {
        id: "color-calendario",
        titulo: "Cambiar el color de un calendario, lista o persona",
        palabras: ["color", "colores", "cambiar color", "color calendario", "pintar", "tono", "personalizado", "color de un calendario"],
        texto:
            "Calendario › Calendarios › toca el calendario › en «Color» toca una de las muestras (o «Personalizado» " +
            "para elegir otro) y pulsa «Guardar». Igual en las listas (Tareas › Listas › la lista › «Editar " +
            "lista») y en las personas (Ajustes › Personas).",
    },
    {
        id: "compartir-calendario",
        titulo: "Compartir un calendario y dar permiso de edición",
        palabras: [
            "compartir calendario", "compartir un calendario", "comparto calendario", "dar acceso", "permiso", "permisos", "edicion",
            "lectura", "solo lectura", "invitar a un calendario", "quien ve el calendario",
        ],
        texto:
            "Calendario › Calendarios › abre el calendario › baja a «Personas con acceso». Si eres el propietario, " +
            "junto a cada persona con cuenta pulsa «Dar acceso» y elige «Lectura» o «Edición». O escribe un email en " +
            "«Email a invitar» y pulsa «Invitar». Para quitar a alguien, el icono de persona con un menos. Si no " +
            "eres el propietario, solo ves los permisos.",
    },
    {
        id: "avisos",
        titulo: "Avisos y notificaciones",
        palabras: ["avisos", "aviso", "notificaciones", "alarma", "recordatorio", "recordar", "alerta", "widgets", "pantalla de bloqueo", "avisar"],
        texto:
            "Cada evento y rutina tiene su «Aviso» (Sin aviso, Justo antes, 10, 20, 30, 40 o 60 min antes). Para " +
            "activar los avisos: Ajustes › «Avisos, widgets y pantalla de bloqueo», con los interruptores «Eventos» " +
            "y «Rutinas», «Rutinas en tiempo real» (pantalla de bloqueo) y «Datos en widgets». Si iOS los tiene " +
            "bloqueados, usa «Abrir Ajustes de iOS».",
    },
    {
        id: "resumen-tareas",
        titulo: "Resumen de tareas pendientes",
        palabras: ["resumen", "resumen diario", "digest", "tareas pendientes", "aviso diario", "resumen de tareas", "hora del resumen", "cada dia"],
        texto:
            "Ajustes › «Avisos, widgets y pantalla de bloqueo»: activa «Resumen de tareas pendientes» y elige la «Hora " +
            "del resumen». También hay «Resumen diario» con tus tareas pendientes y eventos de hoy, con su propia " +
            "hora; se omite si no hay nada.",
    },
    {
        id: "menu",
        titulo: "Pestaña Menú: semana, compra y recetas",
        palabras: ["menu", "comidas", "comida", "compra", "lista de la compra", "recetas", "semana", "cena", "almuerzo", "perfil de comidas"],
        texto:
            "Menú tiene tres segmentos: «Semana» (el plan de comidas), «Compra» (la lista de la compra del hogar; " +
            "tocar una fila la marca o desmarca) y «Recetas». Las preferencias de comidas están en Hogar › Comidas.",
    },
    {
        id: "hogar",
        titulo: "Pestaña Hogar",
        palabras: ["hogar", "casa", "familia", "miembros", "quien esta", "ver miembros", "permisos del hogar"],
        texto:
            "Hogar muestra el «Hogar activo», los «Miembros» (con su tipo, si tienen cuenta y sus permisos; «Ver más» " +
            "abre el catálogo), «Invitar» (si tienes permiso), «Comidas» y «Administración».",
    },
    {
        id: "cambiar-hogar",
        titulo: "Cambiar de hogar",
        palabras: ["cambiar de hogar", "otro hogar", "hogar activo", "varios hogares", "elegir hogar", "cambiar hogar", "mis hogares"],
        texto:
            "Hogar › «Hogar activo»: toca el hogar que quieras usar (el actual lleva la etiqueta «Activo»). Las " +
            "pestañas se recargan con los datos de ese hogar. Si aún no tienes ninguno, la app te ofrece «Crear hogar».",
    },
    {
        id: "invitar-hogar",
        titulo: "Invitar a alguien al hogar",
        palabras: [
            "invitar", "invitacion", "invitaciones", "invitar al hogar", "anadir miembro", "agregar persona al hogar", "codigo de invitacion",
            "meter a alguien", "unir a alguien", "invitar a alguien",
        ],
        texto:
            "Hogar › «Invitar» › «Crear invitación» (solo administradores o miembros con permiso de invitar). Elige el " +
            "Tipo, opcionalmente «Vincular a un miembro», escribe el «Email del invitado» y pulsa «Crear». Te da un " +
            "código que solo se ve una vez: «Copiar código», «Enviar por WhatsApp» o «Compartir invitación». Caduca en " +
            "7 días. Las pendientes: Hogar › «Invitaciones pendientes».",
    },
    {
        id: "unirse-hogar",
        titulo: "Unirse a un hogar con un código",
        palabras: ["unirse", "aceptar invitacion", "tengo un codigo", "codigo", "entrar a un hogar", "me invitaron", "usar codigo"],
        texto:
            "Ajustes (engranaje de Inicio) › «Unirse a un hogar con un código»: escribe el código y pulsa «Unirse». " +
            "Luego «Ver el hogar». Si todavía no tienes ningún hogar, la pantalla inicial también te deja «Aceptar " +
            "invitación» o crear uno con «Crear hogar».",
    },
    {
        id: "vincular-persona",
        titulo: "Vincular una persona del hogar a una cuenta",
        palabras: ["vincular", "vinculada", "vincular persona", "unir persona a cuenta", "sin cuenta", "asociar cuenta", "ligar", "cuenta de una persona"],
        texto:
            "La vinculación se hace al invitar: Hogar › «Crear invitación» › «Vincular a un miembro (opcional)» y " +
            "eliges a la persona sin cuenta. Cuando la invitada acepte, su cuenta queda vinculada a esa persona (en " +
            "Hogar aparece «Vinculada»; sin cuenta, «Sin cuenta»). Solo se puede vincular a personas sin cuenta, " +
            "no a mascotas.",
    },
    {
        id: "administracion",
        titulo: "Administración del hogar",
        palabras: [
            "administracion", "administrar", "admin", "administrador", "configuracion", "zona horaria", "nombre del hogar",
            "transferir", "auditoria", "accesos", "miembros", "revocar",
        ],
        texto:
            "Hogar › «Administración» tiene seis secciones: «Configuración» (nombre y zona horaria), " +
            "«Administradores» (Hacer admin, Quitar admin, Transferir, Salir), «Miembros» (alta y edición de " +
            "personas), «Invitaciones» (Crear invitación, Revocar), «Accesos» (qué puede hacer cada persona) y " +
            "«Auditoría» (cambios recientes, con «Cargar más»).",
    },
    {
        id: "admin-miembro",
        titulo: "Qué ve un administrador y qué un miembro",
        palabras: ["admin", "miembro", "rol", "roles", "permisos", "quien puede", "no puedo", "no me deja", "solo administradores", "restriccion"],
        texto:
            "Un administrador puede editar la configuración, gestionar administradores y miembros, crear invitaciones, " +
            "editar los accesos y ver la auditoría. Un miembro ve la configuración, los administradores y los miembros " +
            "en solo lectura, y solo ve «Invitaciones» si tiene permiso de invitar; no ve «Accesos» ni «Auditoría». " +
            "El servidor decide: si no tienes permiso, la app te lo dice.",
    },
    {
        id: "personas",
        titulo: "Personas del hogar",
        palabras: ["personas", "familia", "ver personas", "niños", "mascotas", "adultos", "miembros sin cuenta"],
        texto:
            "Ajustes › «Personas» lista las personas con las que asignas tareas, eventos y rutinas. Las compartidas de " +
            "otro hogar aparecen «Compartida (solo lectura)». Los miembros del hogar (con tipo y estado) se gestionan " +
            "en Hogar › Administración › Miembros.",
    },
    {
        id: "persona-nueva",
        titulo: "Crear, editar o borrar una persona",
        palabras: ["nueva persona", "crear persona", "anadir persona", "agregar persona", "editar persona", "borrar persona", "eliminar persona", "anadir hijo", "anadir mascota"],
        texto:
            "Ajustes › Personas › «+» (arriba) › Nueva persona: Nombre (1 a 50 caracteres) y Color, y «Crear persona». " +
            "Para editarla, usa el botón de editar de su fila: «Guardar» o «Eliminar persona» (pide confirmar). La lista de personas sirve para " +
            "asignar tareas, eventos y rutinas.",
    },
    {
        id: "ajustes",
        titulo: "Ajustes y cuenta",
        palabras: ["ajustes", "configuracion", "cuenta", "perfil", "cambiar nombre", "cambiar email", "contrasena", "password", "modo oscuro", "cerrar sesion", "salir"],
        texto:
            "Ajustes se abre con el engranaje de Inicio. Tiene Cuenta (Nombre, Email y «Nueva contraseña», con " +
            "«Guardar cambios»), Personas, Inicio (orden y bloques), Avisos, widgets y pantalla de bloqueo, " +
            "«Enviar feedback», «Unirse a un hogar con un código», «Modo oscuro» y «Cerrar sesión».",
    },
    {
        id: "kito",
        titulo: "Kito, el asistente",
        palabras: ["kito", "asistente", "chat", "ayudante", "limite", "limite diario", "cupo", "voz", "dictar", "hablar", "que puede hacer kito", "borrar conversacion"],
        texto:
            "Kito es el ayudante de casa: el botón flotante en cualquier pestaña abre el chat. Le puedes escribir o " +
            "dictar. Por ahora responde preguntas (eventos, rutinas, tareas, listas, calendarios y personas) y explica " +
            "cómo se hace algo en la app; todavía no crea ni borra cosas. Tiene un límite de mensajes al día: al " +
            "agotarlo, vuelve al día siguiente. En «Más opciones» puedes borrar la conversación o elegir cuándo habla con voz.",
    },
    {
        id: "enviar-feedback",
        titulo: "Enviar feedback",
        palabras: ["feedback", "sugerencia", "sugerir", "error", "bug", "problema", "mejora", "reportar", "queja", "opinion", "falta una funcion", "contactar"],
        texto:
            "Ajustes › «Enviar feedback». Elige Sección, Pantalla y Acción de lo que quieras comentar, el Tipo (Bug o " +
            "Mejora), cuéntanos «Qué pasó o qué mejorarías» y pulsa «Enviar feedback». Necesitas conexión.",
    },
    {
        id: "bienvenida",
        titulo: "Pantalla de bienvenida",
        palabras: ["bienvenida", "primera vez", "empezar", "entrar", "abrir la app", "sin sesion", "pantalla inicial"],
        texto:
            "Sin sesión, la app muestra «Homita» con el botón «Iniciar sesión» y, si el registro está activo, " +
            "«Registrarse».",
    },
    {
        id: "login",
        titulo: "Iniciar sesión",
        palabras: ["login", "iniciar sesion", "entrar", "acceder", "identificarme", "no puedo entrar", "mi cuenta"],
        texto:
            "Bienvenida › «Iniciar sesión»: escribe Email y Contraseña y pulsa «Iniciar sesión».",
    },
    {
        id: "registro",
        titulo: "Crear una cuenta",
        palabras: ["registro", "registrarse", "crear cuenta", "nueva cuenta", "darme de alta", "apuntarme", "sign up"],
        texto:
            "Bienvenida › «Registrarse»: escribe Nombre, Email, Contraseña (mínimo 8) y, si te invitaron a un hogar, " +
            "el «Código (opcional)» (usa el email de la invitación). Pulsa «Crear cuenta». Sin código se crea una cuenta " +
            "nueva. Si ya tienes cuenta, inicia sesión y acepta la invitación en Ajustes.",
    },
    {
        id: "sin-hogar",
        titulo: "Si no tengo ningún hogar",
        palabras: ["sin hogar", "no tengo hogar", "crear hogar", "primer hogar", "no tienes ningun hogar", "nuevo hogar"],
        texto:
            "Si la cuenta no tiene hogar, las pestañas muestran «No tienes ningún hogar»: escribe el «Nombre " +
            "del hogar» y pulsa «Crear hogar». Si te invitaron, aparece «Aceptar invitación»; «Ahora no» la deja en espera.",
    },
];
