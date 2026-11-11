import Foundation

/// Hogares del usuario: listar, crear y fijar el predeterminado. Ninguna de estas tres rutas
/// lleva `X-Home-Id` (la regla vive en `RequestBuilder`).
public struct HomeRepository {
    public let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    /// `GET home` → hogares activos del usuario, ordenados por `home_id`.
    public func list() async throws -> [HomeItem] {
        try await client.send(APIRequest(method: .get, path: "home"), as: [HomeItem].self)
    }

    /// `POST home/create` body `{name}` → 201 `HOME_DETAIL`.
    public func create(name: String) async throws -> HomeDetail {
        try await client.send(
            APIRequest(method: .post, path: "home/create", body: try client.encode(CreateHomeBody(name: name))),
            as: HomeDetail.self
        )
    }

    /// `PATCH home/default` body `{home_id}` → `{default_home_id}`. Sin uso en UI hasta 1.12.
    public func setDefault(homeId: Int) async throws -> DefaultHomeResponse {
        try await client.send(
            APIRequest(method: .patch, path: "home/default", body: try client.encode(SetDefaultHomeBody(homeId: homeId))),
            as: DefaultHomeResponse.self
        )
    }

    /// `POST home/invitation/accept` body `{code}` → `INVITATION_ACCEPTED` (1.15). Sin `X-Home-Id`
    /// (D-015): quien acepta aún no es miembro y el hogar lo fija el código.
    public func acceptInvitation(code: String) async throws -> InvitationAccepted {
        try await client.send(
            APIRequest(method: .post, path: "home/invitation/accept",
                       body: try client.encode(AcceptInvitationBody(code: code))),
            as: InvitationAccepted.self
        )
    }

    // MARK: - Administración del hogar (1.12). Todas llevan `X-Home-Id` (ver `RequestBuilder`).

    /// `GET home/detail?id=` → `HOME_DETAIL`.
    public func detail(id: Int) async throws -> HomeDetailFull {
        try await client.send(
            APIRequest(method: .get, path: "home/detail", query: [URLQueryItem(name: "id", value: String(id))]),
            as: HomeDetailFull.self
        )
    }

    /// `PATCH home/update` body `{id,name,timezone?}` → `HOME_DETAIL`. `timezone` nil se omite.
    public func update(id: Int, name: String, timezone: String?) async throws -> HomeDetailFull {
        try await client.send(
            APIRequest(method: .patch, path: "home/update",
                       body: try client.encode(UpdateHomeBody(id: id, name: name, timezone: timezone))),
            as: HomeDetailFull.self
        )
    }

    /// `GET home/membership?id=` → `[MEMBERSHIP_ITEM]`.
    public func memberships(homeId: Int) async throws -> [MembershipItem] {
        try await client.send(
            APIRequest(method: .get, path: "home/membership", query: [URLQueryItem(name: "id", value: String(homeId))]),
            as: [MembershipItem].self
        )
    }

    /// `PATCH home/membership/role` body `{home_id,membership_id,role}` → `MEMBERSHIP_STATE`.
    public func changeRole(homeId: Int, membershipId: Int, role: String) async throws -> MembershipState {
        try await client.send(
            APIRequest(method: .patch, path: "home/membership/role",
                       body: try client.encode(ChangeRoleBody(homeId: homeId, membershipId: membershipId, role: role))),
            as: MembershipState.self
        )
    }

    /// `POST home/membership/transfer` body `{home_id,to_membership_id}` → `TRANSFER_STATE` (200).
    public func transfer(homeId: Int, toMembershipId: Int) async throws -> TransferState {
        try await client.send(
            APIRequest(method: .post, path: "home/membership/transfer",
                       body: try client.encode(TransferBody(homeId: homeId, toMembershipId: toMembershipId))),
            as: TransferState.self
        )
    }

    /// `DELETE home/membership` body `{home_id,membership_id}` → `{success:true}`.
    public func remove(homeId: Int, membershipId: Int) async throws {
        _ = try await client.send(
            APIRequest(method: .delete, path: "home/membership",
                       body: try client.encode(RemoveMembershipBody(homeId: homeId, membershipId: membershipId))),
            as: OkResponse.self
        )
    }

