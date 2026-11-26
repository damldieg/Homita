import XCTest
@testable import ControlKit

/// Kito organizar: cliente de confirmación, `cambios`, accesor de la tarjeta y caducidad.
final class KitoConfirmTests: XCTestCase {
    private final class Refresher: TokenRefreshing, @unchecked Sendable {
        var calls = 0
        func refreshSession() async throws { calls += 1 }
    }

    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("kito-confirm-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func client(refresher: (any TokenRefreshing)? = nil) -> APIClient {
        let c = APIClient(
            baseURL: URL(string: "https://test.supabase.co/functions/v1")!,
            session: StubURLProtocol.session(),
            tokenProvider: { "test-access" },
            homeIdProvider: { "7" },
            readCache: ReadCache(directory: directory.appendingPathComponent("cache"))
        )
        c.refresher = refresher
        return c
    }

    // MARK: - T1 sendRaw

    func testSendRawReturnsStatusAndBodyWithoutThrowing() async throws {
        StubURLProtocol.reset { _ in StubURLProtocol.Stub(status: 409, json: #"{"error":"x","texto":"parcial"}"#) }
        let c = client()
        let request = try c.request(method: .post, path: "asistente/confirmar", body: KitoConfirmRequest(token: "t", timezone: "UTC"))
        let (status, data) = try await c.sendRaw(request)
        XCTAssertEqual(status, 409)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("parcial"))
    }

    func testSendRawStillRefreshesOn401() async throws {
        let refresher = Refresher()
        var first = true
        StubURLProtocol.reset { _ in
            defer { first = false }
            return first ? StubURLProtocol.Stub(status: 401, json: #"{"error":"x"}"#) : StubURLProtocol.Stub(json: #"{"texto":"ok"}"#)
        }
        let c = client(refresher: refresher)
        let request = try c.request(method: .post, path: "asistente/confirmar", body: KitoConfirmRequest(token: "t", timezone: "UTC"))
        let (status, _) = try await c.sendRaw(request)
        XCTAssertEqual(status, 200)
        XCTAssertEqual(refresher.calls, 1)
    }

    func testSendStillThrowsOnNon2xx() async throws {
        StubURLProtocol.reset { _ in StubURLProtocol.Stub(status: 409, json: #"{"error":"boom"}"#) }
        let c = client()
        let request = try c.request(method: .post, path: "x", body: KitoConfirmRequest(token: "t", timezone: "UTC"))
        do {
            _ = try await c.send(request)
            XCTFail("debía lanzar")
        } catch let error as APIError {
            XCTAssertEqual(error, .http(status: 409, message: "boom"))
        }
    }

    // MARK: - T2 cambios

    func testReplyDecodesChanges() throws {
        let json = #"{"texto":"ok","cambios":[{"tipo":"tarea","id":5,"op":"crear"},{"tipo":"lista","id":"a","op":"borrar"}]}"#
        let reply = try JSONDecoder().decode(KitoReply.self, from: Data(json.utf8))
        XCTAssertEqual(reply.cambios.map(\.kind), [.tarea, .lista])
        XCTAssertEqual(reply.cambios.first?.id, "5")
        XCTAssertEqual(reply.cambios.last?.op, "borrar")
    }

    func testReplyWithoutOrInvalidChangesIsEmpty() throws {
        let none = try JSONDecoder().decode(KitoReply.self, from: Data(#"{"texto":"ok"}"#.utf8))
        XCTAssertEqual(none.cambios, [])
        let bad = try JSONDecoder().decode(KitoReply.self, from: Data(#"{"texto":"ok","cambios":"x"}"#.utf8))
        XCTAssertEqual(bad.cambios, [])
        let mixed = try JSONDecoder().decode(KitoReply.self, from: Data(#"{"texto":"ok","cambios":[1,{"op":"crear"},{"tipo":"evento"}]}"#.utf8))
        XCTAssertEqual(mixed.cambios.map(\.tipo), ["evento"])
    }

    func testUnknownChangeKindIsKeptWithoutKind() throws {
        let reply = try JSONDecoder().decode(KitoReply.self, from: Data(#"{"texto":"ok","cambios":[{"tipo":"raro","id":1,"op":"crear"}]}"#.utf8))
        XCTAssertEqual(reply.cambios.count, 1)
        XCTAssertNil(reply.cambios[0].kind)
    }

    // MARK: - T3 tarjeta y caducidad

    private func card(_ extra: [String: JSONValue] = [:]) -> KitoCard {
        var datos: [String: JSONValue] = [
            "texto": .string("¿Borro la lista?"),
            "token": .string("tok"),
            "caduca": .string("2026-11-25T10:10:00.000Z"),
            "acciones": .array([.object(["op": .string("borrar_lista")])])
        ]
        for (k, v) in extra { datos[k] = v }
        return KitoCard(tipo: "confirmacion", datos: datos)
    }

    func testAccessorReadsFields() throws {
        let c = try XCTUnwrap(KitoConfirmation(card: card()))
        XCTAssertEqual(c.token, "tok")
        XCTAssertEqual(c.texto, "¿Borro la lista?")
        XCTAssertEqual(c.acciones.count, 1)
        XCTAssertEqual(c.estado, .pendiente)
        XCTAssertNotNil(c.caduca)
        XCTAssertNil(KitoConfirmation(card: KitoCard(tipo: "otra")))
    }

    func testParseExpiryWithAndWithoutFractions() {
        let a = KitoConfirmation.parseExpiry("2026-11-25T10:10:00.000Z")
        let b = KitoConfirmation.parseExpiry("2026-11-25T10:10:00Z")
        XCTAssertNotNil(a)
        XCTAssertEqual(a, b)
        XCTAssertNil(KitoConfirmation.parseExpiry("mañana"))
    }

    func testMissingOrGarbageExpiryIsExpired() throws {
        let now = Date(timeIntervalSince1970: 0)
        let garbage = try XCTUnwrap(KitoConfirmation(card: card(["caduca": .string("basura")])))
        XCTAssertTrue(garbage.isExpired(at: now))
        var datos = card().datos
        datos["caduca"] = nil
        let missing = try XCTUnwrap(KitoConfirmation(card: KitoCard(tipo: "confirmacion", datos: datos)))
        XCTAssertTrue(missing.isExpired(at: now))
    }

    func testExpiryMarginIsFiveSeconds() throws {
        let c = try XCTUnwrap(KitoConfirmation(card: card()))
        let caduca = try XCTUnwrap(c.caduca)
        XCTAssertFalse(c.isExpired(at: caduca.addingTimeInterval(-6)))
        XCTAssertTrue(c.isExpired(at: caduca.addingTimeInterval(-5)))
        XCTAssertTrue(c.isExpired(at: caduca.addingTimeInterval(1)))
    }

    func testStateRoundTripsThroughTheCardAndHistoryJSON() throws {
        let resolved = KitoConfirmation.card(card(), estado: .hecho, detalle: "Lista borrada")
        let data = try JSONEncoder().encode(resolved)
        let back = try JSONDecoder().decode(KitoCard.self, from: data)
        let c = try XCTUnwrap(KitoConfirmation(card: back))
        XCTAssertEqual(c.estado, .hecho)
        XCTAssertEqual(c.detalle, "Lista borrada")
        XCTAssertNil(c.token)
    }

    func testResolvedCardDropsTokenAndActions() throws {
        for estado in [KitoConfirmationState.hecho, .cancelado, .caducado, .parcial, .error, .desconocido] {
            let resolved = KitoConfirmation.card(card(), estado: estado)
            let c = try XCTUnwrap(KitoConfirmation(card: resolved))
            XCTAssertNil(c.token)
            XCTAssertTrue(c.acciones.isEmpty)
            XCTAssertEqual(c.texto, "¿Borro la lista?")
            XCTAssertEqual(c.estado, estado)
        }
        let sending = try XCTUnwrap(KitoConfirmation(card: KitoConfirmation.card(card(), estado: .enviando)))
        XCTAssertEqual(sending.token, "tok")
    }

    // MARK: - T4 KitoAPI.confirm

    private func kito() -> KitoAPI { KitoAPI(client: client()) }

    func testConfirmPostsTokenAndTimezone() async throws {
        StubURLProtocol.reset { _ in StubURLProtocol.Stub(json: #"{"texto":"Hecho","cambios":[{"tipo":"lista","id":3,"op":"borrar"}]}"#) }
        let out = await kito().confirm(token: "tok", timezone: "Europe/Madrid")
        XCTAssertEqual(out, .hecho(texto: "Hecho", cambios: [KitoChange(tipo: "lista", id: "3", op: "borrar")]))
        let req = try XCTUnwrap(StubURLProtocol.requests.last)
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(req.url?.path, "/functions/v1/asistente/confirmar")
        XCTAssertEqual(req.value(forHTTPHeaderField: "X-Home-Id"), "7")
        let body = String(decoding: try XCTUnwrap(req.capturedBody), as: UTF8.self)
        XCTAssertTrue(body.contains(#""token":"tok""#))
        XCTAssertTrue(body.contains(#""timezone":"Europe\/Madrid""#) || body.contains(#""timezone":"Europe/Madrid""#))
    }

    func testConfirmMapsStatuses() async {
        func run(_ stub: StubURLProtocol.Stub) async -> KitoConfirmOutcome {
            StubURLProtocol.reset { _ in stub }
            return await kito().confirm(token: "t", timezone: "UTC")
        }
        let r403 = await run(.init(status: 403, json: #"{"error":"x","motivo":"caducado"}"#))
        XCTAssertEqual(r403, .rechazado)
        let r409 = await run(.init(status: 409, json: #"{"error":"x","texto":"Hice A, falló B","cambios":[{"tipo":"tarea","id":1,"op":"crear"}]}"#))
        XCTAssertEqual(r409, .parcial(texto: "Hice A, falló B", cambios: [KitoChange(tipo: "tarea", id: "1", op: "crear")]))
        let r409bad = await run(.init(status: 409, json: "no json"))
        XCTAssertEqual(r409bad, .parcial(texto: nil, cambios: []))
        let r503 = await run(.init(status: 503, json: #"{"error":"x"}"#))
        XCTAssertEqual(r503, .sinSecreto)
        let r400 = await run(.init(status: 400, json: #"{"error":"x"}"#))
        XCTAssertEqual(r400, .otro(status: 400))
        let r500 = await run(.init(status: 500, json: "{}"))
        XCTAssertEqual(r500, .otro(status: 500))
        let bad200 = await run(.init(status: 200, json: "no json"))
        XCTAssertEqual(bad200, .desconocido)
        let offline = await run(.offline)
        XCTAssertEqual(offline, .desconocido)
    }
}

/// Modelo de presentación de la tarjeta de confirmación (botones, etiquetas de VoiceOver, anuncios).
final class KitoConfirmationPresentationTests: XCTestCase {
    private func model(_ estado: KitoConfirmationState?, detalle: String? = nil, texto: String = "¿Borro la lista «Pruebas»?") -> KitoConfirmationPresentation {
        var datos: [String: JSONValue] = ["texto": .string(texto), "token": .string("t")]
        if let estado { datos["estado"] = .string(estado.rawValue) }
        if let detalle { datos["detalle"] = .string(detalle) }
        return KitoConfirmationPresentation(KitoConfirmation(card: KitoCard(tipo: "confirmacion", datos: datos))!)
    }

    func testPendingShowsEnabledButtons() {
        let m = model(nil)
        XCTAssertTrue(m.showsButtons)
        XCTAssertTrue(m.buttonsEnabled)
        XCTAssertNil(m.resolvedLabel)
        XCTAssertNil(m.announcement)
        XCTAssertEqual(m.accessibilityLabel, "Kito pide confirmación: ¿Borro la lista «Pruebas»?")
        XCTAssertEqual(m.confirmAccessibilityLabel, "Confirmar: ¿Borro la lista «Pruebas»?")
        XCTAssertEqual(m.cancelAccessibilityLabel, "Cancelar")
    }

    func testSendingShowsDisabledButtonsWithProgress() {
        let m = model(.enviando)
        XCTAssertTrue(m.showsButtons)
        XCTAssertFalse(m.buttonsEnabled)
        XCTAssertTrue(m.confirmIsLoading)
        XCTAssertTrue(m.accessibilityLabel.hasSuffix("Enviando"))
    }

    func testResolvedStatesHaveNoButtonsAndAreAnnounced() {
        for estado in [KitoConfirmationState.hecho, .cancelado, .caducado, .parcial, .error, .desconocido] {
            let m = model(estado)
            XCTAssertFalse(m.showsButtons, "\(estado)")
            XCTAssertEqual(m.announcement, estado.label)
            XCTAssertTrue(m.accessibilityLabel.contains(estado.label))
        }
        let done = model(.hecho, detalle: "Lista borrada")
        XCTAssertEqual(done.accessibilityLabel, "Kito pide confirmación: ¿Borro la lista «Pruebas»?. Hecho. Lista borrada")
    }

    func testLongTextIsReadInFullByVoiceOver() {
        let long = String(repeating: "a", count: 100)
        let m = model(nil, texto: long)
        XCTAssertEqual(m.confirmAccessibilityLabel, "Confirmar: " + long)
        XCTAssertEqual(m.proposalAccessibilityLabel, "Kito pide confirmación: " + long)
    }
}
