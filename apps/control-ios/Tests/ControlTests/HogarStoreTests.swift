import XCTest
@testable import ControlKit

private final class ActiveBox: @unchecked Sendable {
    var active: String? = "2"
}

final class HogarStoreTests: XCTestCase {
    private func makeRepo(box: ActiveBox, _ handler: @escaping (URLRequest) -> StubURLProtocol.Stub = ContractFixtures.response) -> HomeRepository {
        StubURLProtocol.reset(handler)
        let client = APIClient(
            baseURL: URL(string: "https://test.supabase.co/functions/v1/api")!,
            session: StubURLProtocol.session(),
            tokenProvider: { "test-access" },
            homeIdProvider: { box.active }
        )
        return HomeRepository(client: client)
    }

    func testLoadSendsHomeHeaderAndComposesRows() async {
        let box = ActiveBox()
        let store = HogarStore(repo: makeRepo(box: box), homeId: 2, homeRole: "admin", callerAppUserId: 1,
                               activeHomeId: { box.active })
        await store.load()
        XCTAssertEqual(store.state, .loaded)
        let requests = StubURLProtocol.requests
        let paths = requests.compactMap { $0.url?.path }.map { $0.components(separatedBy: "/").last ?? "" }
        XCTAssertTrue(paths.contains("member"))
        XCTAssertTrue(paths.contains("permission"))
        XCTAssertTrue(requests.allSatisfy { $0.value(forHTTPHeaderField: "X-Home-Id") == "2" })
        XCTAssertTrue(requests.allSatisfy { ($0.url?.query ?? "").contains("home_id=2") })
        XCTAssertEqual(store.rows.filter(\.isMe).map(\.name), ["Ana"])
    }

    func testCanInviteForAdminAndMemberWithPermission() async {
        let box = ActiveBox()
        let admin = HogarStore(repo: makeRepo(box: box), homeId: 2, homeRole: "member", callerAppUserId: 1,
                               activeHomeId: { box.active })
        await admin.load()
        XCTAssertEqual(admin.callerRole, "admin")
        XCTAssertTrue(admin.canInvite)

        let plain = HogarStore(repo: makeRepo(box: box), homeId: 2, homeRole: "member", callerAppUserId: 9,
                               activeHomeId: { box.active })
        await plain.load()
        XCTAssertFalse(plain.canInvite)

        let json = #"{"catalog":[],"defaults":[],"memberships":[{"membership_id":8,"app_user_id":9,"name":"Beto","email":"b@x.es","role":"member","kind":"adult","editable":true,"permissions":["home.invite"]}]}"#
        let allowed = HogarStore(
            repo: makeRepo(box: box) { request in
                request.url?.path.hasSuffix("/permission") == true
                    ? StubURLProtocol.Stub(json: json) : ContractFixtures.response(for: request)
            },
            homeId: 2, homeRole: "member", callerAppUserId: 9, activeHomeId: { box.active }
        )
        await allowed.load()
        XCTAssertTrue(allowed.canInvite)
    }

    func testResponseForInactiveHomeDoesNotOverwriteState() async {
        let box = ActiveBox()
        let store = HogarStore(repo: makeRepo(box: box) { request in
            box.active = "3"
            return ContractFixtures.response(for: request)
        }, homeId: 2, homeRole: "admin", callerAppUserId: 1, activeHomeId: { box.active })
        await store.load()
        XCTAssertNotEqual(store.state, .loaded)
        XCTAssertTrue(store.rows.isEmpty)
        XCTAssertFalse(store.canInvite)

        let failing = HogarStore(repo: makeRepo(box: box) { _ in
            box.active = "3"
            return StubURLProtocol.Stub(status: 404, json: #"{"error":"Not Found"}"#)
        }, homeId: 2, homeRole: "admin", callerAppUserId: 1, activeHomeId: { box.active })
        await failing.load()
        if case .failed = failing.state { XCTFail("un 404 de otro hogar no debe fijar .failed") }
    }

    func testFailureShowsFailedState() async {
        let box = ActiveBox()
        let store = HogarStore(repo: makeRepo(box: box) { _ in
            StubURLProtocol.Stub(status: 500, json: #"{"error":"boom"}"#)
        }, homeId: 2, homeRole: "admin", callerAppUserId: 1, activeHomeId: { box.active })
        await store.load()
        if case .failed = store.state {} else { XCTFail("debería ser .failed") }
    }
}
