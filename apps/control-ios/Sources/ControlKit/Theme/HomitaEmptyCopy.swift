import Foundation

/// Contenido de un estado vacío de pantalla (`HomitaEmptyState`, E0-04): ilustración, título,
/// texto y como mucho una acción primaria. Separado de la vista para poder probar los textos
/// reales (`docs/design/ios/code-facts.md`) y la regla de la acción sin snapshot.
struct HomitaEmptyContent: Equatable {
    let illustration: HomitaIllustrationKind
    let title: String
    let message: String
    /// Título de la acción primaria; `nil` = sin botón.
    let actionTitle: String?

    /// Se muestra el botón solo si hay título y acción: nunca un botón sin acción ni más de uno.
    static func showsAction(actionTitle: String?, hasAction: Bool) -> Bool {
        actionTitle != nil && hasAction
    }

    /// TASKS-01: sin filtro invita a crear la primera; con una lista filtrada, la lista está vacía.
    static func tasks(filtered: Bool) -> HomitaEmptyContent {
        HomitaEmptyContent(
            illustration: .tasks,
            title: "Sin tareas",
            message: filtered
                ? "Esta lista no tiene tareas todavía."
                : "Crea tu primera tarea y ponle una lista para tenerla a mano.",
            actionTitle: "Nueva tarea"
        )
    }

    /// TASKS-02.
    static let taskLists = HomitaEmptyContent(
        illustration: .lists,
        title: "Sin listas",
        message: "Las listas agrupan tus tareas: compra, casa, trabajo…",
        actionTitle: "Nueva lista"
    )

    /// CAL-02.
    static let routines = HomitaEmptyContent(
        illustration: .routines,
        title: "Sin rutinas",
        message: "Las rutinas repiten eventos cada día, semana o mes sin que las vuelvas a escribir.",
        actionTitle: "Nueva rutina"
    )

    /// CAL-03.
    static let calendars = HomitaEmptyContent(
        illustration: .calendars,
        title: "Sin calendarios",
        message: "Los calendarios agrupan eventos y rutinas por color, como Trabajo o Familia.",
        actionTitle: "Nuevo calendario"
    )
}

/// Vacíos de una línea dentro de una tarjeta (`HomitaEmptyNote`): los textos reales del código.
enum HomitaEmptyNoteText {
    /// Inicio · Hoy · Eventos.
    static let todayEvents = "Sin eventos hoy"
    /// Inicio · Tareas pendientes.
    static let pendingTasks = "Sin tareas pendientes"
    /// Inicio · Rutinas de hoy.
    static let todayRoutines = "Sin rutinas hoy"
    /// TASKS-03 Detalle de lista.
    static let listTasks = "Sin tareas"
    /// HOGAR-01 Miembros.
    static let members = "Sin miembros"
    /// AJ-03 Personas.
    static let persons = "Sin personas"
}
