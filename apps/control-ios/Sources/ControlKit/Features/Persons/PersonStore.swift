import Foundation

/// Estado de Personas: CRUD; las compartidas (`editable=false`) son solo lectura.
@Observable
public final class PersonStore: WriteFailureReporting {
    public private(set) var persons: [PersonEntry] = []
    public private(set) var isLoading = false
    /// Errores de lectura (alerta de la pantalla).
    public var errorMessage: String?
    /// Última escritura fallida (toast con «Reintentar»).
    public var writeFailure: WriteFailure?

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
        await performWrite { store in
            if let editing {
                _ = try await store.repo.update(UpdatePersonRequest(id: editing.id, name: name, color: color))
            } else {
                _ = try await store.repo.create(CreatePersonRequest(name: name, color: color))
            }
            await store.load()
        }
    }

    public func delete(_ person: PersonEntry) async {
        await performWrite { store in
            _ = try await store.repo.delete(id: person.id)
            await store.load()
        }
    }

    private func report(_ error: Error) {
        errorMessage = (error as? APIError)?.userMessage ?? error.localizedDescription
    }
}
