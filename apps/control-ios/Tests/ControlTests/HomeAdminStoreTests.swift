import XCTest
@testable import ControlKit

private final class Box: @unchecked Sendable {
    var active: String? = "2"
    var reloads = 0
}

final class HomeAdminStoreTests: XCTestCase {
    private func repo(_ handler: @escaping (URLRequest) -> StubURLProtocol.Stub = ContractFixtures.response) -> HomeRepository {
        StubURLProtocol.reset(handler)
        return HomeRepository(client: makeTestClient())
    }

    private func forbidden(_ request: URLRequest) -> StubURLProtocol.Stub {
        StubURLProtocol.Stub(status: 403, json: #"{"error":"Not Allowed"}"#)
    }

    private func method(_ m: String, in requests: [URLRequest]) -> Bool {
        requests.contains { $0.httpMethod == m }
    }

    // MARK: Settings

    func testSettingsLoadAndSaveOmitsUnchangedTimezone() async throws {
        let box = Box()
        let store = HomeSettingsStore(repo: repo(), homeId: 2, activeHomeId: { box.active }, reloadHome: { box.reloads += 1 })
        XCTAssertEqual(store.state, .idle)
        await store.load()
        XCTAssertEqual(store.state, .loaded)
        XCTAssertEqual(store.detail?.timezone, "Europe/Madrid")
        let ok = await store.save(name: " Nueva ", timezone: "Europe/Madrid")
        XCTAssertTrue(ok)
        let sent = try XCTUnwrap(StubURLProtocol.requests.last)
        XCTAssertEqual(sent.httpMethod, "PATCH")
        XCTAssertEqual(String(data: try XCTUnwrap(sent.capturedBody), encoding: .utf8), #"{"id":2,"name":"Nueva"}"#)
        XCTAssertEqual(box.reloads, 1)
        _ = await store.save(name: "Nueva", timezone: "Europe/Paris")
        let body = String(data: try XCTUnwrap(StubURLProtocol.requests.last?.capturedBody), encoding: .utf8)
        XCTAssertEqual(body, #"{"id":2,"name":"Nueva","timezone":"Europe\/Paris"}"#)
    }

    func testSettingsValidation() async {
        XCTAssertNotNil(HomeSettingsStore.validate(name: "  ", timezone: "Europe/Paris"))
        XCTAssertNotNil(HomeSettingsStore.validate(name: String(repeating: "a", count: 51), timezone: "Europe/Paris"))
        XCTAssertNil(HomeSettingsStore.validate(name: String(repeating: "a", count: 50), timezone: "Europe/Paris"))
        XCTAssertNotNil(HomeSettingsStore.validate(name: "ok", timezone: "Mars/Olympus"))
        XCTAssertNil(HomeSettingsStore.validate(name: "ok", timezone: "UTC", current: "UTC"))
        let box = Box()
        let store = HomeSettingsStore(repo: repo(), homeId: 2, activeHomeId: { box.active })
        let ok = await store.save(name: "", timezone: "Europe/Paris")
        XCTAssertFalse(ok)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertTrue(StubURLProtocol.requests.isEmpty)
    }

    func testSettings403ShowsAdminMessage() async {
        let box = Box()
        let store = HomeSettingsStore(repo: repo(forbidden), homeId: 2, activeHomeId: { box.active })
        let ok = await store.save(name: "Casa", timezone: "Europe/Paris")
        XCTAssertFalse(ok)
        XCTAssertEqual(store.errorMessage, "Solo un administrador puede realizar esta acción")
        await store.load()
        XCTAssertEqual(store.state, .failed("Solo un administrador puede realizar esta acción"))
    }

    func testSettingsDoesNotWriteWhenActiveHomeChanged() async {
        let box = Box()
        let store = HomeSettingsStore(repo: repo(), homeId: 2, activeHomeId: { box.active })
        box.active = "9"
        await store.load()
        XCTAssertNil(store.detail)
        let ok = await store.save(name: "Casa", timezone: "Europe/Paris")
        XCTAssertFalse(ok)
        XCTAssertFalse(method("PATCH", in: StubURLProtocol.requests))
    }

    // MARK: Membership

    private func membershipStore(_ box: Box, caller: Int = 1, repo r: HomeRepository? = nil) -> MembershipStore {
        MembershipStore(repo: r ?? repo(), homeId: 2, callerAppUserId: caller,
                        activeHomeId: { box.active }, reloadHome: { box.reloads += 1 })
    }

    func testMembershipLoad() async {
        let store = membershipStore(Box())
        await store.load()
        XCTAssertEqual(store.state, .loaded)
        XCTAssertEqual(store.items.count, 2)
    }

    func testTransferReloadsHomeContext() async {
        let box = Box()
        let store = membershipStore(box)
        await store.load()
        await store.transfer(to: store.items[1])
        XCTAssertEqual(box.reloads, 1)
        XCTAssertTrue(StubURLProtocol.requests.contains { $0.httpMethod == "POST" })
        XCTAssertNil(store.errorMessage)
    }

    func testTransferToSelfBlocked() async {
        let box = Box()
        let store = membershipStore(box)
        await store.load()
        await store.transfer(to: store.items[0])
        XCTAssertNotNil(store.errorMessage)
        XCTAssertEqual(box.reloads, 0)
        XCTAssertFalse(method("POST", in: StubURLProtocol.requests))
    }

    func testLeaveReloadsAndOtherRemoveDoesNot() async {
        let box = Box()
        let store = membershipStore(box)
        await store.load()
        await store.remove(store.items[1])
        XCTAssertEqual(box.reloads, 0)
        await store.remove(store.items[0])
        XCTAssertEqual(box.reloads, 1)
    }

    func testLeave403ShownAndNoReload() async {
        let box = Box()
        let store = membershipStore(box)
        await store.load()
        let item = store.items[0]
        StubURLProtocol.reset(forbidden)
        await store.remove(item)
        XCTAssertEqual(store.errorMessage, "No se puede completar la acción: el hogar debe conservar al menos un administrador")
        XCTAssertNotEqual(store.errorMessage, "Solo un administrador puede realizar esta acción")
        XCTAssertEqual(box.reloads, 0)
    }

    func testChangeOwnRoleReloads() async {
        let box = Box()
        let store = membershipStore(box)
        await store.load()
        await store.changeRole(store.items[0], to: "member")
        XCTAssertEqual(box.reloads, 1)
        await store.changeRole(store.items[1], to: "admin")
        XCTAssertEqual(box.reloads, 1)
    }

    func testMembershipNoWriteWhenActiveHomeChanged() async {
        let box = Box()
        let store = membershipStore(box)
        await store.load()
        box.active = "9"
        await store.remove(store.items[1])
        XCTAssertFalse(method("DELETE", in: StubURLProtocol.requests))
    }

    func testLeaveLastHomeFallsToNoHome() async throws {
        let tokens = InMemoryTokenStore()
        let context = HomeContextStore(store: tokens)
        let client = APIClient(
            baseURL: URL(string: "https://test.supabase.co/functions/v1/api")!,
            session: StubURLProtocol.session(), tokenProvider: { "tok" },
            homeIdProvider: { [weak context] in context?.activeHomeId }
        )
        let homes = HomeRepository(client: client)
        StubURLProtocol.reset { request in
            let path = request.url?.path ?? ""
            if request.httpMethod == "GET", path.hasSuffix("/api/home") {
                return StubURLProtocol.Stub(json: StubURLProtocol.currentHomes)
            }
            return ContractFixtures.response(for: request)
        }
        StubURLProtocol.currentHomes = ContractFixtures.homeList
        await context.load(using: homes)
        XCTAssertEqual(context.activeHomeId, "2")
        let store = MembershipStore(repo: homes, homeId: 2, callerAppUserId: 1,
                                    activeHomeId: { context.activeHomeId },
                                    reloadHome: { await context.load(using: homes) })
        await store.load()
        StubURLProtocol.currentHomes = ContractFixtures.homeListEmpty
        await store.remove(store.items[0])
        XCTAssertEqual(context.state, .noHome)
    }

    // MARK: Permissions

    func testPermissionStoreSavesFullSortedSet() async throws {
        let box = Box()
        let store = PermissionStore(repo: repo(), homeId: 2, activeHomeId: { box.active })
        await store.load()
        let item = try XCTUnwrap(store.response?.memberships.last)
        var draft = PermissionDraft(permissions: item.permissions)
        draft.toggle("task.read")
        let ok = await store.save(item: item, draft: draft)
        XCTAssertTrue(ok)
        let patch = try XCTUnwrap(StubURLProtocol.requests.first { $0.httpMethod == "PATCH" })
        XCTAssertEqual(String(data: try XCTUnwrap(patch.capturedBody), encoding: .utf8),
                       #"{"home_id":2,"membership_id":8,"permissions":["calendar.read","task.read"]}"#)
    }

    func testPermissionStoreRefusesNonEditable() async throws {
        let box = Box()
        let store = PermissionStore(repo: repo(), homeId: 2, activeHomeId: { box.active })
        await store.load()
        let admin = try XCTUnwrap(store.response?.memberships.first)
        let ok = await store.save(item: admin, draft: PermissionDraft(permissions: admin.permissions))
        XCTAssertFalse(ok)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertFalse(method("PATCH", in: StubURLProtocol.requests))
    }

    func testPermissionStore403() async {
        let box = Box()
        let store = PermissionStore(repo: repo(forbidden), homeId: 2, activeHomeId: { box.active })
        await store.load()
        XCTAssertEqual(store.state, .failed("Solo un administrador puede realizar esta acción"))
    }

    // MARK: Audit

    func testAuditLoadAndLoadMore() async throws {
        let box = Box()
        let store = AuditStore(repo: repo(), homeId: 2, limit: 2, activeHomeId: { box.active })
        await store.load()
        XCTAssertEqual(store.items.map(\.id), [12, 11])
        XCTAssertTrue(store.hasMore)
        await store.loadMore()
        let sent = try XCTUnwrap(StubURLProtocol.requests.last)
        XCTAssertTrue(sent.capturedQuery.contains { $0.0 == "before_id" && $0.1 == "11" })
        XCTAssertEqual(store.items.map(\.id), [12, 11])
    }

    func testAuditEndsWhenShortPage() async {
        let box = Box()
        let store = AuditStore(repo: repo(), homeId: 2, limit: 50, activeHomeId: { box.active })
        await store.load()
        XCTAssertFalse(store.hasMore)
    }

    // MARK: Members

    private func ana(linked: Bool = true, kind: String = "adult") -> HomeMember {
        HomeMember(id: 1, homeId: 2, kind: kind, name: "Ana", color: "#FF0000", status: "active", linked: linked)
    }

    func testMembersLoad() async {
        let box = Box()
        let store = HomeMembersStore(repo: repo(), homeId: 2, activeHomeId: { box.active })
        XCTAssertEqual(store.state, .idle)
        await store.load()
        XCTAssertEqual(store.state, .loaded)
        XCTAssertEqual(store.items.count, 1)
    }

    func testMembersLoadError() async {
        let box = Box()
        let store = HomeMembersStore(repo: repo(forbidden), homeId: 2, activeHomeId: { box.active })
        await store.load()
        XCTAssertEqual(store.state, .failed("Solo un administrador puede realizar esta acción"))
    }

    func testMembersInactiveHomeIgnoresResult() async {
        let box = Box()
        box.active = nil
        let store = HomeMembersStore(repo: repo(), homeId: 2, activeHomeId: { box.active })
        await store.load()
        XCTAssertTrue(store.items.isEmpty)
        let ok = await store.create(kind: .adult, name: "Luz", color: "#000000")
        XCTAssertFalse(ok)
        XCTAssertFalse(method("POST", in: StubURLProtocol.requests))
    }

    func testMembersCreateReloadsList() async {
        let box = Box()
        let store = HomeMembersStore(repo: repo(), homeId: 2, activeHomeId: { box.active })
        let ok = await store.create(kind: .child, name: " Luz ", color: "#00FF00")
        XCTAssertTrue(ok)
        XCTAssertEqual(StubURLProtocol.requests.map { $0.httpMethod ?? "" }, ["POST", "GET"])
        XCTAssertEqual(store.state, .loaded)
    }

    func testMembersCreateInvalidDoesNotCallServer() async {
        let box = Box()
        let store = HomeMembersStore(repo: repo(), homeId: 2, activeHomeId: { box.active })
        let ok = await store.create(kind: .child, name: "  ", color: "#00FF00")
        XCTAssertFalse(ok)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertTrue(StubURLProtocol.requests.isEmpty)
    }

    func testMembersUpdateReloadsAndReloadsHomeOnlyForOwnRow() async {
        let box = Box()
        let other = HomeMembersStore(repo: repo(), homeId: 2, activeHomeId: { box.active },
                                     isOwnRow: { _ in false }, onOwnRowChanged: { box.reloads += 1 })
        var ok = await other.update(ana(), kind: .child, status: .active, name: "Ana", color: "#FF0000")
        XCTAssertTrue(ok)
        XCTAssertEqual(StubURLProtocol.requests.map { $0.httpMethod ?? "" }, ["PATCH", "GET"])
        XCTAssertEqual(box.reloads, 0)
        let own = HomeMembersStore(repo: repo(), homeId: 2, activeHomeId: { box.active },
                                   isOwnRow: { _ in true }, onOwnRowChanged: { box.reloads += 1 })
        ok = await own.update(ana(), kind: .child, status: .active, name: "Ana", color: "#FF0000")
        XCTAssertTrue(ok)
        XCTAssertEqual(box.reloads, 1)
        // sin cambio de kind (solo estado) no recarga el contexto
        _ = await own.update(ana(), kind: .adult, status: .inactive, name: "Ana", color: "#FF0000")
        XCTAssertEqual(box.reloads, 1)
    }

    func testMembersUpdateNoChangesSendsNothingAndPetLinkedBlocked() async {
        let box = Box()
        let store = HomeMembersStore(repo: repo(), homeId: 2, activeHomeId: { box.active })
        let same = await store.update(ana(), kind: .adult, status: .active, name: "Ana", color: "#FF0000")
        XCTAssertTrue(same)
        XCTAssertTrue(StubURLProtocol.requests.isEmpty)
        let pet = await store.update(ana(linked: true), kind: .pet, status: .active, name: "Ana", color: "#FF0000")
        XCTAssertFalse(pet)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertTrue(StubURLProtocol.requests.isEmpty)
    }

    func testMembersUpdate403ShowsMessage() async {
        let box = Box()
        let store = HomeMembersStore(repo: repo(forbidden), homeId: 2, activeHomeId: { box.active })
        let ok = await store.update(ana(), kind: .child, status: .active, name: "Ana", color: "#FF0000")
        XCTAssertFalse(ok)
        XCTAssertEqual(store.errorMessage, "Solo un administrador puede realizar esta acción")
    }

    func testMembersUpdateNameOnlyKeepsUnknownKindStatusAndNilColor() async throws {
        let box = Box()
        let store = HomeMembersStore(repo: repo(), homeId: 2, activeHomeId: { box.active })
        let m = HomeMember(id: 1, homeId: 2, kind: "robot", name: "Ana", color: nil, status: "paused", linked: false)
        let ok = await store.update(m, kind: nil, status: nil, name: "Bea", color: nil)
        XCTAssertTrue(ok)
        let sent = try XCTUnwrap(StubURLProtocol.requests.first)
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(sent.capturedBody)) as? [String: Any])
        XCTAssertEqual(Set(obj.keys), ["id", "name"])
    }
}
