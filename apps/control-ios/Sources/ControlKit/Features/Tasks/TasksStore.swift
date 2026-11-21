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

/// Orden de la vista de tareas (0037, por dispositivo, A10). `.list` es el de siempre (servidor:
/// pendientes primero, luego `order`); `.priority` ordena alta > media > baja dentro de pendientes y
/// de completadas, con desempate por el orden de la lista.
public enum TaskSortMode: String, CaseIterable, Identifiable, Sendable {
    case list
    case priority

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .list: return "Lista"
        case .priority: return "Prioridad"
        }
    }
}

/// Orden y filtro por prioridad en cliente (0037). Se aplican sobre las tareas con el overlay ya
/// aplicado, así también entran las pendientes offline. Función pura.
public enum TaskPriorityOrdering {
    /// Filtra por `filter` (nil = todas) y, con `.priority`, ordena por (completada, rango, posición
    /// original): la posición original es el orden del servidor (`order`, `id`) más las pendientes
    /// locales al final, igual que en el orden de lista.
    public static func apply(_ tasks: [TaskEntry], sort: TaskSortMode, filter: TaskPriority?) -> [TaskEntry] {
        let filtered = filter.map { wanted in tasks.filter { $0.priorityValue == wanted } } ?? tasks
        guard sort == .priority else { return filtered }
        return filtered.enumerated().sorted { lhs, rhs in
            let l = lhs.element, r = rhs.element
            if l.isCompleted != r.isCompleted { return !l.isCompleted }
            if l.priorityValue.rank != r.priorityValue.rank { return l.priorityValue.rank < r.priorityValue.rank }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }
}

/// Estado de la pestaña Tareas: listas + tareas (paridad con `TaskViewModel`/`TaskListViewModel`).
/// Reordenar solo se permite en listas con `sort == "custom"` (como Android) y el aviso de título
/// duplicado es de cliente (mismo trim/case-insensitive por lista).
///
/// Offline (D-024): con `outbox`, `tasks` y `taskLists` son la última foto del servidor más la cola
/// pendiente (overlay calculado: una recarga nunca pisa lo pendiente) y las escrituras pasan por
/// `TaskWriteCoordinator` (online-first, caída a la cola). Sin `outbox`, el comportamiento de siempre.
@MainActor
@Observable
public final class TasksStore: MainActorWriteFailureReporting {
    /// Última foto del servidor; lo que ve la UI es `taskLists`/`tasks` (con el overlay).
    private var serverLists: [TaskListEntry] = []
    private var serverTasks: [TaskEntry] = []
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
    /// Orden de la vista (0037): `.list` por defecto (el de siempre). Se guarda en UserDefaults.
    public var sortMode: TaskSortMode = .list {
        didSet { defaults.set(sortMode.rawValue, forKey: Self.sortModeKey) }
    }
    /// Filtro por prioridad (0037): nil = todas (por defecto). Se guarda en UserDefaults.
    public var priorityFilter: TaskPriority? {
        didSet {
            if let priorityFilter {
                defaults.set(priorityFilter.rawValue, forKey: Self.priorityFilterKey)
            } else {
                defaults.removeObject(forKey: Self.priorityFilterKey)
            }
        }
    }

    static let sortModeKey = "tasks.sortMode"
    static let priorityFilterKey = "tasks.priorityFilter"
    @ObservationIgnored private let defaults: UserDefaults

    private let taskListsRepo: TaskListRepository
    private let tasksRepo: TaskRepository
    private let personsRepo: PersonRepository?
    /// Cola offline del hogar (nil = sin offline, comportamiento previo).
    @ObservationIgnored public let outbox: OutboxStore?
    @ObservationIgnored private let coordinator: TaskWriteCoordinator?
    @ObservationIgnored private let isOnline: @MainActor () -> Bool

    /// Reintentos de una carga cuyo resultado quedó viejo por un ack en vuelo (guard de `generation`).
    static let staleReloadRetries = 2

