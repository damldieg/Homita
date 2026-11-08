import Foundation

/// Eventos: lecturas filtradas por query (epoch de 10 dígitos + `timezone`) y escrituras con body.
/// v1 sin "modo IA": crear exige `title` + `date_at`. Las alarmas se guardan en el servidor vía
/// `PATCH event/alarm`, pero el iPhone no programa avisos (v1 sin notificaciones).
public struct EventRepository {
    public let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    /// `GET event` (filtros en query). Efecto: materializa sesiones de rutina en el servidor.
    public func index(_ filters: EventFilters = EventFilters()) async throws -> [EventEntry] {
        try await client.send(APIRequest(method: .get, path: "event", query: filters.queryItems), as: [EventEntry].self)
    }

    /// `GET event/detail?id=&timezone=`.
    public func detail(id: Int, timezone: String) async throws -> EventEntry {
        try await client.send(
            APIRequest(method: .get, path: "event/detail", query: query([("id", String(id)), ("timezone", timezone)])),
            as: EventEntry.self
        )
    }

    /// `POST event/create` → 200 evento (sin `calendar_color`/`calendar_name`).
    public func create(_ request: CreateEventRequest) async throws -> EventEntry {
        try await client.send(
            APIRequest(method: .post, path: "event/create", body: try client.encode(request)),
            as: EventEntry.self
        )
    }

    /// `PATCH event/update`. Si es sesión de rutina, crea `routine_exception` (título/fecha).
    public func update(_ request: UpdateEventRequest, timezone: String) async throws -> EventEntry {
        try await client.send(
            APIRequest(method: .patch, path: "event/update", query: query([("timezone", timezone)]), body: try client.encode(request)),
            as: EventEntry.self
        )
    }

    /// `PATCH event/alarm` body `{event_id,alarm}` (null = sin aviso).
    public func setAlarm(_ request: SetEventAlarmRequest, timezone: String) async throws -> EventEntry {
        try await client.send(
            APIRequest(method: .patch, path: "event/alarm", query: query([("timezone", timezone)]), body: try client.encode(request)),
            as: EventEntry.self
        )
    }

    /// `DELETE event/delete` body `{id}` → `{success:true}`. Sesión de rutina → cancelada.
    public func delete(id: Int, timezone: String) async throws {
        _ = try await client.send(
            APIRequest(method: .delete, path: "event/delete", query: query([("timezone", timezone)]), body: try client.encode(DeleteRequest(id: id))),
            as: OkResponse.self
        )
    }
}
