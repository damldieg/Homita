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

    /// AC4(e) y (c): la sesión caducada conserva la cola offline en disco (R1); `signOut()` la borra.
    func testExpiredSessionKeepsOutboxAndSignOutRemovesIt() async throws {
        let tokens = InMemoryTokenStore()
        let session = SessionStore(store: tokens)
        session.saveSession(user: try decodeFixture(UserResponse.self, ContractFixtures.user), accessToken: "a", refreshToken: "r")
        let services = await AppServices(config: try makeTestConfig(), session: session, tokenStore: tokens, http: StubURLProtocol.session())
        StubURLProtocol.reset(ContractFixtures.response)
        await services.homeContext.load(using: services.homes)
        let (userId, homeId, fileURL): (Int, String, URL) = try await MainActor.run {
            let outbox = try XCTUnwrap(services.activeOutbox)
            outbox.enqueue(PendingOp(homeId: outbox.homeId, kind: .completeTask(ref: .remote(7), listRef: .remote(2), completed: true)))
            return (outbox.userId, outbox.homeId, outbox.fileURL)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        // 401 en todo, también en el refresh de GoTrue: la sesión caduca.
        StubURLProtocol.reset { _ in StubURLProtocol.Stub(status: 401, json: #"{"error":"Unauthorized"}"#) }
        _ = try? await services.tasks.index(taskListId: nil)
        for _ in 0..<100 where session.session != nil {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertNil(session.session, "la sesión debía caducar")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path), "la cola se conserva al caducar la sesión")
        let pendingAfterExpiry = await MainActor.run {
            OutboxStore(userId: userId, homeId: homeId, directory: OutboxRegistry.shared.directory).pendingCount
        }
        XCTAssertEqual(pendingAfterExpiry, 1)

        await services.signOut()
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path), "signOut borra la cola")
        let pendingAfterSignOut = await MainActor.run { OutboxRegistry.shared.pendingCount(userId: userId) }
        XCTAssertEqual(pendingAfterSignOut, 0)
    }
}
