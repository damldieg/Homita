import XCTest
@testable import ControlKit

/// Regla del selector de personas al crear (0038, AC-3): solo con cuenta y acceso a la lista.
final class TaskAssigneesTests: XCTestCase {
    private func person(_ id: Int, _ name: String, account: Int?, home: Int? = nil) throws -> PersonEntry {
        let account = account.map { ",\"app_user_id\":\($0)" } ?? ""
        let home = home.map { ",\"home_id\":\($0)" } ?? ""
        let json = "{\"id\":\(id),\"user_id\":1,\"name\":\"\(name)\",\"color\":\"#FF0000\"\(account)\(home)}"
        return try decodeFixture(PersonEntry.self, json)
    }

    private func member(_ userId: Int, role: String = "viewer") throws -> MemberEntry {
        try decodeFixture(MemberEntry.self, #"{"tlu_id":\#(userId),"user_id":\#(userId),"name":"U","email":"u@homita.example","role":"\#(role)"}"#)
    }

    func testAssignableNeedsAccountAndAccess() throws {
        let persons = [try person(1, "Ana", account: 1), try person(2, "Beto", account: 9),
                       try person(3, "Luz", account: nil), try person(4, "Cris", account: 5)]
        let members = [try member(1, role: "owner"), try member(5)]
        XCTAssertEqual(TaskAssignees.assignable(persons: persons, members: members).map(\.name), ["Ana", "Cris"],
                       "sin cuenta (Luz) y sin ACL (Beto) quedan fuera; cualquier rol vale")
    }

    func testAssignableHasNoDuplicates() throws {
        let ana = try person(1, "Ana", account: 1)
        XCTAssertEqual(TaskAssignees.assignable(persons: [ana, ana], members: [try member(1), try member(1)]).map(\.id), [1])
    }

    func testAssignableWithoutMembersIsEmpty() throws {
        XCTAssertTrue(TaskAssignees.assignable(persons: [try person(1, "Ana", account: 1)], members: []).isEmpty)
    }

    func testLocalListOnlyOffersCurrentUser() throws {
        let persons = [try person(1, "Ana", account: 1), try person(2, "Beto", account: 9), try person(3, "Luz", account: nil)]
        XCTAssertEqual(TaskAssignees.assignableInLocalList(persons: persons, currentUserId: 9).map(\.name), ["Beto"])
        XCTAssertTrue(TaskAssignees.assignableInLocalList(persons: persons, currentUserId: nil).isEmpty)
    }

    func testSplitKeepsOrderAndTreatsUnknownAsRemoved() throws {
        let persons = [try person(1, "Ana", account: 1), try person(2, "Beto", account: 9), try person(3, "Luz", account: nil)]
        let result = TaskAssignees.split(personIds: [3, 1, 42, 2], persons: persons, members: [try member(1)])
        XCTAssertEqual(result.kept, [1])
        XCTAssertEqual(result.removed, [3, 42, 2])
    }

    func testPruneKeepsOnlyAssignableWithoutRepeats() throws {
        let assignable = [try person(1, "Ana", account: 1), try person(4, "Cris", account: 5)]
        XCTAssertEqual(TaskAssignees.prune(selected: [4, 2, 4, 1], assignable: assignable), [4, 1])
        XCTAssertEqual(TaskAssignees.prune(selected: [2], assignable: []), [])
    }

    func testOneOptionPerAccountKeepsFirstPerson() throws {
        // Cinco personas distintas con la misma cuenta (caso "Familia Demo" repetida) y una sin cuenta.
        let persons = try (10...14).map { try person($0, "Familia Demo", account: 7) } + [try person(20, "Luz", account: nil)]
        let assignable = TaskAssignees.assignable(persons: persons, members: [try member(7)])
        XCTAssertEqual(assignable.map(\.id), [10], "una sola opción por cuenta: la primera; Luz sin cuenta fuera")
        XCTAssertEqual(TaskAssignees.assignableInLocalList(persons: persons, currentUserId: 7).map(\.id), [10])
        let result = TaskAssignees.split(personIds: [12, 10, 20], persons: persons, members: [try member(7)])
        XCTAssertEqual(result.kept, [10])
        XCTAssertEqual(result.removed, [12, 20])
        XCTAssertEqual(TaskAssignees.prune(selected: [11, 10, 13, 10], assignable: assignable), [10],
                       "la selección no queda con dos ids de la misma cuenta")
    }

    // MARK: R1-02 · una cuenta en dos hogares

    func testHomeIdIsDecodedAndOptional() throws {
        XCTAssertEqual(try person(1, "Ana", account: 1, home: 3).home_id, 3)
        XCTAssertNil(try person(1, "Ana", account: 1).home_id, "sin la clave (antes de 0038) decodifica igual")
    }

    func testAccountInTwoHomesOffersOnePersonPerHome() throws {
        // La cuenta 7 tiene persona en el hogar 1 (id 10) y en el 2 (id 20); en el hogar 1 hay además
        // una persona repetida de la misma cuenta (id 11).
        let persons = [try person(20, "Ana", account: 7, home: 2), try person(10, "Ana", account: 7, home: 1),
                       try person(11, "Ana", account: 7, home: 1), try person(30, "Beto", account: 8, home: 1)]
        let members = [try member(7), try member(8)]
        XCTAssertEqual(TaskAssignees.assignable(persons: persons, members: members).map(\.id), [20, 10, 30],
                       "cada hogar ofrece su persona; el repetido del mismo hogar queda fuera")
        XCTAssertEqual(TaskAssignees.assignableInLocalList(persons: persons, currentUserId: 7).map(\.id), [20, 10],
                       "lista local: la persona de la cuenta en cada hogar")
    }

    func testSplitDoesNotMixHomes() throws {
        let persons = [try person(20, "Ana", account: 7, home: 2), try person(10, "Ana", account: 7, home: 1),
                       try person(11, "Ana", account: 7, home: 1)]
        let members = [try member(7)]
        // La persona del hogar 1 es válida aunque la del hogar 2 vaya antes en `persons`.
        XCTAssertEqual(TaskAssignees.split(personIds: [10], persons: persons, members: members).kept, [10])
        let result = TaskAssignees.split(personIds: [11, 10, 20], persons: persons, members: members)
        XCTAssertEqual(result.kept, [10, 20], "cada hogar conserva su persona")
        XCTAssertEqual(result.removed, [11], "solo cae el repetido del mismo hogar")
    }

    func testPruneDoesNotMixHomes() throws {
        let persons = [try person(20, "Ana", account: 7, home: 2), try person(10, "Ana", account: 7, home: 1),
                       try person(11, "Ana", account: 7, home: 1)]
        let assignable = TaskAssignees.assignable(persons: persons, members: [try member(7)])
        XCTAssertEqual(TaskAssignees.prune(selected: [10], assignable: assignable), [10],
                       "la persona del hogar 1 no se sustituye por la del hogar 2")
        XCTAssertEqual(TaskAssignees.prune(selected: [20, 11, 10, 20], assignable: assignable), [20, 10])
    }

    func testWithoutHomeIdKeepsOneOptionPerAccount() throws {
        // Servidor anterior a 0038: sin home_id todas cuentan como el mismo hogar (comportamiento previo).
        let persons = [try person(20, "Ana", account: 7), try person(10, "Ana", account: 7)]
        XCTAssertEqual(TaskAssignees.assignable(persons: persons, members: [try member(7)]).map(\.id), [20])
    }

    // MARK: asignar-alta-lista · solo personas del hogar de la lista

    func testListHomeOnlyOffersPersonsOfThatHome() throws {
        // Lista del hogar 1. Las cuentas 7 y 8 están en el ACL; la 7 tiene persona en ambos hogares
        // y la 9 (Cris) solo en el hogar 2.
        let persons = [try person(20, "Ana", account: 7, home: 2), try person(10, "Ana", account: 7, home: 1),
                       try person(30, "Beto", account: 8, home: 1), try person(40, "Cris", account: 9, home: 2),
                       try person(50, "Dani", account: 8)]
        let members = [try member(7), try member(8), try member(9)]
        let assignable = TaskAssignees.assignable(persons: persons, members: members, homeId: 1)
        XCTAssertEqual(assignable.map(\.id), [10, 30], "el selector no ofrece personas de otro hogar ni sin hogar")
        XCTAssertEqual(TaskAssignees.assignableInLocalList(persons: persons, currentUserId: 7, homeId: 1).map(\.id), [10],
                       "lista local: solo la persona del hogar de la lista")
        let result = TaskAssignees.split(personIds: [20, 10, 40, 30], persons: persons, members: members, homeId: 1)
        XCTAssertEqual(result.kept, [10, 30])
        XCTAssertEqual(result.removed, [20, 40], "split no acepta ids de otro hogar")
        XCTAssertEqual(TaskAssignees.prune(selected: [20, 10, 40, 30], assignable: assignable), [10, 30],
                       "prune quita los ids de otro hogar")
    }

    func testListHomeIdIsDecodedAndOptional() throws {
        let base = ##""id":1,"name":"Compra","color":"#FF0000","sort":"custom""##
        XCTAssertEqual(try decodeFixture(TaskListEntry.self, "{\(base),\"home_id\":3}").home_id, 3)
        XCTAssertNil(try decodeFixture(TaskListEntry.self, "{\(base)}").home_id, "sin la clave decodifica igual")
    }
}

/// R1-03: editar sin conexión una tarea local no vacía la selección (sin roster no se poda).
@MainActor
final class TaskAssigneeLoaderRosterTests: XCTestCase {
    nonisolated private static func route(_ request: URLRequest) -> String {
        let path = request.url?.path ?? ""
        return path.range(of: "/functions/v1/api/").map { String(path[$0.upperBound...]) } ?? path
    }

