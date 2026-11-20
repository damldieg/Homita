import XCTest
@testable import ControlKit

/// Catálogo, validación, mapeo del request, repositorio (`POST feedback`) y store del formulario.
final class FeedbackTests: XCTestCase {
    // MARK: - Catálogo (contra el fixture compartido con la Edge)

    private struct FixtureCatalog: Decodable {
        struct Screen: Decodable, Equatable { let nombre: String; let acciones: [String] }
        struct Section: Decodable, Equatable { let nombre: String; let pantallas: [Screen] }
        let secciones: [Section]
    }

    private func loadFixture(file: StaticString = #filePath) throws -> FixtureCatalog {
        var url = URL(fileURLWithPath: "\(file)")
        for _ in 0..<5 { url.deleteLastPathComponent() } // FeedbackTests.swift, ControlTests, Tests, control-ios, apps
        url.appendPathComponent("supabase/functions/api/tests/fixtures/feedback_catalog.json")
        guard let data = try? Data(contentsOf: url) else {
            XCTFail("No existe el fixture del catálogo: \(url.path)")
            throw CocoaError(.fileReadNoSuchFile)
        }
        return try JSONDecoder().decode(FixtureCatalog.self, from: data)
    }

    func testCatalogEqualsSharedFixture() throws {
        let fixture = try loadFixture()
        let mapped = FeedbackCatalog.sections.map { section in
            FixtureCatalog.Section(nombre: section.name, pantallas: section.screens.map {
                FixtureCatalog.Screen(nombre: $0.name, acciones: $0.actions)
            })
        }
        XCTAssertFalse(fixture.secciones.isEmpty)
        XCTAssertEqual(mapped, fixture.secciones)
    }

    func testCatalogInvariants() {
        let sections = FeedbackCatalog.sections
        XCTAssertEqual(Set(sections.map(\.name)).count, sections.count)
        for section in sections {
            XCTAssertFalse(section.screens.isEmpty, section.name)
            XCTAssertEqual(Set(section.screens.map(\.name)).count, section.screens.count, section.name)
            for screen in section.screens {
                XCTAssertFalse(screen.actions.isEmpty, screen.name)
                XCTAssertEqual(Set(screen.actions).count, screen.actions.count, screen.name)
                for name in [section.name, screen.name] + screen.actions {
                    XCTAssertFalse(name.contains(": "), name)
                    XCTAssertEqual(name, name.trimmingCharacters(in: .whitespaces))
                    XCTAssertFalse(name.isEmpty)
                }
                for action in screen.actions {
                    let pair = "\(screen.name): \(action)"
                    XCTAssertLessThanOrEqual(pair.utf16.count, FeedbackDraft.subseccionMaxLength, pair)
                }
            }
        }
    }

    func testCatalogHasAccessAndGeneralSections() {
        XCTAssertNotNil(FeedbackCatalog.section(named: "Acceso"))
        let general = FeedbackCatalog.section(named: "General / otro")
        XCTAssertEqual(general?.screens.map(\.name), ["Otro", "Banner sin conexión", "Animación de arranque"])
        XCTAssertTrue(general?.screens.allSatisfy { $0.actions == ["General"] } ?? false)
    }

    // MARK: - Borrador

    private func validDraft() -> FeedbackDraft {
        let section = FeedbackCatalog.section(named: "Inicio")!
        return FeedbackDraft(section: section, screenName: "Tareas pendientes", action: "Ver más", kind: .bug, text: "  Falla  ")
    }

    func testDraftSubseccionJoinsScreenAndAction() {
        XCTAssertEqual(validDraft().subseccion, "Tareas pendientes: Ver más")
    }

    func testDraftSubseccionWithSpacedActionAndPath() {
        let section = FeedbackCatalog.section(named: "Tareas")!
        let draft = FeedbackDraft(section: section, screenName: "Detalle de lista › Editar tarea",
                                  action: "Guardar", kind: .bug, text: "x")
        XCTAssertEqual(draft.subseccion, "Detalle de lista › Editar tarea: Guardar")
        XCTAssertTrue(draft.isValid)
    }

    func testDraftSubseccionRejectsActionOutsideScreen() {
        var draft = validDraft()
        draft.screenName = "Inicio"
        draft.action = "Eliminar tarea"
        XCTAssertNil(draft.subseccion)
        XCTAssertFalse(draft.isValid)
    }

