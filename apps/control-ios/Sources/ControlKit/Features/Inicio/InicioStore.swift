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
@Observable
public final class InicioStore: WriteFailureReporting {
    public private(set) var events: [EventEntry] = []
    public private(set) var tasks: [TaskEntry] = []
    public private(set) var routines: [RoutineEntry] = []
    public private(set) var taskLists: [TaskListEntry] = []
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

    public init(events: EventRepository, tasks: TaskRepository, routines: RoutineRepository,
                taskLists: TaskListRepository, clock: @escaping () -> LocalClock = { LocalClock() }) {
        self.eventsRepo = events
        self.tasksRepo = tasks
        self.routinesRepo = routines
        self.taskListsRepo = taskLists
        self.clock = clock
    }

    /// Eventos de hoy ordenados por hora.
    public var todayEvents: [EventEntry] {
        let current = clock()
        return TodaySummary.events(events, on: current.now, timeZone: current.timeZone)
    }

    /// Primeras tareas pendientes.
    public var pendingTasks: [TaskEntry] { TodaySummary.pendingTasks(tasks) }

    /// Páginas de la tarjeta de tareas: una por lista con pendientes (nombre/color de la propia tarea).
    public struct TaskPage: Identifiable, Equatable, Sendable {
        public let id: Int
        public let name: String
        public let colorHex: String
        public let tasks: [TaskEntry]
    }

    /// Pendientes agrupadas por lista (orden de `TodaySummary.pendingTasks`, sin límite global;
    /// cada página muestra las primeras `taskLimit`).
    public var pendingTaskPages: [TaskPage] {
        let all = TodaySummary.pendingTasks(tasks, limit: tasks.count)
        var order: [Int] = []
        for task in all where !order.contains(task.task_list_id) { order.append(task.task_list_id) }
        return order.map { listId in
            let items = all.filter { $0.task_list_id == listId }
            let first = items[0]
            return TaskPage(
                id: listId, name: first.task_list_name ?? "Tareas",
                colorHex: first.task_list_color ?? Palette.accentHex,
                tasks: Array(items.prefix(TodaySummary.taskLimit))
            )
        }
    }

    /// Estado de una rutina de hoy según su hora de inicio de hoy (misma regla que la pestaña Rutinas).
    public func status(for routine: RoutineEntry) -> RoutineStatus {
        let current = clock()
        let start = RoutineStatus.startToday(time: routine.time, now: current.now, timeZone: current.timeZone)
        return RoutineStatus.evaluate(start: start, now: current.now)
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
        do {
            tasks = try await tasksRepo.index(taskListId: nil)
            tasksState = .loaded
        } catch {
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
        await performWrite { store in
            _ = try await store.tasksRepo.complete(CompleteTaskRequest(id: task.id, completed: !task.isCompleted))
        }
        await loadTasks()
    }

    /// Listas para el acceso rápido «+ Tarea» (se cargan al pulsar).
    public func loadTaskLists() async {
        do {
            taskLists = try await taskListsRepo.index()
        } catch {
            errorMessage = message(error)
        }
    }

    /// Alta rápida de tarea desde Inicio. Devuelve si se creó (el editor solo se cierra entonces).
    @discardableResult
    public func createTask(title: String, listId: Int) async -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let ok = await performWrite { store in
            _ = try await store.tasksRepo.create(CreateTaskRequest(task_list_id: listId, title: trimmed))
            await store.loadTasks()
        }
        return ok
    }

    private func message(_ error: Error) -> String {
        (error as? APIError)?.userMessage ?? error.localizedDescription
    }
}
