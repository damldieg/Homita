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
    /// «Comidas de hoy» (`GET meal/today`); `nil` hasta la primera carga o si falla sin datos previos.
    public private(set) var mealsToday: MealsToday?
    public private(set) var mealsState: InicioSectionState = .idle
    /// Diferencia entre la hora del hogar que devolvió el servidor y el reloj del dispositivo en ese
    /// momento: así «ahora» sigue siendo la hora del hogar aunque pase el tiempo o la zona difiera.
    private var mealsSkew: TimeInterval = 0
    /// Errores de lectura (alerta de la pantalla).
    public var errorMessage: String?
    /// Última escritura fallida (toast con «Reintentar»).
    public var writeFailure: WriteFailure?

    private let eventsRepo: EventRepository
    private let tasksRepo: TaskRepository
    private let routinesRepo: RoutineRepository
    private let taskListsRepo: TaskListRepository
    private let mealsRepo: MealRepository?
    private let clock: () -> LocalClock
    /// Cola offline del hogar (nil = sin offline, comportamiento previo).
    @ObservationIgnored public let outbox: OutboxStore?
    @ObservationIgnored private let coordinator: TaskWriteCoordinator?
    /// Personas asignables en el alta rápida (0038: con cuenta y acceso a la lista).
    @ObservationIgnored public let assignees: TaskAssigneeLoader
    /// Personas del hogar para saber cuáles son mías (banner de vencimiento, 0041). Best-effort.
    @ObservationIgnored private let personsRepo: PersonRepository?
    private var roster: [PersonEntry] = []
    /// Avisos de vencimiento cerrados en esta sesión (no persisten).
    public private(set) var dismissedDueIds: Set<Int> = []

    public init(events: EventRepository, tasks: TaskRepository, routines: RoutineRepository,
                taskLists: TaskListRepository, persons: PersonRepository? = nil,
                meals: MealRepository? = nil,
                clock: @escaping () -> LocalClock = { LocalClock() },
                outbox: OutboxStore? = nil, isOnline: @escaping @MainActor () -> Bool = { !DataFreshness.shared.isOffline }) {
        self.eventsRepo = events
        self.tasksRepo = tasks
        self.routinesRepo = routines
        self.taskListsRepo = taskLists
        self.mealsRepo = meals
        self.clock = clock
        self.outbox = outbox
        self.coordinator = outbox.map { TaskWriteCoordinator(outbox: $0, tasks: tasks, taskLists: taskLists, isOnline: isOnline) }
        self.personsRepo = persons
        self.assignees = TaskAssigneeLoader(persons: persons, taskLists: taskLists, outbox: outbox)
        assignees.onError = { [weak self] error in self?.errorMessage = self?.message(error) }
    }

    // MARK: - Overlay

    private var overlay: OverlayResult {
        guard let outbox else {
            return OverlayResult(tasks: serverTasks, lists: serverTaskLists, pendingTaskIds: [], pendingListIds: [])
        }
        return PendingOverlay.apply(ops: outbox.ops, idMap: outbox.idMap, tasks: serverTasks, lists: serverTaskLists)
    }

    public var tasks: [TaskEntry] { overlay.tasks }

    /// Banner de vencimiento de Inicio (0041): la tarea de prioridad alta más próxima, si no está cerrada.
    public func dueBanner(now: Date) -> (task: TaskEntry, due: Date)? {
        TaskDue.banner(tasks: tasks, now: now, roster: roster, currentUserId: outbox?.userId, dismissed: dismissedDueIds)
    }

    /// Prioridad alta pendiente para el resumen: las de esta cuenta y las del hogar sin asignar.
    public var highPriorityForMe: [TaskEntry] {
        TaskDue.highPriorityForMe(tasks, roster: roster, currentUserId: outbox?.userId)
    }

    /// Cierra el banner de una tarea en esta sesión; no vuelve a aparecer hasta reabrir la app.
    public func dismissDueBanner(taskId: Int) {
        dismissedDueIds.insert(taskId)
    }
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

    /// Carga las secciones; cada una conserva su propio error.
    public func load() async {
        async let eventsLoad: Void = loadEvents()
        async let tasksLoad: Void = loadTasks()
        async let routinesLoad: Void = loadRoutines()
        async let mealsLoad: Void = loadMeals()
        _ = await (eventsLoad, tasksLoad, routinesLoad, mealsLoad)
    }

    // MARK: - Comidas de hoy

    /// Fase de una comida de hoy según su hora: mismas ventanas que las rutinas (aviso de 60 min
    /// antes y 60 min en curso).
    public enum MealPhase: Equatable, Sendable {
        case done, now, soon, later
    }

    /// Carga `GET meal/today`. Si falla se conserva lo anterior (stale-if-error); sin repo no hace nada.
    public func loadMeals() async {
        guard let mealsRepo else { return }
        mealsState = .loading
        do {
            let today = try await mealsRepo.today()
            mealsToday = today
            if let home = Self.homeClock(of: today) {
                mealsSkew = home.now.timeIntervalSince(clock().now)
            }
            mealsState = .loaded
        } catch {
            mealsState = .failed(message(error))
        }
    }

    /// Reloj del hogar: `date` + `now_local` interpretados en la zona del hogar (no la del dispositivo).
    static func homeClock(of today: MealsToday) -> LocalClock? {
        guard let zone = TimeZone(identifier: today.timezone),
              let now = PHPDateTime.parse("\(today.date) \(today.nowLocal):00", timeZone: zone) else { return nil }
        return LocalClock(now: now, timeZone: zone)
    }

    /// «Ahora» en el hogar: la hora devuelta por el servidor más el tiempo transcurrido desde la carga.
    public var mealsClock: LocalClock? {
        guard let today = mealsToday, let zone = TimeZone(identifier: today.timezone) else { return nil }
        return LocalClock(now: clock().now.addingTimeInterval(mealsSkew), timeZone: zone)
    }

    /// El bloque se muestra solo con un menú aceptado (`has_plan`).
    public var showsMeals: Bool { mealsToday?.hasPlan == true }

    /// Comidas de hoy por hora (y por franja si empatan).
    public var todayMeals: [MealTodayItem] {
        (mealsToday?.items ?? []).sorted { lhs, rhs in
            lhs.time != rhs.time ? lhs.time < rhs.time
                : (MealSlotKind.order.firstIndex(of: lhs.slot) ?? 0) < (MealSlotKind.order.firstIndex(of: rhs.slot) ?? 0)
        }
    }

    /// Minutos hasta la hora de la comida en el hogar (negativo si ya empezó); `nil` sin reloj o hora válida.
    public func minutesUntil(meal: MealTodayItem) -> Int? {
        guard let home = mealsClock, let today = mealsToday,
              let start = PHPDateTime.parse("\(today.date) \(meal.time.prefix(5)):00", timeZone: home.timeZone)
        else { return nil }
        return Int((start.timeIntervalSince(home.now) / 60).rounded(.up))
    }

    public func phase(of meal: MealTodayItem) -> MealPhase {
        guard let minutes = minutesUntil(meal: meal) else { return .later }
        if minutes > Int(RoutineStatus.soonWindow / 60) { return .later }
        if minutes > 0 { return .soon }
        return minutes > -Int(RoutineStatus.window / 60) ? .now : .done
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
        if let personsRepo, let people = try? await personsRepo.index() { roster = people }
        do {
            serverTasks = try await fetchFresh { try await tasksRepo.index(taskListId: nil) }
            // Fecha límite y completadas cambian los avisos locales (0041): se replanifican tras cada carga.
            await HomitaSync.shared.refresh(force: true, allowPrompt: false)
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

    /// Edita título, personas y prioridad de una tarea (mismo patrón que `TasksStore.updateTask`).
    /// La prioridad solo se envía si cambió respecto de `task.priorityValue`, para no pisar
    /// la que haya puesto otro usuario. Devuelve si se guardó (en cola cuenta como guardado).
    @discardableResult
    public func updateTask(_ task: TaskEntry, title: String, personIds: [Int]? = nil, priority: TaskPriority? = nil,
                           dueAt: String? = nil) async -> Bool {
        let changed = priority.flatMap { $0 == task.priorityValue ? nil : $0.rawValue }
        guard let coordinator else {
            return await performWrite { store in
                try await store.reloadingOnNotFound {
                    _ = try await store.tasksRepo.update(UpdateTaskRequest(id: task.id, title: title, person_ids: personIds, priority: changed,
                                                                           due_at: dueAt))
                    await store.loadTasks()
                }
            }
        }
        let op = coordinator.makeOp(.updateTask(ref: ref(for: task.id), listRef: ref(for: task.task_list_id), title: title,
                                                personIds: personIds, priority: changed, dueAt: dueAt))
        return await performWrite { store in
            guard let coordinator = store.coordinator else { return }
            try await store.reloadingOnNotFound {
                if case .sent = try await coordinator.perform(op) { await store.loadTasks() }
            }
        }
    }

    /// 0039 (D-025): si una escritura en línea sobre una tarea responde «Not Found» (se ocultó o se
    /// borró con la pantalla abierta), recarga las tareas para que desaparezca y relanza el error
    /// (toast «No encontrado»). `toggleComplete` ya recarga siempre tras un fallo.
    private func reloadingOnNotFound(_ body: @MainActor () async throws -> Void) async throws {
        do {
            try await body()
        } catch let error as APIError where error.isNotFound {
            await loadTasks()
            throw error
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

    /// Personas asignables al crear en `listId` (0038). En una lista local, la del usuario de la cola.
    public func assignablePersons(listId: Int) -> [PersonEntry] {
        assignees.assignable(listId: listId, currentUserId: outbox?.userId,
                             homeId: assignees.homeId(listId: listId, lists: serverTaskLists, fallbackHomeId: outbox.flatMap { Int($0.homeId) }))
    }

    /// Carga lo que necesita `assignablePersons` para `listId`. Devuelve si hay roster para podar.
    @discardableResult
    public func loadAssignable(listId: Int) async -> Bool {
        await assignees.load(listId: listId)
    }

    /// Alta rápida de tarea desde Inicio. Devuelve si se creó (el editor solo se cierra entonces).
    /// `personIds` vacío se trata como nil: sin selección no se envía la clave (AC-2).
    @discardableResult
    public func createTask(title: String, listId: Int, personIds: [Int]? = nil, priority: TaskPriority? = nil,
                           dueAt: String? = nil) async -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let personIds = personIds?.isEmpty == true ? nil : personIds
        guard let coordinator, let outbox else {
            return await performWrite { store in
                let created = try await store.tasksRepo.create(CreateTaskRequest(task_list_id: listId, title: trimmed, person_ids: personIds,
                                                                                 priority: priority?.rawValue))
                // 0041: create_task no recibe fecha; se fija tras crear.
                if let dueAt, !dueAt.isEmpty {
                    _ = try await store.tasksRepo.update(UpdateTaskRequest(id: created.id, title: trimmed, due_at: dueAt))
                }
                await store.loadTasks()
            }
        }
        let op = coordinator.makeOp(.createTask(local: outbox.makeLocalId(), listRef: ref(for: listId), title: trimmed, personIds: personIds,
                                                priority: priority?.rawValue, dueAt: dueAt))
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
    /// Altura mínima de la zona de la lista: tres filas y cabecera, para que la tarjeta no salte al cambiar de página.
    public static let pageMinHeight: CGFloat = 250

    /// Punto del paginador: lista que representa, si es la actual y si va difuminado (hay listas
    /// fuera de vista en ese lado).
    public struct Dot: Equatable, Sendable {
        public let listIndex: Int?
        public let highlighted: Bool
        public let faded: Bool
    }

    /// Puntos a mostrar para `n` listas con la actual en `c` (máx. 5). Con más de 5 la ventana
    /// `[s, s+4]` sigue a la actual; el primer/último punto se difuminan si quedan listas ocultas.
    public static func dots(count n: Int, current c: Int) -> [Dot] {
        guard n > 0 else { return [] }
        let cur = min(max(c, 0), n - 1)
        if n <= 5 {
            return (0..<n).map { Dot(listIndex: $0, highlighted: $0 == cur, faded: false) }
        }
        let s = min(max(cur - 1, 0), n - 5)
        return (0..<5).map { i in
            Dot(listIndex: s + i, highlighted: s + i == cur,
                faded: (i == 0 && s > 0) || (i == 4 && s + 4 < n - 1))
        }
    }

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
