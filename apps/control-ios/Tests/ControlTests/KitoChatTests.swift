import XCTest
@testable import ControlKit

/// Kito (chat iOS): tarjetas tolerantes, textos de error, cupo, Markdown, saludo y estado del store.
final class KitoChatTests: XCTestCase {
    private func decodeReply(_ json: String) throws -> KitoReply {
        try JSONDecoder().decode(KitoReply.self, from: Data(json.utf8))
    }

    // MARK: - Tarjetas

    func testKnownCardDecodes() throws {
        let reply = try decodeReply(#"{"texto":"ok","tarjetas":[{"tipo":"tarea","titulo":"Comprar","n":2}]}"#)
        XCTAssertEqual(reply.tarjetas.count, 1)
        XCTAssertEqual(reply.tarjetas[0].tipo, "tarea")
        XCTAssertEqual(reply.tarjetas[0].datos["titulo"], .string("Comprar"))
        XCTAssertEqual(reply.tarjetas[0].datos["n"], .number(2))
    }

    func testUnknownCardTypeDoesNotBreakDecode() throws {
        let reply = try decodeReply(#"{"texto":"ok","tarjetas":[{"tipo":"futuro","x":[1,{"a":null}],"texto":"hola"}]}"#)
        XCTAssertEqual(reply.tarjetas.first?.tipo, "futuro")
        XCTAssertEqual(reply.tarjetas.first?.datos["texto"], .string("hola"))
    }

    func testMissingOrNullCardsAreEmpty() throws {
        XCTAssertEqual(try decodeReply(#"{"texto":"ok"}"#).tarjetas, [])
        XCTAssertEqual(try decodeReply(#"{"texto":"ok","tarjetas":null}"#).tarjetas, [])
    }

    func testMalformedCardIsDropped() throws {
        let reply = try decodeReply(#"{"texto":"ok","tarjetas":[5,{"sin":"tipo"},{"tipo":"a"}]}"#)
        XCTAssertEqual(reply.tarjetas.map(\.tipo), ["a"])
        XCTAssertEqual(reply.texto, "ok")
    }

    func testOldHistoryWithoutCardsLoads() throws {
        let json = #"[{"id":"\#(UUID().uuidString)","role":"user","text":"hola","date":0}]"#
        let messages = try JSONDecoder().decode([KitoMessage].self, from: Data(json.utf8))
        XCTAssertEqual(messages.count, 1)
        XCTAssertNil(messages[0].cards)
    }

    func testMessageWithCardRoundTrips() throws {
        let card = KitoCard(tipo: "prueba", datos: ["a": .bool(true), "b": .array([.number(1), .null])])
        let message = KitoMessage(role: .assistant, text: "t", cards: [card])
        let data = try JSONEncoder().encode(message)
        XCTAssertEqual(try JSONDecoder().decode(KitoMessage.self, from: data), message)
    }

    // MARK: - Textos de error

    func testErrorCopyPerCode() {
        XCTAssertEqual(KitoErrorCopy.text(for: APIError.http(status: 429, message: "x")), "Por hoy ya hemos hablado mucho. Mañana sigo aquí.")
        XCTAssertEqual(KitoErrorCopy.text(for: APIError.http(status: 502, message: "x")), "Me he despistado un momento. ¿Lo intentamos otra vez?")
        XCTAssertEqual(KitoErrorCopy.text(for: APIError.http(status: 503, message: "x")), KitoErrorCopy.modelFailure)
        XCTAssertEqual(KitoErrorCopy.text(for: APIError.network("x")), "Ahora mismo no tengo conexión.")
        XCTAssertEqual(KitoErrorCopy.text(for: APIError.http(status: 404, message: "x")), "No encuentro tu hogar activo. Vuelve a elegirlo y lo intentamos.")
        XCTAssertEqual(KitoErrorCopy.text(for: APIError.sessionExpired), "Tu sesión ha caducado. Entra de nuevo y seguimos.")
        XCTAssertEqual(KitoErrorCopy.text(for: APIError.http(status: 400, message: "x")), "Algo ha fallado. ¿Lo intentamos otra vez?")
        XCTAssertEqual(KitoErrorCopy.tooLong(), "Eso es muy largo para mí. ¿Lo dejas en menos de 2000 caracteres?")
    }

    func testRetryableOnlyWhenResendingCanHelp() {
        XCTAssertTrue(KitoErrorCopy.isRetryable(APIError.http(status: 502, message: "x")))
        XCTAssertTrue(KitoErrorCopy.isRetryable(APIError.network("x")))
        XCTAssertFalse(KitoErrorCopy.isRetryable(APIError.http(status: 429, message: "x")))
        XCTAssertFalse(KitoErrorCopy.isRetryable(APIError.sessionExpired))
    }

    // MARK: - Store

    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("kito-chat-tests-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func kitoAPI() -> KitoAPI {
        let client = APIClient(
            baseURL: URL(string: "https://test.supabase.co/functions/v1")!,
            session: StubURLProtocol.session(),
            tokenProvider: { "test-access" },
            homeIdProvider: { "7" },
            readCache: ReadCache(directory: directory.appendingPathComponent("cache"))
        )
        return KitoAPI(client: client)
    }

    private func history() -> KitoHistoryStore {
        KitoHistoryStore(directory: directory.appendingPathComponent("kito"))
    }

    @MainActor
    private func makeStore() -> KitoStore {
        KitoStore(api: kitoAPI(), historyStore: history(), userId: 1, homeId: "7", timezone: { "UTC" })
    }

    @MainActor
    func testRetryAfter502DoesNotDuplicateTheUserMessage() async throws {
        StubURLProtocol.reset { _ in StubURLProtocol.Stub(status: 502, json: #"{"error":"x"}"#) }
        let store = makeStore()
        await store.send("hola")
        XCTAssertEqual(store.failure, KitoFailure(text: KitoErrorCopy.modelFailure, retryable: true))

        StubURLProtocol.reset { _ in StubURLProtocol.Stub(json: #"{"texto":"Aquí estoy","uso":{"usados":3,"limite":50}}"#) }
        await store.retry()

        XCTAssertEqual(store.messages.map(\.role), [.user, .assistant])
        XCTAssertNil(store.failure)
        XCTAssertEqual(history().load(userId: 1, homeId: "7").map(\.role), [.user, .assistant])
        XCTAssertEqual(store.usage, KitoReply.Usage(usados: 3, limite: 50))
    }

    @MainActor
    func testRetryWithoutFailureDoesNothing() async throws {
        StubURLProtocol.reset { _ in StubURLProtocol.Stub(json: #"{"texto":"ok"}"#) }
        let store = makeStore()
        await store.retry()
        XCTAssertTrue(store.messages.isEmpty)
        XCTAssertTrue(StubURLProtocol.requests.isEmpty)
    }

    @MainActor
    func testDailyLimitIsNotRetryable() async throws {
        StubURLProtocol.reset { _ in StubURLProtocol.Stub(status: 429, json: #"{"error":"x"}"#) }
        let store = makeStore()
        await store.send("hola")
        XCTAssertEqual(store.failure?.retryable, false)
        let count = StubURLProtocol.requests.count
        await store.retry()
        XCTAssertEqual(StubURLProtocol.requests.count, count)
    }

    @MainActor
    func testCardsAreSavedWithTheMessage() async throws {
        StubURLProtocol.reset { _ in StubURLProtocol.Stub(json: #"{"texto":"ok","tarjetas":[{"tipo":"prueba","texto":"hola"}]}"#) }
        let store = makeStore()
        await store.send("hola")
        XCTAssertEqual(history().load(userId: 1, homeId: "7").last?.cards?.first?.tipo, "prueba")
    }

    @MainActor
    func testClearConversationOnlyTouchesTheActiveHomeAndUser() async throws {
        let h = history()
        try h.save([KitoMessage(role: .user, text: "a")], userId: 1, homeId: "7")
        try h.save([KitoMessage(role: .user, text: "b")], userId: 1, homeId: "8")
        try h.save([KitoMessage(role: .user, text: "c")], userId: 2, homeId: "7")
        let store = makeStore()
        XCTAssertEqual(store.messages.count, 1)

        store.clearConversation()

        XCTAssertTrue(store.messages.isEmpty)
        XCTAssertNil(store.failure)
        XCTAssertEqual(h.load(userId: 1, homeId: "7"), [])
        XCTAssertEqual(h.load(userId: 1, homeId: "8").map(\.text), ["b"])
        XCTAssertEqual(h.load(userId: 2, homeId: "7").map(\.text), ["c"])
    }

    // MARK: - Cupo

    func testQuotaNoticeThreshold() {
        typealias U = KitoReply.Usage
        XCTAssertEqual(KitoQuota.remainingNotice(U(usados: 40, limite: 50)), "Te quedan 10 mensajes hoy.")
        XCTAssertNil(KitoQuota.remainingNotice(U(usados: 39, limite: 50)))
        XCTAssertEqual(KitoQuota.remainingNotice(U(usados: 49, limite: 50)), "Te queda 1 mensaje hoy.")
        XCTAssertEqual(KitoQuota.remainingNotice(U(usados: 50, limite: 50)), "Hoy ya no me quedan mensajes.")
        XCTAssertEqual(KitoQuota.remainingNotice(U(usados: 52, limite: 50)), "Hoy ya no me quedan mensajes.")
        XCTAssertNil(KitoQuota.remainingNotice(nil))
    }

    // MARK: - Markdown

    func testMarkdownBoldAndItalicAreAttributed() {
        let result = KitoMarkdown.attributed("una **negrita** y *cursiva*")
        XCTAssertEqual(String(result.characters), "una negrita y cursiva")
        let intents = result.runs.compactMap { $0.inlinePresentationIntent }
        XCTAssertTrue(intents.contains(.stronglyEmphasized))
        XCTAssertTrue(intents.contains(.emphasized))
    }

    func testMarkdownListBecomesBullets() {
        let result = KitoMarkdown.attributed("Tienes:\n- uno\n* dos\n  - tres")
        XCTAssertEqual(String(result.characters), "Tienes:\n• uno\n• dos\n• tres")
    }

    func testMarkdownInvalidTextStaysReadable() {
        XCTAssertTrue(String(KitoMarkdown.attributed("abre **sin cerrar").characters).contains("sin cerrar"))
        XCTAssertTrue(String(KitoMarkdown.attributed("mira [roto](").characters).contains("roto"))
        XCTAssertEqual(String(KitoMarkdown.attributed("").characters), "")
    }

    // MARK: - Bienvenida

    private func date(_ hour: Int, day: Int = 25) -> (Date, Calendar) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Madrid")!
        let d = cal.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
        return (d, cal)
    }

    func testSalutationByHour() {
        for (hour, expected) in [(8, "Buenos días"), (15, "Buenas tardes"), (22, "Buenas noches"), (3, "Buenas noches"), (13, "Buenas tardes"), (20, "Buenas noches")] {
            let (d, cal) = date(hour)
            XCTAssertEqual(KitoGreeting.salutation(date: d, calendar: cal), expected, "hora \(hour)")
        }
    }

    func testGreetingUsesFirstNameOnly() {
        XCTAssertEqual(KitoGreeting.text(name: "Ana García"), "¡Hola, Ana! Soy Kito.")
        XCTAssertEqual(KitoGreeting.text(name: "  "), "¡Hola! Soy Kito.")
        XCTAssertEqual(KitoGreeting.text(name: nil), "¡Hola! Soy Kito.")
    }

    func testSuggestionsAreFour() {
        XCTAssertEqual(KitoSuggestions.all.count, 4)
    }

    func testDayLabels() {
        let (now, cal) = date(10)
        XCTAssertEqual(KitoGreeting.dayLabel(for: date(2).0, now: now, calendar: cal), "Hoy")
        XCTAssertEqual(KitoGreeting.dayLabel(for: date(23, day: 24).0, now: now, calendar: cal), "Ayer")
        XCTAssertEqual(KitoGreeting.dayLabel(for: date(9, day: 3).0, now: now, calendar: cal), "3 de noviembre")
    }
}
