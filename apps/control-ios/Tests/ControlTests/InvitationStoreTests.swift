import XCTest
@testable import ControlKit

private final class Box: @unchecked Sendable {
    var active: String? = "2"
}

final class InvitationStoreTests: XCTestCase {
    private func repo(_ handler: @escaping (URLRequest) -> StubURLProtocol.Stub = ContractFixtures.response) -> HomeRepository {
        StubURLProtocol.reset(handler)
        return HomeRepository(client: makeTestClient())
    }

    private func status(_ code: Int, _ message: String) -> (URLRequest) -> StubURLProtocol.Stub {
        { _ in StubURLProtocol.Stub(status: code, json: #"{"error":"\#(message)"}"#) }
    }

    private func luz() -> HomeMember {
        HomeMember(id: 3, homeId: 2, kind: "child", name: "Luz")
    }

    func testCreateKeepsCodeOnlyInCreatedCodeAndClears() async {
        let box = Box()
        let store = InvitationStore(repo: repo(), homeId: 2, activeHomeId: { box.active })
        let ok = await store.create(kind: .guest, member: nil, callerRole: "admin", email: "ana@ejemplo.com")
        XCTAssertTrue(ok)
        XCTAssertEqual(store.createdCode, ContractFixtures.invitationCode)
        XCTAssertEqual(StubURLProtocol.requests.map { $0.httpMethod ?? "" }, ["POST", "GET"])
        XCTAssertFalse(String(describing: store.items).contains(ContractFixtures.invitationCode))
        XCTAssertFalse(String(describing: store.state).contains(ContractFixtures.invitationCode))
        store.clearCode()
        XCTAssertNil(store.createdCode)
    }

    func testCreateWithMemberSendsMemberKind() async throws {
        let box = Box()
        let store = InvitationStore(repo: repo(), homeId: 2, activeHomeId: { box.active })
        let ok = await store.create(kind: nil, member: luz(), callerRole: "member", email: "ana@ejemplo.com")
        XCTAssertTrue(ok)
        let sent = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(String(data: try XCTUnwrap(sent.capturedBody), encoding: .utf8), #"{"email":"ana@ejemplo.com","home_id":2,"kind":"child","member_id":3}"#)
    }

    func testCreateAdultByNonAdminNeverCallsServer() async {
        let box = Box()
        let store = InvitationStore(repo: repo(), homeId: 2, activeHomeId: { box.active })
        let ok = await store.create(kind: .adult, member: nil, callerRole: "member", email: "ana@ejemplo.com")
        XCTAssertFalse(ok)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertNil(store.createdCode)
        XCTAssertTrue(StubURLProtocol.requests.isEmpty)
    }

    func testCreate403ShowsMessageAndNoCode() async {
        let box = Box()
        let store = InvitationStore(repo: repo(status(403, "Not Allowed")), homeId: 2, activeHomeId: { box.active })
        let ok = await store.create(kind: .guest, member: nil, callerRole: "member", email: "ana@ejemplo.com")
        XCTAssertFalse(ok)
        XCTAssertEqual(store.errorMessage, "No tienes permiso para crear esta invitación")
        XCTAssertNil(store.createdCode)
    }

    func testCreateInvalidMemberReloadsMembers() async {
        let box = Box()
        let store = InvitationStore(repo: repo(status(400, "Invalid member")), homeId: 2, activeHomeId: { box.active })
        let ok = await store.create(kind: nil, member: luz(), callerRole: "admin", email: "ana@ejemplo.com")
        XCTAssertFalse(ok)
        XCTAssertTrue(StubURLProtocol.requests.contains { $0.url?.path.hasSuffix("/home/member") == true })
        XCTAssertNotNil(store.errorMessage)
    }

    func testInactiveHomeMakesNoRequests() async {
        let box = Box()
        box.active = "9"
        let store = InvitationStore(repo: repo(), homeId: 2, activeHomeId: { box.active })
        await store.load()
        XCTAssertTrue(store.items.isEmpty)
        let ok = await store.create(kind: .guest, member: nil, callerRole: "admin", email: "ana@ejemplo.com")
        XCTAssertFalse(ok)
        await store.revoke(InvitationItem(id: 5, homeId: 2, kind: "guest", expiresAt: "2999-01-01 00:00:00", createdAt: "x"))
        XCTAssertTrue(StubURLProtocol.requests.filter { $0.httpMethod == "POST" }.isEmpty)
        XCTAssertNil(store.createdCode)
    }

    func testLoadHidesExpired() async {
        let box = Box()
        let expired = #"{"id":9,"home_id":2,"kind":"guest","status":"pending","expires_at":"2000-01-01 00:00:00","created_at":"2000-01-01 00:00:00"}"#
        let store = InvitationStore(repo: repo { _ in
            StubURLProtocol.Stub(status: 200, json: "[\(ContractFixtures.invitationItem),\(expired)]")
        }, homeId: 2, activeHomeId: { box.active })
        await store.load()
        XCTAssertEqual(store.state, .loaded)
        XCTAssertEqual(store.items.map(\.id), [5])
    }

    func testRevokeReloads() async throws {
        let box = Box()
        let store = InvitationStore(repo: repo(), homeId: 2, activeHomeId: { box.active })
        await store.load()
        await store.revoke(try XCTUnwrap(store.items.last))
        XCTAssertEqual(StubURLProtocol.requests.map { $0.httpMethod ?? "" }, ["GET", "POST", "GET"])
        XCTAssertNil(store.errorMessage)
    }

    func testRevoke404ShowsMessageAndReloads() async {
        let box = Box()
        let store = InvitationStore(repo: repo { request in
            request.httpMethod == "POST" ? StubURLProtocol.Stub(status: 404, json: #"{"error":"Not Found"}"#)
                : ContractFixtures.response(for: request)
        }, homeId: 2, activeHomeId: { box.active })
        await store.revoke(InvitationItem(id: 5, homeId: 2, kind: "guest", expiresAt: "2999-01-01 00:00:00", createdAt: "x"))
        XCTAssertEqual(store.errorMessage, "La invitación ya no existe: se usó, se revocó o caducó")
        XCTAssertEqual(StubURLProtocol.requests.map { $0.httpMethod ?? "" }, ["POST", "GET"])
    }

    func testCodeSurvivesReloadsUntilExplicitClear() async {
        let box = Box()
        let store = InvitationStore(repo: repo(), homeId: 2, activeHomeId: { box.active })
        _ = await store.create(kind: .guest, member: nil, callerRole: "admin", email: "ana@ejemplo.com")
        await store.load()
        await store.loadMembers()
        await store.revoke(InvitationItem(id: 5, homeId: 2, kind: "guest", expiresAt: "2999-01-01 00:00:00", createdAt: "x"))
        XCTAssertEqual(store.createdCode, ContractFixtures.invitationCode)
        store.clearCode()
        XCTAssertNil(store.createdCode)
    }

    func testAfterInvalidMemberNextCreateSendsNothingGeneric() async {
        let box = Box()
        let kid = #"{"id":3,"home_id":2,"kind":"child","name":"Luz","status":"active","linked":false}"#
        var linked = false
        let store = InvitationStore(repo: repo { request in
            let path = request.url?.path ?? ""
            if request.httpMethod == "POST", path.hasSuffix("/home/invitation/create") {
                linked = true
                return StubURLProtocol.Stub(status: 400, json: #"{"error":"Invalid member"}"#)
            }
            if path.hasSuffix("/home/member") {
                return StubURLProtocol.Stub(status: 200, json: linked ? "[]" : "[\(kid)]")
            }
            return ContractFixtures.response(for: request)
        }, homeId: 2, activeHomeId: { box.active })
        await store.loadMembers()
        var ok = await store.create(kind: .adult, memberId: 3, callerRole: "admin", email: "ana@ejemplo.com")
        XCTAssertFalse(ok)
        let posts = StubURLProtocol.requests.filter { $0.httpMethod == "POST" }.count
        XCTAssertEqual(posts, 1)
        ok = await store.create(kind: .adult, memberId: 3, callerRole: "admin", email: "ana@ejemplo.com")
        XCTAssertFalse(ok)
        XCTAssertEqual(StubURLProtocol.requests.filter { $0.httpMethod == "POST" }.count, 1)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertNil(store.createdCode)
    }
}
