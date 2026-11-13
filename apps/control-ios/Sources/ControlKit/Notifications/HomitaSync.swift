import Foundation
import HomitaShared
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Mantiene al día lo que vive fuera de la app: avisos locales, datos de los widgets y Live Activity.
///
/// Lee eventos de los próximos 7 días, rutinas y tareas, y con ellos (1) reprograma las
/// notificaciones, (2) escribe el snapshot del App Group y recarga los widgets y (3) inicia,
/// actualiza o termina la Live Activity. Cada parte respeta su toggle de Ajustes › Notificaciones.
/// Se ejecuta al abrir la app, al volver a primer plano, al cambiar un toggle y en segundo plano
/// (`BackgroundRefresh`).
@MainActor
public final class HomitaSync {
    public static let shared = HomitaSync()

    /// Intervalo mínimo entre lecturas de red (los cambios de toggle no leen de red).
    static let minFetchInterval: TimeInterval = 60

    private var services: AppServices?
    private var events: [EventEntry] = []
    private var routines: [RoutineEntry] = []
    private var tasks: [TaskEntry] = []
    private var homeName: String?
    private var hasData = false
    private var isRunning = false
    private var lastFetch: Date?
    private var boundaryTask: Task<Void, Never>?

    private let scheduler = NotificationScheduler()
    private let preferencesStore = NotificationPreferencesStore()
    private let snapshotStore = SnapshotStore()

    public init() {}

    public var preferences: NotificationPreferences {
        get { preferencesStore.load() }
        set { preferencesStore.save(newValue) }
    }

    public var isAttached: Bool { services != nil }

    /// La raíz de la app registra aquí sus servicios (hogar y sesión ya activos).
    public func attach(_ services: AppServices) {
        self.services = services
    }

    /// Lee los datos y aplica avisos, widgets y Live Activity. `allowPrompt`: puede pedir el permiso
    /// de notificaciones (solo con la app en primer plano).
    public func refresh(force: Bool = false, allowPrompt: Bool = true) async {
        guard let services, services.session.session != nil,
              case .ready(let home) = services.homeContext.state else { return }
        homeName = home.name
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        if force || lastFetch.map({ Date().timeIntervalSince($0) >= Self.minFetchInterval }) ?? true {
            await fetch(services)
        }
        await apply(allowPrompt: allowPrompt)
    }

    /// Un toggle de Ajustes cambió: se reaplica con los últimos datos, sin red.
    public func preferencesChanged() async {
        if hasData {
            await apply(allowPrompt: true)
        } else {
            await refresh(force: true)
        }
    }

    /// Cierre de sesión o cambio de cuenta: borra avisos, datos de widgets y Live Activity.
    public func reset() async {
        services = nil
        events = []
        routines = []
        tasks = []
        homeName = nil
        hasData = false
        lastFetch = nil
        boundaryTask?.cancel()
        await scheduler.removeAll()
        snapshotStore.save(.signedOut())
        reloadWidgets()
        await LiveActivityController.endAll()
    }

    // MARK: - Lectura

    private func fetch(_ services: AppServices) async {
        let clock = LocalClock()
        let timezone = clock.timeZone.identifier
        let horizon = clock.now.addingTimeInterval(Double(NotificationPlanner.horizonDays) * 86_400)
        let filters = EventFilters(
            startDate: clock.dayRange.start,
            endDate: LocalClock.epochString(for: horizon, timeZone: clock.timeZone),
            routine: false, timezone: timezone
        )
        // Un fallo (sin red) conserva los datos anteriores de esa sección.
        let newEvents = try? await services.events.index(filters)
        let newRoutines = try? await services.routines.index(timezone: timezone)
        let newTasks = try? await services.tasks.index(taskListId: nil)
        if let newEvents { events = newEvents }
        if let newRoutines { routines = newRoutines }
        if let newTasks { tasks = newTasks }
        if newEvents != nil || newRoutines != nil || newTasks != nil {
            hasData = true
            lastFetch = Date()
        }
    }

    // MARK: - Aplicación

    private func apply(allowPrompt: Bool) async {
        guard hasData else { return }
        let prefs = preferencesStore.load()
        let now = Date()
        let timeZone = TimeZone.current

        // 1. Avisos locales.
        if prefs.anyReminder {
            var permission = await scheduler.permission()
            if permission == .notDetermined, allowPrompt {
                await scheduler.requestPermission()
                permission = await scheduler.permission()
            }
            if permission == .allowed {
                let planned = NotificationPlanner.plan(
                    events: events, routines: routines, pendingTasks: tasks,
                    preferences: prefs, now: now, timeZone: timeZone
                )
                await scheduler.replaceAll(with: planned, timeZone: timeZone)
            }
        } else {
            await scheduler.removeAll()
        }

        // 2. Widgets: el snapshot solo se escribe con el toggle activo.
        let snapshot = SnapshotBuilder.build(
            events: events, routines: routines, tasks: tasks, homeName: homeName, now: now, timeZone: timeZone
        )
        if prefs.widgets {
            snapshotStore.save(snapshot)
        } else {
            snapshotStore.clear()
        }
        reloadWidgets()

        // 3. Live Activity.
        await LiveActivityController.sync(snapshot: snapshot, preferences: prefs, now: now)
        scheduleBoundaryResync(snapshot: snapshot, preferences: prefs, now: now)
    }

    /// Con la app abierta, reaplica la Live Activity justo cuando cambia la fase de una rutina.
    private func scheduleBoundaryResync(snapshot: HomitaSnapshot, preferences: NotificationPreferences, now: Date) {
        boundaryTask?.cancel()
        guard preferences.routineLiveActivity, let next = snapshot.boundaries(after: now).first else { return }
        let delay = max(next.timeIntervalSince(now), 1)
        boundaryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.apply(allowPrompt: false)
        }
    }

    private func reloadWidgets() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
