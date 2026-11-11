import XCTest
@testable import ControlKit

/// Regla de envío de `X-Home-Id`: solo rutas autenticadas `home/*`, salvo `home/create` y
/// `home/default`; `GET home`, rutas públicas y legacy no la llevan.
final class RequestBuilderTests: XCTestCase {
    private let base = URL(string: "https://test.supabase.co/functions/v1/api")!

    private func header(_ request: APIRequest, homeId: String? = "7", token: String? = "tok") throws -> String? {
        try RequestBuilder.urlRequest(baseURL: base, apiRequest: request, accessToken: token, homeId: homeId)
            .value(forHTTPHeaderField: "X-Home-Id")
    }

    func testHomeRouteCarriesHeader() throws {
        XCTAssertEqual(try header(APIRequest(method: .get, path: "home/detail")), "7")
        XCTAssertEqual(try header(APIRequest(method: .patch, path: "home/update", body: Data("{}".utf8))), "7")
    }

    func testExcludedHomeRoutesCarryNoHeader() throws {
        XCTAssertNil(try header(APIRequest(method: .get, path: "home")))
        XCTAssertNil(try header(APIRequest(method: .post, path: "home/create", body: Data("{}".utf8))))
        XCTAssertNil(try header(APIRequest(method: .patch, path: "home/default", body: Data("{}".utf8))))
    }

    func testInvitationAcceptCarriesNoHeaderEvenWithActiveHome() throws {
        // D-015: quien acepta aún no es miembro; el hogar lo fija el código
        XCTAssertNil(try header(APIRequest(method: .post, path: "home/invitation/accept", body: Data("{}".utf8))))
    }

    func testInvitationListCarriesHeader() throws {
        XCTAssertEqual(try header(APIRequest(method: .get, path: "home/invitation")), "7")
        XCTAssertEqual(try header(APIRequest(method: .post, path: "home/invitation/create", body: Data("{}".utf8))), "7")
    }

    func testPublicAndLegacyRoutesCarryNoHeader() throws {
        XCTAssertNil(try header(APIRequest(method: .get, path: "home/detail", isPublic: true)))
        XCTAssertNil(try header(APIRequest(method: .get, path: "task")))
        XCTAssertNil(try header(APIRequest(method: .get, path: "event")))
        XCTAssertNil(try header(APIRequest(method: .get, path: "calendar")))
    }

    func testNilOrEmptyHomeIdCarriesNoHeader() throws {
        XCTAssertNil(try header(APIRequest(method: .get, path: "home/detail"), homeId: nil))
        XCTAssertNil(try header(APIRequest(method: .get, path: "home/detail"), homeId: ""))
    }

    func testApiClientReadsProviderOnEveryAttemptIncludingRetryAfter401() async throws {
        final class Refresher: TokenRefreshing, @unchecked Sendable {
            let onRefresh: () -> Void
            init(onRefresh: @escaping () -> Void) { self.onRefresh = onRefresh }
            func refreshSession() async throws { onRefresh() }
        }
        var current = "5"
        var calls = 0
        StubURLProtocol.reset { _ in
            calls += 1
            return calls == 1
                ? StubURLProtocol.Stub(status: 401, json: #"{"error":"Unauthorized"}"#)
                : StubURLProtocol.Stub(json: ContractFixtures.homeDetail)
        }
        let client = APIClient(
            baseURL: base, session: StubURLProtocol.session(),
            tokenProvider: { "tok" }, homeIdProvider: { current }
        )
        let refresher = Refresher { current = "9" }
        client.refresher = refresher
        _ = try await client.send(APIRequest(method: .get, path: "home/detail"), as: HomeDetail.self)
        let sent = StubURLProtocol.requests
        XCTAssertEqual(sent.count, 2)
        XCTAssertEqual(sent[0].value(forHTTPHeaderField: "X-Home-Id"), "5")
        XCTAssertEqual(sent[1].value(forHTTPHeaderField: "X-Home-Id"), "9")
    }
}
