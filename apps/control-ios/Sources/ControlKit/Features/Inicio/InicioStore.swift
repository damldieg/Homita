import Foundation

/// Estado de una sección de Inicio: un fallo no afecta a las demás.
public enum InicioSectionState: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case failed(String)
}

/// Estado de Inicio (versión mínima): eventos de hoy, tareas pendientes y rutinas de hoy.
/// Solo usa `event`, `task` y `routine` (nada de `/home/*`). Las rutinas se calculan en cliente.
///
/// Offline (D-024): con `outbox`, `tasks` y `taskLists` llevan el overlay de la cola (mismo patrón
/// que `TasksStore`) y el alta y el completar pasan por `TaskWriteCoordinator`.
@MainActor
@Observable
public final class InicioStore: MainActorWriteFailureReporting {
    public private(set) var events: [EventEntry] = []
    public private(set) var routines: [RoutineEntry] = []
    /// Última foto del servidor; lo que ve la UI es `tasks`/`taskLists` (con el overlay).
    private var serverTasks: [TaskEntry] = []
    private var serverTaskLists: [TaskListEntry] = []
    public private(set) var eventsState: InicioSectionState = .idle
    public private(set) var tasksState: InicioSectionState = .idle
    public private(set) var routinesState: InicioSectionState = .idle
    /// Errores de lectura (alerta de la pantalla).
    public var errorMessage: String?
    /// Última escritura fallida (toast con «Reintentar»).
    public var writeFailure: WriteFailure?

    private let eventsRepo: EventRepository
    private let tasksRepo: TaskRepository
    private let routinesRepo: RoutineRepository
    private let taskListsRepo: TaskListRepository
    private let clock: () -> LocalClock
    /// Cola offline del hogar (nil = sin offline, comportamiento previo).
    @ObservationIgnored public let outbox: OutboxStore?
    @ObservationIgnored private let coordinator: TaskWriteCoordinator?

    public init(events: EventRepository, tasks: TaskRepository, routines: RoutineRepository,
                taskLists: TaskListRepository, clock: @escaping () -> LocalClock = { LocalClock() },
                outbox: OutboxStore? = nil, isOnline: @escaping @MainActor () -> Bool = { !DataFreshness.shared.isOffline }) {
        self.eventsRepo = events
        self.tasksRepo = tasks
        self.routinesRepo = routines
        self.taskListsRepo = taskLists
        self.clock = clock
        self.outbox = outbox
        self.coordinator = outbox.map { TaskWriteCoordinator(outbox: $0, tasks: tasks, taskLists: taskLists, isOnline: isOnline) }
    }

    // MARK: - Overlay

    private var overlay: OverlayResult {
        guard let outbox else {
            return OverlayResult(tasks: serverTasks, lists: serverTaskLists, pendingTaskIds: [], pendingListIds: [])
        }
        return PendingOverlay.apply(ops: outbox.ops, idMap: outbox.idMap, tasks: serverTasks, lists: serverTaskLists)
    }

    public var tasks: [TaskEntry] { overlay.tasks }
    public var taskLists: [TaskListEntry] { overlay.lists }
    /// Tareas aún no sincronizadas (icono «Pendiente de sincronizar»).
    public var pendingTaskIds: Set<Int> { overlay.pendingTaskIds }

    /// Referencia para un ID de la UI (temporal o real).
    public func ref(for id: Int) -> Ref {
        outbox?.ref(for: id) ?? Ref(id: id)
    }

    /// Carga con guard de `generation` (como `TasksStore`): si hubo un ack en vuelo, se vuelve a pedir.
    private func fetchFresh<T>(_ fetch: () async throws -> T) async throws -> T {
        var retries = 0
        while true {
            let generation = outbox?.generation
            let result = try await fetch()
            guard let outbox, outbox.generation != generation, retries < TasksStore.staleReloadRetries else { return result }
            retries += 1
        }
    }

    /// Eventos de hoy ordenados por hora.
    public var todayEvents: [EventEntry] {
        let current = clock()
        return TodaySummary.events(events, on: current.now, timeZone: current.timeZone)
    }

    /// Eventos de hoy separados en pasados y próximos/en curso.
    public var eventSplit: (past: [EventEntry], upcoming: [EventEntry]) {
        let current = clock()
        return TodaySummary.splitEvents(todayEvents, now: current.now, timeZone: current.timeZone)
    }

    /// Filas por lista en la tarjeta de tareas de Inicio.
    public static let cardTaskLimit = 3

    /// Primeras tareas pendientes.
    public var pendingTasks: [TaskEntry] { TodaySummary.pendingTasks(tasks) }

    /// Páginas de la tarjeta de tareas: una por lista con pendientes (nombre/color de la propia tarea).
    public struct TaskPage: Identifiable, Equatable, Sendable {
        public let id: Int
        public let name: String
        public let colorHex: String
        public let tasks: [TaskEntry]
    }

