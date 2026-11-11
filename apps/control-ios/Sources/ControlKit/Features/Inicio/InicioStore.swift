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
public final class InicioStore {
    public private(set) var events: [EventEntry] = []
    public private(set) var tasks: [TaskEntry] = []
    public private(set) var routines: [RoutineEntry] = []
    public private(set) var taskLists: [TaskListEntry] = []
    public private(set) var eventsState: InicioSectionState = .idle
    public private(set) var tasksState: InicioSectionState = .idle
    public private(set) var routinesState: InicioSectionState = .idle
    public var errorMessage: String?

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

    /// Rutinas que tocan hoy.
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
        do {
            _ = try await tasksRepo.complete(CompleteTaskRequest(id: task.id, completed: !task.isCompleted))
        } catch {
            errorMessage = message(error)
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

    /// Alta rápida de tarea desde Inicio.
    public func createTask(title: String, listId: Int) async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            _ = try await tasksRepo.create(CreateTaskRequest(task_list_id: listId, title: trimmed))
        } catch {
            errorMessage = message(error)
        }
        await loadTasks()
    }

    private func message(_ error: Error) -> String {
        (error as? APIError)?.userMessage ?? error.localizedDescription
    }
}
