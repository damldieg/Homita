import XCTest
@testable import ControlKit

/// Kito organizar: ciclo de vida de la tarjeta de confirmación en `KitoStore` (estado en disco, una sola
/// llamada, sin reintento, caducidad con reloj inyectado y publicación de cambios).
@MainActor
final class KitoConfirmStoreTests: XCTestCase {
    private final class FakeChanges: KitoChangePublishing {
        var published: [[KitoChange]] = []
        func publish(_ changes: [KitoChange]) { published.append(changes) }
    }

    private var directory: URL!
    private var clock = Date(timeIntervalSince1970: 1_800_000_000)
    private let fakeChanges = FakeChanges()
    private var confirmCalls: Int { StubURLProtocol.requests.filter { $0.url?.path.hasSuffix("/confirmar") == true }.count }

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("kito-cstore-\(UUID().uuidString)")
        clock = Date(timeIntervalSince1970: 1_800_000_000)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func history() -> KitoHistoryStore { KitoHistoryStore(directory: directory.appendingPathComponent("kito")) }

    private func makeStore() -> KitoStore {
        let client = APIClient(
            baseURL: URL(string: "https://test.supabase.co/functions/v1")!,
            session: StubURLProtocol.session(),
            tokenProvider: { "t" },
            homeIdProvider: { "7" },
            readCache: ReadCache(directory: directory.appendingPathComponent("cache"))
        )
        return KitoStore(
            api: KitoAPI(client: client), historyStore: history(), userId: 1, homeId: "7",
            timezone: { "UTC" }, now: { [unowned self] in self.clock }, changes: fakeChanges
        )
    }

