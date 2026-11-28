import XCTest
@testable import ControlKit

/// Conexiones OAuth del usuario (Ajustes › Claude): forma de las peticiones a GoTrue, refresco ante 401,
/// errores y store (cargar, revocar, recargar).
final class ClaudeConnectionsTests: XCTestCase {
    private final class FakeRefresher: TokenRefreshing, @unchecked Sendable {
        var calls = 0
        var token: String
        init(token: String) { self.token = token }
        func refreshSession() async throws { calls += 1; token = "jwt-nuevo" }
    }

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        func increment() { lock.lock(); count += 1; lock.unlock() }
        var value: Int { lock.lock(); defer { lock.unlock() }; return count }
    }

    private static let grantsJSON = """
    [{"client":{"id":"c-1","name":"Claude"},"scopes":["openid","email"],"granted_at":"2026-11-28T16:07:30.555033Z"}]
    """

    private func makeRepo(refresher: FakeRefresher? = nil) throws -> (ClaudeConnectionsRepository, FakeRefresher) {
        let fake = refresher ?? FakeRefresher(token: "jwt-1")
        let repo = ClaudeConnectionsRepository(
            config: try makeTestConfig(), http: StubURLProtocol.session(),
            tokenProvider: { [fake] in fake.token }, refresher: fake)
        return (repo, fake)
    }

    func testListRequestShapeAndDecoding() async throws {
        StubURLProtocol.reset { _ in StubURLProtocol.Stub(json: Self.grantsJSON) }
        let (repo, fake) = try makeRepo()
        let list = try await repo.list()
        let request = try XCTUnwrap(StubURLProtocol.requests.last)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.path, "/auth/v1/user/oauth/grants")
        XCTAssertNil(request.url?.query)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer jwt-1")
        XCTAssertFalse(request.value(forHTTPHeaderField: "apikey")?.isEmpty ?? true)
        XCTAssertEqual(list, [ClaudeConnection(clientId: "c-1", clientName: "Claude", scopes: ["openid", "email"],
                                               grantedAt: "2026-11-28T16:07:30.555033Z")])
        XCTAssertNotNil(list.first?.grantedDate)
        XCTAssertEqual(fake.calls, 0)
    }

    func testRevokeRequestShape() async throws {
        StubURLProtocol.reset { _ in StubURLProtocol.Stub(status: 204, json: "") }
        let (repo, _) = try makeRepo()
        try await repo.revoke(clientId: "c-1")
        let request = try XCTUnwrap(StubURLProtocol.requests.last)
        XCTAssertEqual(request.httpMethod, "DELETE")
        XCTAssertEqual(request.url?.path, "/auth/v1/user/oauth/grants")
        XCTAssertEqual(request.url?.query, "client_id=c-1")
    }

    func testRefreshesOnceOn401AndRetries() async throws {
        StubURLProtocol.reset { request in
            request.value(forHTTPHeaderField: "Authorization") == "Bearer jwt-1"
                ? StubURLProtocol.Stub(status: 401, json: #"{"msg":"expired"}"#)
                : StubURLProtocol.Stub(json: Self.grantsJSON)
        }
        let (repo, fake) = try makeRepo()
        let list = try await repo.list()
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(fake.calls, 1)
        XCTAssertEqual(StubURLProtocol.requests.count, 2)
    }

    func testPersistent401ThrowsSessionExpired() async throws {
        StubURLProtocol.reset { _ in StubURLProtocol.Stub(status: 401, json: #"{"msg":"expired"}"#) }
        let (repo, fake) = try makeRepo()
        do {
            _ = try await repo.list()
            XCTFail("debía fallar")
        } catch let error as APIError {
            XCTAssertEqual(error, .sessionExpired)
        }
        XCTAssertEqual(fake.calls, 1)
    }

    func testSessionExpiredCallsHandlerBeforeThrowing() async throws {
        StubURLProtocol.reset { _ in StubURLProtocol.Stub(status: 401, json: #"{"msg":"expired"}"#) }
        let (repo, _) = try makeRepo()
        let called = Counter()
        repo.onSessionExpired = { called.increment() }
        do {
            _ = try await repo.list()
            XCTFail("debía fallar")
        } catch let error as APIError {
            XCTAssertEqual(error, .sessionExpired)
        }
        XCTAssertEqual(called.value, 1)
    }

    func testServerErrorKeepsGoTrueMessage() async throws {
        StubURLProtocol.reset { _ in StubURLProtocol.Stub(status: 500, json: #"{"code":500,"msg":"boom"}"#) }
        let (repo, _) = try makeRepo()
        do {
            _ = try await repo.list()
            XCTFail("debía fallar")
        } catch let error as APIError {
            XCTAssertEqual(error, .http(status: 500, message: "boom"))
        }
    }

    func testOfflineIsNetworkError() async throws {
        StubURLProtocol.reset { _ in .offline }
        let (repo, _) = try makeRepo()
        do {
            _ = try await repo.list()
            XCTFail("debía fallar")
        } catch let error as APIError {
            guard case .network = error else { return XCTFail("esperaba .network, llegó \(error)") }
        }
    }

    func testStoreLoadsAndRevokesThenReloads() async throws {
        var revoked = false
        StubURLProtocol.reset { request in
            if request.httpMethod == "DELETE" { revoked = true; return StubURLProtocol.Stub(status: 204, json: "") }
            return StubURLProtocol.Stub(json: revoked ? "[]" : Self.grantsJSON)
        }
        let (repo, _) = try makeRepo()
        let store = ClaudeConnectionsStore(repo: repo)
        await store.load()
        XCTAssertEqual(store.state, .loaded)
        XCTAssertEqual(store.connections.map(\.clientId), ["c-1"])
        await store.revoke(store.connections[0])
        XCTAssertTrue(store.connections.isEmpty)
        XCTAssertEqual(store.state, .loaded)
        XCTAssertNil(store.errorMessage)
        XCTAssertNil(store.revokingClientId)
    }

    func testStoreRevokeFailureKeepsListAndSetsError() async throws {
        StubURLProtocol.reset { request in
            request.httpMethod == "DELETE"
                ? StubURLProtocol.Stub(status: 500, json: #"{"msg":"boom"}"#)
                : StubURLProtocol.Stub(json: Self.grantsJSON)
        }
        let (repo, _) = try makeRepo()
        let store = ClaudeConnectionsStore(repo: repo)
        await store.load()
        await store.revoke(store.connections[0])
        XCTAssertEqual(store.connections.count, 1)
        XCTAssertNotNil(store.errorMessage)
    }

    func testStoreLoadFailureSetsFailedState() async throws {
        StubURLProtocol.reset { _ in .offline }
        let (repo, _) = try makeRepo()
        let store = ClaudeConnectionsStore(repo: repo)
        await store.load()
        guard case .failed = store.state else { return XCTFail("esperaba .failed") }
    }
}
