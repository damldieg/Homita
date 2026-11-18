import Foundation

/// Permiso de una persona sobre un calendario o una lista (0029): el owner edita siempre; el resto
/// es lectura o edición (`can_edit`). Las escrituras de contenido exigen además el permiso del
/// catálogo del hogar (tope adicional): el servidor decide, la app solo lo muestra.
public enum AccessLevel: String, Equatable, CaseIterable, Sendable {
    case owner
    case edit
    case read

    public var title: String {
        switch self {
        case .owner: return "Propietario"
        case .edit: return "Edición"
        case .read: return "Lectura"
        }
    }

    public var canEdit: Bool { self != .read }

    /// Opciones del selector (el owner no se elige: es quien creó el recurso).
    public static let choices: [AccessLevel] = [.read, .edit]
}

/// Fila del panel «Personas con acceso»: un miembro del ACL o una cuenta del hogar sin acceso.
public struct AccessRow: Equatable, Identifiable, Sendable {
    public let userId: Int
    public let name: String
    /// Email (miembros del ACL) o `nil` (cuentas del hogar aún sin acceso: `GET person` no lo trae).
    public let email: String?
    /// `nil` = cuenta del hogar sin acceso todavía (elegir un permiso la agrega).
    public let level: AccessLevel?
    public let isCurrentUser: Bool
    /// El usuario actual puede cambiar el permiso de esta fila (es owner, no es su fila ni otro owner).
    public let isEditable: Bool

    public var id: Int { userId }
    public var hasAccess: Bool { level != nil }
}

/// Arma la lista del selector de permisos a partir de los miembros del ACL (`GET calendar/user` o
/// `GET task-list/user`) y de las personas del hogar (`GET person`). Solo entran cuentas: las
/// personas sin `app_user_id` (niños sin cuenta, mascotas) no pueden iniciar sesión y no aparecen.
public enum AccessRoster {
    /// Nivel del usuario actual en el ACL; `nil` si no está (p. ej. admin del hogar sin ACL propia).
    public static func level(of userId: Int?, in members: [MemberEntry]) -> AccessLevel? {
        guard let userId else { return nil }
        return members.first { $0.user_id == userId }?.accessLevel
    }

    /// Solo el owner del recurso cambia permisos (el servidor lo valida igual: 403).
    public static func callerIsOwner(_ currentUserId: Int?, in members: [MemberEntry]) -> Bool {
        level(of: currentUserId, in: members) == .owner
    }

    /// Filas: primero los miembros del ACL (orden del servidor: owner primero), luego las cuentas
    /// del hogar sin acceso, por nombre. Una cuenta aparece una sola vez.
    public static func rows(members: [MemberEntry], persons: [PersonEntry], currentUserId: Int?) -> [AccessRow] {
        let owner = callerIsOwner(currentUserId, in: members)
        var seen = Set<Int>()
        var result: [AccessRow] = []
        for member in members where seen.insert(member.user_id).inserted {
            let isSelf = member.user_id == currentUserId
            result.append(AccessRow(
                userId: member.user_id, name: member.name, email: member.email,
                level: member.accessLevel, isCurrentUser: isSelf,
                isEditable: owner && !isSelf && member.accessLevel != .owner
            ))
        }
        // Solo el owner ve las cuentas sin acceso: son candidatas a compartir.
        guard owner else { return result }
        let candidates = persons
            .compactMap { person -> (Int, String)? in
                guard let account = person.app_user_id else { return nil }
                return (account, person.name)
            }
            .sorted { $0.1.localizedCaseInsensitiveCompare($1.1) == .orderedAscending }
        for (account, name) in candidates where seen.insert(account).inserted {
            let isSelf = account == currentUserId
            result.append(AccessRow(
                userId: account, name: name, email: nil, level: nil, isCurrentUser: isSelf,
                isEditable: !isSelf
            ))
        }
        return result
    }
}
