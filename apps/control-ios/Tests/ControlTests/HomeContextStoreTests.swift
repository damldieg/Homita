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

    func testAcceptInvitationActivatesJoinedHome() async throws {
        let (store, tokens, repo) = try makeSUT(persisted: "1")
        var joined = false
        StubURLProtocol.reset { request in
            let path = request.url?.path ?? ""
            if request.httpMethod == "POST", path.hasSuffix("/home/invitation/accept") {
                joined = true
                return StubURLProtocol.Stub(json: ContractFixtures.invitationAccepted)
            }
            return StubURLProtocol.Stub(json: joined ? ContractFixtures.homeList : "[\(ContractFixtures.homeItem1)]")
        }
        await store.load(using: repo)
        XCTAssertEqual(store.activeHomeId, "1")
        let error = await store.acceptInvitation(code: " 0123456789ABCDEF0123456789abcdef ", using: repo)
        XCTAssertNil(error)
        XCTAssertEqual(store.activeHomeId, "2")
        XCTAssertEqual(try tokens.get(key), "2")
        let accept = try XCTUnwrap(StubURLProtocol.requests.first { $0.httpMethod == "POST" })
        XCTAssertNil(accept.value(forHTTPHeaderField: "X-Home-Id"))
        XCTAssertEqual(String(data: try XCTUnwrap(accept.capturedBody), encoding: .utf8),
                       #"{"code":"0123456789abcdef0123456789abcdef"}"#)
    }

    func testAcceptInvitationNotFoundKeepsState() async throws {
        let (store, _, repo) = try makeSUT()
        StubURLProtocol.reset { request in
            request.httpMethod == "POST"
                ? StubURLProtocol.Stub(status: 404, json: #"{"error":"Not Found"}"#)
                : StubURLProtocol.Stub(json: "[]")
        }
        await store.load(using: repo)
        XCTAssertEqual(store.state, .noHome)
        let error = await store.acceptInvitation(code: "ffffffffffffffffffffffffffffffff", using: repo)
        XCTAssertEqual(error, "El código no es válido, ya se usó o ha caducado")
        XCTAssertEqual(store.state, .noHome)
        XCTAssertEqual(StubURLProtocol.requests.filter { $0.httpMethod == "GET" }.count, 1)
    }

    func testAcceptInvitationFromNoHomeActivatesHome() async throws {
        let (store, _, repo) = try makeSUT()
        var joined = false
        StubURLProtocol.reset { request in
            if request.httpMethod == "POST" {
                joined = true
                return StubURLProtocol.Stub(json: ContractFixtures.invitationAccepted)
            }
            return StubURLProtocol.Stub(json: joined ? "[\(ContractFixtures.homeItem2)]" : "[]")
        }
        await store.load(using: repo)
        XCTAssertEqual(store.state, .noHome)
        let error = await store.acceptInvitation(code: "0123456789abcdef0123456789abcdef", using: repo)
        XCTAssertNil(error)
        XCTAssertEqual(store.activeHomeId, "2")
    }

    /// R2-04: cerrar sesión no deja el código de invitación pendiente en memoria.
    func testClearResetsPendingInvitationCode() throws {
        let (store, _, _) = try makeSUT()
        store.pendingInvitationCode = "0123456789abcdef0123456789abcdef"
        store.clear()
        XCTAssertNil(store.pendingInvitationCode)
    }
}

final class HomeSwitcherTests: XCTestCase {
    private let key = "active_home_id"

    private func makeSUT(tokens: TokenStore = InMemoryTokenStore()) -> (HomeContextStore, TokenStore, HomeRepository) {
        let store = HomeContextStore(store: tokens)
        let client = APIClient(
            baseURL: URL(string: "https://test.supabase.co/functions/v1/api")!,
            session: StubURLProtocol.session(),
            tokenProvider: { "tok" },
            homeIdProvider: { [weak store] in store?.activeHomeId }
        )
        return (store, tokens, HomeRepository(client: client))
    }

    // Acceptance 1
    func testRowsListAllHomesWithRoleAndActiveMark() async throws {
        let (store, _, repo) = makeSUT()
        StubURLProtocol.reset { _ in StubURLProtocol.Stub(json: ContractFixtures.homeList) }
        await store.load(using: repo)
        let rows = HomeSwitcher.rows(homes: store.homes, activeHomeId: store.activeHomeId)
        XCTAssertEqual(rows.count, store.homes.count)
        XCTAssertEqual(rows.map(\.id), store.homes.map(\.homeId))
        XCTAssertEqual(rows.filter(\.isActive).map(\.id), [2])
        XCTAssertEqual(rows.map(\.roleLabel), store.homes.map { $0.role == "admin" ? "Administrador" : "Miembro" })
        XCTAssertEqual(HomeSwitcher.rows(homes: [], activeHomeId: nil), [])
    }

    // Acceptance 2 + 4
    func testSelectChangesActiveHomeAndHeaderWithoutWrites() async throws {
        let (store, tokens, repo) = makeSUT()
        StubURLProtocol.reset { _ in StubURLProtocol.Stub(json: ContractFixtures.homeList) }
        await store.load(using: repo)
        XCTAssertEqual(store.activeHomeId, "2")
        XCTAssertTrue(store.select(homeId: 1))
        XCTAssertEqual(store.activeHomeId, "1")
        XCTAssertEqual(try tokens.get(key), "1")
        XCTAssertFalse(store.select(homeId: 99))
        XCTAssertEqual(store.activeHomeId, "1")
        // Sin PATCH home/default ni otras escrituras durante load + select (requests reales, antes de resetear).
        let beforeSend = StubURLProtocol.requests
        XCTAssertEqual(beforeSend.count, 1)
        XCTAssertTrue(beforeSend.allSatisfy { $0.httpMethod == "GET" })
        XCTAssertFalse(beforeSend.contains { $0.url?.path.hasSuffix("/home/default") == true })
        StubURLProtocol.reset { _ in StubURLProtocol.Stub(json: ContractFixtures.homeDetail) }
        _ = try await repo.client.send(APIRequest(method: .get, path: "home/detail"), as: HomeDetail.self)
        XCTAssertEqual(StubURLProtocol.requests.last?.value(forHTTPHeaderField: "X-Home-Id"), "1")
    }

    // Acceptance 4 (todo el flujo load + select)
    func testNoDefaultPatchDuringLoadAndSelect() async throws {
        let (store, _, repo) = makeSUT()
        StubURLProtocol.reset { _ in StubURLProtocol.Stub(json: ContractFixtures.homeList) }
        await store.load(using: repo)
        store.select(homeId: 1)
        XCTAssertEqual(StubURLProtocol.requests.count, 1)
        XCTAssertFalse(StubURLProtocol.requests.contains { $0.httpMethod == "PATCH" })
    }

    // R1-02: select con un load en vuelo; el load no pisa la elección.
    func testSelectDuringInFlightLoadIsNotOverwritten() async throws {
        let (store, tokens, repo) = makeSUT()
        StubURLProtocol.reset { _ in StubURLProtocol.Stub(json: ContractFixtures.homeList) }
        await store.load(using: repo)
        XCTAssertEqual(store.activeHomeId, "2")
        StubURLProtocol.reset { _ in StubURLProtocol.Stub(json: ContractFixtures.homeList, delay: 0.3) }
        let task = Task { await store.load(using: repo) }
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(store.select(homeId: 1))
        await task.value
        XCTAssertEqual(store.activeHomeId, "1")
        XCTAssertEqual(try tokens.get(key), "1")
        XCTAssertEqual(StubURLProtocol.requests.count, 1)
        XCTAssertTrue(StubURLProtocol.requests.allSatisfy { $0.httpMethod == "GET" })
    }

    // R1-01: set que lanza; la selección sigue activa tras load y el error queda expuesto.
    func testPersistenceFailureKeepsSelectionAndExposesError() async throws {
        let tokens = FailingSetTokenStore()
        let (store, _, repo) = makeSUT(tokens: tokens)
        StubURLProtocol.reset { _ in StubURLProtocol.Stub(json: ContractFixtures.homeList) }
        await store.load(using: repo)
        XCTAssertNotNil(store.persistenceError) // el set del load ya falló
        XCTAssertTrue(store.select(homeId: 1))
        XCTAssertEqual(store.activeHomeId, "1")
        let message = try XCTUnwrap(store.persistenceError)
        XCTAssertTrue(message.contains("No se pudo guardar el hogar activo"))
        await store.load(using: repo)
        XCTAssertEqual(store.activeHomeId, "1", "un load posterior revirtió la elección")
        XCTAssertNotNil(store.persistenceError)
        store.clear()
        XCTAssertNil(store.persistenceError)
    }

    // Acceptance 3
    func testActiveHomeRestoredFromPersistenceOnRebuild() async throws {
        let tokens = InMemoryTokenStore()
        let (first, _, repo1) = makeSUT(tokens: tokens)
        StubURLProtocol.reset { _ in StubURLProtocol.Stub(json: ContractFixtures.homeList) }
        await first.load(using: repo1)
        first.select(homeId: 1)
        let (second, _, repo2) = makeSUT(tokens: tokens)
        await second.load(using: repo2)
        XCTAssertEqual(second.activeHomeId, "1")
    }

    func testClearEmptiesHomes() async throws {
        let (store, _, repo) = makeSUT()
        StubURLProtocol.reset { _ in StubURLProtocol.Stub(json: ContractFixtures.homeList) }
        await store.load(using: repo)
        store.clear()
        XCTAssertTrue(store.homes.isEmpty)
        XCTAssertFalse(store.select(homeId: 1))
    }
}

/// Diagnóstico 1.15c: la selección sobrevive a reconstruir el store (relanzar la app).
final class HomeActivePersistenceTests: XCTestCase {
    private func makeRepo(_ store: HomeContextStore) -> HomeRepository {
        HomeRepository(client: APIClient(
            baseURL: URL(string: "https://test.supabase.co/functions/v1/api")!,
            session: StubURLProtocol.session(),
            tokenProvider: { "tok" },
            homeIdProvider: { [weak store] in store?.activeHomeId }
        ))
    }

    private func assertSelectionSurvivesRelaunch(_ tokens: TokenStore, file: StaticString = #filePath, line: UInt = #line) async throws {
        StubURLProtocol.reset { _ in StubURLProtocol.Stub(json: ContractFixtures.homeList) }
        let first = HomeContextStore(store: tokens)
        await first.load(using: makeRepo(first))
        XCTAssertEqual(first.activeHomeId, "2", file: file, line: line) // predeterminado
        XCTAssertTrue(first.select(homeId: 1), file: file, line: line)
        // Lectura directa: el valor debe estar realmente en el store.
        XCTAssertEqual(try tokens.get("active_home_id"), "1", file: file, line: line)
        let second = HomeContextStore(store: tokens)
        await second.load(using: makeRepo(second))
        XCTAssertEqual(second.activeHomeId, "1", "el hogar elegido se perdió al reconstruir", file: file, line: line)
    }

    func testSelectionSurvivesRelaunchInMemory() async throws {
        try await assertSelectionSurvivesRelaunch(InMemoryTokenStore())
    }

    func testSelectionSurvivesRelaunchRealKeychain() async throws {
        let tokens = KeychainTokenStore(service: "com.lito.planify.control.ios.tests.\(UUID().uuidString)")
        defer { try? tokens.remove("active_home_id") }
        do { try tokens.set("probe", forKey: "active_home_id") } catch {
            throw XCTSkip("Keychain no disponible en este host de tests: \(error)")
        }
        try await assertSelectionSurvivesRelaunch(tokens)
    }
}

/// TokenStore cuyo `set` siempre lanza (Keychain sin firma).
private final class FailingSetTokenStore: TokenStore {
    func set(_ value: String, forKey key: String) throws { throw TokenStoreError.status(-34018) }
    func get(_ key: String) throws -> String? { nil }
    func remove(_ key: String) throws {}
}
