import Foundation

/// Estado de la lista de eventos: próximos/pasados con los filtros del contrato (`start_date`/
/// `end_date` = epoch local de 10 dígitos, `routine=false`, `timezone` IANA), como Android.
@Observable
public final class EventStore: WriteFailureReporting {
    /// Próximos sin los «en curso» (D-020).
    public private(set) var upcoming: [EventEntry] = []
    /// Eventos de varios días cuyo rango contiene hoy (zona del dispositivo), por `date_at`.
    public private(set) var ongoing: [EventEntry] = []
    public private(set) var past: [EventEntry] = []
    public private(set) var isLoading = false
    /// Primera carga completada: hasta entonces la vista muestra el loader, no el estado vacío.
    public private(set) var hasLoaded = false
    /// Errores de lectura (alerta de la pantalla).
    public var errorMessage: String?
    /// Última escritura fallida (toast con «Reintentar»).
    public var writeFailure: WriteFailure?
    public var calendarFilterId: Int?
    public var searchText: String = ""

    private let repo: EventRepository
    private let clock: () -> LocalClock

    public init(repo: EventRepository, clock: @escaping () -> LocalClock = { LocalClock() }) {
        self.repo = repo
        self.clock = clock
    }

    private var timezone: String { TimeZone.current.identifier }

    /// Tamaño de página de «Pasados» (contrato `limit`/`offset`, I2).
    public static let pageSize = 50
    /// Hay más pasados que cargar (la última página vino llena).
    public private(set) var hasMorePast = false
    public private(set) var isLoadingMore = false
    /// Filas de «Pasados» ya cargadas: `offset` de la siguiente página.
    private var pastOffset = 0
    /// Generación de la lista: cada `load()` la incrementa. Una página de «Cargar más» pedida antes
    /// de un cambio de filtro o búsqueda se descarta al llegar, para no mezclar filas ni offsets.
    private var generation = 0

    public func load() async {
        isLoading = true
        defer { isLoading = false; hasLoaded = true }
        generation &+= 1
        let currentClock = clock()
        let localNow = currentClock.localNowEpoch
        let today = currentClock.todayString
        let search = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        var filters = EventFilters(
            calendarId: calendarFilterId,
            search: search.isEmpty ? nil : search,
            routine: false,
            timezone: timezone
        )
        filters.startDate = localNow
        do {
            var next = try await repo.index(filters)
            next.sort { $0.date_at < $1.date_at }
            // Un en curso cumple `end_date + 1d > ahora`, así que siempre llega en esta respuesta (DD-11).
            ongoing = next.filter { $0.isOngoing(today: today) }
            upcoming = next.filter { !$0.isOngoing(today: today) }
        } catch {
            report(error)
        }
        do {
            let page = try await repo.index(pastFilters(localNow: localNow, offset: 0))
            past = page.filter { !$0.isOngoing(today: today) }
            pastOffset = page.count
            hasMorePast = page.count == Self.pageSize
        } catch {
            report(error)
        }
    }

    /// Siguiente página de «Pasados» (I2). Sin efecto si no hay más o ya hay una en curso.
    public func loadMorePast() async {
        guard hasMorePast, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let requested = generation
        do {
            let page = try await repo.index(pastFilters(localNow: clock().localNowEpoch, offset: pastOffset))
            // Respuesta de una lista anterior (filtro o búsqueda cambiados mientras cargaba): se descarta.
            guard requested == generation else { return }
            let today = clock().todayString
            // Offset y «hay más» siguen el `count` bruto de la página, no el filtrado (DD-11).
            past.append(contentsOf: page.filter { !$0.isOngoing(today: today) })
            pastOffset += page.count
            hasMorePast = page.count == Self.pageSize
        } catch {
            report(error)
        }
    }

    /// Filtros de «Pasados»: fin = ahora, orden descendente, paginado.
    private func pastFilters(localNow: String, offset: Int) -> EventFilters {
        let search = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        var filters = EventFilters(
            calendarId: calendarFilterId,
            search: search.isEmpty ? nil : search,
            routine: false,
            timezone: timezone
        )
        filters.endDate = localNow
        filters.orderMode = "DESC"
        filters.limit = Self.pageSize
        filters.offset = offset
        return filters
    }

    /// Alta/edición. La validación de cliente exige título (v1 sin "modo IA").
    @discardableResult
    public func save(draft: EventDraft, editing: EventEntry?) async -> Bool {
        if let problem = EventValidation.validate(title: draft.title, dateAt: draft.dateAt, endDate: draft.endDate) {
            rejectWrite(problem)
            return false
        }
        return await performWrite { store in
            if let editing {
                _ = try await store.repo.update(
                    // Evento de rutina: sin fin (RN-4), la clave se omite. Si no: se envía siempre
                    // (valor o null explícito para borrarlo, RN-3).
                    UpdateEventRequest(
                        id: editing.id, title: draft.title, date_at: draft.dateAt, alarm: draft.alarm,
                        person_ids: draft.personIds, end_date: draft.endDate,
                        sendEndDate: editing.routine_id == nil
                    ),
                    timezone: store.timezone
                )
            } else {
                _ = try await store.repo.create(CreateEventRequest(
                    calendar_id: draft.calendarId, title: draft.title, date_at: draft.dateAt,
                    alarm: draft.alarm, person_ids: draft.personIds, end_date: draft.endDate
                ))
            }
            await store.load()
        }
    }

    public func setAlarm(_ event: EventEntry, alarm: Int?) async {
        await performWrite { store in
            _ = try await store.repo.setAlarm(SetEventAlarmRequest(event_id: event.id, alarm: alarm), timezone: store.timezone)
            await store.load()
        }
    }

    public func delete(_ event: EventEntry) async {
        await performWrite { store in
            _ = try await store.repo.delete(id: event.id, timezone: store.timezone)
            await store.load()
        }
    }

    private func report(_ error: Error) {
        errorMessage = (error as? APIError)?.userMessage ?? error.localizedDescription
    }
}

/// Borrador del formulario de evento.
public struct EventDraft: Equatable, Sendable {
    public var calendarId: Int
    public var title: String
    public var dateAt: String
    public var alarm: Int?
    public var personIds: [Int]
    /// Último día (`YYYY-MM-DD`, inclusive); `nil` = evento de un solo día.
    public var endDate: String?

    public init(calendarId: Int, title: String, dateAt: String, alarm: Int?, personIds: [Int], endDate: String? = nil) {
        self.calendarId = calendarId
        self.title = title
        self.dateAt = dateAt
        self.alarm = alarm
        self.personIds = personIds
        self.endDate = endDate
    }
}
