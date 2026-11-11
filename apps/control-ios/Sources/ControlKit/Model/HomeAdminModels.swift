import Foundation

/// `HOME_DETAIL` completo (`GET home/detail`, `PATCH home/update`). Tipo separado de `HomeDetail`
/// (que solo usa `create`). Las fechas llegan como texto del servidor y se muestran tal cual.
public struct HomeDetailFull: Codable, Equatable, Sendable {
    public let id: Int
    public let name: String
    public let timezone: String
    public let isPersonal: Bool
    public let createdAt: String
    public let updatedAt: String

    public init(id: Int, name: String, timezone: String, isPersonal: Bool, createdAt: String, updatedAt: String) {
        self.id = id
        self.name = name
        self.timezone = timezone
        self.isPersonal = isPersonal
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, name, timezone
        case isPersonal = "is_personal"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// Body de `PATCH home/update`. `timezone` nil se omite del JSON (no cambia).
public struct UpdateHomeBody: Codable, Equatable, Sendable {
    public let id: Int
    public let name: String
    public let timezone: String?

    public init(id: Int, name: String, timezone: String? = nil) {
        self.id = id
        self.name = name
        self.timezone = timezone
    }
}

/// `MEMBERSHIP_ITEM` (`GET home/membership`).
public struct MembershipItem: Codable, Equatable, Sendable {
    public let membershipId: Int
    public let appUserId: Int
    public let name: String
    public let email: String
    public let role: String
    public let permissions: [String]

    public init(membershipId: Int, appUserId: Int, name: String, email: String, role: String, permissions: [String] = []) {
        self.membershipId = membershipId
        self.appUserId = appUserId
        self.name = name
        self.email = email
        self.role = role
        self.permissions = permissions
    }

    enum CodingKeys: String, CodingKey {
        case membershipId = "membership_id"
        case appUserId = "app_user_id"
        case name, email, role, permissions
    }
}

/// `MEMBERSHIP_STATE` (`PATCH home/membership/role`).
public struct MembershipState: Codable, Equatable, Sendable {
    public let membershipId: Int
    public let homeId: Int
    public let appUserId: Int
    public let role: String

    enum CodingKeys: String, CodingKey {
        case membershipId = "membership_id"
        case homeId = "home_id"
        case appUserId = "app_user_id"
        case role
    }
}

/// `TRANSFER_STATE` (`POST home/membership/transfer`).
public struct TransferState: Codable, Equatable, Sendable {
    public let fromMembershipId: Int
    public let toMembershipId: Int

    enum CodingKeys: String, CodingKey {
        case fromMembershipId = "from_membership_id"
        case toMembershipId = "to_membership_id"
    }
}

public struct ChangeRoleBody: Codable, Equatable, Sendable {
    public let homeId: Int
    public let membershipId: Int
    public let role: String

    public init(homeId: Int, membershipId: Int, role: String) {
        self.homeId = homeId
        self.membershipId = membershipId
        self.role = role
    }

    enum CodingKeys: String, CodingKey {
        case homeId = "home_id"
        case membershipId = "membership_id"
        case role
    }
}

public struct TransferBody: Codable, Equatable, Sendable {
    public let homeId: Int
    public let toMembershipId: Int

    public init(homeId: Int, toMembershipId: Int) {
        self.homeId = homeId
        self.toMembershipId = toMembershipId
    }

    enum CodingKeys: String, CodingKey {
        case homeId = "home_id"
        case toMembershipId = "to_membership_id"
    }
}

public struct RemoveMembershipBody: Codable, Equatable, Sendable {
    public let homeId: Int
    public let membershipId: Int

    public init(homeId: Int, membershipId: Int) {
        self.homeId = homeId
        self.membershipId = membershipId
    }

    enum CodingKeys: String, CodingKey {
        case homeId = "home_id"
        case membershipId = "membership_id"
    }
}

public struct SetPermissionsBody: Codable, Equatable, Sendable {
    public let homeId: Int
    public let membershipId: Int
    public let permissions: [String]

    public init(homeId: Int, membershipId: Int, permissions: [String]) {
        self.homeId = homeId
        self.membershipId = membershipId
        self.permissions = permissions
    }

    enum CodingKeys: String, CodingKey {
        case homeId = "home_id"
        case membershipId = "membership_id"
        case permissions
    }
}

/// Tipo de miembro del hogar (`kind`). `pet` no puede estar vinculado a una cuenta.
public enum MemberKind: String, CaseIterable, Codable, Sendable {
    case adult, child, relative, guest, pet
}

/// Estado de un miembro (`status`); desactivar es el borrado lógico.
public enum MemberStatus: String, CaseIterable, Codable, Sendable {
    case active, inactive
}

/// `HOME_MEMBER` (`GET home/member`, `POST home/member/create`, `PATCH home/member/update`).
/// `kind` y `status` se guardan como texto: un valor nuevo del servidor no rompe el listado
/// (los enums `MemberKind`/`MemberStatus` se usan en la entrada y en la UI).
public struct HomeMember: Codable, Equatable, Sendable {
    public let id: Int
    public let homeId: Int
    public let kind: String
    public let name: String
    public let color: String?
    public let status: String
    public let linked: Bool
    public let createdAt: String?
    public let updatedAt: String?

    public init(id: Int, homeId: Int, kind: String, name: String, color: String? = nil,
                status: String = "active", linked: Bool = false,
                createdAt: String? = nil, updatedAt: String? = nil) {
        self.id = id
        self.homeId = homeId
        self.kind = kind
        self.name = name
        self.color = color
        self.status = status
        self.linked = linked
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case homeId = "home_id"
        case kind, name, color, status, linked
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// Body de `POST home/member/create`.
public struct CreateMemberBody: Codable, Equatable, Sendable {
    public let homeId: Int
    public let kind: String
    public let name: String
    public let color: String

    public init(homeId: Int, kind: MemberKind, name: String, color: String) {
        self.homeId = homeId
        self.kind = kind.rawValue
        self.name = name
        self.color = color
    }

    enum CodingKeys: String, CodingKey {
        case homeId = "home_id"
        case kind, name, color
    }
}

/// Body de `PATCH home/member/update`: sin `home_id` (el hogar viaja en `X-Home-Id`); los campos
/// nil se omiten del JSON y el servidor los deja como están.
public struct UpdateMemberBody: Codable, Equatable, Sendable {
    public let id: Int
    public let kind: String?
    public let status: String?
    public let name: String?
    public let color: String?

    public init(id: Int, kind: MemberKind? = nil, status: MemberStatus? = nil, name: String? = nil, color: String? = nil) {
        self.id = id
        self.kind = kind?.rawValue
        self.status = status?.rawValue
        self.name = name
        self.color = color
    }

    /// Sin ningún campo a cambiar.
    public var isEmpty: Bool { kind == nil && status == nil && name == nil && color == nil }
}

public struct PermissionCatalogEntry: Codable, Equatable, Sendable {
    public let code: String
    public let domain: String
    public let description: String

    public init(code: String, domain: String, description: String) {
        self.code = code
        self.domain = domain
        self.description = description
    }
}

public struct PermissionDefaults: Codable, Equatable, Sendable {
    public let kind: String
    public let permissions: [String]
}

/// `PERMISSION_ITEM`: `kind` puede faltar; `editable` = caller admin y fila `member`.
public struct PermissionItem: Codable, Equatable, Sendable {
    public let membershipId: Int
    public let appUserId: Int
    public let name: String
    public let email: String
    public let role: String
    public let kind: String?
    public let editable: Bool
    public let permissions: [String]

    public init(membershipId: Int, appUserId: Int, name: String, email: String, role: String,
                kind: String? = nil, editable: Bool, permissions: [String]) {
        self.membershipId = membershipId
        self.appUserId = appUserId
        self.name = name
        self.email = email
        self.role = role
        self.kind = kind
        self.editable = editable
        self.permissions = permissions
    }

    enum CodingKeys: String, CodingKey {
        case membershipId = "membership_id"
        case appUserId = "app_user_id"
        case name, email, role, kind, editable, permissions
    }
}

/// `PERMISSION_GET`.
public struct PermissionsResponse: Codable, Equatable, Sendable {
    public let catalog: [PermissionCatalogEntry]
    public let defaults: [PermissionDefaults]
    public let memberships: [PermissionItem]
}

/// `PERMISSION_STATE` (`PATCH home/permission`).
public struct PermissionState: Codable, Equatable, Sendable {
    public let membershipId: Int
    public let homeId: Int
    public let permissions: [String]
    public let granted: [String]
    public let revoked: [String]

    enum CodingKeys: String, CodingKey {
        case membershipId = "membership_id"
        case homeId = "home_id"
        case permissions, granted, revoked
    }
}

/// `payload` de auditoría: objeto sin esquema por acción. Decodificación lenient: escalares a
/// texto, null omitido, anidados a un texto compacto; nunca falla por una acción nueva. Solo
/// para mostrar (`lines`).
public struct AuditPayload: Codable, Equatable, Sendable {
    public let values: [String: String]

    public init(values: [String: String] = [:]) {
        self.values = values
    }

    public init(from decoder: Decoder) throws {
        guard let container = try? decoder.container(keyedBy: AnyKey.self) else {
            values = [:]
            return
        }
        var result: [String: String] = [:]
        for key in container.allKeys {
            if (try? container.decodeNil(forKey: key)) == true { continue }
            if let s = try? container.decode(String.self, forKey: key) {
                result[key.stringValue] = s
            } else if let b = try? container.decode(Bool.self, forKey: key) {
                result[key.stringValue] = b ? "true" : "false"
            } else if let i = try? container.decode(Int.self, forKey: key) {
                result[key.stringValue] = String(i)
            } else if let d = try? container.decode(Double.self, forKey: key) {
                result[key.stringValue] = String(d)
            } else if (try? container.nestedUnkeyedContainer(forKey: key)) != nil {
                result[key.stringValue] = "[…]"
            } else {
                result[key.stringValue] = "{…}"
            }
        }
        values = result
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(values)
    }

    /// Líneas `clave: valor` ordenadas por clave.
    public var lines: [String] {
        values.keys.sorted().map { "\($0): \(values[$0] ?? "")" }
    }

    private struct AnyKey: CodingKey {
        let stringValue: String
        let intValue: Int? = nil
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
}

/// `AUDIT_ITEM` (`GET home/audit`).
public struct AuditItem: Codable, Equatable, Sendable {
    public let id: Int
    public let action: String
    public let targetType: String
    public let targetId: Int?
    public let actorAppUserId: Int?
    public let actorName: String?
    public let payload: AuditPayload
    public let createdAt: String

    public init(id: Int, action: String, targetType: String, targetId: Int? = nil,
                actorAppUserId: Int? = nil, actorName: String? = nil,
                payload: AuditPayload = AuditPayload(), createdAt: String) {
        self.id = id
        self.action = action
        self.targetType = targetType
        self.targetId = targetId
        self.actorAppUserId = actorAppUserId
        self.actorName = actorName
        self.payload = payload
        self.createdAt = createdAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        action = try c.decode(String.self, forKey: .action)
        targetType = try c.decode(String.self, forKey: .targetType)
        targetId = try c.decodeIfPresent(Int.self, forKey: .targetId)
        actorAppUserId = try c.decodeIfPresent(Int.self, forKey: .actorAppUserId)
        actorName = try c.decodeIfPresent(String.self, forKey: .actorName)
        payload = (try? c.decodeIfPresent(AuditPayload.self, forKey: .payload)) ?? AuditPayload()
        createdAt = try c.decode(String.self, forKey: .createdAt)
    }

    enum CodingKeys: String, CodingKey {
        case id, action, payload
        case targetType = "target_type"
        case targetId = "target_id"
        case actorAppUserId = "actor_app_user_id"
        case actorName = "actor_name"
        case createdAt = "created_at"
    }
}

// MARK: - Invitaciones (1.15b): crear, listar y revocar desde iOS

/// `INVITATION_ITEM` (`GET home/invitation`, `POST home/invitation/revoke`). Nunca lleva el código.
public struct InvitationItem: Codable, Equatable, Sendable {
    public let id: Int
    public let homeId: Int
    public let kind: String
    public let memberId: Int?
    public let memberName: String?
    /// Email al que va ligada la invitación (0023). Nil en invitaciones anteriores.
    public let email: String?
    public let status: String
    public let expiresAt: String
    public let createdBy: Int?
    public let createdAt: String

    public init(id: Int, homeId: Int, kind: String, memberId: Int? = nil, memberName: String? = nil,
                email: String? = nil, status: String = "pending", expiresAt: String, createdBy: Int? = nil,
                createdAt: String) {
        self.id = id
        self.homeId = homeId
        self.kind = kind
        self.memberId = memberId
        self.memberName = memberName
        self.email = email
        self.status = status
        self.expiresAt = expiresAt
        self.createdBy = createdBy
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case homeId = "home_id"
        case kind
        case memberId = "member_id"
        case memberName = "member_name"
        case email
        case status
        case expiresAt = "expires_at"
        case createdBy = "created_by"
        case createdAt = "created_at"
    }
}

/// `INVITATION_CREATED` (`POST home/invitation/create`, 201): el item más el `code`, que solo
/// viaja en esta respuesta. `description` y `debugDescription` lo redactan (nunca a logs).
public struct InvitationCreated: Decodable, Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let item: InvitationItem
    public let code: String

    public init(item: InvitationItem, code: String) {
        self.item = item
        self.code = code
    }

    private enum CodeKey: String, CodingKey { case code }

    public init(from decoder: Decoder) throws {
        item = try InvitationItem(from: decoder)
        code = try decoder.container(keyedBy: CodeKey.self).decode(String.self, forKey: .code)
    }

    public var description: String { "InvitationCreated(id: \(item.id), code: <redacted>)" }
    public var debugDescription: String { description }
}

/// Body de `POST home/invitation/create`. `kind` y `member_id` nil se omiten (hace falta al menos uno).
public struct CreateInvitationBody: Codable, Equatable, Sendable {
    public let homeId: Int
    public let kind: String?
    public let memberId: Int?
    /// Email del invitado (0023, obligatorio). Se normaliza a minúsculas sin espacios.
    public let email: String

    public init(homeId: Int, kind: String?, memberId: Int?, email: String) {
        self.homeId = homeId
        self.kind = kind
        self.memberId = memberId
        self.email = email
    }

    enum CodingKeys: String, CodingKey {
        case homeId = "home_id"
        case kind
        case email
        case memberId = "member_id"
    }
}

/// Body de `POST home/invitation/revoke`.
public struct RevokeInvitationBody: Codable, Equatable, Sendable {
    public let homeId: Int
    public let id: Int

    public init(homeId: Int, id: Int) {
        self.homeId = homeId
        self.id = id
    }

    enum CodingKeys: String, CodingKey {
        case homeId = "home_id"
        case id
    }
}
