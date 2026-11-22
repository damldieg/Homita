import XCTest
@testable import ControlKit

/// Lista inicial del editor de tareas: fijada desde la cabecera de un grupo (sin selector).
final class TaskEditorListTests: XCTestCase {
    private func list(_ id: Int) throws -> TaskListEntry {
        try decodeFixture(TaskListEntry.self, "{\"id\":\(id),\"name\":\"L\(id)\",\"color\":\"#FF0000\",\"sort\":\"custom\"}")
    }

    private func task(listId: Int) throws -> TaskEntry {
        try decodeFixture(TaskEntry.self, #"{"id":1,"task_list_id":\#(listId),"title":"T"}"#)
    }

    func testCreateWithExistingInitialListIsLocked() throws {
        let r = TaskEditorView.resolveListId(task: nil, initialListId: 2, taskLists: [try list(1), try list(2)])
        XCTAssertEqual(r.listId, 2)
        XCTAssertTrue(r.isLocked)
    }

    func testCreateWithoutInitialListUsesFirst() throws {
        let r = TaskEditorView.resolveListId(task: nil, initialListId: nil, taskLists: [try list(1), try list(2)])
        XCTAssertEqual(r.listId, 1)
        XCTAssertFalse(r.isLocked)
    }

    func testMissingInitialListFallsBackToFirst() throws {
        let r = TaskEditorView.resolveListId(task: nil, initialListId: 9, taskLists: [try list(1), try list(2)])
        XCTAssertEqual(r.listId, 1)
        XCTAssertFalse(r.isLocked)
    }

    func testNoListsGivesZero() {
        let r = TaskEditorView.resolveListId(task: nil, initialListId: 3, taskLists: [])
        XCTAssertEqual(r.listId, 0)
        XCTAssertFalse(r.isLocked)
    }

    func testEditUsesTaskListAndIgnoresInitial() throws {
        let r = TaskEditorView.resolveListId(task: try task(listId: 2), initialListId: 1, taskLists: [try list(1), try list(2)])
        XCTAssertEqual(r.listId, 2)
        XCTAssertFalse(r.isLocked)
    }
}
