import XCTest
@testable import ControlKit

final class HomeAdminRepositoryTests: XCTestCase {
    private func makeRepo(_ handler: @escaping (URLRequest) -> StubURLProtocol.Stub = ContractFixtures.response) -> HomeRepository {
        StubURLProtocol.reset(handler)
        var client: APIClient!
        client = APIClient(
            baseURL: URL(string: "https://test.supabase.co/functions/v1/api")!,
            session: StubURLProtocol.session(),
            tokenProvider: { "tok" },
            homeIdProvider: { "2" }
        )
        return HomeRepository(client: client)
    }

    private func last() throws -> URLRequest { try XCTUnwrap(StubURLProtocol.requests.last) }
    private func body(_ r: URLRequest) throws -> String { String(data: try XCTUnwrap(r.capturedBody), encoding: .utf8) ?? "" }
    private func query(_ r: URLRequest) -> [String] { r.capturedQuery.map { "\($0.0)=\($0.1 ?? "")" } }

    func testDetail() async throws {
        let d = try await makeRepo().detail(id: 2)
        let r = try last()
        XCTAssertEqual(r.httpMethod, "GET")
        XCTAssertTrue(r.url?.path.hasSuffix("/api/home/detail") == true)
        XCTAssertEqual(query(r), ["id=2"])
        XCTAssertEqual(r.value(forHTTPHeaderField: "X-Home-Id"), "2")
        XCTAssertEqual(d.timezone, "Europe/Madrid")
    }

