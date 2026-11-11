import Foundation

/// Reglas puras de la creación de invitaciones (1.15b). El cliente solo oculta; el servidor decide.
/// D-017: solo un admin crea invitaciones `adult`.
public enum InvitationRules {
    /// Tipos invitables: nunca `pet`; `adult` solo para admin.
    public static func allowedKinds(callerRole: String) -> [MemberKind] {
        let admin = HomeAdminAccess.isAdmin(role: callerRole)
        return MemberKind.allCases.filter { $0 != .pet && (admin || $0 != .adult) }
    }

    /// Miembros a los que se puede vincular: activos, sin cuenta, no mascota y, salvo admin, no adultos.
    public static func selectableMembers(_ members: [HomeMember], callerRole: String) -> [HomeMember] {
        let allowed = Set(allowedKinds(callerRole: callerRole).map(\.rawValue))
        return members.filter { !$0.linked && $0.status == MemberStatus.active.rawValue && allowed.contains($0.kind) }
    }

    /// Body de create. Con `member` envía el `kind` del miembro; `nil` si no hay ni tipo ni miembro,
    /// si el tipo no está permitido o si no coincide con el del miembro.
    public static func makeBody(homeId: Int, kind: MemberKind?, member: HomeMember?,
                                callerRole: String) -> CreateInvitationBody? {
        let allowed = allowedKinds(callerRole: callerRole)
        if let member {
            guard let memberKind = MemberKind(rawValue: member.kind), allowed.contains(memberKind) else { return nil }
            if let kind, kind != memberKind { return nil }
            return CreateInvitationBody(homeId: homeId, kind: memberKind.rawValue, memberId: member.id)
        }
        guard let kind, allowed.contains(kind) else { return nil }
        return CreateInvitationBody(homeId: homeId, kind: kind.rawValue, memberId: nil)
    }

    /// Caducada si `expires_at` se parsea y ya pasó. Un formato desconocido no se considera caducada (A2).
    public static func isExpired(_ item: InvitationItem, now: Date = Date()) -> Bool {
        guard let date = PHPDateTime.parse(item.expiresAt) else { return false }
        return date <= now
    }

    /// Pendientes no caducadas.
    public static func visible(_ items: [InvitationItem], now: Date = Date()) -> [InvitationItem] {
        items.filter { $0.status == "pending" && !isExpired($0, now: now) }
    }
}

/// Acciones sobre una invitación listada.
public enum InvitationAction: Equatable, Hashable, Sendable {
    case revoke

    public var requiresConfirmation: Bool { true }
}
