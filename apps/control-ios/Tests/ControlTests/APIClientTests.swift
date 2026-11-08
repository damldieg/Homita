import XCTest
@testable import ControlKit

/// `APIClient`/`RequestBuilder` con `URLProtocol` stub: GET sin body, Bearer solo en rutas
/// protegidas, parseo de `{"error":…}`, 401 → refresh una vez → reintento, y mapeos 500
/// `Not Found` / 403 `Not Allowed`.
final class APIClientTests: XCTestCase {
    private final class MockRefresher: TokenRefreshing, @unchecked Sendable {
        var calls = 0
        var error: Error?
        func refreshSession() async throws {
            calls += 1
            if let error { throw error }
        }
    }

    private func lastRequest() throws -> URLRequest {
        try XCTUnwrap(StubURLProtocol.requests.last)
    }

    func testGetNeverCarriesBody() async throws {
        StubURLProtocol.reset(ContractFixtures.response)
        let client = makeTestClient()
        // Aunque se pase body (desviación 9), GET sale sin él y con los filtros en query.
        let request = try client.request(
            method: .get, path: "task",
            query: [URLQueryItem(name: "task_list_id", value: "2")],
            body: OrderTaskRequest(id: 7, position: 0)
        )
        _ = try await client.send(request, as: [TaskEntry].self)
        let sent = try lastRequest()
        XCTAssertEqual(sent.httpMethod, "GET")
        XCTAssertNil(sent.capturedBody)
        XCTAssertEqual(sent.capturedQuery.map(\.0), ["task_list_id"])
        XCTAssertEqual(sent.capturedQuery.map { $0.1 ?? "" }, ["2"])
    }

    func testBearerOnProtectedRoutesOnly() async throws {
        StubURLProtocol.reset(ContractFixtures.response)
        let client = makeTestClient(token: "test-access")
        _ = try await client.send(APIRequest(method: .get, path: "calendar"), as: [CalendarEntry].self)
        XCTAssertEqual(try lastRequest().value(forHTTPHeaderField: "Authorization"), "Bearer test-access")

        _ = try await client.send(APIRequest(method: .get, path: "config", isPublic: true), as: ConfigResponse.self)
        XCTAssertNil(try lastRequest().value(forHTTPHeaderField: "Authorization"))
    }

    func testErrorEnvelopeParsing() async throws {
        StubURLProtocol.reset { _ in
            StubURLProtocol.Stub(status: 400, json: #"{"error":"Name is required"}"#)
        }
        let client = makeTestClient()
        do {
            _ = try await client.send(APIRequest(method: .get, path: "calendar"), as: [CalendarEntry].self)
            XCTFail("debía fallar")
        } catch let error as APIError {
            XCTAssertEqual(error, .http(status: 400, message: "Name is required"))
            XCTAssertEqual(error.userMessage, "Name is required")
        }
    }

    func testUnauthorizedTriggersRefreshThenRetry() async throws {
        let refresher = MockRefresher()
        var calendarCalls = 0
        StubURLProtocol.reset { request in
            if request.url?.path.hasSuffix("/calendar") == true {
                calendarCalls += 1
                return calendarCalls == 1
                    ? StubURLProtocol.Stub(status: 401, json: #"{"error":"Unauthorized"}"#)
                    : StubURLProtocol.Stub(json: "[]")
            }
            return StubURLProtocol.Stub(status: 500, json: #"{"error":"Not Found"}"#)
        }
        let client = makeTestClient(refresher: refresher)
        _ = try await client.send(APIRequest(method: .get, path: "calendar"), as: [CalendarEntry].self)
        XCTAssertEqual(refresher.calls, 1)
        XCTAssertEqual(calendarCalls, 2)
    }

    func testFailedRefreshExpiresSession() async throws {
        let refresher = MockRefresher()
        refresher.error = APIError.sessionExpired
        StubURLProtocol.reset { _ in
            StubURLProtocol.Stub(status: 401, json: #"{"error":"Unauthorized"}"#)
        }
        let client = makeTestClient(refresher: refresher)
        do {
            _ = try await client.send(APIRequest(method: .get, path: "calendar"), as: [CalendarEntry].self)
            XCTFail("debía fallar")
        } catch let error as APIError {
            XCTAssertEqual(error, .sessionExpired)
        }
    }

    func testSecondUnauthorizedExpiresSession() async throws {
        // El reintento tras el refresh también devuelve 401: no hay segundo refresh (una sola vez).
        let refresher = MockRefresher()
        StubURLProtocol.reset { _ in
            StubURLProtocol.Stub(status: 401, json: #"{"error":"Unauthorized"}"#)
        }
        let client = makeTestClient(refresher: refresher)
        do {
            _ = try await client.send(APIRequest(method: .get, path: "calendar"), as: [CalendarEntry].self)
            XCTFail("debía fallar")
        } catch let error as APIError {
            XCTAssertEqual(error, .sessionExpired)
        }
        XCTAssertEqual(refresher.calls, 1)
    }

    func testPublicRouteUnauthorizedDoesNotRefresh() async throws {
        let refresher = MockRefresher()
        StubURLProtocol.reset { _ in
            StubURLProtocol.Stub(status: 401, json: #"{"error":"Invalid credentials"}"#)
        }
        let client = makeTestClient(refresher: refresher)
        do {
            _ = try await client.send(APIRequest(method: .post, path: "user/auth", isPublic: true), as: UserResponse.self)
            XCTFail("debía fallar")
        } catch let error as APIError {
            XCTAssertEqual(error, .http(status: 401, message: "Invalid credentials"))
            XCTAssertEqual(error.userMessage, "Email o contraseña incorrectos")
        }
        XCTAssertEqual(refresher.calls, 0)
    }

    func testNotFoundMapping() async throws {
        StubURLProtocol.reset { _ in
            StubURLProtocol.Stub(status: 500, json: #"{"error":"Not Found"}"#)
        }
        let client = makeTestClient()
        do {
            _ = try await client.send(APIRequest(method: .get, path: "calendar/detail"), as: CalendarEntry.self)
            XCTFail("debía fallar")
        } catch let error as APIError {
            XCTAssertTrue(error.isNotFound)
            XCTAssertFalse(error.isOwnerOnly)
            XCTAssertEqual(error.userMessage, "No encontrado")
        }
    }

    func testOwnerOnlyMapping() async throws {
        StubURLProtocol.reset { _ in
            StubURLProtocol.Stub(status: 403, json: #"{"error":"Not Allowed"}"#)
        }
        let client = makeTestClient()
        do {
            _ = try await client.send(APIRequest(method: .delete, path: "calendar/delete"), as: OkResponse.self)
            XCTFail("debía fallar")
        } catch let error as APIError {
            XCTAssertTrue(error.isOwnerOnly)
            XCTAssertFalse(error.isNotFound)
            XCTAssertEqual(error.userMessage, "Solo el propietario puede realizar esta acción")
        }
    }

    func testInvalidJSONIsDecodingError() async throws {
        StubURLProtocol.reset { _ in
            StubURLProtocol.Stub(json: "no es json")
        }
        let client = makeTestClient()
        do {
            _ = try await client.send(APIRequest(method: .get, path: "calendar"), as: [CalendarEntry].self)
            XCTFail("debía fallar")
        } catch let error as APIError {
            guard case .decoding = error else {
                return XCTFail("esperaba .decoding, llegó \(error)")
            }
        }
    }
}
