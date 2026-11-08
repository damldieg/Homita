import Foundation

/// Cuerpo del refresco GoTrue (`POST {SUPABASE_URL}/auth/v1/token?grant_type=refresh_token`).
private struct RefreshRequest: Encodable {
    let refresh_token: String
}

/// Respuesta GoTrue (tolerante: `refresh_token` puede no venir y se conserva el actual).
private struct GoTrueTokenResponse: Decodable {
    let access_token: String
    let refresh_token: String?
}

/// Serializa el refresco de sesión: un solo `Task` en vuelo; los refrescos concurrentes esperan.
private actor RefreshCoordinator {
    private var inFlight: Task<Void, Error>?

    func serialized(_ operation: @escaping @Sendable () async throws -> Void) async throws {
        if let inFlight {
            try await inFlight.value
            return
        }
        let task = Task { try await operation() }
        inFlight = task
        defer { inFlight = nil }
        try await task.value
    }
}

/// Auth contra la Edge (`user/auth`, `user/create`, `user/update`, `GET config`) + refresco de
/// sesión vía GoTrue directo (sin SDK). Los refrescos se serializan: un solo `Task` en vuelo.
@Observable
public final class AuthService: TokenRefreshing {
    public private(set) var allowRegistration = false

    private let client: APIClient
    private let session: SessionStore
    private let config: AppConfig
    private let http: URLSession
    private let refreshCoordinator = RefreshCoordinator()

    public init(client: APIClient, session: SessionStore, config: AppConfig, http: URLSession = .shared) {
        self.client = client
        self.session = session
        self.config = config
        self.http = http
    }

    /// `GET config` (público): decide si la UI muestra "Registrarse" (prod: `allow_registration=false`).
    public func fetchConfig() async {
        let request = APIRequest(method: .get, path: "config", isPublic: true)
        if let config = try? await client.send(request, as: ConfigResponse.self) {
            allowRegistration = config.allowRegistration
        }
    }

    /// `POST user/auth` → `{id,name,email,token,refresh_token}` (la Edge añade `refresh_token`).
    public func login(email: String, password: String) async throws {
        let body = try client.encode(AuthRequest(email: email, password: password))
        let request = APIRequest(method: .post, path: "user/auth", body: body, isPublic: true)
        let user = try await client.send(request, as: UserResponse.self)
        try store(user: user)
    }

    /// `POST user/create` → 201 `{id,name,email,token,…}` (sin `refresh_token`).
    public func register(name: String, email: String, password: String) async throws {
        let body = try client.encode(RegisterRequest(name: name, email: email, password: password))
        let request = APIRequest(method: .post, path: "user/create", body: body, isPublic: true)
        let user = try await client.send(request, as: UserResponse.self)
        try store(user: user)
    }

    /// `PATCH user/update` → `{id,name,email,created_at,updated_at}` sin token (se conserva el actual).
    @discardableResult
    public func updateProfile(name: String, email: String, password: String?) async throws -> UserResponse {
        let body = try client.encode(UpdateProfileRequest(name: name, email: email, password: password))
        let request = APIRequest(method: .patch, path: "user/update", body: body)
        let user = try await client.send(request, as: UserResponse.self)
        session.updateProfile(name: user.name, email: user.email)
        return user
    }

    /// Refresco GoTrue (TokenRefreshing). Serializado: los refrescos concurrentes esperan al
    /// `Task` en vuelo. Si falla → `APIError.sessionExpired` → logout local en la UI.
    public func refreshSession() async throws {
        try await refreshCoordinator.serialized { [weak self] in
            guard let self else { throw APIError.sessionExpired }
            try await self.performRefresh()
        }
    }

    private func store(user: UserResponse) throws {
        guard let token = user.token, !token.isEmpty else {
            throw APIError.decoding("user/auth sin token")
        }
        session.saveSession(user: user, accessToken: token, refreshToken: user.refresh_token)
    }

    private func performRefresh() async throws {
        guard let refresh = session.refreshToken else {
            throw APIError.sessionExpired
        }
        var components = URLComponents(url: config.supabaseURL, resolvingAgainstBaseURL: false)
        components?.path += "/auth/v1/token"
        components?.queryItems = [URLQueryItem(name: "grant_type", value: "refresh_token")]
        guard let url = components?.url else {
            throw APIError.decoding("SUPABASE_URL inválida")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONCoding.encoder().encode(RefreshRequest(refresh_token: refresh))

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await http.data(for: request)
        } catch {
            throw APIError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIError.sessionExpired
        }
        guard let tokens = try? JSONCoding.decoder().decode(GoTrueTokenResponse.self, from: data) else {
            throw APIError.decoding("respuesta de refresco inválida")
        }
        session.updateTokens(access: tokens.access_token, refresh: tokens.refresh_token ?? refresh)
    }
}
