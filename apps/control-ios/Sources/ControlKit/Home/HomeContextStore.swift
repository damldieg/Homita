import Foundation

/// Estado de resolución del hogar activo.
public enum HomeContextState: Equatable, Sendable {
    /// Antes de cargar (sin sesión o tras `clear()`).
    case unresolved
    case loading
    case ready(HomeItem)
    /// El usuario no pertenece a ningún hogar.
    case noHome
    case failed(String)
}

/// Hogar activo de la sesión. Store propio (no vive en `SessionStore`), persistido en el mismo
/// `TokenStore` (Keychain) bajo la clave `active_home_id`.
///
/// Resolución en `load`: el id persistido si sigue en `GET home`; si no, el hogar con
/// `is_default`; si no, el primero. Un id no validado contra el servidor nunca se usa
/// (`activeHomeId` es nil salvo en `.ready`).
///
/// `sessionExpired` no limpia el hogar activo (no hay logout automático): se limpia solo con
/// `AppServices.signOut()`. `load` revalida siempre contra `GET home`, así que un id ajeno
/// residual cae al predeterminado. Si se añade logout automático debe pasar por
/// `AppServices.signOut()`.
@Observable
public final class HomeContextStore {
    public private(set) var state: HomeContextState = .unresolved

    private let store: TokenStore
    /// Se incrementa en `clear()`: un `load`/`create` en vuelo que termina después descarta su resultado.
    private var generation = 0

    static let key = "active_home_id"

    public init(store: TokenStore) {
        self.store = store
    }

    /// Id del hogar activo para `X-Home-Id`; nil salvo en `.ready`.
    public var activeHomeId: String? {
        if case .ready(let home) = state { return String(home.homeId) }
        return nil
    }

    /// Carga `GET home` y resuelve el hogar activo.
    public func load(using repository: HomeRepository) async {
        let token = generation
        state = .loading
        do {
            let homes = try await repository.list()
            guard token == generation else { return }
            resolve(homes)
        } catch {
            guard token == generation else { return }
            state = .failed(Self.message(error))
        }
    }

    /// `POST home/create`; el hogar creado pasa a ser el activo (se re-lista para tener el `HomeItem` completo).
    /// Si el POST falla devuelve el mensaje de error (el estado no cambia). Si el POST sale bien pero
    /// el `list()` posterior falla, el hogar ya existe en el servidor: el estado pasa a `.failed`
    /// (la UI muestra "Reintentar", que llama a `load` y reconcilia) para no ofrecer un segundo
    /// "Crear hogar" que duplicaría el hogar.
    @discardableResult
    public func create(name: String, using repository: HomeRepository) async -> String? {
        let token = generation
        let detail: HomeDetail
        do {
            detail = try await repository.create(name: name)
        } catch {
            return Self.message(error)
        }
        guard token == generation else { return nil }
        do {
            let homes = try await repository.list()
            guard token == generation else { return nil }
            if let created = homes.first(where: { $0.homeId == detail.id }) {
                activate(created)
            } else {
                resolve(homes)
            }
        } catch {
            guard token == generation else { return nil }
            state = .failed(Self.message(error))
        }
        return nil
    }

    /// Borra la clave persistida y el estado; invalida cargas en vuelo.
    public func clear() {
        generation += 1
        try? store.remove(Self.key)
        state = .unresolved
    }

    private func resolve(_ homes: [HomeItem]) {
        guard !homes.isEmpty else {
            try? store.remove(Self.key)
            state = .noHome
            return
        }
        let persisted = (try? store.get(Self.key)) ?? nil
        let chosen = persisted.flatMap { id in homes.first { String($0.homeId) == id } }
            ?? homes.first(where: \.isDefault)
            ?? homes[0]
        activate(chosen)
    }

    private func activate(_ home: HomeItem) {
        try? store.set(String(home.homeId), forKey: Self.key)
        state = .ready(home)
    }

    private static func message(_ error: Error) -> String {
        (error as? APIError)?.userMessage ?? error.localizedDescription
    }
}
