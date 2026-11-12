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

    /// Marcas manuales de «hecha» de hoy (`true` = hecha, `false` = desmarcada). No hay endpoint de
    /// completar rutinas: es estado local del dispositivo, por día (se descarta al cambiar de día).
    public private(set) var routineDoneOverrides: [Int: Bool] = [:]
    private var overridesDay: String?

    /// ¿Está hecha hoy? La marca manual manda; sin marca, una rutina caducada (pasó su hora + ventana)
    /// cuenta como hecha, igual que en la pestaña Rutinas. Solo lectura (no muta estado: se llama
    /// desde `body`); las marcas de un día anterior se ignoran y se descartan al escribir o cargar.
    public func isRoutineDone(_ routine: RoutineEntry) -> Bool {
        let override = overridesDay == currentDay() ? routineDoneOverrides[routine.id] : nil
        return override ?? (status(for: routine) == .expired)
    }

    /// Marca o desmarca una rutina de hoy como hecha.
    public func setRoutineDone(_ routine: RoutineEntry, done: Bool) {
        resetOverridesIfNewDay()
        routineDoneOverrides[routine.id] = done
    }

    private func currentDay() -> String {
        let current = clock()
        return String(PHPDateTime.format(current.now, timeZone: current.timeZone).prefix(10))
    }

    /// Descarta las marcas de un día anterior. Solo se llama fuera del render (carga y escritura).
    private func resetOverridesIfNewDay() {
        let day = currentDay()
        if overridesDay != day {
            overridesDay = day
            routineDoneOverrides = [:]
        }
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
        resetOverridesIfNewDay()
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
