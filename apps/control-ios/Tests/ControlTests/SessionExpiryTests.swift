import XCTest
@testable import ControlKit

/// C3: si la sesión caduca (401 sin refresh posible), el cliente avisa una vez para cerrar sesión.
final class SessionExpiryTests: XCTestCase {
    private final class Flag: @unchecked Sendable { var count = 0 }
    private final class FailingRefresher: TokenRefreshing, @unchecked Sendable {
        func refreshSession() async throws { throw APIError.sessionExpired }
    }

    func testExpiredSessionNotifiesAndThrows() async {
        StubURLProtocol.reset { _ in StubURLProtocol.Stub(status: 401, json: #"{"error":"Unauthorized"}"#) }
        let flag = Flag()
        let client = makeTestClient(refresher: FailingRefresher())
        client.onSessionExpired = { flag.count += 1 }
        do {
            _ = try await client.send(APIRequest(method: .get, path: "task"))
            XCTFail("debía lanzar sessionExpired")
        } catch APIError.sessionExpired {
            XCTAssertEqual(flag.count, 1)
        } catch {
            XCTFail("error inesperado: \(error)")
        }
    }

    func testRequestWithoutRefresherAlsoNotifies() async {
        StubURLProtocol.reset { _ in StubURLProtocol.Stub(status: 401, json: #"{"error":"Unauthorized"}"#) }
        let flag = Flag()
        let client = makeTestClient(refresher: nil)
        client.onSessionExpired = { flag.count += 1 }
        do {
            _ = try await client.send(APIRequest(method: .get, path: "task"))
            XCTFail("debía lanzar sessionExpired")
        } catch APIError.sessionExpired {
            XCTAssertEqual(flag.count, 1)
        } catch {
            XCTFail("error inesperado: \(error)")
        }
    }

    /// Un fallo transitorio del refresh (red, 5xx) no caduca la sesión: el error se propaga.
    func testTransientRefreshFailureDoesNotExpireSession() async {
        final class TransientRefresher: TokenRefreshing, @unchecked Sendable {
            func refreshSession() async throws { throw APIError.network("timeout") }
        }
        StubURLProtocol.reset { _ in StubURLProtocol.Stub(status: 401, json: #"{"error":"Unauthorized"}"#) }
        let flag = Flag()
        let refresher = TransientRefresher()   // APIClient.refresher es weak: hay que retenerlo aquí
        let client = makeTestClient(refresher: refresher)
        client.onSessionExpired = { flag.count += 1 }
        do {
            _ = try await client.send(APIRequest(method: .get, path: "task"))
            XCTFail("debía propagar el error de red")
        } catch APIError.network {
            XCTAssertEqual(flag.count, 0, "un fallo transitorio no debe cerrar sesión")
        } catch {
            XCTFail("error inesperado: \(error)")
        }
    }
}
