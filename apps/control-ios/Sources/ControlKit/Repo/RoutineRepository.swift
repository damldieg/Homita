import Foundation

/// Rutinas: CRUD (daily/weekly/monthly), pausa/activa y alarma (`PATCH routine/alarm`, sin aviso
/// en el iPhone). Las sesiones individuales se leen como eventos (`routine=true`) y no se editan.
public struct RoutineRepository {
    public let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    /// `GET routine?timezone=` (efecto: materializa).
    public func index(timezone: String) async throws -> [RoutineEntry] {
        try await client.send(
            APIRequest(method: .get, path: "routine", query: query([("timezone", timezone)])),
            as: [RoutineEntry].self
        )
    }

    /// `GET routine/detail?id=&timezone=`.
    public func detail(id: Int, timezone: String) async throws -> RoutineEntry {
        try await client.send(
            APIRequest(method: .get, path: "routine/detail", query: query([("id", String(id)), ("timezone", timezone)])),
            as: RoutineEntry.self
        )
    }

    /// `POST routine/create` (incluye `alarm`; crea `routine_user` y materializa).
    public func create(_ request: CreateRoutineRequest, timezone: String) async throws -> RoutineEntry {
        try await client.send(
            APIRequest(method: .post, path: "routine/create", query: query([("timezone", timezone)]), body: try client.encode(request)),
            as: RoutineEntry.self
        )
    }

    /// `PATCH routine/update` (sin `alarm`: se cambia aparte).
    public func update(_ request: UpdateRoutineRequest, timezone: String) async throws -> RoutineEntry {
        try await client.send(
            APIRequest(method: .patch, path: "routine/update", query: query([("timezone", timezone)]), body: try client.encode(request)),
            as: RoutineEntry.self
        )
    }

    /// `PATCH routine/alarm` body `{id,alarm}` (null = sin aviso).
    public func setAlarm(_ request: SetRoutineAlarmRequest, timezone: String) async throws -> RoutineEntry {
        try await client.send(
            APIRequest(method: .patch, path: "routine/alarm", query: query([("timezone", timezone)]), body: try client.encode(request)),
            as: RoutineEntry.self
        )
    }

    /// `DELETE routine/delete` body `{id}` → `{success:true}`; borra sesiones futuras.
    public func delete(id: Int, timezone: String) async throws {
        _ = try await client.send(
            APIRequest(method: .delete, path: "routine/delete", query: query([("timezone", timezone)]), body: try client.encode(DeleteRequest(id: id))),
            as: OkResponse.self
        )
    }
}
