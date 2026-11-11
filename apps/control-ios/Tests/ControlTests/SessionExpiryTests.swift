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
}
