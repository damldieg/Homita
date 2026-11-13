import Foundation

/// Resúmenes de una línea del menú Administración (E4-04): «2 administradores», «1 pendiente».
/// Puro, sin UI. `nil` en la entrada = no se pudo cargar (la vista muestra «No se pudo cargar»).
public enum HomeAdminSummary {
    public static let unavailable = "No se pudo cargar"

    public static func administrators(_ count: Int?) -> String? {
        guard let count else { return nil }
        return count == 1 ? "1 administrador" : "\(count) administradores"
    }

    public static func members(_ count: Int?) -> String? {
        guard let count else { return nil }
        switch count {
        case 0: return "Sin miembros"
        case 1: return "1 miembro"
        default: return "\(count) miembros"
        }
    }

    public static func invitations(_ count: Int?) -> String? {
        guard let count else { return nil }
        switch count {
        case 0: return "Sin pendientes"
        case 1: return "1 pendiente"
        default: return "\(count) pendientes"
        }
    }
}

/// Filtros de la auditoría (frame 8 del wireframe): por acción y por persona, sobre lo ya cargado.
public struct AuditFilter: Equatable, Sendable {
    /// Grupos de acción: se deducen del código técnico (`home.invitation.create` → invitaciones).
    public enum Group: String, CaseIterable, Sendable {
        case invitations, permissions, members, home

        public var label: String {
            switch self {
            case .invitations: return "Invitaciones"
            case .permissions: return "Accesos"
            case .members: return "Miembros"
            case .home: return "Hogar"
            }
        }

        public static func of(action: String) -> Group {
            if action.contains("invitation") { return .invitations }
            if action.contains("permission") { return .permissions }
            if action.contains("member") { return .members }
            return .home
        }
    }

    public var group: Group?
    /// Nombre del actor tal cual viene del servidor; `AuditFilter.system` = acciones sin actor.
    public var actor: String?

    public static let system = "Sistema"

    public init(group: Group? = nil, actor: String? = nil) {
        self.group = group
        self.actor = actor
    }

    public var isActive: Bool { group != nil || actor != nil }

    public func matches(_ item: AuditItem) -> Bool {
        if let group, Group.of(action: item.action) != group { return false }
        if let actor, Self.actorName(item) != actor { return false }
        return true
    }

    public func apply(to items: [AuditItem]) -> [AuditItem] {
        isActive ? items.filter(matches) : items
    }

    /// Actores presentes en `items`, ordenados, con «Sistema» al final si hay entradas sin actor.
    public static func actors(in items: [AuditItem]) -> [String] {
        let names = Set(items.map(actorName))
        let named = names.subtracting([system]).sorted()
        return names.contains(system) ? named + [system] : named
    }

    static func actorName(_ item: AuditItem) -> String {
        if let name = item.actorName, !name.isEmpty { return name }
        return system
    }
}
