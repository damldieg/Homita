import Foundation

/// Estado de Personas: CRUD; las compartidas (`editable=false`) son solo lectura.
@Observable
public final class PersonStore {
    public private(set) var persons: [PersonEntry] = []
    public private(set) var isLoading = false
    public var errorMessage: String?

    private let repo: PersonRepository

    public init(repo: PersonRepository) {
        self.repo = repo
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            persons = try await repo.index()
        } catch {
            report(error)
        }
    }

    @discardableResult
    public func save(name: String, color: String, editing: PersonEntry?) async -> Bool {
        do {
            if let editing {
                _ = try await repo.update(UpdatePersonRequest(id: editing.id, name: name, color: color))
            } else {
                _ = try await repo.create(CreatePersonRequest(name: name, color: color))
            }
            await load()
            return true
        } catch {
            report(error)
            return false
        }
    }

    public func delete(_ person: PersonEntry) async {
        do {
            _ = try await repo.delete(id: person.id)
            await load()
        } catch {
            report(error)
        }
    }

    private func report(_ error: Error) {
        errorMessage = (error as? APIError)?.userMessage ?? error.localizedDescription
    }
}
