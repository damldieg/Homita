import Foundation

/// Listas de tareas: CRUD, `sort` (`updated_at|title|custom`) e invitaciones por email.
public struct TaskListRepository {
    public let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    /// `GET task-list` → orden `name` ASC, con widget/dashboard y `pending_task_count`.
    public func index() async throws -> [TaskListEntry] {
        try await client.send(APIRequest(method: .get, path: "task-list"), as: [TaskListEntry].self)
    }

    /// `GET task-list/detail?id=`.
    public func detail(id: Int) async throws -> TaskListEntry {
        try await client.send(
            APIRequest(method: .get, path: "task-list/detail", query: query([("id", String(id))])),
            as: TaskListEntry.self
        )
    }

    /// `POST task-list/create` → 201; `sort` por defecto `updated_at` en el servidor.
    public func create(_ request: CreateTaskListRequest) async throws -> TaskListEntry {
        try await client.send(
            APIRequest(method: .post, path: "task-list/create", body: try client.encode(request)),
            as: TaskListEntry.self
        )
    }

    /// `PATCH task-list/update`; `name`/`color`/`sort` distintos → owner-only (403).
    public func update(_ request: UpdateTaskListRequest) async throws -> TaskListEntry {
        try await client.send(
            APIRequest(method: .patch, path: "task-list/update", body: try client.encode(request)),
            as: TaskListEntry.self
        )
    }

    /// `DELETE task-list/delete` body `{id}` → `{success:true}` (owner-only; cascada de tareas).
    public func delete(id: Int) async throws {
        _ = try await client.send(
            APIRequest(method: .delete, path: "task-list/delete", body: try client.encode(DeleteRequest(id: id))),
            as: OkResponse.self
        )
    }

    /// `GET task-list/user?task_list_id=` → todos los miembros.
    public func users(taskListId: Int) async throws -> [MemberEntry] {
        try await client.send(
            APIRequest(method: .get, path: "task-list/user", query: query([("task_list_id", String(taskListId))])),
            as: [MemberEntry].self
        )
    }

    /// `POST task-list/user` body `{task_list_id,email}` → invitado (viewer si no era miembro).
    public func invite(taskListId: Int, email: String) async throws -> UserResponse {
        try await client.send(
            APIRequest(method: .post, path: "task-list/user", body: try client.encode(CreateTaskListUserRequest(task_list_id: taskListId, email: email))),
            as: UserResponse.self
        )
    }

    /// `DELETE task-list/user` body `{task_list_id,user_id}` → `{status:"ok"}`.
    public func removeUser(taskListId: Int, userId: Int) async throws {
        _ = try await client.send(
            APIRequest(method: .delete, path: "task-list/user", body: try client.encode(DeleteTaskListUserRequest(task_list_id: taskListId, user_id: userId))),
            as: OkResponse.self
        )
    }

    /// `PATCH task-list/user` body `{task_list_id,user_id,can_edit}` (0029) → fila del miembro con
    /// `can_edit`. Solo owner (403); agrega a la cuenta del hogar si no tenía acceso.
    @discardableResult
    public func setAccess(taskListId: Int, userId: Int, canEdit: Bool) async throws -> MemberEntry {
        try await client.send(
            APIRequest(method: .patch, path: "task-list/user", body: try client.encode(UpdateTaskListUserAccessRequest(task_list_id: taskListId, user_id: userId, can_edit: canEdit))),
            as: MemberEntry.self
        )
    }
}
