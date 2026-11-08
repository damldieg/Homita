import Foundation

/// Estado de Calendarios: CRUD, flags `widget`/`dashboard` propios e invitaciones por email.
@Observable
public final class CalendarStore {
    public private(set) var calendars: [CalendarEntry] = []
    public private(set) var members: [MemberEntry] = []
    public private(set) var isLoading = false
    public var errorMessage: String?

    private let repo: CalendarRepository

    public init(repo: CalendarRepository) {
        self.repo = repo
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
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