    /// `GET home/member?home_id=` → `[HOME_MEMBER]` (1.13).
    public func members(homeId: Int) async throws -> [HomeMember] {
        try await client.send(
            APIRequest(method: .get, path: "home/member", query: [URLQueryItem(name: "home_id", value: String(homeId))]),
            as: [HomeMember].self
        )
    }

    /// `POST home/member/create` body `{home_id,kind,name,color}` → 201 `HOME_MEMBER`.
    public func createMember(homeId: Int, kind: MemberKind, name: String, color: String) async throws -> HomeMember {
        try await client.send(
            APIRequest(method: .post, path: "home/member/create",
                       body: try client.encode(CreateMemberBody(homeId: homeId, kind: kind, name: name, color: color))),
            as: HomeMember.self
        )
    }

    /// `PATCH home/member/update` body `{id,kind?,status?,name?,color?}` (sin `home_id`) → `HOME_MEMBER`.
    public func updateMember(_ body: UpdateMemberBody) async throws -> HomeMember {
        try await client.send(
            APIRequest(method: .patch, path: "home/member/update", body: try client.encode(body)),
            as: HomeMember.self
        )
    }

    /// `GET home/permission?home_id=` → `PERMISSION_GET`.
    public func permissions(homeId: Int) async throws -> PermissionsResponse {
        try await client.send(
            APIRequest(method: .get, path: "home/permission", query: [URLQueryItem(name: "home_id", value: String(homeId))]),
            as: PermissionsResponse.self
        )
    }

    /// `PATCH home/permission` body `{home_id,membership_id,permissions[]}` → `PERMISSION_STATE`.
    public func setPermissions(homeId: Int, membershipId: Int, permissions: [String]) async throws -> PermissionState {
        try await client.send(
            APIRequest(method: .patch, path: "home/permission",
                       body: try client.encode(SetPermissionsBody(homeId: homeId, membershipId: membershipId, permissions: permissions))),
            as: PermissionState.self
        )
    }

    /// `GET home/audit?home_id=&limit=&before_id=` → `[AUDIT_ITEM]`; `limit` y `before_id` solo si no son nil.
    public func audit(homeId: Int, limit: Int? = nil, beforeId: Int? = nil) async throws -> [AuditItem] {
        var query = [URLQueryItem(name: "home_id", value: String(homeId))]
        if let limit { query.append(URLQueryItem(name: "limit", value: String(limit))) }
        if let beforeId { query.append(URLQueryItem(name: "before_id", value: String(beforeId))) }
        return try await client.send(APIRequest(method: .get, path: "home/audit", query: query), as: [AuditItem].self)
    }

    // MARK: - Invitaciones (1.15b). Todas salvo accept llevan `X-Home-Id` (ver `RequestBuilder`).

    /// `GET home/invitation?home_id=` → `[INVITATION_ITEM]` (pendientes no caducadas).
    public func invitations(homeId: Int) async throws -> [InvitationItem] {
        try await client.send(
            APIRequest(method: .get, path: "home/invitation", query: [URLQueryItem(name: "home_id", value: String(homeId))]),
            as: [InvitationItem].self
        )
    }

    /// `POST home/invitation/create` → 201 `INVITATION_CREATED` (el `code` solo viaja aquí).
    public func createInvitation(_ body: CreateInvitationBody) async throws -> InvitationCreated {
        try await client.send(
            APIRequest(method: .post, path: "home/invitation/create", body: try client.encode(body)),
            as: InvitationCreated.self
        )
    }

    /// `POST home/invitation/revoke` body `{home_id,id}` → `INVITATION_ITEM` con `status: "revoked"`.
    public func revokeInvitation(homeId: Int, id: Int) async throws -> InvitationItem {
        try await client.send(
            APIRequest(method: .post, path: "home/invitation/revoke",
                       body: try client.encode(RevokeInvitationBody(homeId: homeId, id: id))),
            as: InvitationItem.self
        )
    }
}
