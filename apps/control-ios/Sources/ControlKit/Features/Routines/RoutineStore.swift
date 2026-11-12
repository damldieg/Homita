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

    /// Rutinas por próxima ocurrencia (A3): las que tienen sesión futura primero, la más cercana antes;
    /// las que no tienen próxima al final, en su orden original.
    public var routinesByNextOccurrence: [RoutineEntry] {
        let indexed = routines.enumerated().map { (index: $0.offset, routine: $0.element, next: nextSession(for: $0.element)?.date_at) }
        let sorted = indexed.sorted { lhs, rhs in
            switch (lhs.next, rhs.next) {
            case let (l?, r?): return l == r ? lhs.index < rhs.index : l < r
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return lhs.index < rhs.index
            }
        }.map(\.routine)
        // Sin hora fija al final (orden estable).
        return sorted.filter(\.hasFixedTime) + sorted.filter { !$0.hasFixedTime }
    }

    /// Secciones por fecha de la próxima ocurrencia (Hoy, Mañana, Próxima semana); omite las vacías.
    /// Dentro de cada grupo, las de hora fija primero y las sin hora fija al final.
    /// Sin próxima ocurrencia o posterior a mañana → "Próxima semana".
    public var routineSections: [(group: RoutineDayGroup, routines: [RoutineEntry])] {
        let clock = clock()
        let today = String(PHPDateTime.format(clock.now, timeZone: clock.timeZone).prefix(10))
        // Mañana por calendario (no now + 86400): correcto en cambios de hora.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = clock.timeZone
        let tomorrowDate = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: clock.now)) ?? clock.now
        let tomorrow = String(PHPDateTime.format(tomorrowDate, timeZone: clock.timeZone).prefix(10))
        func group(of routine: RoutineEntry) -> RoutineDayGroup {
            guard let day = nextSession(for: routine)?.date_at.prefix(10) else { return .nextWeek }
            if day == today { return .today }
            if day == tomorrow { return .tomorrow }
            return .nextWeek
        }
        let ordered = routinesByNextOccurrence
        return RoutineDayGroup.allCases.compactMap { target in
            var items = ordered.filter { group(of: $0) == target }
            // Hoy también las que ya pasaron o caducaron hoy (se muestran deshabilitadas, al final).
            if target == .today {
                items += ordered.filter { group(of: $0) != .today && hasExpiredToday($0) }
            }
            return items.isEmpty ? nil : (group: target, routines: items)
        }
    }

    /// ¿La última ocurrencia de hoy que ya empezó está caducada (pasó su hora + ventana)?
    private func hasExpiredToday(_ routine: RoutineEntry) -> Bool {
        let clock = clock()
        guard routine.hasFixedTime else { return false }
        let today = String(PHPDateTime.format(clock.now, timeZone: clock.timeZone).prefix(10))
        let starts = sessions
            .filter { $0.routine_id == routine.id && $0.date_at.hasPrefix(today) }
            .compactMap { PHPDateTime.parse($0.date_at, timeZone: clock.timeZone) }
        let started = RoutineStatus.relevantStart(among: starts, now: clock.now)
        return RoutineStatus.evaluate(start: started, now: clock.now) == .expired
    }

    /// Estado de la fila en un grupo: en "Hoy" una rutina con la sesión de hoy caducada va como caducada
    /// aunque su próxima ocurrencia sea posterior; en el resto, `status(for:)`.
    public func status(for routine: RoutineEntry, in group: RoutineDayGroup) -> RoutineStatus {
        let base = status(for: routine)
        if group == .today, base == .normal, hasExpiredToday(routine) { return .expired }
        return base
    }

    /// Estado de la ocurrencia mostrada: en curso si una sesión de hoy está dentro de su hora; si hay
    /// próxima ocurrencia (hoy más tarde, mañana o posterior) → normal; sin hora fija → normal.
    public func status(for routine: RoutineEntry) -> RoutineStatus {
        let clock = clock()
        guard routine.hasFixedTime else { return .normal }
        let today = String(PHPDateTime.format(clock.now, timeZone: clock.timeZone).prefix(10))
        let starts = sessions
            .filter { $0.routine_id == routine.id && $0.date_at.hasPrefix(today) }
            .compactMap { PHPDateTime.parse($0.date_at, timeZone: clock.timeZone) }
        let started = RoutineStatus.relevantStart(among: starts, now: clock.now)
        let next = nextSession(for: routine).flatMap { PHPDateTime.parse($0.date_at, timeZone: clock.timeZone) }
        return RoutineStatus.evaluateShown(started: started, next: next, now: clock.now)
    }

    /// Próxima sesión futura de una rutina (a partir de las sesiones ya materializadas).
    public func nextSession(for routine: RoutineEntry) -> EventEntry? {
        let current = clock()
        let now = PHPDateTime.format(current.now, timeZone: current.timeZone)
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

/// Grupo de día de la lista de rutinas.
public enum RoutineDayGroup: CaseIterable, Sendable {
    case today, tomorrow, nextWeek

    public var title: String {
        switch self {
        case .today: return "Hoy"
        case .tomorrow: return "Mañana"
        case .nextWeek: return "Próxima semana"
        }
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