    public init(taskLists: TaskListRepository, tasks: TaskRepository, persons: PersonRepository? = nil,
                outbox: OutboxStore? = nil, isOnline: @escaping @MainActor () -> Bool = { !DataFreshness.shared.isOffline },
                defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.sortMode = defaults.string(forKey: Self.sortModeKey).flatMap(TaskSortMode.init(rawValue:)) ?? .list
        self.priorityFilter = defaults.string(forKey: Self.priorityFilterKey).flatMap(TaskPriority.init(rawValue:))
        self.personsRepo = persons
        self.taskListsRepo = taskLists
        self.tasksRepo = tasks
        self.outbox = outbox
        self.isOnline = isOnline
        self.coordinator = outbox.map { TaskWriteCoordinator(outbox: $0, tasks: tasks, taskLists: taskLists, isOnline: isOnline) }
    }

    // MARK: - Overlay

    /// Servidor + cola. Con filtro de lista, solo las tareas de esa lista (también las pendientes).
    private var overlay: OverlayResult {
        guard let outbox else {
            return OverlayResult(tasks: serverTasks, lists: serverLists, pendingTaskIds: [], pendingListIds: [])
        }
        let result = PendingOverlay.apply(ops: outbox.ops, idMap: outbox.idMap, tasks: serverTasks, lists: serverLists)
        guard let listFilterId else { return result }
        let filter = resolve(listFilterId)
        return OverlayResult(
            tasks: result.tasks.filter { $0.task_list_id == filter }, lists: result.lists,
            pendingTaskIds: result.pendingTaskIds, pendingListIds: result.pendingListIds
        )
    }

    public var taskLists: [TaskListEntry] { overlay.lists }
    public var tasks: [TaskEntry] { overlay.tasks }
    /// Filas aún no sincronizadas (icono «Pendiente de sincronizar»).
    public var pendingTaskIds: Set<Int> { overlay.pendingTaskIds }
    public var pendingListIds: Set<Int> { overlay.pendingListIds }

    /// ID real de un temporal ya confirmado; el mismo ID si es remoto o aún no se resolvió.
    public func resolve(_ id: Int) -> Int {
        outbox?.resolve(id) ?? id
    }

    /// Referencia para un ID de la UI (temporal o real).
    public func ref(for id: Int) -> Ref {
        outbox?.ref(for: id) ?? Ref(id: id)
    }

    /// Carga con guard de `generation`: si hubo un ack mientras estaba en vuelo, el resultado puede
    /// ser previo al replay y se vuelve a pedir (máximo `staleReloadRetries` veces).
    private func fetchFresh<T>(_ fetch: () async throws -> T) async throws -> T {
        var retries = 0
        while true {
            let generation = outbox?.generation
            let result = try await fetch()
            guard let outbox, outbox.generation != generation, retries < Self.staleReloadRetries else { return result }
            retries += 1
        }
    }

    /// Tareas que muestra la vista: overlay + filtro y orden por prioridad (0037).
    public var visibleTasks: [TaskEntry] { TaskPriorityOrdering.apply(tasks, sort: sortMode, filter: priorityFilter) }
    public var pendingTasks: [TaskEntry] { visibleTasks.filter { !$0.isCompleted } }
    public var completedTasks: [TaskEntry] { visibleTasks.filter { $0.isCompleted } }
    public var taskGroups: [TaskGroup] { TaskGroup.group(tasks: visibleTasks, lists: taskLists) }
    public var activeSort: String { taskLists.first { $0.id == listFilterId }?.sort ?? "updated_at" }
    /// ¿Hay orden o filtro por prioridad activo? (la vista lo muestra en la toolbar)
    public var hasPriorityView: Bool { sortMode != .list || priorityFilter != nil }
    /// Reordenar (onMove) solo con orden personalizado y lista activa, con red y sin cambios
    /// pendientes (el reorden no se encola, Q9 y R8), y sin orden ni filtro por prioridad (0037: la
    /// posición en pantalla no sería la de la lista).
    public var canReorder: Bool {
        listFilterId != nil && activeSort == "custom" && isOnline() && (outbox?.isEmpty ?? true) && !hasPriorityView
    }

    public func loadLists() async {
        isLoading = true
        defer { isLoading = false; hasLoadedLists = true }
        do {
            serverLists = try await fetchFresh { try await taskListsRepo.index() }
        } catch {
            report(error)
        }
    }

    public func loadTasks() async {
        isLoading = true
        defer { isLoading = false; hasLoadedTasks = true }
        // Tras el ack de un create de lista, el filtro pasa del ID temporal al real.
        if let listFilterId { self.listFilterId = resolve(listFilterId) }
        // Una lista local aún no existe en el servidor: solo cuenta el overlay.
        if let listFilterId, listFilterId < 0 {
            serverTasks = []
            return
        }
        do {
            let filter = listFilterId
            serverTasks = try await fetchFresh { try await tasksRepo.index(taskListId: filter) }
        } catch {
            report(error)
        }
    }

