import XCTest
@testable import ControlKit

/// Overlay de la cola offline sobre la foto del servidor (AC1, parte pura).
final class PendingOverlayTests: XCTestCase {
    private let list = TaskListEntry(
        id: 2, name: "Compra", color: "#6923E2", token: nil, sort: "custom", created_at: nil, updated_at: nil,
        widget: nil, dashboard: nil, pending_task_count: FlexInt(1), can_edit: nil
    )
    private let milk = TaskEntry(
        id: 7, task_list_id: 2, title: "Leche", completed_at: nil, created_at: nil, updated_at: nil, order: FlexInt(1),
        task_list_color: "#6923E2", task_list_name: "Compra", persons: nil
    )

    private func apply(_ kinds: [PendingOp.Kind], idMap: [Int: Int] = [:], tasks: [TaskEntry]? = nil, lists: [TaskListEntry]? = nil) -> OverlayResult {
        PendingOverlay.apply(
            ops: kinds.map { PendingOp(homeId: "1", kind: $0) }, idMap: idMap,
            tasks: tasks ?? [milk], lists: lists ?? [list]
        )
    }

    func testEmptyQueueIsServerAsIs() {
        let result = apply([])
        XCTAssertEqual(result.tasks, [milk])
        XCTAssertEqual(result.lists, [list])
        XCTAssertTrue(result.pendingTaskIds.isEmpty)
    }

    func testLocalCreateAddsPendingRowWithListNameAndColor() throws {
        let result = apply([.createTask(local: -1, listRef: .remote(2), title: "Pan", personIds: nil)])
        let row = try XCTUnwrap(result.tasks.first { $0.id == -1 })
        XCTAssertEqual(row.title, "Pan")
        XCTAssertEqual(row.task_list_id, 2)
        XCTAssertEqual(row.task_list_name, "Compra")
        XCTAssertEqual(row.task_list_color, "#6923E2")
        XCTAssertFalse(row.isCompleted)
        XCTAssertEqual(result.pendingTaskIds, [-1])
        XCTAssertEqual(result.lists.first?.pendingTaskCount, 2)
    }

    func testUpdateCompleteAndDelete() {
        let updated = apply([.updateTask(ref: .remote(7), listRef: .remote(2), title: "Leche entera", personIds: nil)])
        XCTAssertEqual(updated.tasks.first?.title, "Leche entera")
        XCTAssertEqual(updated.pendingTaskIds, [7])

        let completed = apply([.completeTask(ref: .remote(7), listRef: .remote(2), completed: true)])
        XCTAssertEqual(completed.tasks.first?.isCompleted, true)
        XCTAssertEqual(completed.lists.first?.pendingTaskCount, 0)

        let deleted = apply([.deleteTask(ref: .remote(7), listRef: .remote(2))])
        XCTAssertTrue(deleted.tasks.isEmpty)
        XCTAssertTrue(deleted.pendingTaskIds.isEmpty)
        XCTAssertEqual(deleted.lists.first?.pendingTaskCount, 0)
    }

    func testLocalListWithTasks() throws {
        let result = apply([
            .createList(local: -1, name: "Viaje", color: "#112233", sort: "custom", widget: true, dashboard: false),
            .createTask(local: -2, listRef: .local(-1), title: "Pasaporte", personIds: nil)
        ])
        let newList = try XCTUnwrap(result.lists.first { $0.id == -1 })
        XCTAssertEqual(newList.name, "Viaje")
        XCTAssertFalse(newList.showsInDashboard)
        XCTAssertEqual(newList.pendingTaskCount, 1)
        let task = try XCTUnwrap(result.tasks.first { $0.id == -2 })
        XCTAssertEqual(task.task_list_id, -1)
        XCTAssertEqual(task.task_list_name, "Viaje")
        XCTAssertEqual(result.pendingListIds, [-1])
        XCTAssertEqual(result.pendingTaskIds, [-2])
    }

    func testDeleteListRemovesItsTasks() {
        let result = apply([.deleteList(ref: .remote(2))])
        XCTAssertTrue(result.lists.isEmpty)
        XCTAssertTrue(result.tasks.isEmpty)
    }

    func testResolvedIdDoesNotDuplicateWhenServerAlreadyHasIt() {
        // La tarea -1 ya se confirmó como 7 y la recarga del servidor la trae: una sola fila.
        let result = apply([.createTask(local: -1, listRef: .remote(2), title: "Leche", personIds: nil)], idMap: [-1: 7])
        XCTAssertEqual(result.tasks.map(\.id), [7])
        XCTAssertEqual(result.lists.first?.pendingTaskCount, 1, "no suma la fila que el servidor ya contó")
    }

    // MARK: - 0039 (D-025): tareas ocultas que el servidor ya no trae

    func testUpdateAndCompleteOfHiddenTaskDoNotReintroduceIt() {
        // La tarea 9 se ocultó: el servidor solo trae la 7 y la cola tiene ops sobre la 9.
        let result = apply([
            .updateTask(ref: .remote(9), listRef: .remote(2), title: "Pan", personIds: nil),
            .completeTask(ref: .remote(9), listRef: .remote(2), completed: false),
            .completeTask(ref: .remote(9), listRef: .remote(2), completed: true)
        ])
        XCTAssertEqual(result.tasks, [milk], "no se reintroduce una fila que el servidor no trae")
        XCTAssertTrue(result.pendingTaskIds.isEmpty, "ni se marca pendiente")
        XCTAssertEqual(result.lists.first?.pendingTaskCount, 1, "el recuento de la lista no cambia")
    }

    func testDeleteOfHiddenTaskKeepsCounts() {
        let result = apply([.deleteTask(ref: .remote(9), listRef: .remote(2))])
        XCTAssertEqual(result.tasks, [milk])
        XCTAssertTrue(result.pendingTaskIds.isEmpty)
        XCTAssertEqual(result.lists.first?.pendingTaskCount, 1, "un delete de un id ausente no toca el recuento")
    }

    func testUpdateOfLocalListRenamesItsTasks() throws {
        let result = apply([
            .updateList(ref: .remote(2), name: "Súper", color: "#000000", sort: "title", widget: true, dashboard: true)
        ])
        XCTAssertEqual(result.lists.first?.name, "Súper")
        XCTAssertEqual(result.tasks.first?.task_list_name, "Súper")
        XCTAssertEqual(result.pendingListIds, [2])
    }
}
