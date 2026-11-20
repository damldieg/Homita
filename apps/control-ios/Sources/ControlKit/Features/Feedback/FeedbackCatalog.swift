import Foundation

/// Tipo de feedback: radio obligatorio. Los `rawValue` son los de `public.feedback.tipo`.
public enum FeedbackKind: String, CaseIterable, Sendable {
    case bug, mejora

    public var title: String {
        switch self {
        case .bug: "Bug"
        case .mejora: "Mejora"
        }
    }
}

/// Pantalla (o subpantalla) de una sección con las acciones que admite. `name` es el nombre visible
/// y se envía tal cual; si se llega desde varios sitios lleva el camino con « › » desde la raíz de la sección.
public struct FeedbackScreen: Equatable, Hashable, Sendable {
    public let name: String
    public let actions: [String]

    public init(_ name: String, actions: [String]) {
        self.name = name
        self.actions = actions
    }
}

/// Sección de la app (pestaña, «Acceso» o «General / otro»). `name` se guarda tal cual en
/// `public.feedback.seccion`.
public struct FeedbackSection: Equatable, Hashable, Sendable {
    public let name: String
    public let screens: [FeedbackScreen]

    public init(_ name: String, screens: [FeedbackScreen]) {
        self.name = name
        self.screens = screens
    }

    public func screen(named name: String) -> FeedbackScreen? {
        screens.first { $0.name == name }
    }
}

