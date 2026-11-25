import XCTest
@testable import ControlKit

/// Kito (fase 1): forma de la petición a `asistente`, historial local por usuario y hogar, mapeo de
/// errores y flujo del store. Red con `StubURLProtocol`; disco en un directorio temporal por test.
final class KitoTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("kito-tests-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    /// Cliente de la base de funciones (`…/functions/v1`) sobre el stub, con hogar activo `7`.
    private func kitoAPI(homeId: String? = "7") -> KitoAPI {
        let client = APIClient(
            baseURL: URL(string: "https://test.supabase.co/functions/v1")!,
            session: StubURLProtocol.session(),
            tokenProvider: { "test-access" },
            homeIdProvider: { homeId },
            readCache: ReadCache(directory: directory.appendingPathComponent("cache"))
        )
        return KitoAPI(client: client)
    }

    private func history() -> KitoHistoryStore {
        KitoHistoryStore(directory: directory.appendingPathComponent("kito"))
    }

    private func sent() throws -> URLRequest {
        try XCTUnwrap(StubURLProtocol.requests.last)
    }

    private func body(_ request: URLRequest) throws -> String {
        String(data: try XCTUnwrap(request.capturedBody), encoding: .utf8) ?? ""
    }

    // MARK: - Petición

    func testRequestKeepsOnlyTheLastMessagesInOrder() {
        let history = (0..<25).map { i in
            KitoMessage(role: i % 2 == 0 ? .user : .assistant, text: "m\(i)")
        }
        let body = KitoAPIRequest.make(history: history, timezone: "Europe/Madrid")
        XCTAssertEqual(body.messages.count, KitoLimits.maxMessages)
        XCTAssertEqual(body.messages.first?.content, "m5")
        XCTAssertEqual(body.messages.last?.content, "m24")
        XCTAssertEqual(body.timezone, "Europe/Madrid")
    }

    func testAskSendsPostToAsistenteWithHomeAndBearer() async throws {
        StubURLProtocol.reset { _ in StubURLProtocol.Stub(json: #"{"texto":"Hola","uso":{"usados":1,"limite":50}}"#) }
        let reply = try await kitoAPI().ask(
            history: [KitoMessage(role: .user, text: "hola")],
            timezone: "Europe/Madrid"
        )

        XCTAssertEqual(reply.texto, "Hola")
        XCTAssertEqual(reply.uso, KitoReply.Usage(usados: 1, limite: 50))
        let request = try sent()
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/functions/v1/asistente")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-access")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Home-Id"), "7")
        XCTAssertEqual(
            try body(request),
            #"{"messages":[{"content":"hola","role":"user"}],"timezone":"Europe\/Madrid"}"#
        )
    }

    func testFunctionsBaseDropsTheApiSegment() {
        let base = KitoAPI.functionsBaseURL(fromAPIBaseURL: URL(string: "https://x.supabase.co/functions/v1/api")!)
        XCTAssertEqual(base.absoluteString, "https://x.supabase.co/functions/v1")
    }

    // MARK: - Historial local

    func testHistoryRoundTripKeepsTheNewestMessages() throws {
        let store = history()
        let mensajes = (0..<250).map { KitoMessage(role: .user, text: "m\($0)") }
        try store.save(mensajes, userId: 1, homeId: "7")

        let cargados = store.load(userId: 1, homeId: "7")
        XCTAssertEqual(cargados.count, KitoHistoryStore.maxStored)
        XCTAssertEqual(cargados.first?.text, "m50")
        XCTAssertEqual(cargados.last?.text, "m249")
    }

    func testHistoryIsSeparatedByUserAndHome() throws {
        let store = history()
        try store.save([KitoMessage(role: .user, text: "casa A")], userId: 1, homeId: "7")
        try store.save([KitoMessage(role: .user, text: "otro hogar")], userId: 1, homeId: "8")
        try store.save([KitoMessage(role: .user, text: "otro usuario")], userId: 2, homeId: "7")

        XCTAssertEqual(store.load(userId: 1, homeId: "7").map(\.text), ["casa A"])
        XCTAssertEqual(store.load(userId: 1, homeId: "8").map(\.text), ["otro hogar"])
        XCTAssertEqual(store.load(userId: 2, homeId: "7").map(\.text), ["otro usuario"])
    }

    func testClearRemovesEveryHomeOfTheUserOnly() throws {
        let store = history()
        try store.save([KitoMessage(role: .user, text: "a")], userId: 1, homeId: "7")
        try store.save([KitoMessage(role: .user, text: "b")], userId: 1, homeId: "8")
        try store.save([KitoMessage(role: .user, text: "c")], userId: 2, homeId: "7")

        store.clear(userId: 1)

        XCTAssertEqual(store.load(userId: 1, homeId: "7"), [])
        XCTAssertEqual(store.load(userId: 1, homeId: "8"), [])
        XCTAssertEqual(store.load(userId: 2, homeId: "7").map(\.text), ["c"])
    }

    func testMissingOrCorruptHistoryLoadsEmpty() throws {
        let store = history()
        XCTAssertEqual(store.load(userId: 9, homeId: "1"), [])

        try FileManager.default.createDirectory(
            at: store.fileURL(userId: 9, homeId: "1").deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("no es json".utf8).write(to: store.fileURL(userId: 9, homeId: "1"))
        XCTAssertEqual(store.load(userId: 9, homeId: "1"), [])
    }

    // MARK: - Errores

    @MainActor
    func testErrorMessagesAreClear() {
        XCTAssertTrue(KitoStore.message(for: APIError.http(status: 429, message: "Límite diario alcanzado")).contains("hablado mucho"))
        XCTAssertTrue(KitoStore.message(for: APIError.http(status: 502, message: "Kito no puede responder ahora")).contains("despistado"))
        XCTAssertTrue(KitoStore.message(for: APIError.network("offline")).contains("no tengo conexión"))
        XCTAssertTrue(KitoStore.message(for: APIError.sessionExpired).contains("sesión"))
        XCTAssertTrue(KitoStore.message(for: URLError(.badURL)).contains("Algo ha fallado"))
    }

    // MARK: - Store

    @MainActor
    func testSendStoresBothMessagesAndPersistsThem() async throws {
        StubURLProtocol.reset { _ in StubURLProtocol.Stub(json: #"{"texto":"Tienes dos tareas.","uso":null}"#) }
        let store = KitoStore(api: kitoAPI(), historyStore: history(), userId: 1, homeId: "7", timezone: { "UTC" })

        await store.send("  ¿qué tengo?  ")

        XCTAssertEqual(store.messages.map(\.role), [.user, .assistant])
        XCTAssertEqual(store.messages.first?.text, "¿qué tengo?")
        XCTAssertEqual(store.messages.last?.text, "Tienes dos tareas.")
        XCTAssertNil(store.errorText)
        XCTAssertFalse(store.isSending)
        XCTAssertEqual(history().load(userId: 1, homeId: "7").count, 2)
    }

    @MainActor
    func testFailureKeepsTheUserMessageAndExplainsTheLimit() async throws {
        StubURLProtocol.reset { _ in StubURLProtocol.Stub(status: 429, json: #"{"error":"Límite diario alcanzado"}"#) }
        let store = KitoStore(api: kitoAPI(), historyStore: history(), userId: 1, homeId: "7", timezone: { "UTC" })

        await store.send("hola")

        XCTAssertEqual(store.messages.map(\.role), [.user])
        XCTAssertEqual(store.errorText, KitoStore.message(for: APIError.http(status: 429, message: "x")))
        XCTAssertTrue(store.errorText?.contains("hablado mucho") == true)
    }

    @MainActor
    func testEmptyAndOverlongMessagesAreNotSent() async throws {
        StubURLProtocol.reset { _ in StubURLProtocol.Stub(json: #"{"texto":"ok"}"#) }
        let store = KitoStore(api: kitoAPI(), historyStore: history(), userId: 1, homeId: "7", timezone: { "UTC" })

        await store.send("   ")
        XCTAssertTrue(store.messages.isEmpty)
        XCTAssertTrue(StubURLProtocol.requests.isEmpty)

        await store.send(String(repeating: "a", count: KitoLimits.maxChars + 1))
        XCTAssertTrue(store.messages.isEmpty)
        XCTAssertNotNil(store.errorText)
        XCTAssertTrue(StubURLProtocol.requests.isEmpty)
    }

    @MainActor
    func testStoreLoadsPreviousConversation() throws {
        let store = history()
        try store.save([KitoMessage(role: .user, text: "anterior")], userId: 1, homeId: "7")

        let nuevo = KitoStore(api: kitoAPI(), historyStore: store, userId: 1, homeId: "7", timezone: { "UTC" })
        XCTAssertEqual(nuevo.messages.map(\.text), ["anterior"])
    }
}
