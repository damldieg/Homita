import Foundation

/// Estado de la lista de eventos: próximos/pasados con los filtros del contrato (`start_date`/
/// `end_date` = epoch local de 10 dígitos, `routine=false`, `timezone` IANA), como Android.
@Observable
public final class EventStore {
    public private(set) var upcoming: [EventEntry] = []
    public private(set) var past: [EventEntry] = []
    public private(set) var isLoading = false
    public var errorMessage: String?
    public var calendarFilterId: Int?
    public var searchText: String = ""

    private let repo: EventRepository
    private let clock: () -> LocalClock

    public init(repo: EventRepository, clock: @escaping () -> LocalClock = { LocalClock() }) {
        self.repo = repo
        self.clock = clock
    }

    private var timezone: String { TimeZone.current.identifier }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        let localNow = clock().localNowEpoch
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
            upcoming = next
        } catch {
            report(error)
        }
        filters.startDate = nil
        filters.endDate = localNow
        filters.orderMode = "DESC"
        do {
            past = try await repo.index(filters)
        } catch {
            report(error)
        }
    }

    /// Alta/edición. La validación de cliente exige título (v1 sin "modo IA").
    @discardableResult
    public func save(draft: EventDraft, editing: EventEntry?) async -> Bool {
        if let problem = EventValidation.validate(title: draft.title, dateAt: draft.dateAt) {
            errorMessage = problem
            return false
        }
        do {
            if let editing {
                _ = try await repo.update(
                    UpdateEventRequest(id: editing.id, title: draft.title, date_at: draft.dateAt, alarm: draft.alarm, person_ids: draft.personIds),
                    timezone: timezone
                )
            } else {
                _ = try await repo.create(CreateEventRequest(
                    calendar_id: draft.calendarId, title: draft.title, date_at: draft.dateAt,
                    alarm: draft.alarm, person_ids: draft.personIds
                ))
            }
            await load()
            return true
        } catch {
            report(error)
            return false
        }
    }

    public func setAlarm(_ event: EventEntry, alarm: Int?) async {
        do {
            _ = try await repo.setAlarm(SetEventAlarmRequest(event_id: event.id, alarm: alarm), timezone: timezone)
            await load()
        } catch {
            report(error)
        }
    }

    public func delete(_ event: EventEntry) async {
        do {
            _ = try await repo.delete(id: event.id, timezone: timezone)
            await load()
        } catch {
            report(error)
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

    public init(calendarId: Int, title: String, dateAt: String, alarm: Int?, personIds: [Int]) {
        self.calendarId = calendarId
        self.title = title
        self.dateAt = dateAt
        self.alarm = alarm
        self.personIds = personIds
    }
}
