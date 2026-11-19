import Foundation

/// Acción que el usuario hace (o querría hacer) sobre una sub-área. Va dentro de `subseccion`
/// junto con la sub-área (D2): `"<sub-área>: <acción>"`. Los `rawValue` coinciden con la
/// whitelist de `POST /feedback` (`validateFeedback`).
public enum FeedbackAction: String, CaseIterable, Sendable {
    case ver, crear, editar, eliminar

    public var title: String {
        switch self {
        case .ver: "Ver"
        case .crear: "Crear"
        case .editar: "Editar"
        case .eliminar: "Eliminar"
        }
    }
}

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

/// Sub-área de una sección con las acciones que admite.
public struct FeedbackArea: Equatable, Hashable, Sendable {
    public let name: String
    public let actions: [FeedbackAction]

    public init(_ name: String, actions: [FeedbackAction] = FeedbackAction.allCases) {
        self.name = name
        self.actions = actions
    }
}

/// Sección principal de la app. `name` se guarda tal cual en `public.feedback.seccion`
/// (`procesar-feedback` busca en `backlog` por ese valor).
public struct FeedbackSection: Equatable, Hashable, Sendable {
    public let name: String
    public let areas: [FeedbackArea]

    public init(_ name: String, areas: [FeedbackArea]) {
        self.name = name
        self.areas = areas
    }

    public func area(named name: String) -> FeedbackArea? {
        areas.first { $0.name == name }
    }
}

/// Catálogo fijo de secciones y sub-áreas (datos en código del cliente).
public enum FeedbackCatalog {
    public static let sections: [FeedbackSection] = [
        FeedbackSection("Inicio", areas: [
            FeedbackArea("resumen del día", actions: [.ver]),
            FeedbackArea("eventos de hoy"),
            FeedbackArea("rutinas de hoy")
        ]),
        FeedbackSection("Tareas", areas: [
            FeedbackArea("listas"),
            FeedbackArea("tareas")
        ]),
        FeedbackSection("Calendario", areas: [
            FeedbackArea("eventos"),
            FeedbackArea("rutinas"),
            FeedbackArea("calendarios")
        ]),
        FeedbackSection("Hogar", areas: [
            FeedbackArea("miembros"),
            FeedbackArea("invitaciones"),
            FeedbackArea("administradores"),
            FeedbackArea("permisos")
        ]),
        FeedbackSection("Ajustes", areas: [
            FeedbackArea("perfil"),
            FeedbackArea("notificaciones"),
            FeedbackArea("cuenta")
        ])
    ]

    public static func section(named name: String) -> FeedbackSection? {
        sections.first { $0.name == name }
    }
}
