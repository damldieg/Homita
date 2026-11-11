import Foundation

/// Fila de la lista de miembros de Hogar: una cuenta con acceso o un miembro sin cuenta.
public struct HogarMemberRow: Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let initial: String
    /// Tipo localizado (adulto, niño…); nil si la cuenta no tiene tipo asignado.
    public let kindLabel: String?
    /// Rol localizado de la cuenta; nil en miembros sin cuenta.
    public let roleLabel: String?
    /// Permisos como `description` del catálogo; un código fuera del catálogo se muestra tal cual.
    public let permissions: [String]
    public let isMe: Bool
    /// `true` si es una cuenta (con acceso a la app); `false` si es un miembro sin cuenta.
    public let hasAccount: Bool

    /// Cuántos permisos se muestran en la fila antes de «Ver más».
    public static let permissionPreviewLimit = 3
    /// Primeros permisos, en el orden del backend (sin reordenar).
    public var permissionsPreview: [String] { Array(permissions.prefix(Self.permissionPreviewLimit)) }
    /// `true` si hay más permisos que los de la vista previa.
    public var hasMorePermissions: Bool { permissions.count > Self.permissionPreviewLimit }
}

/// Composición pura de la lista de miembros de Hogar con dos fuentes: `GET /home/permission`
/// (cuentas, con rol, tipo y permisos) y `GET /home/member` (miembros, incluidos los sin cuenta).
/// No hay id común entre ambas: los `HomeMember` vinculados se omiten porque ya salen como cuenta.
public enum HogarMemberRows {
    public static func compose(members: [HomeMember], permissions: PermissionsResponse,
                               callerAppUserId: Int?) -> [HogarMemberRow] {
        let descriptions = Dictionary(permissions.catalog.map { ($0.code, $0.description) },
                                      uniquingKeysWith: { first, _ in first })
        let accounts = permissions.memberships.map { item in
            HogarMemberRow(
                id: "account-\(item.membershipId)",
                name: item.name,
                initial: initial(of: item.name),
                kindLabel: item.kind.map(MemberRules.kindLabel),
                roleLabel: HomeSwitcher.roleLabel(item.role),
                permissions: item.permissions.map { descriptions[$0] ?? $0 },
                isMe: callerAppUserId != nil && item.appUserId == callerAppUserId,
                hasAccount: true
            )
        }
        let withoutAccount = members
            .filter { !$0.linked && $0.status == MemberStatus.active.rawValue }
            .map { member in
                HogarMemberRow(
                    id: "member-\(member.id)",
                    name: member.name,
                    initial: initial(of: member.name),
                    kindLabel: MemberRules.kindLabel(member.kind),
                    roleLabel: nil,
                    permissions: [],
                    isMe: false,
                    hasAccount: false
                )
            }
        return accounts + withoutAccount
    }

    static func initial(of name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).first.map { String($0).uppercased() } ?? "?"
    }
}