    private func isoString(offset: TimeInterval) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: clock.addingTimeInterval(offset))
    }

    private func seed(estado: String? = nil, offset: TimeInterval = 120) throws -> UUID {
        var datos: [String: JSONValue] = [
            "texto": .string("¿Borro la lista «Pruebas»?"), "token": .string("tok"),
            "caduca": .string(isoString(offset: offset)), "acciones": .array([])
        ]
        if let estado { datos["estado"] = .string(estado) }
        let message = KitoMessage(role: .assistant, text: "Te lo confirmo", cards: [KitoCard(tipo: "confirmacion", datos: datos)])
        try history().save([KitoMessage(role: .user, text: "borra"), message], userId: 1, homeId: "7")
        return message.id
    }

    private func diskState(_ id: UUID) -> KitoConfirmationState? {
        let msg = history().load(userId: 1, homeId: "7").first { $0.id == id }
        return msg?.cards?.first.flatMap(KitoConfirmation.init(card:))?.estado
    }

    // MARK: - T6 estados

    func testStateMappingAndUnknownValue() {
        XCTAssertEqual(KitoConfirmationState(rawValue: "hecho"), .hecho)
        XCTAssertEqual(KitoConfirmationState(rawValue: "algo raro"), .desconocido)
        XCTAssertFalse(KitoConfirmationState.pendiente.isResolved)
        XCTAssertFalse(KitoConfirmationState.enviando.isResolved)
        XCTAssertTrue(KitoConfirmationState.hecho.isResolved)
        XCTAssertEqual(KitoConfirmationState.caducado.label, "Ha caducado, pídemelo otra vez")
    }

    // MARK: - T7 resolveCard

    func testResolveReplacesTheMessageAndPersists() throws {
        let id = try seed()
        let store = makeStore()
        store.resolveCard(messageId: id, index: 0, estado: .hecho, detalle: "ok")
        XCTAssertEqual(store.messages.filter { $0.id == id }.count, 1)
        XCTAssertEqual(store.messages.count, 2)
        XCTAssertEqual(diskState(id), .hecho)
    }

    // MARK: - T8 confirm

    func testConfirmSuccessPersistsPublishesAndAddsAnswer() async throws {
        let id = try seed()
        StubURLProtocol.reset { _ in StubURLProtocol.Stub(json: #"{"texto":"Lista borrada","cambios":[{"tipo":"lista","id":3,"op":"borrar"}]}"#) }
        let store = makeStore()
        await store.confirm(messageId: id, cardIndex: 0)
        XCTAssertEqual(confirmCalls, 1)
        XCTAssertEqual(diskState(id), .hecho)
        XCTAssertEqual(fakeChanges.published.count, 1)
        XCTAssertEqual(fakeChanges.published[0].first?.kind, .lista)
        let c = try XCTUnwrap(store.messages.first { $0.id == id }?.cards?.first.flatMap(KitoConfirmation.init(card:)))
        XCTAssertEqual(c.detalle, "Lista borrada")
        let last = try XCTUnwrap(store.messages.last)
        XCTAssertEqual(last.role, .assistant)
        XCTAssertEqual(last.text, "Hecho: Lista borrada")
        // El servidor solo ve role/content: la respuesta de Kito entra en el historial enviado.
        let body = KitoAPIRequest.make(history: store.messages + [KitoMessage(role: .user, text: "¿está?")], timezone: "UTC")
        XCTAssertTrue(body.messages.contains { $0.content == "Hecho: Lista borrada" })
    }

    func testDoubleTapCallsOnce() async throws {
        let id = try seed()
        StubURLProtocol.reset { _ in
            Thread.sleep(forTimeInterval: 0.3)
            return StubURLProtocol.Stub(json: #"{"texto":"ok","cambios":[]}"#)
        }
        let store = makeStore()
        let a = Task { await store.confirm(messageId: id, cardIndex: 0) }
        while store.confirmationState(messageId: id, cardIndex: 0) == .pendiente { try await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertEqual(store.confirmationState(messageId: id, cardIndex: 0), .enviando)
        XCTAssertEqual(diskState(id), .enviando)
        await store.confirm(messageId: id, cardIndex: 0)
        await a.value
        XCTAssertEqual(confirmCalls, 1)
        await store.confirm(messageId: id, cardIndex: 0)
        XCTAssertEqual(confirmCalls, 1)
    }

    func testRejectedIsExpiredAndDoesNotRepublish() async throws {
        let id = try seed()
        StubURLProtocol.reset { _ in StubURLProtocol.Stub(status: 403, json: #"{"error":"x","motivo":"firma"}"#) }
        let store = makeStore()
        await store.confirm(messageId: id, cardIndex: 0)
        XCTAssertEqual(diskState(id), .caducado)
        XCTAssertTrue(fakeChanges.published.isEmpty)
        await store.confirm(messageId: id, cardIndex: 0)
        XCTAssertEqual(confirmCalls, 1)
    }

    func testPartialAppliesChangesAndShowsServerText() async throws {
        let id = try seed()
        StubURLProtocol.reset { _ in StubURLProtocol.Stub(status: 409, json: #"{"error":"x","texto":"Hice A, falló B","cambios":[{"tipo":"tarea","id":1,"op":"crear"}]}"#) }
        let store = makeStore()
        await store.confirm(messageId: id, cardIndex: 0)
        XCTAssertEqual(diskState(id), .parcial)
        XCTAssertEqual(fakeChanges.published.count, 1)
        let c = try XCTUnwrap(store.messages.first { $0.id == id }?.cards?.first.flatMap(KitoConfirmation.init(card:)))
        XCTAssertEqual(c.detalle, "Hice A, falló B")
    }

    func testServiceUnavailableAndBadRequestEndInError() async throws {
        for (status, expected) in [(503, "Kito no puede confirmar ahora mismo"), (400, "Pídemelo otra vez")] {
            let id = try seed()
            StubURLProtocol.reset { _ in StubURLProtocol.Stub(status: status, json: #"{"error":"x"}"#) }
            let store = makeStore()
            await store.confirm(messageId: id, cardIndex: 0)
            XCTAssertEqual(diskState(id), .error)
            let c = try XCTUnwrap(store.messages.first { $0.id == id }?.cards?.first.flatMap(KitoConfirmation.init(card:)))
            XCTAssertEqual(c.detalle, expected)
            XCTAssertEqual(confirmCalls, 1)
        }
    }

    func testNetworkFailureAnd5xxAreUnknownWithoutRetry() async throws {
        for stub in [StubURLProtocol.Stub.offline, StubURLProtocol.Stub(status: 500, json: "{}")] {
            let id = try seed()
            StubURLProtocol.reset { _ in stub }
            let store = makeStore()
            await store.confirm(messageId: id, cardIndex: 0)
            XCTAssertEqual(diskState(id), .desconocido)
            XCTAssertEqual(confirmCalls, 1)
            await store.confirm(messageId: id, cardIndex: 0)
            XCTAssertEqual(confirmCalls, 1)
        }
    }

    func testCancelIsLocalAndFinal() async throws {
        let id = try seed()
        StubURLProtocol.reset { _ in StubURLProtocol.Stub() }
        let store = makeStore()
        store.cancel(messageId: id, cardIndex: 0)
        XCTAssertEqual(diskState(id), .cancelado)
        XCTAssertTrue(StubURLProtocol.requests.isEmpty)
        await store.confirm(messageId: id, cardIndex: 0)
        XCTAssertTrue(StubURLProtocol.requests.isEmpty)
        XCTAssertEqual(store.messages.last?.text, "Cancelado. No he hecho ningún cambio.")
    }

    func testConfirmAfterClearDoesNotWriteButPublishes() async throws {
        let id = try seed()
        StubURLProtocol.reset { _ in
            Thread.sleep(forTimeInterval: 0.3)
            return StubURLProtocol.Stub(json: #"{"texto":"ok","cambios":[{"tipo":"evento","id":1,"op":"crear"}]}"#)
        }
        let store = makeStore()
        let t = Task { await store.confirm(messageId: id, cardIndex: 0) }
        while store.confirmationState(messageId: id, cardIndex: 0) == .pendiente { try await Task.sleep(nanoseconds: 5_000_000) }
        store.clearConversation()
        await t.value
        XCTAssertTrue(store.messages.isEmpty)
        XCTAssertEqual(history().load(userId: 1, homeId: "7"), [])
        XCTAssertEqual(fakeChanges.published.count, 1)
    }

    // MARK: - T9 caducidad

    func testExpiredCardDoesNotCallAndPersistsExpired() async throws {
        let id = try seed(offset: -30)
        StubURLProtocol.reset { _ in StubURLProtocol.Stub() }
        // Se carga ya caducada: normalize la marca al abrir.
        let store = makeStore()
        XCTAssertEqual(diskState(id), .caducado)
        await store.confirm(messageId: id, cardIndex: 0)
        XCTAssertTrue(StubURLProtocol.requests.isEmpty)
    }

    func testConfirmWhenExpiredBetweenLoadAndTap() async throws {
        let id = try seed(offset: 60)
        StubURLProtocol.reset { _ in StubURLProtocol.Stub() }
        let store = makeStore()
        clock = clock.addingTimeInterval(61)
        await store.confirm(messageId: id, cardIndex: 0)
        XCTAssertTrue(StubURLProtocol.requests.isEmpty)
        XCTAssertEqual(diskState(id), .caducado)
    }

    func testExpiryMarginAndFutureWithFractions() async throws {
        let inside = try seed(offset: 4)  // dentro del margen de 5 s
        let store = makeStore()
        XCTAssertEqual(diskState(inside), .caducado)
        _ = store
        let future = try seed(offset: 20)
        StubURLProtocol.reset { _ in StubURLProtocol.Stub(json: #"{"texto":"ok","cambios":[]}"#) }
        let s2 = makeStore()
        await s2.confirm(messageId: future, cardIndex: 0)
        XCTAssertEqual(confirmCalls, 1)
        XCTAssertEqual(diskState(future), .hecho)
    }

    func testExpireIfNeededOnAppear() throws {
        let id = try seed(offset: 60)
        let store = makeStore()
        XCTAssertFalse(store.expireIfNeeded(messageId: id, cardIndex: 0))
        clock = clock.addingTimeInterval(120)
        XCTAssertTrue(store.expireIfNeeded(messageId: id, cardIndex: 0))
        XCTAssertEqual(diskState(id), .caducado)
    }

    // MARK: - T10 historial

    func testReopeningWithSendingBecomesUnknownAndPersists() throws {
        let id = try seed(estado: "enviando")
        let store = makeStore()
        XCTAssertEqual(store.confirmationState(messageId: id, cardIndex: 0), .desconocido)
        XCTAssertEqual(diskState(id), .desconocido)
    }

    func testReopeningResolvedCardStaysResolved() throws {
        let id = try seed(estado: "hecho")
        let store = makeStore()
        XCTAssertEqual(store.confirmationState(messageId: id, cardIndex: 0), .hecho)
    }

    func testAskPublishesChangesOnce() async throws {
        StubURLProtocol.reset { _ in StubURLProtocol.Stub(json: #"{"texto":"hecho","cambios":[{"tipo":"tarea","id":9,"op":"crear"}]}"#) }
        let store = makeStore()
        await store.send("apúntame pan")
        XCTAssertEqual(fakeChanges.published.count, 1)
        XCTAssertEqual(fakeChanges.published[0].first?.kind, .tarea)
    }

    func testAskWithoutChangesPublishesNothingMeaningful() async throws {
        StubURLProtocol.reset { _ in StubURLProtocol.Stub(json: #"{"texto":"hola"}"#) }
        let store = makeStore()
        await store.send("hola")
        XCTAssertTrue(fakeChanges.published.allSatisfy(\.isEmpty))
    }
}
