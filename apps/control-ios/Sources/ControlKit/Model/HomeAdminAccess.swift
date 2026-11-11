import Foundation

/// Acciones posibles sobre una fila de administradores.
public enum MembershipRowAction: Equatable, Hashable, Sendable {
    case promote
    case demote
    case transfer
    case remove
    case leave
    case editPermissions
}

/// Gating de cliente de la administración del hogar. Puro y sin red: el cliente solo oculta,
/// el servidor decide (403 `Not Allowed`).
public enum HomeAdminAccess {
    public static func isAdmin(role: String) -> Bool { role == "admin" }
    public static func canEditSettings(role: String) -> Bool { isAdmin(role: role) }
    public static func canViewAudit(role: String) -> Bool { isAdmin(role: role) }
    public static func canManageRoles(role: String) -> Bool { isAdmin(role: role) }
    /// Alta y edición de miembros: solo admin (la lista la ve cualquiera).
    public static func canManageMembers(role: String) -> Bool { isAdmin(role: role) }

    /// Acciones sobre `row`. `callerAppUserId` es el `UserSession.id` (== `app_user_id`, T1).
    /// Hogar personal: sin `.transfer` ni `.remove` (decisión aprobada); renombrar lo decide el servidor.
    /// `adminCount` = admins en la lista de membresías: el último admin no puede degradarse, quitarse
    /// ni salir (el servidor responde 403). nil = desconocido, no se bloquea.
    /// `editable` viene de `PERMISSION_ITEM`; si no se conoce (nil) se asume la regla `member`.
    public static func rowActions(
        callerRole: String,
        row: MembershipItem,
        callerAppUserId: Int?,
        isPersonal: Bool,
        permissionEditable: Bool? = nil,
        adminCount: Int? = nil
    ) -> Set<MembershipRowAction> {
        let isSelf = callerAppUserId != nil && row.appUserId == callerAppUserId
        let isLastAdmin = row.role == "admin" && (adminCount.map { $0 <= 1 } ?? false)
        var actions: Set<MembershipRowAction> = []
        if isSelf && !isPersonal {
            actions.insert(.leave)
        }
        guard isAdmin(role: callerRole) else { return actions }
        if row.role == "admin" {
            actions.insert(.demote)
        } else if row.role == "member" {
            actions.insert(.promote)
            if !isSelf && !isPersonal {
                actions.insert(.transfer)
                actions.insert(.remove)
            }
            if permissionEditable ?? true { actions.insert(.editPermissions) }
        }
        if !isSelf && row.role == "admin" && !isPersonal {
            actions.insert(.remove)
        }
        if isLastAdmin {
            actions.subtract([.demote, .remove, .leave])
        }
        return actions
    }

    /// Si la acción exige confirmación previa (destructivas o que ceden poder).
    public static func requiresConfirmation(action: MembershipRowAction) -> Bool {
        switch action {
        case .remove, .leave, .transfer, .demote: return true
        case .promote, .editPermissions: return false
        }
    }
}

/// Estado final del set de permisos de un miembro (envío completo, idempotente).
public struct PermissionDraft: Equatable, Sendable {
    public let original: Set<String>
    public private(set) var current: Set<String>

    public init(permissions: [String]) {
        original = Set(permissions)
        current = original
    }

    public func isOn(_ code: String) -> Bool { current.contains(code) }

    public mutating func toggle(_ code: String) {
        if current.contains(code) { current.remove(code) } else { current.insert(code) }
    }

    public var isDirty: Bool { current != original }
    public var finalPermissions: [String] { current.sorted() }
}

/// Catálogo agrupado por `domain` (dominios y códigos ordenados).
public struct PermissionGroup: Equatable, Sendable {
    public let domain: String
    public let entries: [PermissionCatalogEntry]
}

