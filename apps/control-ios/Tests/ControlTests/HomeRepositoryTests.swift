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
}
