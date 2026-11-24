import Foundation

/// `/meal/*` (0043, menus-perfil-hogar). Todas llevan `X-Home-Id` (ver `RequestBuilder`).
public struct MealRepository {
    public let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    /// `GET meal/profile` → perfil, franjas, fichas y horario del hogar.
    public func profile() async throws -> MealProfile {
        try await client.send(APIRequest(method: .get, path: "meal/profile"), as: MealProfile.self)
    }

    /// `PATCH meal/profile` (solo con `menu.profile.edit`).
    public func updateHome(_ update: MealHomeUpdate) async throws {
        _ = try await client.send(
            APIRequest(method: .patch, path: "meal/profile", body: try client.encode(update)), as: OkResponse.self)
    }

    /// `PATCH meal/profile/member`; `eats: false` borra la ficha.
    public func updateMember(_ update: MealMemberUpdate) async throws {
        _ = try await client.send(
            APIRequest(method: .patch, path: "meal/profile/member", body: try client.encode(update)),
            as: OkResponse.self)
    }

    /// `PUT meal/schedule` body `{entries}`.
    public func setSchedule(_ entries: [MealScheduleEntry]) async throws {
        _ = try await client.send(
            APIRequest(method: .put, path: "meal/schedule", body: try client.encode(MealScheduleBody(entries: entries))),
            as: OkResponse.self)
    }

    /// `PUT meal/slots` body `{slots}`.
    public func setSlots(_ slots: [MealSlot]) async throws {
        _ = try await client.send(
            APIRequest(method: .put, path: "meal/slots", body: try client.encode(MealSlotsBody(slots: slots))),
            as: OkResponse.self)
    }
}
