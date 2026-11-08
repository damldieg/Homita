import Foundation

/// Tareas: CRUD, completar y reordenar. `GET task` con `task_list_id` como query (nunca body:
/// desviación 9 del runtime). `PATCH task/order` mueve la tarea a `position` (índice 0-based).
public struct TaskRepository {
    public let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    /// `GET task` — el servidor ordena por `(completed_at IS NOT NULL), order`.
    public func index(taskListId: Int? = nil, widget: Bool? = nil, dashboard: Bool? = nil) async throws -> [TaskEntry] {
        let filters = query([
            ("task_list_id", taskListId.map(String.init)),
            ("widget", widget.map { $0 ? "true" : "false" }),
            ("dashboard", dashboard.map { $0 ? "true" : "false" })
        ])
        return try await client.send(APIRequest(method: .get, path: "task", query: filters), as: [TaskEntry].self)
    }

    /// `GET task/detail?id=`.
    public func detail(id: Int) async throws -> TaskEntry {
        try await client.send(
            APIRequest(method: .get, path: "task/detail", query: query([("id", String(id))])),
            as: TaskEntry.self
        )
    }

    /// `POST task/create` body `{task_list_id,title}` → 201.
    public func create(_ request: CreateTaskRequest) async throws -> TaskEntry {
        try await client.send(
            APIRequest(method: .post, path: "task/create", body: try client.encode(request)),
            as: TaskEntry.self
        )
    }

    /// `PATCH task/update` body `{id,title}`.
    public func update(_ request: UpdateTaskRequest) async throws -> TaskEntry {
        try await client.send(
            APIRequest(method: .patch, path: "task/update", body: try client.encode(request)),
            as: TaskEntry.self
        )
    }

    /// `PATCH task/complete` body `{id,completed}` → fija/limpia `completed_at`.
    public func complete(_ request: CompleteTaskRequest) async throws -> TaskEntry {
        try await client.send(
            APIRequest(method: .patch, path: "task/complete", body: try client.encode(request)),
            as: TaskEntry.self
        )
    }

    /// `PATCH task/order` body `{id,position}` → renumera 1..n en el servidor.
    public func order(_ request: OrderTaskRequest) async throws -> TaskEntry {
        try await client.send(
            APIRequest(method: .patch, path: "task/order", body: try client.encode(request)),
            as: TaskEntry.self
        )
    }

    /// `DELETE task/delete` body `{id}` → `{success:true}`.
    public func delete(id: Int) async throws {
        _ = try await client.send(
            APIRequest(method: .delete, path: "task/delete", body: try client.encode(DeleteRequest(id: id))),
            as: OkResponse.self
        )
    }
}
