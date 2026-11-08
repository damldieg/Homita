import Foundation

/// Calendarios: CRUD + invitaciones por email. Roles: `role='owner'` en `MemberEntry`; las
/// acciones owner-only devuelven 403 `Not Allowed` en la Edge (se muestra aviso, no se reintenta).
public struct CalendarRepository {
    public let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    /// `GET calendar` → orden `name` ASC, con widget/dashboard y `upcoming_event_count`.
    public func index() async throws -> [CalendarEntry] {
        try await client.send(APIRequest(method: .get, path: "calendar"), as: [CalendarEntry].self)
    }

    /// `GET calendar/detail?id=`.
    public func detail(id: Int) async throws -> CalendarEntry {
        try await client.send(
            APIRequest(method: .get, path: "calendar/detail", query: query([("id", String(id))])),
            as: CalendarEntry.self
        )
    }

    /// `POST calendar/create` → 201; el creador queda como owner.
    public func create(_ request: CreateCalendarRequest) async throws -> CalendarEntry {
        try await client.send(
            APIRequest(method: .post, path: "calendar/create", body: try client.encode(request)),
            as: CalendarEntry.self
        )
    }

    /// `PATCH calendar/update`; `name`/`color` distintos → owner-only.
    public func update(_ request: UpdateCalendarRequest) async throws -> CalendarEntry {
        try await client.send(
            APIRequest(method: .patch, path: "calendar/update", body: try client.encode(request)),
            as: CalendarEntry.self
        )
    }

    /// `DELETE calendar/delete` body `{id}` → `{success:true}` (owner-only en la Edge).
    public func delete(id: Int) async throws {
        _ = try await client.send(
            APIRequest(method: .delete, path: "calendar/delete", body: try client.encode(DeleteRequest(id: id))),
            as: OkResponse.self
        )
    }

    /// `GET calendar/user?calendar_id=` → miembros (orden role ASC, name ASC).
    public func users(calendarId: Int) async throws -> [MemberEntry] {
        try await client.send(
            APIRequest(method: .get, path: "calendar/user", query: query([("calendar_id", String(calendarId))])),
            as: [MemberEntry].self
        )
    }

    /// `POST calendar/user` body `{calendar_id,email}` → invitado (viewer si no era miembro).
    public func invite(calendarId: Int, email: String) async throws -> UserResponse {
        try await client.send(
            APIRequest(method: .post, path: "calendar/user", body: try client.encode(CreateCalendarUserRequest(calendar_id: calendarId, email: email))),
            as: UserResponse.self
        )
    }

    /// `DELETE calendar/user` body `{calendar_id,user_id}` → `{status:"ok"}`. Quitarse a uno mismo
    /// → 400 `User cannot remove themselves` (antes que el check de owner).
    public func removeUser(calendarId: Int, userId: Int) async throws {
        _ = try await client.send(
            APIRequest(method: .delete, path: "calendar/user", body: try client.encode(DeleteCalendarUserRequest(calendar_id: calendarId, user_id: userId))),
            as: OkResponse.self
        )
    }
}
