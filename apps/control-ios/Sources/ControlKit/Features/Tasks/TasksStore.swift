import Foundation

/// Grupo de tareas de una misma lista (sección plegable de la pestaña Tareas).
public struct TaskGroup: Equatable, Identifiable {
    public let listId: Int
    public let name: String
    public let colorHex: String?
    public let tasks: [TaskEntry]
    public var id: Int { listId }
    public var count: Int { tasks.count }

    /// Agrupa por lista: primero las listas en el orden de `lists`, luego las listas desconocidas
    /// por orden de aparición. Dentro del grupo, pendientes antes que completadas (estable).
    /// Las listas sin tareas no generan grupo.
    public static func group(tasks: [TaskEntry], lists: [TaskListEntry]) -> [TaskGroup] {
        var order = lists.map(\.id)
        for task in tasks where !order.contains(task.task_list_id) { order.append(task.task_list_id) }
        return order.compactMap { id in
            let items = tasks.filter { $0.task_list_id == id }
            guard !items.isEmpty else { return nil }
            let list = lists.first { $0.id == id }
            return TaskGroup(
                listId: id,
                name: list?.name ?? items[0].task_list_name ?? "Sin lista",
                colorHex: list?.color ?? items[0].task_list_color,
                tasks: items.filter { !$0.isCompleted } + items.filter { $0.isCompleted }
            )
        }
    }
}

/// Estado de la pestaña Tareas: listas + tareas (paridad con `TaskViewModel`/`TaskListViewModel`).
/// Reordenar solo se permite en listas con `sort == "custom"` (como Android) y el aviso de título
/// duplicado es de cliente (mismo trim/case-insensitive por lista).
@Observable
public final class TasksStore: WriteFailureReporting {
    public private(set) var taskLists: [TaskListEntry] = []
    public private(set) var tasks: [TaskEntry] = []
    public private(set) var members: [MemberEntry] = []
    /// Personas invitables a una tarea (selector del editor, 0025).
    public private(set) var persons: [PersonEntry] = []
    public private(set) var isLoading = false
    /// Borrado masivo de completadas en curso: bloquea la lista hasta que termina.
    public private(set) var isDeletingCompleted = false
    /// Primera carga de listas y de tareas completada (loader hasta entonces).
    public private(set) var hasLoadedLists = false
    public private(set) var hasLoadedTasks = false
    /// Errores de lectura (alerta de la pantalla).
    public var errorMessage: String?
    /// Última escritura fallida (toast con «Reintentar»).
    public var writeFailure: WriteFailure?
    /// Filtro global por lista (nil = todas); dentro de una lista el filtro es la propia lista.
    public var listFilterId: Int?

    private let taskListsRepo: TaskListRepository
    private let tasksRepo: TaskRepository
    private let personsRepo: PersonRepository?

    public init(taskLists: TaskListRepository, tasks: TaskRepository, persons: PersonRepository? = nil) {
        self.personsRepo = persons
        self.taskListsRepo = taskLists
        self.tasksRepo = tasks
    }

    public var pendingTasks: [TaskEntry] { tasks.filter { !$0.isCompleted } }
    public var completedTasks: [TaskEntry] { tasks.filter { $0.isCompleted } }
    public var taskGroups: [TaskGroup] { TaskGroup.group(tasks: tasks, lists: taskLists) }
    public var activeSort: String { taskLists.first { $0.id == listFilterId }?.sort ?? "updated_at" }
    /// Reordenar (onMove) solo con orden personalizado y lista activa.
    public var canReorder: Bool { listFilterId != nil && activeSort == "custom" }

    public func loadLists() async {
        isLoading = true
        defer { isLoading = false; hasLoadedLists = true }
        do {
            taskLists = try await taskListsRepo.index()
        } catch {
            report(error)
        }
    }

    public func loadTasks() async {
        isLoading = true
        defer { isLoading = false; hasLoadedTasks = true }
        do {
            tasks = try await tasksRepo.index(taskListId: listFilterId)
        } catch {
            report(error)
        }
    }

    /// Alta rápida con guard de título duplicado por lista (paridad con Android).
    public func loadPersons() async {
        guard let personsRepo else { return }
        do {
            persons = try await personsRepo.index()
        } catch {
            report(error)
        }
    }

