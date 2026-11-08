import XCTest
@testable import ControlKit

/// `AuthService`: shapes de `user/auth` (con `refresh_token`), `user/create`, `user/update`,
/// `GET config` y refresco GoTrue (URL, headers y body exactos del contrato) con serialización
/// de refrescos concurrentes.
final class AuthServiceTests: XCTestCase {
    private func makeAuth() throws -> (AuthService, SessionStore, InMemoryTokenStore) {
        let tokens = InMemoryTokenStore()
        let session = SessionStore(store: tokens)
        // El Bearer sale del token de la sesión (como `AppServices`).
        let client = APIClient(
            baseURL: URL(string: "https://test.supabase.co/functions/v1/api")!,
            session: StubURLProtocol.session(),
            tokenProvider: { [weak session] in session?.accessToken }
        )
        let auth = AuthService(client: client, session: session, config: try makeTestConfig(), http: StubURLProtocol.session())
        return (auth, session, tokens)
    }

    private func lastRequest() throws -> URLRequest {
        try XCTUnwrap(StubURLProtocol.requests.last)
    }

    func testLoginRequestShape() async throws {
        StubURLProtocol.reset { _ in
            StubURLProtocol.Stub(json: """
            {"id":1,"name":"Demo","email":"demo@homita.example","token":"jwt-access",
             "refresh_token":"rt-1","created_at":"2026-11-08 09:30:00","updated_at":"2026-11-08 09:30:00"}
            """)
        }
        let (auth, _, _) = try makeAuth()
        try await auth.login(email: "demo@homita.example", password: "demo1234")

        let request = try lastRequest()
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path.hasSuffix("/user/auth"), true)
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization")) // ruta pública
        // Shape de `POST user/auth` (inventario, ruta 3) con claves ordenadas.
        XCTAssertEqual(String(data: try XCTUnwrap(request.capturedBody), encoding: .utf8),
                       #"{"email":"demo@homita.example","password":"demo1234"}"#)
    }

    func testLoginStoresTokensAndProfile() async throws {
        StubURLProtocol.reset { _ in
            StubURLProtocol.Stub(json: """
            {"id":1,"name":"Demo","email":"demo@homita.example","token":"jwt-access","refresh_token":"rt-1"}
            """)
        }
        let (auth, session, tokens) = try makeAuth()
        try await auth.login(email: "demo@homita.example", password: "demo1234")
        XCTAssertEqual(session.accessToken, "jwt-access")
        XCTAssertEqual(session.refreshToken, "rt-1")
        XCTAssertEqual(session.session?.email, "demo@homita.example")
        // Persistencia en el TokenStore (Keychain en la app): roundtrip con restore().
        let restored = SessionStore(store: tokens)
        restored.restore()
        XCTAssertEqual(restored.session, session.session)
        XCTAssertEqual(restored.accessToken, "jwt-access")
        XCTAssertEqual(restored.refreshToken, "rt-1")
    }