    func testDraftInvalidWhenSubseccionExceedsLimit() {
        let long = String(repeating: "a", count: FeedbackDraft.subseccionMaxLength)
        let section = FeedbackSection("S", screens: [FeedbackScreen(long, actions: ["Ver"])])
        let draft = FeedbackDraft(section: section, screenName: long, action: "Ver", kind: .bug, text: "x")
        XCTAssertNotNil(draft.subseccion)
        XCTAssertFalse(draft.isValid)
    }

    func testDraftRequiresTextKindSectionScreenAndAction() {
        XCTAssertTrue(validDraft().isValid)
        var d = validDraft(); d.text = "   \n "
        XCTAssertFalse(d.isValid)
        d = validDraft(); d.kind = nil
        XCTAssertFalse(d.isValid)
        d = validDraft(); d.section = nil
        XCTAssertFalse(d.isValid)
        d = validDraft(); d.screenName = nil
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
                       FeedbackRequest(seccion: "Inicio", subseccion: "Tareas pendientes: Ver más", tipo: "bug", texto: "Falla"))
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
            #"{"seccion":"Inicio","subseccion":"Tareas pendientes: Ver más","texto":"Falla","tipo":"bug"}"#
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
        let section = FeedbackCatalog.section(named: "Tareas")!
        store.selectSection(section)
        store.selectScreen(section.screen(named: "Listas")!)
        store.selectAction("Nueva lista")
        store.selectKind(.mejora)
        store.text = "Quiero ordenar listas"
        return store
    }

    func testChangingSectionResetsScreenAndAction() {
        let store = filledStore()
        XCTAssertEqual(store.draft.screenName, "Listas")
        let hogar = FeedbackCatalog.section(named: "Hogar")!
        store.selectSection(hogar)
        XCTAssertNil(store.draft.screenName)
        XCTAssertNil(store.draft.action)
        XCTAssertEqual(store.screens, hogar.screens)
        XCTAssertTrue(store.actions.isEmpty)
        // Mismo valor: no reinicia.
        store.selectScreen(store.screens[0]); store.selectAction(store.screens[0].actions[0])
        let chosen = store.draft.action
        store.selectSection(hogar)
        XCTAssertEqual(store.draft.action, chosen)
        XCTAssertNotNil(chosen)
    }

    func testChangingScreenResetsActionAndActionsFollowScreen() {
        let store = filledStore()
        XCTAssertEqual(store.draft.action, "Nueva lista")
        let tareas = FeedbackCatalog.section(named: "Tareas")!.screen(named: "Tareas")!
        store.selectScreen(tareas)
        XCTAssertNil(store.draft.action)
        XCTAssertEqual(store.actions, tareas.actions)
        store.selectAction("Nueva lista") // de otra pantalla: se ignora
        XCTAssertNil(store.draft.action)
    }

    func testSingleActionScreenAutoSelects() {
        let store = FeedbackStore(send: { _ in })
        store.selectSection(FeedbackCatalog.section(named: "General / otro")!)
        store.selectScreen(store.screens[0])
        XCTAssertEqual(store.actions, ["General"])
        XCTAssertEqual(store.draft.action, "General")
    }

    func testAccessAndGeneralSectionsAreSendable() async {
        for (sectionName, screenName) in [("Acceso", "No tienes ningún hogar"), ("General / otro", "Otro")] {
            var received: FeedbackRequest?
            let store = FeedbackStore(send: { received = $0 })
            let section = FeedbackCatalog.section(named: sectionName)!
            store.selectSection(section)
            store.selectScreen(section.screen(named: screenName)!)
            store.selectAction(store.actions[0])
            store.selectKind(.bug)
            store.text = "Algo"
            let ok = await store.submit()
            XCTAssertTrue(ok, sectionName)
            XCTAssertEqual(received?.seccion, sectionName)
            XCTAssertEqual(received?.subseccion, "\(screenName): \(store.actions[0])")
        }
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
        XCTAssertEqual(received, FeedbackRequest(seccion: "Tareas", subseccion: "Listas: Nueva lista", tipo: "mejora",
                                                 texto: "Quiero ordenar listas"))
    }

    func testResetClearsDraftAfterSend() async {
        let store = filledStore { _ in }
        _ = await store.submit()
        store.reset()
        XCTAssertEqual(store.draft, FeedbackDraft())
        XCTAssertFalse(store.didSend)
        XCTAssertNil(store.errorMessage)
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
        XCTAssertEqual(store.draft.screenName, "Listas")
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
