import Foundation

/// Estado de la pestaña Tareas: listas + tareas (paridad con `TaskViewModel`/`TaskListViewModel`).
/// Reordenar solo se permite en listas con `sort == "custom"` (como Android) y el aviso de título
/// duplicado es de cliente (mismo trim/case-insensitive por lista).
@Observable
public final class TasksStore {
    public private(set) var taskLists: [TaskListEntry] = []
    public private(set) var tasks: [TaskEntry] = []
    public private(set) var members: [MemberEntry] = []
    /// Personas invitables a una tarea (selector del editor, 0025).
    public private(set) var persons: [PersonEntry] = []
    public private(set) var isLoading = false
    /// Primera carga de listas y de tareas completada (loader hasta entonces).
    public private(set) var hasLoadedLists = false
    public private(set) var hasLoadedTasks = false
    public var errorMessage: String?
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

    public func createTask(title: String, listId: Int, personIds: [Int]? = nil) async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let duplicate = tasks.contains {
            $0.task_list_id == listId && $0.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == trimmed.lowercased()
        }
        guard !duplicate else {
            errorMessage = "Ya existe una tarea con ese título en la lista"
            return
        }
        do {
            _ = try await tasksRepo.create(CreateTaskRequest(task_list_id: listId, title: trimmed, person_ids: personIds))
            await loadTasks()
        } catch {
            report(error)
        }
    }

    public func updateTask(_ task: TaskEntry, title: String, personIds: [Int]? = nil) async {
        do {
            _ = try await tasksRepo.update(UpdateTaskRequest(id: task.id, title: title, person_ids: personIds))
            await loadTasks()
        } catch {
            report(error)
        }
    }

    public func toggleComplete(_ task: TaskEntry) async {
        do {
            _ = try await tasksRepo.complete(CompleteTaskRequest(id: task.id, completed: !task.isCompleted))
            await loadTasks()
        } catch {
            report(error)
        }
    }

    /// `PATCH task/order` con `position` = índice destino dentro de la sección de pendientes
    /// (misma semántica que el reorder de Android); el servidor renumera 1..n.
    public func movePendingTask(id: Int, to position: Int) async {
        do {
            _ = try await tasksRepo.order(OrderTaskRequest(id: id, position: position))
            await loadTasks()
        } catch {
            report(error)
            await loadTasks()
        }
    }

    public func deleteTask(_ task: TaskEntry) async {
        do {
            _ = try await tasksRepo.delete(id: task.id)
            await loadTasks()
        } catch {
            report(error)
        }
    }

    // MARK: - Listas

    /// Alta/edición de lista (nombre, orden, color, flags). Devuelve si hubo éxito.
    @discardableResult
    public func saveList(name: String, color: String, sort: String, widget: Bool, dashboard: Bool, editing: TaskListEntry?) async -> Bool {
        do {
            if let editing {
                _ = try await taskListsRepo.update(UpdateTaskListRequest(
                    id: editing.id, name: name, color: color, sort: sort, widget: widget, dashboard: dashboard
                ))
            } else {
                _ = try await taskListsRepo.create(CreateTaskListRequest(
                    name: name, color: color, sort: sort, widget: widget, dashboard: dashboard
                ))
            }
            await loadLists()
            return true
        } catch {
            report(error)
            return false
        }
    }

    public func deleteList(_ list: TaskListEntry) async {
        do {
            _ = try await taskListsRepo.delete(id: list.id)
            if listFilterId == list.id { listFilterId = nil }
            await loadLists()
            await loadTasks()
        } catch {
            report(error)
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
        do {
            _ = try await taskListsRepo.invite(taskListId: listId, email: email)
            await loadMembers(listId: listId)
        } catch {
            report(error)
        }
    }

    public func removeMember(listId: Int, userId: Int) async {
        do {
            _ = try await taskListsRepo.removeUser(taskListId: listId, userId: userId)
            await loadMembers(listId: listId)
        } catch {
            report(error)
        }
    }

    private func report(_ error: Error) {
        errorMessage = (error as? APIError)?.userMessage ?? error.localizedDescription
    }
}
