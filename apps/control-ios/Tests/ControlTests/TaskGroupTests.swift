import XCTest
@testable import ControlKit

/// Agrupación de tareas por lista (orden de listas y conteo).
final class TaskGroupTests: XCTestCase {
    private func list(_ id: Int, _ name: String) throws -> TaskListEntry {
        try JSONDecoder().decode(TaskListEntry.self, from: Data(
            ##"{"id":\##(id),"name":"\##(name)","color":"#112233","sort":"updated_at"}"##.utf8))
    }

    private func task(_ id: Int, list: Int, done: Bool = false) throws -> TaskEntry {
        let completed = done ? #""2026-01-01 10:00:00""# : "null"
        return try JSONDecoder().decode(TaskEntry.self, from: Data(
            #"{"id":\#(id),"task_list_id":\#(list),"title":"t\#(id)","completed_at":\#(completed),"task_list_name":"Ext"}"#.utf8))
    }

    func testGroupsFollowListOrderAndCount() throws {
        let lists = [try list(1, "Casa"), try list(2, "Compra"), try list(3, "Vacía")]
        let tasks = [try task(1, list: 2), try task(2, list: 1, done: true), try task(3, list: 1)]
        let groups = TaskGroup.group(tasks: tasks, lists: lists)
        XCTAssertEqual(groups.map(\.name), ["Casa", "Compra"])
        XCTAssertEqual(groups.map(\.count), [2, 1])
        XCTAssertEqual(groups[0].tasks.map(\.id), [3, 2]) // pendientes antes que completadas
    }

    func testUnknownListAppendedWithTaskName() throws {
        let groups = TaskGroup.group(tasks: [try task(1, list: 9)], lists: [try list(1, "Casa")])
        XCTAssertEqual(groups.map(\.name), ["Ext"])
    }
}