    /// Devuelve si se creó (el editor solo se cierra entonces y conserva lo escrito si no).
    @discardableResult
    public func createTask(title: String, listId: Int, personIds: [Int]? = nil) async -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let duplicate = tasks.contains {
            $0.task_list_id == listId && $0.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == trimmed.lowercased()
        }
        guard !duplicate else {
            rejectWrite("Ya existe una tarea con ese título en la lista")
            return false
        }
        return await performWrite { store in
            _ = try await store.tasksRepo.create(CreateTaskRequest(task_list_id: listId, title: trimmed, person_ids: personIds))
            await store.loadTasks()
        }
    }

    /// Devuelve si se guardó.
    @discardableResult
    public func updateTask(_ task: TaskEntry, title: String, personIds: [Int]? = nil) async -> Bool {
        await performWrite { store in
            _ = try await store.tasksRepo.update(UpdateTaskRequest(id: task.id, title: title, person_ids: personIds))
            await store.loadTasks()
        }
    }

    public func toggleComplete(_ task: TaskEntry) async {
        await performWrite { store in
            _ = try await store.tasksRepo.complete(CompleteTaskRequest(id: task.id, completed: !task.isCompleted))
            await store.loadTasks()
        }
    }

    /// `PATCH task/order` con `position` = índice destino dentro de la sección de pendientes
    /// (misma semántica que el reorder de Android); el servidor renumera 1..n.
    public func movePendingTask(id: Int, to position: Int) async {
        let ok = await performWrite { store in
            _ = try await store.tasksRepo.order(OrderTaskRequest(id: id, position: position))
            await store.loadTasks()
        }
        // Si falla, se recarga para deshacer el movimiento local de la lista.
        if !ok { await loadTasks() }
    }

    /// Borra todas las tareas completadas de una lista en paralelo, espera a todas y recarga una vez.
    /// Solo desaparecen las que el servidor confirma; las que fallen siguen en la lista y se avisa.
    public func deleteCompleted(listId: Int) async {
        let completed = tasks.filter { $0.task_list_id == listId && $0.isCompleted }
        guard !completed.isEmpty, !isDeletingCompleted else { return }
        isDeletingCompleted = true
        defer { isDeletingCompleted = false }

        let repo = tasksRepo
        var failed = 0
        await withTaskGroup(of: Bool.self) { group in
            for task in completed {
                group.addTask {
                    do {
                        _ = try await repo.delete(id: task.id)
                        return true
                    } catch {
                        return false
                    }
                }
            }
            for await ok in group where !ok {
                failed += 1
            }
        }
        await loadTasks()
        if failed > 0 {
            rejectWrite("No se pudieron eliminar \(failed) de \(completed.count) tareas completadas")
        }
    }

    public func deleteTask(_ task: TaskEntry) async {
        await performWrite { store in
            _ = try await store.tasksRepo.delete(id: task.id)
            await store.loadTasks()
        }
    }

    // MARK: - Listas

    /// Alta/edición de lista (nombre, orden, color, flags). Devuelve si hubo éxito.
    @discardableResult
    public func saveList(name: String, color: String, sort: String, widget: Bool, dashboard: Bool, editing: TaskListEntry?) async -> Bool {
        await performWrite { store in
            if let editing {
                _ = try await store.taskListsRepo.update(UpdateTaskListRequest(
                    id: editing.id, name: name, color: color, sort: sort, widget: widget, dashboard: dashboard
                ))
            } else {
                _ = try await store.taskListsRepo.create(CreateTaskListRequest(
                    name: name, color: color, sort: sort, widget: widget, dashboard: dashboard
                ))
            }
            await store.loadLists()
        }
    }

    public func deleteList(_ list: TaskListEntry) async {
        await performWrite { store in
            _ = try await store.taskListsRepo.delete(id: list.id)
            if store.listFilterId == list.id { store.listFilterId = nil }
            await store.loadLists()
            await store.loadTasks()
        }
    }

    // MARK: - Invitaciones

    public func loadMembers(listId: Int) async {
        do {
            members = try await taskListsRepo.users(taskListId: listId)
        } catch {
            report(error)
        }
    }

    public func invite(listId: Int, email: String) async {
        await performWrite { store in
            _ = try await store.taskListsRepo.invite(taskListId: listId, email: email)
            await store.loadMembers(listId: listId)
        }
    }

    public func removeMember(listId: Int, userId: Int) async {
        await performWrite { store in
            _ = try await store.taskListsRepo.removeUser(taskListId: listId, userId: userId)
            await store.loadMembers(listId: listId)
        }
    }

    private func report(_ error: Error) {
        errorMessage = (error as? APIError)?.userMessage ?? error.localizedDescription
    }
}
