import Foundation

/// Conexión OAuth de un cliente (p. ej. Claude) con la cuenta del usuario: `GET /auth/v1/user/oauth/grants`.
public struct ClaudeConnection: Equatable, Identifiable, Sendable, Decodable {
    public let clientId: String
    public let clientName: String
    public let scopes: [String]
    /// Fecha ISO 8601 tal como la devuelve Auth (con fracciones de segundo).
    public let grantedAt: String

    public var id: String { clientId }

    public init(clientId: String, clientName: String, scopes: [String], grantedAt: String) {
        self.clientId = clientId
        self.clientName = clientName
        self.scopes = scopes
        self.grantedAt = grantedAt
    }

    private struct Client: Decodable {
        let id: String
        let name: String?
    }

    private enum CodingKeys: String, CodingKey {
        case client, scopes
        case grantedAt = "granted_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let client = try c.decode(Client.self, forKey: .client)
        clientId = client.id
        clientName = client.name ?? ""
        scopes = try c.decodeIfPresent([String].self, forKey: .scopes) ?? []
        grantedAt = try c.decodeIfPresent(String.self, forKey: .grantedAt) ?? ""
    }

    /// Fecha de la autorización; nil si Auth no la manda o no se entiende.
    public var grantedDate: Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFraction.date(from: grantedAt) ?? ISO8601DateFormatter().date(from: grantedAt)
    }
}

/// Conexiones OAuth del usuario con Supabase Auth directo (GoTrue, sin pasar por `api`):
/// `GET {SUPABASE_URL}/auth/v1/user/oauth/grants` y `DELETE …/grants?client_id=<id>`, con el Bearer del
/// usuario. Revocar borra la sesión del cliente y sus refresh tokens: el token OAuth deja de valer al instante
/// (el MCP valida con `GET /auth/v1/user`). Ante un 401 refresca la sesión una vez y reintenta.
public final class ClaudeConnectionsRepository {
    private let config: AppConfig
    private let http: URLSession
    private let tokenProvider: () -> String?
    private weak var refresher: (any TokenRefreshing)?

    public init(config: AppConfig, http: URLSession = .shared, tokenProvider: @escaping () -> String?,
                refresher: (any TokenRefreshing)?) {
        self.config = config
        self.http = http
        self.tokenProvider = tokenProvider
        self.refresher = refresher
    }

    public func list() async throws -> [ClaudeConnection] {
        let data = try await perform(method: "GET", query: [])
        do {
            return try JSONCoding.decoder().decode([ClaudeConnection].self, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    /// Revoca la autorización del cliente (204).
    public func revoke(clientId: String) async throws {
        _ = try await perform(method: "DELETE", query: [URLQueryItem(name: "client_id", value: clientId)])
    }

    private func perform(method: String, query: [URLQueryItem], allowRefresh: Bool = true) async throws -> Data {
        guard let token = tokenProvider() else { throw APIError.sessionExpired }
        var components = URLComponents(url: config.supabaseURL, resolvingAgainstBaseURL: false)
        components?.path += "/auth/v1/user/oauth/grants"
        components?.queryItems = query.isEmpty ? nil : query
        guard let url = components?.url else { throw APIError.decoding("SUPABASE_URL inválida") }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await http.data(for: request)
        } catch {
            throw APIError.network(error.localizedDescription)
        }
        guard let status = (response as? HTTPURLResponse)?.statusCode else { throw APIError.network("Respuesta inválida") }
        if (200...299).contains(status) { return data }
        if status == 401 {
            guard allowRefresh, let refresher else { throw APIError.sessionExpired }
            try await refresher.refreshSession()
            return try await perform(method: method, query: query, allowRefresh: false)
        }
        throw APIError.http(status: status, message: Self.message(from: data))
    }

    /// GoTrue responde `{"code":…,"error_code":…,"msg":"…"}`.
    private static func message(from data: Data) -> String {
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        return (object?["msg"] as? String) ?? (object?["error"] as? String) ?? "Error"
    }
}