    func testLoginWithoutTokenIsDecodingError() async throws {
        StubURLProtocol.reset { _ in
            StubURLProtocol.Stub(json: #"{"id":1,"name":"Demo","email":"demo@homita.example"}"#)
        }
        let (auth, _, _) = try makeAuth()
        do {
            try await auth.login(email: "demo@homita.example", password: "demo1234")
            XCTFail("debía fallar")
        } catch let error as APIError {
            guard case .decoding = error else {
                return XCTFail("esperaba .decoding, llegó \(error)")
            }
        }
    }

    func testRegisterRequestShape() async throws {
        StubURLProtocol.reset { _ in
            StubURLProtocol.Stub(status: 201, json: #"{"id":2,"name":"Nuevo","email":"nuevo@homita.example","token":"jwt-2"}"#)
        }
        let (auth, _, _) = try makeAuth()
        try await auth.register(name: "Nuevo", email: "nuevo@homita.example", password: "secreto12")
        let request = try lastRequest()
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path.hasSuffix("/user/create"), true)
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        // Shape de `POST user/create` (inventario, ruta 2).
        XCTAssertEqual(String(data: try XCTUnwrap(request.capturedBody), encoding: .utf8),
                       #"{"email":"nuevo@homita.example","name":"Nuevo","password":"secreto12"}"#)
    }

    func testUpdateProfileRequestShape() async throws {
        StubURLProtocol.reset { _ in
            StubURLProtocol.Stub(json: #"{"id":1,"name":"Demo","email":"demo@homita.example"}"#)
        }
        let (auth, session, _) = try makeAuth()
        session.saveSession(
            user: try decodeFixture(UserResponse.self, #"{"id":1,"name":"Demo","email":"demo@homita.example"}"#),
            accessToken: "jwt-access", refreshToken: "rt-1"
        )
        _ = try await auth.updateProfile(name: "Demo", email: "demo@homita.example", password: "nueva1234")
        let request = try lastRequest()
        XCTAssertEqual(request.httpMethod, "PATCH")
        XCTAssertEqual(request.url?.path.hasSuffix("/user/update"), true)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer jwt-access")
        // Shape de `PATCH user/update` (inventario, ruta 4); sin password si no llega.
        XCTAssertEqual(String(data: try XCTUnwrap(request.capturedBody), encoding: .utf8),
                       #"{"email":"demo@homita.example","name":"Demo","password":"nueva1234"}"#)

        _ = try await auth.updateProfile(name: "Demo", email: "demo@homita.example", password: nil)
        XCTAssertEqual(String(data: try XCTUnwrap(lastRequest().capturedBody), encoding: .utf8),
                       #"{"email":"demo@homita.example","name":"Demo"}"#)
    }

    func testFetchConfigIsPublicAndGatesRegistration() async throws {
        StubURLProtocol.reset { _ in
            StubURLProtocol.Stub(json: #"{"allow_registration":true}"#)
        }
        let (auth, _, _) = try makeAuth()
        await auth.fetchConfig()
        XCTAssertTrue(auth.allowRegistration)
        let request = try lastRequest()
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.path.hasSuffix("/config"), true)
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }

    func testRefreshGrantRequestShape() async throws {
        StubURLProtocol.reset { _ in
            StubURLProtocol.Stub(json: #"{"access_token":"nuevo-access","refresh_token":"nuevo-refresh"}"#)
        }
        let (auth, session, _) = try makeAuth()
        session.saveSession(
            user: try decodeFixture(UserResponse.self, #"{"id":1,"name":"Demo","email":"demo@homita.example"}"#),
            accessToken: "jwt-access", refreshToken: "refresh-1"
        )
        try await auth.refreshSession()

        let request = try lastRequest()
        XCTAssertEqual(request.httpMethod, "POST")
        // GoTrue: POST {SUPABASE_URL}/auth/v1/token?grant_type=refresh_token (D-008 Q8).
        XCTAssertEqual(request.url?.path, "/auth/v1/token")
        XCTAssertEqual(request.url?.query, "grant_type=refresh_token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "apikey"), "anon-key-test")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(String(data: try XCTUnwrap(request.capturedBody), encoding: .utf8),
                       #"{"refresh_token":"refresh-1"}"#)
        // Rotación de tokens.
        XCTAssertEqual(session.accessToken, "nuevo-access")
        XCTAssertEqual(session.refreshToken, "nuevo-refresh")
    }

    func testRefreshKeepsTokenWhenResponseOmitsIt() async throws {
        StubURLProtocol.reset { _ in
            StubURLProtocol.Stub(json: #"{"access_token":"nuevo-access"}"#)
        }
        let (auth, session, _) = try makeAuth()
        session.saveSession(
            user: try decodeFixture(UserResponse.self, #"{"id":1,"name":"Demo","email":"demo@homita.example"}"#),
            accessToken: "jwt-access", refreshToken: "refresh-1"
        )
        try await auth.refreshSession()
        XCTAssertEqual(session.accessToken, "nuevo-access")
        XCTAssertEqual(session.refreshToken, "refresh-1")
    }

    func testRefreshWithoutRefreshTokenFails() async throws {
        StubURLProtocol.reset(ContractFixtures.response)
        let (auth, session, _) = try makeAuth()
        session.saveSession(
            user: try decodeFixture(UserResponse.self, #"{"id":1,"name":"Demo","email":"demo@homita.example"}"#),
            accessToken: "jwt-access", refreshToken: nil
        )
        do {
            try await auth.refreshSession()
            XCTFail("debía fallar")
        } catch let error as APIError {
            XCTAssertEqual(error, .sessionExpired)
        }
    }

    func testConcurrentRefreshesAreSerialized() async throws {
        // Un solo refresh en vuelo: dos llamadas concurrentes → una sola petición a GoTrue.
        StubURLProtocol.reset { request in
            if request.url?.path.hasSuffix("/auth/v1/token") == true {
                return StubURLProtocol.Stub(json: #"{"access_token":"nuevo-access","refresh_token":"nuevo-refresh"}"#, delay: 0.3)
            }
            return StubURLProtocol.Stub(json: "{}")
        }
        let (auth, session, _) = try makeAuth()
        session.saveSession(
            user: try decodeFixture(UserResponse.self, #"{"id":1,"name":"Demo","email":"demo@homita.example"}"#),
            accessToken: "jwt-access", refreshToken: "refresh-1"
        )
        async let first: Void = auth.refreshSession()
        async let second: Void = auth.refreshSession()
        try await first
        try await second

        let refreshCalls = StubURLProtocol.requests.filter { $0.url?.path.hasSuffix("/auth/v1/token") == true }
        XCTAssertEqual(refreshCalls.count, 1)
        XCTAssertEqual(session.accessToken, "nuevo-access")
    }
}
