import XCTest
@testable import ControlKit

final class HomeRepositoryTests: XCTestCase {
    func testListShapeAndDecode() async throws {
        StubURLProtocol.reset(ContractFixtures.response)
        let homes = try await HomeRepository(client: makeTestClient()).list()
        let sent = try XCTUnwrap(StubURLProtocol.requests.last)
        XCTAssertEqual(sent.httpMethod, "GET")
        XCTAssertTrue(sent.url?.path.hasSuffix("/api/home") == true)
        XCTAssertNil(sent.value(forHTTPHeaderField: "X-Home-Id"))
        XCTAssertEqual(homes.map(\.homeId), [1, 2])
        XCTAssertEqual(homes[1], HomeItem(homeId: 2, name: "Familia", role: "adult", isDefault: true, isPersonal: false))
    }

    func testCreateShapeAndDecode() async throws {
        StubURLProtocol.reset(ContractFixtures.response)
        let detail = try await HomeRepository(client: makeTestClient()).create(name: "Nuevo")
        let sent = try XCTUnwrap(StubURLProtocol.requests.last)
        XCTAssertEqual(sent.httpMethod, "POST")
        XCTAssertTrue(sent.url?.path.hasSuffix("/api/home/create") == true)
        XCTAssertEqual(String(data: try XCTUnwrap(sent.capturedBody), encoding: .utf8), #"{"name":"Nuevo"}"#)
        XCTAssertNil(sent.value(forHTTPHeaderField: "X-Home-Id"))
        XCTAssertEqual(detail, HomeDetail(id: 3, name: "Nuevo"))
    }

    func testSetDefaultShapeAndDecode() async throws {
        StubURLProtocol.reset(ContractFixtures.response)
        let response = try await HomeRepository(client: makeTestClient()).setDefault(homeId: 2)
        let sent = try XCTUnwrap(StubURLProtocol.requests.last)
        XCTAssertEqual(sent.httpMethod, "PATCH")
        XCTAssertTrue(sent.url?.path.hasSuffix("/api/home/default") == true)
        XCTAssertEqual(String(data: try XCTUnwrap(sent.capturedBody), encoding: .utf8), #"{"home_id":2}"#)
        XCTAssertNil(sent.value(forHTTPHeaderField: "X-Home-Id"))
        XCTAssertEqual(response.defaultHomeId, 2)
    }

    private func clientWithActiveHome() -> APIClient {
        APIClient(
            baseURL: URL(string: "https://test.supabase.co/functions/v1/api")!,
            session: StubURLProtocol.session(),
            tokenProvider: { "tok" },
            homeIdProvider: { "7" }
        )
    }

    func testAcceptInvitationShape() async throws {
        StubURLProtocol.reset(ContractFixtures.response)
        _ = try await HomeRepository(client: makeTestClient()).acceptInvitation(code: "0123456789abcdef0123456789abcdef")
        let sent = try XCTUnwrap(StubURLProtocol.requests.last)
        XCTAssertEqual(sent.httpMethod, "POST")
        XCTAssertTrue(sent.url?.path.hasSuffix("/api/home/invitation/accept") == true)
        XCTAssertEqual(String(data: try XCTUnwrap(sent.capturedBody), encoding: .utf8),
                       #"{"code":"0123456789abcdef0123456789abcdef"}"#)
    }

    func testAcceptInvitationCarriesNoHeaderWithActiveHome() async throws {
        StubURLProtocol.reset(ContractFixtures.response)
        _ = try await HomeRepository(client: clientWithActiveHome()).acceptInvitation(code: "0123456789abcdef0123456789abcdef")
        XCTAssertNil(try XCTUnwrap(StubURLProtocol.requests.last).value(forHTTPHeaderField: "X-Home-Id"))
    }

    func testAcceptInvitationDecodeAndNotFound() async throws {
        StubURLProtocol.reset(ContractFixtures.response)
        let accepted = try await HomeRepository(client: makeTestClient()).acceptInvitation(code: "0123456789abcdef0123456789abcdef")
        XCTAssertEqual(accepted, InvitationAccepted(homeId: 2, membershipId: 40, memberId: 41, role: "member", kind: "guest"))
        StubURLProtocol.reset { _ in StubURLProtocol.Stub(status: 404, json: #"{"error":"Not Found"}"#) }
        do {
            _ = try await HomeRepository(client: makeTestClient()).acceptInvitation(code: "ffffffffffffffffffffffffffffffff")
            XCTFail("esperaba 404")
        } catch let error as APIError {
            XCTAssertEqual(error, .http(status: 404, message: "Not Found"))
        }
    }
}
