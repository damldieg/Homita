import Foundation

/// Refresco de sesión (GoTrue). Implementado por `AuthService`; el `APIClient` lo llama una vez
/// ante un 401 y reintenta la petición.
public protocol TokenRefreshing: AnyObject {
    func refreshSession() async throws
}

/// Cliente HTTP del contrato: URLSession + async/await, sin dependencias. Mapea 401 → refresh
/// una vez → reintento; si el refresh falla → `sessionExpired` (logout local en la UI).
public final class APIClient {
    public let baseURL: URL
    private let session: URLSession
    private let tokenProvider: () -> String?
    private let homeIdProvider: () -> String?
    public weak var refresher: (any TokenRefreshing)?
    /// Se llama cuando la sesión caduca (refresh fallido o sin refresher). Lo usa `AppServices`
    /// para cerrar sesión local y volver a Welcome (C3). Puede llamarse desde cualquier hilo.
    public var onSessionExpired: (@Sendable () -> Void)?

    public init(baseURL: URL, session: URLSession = .shared, tokenProvider: @escaping () -> String?, homeIdProvider: @escaping () -> String? = { nil }) {
        self.baseURL = baseURL
        self.session = session
        self.tokenProvider = tokenProvider
        self.homeIdProvider = homeIdProvider
    }

    /// Codifica un body JSON (claves snake_case literales, orden estable).
    public func encode<T: Encodable>(_ value: T) throws -> Data {
        try JSONCoding.encoder().encode(value)
    }

    public func send(_ request: APIRequest) async throws -> Data {
        try await perform(request, allowRefresh: true)
    }

    public func send<T: Decodable>(_ request: APIRequest, as type: T.Type) async throws -> T {
        let data = try await send(request)
        do {
            return try JSONCoding.decoder().decode(T.self, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    /// Petición con body `Encodable` (nil no se envía).
    public func request<T: Encodable>(method: HTTPMethod, path: String, query: [URLQueryItem] = [], body: T?, isPublic: Bool = false) throws -> APIRequest {
        let data = try body.map { try encode($0) }
        return APIRequest(method: method, path: path, query: query, body: data, isPublic: isPublic)
    }

    /// Avisa de la caducidad y devuelve el error para lanzarlo.
    private func expireSession() -> APIError {
        onSessionExpired?()
        return .sessionExpired
    }

    private func perform(_ request: APIRequest, allowRefresh: Bool) async throws -> Data {
        let urlRequest = try RequestBuilder.urlRequest(baseURL: baseURL, apiRequest: request, accessToken: tokenProvider(), homeId: homeIdProvider())
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            throw APIError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw APIError.network("Respuesta sin HTTPURLResponse")
        }
        if http.statusCode == 401, !request.isPublic {
            guard allowRefresh, let refresher else { throw expireSession() }
            do {
                try await refresher.refreshSession()
            } catch {
                throw expireSession()
            }
            return try await perform(request, allowRefresh: false)
        }
        guard (200...299).contains(http.statusCode) else {
            let envelope = try? JSONCoding.decoder().decode(ErrorEnvelope.self, from: data)
            throw APIError.http(status: http.statusCode, message: envelope?.error ?? "HTTP \(http.statusCode)")
        }
        return data
    }
}