    func testUpdateWithAndWithoutTimezone() async throws {
        let repo = makeRepo()
        _ = try await repo.update(id: 2, name: "Casa", timezone: "UTC")
        var r = try last()
        XCTAssertEqual(r.httpMethod, "PATCH")
        XCTAssertTrue(r.url?.path.hasSuffix("/api/home/update") == true)
        XCTAssertEqual(try body(r), #"{"id":2,"name":"Casa","timezone":"UTC"}"#)
        XCTAssertEqual(r.value(forHTTPHeaderField: "X-Home-Id"), "2")
        _ = try await repo.update(id: 2, name: "Casa", timezone: nil)
        r = try last()
        XCTAssertEqual(try body(r), #"{"id":2,"name":"Casa"}"#)
    }

    func testMemberships() async throws {
        let list = try await makeRepo().memberships(homeId: 2)
        let r = try last()
        XCTAssertEqual(r.httpMethod, "GET")
        XCTAssertTrue(r.url?.path.hasSuffix("/api/home/membership") == true)
        XCTAssertEqual(query(r), ["id=2"])
        XCTAssertEqual(r.value(forHTTPHeaderField: "X-Home-Id"), "2")
        XCTAssertEqual(list.count, 2)
    }

    func testChangeRole() async throws {
        _ = try await makeRepo().changeRole(homeId: 2, membershipId: 8, role: "admin")
        let r = try last()
        XCTAssertEqual(r.httpMethod, "PATCH")
        XCTAssertTrue(r.url?.path.hasSuffix("/api/home/membership/role") == true)
        XCTAssertEqual(try body(r), #"{"home_id":2,"membership_id":8,"role":"admin"}"#)
        XCTAssertEqual(r.value(forHTTPHeaderField: "X-Home-Id"), "2")
    }

    func testTransfer() async throws {
        let t = try await makeRepo().transfer(homeId: 2, toMembershipId: 8)
        let r = try last()
        XCTAssertEqual(r.httpMethod, "POST")
        XCTAssertTrue(r.url?.path.hasSuffix("/api/home/membership/transfer") == true)
        XCTAssertEqual(try body(r), #"{"home_id":2,"to_membership_id":8}"#)
        XCTAssertEqual(t.fromMembershipId, 7)
    }

    func testRemoveDeleteWithBody() async throws {
        try await makeRepo().remove(homeId: 2, membershipId: 8)
        let r = try last()
        XCTAssertEqual(r.httpMethod, "DELETE")
        XCTAssertTrue(r.url?.path.hasSuffix("/api/home/membership") == true)
        XCTAssertEqual(try body(r), #"{"home_id":2,"membership_id":8}"#)
        XCTAssertEqual(r.value(forHTTPHeaderField: "X-Home-Id"), "2")
    }

    func testMembers() async throws {
        let m = try await makeRepo().members(homeId: 2)
        let r = try last()
        XCTAssertEqual(r.httpMethod, "GET")
        XCTAssertTrue(r.url?.path.hasSuffix("/api/home/member") == true)
        XCTAssertEqual(query(r), ["home_id=2"])
        XCTAssertEqual(r.value(forHTTPHeaderField: "X-Home-Id"), "2")
        XCTAssertEqual(m.count, 1)
    }

    private func json(_ r: URLRequest) throws -> [String: String] {
        let obj = try JSONSerialization.jsonObject(with: try XCTUnwrap(r.capturedBody)) as? [String: Any]
        return try XCTUnwrap(obj).mapValues { "\($0)" }
    }

    func testMemberCreate() async throws {
        let m = try await makeRepo().createMember(homeId: 2, kind: .child, name: "Luz", color: "#00FF00")
        let r = try last()
        XCTAssertEqual(r.httpMethod, "POST")
        XCTAssertTrue(r.url?.path.hasSuffix("/api/home/member/create") == true)
        XCTAssertEqual(try json(r), ["home_id": "2", "kind": "child", "name": "Luz", "color": "#00FF00"])
        XCTAssertEqual(r.value(forHTTPHeaderField: "X-Home-Id"), "2")
        XCTAssertEqual(m.id, 1)
    }

    func testMemberUpdateSendsOnlyChangedFieldsWithoutHomeId() async throws {
        let m = try await makeRepo().updateMember(UpdateMemberBody(id: 1, status: .inactive, name: "Ana B"))
        let r = try last()
        XCTAssertEqual(r.httpMethod, "PATCH")
        XCTAssertTrue(r.url?.path.hasSuffix("/api/home/member/update") == true)
        XCTAssertEqual(try json(r), ["id": "1", "status": "inactive", "name": "Ana B"])
        XCTAssertEqual(r.value(forHTTPHeaderField: "X-Home-Id"), "2")
        XCTAssertEqual(m.name, "Ana")
    }

    func testMemberErrorsAsAPIError() async throws {
        let repo = makeRepo { _ in StubURLProtocol.Stub(status: 400, json: #"{"error":"Invalid member"}"#) }
        do {
            _ = try await repo.createMember(homeId: 2, kind: .pet, name: "x", color: "#000000")
            XCTFail("debía fallar")
        } catch let e as APIError {
            XCTAssertEqual(e, .http(status: 400, message: "Invalid member"))
        }
        let forbidden = makeRepo { _ in StubURLProtocol.Stub(status: 403, json: #"{"error":"Not Allowed"}"#) }
        do {
            _ = try await forbidden.updateMember(UpdateMemberBody(id: 1, name: "x"))
            XCTFail("debía fallar")
        } catch let e as APIError {
            XCTAssertTrue(e.isOwnerOnly)
        }
    }

    func testPermissionsGetAndPatch() async throws {
        let repo = makeRepo()
        let g = try await repo.permissions(homeId: 2)
        var r = try last()
        XCTAssertEqual(r.httpMethod, "GET")
        XCTAssertTrue(r.url?.path.hasSuffix("/api/home/permission") == true)
        XCTAssertEqual(query(r), ["home_id=2"])
        XCTAssertEqual(g.memberships.count, 2)
        _ = try await repo.setPermissions(homeId: 2, membershipId: 8, permissions: ["calendar.read", "task.read"])
        r = try last()
        XCTAssertEqual(r.httpMethod, "PATCH")
        XCTAssertEqual(try body(r), #"{"home_id":2,"membership_id":8,"permissions":["calendar.read","task.read"]}"#)
        XCTAssertEqual(r.value(forHTTPHeaderField: "X-Home-Id"), "2")
    }

    func testAuditQueryOptional() async throws {
        let repo = makeRepo()
        _ = try await repo.audit(homeId: 2)
        XCTAssertEqual(query(try last()), ["home_id=2"])
        _ = try await repo.audit(homeId: 2, limit: 50, beforeId: 11)
        let r = try last()
        XCTAssertEqual(r.httpMethod, "GET")
        XCTAssertTrue(r.url?.path.hasSuffix("/api/home/audit") == true)
        XCTAssertEqual(query(r), ["home_id=2", "limit=50", "before_id=11"])
        XCTAssertEqual(r.value(forHTTPHeaderField: "X-Home-Id"), "2")
    }

    func testErrorsAsAPIError() async throws {
        for (status, msg) in [(403, "Not Allowed"), (404, "Not Found"), (400, "Invalid timezone")] {
            let repo = makeRepo { _ in StubURLProtocol.Stub(status: status, json: #"{"error":"\#(msg)"}"#) }
            do {
                _ = try await repo.detail(id: 2)
                XCTFail("debía fallar")
            } catch let error as APIError {
                XCTAssertEqual(error, .http(status: status, message: msg))
            }
        }
    }
}
