import Foundation

/// Estado de Ajustes › Claude: conexiones OAuth del usuario y revocación. Tras revocar recarga la lista.
@Observable
public final class ClaudeConnectionsStore {
    public private(set) var connections: [ClaudeConnection] = []
    public private(set) var state: HomeAdminLoadState = .idle
    public private(set) var revokingClientId: String?
    public var errorMessage: String?

    private let repo: ClaudeConnectionsRepository

    public init(repo: ClaudeConnectionsRepository) {
        self.repo = repo
    }

    public func load() async {
        state = .loading
        do {
            connections = try await repo.list()
            state = .loaded
        } catch {
            state = .failed(Self.message(error))
        }
    }

    /// Revoca la conexión; si sale bien desaparece de la lista y se recarga para reflejar el servidor.
    public func revoke(_ connection: ClaudeConnection) async {
        guard revokingClientId == nil else { return }
        revokingClientId = connection.clientId
        defer { revokingClientId = nil }
        do {
            try await repo.revoke(clientId: connection.clientId)
            connections.removeAll { $0.clientId == connection.clientId }
            await load()
        } catch {
            errorMessage = Self.message(error)
        }
    }

    static func message(_ error: Error) -> String {
        (error as? APIError)?.userMessage ?? error.localizedDescription
    }
}
