import Foundation

/// Estado de Rutinas: lista + sesiones materializadas (`GET event` con `routine=true` desde el
/// inicio del mes, como Android) para la etiqueta de próxima sesión. Las sesiones individuales
/// son solo lectura. Guardar actualiza la rutina y, si cambia el aviso, `PATCH routine/alarm`.
@Observable
public final class RoutineStore {
    public private(set) var routines: [RoutineEntry] = []
    public private(set) var sessions: [EventEntry] = []
    public private(set) var isLoading = false
    /// Primera carga completada (loader hasta entonces).
    public private(set) var hasLoaded = false
    public var errorMessage: String?

    private let repo: RoutineRepository
    private let events: EventRepository
    private let clock: () -> LocalClock

    public init(repo: RoutineRepository, events: EventRepository, clock: @escaping () -> LocalClock = { LocalClock() }) {
        self.repo = repo
        self.events = events
        self.clock = clock
    }

    private var timezone: String { TimeZone.current.identifier }

    public func load() async {
        isLoading = true
        defer { isLoading = false; hasLoaded = true }
        do {
            routines = try await repo.index(timezone: timezone)
        } catch {
            report(error)
        }
        do {
            let filters = EventFilters(startDate: clock().monthStartEpoch, routine: true, timezone: timezone)
            sessions = try await events.index(filters)
        } catch {
            report(error)
        }
    }

    /// Próxima sesión futura de una rutina (a partir de las sesiones ya materializadas).
    public func nextSession(for routine: RoutineEntry) -> EventEntry? {
        let now = PHPDateTime.format(clock().now)
        return sessions
            .filter { $0.routine_id == routine.id && $0.date_at >= now }
            .min { $0.date_at < $1.date_at }
    }

    /// Alta/edición con la semántica de Android: crear lleva `alarm` en el body; editar llama a
    /// `PATCH routine/update` y luego, solo si cambió, `PATCH routine/alarm`.
    @discardableResult
    public func save(draft: RoutineDraft, editing: RoutineEntry?) async -> Bool {
        do {
            if let editing {
                _ = try await repo.update(
                    UpdateRoutineRequest(
                        id: editing.id, title: draft.title, frequency: draft.frequency, interval: draft.interval,
                        days: draft.days, time: draft.time, start_date: draft.startDate, end_date: draft.endDate,
                        active: draft.active, person_ids: draft.personIds
                    ),
                    timezone: timezone
                )
                if draft.alarm != editing.alarm {
                    _ = try await repo.setAlarm(SetRoutineAlarmRequest(id: editing.id, alarm: draft.alarm), timezone: timezone)
                }
            } else {
                _ = try await repo.create(
                    CreateRoutineRequest(
                        calendar_id: draft.calendarId, title: draft.title, frequency: draft.frequency,
                        interval: draft.interval, days: draft.days, time: draft.time, start_date: draft.startDate,
                        end_date: draft.endDate, active: draft.active, alarm: draft.alarm, person_ids: draft.personIds
                    ),
                    timezone: timezone
                )
            }
            await load()
            return true
        } catch {
            report(error)
            return false
        }
    }

    public func delete(_ routine: RoutineEntry) async {
        do {
            _ = try await repo.delete(id: routine.id, timezone: timezone)
            await load()
        } catch {
            report(error)
        }
    }

    private func report(_ error: Error) {
        errorMessage = (error as? APIError)?.userMessage ?? error.localizedDescription
    }
}

/// Borrador del formulario de rutina (paridad con `RoutineFormDialog` de Android).
public struct RoutineDraft: Equatable, Sendable {
    public var calendarId: Int
    public var title: String
    public var frequency: String
    public var interval: Int
    public var days: [Int]
    public var time: String
    public var startDate: String
    public var endDate: String?
    public var active: Bool
    public var alarm: Int?
    public var personIds: [Int]

    public init(
        calendarId: Int, title: String, frequency: String, interval: Int, days: [Int], time: String,
        startDate: String, endDate: String?, active: Bool, alarm: Int?, personIds: [Int]
    ) {
        self.calendarId = calendarId
        self.title = title
        self.frequency = frequency
        self.interval = interval
        self.days = days
        self.time = time
        self.startDate = startDate
        self.endDate = endDate
        self.active = active
        self.alarm = alarm
        self.personIds = personIds
    }
}
