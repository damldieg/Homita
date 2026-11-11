import Foundation

/// Estado de Calendarios: CRUD, flags `widget`/`dashboard` propios e invitaciones por email.
@Observable
public final class CalendarStore {
    public private(set) var calendars: [CalendarEntry] = []
    public private(set) var members: [MemberEntry] = []
    public private(set) var isLoading = false
    /// Primera carga completada (loader hasta entonces).
    public private(set) var hasLoaded = false
    public var errorMessage: String?

    /// Eventos y rutinas vinculados al calendario abierto (A4).
    public private(set) var linkedEvents: [EventEntry] = []
    public private(set) var linkedRoutines: [RoutineEntry] = []
    public private(set) var linkedLoaded = false

    private let repo: CalendarRepository
    private let events: EventRepository?
    private let routines: RoutineRepository?

    public init(repo: CalendarRepository, events: EventRepository? = nil, routines: RoutineRepository? = nil) {
        self.repo = repo
        self.events = events
        self.routines = routines
    }

    /// Carga los eventos (futuros, sin sesiones de rutina) y las rutinas del calendario (A4).
    /// Filtra por `calendar_id` en cliente para las rutinas: `GET routine` no admite ese filtro.
    public func loadLinked(calendarId: Int) async {
        guard let events, let routines else { return }
        let timezone = TimeZone.current.identifier
        let localNow = LocalClock().localNowEpoch
        // Estado limpio por carga: sin datos de un calendario anterior si esta falla (R1-03).
        linkedEvents = []
        linkedRoutines = []
        linkedLoaded = false
        do {
            async let upcoming = events.index(EventFilters(calendarId: calendarId, startDate: localNow, routine: false, timezone: timezone))
            async let allRoutines = routines.index(timezone: timezone)
            let (eventRows, routineRows) = try await (upcoming, allRoutines)
            linkedEvents = eventRows.sorted { $0.date_at < $1.date_at }
            linkedRoutines = routineRows.filter { $0.calendar_id == calendarId }
            linkedLoaded = true
        } catch {
            // Una carga cancelada (p. ej. al salir del detalle) no muestra error ni «sin vínculos» (R2-01/R2-02).
            if !Task.isCancelled { report(error) }
        }
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false; hasLoaded = true }
        do {
            calendars = try await repo.index()
        } catch {
            report(error)
        }
    }

    @discardableResult
    public func save(name: String, color: String, widget: Bool, dashboard: Bool, editing: CalendarEntry?) async -> Bool {
        do {
            if let editing {
                _ = try await repo.update(UpdateCalendarRequest(
                    id: editing.id, name: name, color: color, widget: widget, dashboard: dashboard
                ))
            } else {
                _ = try await repo.create(CreateCalendarRequest(
                    name: name, color: color, widget: widget, dashboard: dashboard
                ))
            }
            await load()
            return true
        } catch {
            report(error)
            return false
        }
    }

    public func delete(_ calendar: CalendarEntry) async {
        do {
            _ = try await repo.delete(id: calendar.id)
            await load()
        } catch {
            report(error)
        }
    }

    // MARK: - Invitaciones

    public func loadMembers(calendarId: Int) async {
        do {
            members = try await repo.users(calendarId: calendarId)
        } catch {
            report(error)
        }
    }

    public func invite(calendarId: Int, email: String) async {
        do {
            _ = try await repo.invite(calendarId: calendarId, email: email)
            await loadMembers(calendarId: calendarId)
        } catch {
            report(error)
        }
    }

    public func removeMember(calendarId: Int, userId: Int) async {
        do {
            _ = try await repo.removeUser(calendarId: calendarId, userId: userId)
            await loadMembers(calendarId: calendarId)
        } catch {
            report(error)
        }
    }

    private func report(_ error: Error) {
        errorMessage = (error as? APIError)?.userMessage ?? error.localizedDescription
    }
}
