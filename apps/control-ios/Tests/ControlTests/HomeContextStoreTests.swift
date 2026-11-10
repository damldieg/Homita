import XCTest
@testable import ControlKit

final class HomeContextStoreTests: XCTestCase {
    private let key = "active_home_id"

    private func makeSUT(persisted: String? = nil) throws -> (HomeContextStore, InMemoryTokenStore, HomeRepository) {
        let tokens = InMemoryTokenStore()
        if let persisted { try tokens.set(persisted, forKey: key) }
        let store = HomeContextStore(store: tokens)
        var client: APIClient!
        client = APIClient(
            baseURL: URL(string: "https://test.supabase.co/functions/v1/api")!,
            session: StubURLProtocol.session(),
            tokenProvider: { "tok" },
            homeIdProvider: { [weak store] in store?.activeHomeId }
        )
        return (store, tokens, HomeRepository(client: client))
    }

    private func stubList(_ json: String, delay: TimeInterval = 0) {
        StubURLProtocol.reset { _ in StubURLProtocol.Stub(json: json, delay: delay) }
    }

    func testDefaultHomeWins() async throws {
        let (store, tokens, repo) = try makeSUT()
        stubList(ContractFixtures.homeList)
        await store.load(using: repo)
        guard case .ready(let home) = store.state else { return XCTFail("estado \(store.state)") }
        XCTAssertEqual(home.homeId, 2)
        XCTAssertEqual(store.activeHomeId, "2")
        XCTAssertEqual(try tokens.get(key), "2")
    }

    func testValidPersistedWinsOverDefault() async throws {
        let (store, tokens, repo) = try makeSUT(persisted: "1")
        stubList(ContractFixtures.homeList)
        await store.load(using: repo)
        XCTAssertEqual(store.activeHomeId, "1")
        XCTAssertEqual(try tokens.get(key), "1")
    }

    func testInvalidPersistedFallsBackToDefault() async throws {
        let (store, tokens, repo) = try makeSUT(persisted: "99")
        stubList(ContractFixtures.homeList)
        await store.load(using: repo)
        XCTAssertEqual(store.activeHomeId, "2")
        XCTAssertEqual(try tokens.get(key), "2")
    }

    func testNoDefaultPicksFirst() async throws {
        let (store, _, repo) = try makeSUT()
        stubList("[\(ContractFixtures.homeItem1)]")
        await store.load(using: repo)
        XCTAssertEqual(store.activeHomeId, "1")
    }

    func testHttpErrorFails() async throws {
        let (store, _, repo) = try makeSUT(persisted: "1")
        StubURLProtocol.reset { _ in StubURLProtocol.Stub(status: 500, json: #"{"error":"Boom"}"#) }
        await store.load(using: repo)
        XCTAssertEqual(store.state, .failed("Boom"))
        XCTAssertNil(store.activeHomeId)
    }

    func testEmptyListIsNoHomeAndClearsKey() async throws {
        let (store, tokens, repo) = try makeSUT(persisted: "1")
        stubList(ContractFixtures.homeListEmpty)
        await store.load(using: repo)
        XCTAssertEqual(store.state, .noHome)
        XCTAssertNil(store.activeHomeId)
        XCTAssertNil(try tokens.get(key))
        let sent = StubURLProtocol.requests
        XCTAssertEqual(sent.count, 1)
        XCTAssertNil(sent[0].value(forHTTPHeaderField: "X-Home-Id"))
    }

    func testCreateActivatesHomeAndLaterCallsCarryHeader() async throws {
        let (store, tokens, repo) = try makeSUT()
        var created = false
        StubURLProtocol.reset { request in
            let path = request.url?.path ?? ""
            if request.httpMethod == "POST", path.hasSuffix("/home/create") {
                created = true
                return StubURLProtocol.Stub(status: 201, json: ContractFixtures.homeDetail)
            }
            if path.hasSuffix("/api/home") {
                return StubURLProtocol.Stub(json: created
                    ? #"[{"home_id":3,"name":"Nuevo","role":"admin","is_default":true,"is_personal":false}]"#
                    : "[]")
            }
            return StubURLProtocol.Stub(json: ContractFixtures.homeDetail)
        }
        await store.load(using: repo)
        XCTAssertEqual(store.state, .noHome)
        let error = await store.create(name: "Nuevo", using: repo)
        XCTAssertNil(error)
        XCTAssertEqual(store.activeHomeId, "3")
        XCTAssertEqual(try tokens.get(key), "3")
        _ = try await repo.client.send(APIRequest(method: .get, path: "home/detail"), as: HomeDetail.self)
        XCTAssertEqual(StubURLProtocol.requests.last?.value(forHTTPHeaderField: "X-Home-Id"), "3")
        // create y las dos listas no llevan cabecera
        for request in StubURLProtocol.requests.dropLast() {
            XCTAssertNil(request.value(forHTTPHeaderField: "X-Home-Id"))
        }
    }

    func testCreateFailureReturnsMessageAndKeepsState() async throws {
        let (store, _, repo) = try makeSUT()
        StubURLProtocol.reset { request in
            request.httpMethod == "POST"
                ? StubURLProtocol.Stub(status: 400, json: #"{"error":"Name is required"}"#)
                : StubURLProtocol.Stub(json: "[]")
        }
        await store.load(using: repo)
        let error = await store.create(name: "x", using: repo)
        XCTAssertEqual(error, "Name is required")
        XCTAssertEqual(store.state, .noHome)
    }

    func testCreateOkThenListFailsGoesFailedAndReconcilesOnRetry() async throws {
        let (store, tokens, repo) = try makeSUT()
        var created = false
        var listFails = false
        StubURLProtocol.reset { request in
            let path = request.url?.path ?? ""
            if request.httpMethod == "POST", path.hasSuffix("/home/create") {
                created = true
                listFails = true
                return StubURLProtocol.Stub(status: 201, json: ContractFixtures.homeDetail)
            }
            if listFails {
                listFails = false
                return StubURLProtocol.Stub(status: 500, json: #"{"error":"Boom"}"#)
            }
            return StubURLProtocol.Stub(json: created
                ? #"[{"home_id":3,"name":"Nuevo","role":"admin","is_default":true,"is_personal":false}]"#
                : "[]")
        }
        await store.load(using: repo)
        XCTAssertEqual(store.state, .noHome)
        await store.create(name: "Nuevo", using: repo)
        // No queda en .noHome (formulario activo): pasa a .failed, sin hogar activo sin validar.
        XCTAssertEqual(store.state, .failed("Boom"))
        XCTAssertNil(store.activeHomeId)
        let posts = { StubURLProtocol.requests.filter { $0.httpMethod == "POST" }.count }
        XCTAssertEqual(posts(), 1)
        // Reintentar = load: reconcilia con el hogar ya creado, sin segundo POST.
        await store.load(using: repo)
        XCTAssertEqual(store.activeHomeId, "3")
        XCTAssertEqual(try tokens.get(key), "3")
        XCTAssertEqual(posts(), 1)
    }

    func testClearDiscardsInFlightLoad() async throws {
        let (store, tokens, repo) = try makeSUT()
        stubList(ContractFixtures.homeList, delay: 0.3)
        let task = Task { await store.load(using: repo) }
        try await Task.sleep(nanoseconds: 100_000_000)
        store.clear()
        await task.value
        XCTAssertEqual(store.state, .unresolved)
        XCTAssertNil(store.activeHomeId)
        XCTAssertNil(try tokens.get(key))
    }
}
