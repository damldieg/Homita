import XCTest
@testable import ControlKit

@MainActor
final class KitoMenuTests: XCTestCase {
    private let replyJSON = """
    {"texto":"Te propongo este menú","tarjetas":[
      {"tipo":"menu","id":"menu","semana":"2026-11-23","plan_id":9,"revision":3,"estado":"draft","origen":"kito",
       "conflictos":0,"sin_comprobar":[],
       "casillas":[
         {"id":11,"dia":"2026-11-24","franja":"dinner","franja_es":"cena","posicion":0,"tipo":"free_text",
          "titulo":"Tortilla","receta_id":null,"estado":"rejected","personas":[3],"comprobada":true,"motivo":"Ya la cené ayer"},
         {"id":10,"dia":"2026-11-23","franja":"lunch","franja_es":"comida","posicion":0,"tipo":"recipe",
          "titulo":"Lentejas","receta_id":5,"estado":null,"personas":[],"comprobada":true},
         {"id":12,"dia":"2026-11-23","franja":"dinner","franja_es":"cena","posicion":0,"tipo":"free_text",
          "titulo":"Sopa","receta_id":null,"estado":"locked","personas":[],"comprobada":true}
       ]},
      {"tipo":"tipo_nuevo_que_no_conozco","x":1}
    ]}
    """

    private func card(_ json: String) throws -> KitoCard {
        try JSONCoding.decoder().decode(KitoCard.self, from: Data(json.utf8))
    }

    func testDecodesValidMenuCard() throws {
        let reply = try JSONCoding.decoder().decode(KitoReply.self, from: Data(replyJSON.utf8))
        XCTAssertEqual(reply.tarjetas.count, 2, "la desconocida no rompe la respuesta")
        let menu = try XCTUnwrap(KitoMenu(card: reply.tarjetas[0]))
        XCTAssertEqual(menu.planId, 9)
        XCTAssertEqual(menu.revision, 3)
        XCTAssertEqual(menu.semana, "2026-11-23")
        XCTAssertEqual(menu.estadoPlan, "draft")
        XCTAssertEqual(menu.resultado, .pendiente)
        XCTAssertEqual(menu.casillas.count, 3)
        XCTAssertEqual(menu.rejected.map(\.titulo), ["Tortilla"])
        XCTAssertEqual(menu.rejected.first?.motivo, "Ya la cené ayer")
        XCTAssertEqual(menu.days.map(\.dia), ["2026-11-23", "2026-11-24"])
        XCTAssertEqual(menu.days[0].dishes.map(\.titulo), ["Lentejas", "Sopa"])
        XCTAssertEqual(menu.days[0].dishes[0].franjaEs, "comida")
    }

    func testUnknownCardTypeIsNotAMenu() throws {
        let reply = try JSONCoding.decoder().decode(KitoReply.self, from: Data(replyJSON.utf8))
        XCTAssertNil(KitoMenu(card: reply.tarjetas[1]))
    }

