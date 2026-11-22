import Foundation

/// Resultado del overlay: lo que ve la UI (servidor + cola) y qué filas están pendientes.
public struct OverlayResult: Equatable {
    public let tasks: [TaskEntry]
    public let lists: [TaskListEntry]
    public let pendingTaskIds: Set<Int>
    public let pendingListIds: Set<Int>
}

/// Aplica la cola offline sobre la última foto del servidor (D-024). Función pura: los stores la
/// llaman en sus propiedades calculadas, así una recarga nunca pisa lo pendiente (R3). Las filas
/// creadas offline llevan el ID temporal (o el real si ya se confirmó) y, si el servidor ya trae
/// ese ID, no se duplican.
public enum PendingOverlay {
    public static func apply(ops: [PendingOp], idMap: [Int: Int], tasks serverTasks: [TaskEntry], lists serverLists: [TaskListEntry]) -> OverlayResult {
        var tasks = serverTasks
        var lists = serverLists
        var pendingTasks = Set<Int>()
        var pendingLists = Set<Int>()

        func adjustCount(listId: Int, by delta: Int) {
            guard delta != 0, let index = lists.firstIndex(where: { $0.id == listId }) else { return }
            let list = lists[index]
            lists[index] = list.overlay(pendingCount: max(0, list.pendingTaskCount + delta))
        }

        for op in ops {
            switch op.kind {
            case .createList(let local, let name, let color, let sort, let widget, let dashboard):
                let id = Ref.local(local).displayId(with: idMap)
                pendingLists.insert(id)
                guard !lists.contains(where: { $0.id == id }) else { continue }
                lists.append(TaskListEntry(
                    id: id, name: name, color: color, token: nil, sort: sort, created_at: nil, updated_at: nil,
                    widget: FlexBool(widget), dashboard: FlexBool(dashboard), pending_task_count: FlexInt(0), can_edit: FlexBool(true)
                ))

            case .updateList(let ref, let name, let color, let sort, let widget, let dashboard):
                let id = ref.displayId(with: idMap)
                guard let index = lists.firstIndex(where: { $0.id == id }) else { continue }
                lists[index] = lists[index].overlay(name: name, color: color, sort: sort, widget: widget, dashboard: dashboard)
                pendingLists.insert(id)

            case .deleteList(let ref):
                let id = ref.displayId(with: idMap)
                lists.removeAll { $0.id == id }
                let removed = Set(tasks.filter { $0.task_list_id == id }.map(\.id))
                tasks.removeAll { $0.task_list_id == id }
                pendingLists.remove(id)
                pendingTasks.subtract(removed)

            case .createTask(let local, let listRef, let title, _, let priority):
                let id = Ref.local(local).displayId(with: idMap)
                let listId = listRef.displayId(with: idMap)
                pendingTasks.insert(id)
                guard !tasks.contains(where: { $0.id == id }) else { continue }
                let list = lists.first { $0.id == listId }
                tasks.append(TaskEntry(
                    id: id, task_list_id: listId, title: title, completed_at: nil, created_at: PHPDateTime.format(op.createdAt),
                    updated_at: nil, order: nil, task_list_color: list?.color, task_list_name: list?.name, persons: nil,
                    priority: priority ?? TaskPriority.media.rawValue
                ))
                adjustCount(listId: listId, by: 1)

            case .updateTask(let ref, _, let title, _, let priority):
                let id = ref.displayId(with: idMap)
                guard let index = tasks.firstIndex(where: { $0.id == id }) else { continue }
                tasks[index] = tasks[index].overlay(title: title, priority: priority)
                pendingTasks.insert(id)

            case .completeTask(let ref, _, let completed):
                let id = ref.displayId(with: idMap)
                guard let index = tasks.firstIndex(where: { $0.id == id }) else { continue }
                let task = tasks[index]
                pendingTasks.insert(id)
                guard task.isCompleted != completed else { continue }
                let completedAt: String? = completed ? PHPDateTime.format(op.createdAt) : nil
                tasks[index] = task.overlay(completedAt: .some(completedAt))
                adjustCount(listId: task.task_list_id, by: completed ? -1 : 1)

            case .deleteTask(let ref, _):
                let id = ref.displayId(with: idMap)
                if let task = tasks.first(where: { $0.id == id }), !task.isCompleted {
                    adjustCount(listId: task.task_list_id, by: -1)
                }
                tasks.removeAll { $0.id == id }
                pendingTasks.remove(id)
            }
        }

        // Las tareas de una lista creada o editada offline muestran su nombre y color actuales.
        if !pendingLists.isEmpty {
            for index in tasks.indices {
                let task = tasks[index]
                guard pendingLists.contains(task.task_list_id), let list = lists.first(where: { $0.id == task.task_list_id }) else { continue }
                tasks[index] = task.overlay(listName: list.name, listColor: list.color)
            }
        }

        return OverlayResult(tasks: tasks, lists: lists, pendingTaskIds: pendingTasks, pendingListIds: pendingLists)
    }
}

// MARK: - Copias con cambios (memberwise `internal`)

extension TaskEntry {
    func overlay(title: String? = nil, completedAt: String?? = nil, listName: String? = nil, listColor: String? = nil, priority: String? = nil) -> TaskEntry {
        TaskEntry(
            id: id, task_list_id: task_list_id, title: title ?? self.title,
            completed_at: completedAt ?? completed_at, created_at: created_at, updated_at: updated_at, order: order,
            task_list_color: listColor ?? task_list_color, task_list_name: listName ?? task_list_name, persons: persons,
            priority: priority ?? self.priority
        )
    }
}

extension TaskListEntry {
    func overlay(name: String? = nil, color: String? = nil, sort: String? = nil, widget: Bool? = nil, dashboard: Bool? = nil, pendingCount: Int? = nil) -> TaskListEntry {
        TaskListEntry(
            id: id, name: name ?? self.name, color: color ?? self.color, token: token, sort: sort ?? self.sort,
            created_at: created_at, updated_at: updated_at,
            widget: widget.map(FlexBool.init) ?? self.widget, dashboard: dashboard.map(FlexBool.init) ?? self.dashboard,
            pending_task_count: pendingCount.map(FlexInt.init) ?? pending_task_count, can_edit: can_edit,
            home_id: home_id
        )
    }
}