    private static let roster = ##"[{"id":1,"user_id":1,"name":"Ana","color":"#FF0000","app_user_id":1},{"id":2,"user_id":1,"name":"Beto","color":"#00FF00","app_user_id":9}]"##

    private func makeLoader(_ stubs: [String: StubURLProtocol.Stub]) -> TaskAssigneeLoader {
        StubURLProtocol.reset { request in stubs[Self.route(request)] ?? .offline }
        let client = makeTestClient()
        return TaskAssigneeLoader(persons: PersonRepository(client: client), taskLists: TaskListRepository(client: client))
    }

    func testPruneWithoutRosterKeepsSelection() throws {
        XCTAssertEqual(TaskAssignees.prune(selected: [2, 1], assignable: [], rosterLoaded: false), [2, 1],
                       "sin roster no se poda")
        let ana = try decodeFixture(PersonEntry.self, ##"{"id":1,"user_id":1,"name":"Ana","color":"#FF0000","app_user_id":1}"##)
        XCTAssertEqual(TaskAssignees.prune(selected: [2, 1], assignable: [ana], rosterLoaded: true), [1])
    }

    func testOfflineLoadReportsNoRosterAndSelectionSurvives() async {
        // Sin red y sin caché: fallan `GET person` y `GET task-list/user`.
        let loader = makeLoader([:])
        let loaded = await loader.load(listId: 2)
        XCTAssertFalse(loaded)
        XCTAssertTrue(loader.assignable(listId: 2, currentUserId: 1).isEmpty)
        let selection = TaskAssignees.prune(selected: [1, 2], assignable: loader.assignable(listId: 2, currentUserId: 1),
                                            rosterLoaded: loaded)
        XCTAssertEqual(selection, [1, 2], "la tarea local conserva sus personas al editarla sin conexión")
    }

    func testMembersFailureAloneAlsoKeepsSelection() async {
        let loader = makeLoader(["person": StubURLProtocol.Stub(json: Self.roster)])
        let loaded = await loader.load(listId: 2)
        XCTAssertFalse(loaded, "personas sí, miembros no: no hay roster de la lista")
        XCTAssertFalse(loader.hasRoster(listId: 2))
    }

    func testLoadedRosterPrunes() async {
        let loader = makeLoader([
            "person": StubURLProtocol.Stub(json: Self.roster),
            "task-list/user": StubURLProtocol.Stub(json: #"[{"tlu_id":10,"user_id":1,"name":"Demo","email":"demo@homita.example","role":"owner"}]"#)
        ])
        let loaded = await loader.load(listId: 2)
        XCTAssertTrue(loaded)
        XCTAssertEqual(TaskAssignees.prune(selected: [1, 2], assignable: loader.assignable(listId: 2, currentUserId: 1),
                                           rosterLoaded: loaded), [1])
    }

    func testLoaderOffersOnlyPersonsOfListHome() async {
        let roster = ##"[{"id":1,"user_id":1,"name":"Ana","color":"#FF0000","app_user_id":1,"home_id":2},{"id":3,"user_id":1,"name":"Ana","color":"#FF0000","app_user_id":1,"home_id":1}]"##
        let loader = makeLoader([
            "person": StubURLProtocol.Stub(json: roster),
            "task-list/user": StubURLProtocol.Stub(json: #"[{"tlu_id":10,"user_id":1,"name":"Demo","email":"demo@homita.example","role":"owner"}]"#)
        ])
        _ = await loader.load(listId: 2)
        let list = try? decodeFixture(TaskListEntry.self, ##"{"id":2,"name":"Compra","color":"#FF0000","sort":"custom","home_id":1}"##)
        let homeId = loader.homeId(listId: 2, lists: list.map { [$0] } ?? [], fallbackHomeId: 2)
        XCTAssertEqual(homeId, 1, "manda el home_id de la lista sobre el hogar activo")
        XCTAssertEqual(loader.assignable(listId: 2, currentUserId: 1, homeId: homeId).map(\.id), [3])
        XCTAssertEqual(loader.homeId(listId: -1, lists: [], fallbackHomeId: 2), 2, "lista local: hogar activo")
    }
}
