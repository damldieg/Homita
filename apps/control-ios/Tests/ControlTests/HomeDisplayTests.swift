import XCTest
@testable import ControlKit

/// Pantallas del hogar (dashboard-pantalla-hogar): decodificación, forma de las peticiones y mensajes de la
/// vinculación. Sin red: `StubURLProtocol` responde según la ruta.
final class HomeDisplayTests: XCTestCase {
    private let displayJSON = """
    {"id": 3, "name": "Salón", "settings": {"brightness": 0.5,
      "schedule": {"enabled": true, "weekdayOn": 420, "weekdayOff": 1380, "weekendOn": 510, "weekendOff": 1410, "screenOff": false},
      "location": {"name": "Madrid", "detail": "Comunidad de Madrid, España", "latitude": 40.4165, "longitude": -3.70256}},
      "last_seen_at": "2026-11-27 11:20:00", "calendar_ids": [1, 2], "task_list_ids": [2]}
    """

    func testDisplayDecodesSnakeCaseAndNestedSettings() throws {
        let display = try JSONDecoder().decode(HomeDisplay.self, from: Data(displayJSON.utf8))
        XCTAssertEqual(display.id, 3)
        XCTAssertEqual(display.calendarIds, [1, 2])
        XCTAssertEqual(display.taskListIds, [2])
        XCTAssertEqual(display.lastSeenAt, "2026-11-27 11:20:00")
        XCTAssertEqual(display.settings.brightness, 0.5)
        XCTAssertEqual(display.settings.schedule?.weekdayOn, 420)
        XCTAssertEqual(display.settings.location?.name, "Madrid")
    }

    func testDisplayDecodesChannelAndVersionFromTheListAndAcceptsOlderServers() throws {
        let withVersion = displayJSON.replacingOccurrences(of: #""task_list_ids": [2]}"#,
            with: #""task_list_ids": [2], "update_channel": "pruebas", "app_version_code": 4, "app_version_name": "1.3", "last_update_result": "instalada 4"}"#)
        let display = try JSONDecoder().decode(HomeDisplay.self, from: Data(withVersion.utf8))
        XCTAssertEqual(display.updateChannel, "pruebas")
        XCTAssertEqual(display.appVersionCode, 4)
        XCTAssertEqual(display.appVersionName, "1.3")
        XCTAssertEqual(display.lastUpdateResult, "instalada 4")
        // Un servidor anterior a 0053 no manda los campos: se decodifica igual
        let old = try JSONDecoder().decode(HomeDisplay.self, from: Data(displayJSON.utf8))
        XCTAssertNil(old.updateChannel)
        XCTAssertNil(old.appVersionCode)
    }

    func testUpdateBodyOmitsNilFieldsAndUsesSnakeKeysForSelection() throws {
        let body = UpdateDisplayBody(id: 3, name: nil, settings: nil, calendarIds: [1], taskListIds: nil)
        // Comparación por contenido: JSONEncoder no garantiza el orden de las claves.
        let object = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(body)) as? [String: Any]
        XCTAssertEqual(object?["id"] as? Int, 3)
        XCTAssertEqual(object?["calendar_ids"] as? [Int], [1])
        XCTAssertEqual(object?.count, 2)
    }

    func testUpdateSendsSettingsAndSelectionWithHomeHeader() async throws {
        // Respuesta real del servidor (R1-02): solo el id, no la pantalla completa
        StubURLProtocol.reset { _ in StubURLProtocol.Stub(json: #"{"id": 3}"#) }
        let repo = HomeRepository(client: makeTestClient())
        let settings = DisplaySettings(brightness: nil, schedule: .standard, location: nil)
        let saved = try await repo.updateDisplay(UpdateDisplayBody(id: 3, name: "Salón", settings: settings, calendarIds: [1], taskListIds: []))
        XCTAssertEqual(saved.id, 3)
        let sent = try XCTUnwrap(StubURLProtocol.requests.last)
        XCTAssertEqual(sent.httpMethod, "PATCH")
        XCTAssertTrue(sent.url?.path.hasSuffix("/api/home/display/update") == true)
        let body = String(data: try XCTUnwrap(sent.capturedBody), encoding: .utf8) ?? ""
        XCTAssertTrue(body.contains(#""calendar_ids":[1]"#))
        XCTAssertTrue(body.contains(#""task_list_ids":[]"#))
        XCTAssertTrue(body.contains(#""weekdayOn":420"#))
    }

    func testLinkConfirmSendsCodeAndName() async throws {
        StubURLProtocol.reset { _ in StubURLProtocol.Stub(status: 201, json: #"{"id": 9, "name": "Salón", "home_id": 1}"#) }
        let linked = try await HomeRepository(client: makeTestClient()).confirmDisplayLink(code: "123456", name: "Salón")
        let sent = try XCTUnwrap(StubURLProtocol.requests.last)
        XCTAssertTrue(sent.url?.path.hasSuffix("/api/home/display/link-confirm") == true)
        XCTAssertEqual(String(data: try XCTUnwrap(sent.capturedBody), encoding: .utf8), #"{"code":"123456","name":"Salón"}"#)
        XCTAssertEqual(linked, DisplayLinked(id: 9, name: "Salón", homeId: 1))
    }

    func testRevokeDecodesResult() async throws {
        StubURLProtocol.reset { _ in StubURLProtocol.Stub(json: #"{"id": 3, "revoked": true}"#) }
        let result = try await HomeRepository(client: makeTestClient()).revokeDisplay(id: 3)
        XCTAssertEqual(result, RevokedDisplay(id: 3, revoked: true))
    }

    @MainActor
    func testLinkMessagesFollowTheServerError() async {
        StubURLProtocol.reset { _ in StubURLProtocol.Stub(status: 400, json: #"{"error": "Invalid link code"}"#) }
        let store = DisplaysStore(repo: HomeRepository(client: makeTestClient()), homeId: 1, activeHomeId: { "1" })
        let linked = await store.link(code: "123456", name: "Salón")
        XCTAssertFalse(linked)
        XCTAssertEqual(store.lastError, "El código no es válido o ha caducado. Mira la pantalla y escribe el que aparece.")

        StubURLProtocol.reset { _ in StubURLProtocol.Stub(status: 429, json: #"{"error": "Too many attempts"}"#) }
        _ = await store.link(code: "123456", name: "Salón")
        XCTAssertEqual(store.lastError, "Demasiados intentos. Espera unos minutos.")
    }
}
