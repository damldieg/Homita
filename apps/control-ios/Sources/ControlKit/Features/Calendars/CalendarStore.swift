import Foundation

/// Estado de Calendarios: CRUD, flags `widget`/`dashboard` propios e invitaciones por email.
@Observable
public final class CalendarStore: WriteFailureReporting {
    public private(set) var calendars: [CalendarEntry] = []
    public private(set) var members: [MemberEntry] = []
    /// Personas del hogar (`GET person`): fuente de las cuentas a las que se puede dar acceso.
    public private(set) var homePersons: [PersonEntry] = []
    public private(set) var isLoading = false
    /// Primera carga completada (loader hasta entonces).
    public private(set) var hasLoaded = false
    /// Errores de lectura (alerta de la pantalla).
    public var errorMessage: String?
    /// Última escritura fallida (toast con «Reintentar»).
    public var writeFailure: WriteFailure?

    /// Eventos y rutinas vinculados al calendario abierto (A4).
    public private(set) var linkedEvents: [EventEntry] = []
    public private(set) var linkedRoutines: [RoutineEntry] = []
    public private(set) var linkedLoaded = false

    private let repo: CalendarRepository
    private let events: EventRepository?
    private let routines: RoutineRepository?
    private let persons: PersonRepository?

    public init(repo: CalendarRepository, events: EventRepository? = nil, routines: RoutineRepository? = nil,
                persons: PersonRepository? = nil) {
        self.repo = repo
        self.events = events
        self.routines = routines
        self.persons = persons
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
        await performWrite { store in
            if let editing {
                _ = try await store.repo.update(UpdateCalendarRequest(
                    id: editing.id, name: name, color: color, widget: widget, dashboard: dashboard
                ))
            } else {
                _ = try await store.repo.create(CreateCalendarRequest(
                    name: name, color: color, widget: widget, dashboard: dashboard
                ))
            }
            await store.load()
        }
    }

    public func delete(_ calendar: CalendarEntry) async {
        await performWrite { store in
            _ = try await store.repo.delete(id: calendar.id)
            await store.load()
        }
    }

    // MARK: - Invitaciones

    public func loadMembers(calendarId: Int) async {
        do {
            members = try await repo.users(calendarId: calendarId)
        } catch {
            report(error)
        }
        // Las cuentas del hogar solo hacen falta si el usuario es owner (selector de permisos).
        // Un fallo aquí no tapa la lista de miembros: el selector muestra solo el ACL.
        if let persons, AccessRoster.callerIsOwner(currentUserId, in: members) {
            homePersons = (try? await persons.index()) ?? []
        }
    }

    /// Usuario de la sesión (lo fija la vista antes de cargar miembros).
    public var currentUserId: Int?

    /// Filas del panel de acceso (miembros + cuentas del hogar sin acceso, solo para el owner).
    public var accessRows: [AccessRow] {
        AccessRoster.rows(members: members, persons: homePersons, currentUserId: currentUserId)
    }

    /// Cambia el permiso de un miembro (o comparte con una cuenta del hogar). Error → toast.
    public func setAccess(calendarId: Int, userId: Int, level: AccessLevel) async {
        await performWrite { store in
            try await store.repo.setAccess(calendarId: calendarId, userId: userId, canEdit: level.canEdit)
            await store.loadMembers(calendarId: calendarId)
        }
    }

    public func invite(calendarId: Int, email: String) async {
        await performWrite { store in
            _ = try await store.repo.invite(calendarId: calendarId, email: email)
            await store.loadMembers(calendarId: calendarId)
        }
    }

    public func removeMember(calendarId: Int, userId: Int) async {
        await performWrite { store in
            _ = try await store.repo.removeUser(calendarId: calendarId, userId: userId)
            await store.loadMembers(calendarId: calendarId)
        }
    }

    private func report(_ error: Error) {
        errorMessage = (error as? APIError)?.userMessage ?? error.localizedDescription
    }
}