/// Catálogo fijo: sección › pantalla › acción (datos en código del cliente). La Edge (`FEEDBACK_CATALOG` en
/// `_shared/validate.ts`) lo replica; ambos se comparan contra `supabase/functions/api/tests/fixtures/
/// feedback_catalog.json` en sus tests. Ningún nombre puede contener `": "`.
public enum FeedbackCatalog {
    public static let sections: [FeedbackSection] = [
        FeedbackSection("Inicio", screens: [
            FeedbackScreen("Inicio", actions: ["Ver / cargar", "Tirar para actualizar", "Crear › Tarea", "Crear › Evento", "Ir a Hogar"]),
            FeedbackScreen("Inicio › Nueva tarea", actions: ["Título", "Lista", "Personas", "Crear tarea", "Cancelar"]),
            FeedbackScreen("Inicio › Nuevo evento", actions: ["Título", "Fecha y hora", "Fecha de fin", "Calendario", "Aviso", "Personas", "Crear evento", "Cancelar"]),
            FeedbackScreen("Hoy · Eventos", actions: ["Ver / cargar", "Ir a Hoy · Eventos", "Ya pasaron", "Reintentar"]),
            FeedbackScreen("Tareas pendientes", actions: ["Ver / cargar", "Ir a Tareas pendientes", "Marcar hecha", "Lista", "Deslizar entre listas", "Ver más", "Reintentar"]),
            FeedbackScreen("Rutinas de hoy", actions: ["Ver / cargar", "Ver todas", "Completadas", "Reintentar"])
        ]),
        FeedbackSection("Tareas", screens: [
            FeedbackScreen("Tareas", actions: ["Ver / cargar", "Tirar para actualizar", "Nueva tarea", "Filtrar", "Campo Nueva tarea", "Marcar hecha", "Editar tarea", "Deslizar para eliminar", "Editar", "Plegar / desplegar lista", "Eliminar tareas completadas"]),
            FeedbackScreen("Tareas › Nueva tarea", actions: ["Título", "Lista", "Personas", "Crear tarea", "Cancelar"]),
            FeedbackScreen("Tareas › Editar tarea", actions: ["Título", "Personas", "Personas con acceso", "Guardar", "Eliminar tarea", "Cancelar"]),
            FeedbackScreen("Listas", actions: ["Ver / cargar", "Tirar para actualizar", "Abrir lista", "Nueva lista"]),
            FeedbackScreen("Listas › Nueva lista", actions: ["Nombre", "Color", "Orden de las tareas", "Widget", "Dashboard", "Crear lista", "Cancelar"]),
            FeedbackScreen("Detalle de lista", actions: ["Ver / cargar", "Tirar para actualizar", "Campo Nueva tarea", "Marcar hecha", "Editar tarea", "Deslizar para eliminar", "Reordenar", "Editar lista", "Eliminar todas las completadas", "Email a invitar", "Invitar", "Quitar persona", "Dar acceso", "Lectura", "Edición"]),
            FeedbackScreen("Detalle de lista › Editar tarea", actions: ["Título", "Personas", "Personas con acceso", "Guardar", "Eliminar tarea", "Cancelar"]),
            FeedbackScreen("Detalle de lista › Editar lista", actions: ["Nombre", "Color", "Orden de las tareas", "Widget", "Dashboard", "Guardar", "Eliminar lista", "Cancelar"])
        ]),
        FeedbackSection("Calendario", screens: [
            FeedbackScreen("Eventos", actions: ["Ver / cargar", "Día anterior", "Día siguiente", "Deslizar entre días", "Tira de semana", "Hoy", "Elegir fecha", "Nuevo evento", "Abrir evento"]),
            FeedbackScreen("Eventos › Elegir fecha", actions: ["Fecha", "Hoy", "Listo"]),
            FeedbackScreen("Eventos › Nuevo evento", actions: ["Título", "Fecha y hora", "Fecha de fin", "Calendario", "Aviso", "Personas", "Crear evento", "Cancelar"]),
            FeedbackScreen("Eventos › Editar evento", actions: ["Título", "Fecha y hora", "Fecha de fin", "Aviso", "Personas", "Guardar", "Eliminar evento", "Cancelar"]),
            FeedbackScreen("Rutinas", actions: ["Ver / cargar", "Tirar para actualizar", "Nueva rutina", "Abrir rutina", "Deslizar para eliminar"]),
            FeedbackScreen("Rutinas › Nueva rutina", actions: ["Título", "Calendario", "Frecuencia", "Horario", "Activa", "Aviso", "Personas", "Crear rutina", "Cancelar"]),
            FeedbackScreen("Rutinas › Editar rutina", actions: ["Título", "Frecuencia", "Horario", "Activa", "Aviso", "Personas", "Guardar", "Eliminar rutina", "Cancelar"]),
            FeedbackScreen("Calendarios", actions: ["Ver / cargar", "Tirar para actualizar", "Nuevo calendario", "Abrir calendario"]),
            FeedbackScreen("Calendarios › Nuevo calendario", actions: ["Nombre", "Color", "Widget", "Dashboard", "Crear calendario", "Cancelar"]),
            FeedbackScreen("Calendarios › Editar calendario", actions: ["Nombre", "Color", "Widget", "Dashboard", "Guardar", "Email a invitar", "Invitar", "Quitar persona", "Dar acceso", "Lectura", "Edición", "Eliminar calendario", "Cancelar"])
        ]),
        FeedbackSection("Hogar", screens: [
            FeedbackScreen("Hogar", actions: ["Ver / cargar", "Tirar para actualizar", "Hogar activo", "Ver más", "Crear invitación", "Invitaciones pendientes", "Administración", "Reintentar"]),
            FeedbackScreen("Permisos del hogar", actions: ["Cerrar"]),
            FeedbackScreen("Hogar › Nueva invitación", actions: ["Tipo", "Vincular a un miembro (opcional)", "Email del invitado", "Crear", "Cancelar"]),
            FeedbackScreen("Hogar › Invitación creada", actions: ["Copiar código", "Enviar por WhatsApp", "Compartir invitación", "Listo"]),
            FeedbackScreen("Hogar › Invitaciones", actions: ["Ver / cargar", "Tirar para actualizar", "Crear invitación", "Revocar", "Reintentar"]),
            FeedbackScreen("Hogar › Invitaciones › Nueva invitación", actions: ["Tipo", "Vincular a un miembro (opcional)", "Email del invitado", "Crear", "Cancelar"]),
            FeedbackScreen("Hogar › Invitaciones › Invitación creada", actions: ["Copiar código", "Enviar por WhatsApp", "Compartir invitación", "Listo"]),
            FeedbackScreen("Administración", actions: ["Configuración", "Administradores", "Miembros", "Invitaciones", "Accesos", "Auditoría"]),
            FeedbackScreen("Administración › Configuración", actions: ["Ver / cargar", "Nombre", "Zona horaria", "Guardar cambios", "Reintentar"]),
            FeedbackScreen("Administración › Configuración › Zona horaria", actions: ["Buscar zona horaria", "Elegir zona", "Cerrar"]),
            FeedbackScreen("Administración › Administradores", actions: ["Ver / cargar", "Tirar para actualizar", "Quitar admin", "Quitar", "Hacer admin", "Transferir", "Salir", "Reintentar"]),
            FeedbackScreen("Administración › Miembros", actions: ["Ver / cargar", "Tirar para actualizar", "Agregar", "Abrir miembro", "Reintentar"]),
            FeedbackScreen("Administración › Miembros › Nuevo miembro", actions: ["Nombre (1-50)", "Color", "Tipo", "Agregar", "Cancelar"]),
            FeedbackScreen("Administración › Miembros › Editar miembro", actions: ["Nombre (1-50)", "Color", "Tipo", "Estado", "Guardar", "Cambiar tipo", "Cancelar"]),
            FeedbackScreen("Administración › Invitaciones", actions: ["Ver / cargar", "Tirar para actualizar", "Crear invitación", "Revocar", "Reintentar"]),
            FeedbackScreen("Administración › Invitaciones › Nueva invitación", actions: ["Tipo", "Vincular a un miembro (opcional)", "Email del invitado", "Crear", "Cancelar"]),
            FeedbackScreen("Administración › Invitaciones › Invitación creada", actions: ["Copiar código", "Enviar por WhatsApp", "Compartir invitación", "Listo"]),
            FeedbackScreen("Administración › Accesos", actions: ["Ver / cargar", "Tirar para actualizar", "Editar", "Reintentar"]),
            FeedbackScreen("Administración › Accesos › Editor de accesos", actions: ["Interruptor de permiso", "Restablecer a tipo", "Guardar", "Cancelar"]),
            FeedbackScreen("Administración › Auditoría", actions: ["Ver / cargar", "Tirar para actualizar", "Todo", "Acción", "Persona", "Cargar más", "Reintentar"])
        ]),
        FeedbackSection("Ajustes", screens: [
            FeedbackScreen("Ajustes", actions: ["Nombre", "Email", "Nueva contraseña (opcional, mínimo 8)", "Guardar cambios", "Personas", "Avisos, widgets y pantalla de bloqueo", "Unirse a un hogar con un código", "Enviar feedback", "Modo oscuro", "Cerrar sesión"]),
            FeedbackScreen("Personas", actions: ["Ver / cargar", "Tirar para actualizar", "Nueva persona", "Editar persona", "Eliminar persona", "Reintentar"]),
            FeedbackScreen("Personas › Nueva persona", actions: ["Nombre (1-50)", "Color", "Crear persona", "Cancelar"]),
            FeedbackScreen("Personas › Editar persona", actions: ["Nombre (1-50)", "Color", "Guardar", "Eliminar persona", "Cancelar"]),
            FeedbackScreen("Notificaciones", actions: ["Eventos", "Rutinas", "Resumen de tareas pendientes", "Hora del resumen", "Rutinas en tiempo real", "Datos en widgets", "Abrir Ajustes de iOS"]),
            FeedbackScreen("Unirse a un hogar", actions: ["Código de invitación", "Unirse", "Ver el hogar"]),
            FeedbackScreen("Enviar feedback", actions: ["Sección", "Pantalla", "Acción", "Tipo", "Qué pasó o qué mejorarías", "Enviar feedback"])
        ]),
        FeedbackSection("Acceso", screens: [
            FeedbackScreen("Bienvenida", actions: ["Iniciar sesión", "Registrarse"]),
            FeedbackScreen("Iniciar sesión", actions: ["Email", "Contraseña", "Iniciar sesión"]),
            FeedbackScreen("Registrarse", actions: ["Nombre", "Email", "Contraseña (mínimo 8)", "Código (opcional)", "Crear cuenta"]),
            FeedbackScreen("No tienes ningún hogar", actions: ["Nombre del hogar", "Crear hogar", "Aceptar invitación", "Ahora no"]),
            FeedbackScreen("Cargando inicio", actions: ["Ver / cargar"]),
            FeedbackScreen("No se pudo cargar tu hogar", actions: ["Reintentar"])
        ]),
        FeedbackSection("General / otro", screens: [
            FeedbackScreen("Otro", actions: ["General"]),
            FeedbackScreen("Banner sin conexión", actions: ["General"]),
            FeedbackScreen("Animación de arranque", actions: ["General"])
        ])
    ]

    public static func section(named name: String) -> FeedbackSection? {
        sections.first { $0.name == name }
    }
}