    /// Envía o encola la op (offline) y recarga solo si se envió. Sin cola, `legacy` es la escritura
    /// de siempre. La op se crea fuera del cierre: el reintento reusa el mismo `client_request_id`.
    @discardableResult
    private func write(_ kind: PendingOp.Kind?, reload: @escaping @MainActor (TasksStore) async -> Void,
                       legacy: @escaping @MainActor (TasksStore) async throws -> Void) async -> Bool {
        guard let coordinator, let kind else {
            return await performWrite { store in
                try await legacy(store)
                await reload(store)
            }
        }
        let op = coordinator.makeOp(kind)
        return await performWrite { store in
            guard let coordinator = store.coordinator else { return }
            if case .sent = try await coordinator.perform(op) { await reload(store) }
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
    public func createTask(title: String, listId: Int, personIds: [Int]? = nil, priority: TaskPriority? = nil) async -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        // Cuenta también las filas pendientes del overlay (Q10).
        let list = resolve(listId)
        let duplicate = tasks.contains {
            $0.task_list_id == list && $0.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == trimmed.lowercased()
        }
        guard !duplicate else {
            rejectWrite("Ya existe una tarea con ese título en la lista")
            return false
        }
        let kind = outbox.map {
            PendingOp.Kind.createTask(local: $0.makeLocalId(), listRef: ref(for: listId), title: trimmed, personIds: personIds,
                                      priority: priority?.rawValue)
        }
        return await write(kind, reload: { await $0.loadTasks() }) { store in
            _ = try await store.tasksRepo.create(CreateTaskRequest(task_list_id: listId, title: trimmed, person_ids: personIds,
                                                                   priority: priority?.rawValue))
        }
    }

    /// Devuelve si se guardó. `priority` solo se envía si cambió respecto a `task` (no pisa el
    /// cambio de otro usuario cuando solo se edita el título).
    @discardableResult
    public func updateTask(_ task: TaskEntry, title: String, personIds: [Int]? = nil, priority: TaskPriority? = nil) async -> Bool {
        let changed = priority.flatMap { $0 == task.priorityValue && task.priority != nil ? nil : $0.rawValue }
        let kind = PendingOp.Kind.updateTask(ref: ref(for: task.id), listRef: ref(for: task.task_list_id), title: title,
                                             personIds: personIds, priority: changed)
        return await write(kind, reload: { await $0.loadTasks() }) { store in
            _ = try await store.tasksRepo.update(UpdateTaskRequest(id: task.id, title: title, person_ids: personIds, priority: changed))
        }
    }

    public func toggleComplete(_ task: TaskEntry) async {
        let kind = PendingOp.Kind.completeTask(ref: ref(for: task.id), listRef: ref(for: task.task_list_id), completed: !task.isCompleted)
        await write(kind, reload: { await $0.loadTasks() }) { store in
            _ = try await store.tasksRepo.complete(CompleteTaskRequest(id: task.id, completed: !task.isCompleted))
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
    /// Offline (o con cambios pendientes) encola un delete por tarea: las creadas offline se anulan
    /// con su create; con red, un fallo de red también se encola en vez de avisar.
    public func deleteCompleted(listId: Int) async {
        let list = resolve(listId)
        let completed = tasks.filter { $0.task_list_id == list && $0.isCompleted }
        guard !completed.isEmpty, !isDeletingCompleted else { return }
        isDeletingCompleted = true
        defer { isDeletingCompleted = false }

        let deleteKind: (TaskEntry) -> PendingOp.Kind = { [unowned self] task in
            .deleteTask(ref: ref(for: task.id), listRef: ref(for: task.task_list_id))
        }
        if let outbox, !outbox.isEmpty || !isOnline() || completed.contains(where: { ref(for: $0.id).isLocal }) {
            for task in completed {
                outbox.enqueue(PendingOp(homeId: outbox.homeId, kind: deleteKind(task)))
            }
            return
        }

        let repo = tasksRepo
        var failed = 0
        var offline: [TaskEntry] = []
        await withTaskGroup(of: (TaskEntry, Error?).self) { group in
            for task in completed {
                group.addTask {
                    do {
                        _ = try await repo.delete(id: task.id)
                        return (task, nil)
                    } catch {
                        return (task, error)
                    }
                }
            }
            for await (task, error) in group {
                guard let error else { continue }
                if outbox != nil, case APIError.network? = error as? APIError {
                    offline.append(task)
                } else {
                    failed += 1
                }
            }
        }
        if let outbox {
            for task in offline {
                outbox.enqueue(PendingOp(homeId: outbox.homeId, kind: deleteKind(task)))
            }
        }
        await loadTasks()
        if failed > 0 {
            rejectWrite("No se pudieron eliminar \(failed) de \(completed.count) tareas completadas")
        }
    }

    public func deleteTask(_ task: TaskEntry) async {
        let kind = PendingOp.Kind.deleteTask(ref: ref(for: task.id), listRef: ref(for: task.task_list_id))
        await write(kind, reload: { await $0.loadTasks() }) { store in
            _ = try await store.tasksRepo.delete(id: task.id)
        }
    }

    // MARK: - Listas

    /// Alta/edición de lista (nombre, orden, color, flags). Devuelve si hubo éxito.
    @discardableResult
    public func saveList(name: String, color: String, sort: String, widget: Bool, dashboard: Bool, editing: TaskListEntry?) async -> Bool {
        let kind: PendingOp.Kind? = outbox.map { outbox in
            if let editing {
                return .updateList(ref: ref(for: editing.id), name: name, color: color, sort: sort, widget: widget, dashboard: dashboard)
            }
            return .createList(local: outbox.makeLocalId(), name: name, color: color, sort: sort, widget: widget, dashboard: dashboard)
        }
        return await write(kind, reload: { await $0.loadLists() }) { store in
            if let editing {
                _ = try await store.taskListsRepo.update(UpdateTaskListRequest(
                    id: editing.id, name: name, color: color, sort: sort, widget: widget, dashboard: dashboard
                ))
            } else {
                _ = try await store.taskListsRepo.create(CreateTaskListRequest(
                    name: name, color: color, sort: sort, widget: widget, dashboard: dashboard
                ))
            }
        }
    }

    public func deleteList(_ list: TaskListEntry) async {
        guard let coordinator else {
            await performWrite { store in
                _ = try await store.taskListsRepo.delete(id: list.id)
                if store.listFilterId == list.id { store.listFilterId = nil }
                await store.loadLists()
                await store.loadTasks()
            }
            return
        }
        let op = coordinator.makeOp(.deleteList(ref: ref(for: list.id)))
        await performWrite { store in
            guard let coordinator = store.coordinator else { return }
            let outcome = try await coordinator.perform(op)
            if let filter = store.listFilterId, store.resolve(filter) == store.resolve(list.id) { store.listFilterId = nil }
            if case .sent = outcome {
                await store.loadLists()
                await store.loadTasks()
            }
        }
    }

    // MARK: - Invitaciones

    public func loadMembers(listId: Int) async {
        // Una lista creada offline aún no tiene miembros en el servidor.
        let listId = resolve(listId)
        guard listId > 0 else {
            members = []
            return
        }
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

    /// Usuario de la sesión (lo fija la vista antes de cargar miembros).
    public var currentUserId: Int?

    /// Filas del panel de acceso de la lista (miembros + cuentas del hogar sin acceso, solo owner).
    public var accessRows: [AccessRow] {
        AccessRoster.rows(members: members, persons: persons, currentUserId: currentUserId)
    }

    /// Miembros cargados de la lista de la tarea abierta: `members` siempre es de una sola lista.
    public func loadAccess(forTask task: TaskEntry) async {
        await loadMembers(listId: task.task_list_id)
        if persons.isEmpty { await loadPersons() }
    }

    /// Cambia el permiso de un miembro en la lista (o comparte con una cuenta del hogar).
    public func setAccess(listId: Int, userId: Int, level: AccessLevel) async {
        await performWrite { store in
            try await store.taskListsRepo.setAccess(taskListId: listId, userId: userId, canEdit: level.canEdit)
            await store.loadMembers(listId: listId)
        }
    }

    private func report(_ error: Error) {
        errorMessage = (error as? APIError)?.userMessage ?? error.localizedDescription
    }
}
