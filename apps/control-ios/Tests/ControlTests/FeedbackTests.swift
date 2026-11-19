import XCTest
@testable import ControlKit

/// Catálogo, validación, mapeo del request, repositorio (`POST feedback`) y store del formulario.
final class FeedbackTests: XCTestCase {
    // MARK: - Catálogo

    func testCatalogHasFiveSectionsWithExpectedAreas() {
        let sections = FeedbackCatalog.sections
        XCTAssertEqual(sections.map(\.name), ["Inicio", "Tareas", "Calendario", "Hogar", "Ajustes"])
        XCTAssertEqual(sections.map { $0.areas.count }, [3, 2, 3, 4, 3])
        XCTAssertEqual(FeedbackCatalog.section(named: "Hogar")?.areas.map(\.name),
                       ["miembros", "invitaciones", "administradores", "permisos"])
    }

    func testOnlyDaySummaryIsViewOnly() {
        for section in FeedbackCatalog.sections {
            for area in section.areas {
                if area.name == "resumen del día" {
                    XCTAssertEqual(area.actions, [.ver])
                } else {
                    XCTAssertEqual(area.actions, [.ver, .crear, .editar, .eliminar], "\(section.name)/\(area.name)")
                }
            }
        }
    }

    // MARK: - Borrador

    private func validDraft() -> FeedbackDraft {
        let section = FeedbackCatalog.section(named: "Inicio")!
        return FeedbackDraft(section: section, areaName: "eventos de hoy", action: .ver, kind: .bug, text: "  Falla  ")
    }

    func testDraftSubseccionJoinsAreaAndAction() {
        XCTAssertEqual(validDraft().subseccion, "eventos de hoy: ver")
    }

    func testDraftSubseccionRejectsActionOutsideArea() {
        var draft = validDraft()
        draft.areaName = "resumen del día"
        draft.action = .editar
        XCTAssertNil(draft.subseccion)
        XCTAssertFalse(draft.isValid)
    }

    func testDraftRequiresTextKindSectionAreaAndAction() {
        XCTAssertTrue(validDraft().isValid)
        var d = validDraft(); d.text = "   \n "
        XCTAssertFalse(d.isValid)
        d = validDraft(); d.kind = nil
        XCTAssertFalse(d.isValid)
        d = validDraft(); d.section = nil
        XCTAssertFalse(d.isValid)
        d = validDraft(); d.areaName = nil
        XCTAssertFalse(d.isValid)
        d = validDraft(); d.action = nil
        XCTAssertFalse(d.isValid)
        d = validDraft(); d.text = String(repeating: "a", count: FeedbackDraft.maxLength + 1)
        XCTAssertFalse(d.isValid)
    }

    func testLimitCountsUTF16LikeServer() {
        var d = validDraft(); d.text = String(repeating: "😀", count: 1000) // 2000 UTF-16, 1000 graphemes
        XCTAssertTrue(d.isValid)
        d.text += "a"
        XCTAssertFalse(d.isValid)
        d.text = String(repeating: "😀", count: 1001)
        XCTAssertFalse(d.isValid)
        XCTAssertEqual(FeedbackDraft.clamped(d.text).utf16.count, 2000)
    }

    func testStoreClampsEmojiWithoutSplitting() {
        let store = FeedbackStore(send: { _ in })
        store.text = String(repeating: "😀", count: 1500)
        XCTAssertEqual(store.text.utf16.count, FeedbackDraft.maxLength)
        XCTAssertEqual(store.text.count, 1000)
    }

    func testFeedbackForbiddenIsNotOwnerOnlyMessage() {
        for message in ["Feedback not allowed", "Not Allowed"] {
            let e = APIError.http(status: 403, message: message)
            XCTAssertEqual(e.feedbackMessage, "No se pudo enviar el comentario. Inténtalo de nuevo más tarde.")
            XCTAssertFalse(e.feedbackMessage.contains("propietario"))
        }
        XCTAssertEqual(APIError.http(status: 400, message: "Invalid tipo").feedbackMessage, "Invalid tipo")
    }

    func testDraftRequestMapping() {
        XCTAssertEqual(validDraft().request,
                       FeedbackRequest(seccion: "Inicio", subseccion: "eventos de hoy: ver", tipo: "bug", texto: "Falla"))
    }

    // MARK: - Request

