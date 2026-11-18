import XCTest
@testable import ControlKit

/// Registro con invitación y sesión automática (change permisos-edicion-registro-sesion): con
/// «Confirm email» desactivado la app entra sola; con confirmación activa intenta el login y, si no
/// puede, pide iniciar sesión con los datos cargados. «Email confirmation is pending» no es final.
final class RegistroSesionTests: XCTestCase {
    private let pending = #"{"error":"Email confirmation is pending"}"#
    private let sessionJSON = #"{"id":2,"name":"Nuevo","email":"nuevo@homita.example","token":"jwt-2","refresh_token":"rt-2"}"#

    private func makeAuth() throws -> (AuthService, SessionStore) {
        let session = SessionStore(store: InMemoryTokenStore())
        let client = APIClient(
            baseURL: URL(string: "https://test.supabase.co/functions/v1/api")!,
            session: StubURLProtocol.session(),
            tokenProvider: { [weak session] in session?.accessToken }
        )
        return (AuthService(client: client, session: session, config: try makeTestConfig(),
                            http: StubURLProtocol.session()), session)
    }

    private func register(_ auth: AuthService, code: String? = "abc23456") async throws -> RegistrationOutcome {
        try await auth.register(name: "Nuevo", email: "nuevo@homita.example", password: "secreto12", invitationCode: code)
    }

    private var paths: [String] {
        StubURLProtocol.requests.compactMap { $0.url?.path.split(separator: "/").suffix(2).joined(separator: "/") }
    }

    func testRegisterWithSessionSignsInAndKeepsRefreshToken() async throws {
        StubURLProtocol.reset { _ in StubURLProtocol.Stub(status: 201, json: self.sessionJSON) }
        let (auth, session) = try makeAuth()
        let outcome = try await register(auth)
        XCTAssertEqual(outcome, .signedIn)
        XCTAssertEqual(session.accessToken, "jwt-2")
        XCTAssertEqual(session.refreshToken, "rt-2")
        XCTAssertEqual(paths, ["user/create"], "sin login extra si ya hay sesión")
    }

    func testPendingConfirmationFallsBackToLogin() async throws {
        StubURLProtocol.reset { request in
            if request.url?.path.hasSuffix("/user/create") == true {
                return StubURLProtocol.Stub(status: 400, json: self.pending)
            }
            return StubURLProtocol.Stub(json: self.sessionJSON)
        }
        let (auth, session) = try makeAuth()
        let outcome = try await register(auth)
        XCTAssertEqual(outcome, .signedIn)
        XCTAssertEqual(session.accessToken, "jwt-2")
        XCTAssertEqual(paths, ["user/create", "user/auth"])
        // El login usa el mismo email y contraseña del alta.
        let login = try XCTUnwrap(StubURLProtocol.requests.last)
        XCTAssertEqual(String(data: try XCTUnwrap(login.capturedBody), encoding: .utf8),
                       #"{"email":"nuevo@homita.example","password":"secreto12"}"#)
    }

    func testPendingConfirmationWithFailingLoginNeedsLogin() async throws {
        StubURLProtocol.reset { request in
            if request.url?.path.hasSuffix("/user/create") == true {
                return StubURLProtocol.Stub(status: 400, json: self.pending)
            }
            return StubURLProtocol.Stub(status: 401, json: #"{"error":"Invalid credentials"}"#)
        }
        let (auth, session) = try makeAuth()
        let outcome = try await register(auth)
        XCTAssertEqual(outcome, .needsLogin)
        XCTAssertNil(session.accessToken, "sin sesión hasta que la persona inicie sesión")
        XCTAssertTrue(RegistrationOutcome.needsLoginNotice.contains("inicia sesión"))
    }

    func testOtherRegisterErrorsStillThrow() async throws {
        StubURLProtocol.reset { _ in StubURLProtocol.Stub(status: 400, json: #"{"error":"Email already exists"}"#) }
        let (auth, _) = try makeAuth()
        do {
            _ = try await register(auth)
            XCTFail("debía fallar")
        } catch let error as APIError {
            XCTAssertEqual(error, .http(status: 400, message: "Email already exists"))
        }
        XCTAssertEqual(paths, ["user/create"], "un error distinto no intenta login")
    }

    func testConfirmationPendingDetection() {
        XCTAssertTrue(RegistrationOutcome.isConfirmationPending(.http(status: 400, message: "Email confirmation is pending")))
        XCTAssertFalse(RegistrationOutcome.isConfirmationPending(.http(status: 500, message: "Email confirmation is pending")))
        XCTAssertFalse(RegistrationOutcome.isConfirmationPending(.http(status: 400, message: "Email already exists")))
        XCTAssertFalse(RegistrationOutcome.isConfirmationPending(.network("x")))
    }

    func testPendingInvitationSurvivesUntilAccepted() {
        let context = HomeContextStore(store: InMemoryTokenStore())
        context.pendingInvitationCode = "ABC23456"
        XCTAssertEqual(context.pendingInvitationCode, "ABC23456")
        context.clear()
        XCTAssertNil(context.pendingInvitationCode, "cerrar sesión descarta el código pendiente")
    }
}
