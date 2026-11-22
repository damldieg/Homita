import XCTest
@testable import ControlKit

/// Regla del selector de personas al crear (0038, AC-3): solo con cuenta y acceso a la lista.
final class TaskAssigneesTests: XCTestCase {
    private func person(_ id: Int, _ name: String, account: Int?) throws -> PersonEntry {
        let account = account.map { ",\"app_user_id\":\($0)" } ?? ""
        let json = "{\"id\":\(id),\"user_id\":1,\"name\":\"\(name)\",\"color\":\"#FF0000\"\(account)}"
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
}