    /// Pendientes agrupadas por lista (sin límite global; cada página muestra las primeras `cardTaskLimit`).
    /// Las páginas van por `position` de la lista en `taskLists` (0040: lista prioritaria primero); las listas
    /// sin posición (o aún no cargadas en `taskLists`) van al final y empatan por el orden de
    /// `TodaySummary.pendingTasks`. Las tareas dentro de cada página no cambian.
    public var pendingTaskPages: [TaskPage] {
        let all = TodaySummary.pendingTasks(tasks, limit: tasks.count)
        var firstSeen: [Int] = []
        for task in all where !firstSeen.contains(task.task_list_id) { firstSeen.append(task.task_list_id) }
        let positions = Dictionary(taskLists.compactMap { list in list.positionValue.map { (list.id, $0) } },
                                   uniquingKeysWith: { first, _ in first })
        let order = firstSeen.enumerated().sorted { lhs, rhs in
            let l = positions[lhs.element] ?? Int.max
            let r = positions[rhs.element] ?? Int.max
            return l != r ? l < r : lhs.offset < rhs.offset
        }.map(\.element)
        return order.map { listId in
            let items = all.filter { $0.task_list_id == listId }
            let first = items[0]
            return TaskPage(
                id: listId, name: first.task_list_name ?? "Tareas",
                colorHex: first.task_list_color ?? Palette.accentHex,
                tasks: Array(items.prefix(Self.cardTaskLimit))
            )
        }
    }

    /// Estado de una rutina de hoy según su hora de inicio de hoy (misma regla que la pestaña Rutinas).
    public func status(for routine: RoutineEntry) -> RoutineStatus {
        let current = clock()
        let start = RoutineStatus.startToday(time: routine.time, now: current.now, timeZone: current.timeZone)
        return RoutineStatus.evaluate(start: start, now: current.now)
    }

    /// Fase de una rutina de hoy en Inicio: finalizada, en curso, aviso (≤ 60 min) o más tarde.
    public enum RoutinePhase: Equatable, Sendable {
        case done, now, soon, later
    }

    /// Fase según el horario (D-1): caducada = finalizada; en curso; en aviso; resto = más tarde.
    public func phase(of routine: RoutineEntry) -> RoutinePhase {
        switch status(for: routine) {
        case .expired: return .done
        case .inProgress: return .now
        case .normal: return isSoon(routine) ? .soon : .later
        }
    }

    /// Aviso (≤ 60 min antes del inicio). El estado se calcula solo por horario (D-1): sin marca manual.
    public func isSoon(_ routine: RoutineEntry) -> Bool {
        let current = clock()
        return RoutineStatus.isSoon(start: startToday(of: routine), now: current.now)
    }

    /// Hora de inicio de hoy de una rutina (`nil` = sin hora fija).
    public func startToday(of routine: RoutineEntry) -> Date? {
        let current = clock()
        return RoutineStatus.startToday(time: routine.time, now: current.now, timeZone: current.timeZone)
    }

    /// Rutinas de hoy ordenadas por hora (sin hora al final).
    public var todayRoutinesByTime: [RoutineEntry] {
        let list = todayRoutines
        return list.filter(\.hasFixedTime).sorted { $0.time < $1.time } + list.filter { !$0.hasFixedTime }
    }

    /// Minutos que quedan de la ventana de 60 min de una rutina en curso (`nil` si no está en curso).
    public func minutesLeftInWindow(of routine: RoutineEntry) -> Int? {
        guard let start = startToday(of: routine) else { return nil }
        let now = clock().now
        let end = start.addingTimeInterval(RoutineStatus.window)
        guard now >= start, now <= end else { return nil }
        return max(1, Int((end.timeIntervalSince(now) / 60).rounded(.up)))
    }

    /// Fracción 0…1 de la barra de tiempo: para «aviso» cuánto falta para empezar (llena al empezar);
    /// para «en curso», cuánto lleva transcurrido de la ventana. `nil` fuera de esos dos estados.
    public func windowFraction(of routine: RoutineEntry) -> Double? {
        guard let start = startToday(of: routine) else { return nil }
        let now = clock().now
        if RoutineStatus.isSoon(start: start, now: now) {
            return 1 - start.timeIntervalSince(now) / RoutineStatus.soonWindow
        }
        if RoutineStatus.evaluate(start: start, now: now) == .inProgress {
            return now.timeIntervalSince(start) / RoutineStatus.window
        }
        return nil
    }

    /// Minutos hasta el inicio de hoy de la rutina (`nil` sin hora fija o si ya empezó).
    public func minutesUntilStart(of routine: RoutineEntry) -> Int? {
        guard let start = startToday(of: routine) else { return nil }
        let diff = Int((start.timeIntervalSince(clock().now) / 60).rounded(.up))
        return diff > 0 ? diff : nil
    }

    public var todayRoutines: [RoutineEntry] {
        let current = clock()
        return TodaySummary.routines(routines, on: current.now, timeZone: current.timeZone)
    }

    /// Carga las tres secciones; cada una conserva su propio error.
    public func load() async {
        async let eventsLoad: Void = loadEvents()
        async let tasksLoad: Void = loadTasks()
        async let routinesLoad: Void = loadRoutines()
        _ = await (eventsLoad, tasksLoad, routinesLoad)
    }