    func testRequestShape() async throws {
        StubURLProtocol.reset { _ in StubURLProtocol.Stub(status: 201, json: #"{"ok":true}"#) }
        let client = makeTestClient()
        try await FeedbackRepository(client: client).send(validDraft().request!)
        let sent = try XCTUnwrap(StubURLProtocol.requests.last)
        XCTAssertEqual(sent.httpMethod, "POST")
        XCTAssertEqual(sent.url?.path.hasSuffix("/feedback"), true)
        XCTAssertEqual(sent.value(forHTTPHeaderField: "Authorization"), "Bearer test-access")
        XCTAssertNil(sent.value(forHTTPHeaderField: "X-Home-Id"))
        XCTAssertEqual(
            String(data: try XCTUnwrap(sent.capturedBody), encoding: .utf8),
            #"{"seccion":"Inicio","subseccion":"eventos de hoy: ver","texto":"Falla","tipo":"bug"}"#
        )
    }

    func testRepositoryMapsHttpError() async throws {
        StubURLProtocol.reset { _ in StubURLProtocol.Stub(status: 400, json: #"{"error":"Invalid tipo"}"#) }
        do {
            try await FeedbackRepository(client: makeTestClient()).send(validDraft().request!)
            XCTFail("debía fallar")
        } catch let error as APIError {
            XCTAssertEqual(error, .http(status: 400, message: "Invalid tipo"))
        }
    }

    func testRepositoryUnauthorizedWithoutRefresherExpiresSession() async throws {
        StubURLProtocol.reset { _ in StubURLProtocol.Stub(status: 401, json: #"{"error":"Unauthorized"}"#) }
        do {
            try await FeedbackRepository(client: makeTestClient()).send(validDraft().request!)
            XCTFail("debía fallar")
        } catch let error as APIError {
            XCTAssertEqual(error, .sessionExpired)
        }
    }

    // MARK: - Store

    private func filledStore(send: @escaping (FeedbackRequest) async throws -> Void = { _ in }) -> FeedbackStore {
        let store = FeedbackStore(send: send)
        store.selectSection(FeedbackCatalog.section(named: "Tareas")!)
        store.selectArea(FeedbackCatalog.section(named: "Tareas")!.areas[0])
        store.selectAction(.crear)
        store.selectKind(.mejora)
        store.text = "Quiero ordenar listas"
        return store
    }

    func testChangingSectionResetsAreaAndAction() {
        let store = filledStore()
        XCTAssertEqual(store.draft.areaName, "listas")
        store.selectSection(FeedbackCatalog.section(named: "Hogar")!)
        XCTAssertNil(store.draft.areaName)
        XCTAssertNil(store.draft.action)
        XCTAssertEqual(store.areas.map(\.name), ["miembros", "invitaciones", "administradores", "permisos"])
        XCTAssertTrue(store.actions.isEmpty)
        // Mismo valor: no reinicia.
        store.selectArea(store.areas[0]); store.selectAction(.ver)
        store.selectSection(FeedbackCatalog.section(named: "Hogar")!)
        XCTAssertEqual(store.draft.action, .ver)
    }

    func testDaySummaryOffersOnlyViewAndPreselectsIt() {
        let store = FeedbackStore(send: { _ in })
        store.selectSection(FeedbackCatalog.section(named: "Inicio")!)
        store.selectArea(store.areas[0])
        XCTAssertEqual(store.actions, [.ver])
        XCTAssertEqual(store.draft.action, .ver)
        store.selectAction(.editar)
        XCTAssertEqual(store.draft.action, .ver)
    }

    func testCanSubmitNeedsTextKindAndNetwork() {
        let store = filledStore()
        XCTAssertTrue(store.canSubmit(isOffline: false))
        XCTAssertFalse(store.canSubmit(isOffline: true))
        store.selectKind(nil)
        XCTAssertFalse(store.canSubmit(isOffline: false))
        store.selectKind(.bug)
        store.text = "   "
        XCTAssertFalse(store.canSubmit(isOffline: false))
    }

    func testTextIsClampedToLimit() {
        let store = FeedbackStore(send: { _ in })
        store.text = String(repeating: "x", count: FeedbackDraft.maxLength + 50)
        XCTAssertEqual(store.text.count, FeedbackDraft.maxLength)
    }

    func testSubmitSuccessSendsRequestAndMarksSent() async {
        var received: FeedbackRequest?
        let store = filledStore { received = $0 }
        let ok = await store.submit()
        XCTAssertTrue(ok)
        XCTAssertTrue(store.didSend)
        XCTAssertFalse(store.isWorking)
        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(received, FeedbackRequest(seccion: "Tareas", subseccion: "listas: crear", tipo: "mejora",
                                                 texto: "Quiero ordenar listas"))
    }

    func testSubmitOfflineDoesNotSend() async {
        var calls = 0
        let store = filledStore { _ in calls += 1 }
        let ok = await store.submit(isOffline: true)
        XCTAssertFalse(ok)
        XCTAssertEqual(calls, 0)
        XCTAssertFalse(store.didSend)
    }

    func testSubmitFailureKeepsContentAndShowsError() async {
        let store = filledStore { _ in throw APIError.network("sin red") }
        let ok = await store.submit()
        XCTAssertFalse(ok)
        XCTAssertFalse(store.didSend)
        XCTAssertFalse(store.isWorking)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertEqual(store.text, "Quiero ordenar listas")
        XCTAssertEqual(store.draft.kind, .mejora)
        XCTAssertEqual(store.draft.areaName, "listas")
    }

    func testSecondSubmitIgnoredWhileWorking() async {
        let store = filledStore { _ in try await Task.sleep(nanoseconds: 100_000_000) }
        async let first = store.submit()
        try? await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertTrue(store.isWorking)
        XCTAssertFalse(store.canSubmit(isOffline: false))
        let second = await store.submit()
        XCTAssertFalse(second)
        _ = await first
    }
}
