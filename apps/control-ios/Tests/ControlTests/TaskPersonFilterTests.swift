import XCTest
@testable import ControlKit

/// Filtro por persona en cliente («Mis tareas» y persona del hogar), puro.
final class TaskPersonFilterTests: XCTestCase {
    private func person(_ id: Int, _ name: String, account: Int?) throws -> PersonEntry {
        let account = account.map { ",\"app_user_id\":\($0)" } ?? ""
        return try decodeFixture(PersonEntry.self, "{\"id\":\(id),\"user_id\":1,\"name\":\"\(name)\",\"color\":\"#FF0000\"\(account)}")
    }

    private func task(_ id: Int, persons: [PersonEntry]?, priority: String? = nil) -> TaskEntry {
        TaskEntry(id: id, task_list_id: 1, title: "T\(id)", completed_at: nil, created_at: nil, updated_at: nil,
                  order: nil, task_list_color: nil, task_list_name: nil, persons: persons, priority: priority)
    }

    private var ana: PersonEntry { get throws { try person(1, "Ana", account: 1) } }
    private var beto: PersonEntry { get throws { try person(2, "Beto", account: 9) } }

    /// Como `GET task`: las personas de la tarea no traen `app_user_id`.
    private func bare(_ id: Int) throws -> PersonEntry { try person(id, "X", account: nil) }

    func testNilFilterReturnsAll() throws {
        let tasks = [task(1, persons: nil), task(2, persons: [try bare(1)])]
        XCTAssertEqual(TaskPersonFiltering.apply(tasks, filter: nil, roster: [], currentUserId: nil), tasks)
    }

    func testMineResolvesByRosterEvenWithoutAppUserIdInTask() throws {
        let roster = [try ana, try beto]
        let tasks = [task(1, persons: [try bare(1)]), task(2, persons: [try bare(2)]), task(3, persons: [try bare(2), try bare(1)])]
        let result = TaskPersonFiltering.apply(tasks, filter: .mine, roster: roster, currentUserId: 1)
        XCTAssertEqual(result.map(\.id), [1, 3])
    }

    func testMineWithoutUserOrLinkedPersonIsEmpty() throws {
        let roster = [try ana, try beto]
        let tasks = [task(1, persons: [try bare(1)])]
        XCTAssertTrue(TaskPersonFiltering.apply(tasks, filter: .mine, roster: roster, currentUserId: nil).isEmpty)
        XCTAssertTrue(TaskPersonFiltering.apply(tasks, filter: .mine, roster: roster, currentUserId: 77).isEmpty)
        XCTAssertTrue(TaskPersonFiltering.apply(tasks, filter: .mine, roster: [], currentUserId: 1).isEmpty)
    }

    func testPersonFilter() throws {
        let tasks = [task(1, persons: [try bare(1)]), task(2, persons: [try bare(2)]), task(3, persons: [try bare(1), try bare(2)])]
        XCTAssertEqual(TaskPersonFiltering.apply(tasks, filter: .person(2), roster: [], currentUserId: nil).map(\.id), [2, 3])
    }

    func testTasksWithoutPersonsAreExcluded() throws {
        let tasks = [task(1, persons: nil), task(2, persons: []), task(3, persons: [try bare(2)])]
        XCTAssertEqual(TaskPersonFiltering.apply(tasks, filter: .person(2), roster: [], currentUserId: nil).map(\.id), [3])
        XCTAssertTrue(TaskPersonFiltering.apply(tasks, filter: .mine, roster: [try ana], currentUserId: 1).isEmpty)
    }

    func testKeepsOriginalOrder() throws {
        let tasks = [task(5, persons: [try bare(1)]), task(2, persons: [try bare(1)]), task(9, persons: [try bare(1)])]
        XCTAssertEqual(TaskPersonFiltering.apply(tasks, filter: .person(1), roster: [], currentUserId: nil).map(\.id), [5, 2, 9])
    }

    func testComposesWithPriorityFilter() throws {
        let tasks = [task(1, persons: [try bare(1)], priority: "alta"), task(2, persons: [try bare(1)], priority: "baja"),
                     task(3, persons: [try bare(2)], priority: "alta")]
        let byPerson = TaskPersonFiltering.apply(tasks, filter: .person(1), roster: [], currentUserId: nil)
        XCTAssertEqual(TaskPriorityOrdering.apply(byPerson, sort: .priority, filter: .alta).map(\.id), [1])
    }
}
