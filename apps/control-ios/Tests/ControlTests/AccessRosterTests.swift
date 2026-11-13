import XCTest
@testable import ControlKit

/// Permisos de edición por calendario y lista (0029): decodificación de `can_edit`, filas del
/// selector (solo cuentas, solo owner cambia), forma de las peticiones y mensaje del 403.
final class AccessRosterTests: XCTestCase {
    private func member(_ id: Int, _ name: String, role: String, canEdit: Bool? = nil) throws -> MemberEntry {
        let extra = canEdit.map { #","can_edit":\#($0)"# } ?? ""
        return try decodeFixture(
            MemberEntry.self,
            #"{"cu_id":\#(id),"user_id":\#(id),"name":"\#(name)","email":"\#(name.lowercased())@homita.example","role":"\#(role)"\#(extra)}"#
        )
    }

    private func person(_ id: Int, _ name: String, account: Int?) throws -> PersonEntry {
        let acc = account.map { #","app_user_id":\#($0)"# } ?? ""
        return try decodeFixture(
            PersonEntry.self, ##"{"id":\##(id),"user_id":1,"name":"\##(name)","color":"#112233"\##(acc)}"##)
    }

    // MARK: - Decodificación

    func testMemberAccessLevelFromCanEdit() throws {
        XCTAssertEqual(try member(1, "Ana", role: "owner", canEdit: true).accessLevel, .owner)
        XCTAssertEqual(try member(2, "Bea", role: "viewer", canEdit: true).accessLevel, .edit)
        XCTAssertEqual(try member(3, "Cai", role: "viewer", canEdit: false).accessLevel, .read)
        // Servidor previo a 0029 (sin la clave): viewer = lectura, como se mostraba hasta ahora.
        XCTAssertEqual(try member(4, "Dan", role: "viewer").accessLevel, .read)
    }

    func testCalendarAndListCanEditDefaultsToEdit() throws {
        let calendar = try decodeFixture(CalendarEntry.self, ##"{"id":3,"name":"Familia","color":"#6923E2","can_edit":0}"##)
        XCTAssertFalse(calendar.canEdit)
        let list = try decodeFixture(TaskListEntry.self, ##"{"id":4,"name":"Compra","color":"#6923E2","sort":"title","can_edit":true}"##)
        XCTAssertTrue(list.canEdit)
        // Sin la clave no se ocultan acciones: el servidor decide con 403.
        let legacy = try decodeFixture(CalendarEntry.self, ##"{"id":3,"name":"Familia","color":"#6923E2"}"##)
        XCTAssertTrue(legacy.canEdit)
    }

    func testAccessLevelChoicesExcludeOwner() {
        XCTAssertEqual(AccessLevel.choices, [.read, .edit])
        XCTAssertFalse(AccessLevel.read.canEdit)
        XCTAssertTrue(AccessLevel.edit.canEdit)
        XCTAssertTrue(AccessLevel.owner.canEdit)
    }

    // MARK: - Filas del selector

    func testOwnerSeesSelectorForOthersButNotForSelfOrOtherOwners() throws {
        let members = [
            try member(1, "Ana", role: "owner"),
            try member(2, "Bea", role: "viewer", canEdit: true),
            try member(3, "Cai", role: "owner"),
        ]
        let rows = AccessRoster.rows(members: members, persons: [], currentUserId: 1)
        XCTAssertEqual(rows.map(\.userId), [1, 2, 3])
        XCTAssertEqual(rows.map(\.isEditable), [false, true, false])
        XCTAssertTrue(rows[0].isCurrentUser)
        XCTAssertTrue(AccessRoster.callerIsOwner(1, in: members))
    }

    func testViewerSeesOwnPermissionButNoSelector() throws {
        let members = [try member(1, "Ana", role: "owner"), try member(2, "Bea", role: "viewer", canEdit: false)]
        XCTAssertFalse(AccessRoster.callerIsOwner(2, in: members))
        XCTAssertEqual(AccessRoster.level(of: 2, in: members), .read)
        let rows = AccessRoster.rows(members: members, persons: [try person(1, "Cai", account: 9)], currentUserId: 2)
        XCTAssertEqual(rows.map(\.isEditable), [false, false])
        XCTAssertEqual(rows.map(\.userId), [1, 2], "el no-owner no ve cuentas sin acceso")
    }

    func testMembersWithoutAccountNeverAppear() throws {
        let members = [try member(1, "Ana", role: "owner")]
        let persons = [
            try person(10, "Peque", account: nil),
            try person(11, "Luna", account: nil),
            try person(12, "Bea", account: 2),
        ]
        let rows = AccessRoster.rows(members: members, persons: persons, currentUserId: 1)
        XCTAssertEqual(rows.map(\.name), ["Ana", "Bea"])
        XCTAssertNil(rows[1].level, "la cuenta del hogar sin acceso aparece sin permiso")
        XCTAssertFalse(rows[1].hasAccess)
        XCTAssertTrue(rows[1].isEditable)
    }

    func testAccountAppearsOnceAndOwnPersonIsNotOffered() throws {
        let members = [try member(1, "Ana", role: "owner"), try member(2, "Bea", role: "viewer", canEdit: false)]
        let persons = [
            try person(10, "Ana (persona)", account: 1),
            try person(11, "Bea (persona)", account: 2),
            try person(12, "Cai", account: 3),
            try person(13, "Cai otra vez", account: 3),
        ]
        let rows = AccessRoster.rows(members: members, persons: persons, currentUserId: 1)
        XCTAssertEqual(rows.map(\.userId), [1, 2, 3])
        XCTAssertEqual(rows[2].name, "Cai")
    }

    func testCandidatesSortedByName() throws {
        let members = [try member(1, "Ana", role: "owner")]
        let persons = [try person(10, "zoe", account: 5), try person(11, "Bruno", account: 6)]
        let rows = AccessRoster.rows(members: members, persons: persons, currentUserId: 1)
        XCTAssertEqual(rows.dropFirst().map(\.name), ["Bruno", "zoe"])
    }

    // MARK: - Peticiones y errores

    func testSetAccessRequestShapes() async throws {
        StubURLProtocol.reset { _ in
            StubURLProtocol.Stub(json: #"{"cu_id":5,"user_id":2,"name":"Bea","email":"bea@homita.example","role":"viewer","can_edit":true}"#)
        }
        let client = makeTestClient()
        let calendar = try await CalendarRepository(client: client).setAccess(calendarId: 3, userId: 2, canEdit: true)
        XCTAssertEqual(calendar.accessLevel, .edit)
        var request = try XCTUnwrap(StubURLProtocol.requests.last)
        XCTAssertEqual(request.httpMethod, "PATCH")
        XCTAssertEqual(request.url?.path.hasSuffix("/calendar/user"), true)
        XCTAssertEqual(String(data: try XCTUnwrap(request.capturedBody), encoding: .utf8),
                       #"{"calendar_id":3,"can_edit":true,"user_id":2}"#.sortedKeysJSON)

        _ = try await TaskListRepository(client: client).setAccess(taskListId: 4, userId: 2, canEdit: false)
        request = try XCTUnwrap(StubURLProtocol.requests.last)
        XCTAssertEqual(request.httpMethod, "PATCH")
        XCTAssertEqual(request.url?.path.hasSuffix("/task-list/user"), true)
        XCTAssertEqual(String(data: try XCTUnwrap(request.capturedBody), encoding: .utf8),
                       #"{"task_list_id":4,"can_edit":false,"user_id":2}"#.sortedKeysJSON)
    }

    func testWriteMessageForNotAllowedIsClearAndOthersKeepUserMessage() {
        let forbidden = APIError.http(status: 403, message: "Not Allowed")
        XCTAssertTrue(forbidden.writeMessage.contains("permiso de edición"))
        XCTAssertEqual(APIError.network("x").writeMessage, APIError.network("x").userMessage)
        XCTAssertEqual(APIError.http(status: 400, message: "Color must be #RRGGBB").writeMessage,
                       "El color debe ser #RRGGBB")
    }

    func testCalendarStoreSetAccessForbiddenShowsToastWithoutRetry() async throws {
        StubURLProtocol.reset { _ in StubURLProtocol.Stub(status: 403, json: #"{"error":"Not Allowed"}"#) }
        let store = CalendarStore(repo: CalendarRepository(client: makeTestClient()))
        await store.setAccess(calendarId: 3, userId: 2, level: .edit)
        let failure = try XCTUnwrap(store.writeFailure)
        XCTAssertTrue(failure.message.contains("permiso de edición"))
        XCTAssertNil(failure.retry, "un 403 no se reintenta")
        XCTAssertNil(store.errorMessage)
    }

    func testStoreSetAccessSendsCanEditAndReloadsMembers() async throws {
        StubURLProtocol.reset { request in
            if request.httpMethod == "GET" {
                return StubURLProtocol.Stub(json: #"[{"cu_id":1,"user_id":1,"name":"Ana","email":"ana@homita.example","role":"owner","can_edit":true},{"cu_id":5,"user_id":2,"name":"Bea","email":"bea@homita.example","role":"viewer","can_edit":true}]"#)
            }
            return StubURLProtocol.Stub(json: #"{"cu_id":5,"user_id":2,"name":"Bea","email":"bea@homita.example","role":"viewer","can_edit":true}"#)
        }
        let store = CalendarStore(repo: CalendarRepository(client: makeTestClient()))
        store.currentUserId = 1
        await store.setAccess(calendarId: 3, userId: 2, level: .edit)
        XCTAssertNil(store.writeFailure)
        XCTAssertEqual(store.members.map(\.accessLevel), [.owner, .edit])
        XCTAssertEqual(store.accessRows.map(\.isEditable), [false, true])
        XCTAssertEqual(StubURLProtocol.requests.map(\.httpMethod), ["PATCH", "GET"])
    }
}

private extension String {
    /// El encoder de la app ordena las claves: normaliza el literal esperado igual.
    var sortedKeysJSON: String {
        guard let data = data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let sorted = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return self }
        return String(decoding: sorted, as: UTF8.self)
    }
}