public func groupedCatalog(_ catalog: [PermissionCatalogEntry]) -> [PermissionGroup] {
    Dictionary(grouping: catalog, by: \.domain)
        .map { PermissionGroup(domain: $0.key, entries: $0.value.sorted { $0.code < $1.code }) }
        .sorted { $0.domain < $1.domain }
}

/// Paginación de auditoría por `before_id`.
public enum AuditPager {
    public static let pageSize = 50

    public static func nextBeforeId(items: [AuditItem]) -> Int? { items.last?.id }
    public static func hasMore(received: Int, limit: Int) -> Bool { received == limit }

    /// Concatena sin duplicados por `id`, conservando el orden.
    public static func merge(_ existing: [AuditItem], _ page: [AuditItem]) -> [AuditItem] {
        var seen = Set(existing.map(\.id))
        return existing + page.filter { seen.insert($0.id).inserted }
    }
}

/// Qué secciones muestra la pantalla de administración según el rol.
public struct HomeAdminScreenModel: Equatable, Sendable {
    public let showSettings: Bool
    public let showAdministrators: Bool
    public let showPermissions: Bool
    public let showAudit: Bool
    public let canEdit: Bool
    public let showMembers: Bool
    public let canCreateMembers: Bool
    public let canEditMembers: Bool

    public init(role: String) {
        let admin = HomeAdminAccess.isAdmin(role: role)
        showSettings = true
        showAdministrators = true
        showPermissions = admin
        showAudit = HomeAdminAccess.canViewAudit(role: role)
        canEdit = admin
        showMembers = true
        canCreateMembers = HomeAdminAccess.canManageMembers(role: role)
        canEditMembers = canCreateMembers
    }
}

/// Reglas puras de miembros del hogar (selector de tipo, advertencia, cuerpo de edición, textos).
public enum MemberRules {
    /// Tipos seleccionables: un miembro vinculado a una cuenta no puede ser `pet`.
    public static func availableKinds(linked: Bool) -> [MemberKind] {
        linked ? MemberKind.allCases.filter { $0 != .pet } : MemberKind.allCases
    }

    /// Cambiar el tipo de un vinculado restablece sus permisos a los del nuevo tipo.
    public static func needsPermissionResetWarning(member: HomeMember, newKind: MemberKind?) -> Bool {
        guard let newKind else { return false }
        return member.linked && member.kind != newKind.rawValue
    }

    /// Cuerpo de `update` con solo los campos cambiados (nombre recortado). `kind`, `status` y
    /// `color` en nil significan "sin elección": no se envían (un valor original desconocido o un
    /// color nulo nunca se reescriben por defecto). `nil` si no hay cambios o si se pide `pet`
    /// para un vinculado (el servidor respondería 400).
    public static func makeUpdateBody(original: HomeMember, kind: MemberKind?, status: MemberStatus?,
                                      name: String, color: String?) -> UpdateMemberBody? {
        if original.linked && kind == .pet { return nil }
        let trimmed = MemberValidation.trimmedName(name)
        let body = UpdateMemberBody(
            id: original.id,
            kind: kind.flatMap { $0.rawValue == original.kind ? nil : $0 },
            status: status.flatMap { $0.rawValue == original.status ? nil : $0 },
            name: trimmed == original.name ? nil : trimmed,
            color: color.flatMap { $0.uppercased() == (original.color ?? "").uppercased() ? nil : $0 }
        )
        return body.isEmpty ? nil : body
    }

    public static func linkStatusLabel(linked: Bool) -> String { linked ? "Vinculada" : "Sin cuenta" }

    public static func statusLabel(_ status: String) -> String {
        switch MemberStatus(rawValue: status) {
        case .active: return "Activo"
        case .inactive: return "Inactivo"
        case nil: return status
        }
    }

    public static func kindLabel(_ kind: String) -> String {
        switch MemberKind(rawValue: kind) {
        case .adult: return "Adulto"
        case .child: return "Niño"
        case .relative: return "Familiar"
        case .guest: return "Invitado"
        case .pet: return "Mascota"
        case nil: return kind
        }
    }
}