    func testMenuWithoutPlanOrRevisionIsRejected() throws {
        XCTAssertNil(KitoMenu(card: try card(#"{"tipo":"menu","semana":"2026-11-23","casillas":[]}"#)))
        XCTAssertNil(KitoMenu(card: try card(#"{"tipo":"menu","plan_id":9,"casillas":[]}"#)))
        XCTAssertNil(KitoMenu(card: try card(#"{"tipo":"menu","plan_id":"9","revision":1}"#)))
    }

    func testMalformedDishesAreSkipped() throws {
        let c = try card(#"{"tipo":"menu","plan_id":9,"revision":1,"casillas":[1,{"titulo":"sin dia"},{"dia":"2026-11-23","titulo":"Arroz"}]}"#)
        let menu = try XCTUnwrap(KitoMenu(card: c))
        XCTAssertEqual(menu.casillas.map(\.titulo), ["Arroz"])
        XCTAssertEqual(menu.casillas[0].franjaEs, "")
    }

    func testResultRoundTripsAndUnknownValueIsDesconocido() throws {
        let c = try card(#"{"tipo":"menu","plan_id":9,"revision":1}"#)
        let done = KitoMenu.card(c, resultado: .aceptado)
        XCTAssertEqual(KitoMenu(card: done)?.resultado, .aceptado)
        XCTAssertEqual(KitoMenuResult(rawValue: "raro"), .desconocido)
        XCTAssertFalse(KitoMenuResult.aceptado.canAccept)
        XCTAssertTrue(KitoMenuResult.pendiente.canAccept)
    }

    func testMealKindsReloadMealsTab() {
        let c = KitoChanges()
        c.publish([KitoChange(tipo: "menu", id: "9", op: "proponer"), KitoChange(tipo: "receta", id: "5", op: "crear")])
        XCTAssertEqual(c.counter(for: KitoReloadTargets.meals), 2)
        XCTAssertEqual(c.counter(for: KitoReloadTargets.tasks), 0)
    }
}

@MainActor
final class KitoMenuStoreTests: XCTestCase {
    private var directory: URL!
    private let fakeChanges = KitoChanges()

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("kito-menu-\(UUID().uuidString)")
        StubURLProtocol.reset { _ in StubURLProtocol.Stub(json: "{}") }
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func history() -> KitoHistoryStore { KitoHistoryStore(directory: directory.appendingPathComponent("kito")) }

    private func client() -> APIClient {
        APIClient(
            baseURL: URL(string: "https://test.supabase.co/functions/v1/api")!, session: StubURLProtocol.session(),
            tokenProvider: { "t" }, homeIdProvider: { "7" },
            readCache: ReadCache(directory: directory.appendingPathComponent("cache")))
    }

    private func makeStore(accept: Bool = true) -> KitoStore {
        let meals = MealRepository(client: client())
        return KitoStore(
            api: KitoAPI(client: client()), historyStore: history(), userId: 1, homeId: "7", timezone: { "UTC" },
            changes: fakeChanges,
            acceptMenu: accept ? { id, rev in _ = try await meals.accept(planId: id, expectedRevision: rev) } : nil)
    }

    private func seed(resultado: String? = nil) throws -> UUID {
        var datos: [String: JSONValue] = [
            "plan_id": .number(9), "revision": .number(3), "semana": .string("2026-11-23"), "estado": .string("draft"),
            "casillas": .array([.object(["dia": .string("2026-11-23"), "franja_es": .string("comida"), "titulo": .string("Lentejas")])])
        ]
        if let resultado { datos["resultado"] = .string(resultado) }
        let message = KitoMessage(role: .assistant, text: "Menú", cards: [KitoCard(tipo: "menu", datos: datos)])
        try history().save([KitoMessage(role: .user, text: "menú"), message], userId: 1, homeId: "7")
        return message.id
    }

    private let planResponse = """
    {"id":9,"week_start":"2026-11-23","status":"accepted","revision":4,"accepted_at":null,"accepted_by":null,
     "updated_at":"2026-11-24T10:00:00","items":[]}
    """

    private static func bodyData(of request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let n = stream.read(&buffer, maxLength: buffer.count)
            if n <= 0 { break }
            data.append(buffer, count: n)
        }
        return data
    }

    private func acceptCalls() -> [URLRequest] {
        StubURLProtocol.requests.filter { $0.url?.path.hasSuffix("/meal/plan/accept") == true }
    }

    func testNothingIsAcceptedWithoutTapping() throws {
        _ = try seed()
        _ = makeStore()
        XCTAssertTrue(acceptCalls().isEmpty)
    }

    func testAcceptSendsPlanAndRevisionOnceAndPublishesMenuChange() async throws {
        let id = try seed()
        StubURLProtocol.reset { _ in StubURLProtocol.Stub(json: self.planResponse) }
        let store = makeStore()
        await store.acceptMenu(messageId: id, cardIndex: 0)
        let calls = acceptCalls()
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls[0].httpMethod, "POST")
        let body = try XCTUnwrap(Self.bodyData(of: calls[0]))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["plan_id"] as? Int, 9)
        XCTAssertEqual(json["expected_revision"] as? Int, 3)
        XCTAssertEqual(store.menuResult(messageId: id, cardIndex: 0), .aceptado)
        XCTAssertEqual(fakeChanges.counter(for: KitoReloadTargets.meals), 1)
        // Ya aceptada: un segundo toque no llama otra vez.
        await store.acceptMenu(messageId: id, cardIndex: 0)
        XCTAssertEqual(acceptCalls().count, 1)
    }

    func testStaleRevisionMarksCardOutdatedAndDoesNotPublish() async throws {
        let id = try seed()
        StubURLProtocol.reset { _ in StubURLProtocol.Stub(status: 409, json: #"{"error":"Stale meal plan revision"}"#) }
        let store = makeStore()
        await store.acceptMenu(messageId: id, cardIndex: 0)
        XCTAssertEqual(store.menuResult(messageId: id, cardIndex: 0), .desactualizado)
        XCTAssertEqual(fakeChanges.counter(for: KitoReloadTargets.meals), 0)
    }

    func testWithoutAcceptHandlerNothingHappens() async throws {
        let id = try seed()
        let store = makeStore(accept: false)
        await store.acceptMenu(messageId: id, cardIndex: 0)
        XCTAssertTrue(acceptCalls().isEmpty)
        XCTAssertEqual(store.menuResult(messageId: id, cardIndex: 0), .pendiente)
    }

    func testSendingStateFromClosedAppBecomesDesconocidoOnLoad() throws {
        let id = try seed(resultado: "enviando")
        let store = makeStore()
        XCTAssertEqual(store.menuResult(messageId: id, cardIndex: 0), .desconocido)
    }

    func testPresentationShowsRejectedWithReasonAndFullAccessibilityText() throws {
        let card = KitoCard(tipo: "menu", datos: [
            "plan_id": .number(9), "revision": .number(3), "semana": .string("2026-11-23"),
            "casillas": .array([.object(["dia": .string("2026-11-24"), "franja_es": .string("cena"), "titulo": .string("Tortilla"),
                                         "estado": .string("rejected"), "motivo": .string("Ya la cené")])])
        ])
        let model = KitoMenuPresentation(menu: try XCTUnwrap(KitoMenu(card: card)))
        XCTAssertEqual(model.title, "Menú de la semana del 23 de noviembre")
        XCTAssertTrue(model.showsAccept)
        XCTAssertTrue(model.accessibilityLabel.contains("cena: Tortilla (a cambiar: Ya la cené)"))
        XCTAssertTrue(model.accessibilityLabel.contains("martes 24 de noviembre"))
    }
}