    public func loadEvents() async {
        eventsState = .loading
        let current = clock()
        let range = current.dayRange
        let filters = EventFilters(
            startDate: range.start, endDate: range.end, routine: false, timezone: current.timeZone.identifier
        )
        do {
            events = try await eventsRepo.index(filters)
            eventsState = .loaded
        } catch {
            eventsState = .failed(message(error))
        }
    }

    public func loadTasks() async {
        tasksState = .loading
        // Las listas (para el orden de las páginas por `position`) son best-effort: si fallan, las tareas
        // siguen cargando y no se toca ni `tasksState` ni `errorMessage`.
        async let listsLoad: [TaskListEntry]? = try? await fetchFresh { try await taskListsRepo.index() }
        do {
            serverTasks = try await fetchFresh { try await tasksRepo.index(taskListId: nil) }
            if let lists = await listsLoad { serverTaskLists = lists }
            tasksState = .loaded
        } catch {
            _ = await listsLoad
            tasksState = .failed(message(error))
        }
    }

    public func loadRoutines() async {
        routinesState = .loading
        let current = clock()
        do {
            routines = try await routinesRepo.index(timezone: current.timeZone.identifier)
            routinesState = .loaded
        } catch {
            routinesState = .failed(message(error))
        }
    }

    /// Completa/reabre una tarea (misma llamada que `TasksStore.toggleComplete`) y recarga tareas.
    public func toggleComplete(_ task: TaskEntry) async {
        guard let coordinator else {
            await performWrite { store in
                _ = try await store.tasksRepo.complete(CompleteTaskRequest(id: task.id, completed: !task.isCompleted))
            }
            await loadTasks()
            return
        }
        let op = coordinator.makeOp(.completeTask(ref: ref(for: task.id), listRef: ref(for: task.task_list_id), completed: !task.isCompleted))
        var queued = false
        await performWrite { store in
            guard let coordinator = store.coordinator else { return }
            queued = try await coordinator.perform(op) == .queued
        }
        // En la cola ya se ve por el overlay: no hace falta recargar.
        if !queued { await loadTasks() }
    }

    /// Edita título y personas de una tarea (mismo patrón que `TasksStore.updateTask`).
    /// Devuelve si se guardó (en cola cuenta como guardado).
    @discardableResult
    public func updateTask(_ task: TaskEntry, title: String, personIds: [Int]? = nil) async -> Bool {
        guard let coordinator else {
            return await performWrite { store in
                _ = try await store.tasksRepo.update(UpdateTaskRequest(id: task.id, title: title, person_ids: personIds))
                await store.loadTasks()
            }
        }
        let op = coordinator.makeOp(.updateTask(ref: ref(for: task.id), listRef: ref(for: task.task_list_id), title: title, personIds: personIds))
        return await performWrite { store in
            guard let coordinator = store.coordinator else { return }
            if case .sent = try await coordinator.perform(op) { await store.loadTasks() }
        }
    }

    /// Listas para el acceso rápido «+ Tarea» (se cargan al pulsar).
    public func loadTaskLists() async {
        do {
            serverTaskLists = try await fetchFresh { try await taskListsRepo.index() }
        } catch {
            errorMessage = message(error)
        }
    }

    /// Alta rápida de tarea desde Inicio. Devuelve si se creó (el editor solo se cierra entonces).
    @discardableResult
    public func createTask(title: String, listId: Int) async -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard let coordinator, let outbox else {
            return await performWrite { store in
                _ = try await store.tasksRepo.create(CreateTaskRequest(task_list_id: listId, title: trimmed))
                await store.loadTasks()
            }
        }
        let op = coordinator.makeOp(.createTask(local: outbox.makeLocalId(), listRef: ref(for: listId), title: trimmed, personIds: nil))
        return await performWrite { store in
            guard let coordinator = store.coordinator else { return }
            if case .sent = try await coordinator.perform(op) { await store.loadTasks() }
        }
    }

    private func message(_ error: Error) -> String {
        (error as? APIError)?.userMessage ?? error.localizedDescription
    }
}

/// Navegación entre las listas de la tarjeta de tareas de Inicio (swipe y VoiceOver).
public enum InicioTaskPaging {
    /// Id de la lista contigua a `current` (`forward` = la siguiente); `nil` en los extremos o si
    /// `current` no está en `ids`. Sin vuelta al principio: el gesto se detiene en la última lista.
    public static func neighbor(of current: Int, in ids: [Int], forward: Bool) -> Int? {
        guard let index = ids.firstIndex(of: current) else { return nil }
        let target = forward ? index + 1 : index - 1
        return ids.indices.contains(target) ? ids[target] : nil
    }

    /// `true` si un arrastre cuenta como swipe horizontal: recorrido suficiente y claramente más
    /// horizontal que vertical (así no compite con el scroll de la home).
    public static func isHorizontalSwipe(width: Double, height: Double) -> Bool {
        abs(width) >= 50 && abs(width) > abs(height) * 2
    }
}
