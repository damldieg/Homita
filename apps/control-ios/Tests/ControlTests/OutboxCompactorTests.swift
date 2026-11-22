import XCTest
@testable import ControlKit

/// AC6: compactación de la cola al encolar.
final class OutboxCompactorTests: XCTestCase {
    private func op(_ kind: PendingOp.Kind) -> PendingOp {
        PendingOp(homeId: "1", kind: kind)
    }

    private func enqueue(_ kinds: [PendingOp.Kind], inFlight: UUID? = nil, into start: [PendingOp] = [], idMap: [Int: Int] = [:]) -> [PendingOp] {
        kinds.reduce(start) { OutboxCompactor.enqueue(op($1), into: $0, inFlight: inFlight, idMap: idMap) }
    }

    func testUpdateOverPendingCreateMergesKeepingPersonsWhenNil() {
        let queue = enqueue([
            .createTask(local: -1, listRef: .remote(2), title: "Leche", personIds: [5]),
            .updateTask(ref: .local(-1), listRef: .remote(2), title: "Leche entera", personIds: nil)
        ])
        XCTAssertEqual(queue.map(\.kind), [.createTask(local: -1, listRef: .remote(2), title: "Leche entera", personIds: [5])])
    }

    func testUpdateOverPendingCreateReplacesPersonsWhenGiven() {
        let queue = enqueue([
            .createTask(local: -1, listRef: .remote(2), title: "Leche", personIds: [5]),
            .updateTask(ref: .local(-1), listRef: .remote(2), title: "Leche", personIds: [])
        ])
        XCTAssertEqual(queue.map(\.kind), [.createTask(local: -1, listRef: .remote(2), title: "Leche", personIds: [])])
    }

    func testUpdateOverUpdateKeepsLastWithPersonsRule() {
        let queue = enqueue([
            .updateTask(ref: .remote(7), listRef: .remote(2), title: "A", personIds: [1]),
            .updateTask(ref: .remote(7), listRef: .remote(2), title: "B", personIds: nil)
        ])
        XCTAssertEqual(queue.map(\.kind), [.updateTask(ref: .remote(7), listRef: .remote(2), title: "B", personIds: [1])])
    }

    func testThreeCompletesLeaveTheLast() {
        let queue = enqueue([
            .completeTask(ref: .remote(7), listRef: .remote(2), completed: true),
            .completeTask(ref: .remote(7), listRef: .remote(2), completed: false),
            .completeTask(ref: .remote(7), listRef: .remote(2), completed: true)
        ])
        XCTAssertEqual(queue.map(\.kind), [.completeTask(ref: .remote(7), listRef: .remote(2), completed: true)])
    }

    func testDeleteOverPendingCreateAnnulsEverything() {
        let queue = enqueue([
            .createTask(local: -1, listRef: .remote(2), title: "Leche", personIds: nil),
            .completeTask(ref: .local(-1), listRef: .remote(2), completed: true),
            .completeTask(ref: .remote(8), listRef: .remote(2), completed: true),
            .deleteTask(ref: .local(-1), listRef: .remote(2))
        ])
        XCTAssertEqual(queue.map(\.kind), [.completeTask(ref: .remote(8), listRef: .remote(2), completed: true)])
    }

    func testDeleteOfRemoteTaskDropsPreviousUpdatesAndCompletes() {
        let queue = enqueue([
            .updateTask(ref: .remote(7), listRef: .remote(2), title: "A", personIds: nil),
            .completeTask(ref: .remote(7), listRef: .remote(2), completed: true),
            .deleteTask(ref: .remote(7), listRef: .remote(2))
        ])
        XCTAssertEqual(queue.map(\.kind), [.deleteTask(ref: .remote(7), listRef: .remote(2))])
    }

    func testDeleteListDropsItsTaskOps() {
        let queue = enqueue([
            .createTask(local: -1, listRef: .remote(2), title: "Leche", personIds: nil),
            .completeTask(ref: .remote(7), listRef: .remote(2), completed: true),
            .completeTask(ref: .remote(9), listRef: .remote(3), completed: true),
            .updateList(ref: .remote(2), name: "X", color: "#000000", sort: "custom", widget: true, dashboard: true),
            .deleteList(ref: .remote(2))
        ])
        XCTAssertEqual(queue.map(\.kind), [
            .completeTask(ref: .remote(9), listRef: .remote(3), completed: true),
            .deleteList(ref: .remote(2))
        ])
    }

    func testDeleteLocalListAnnulsItsCreateAndTasks() {
        let queue = enqueue([
            .createList(local: -1, name: "Compra", color: "#6923E2", sort: "custom", widget: true, dashboard: true),
            .createTask(local: -2, listRef: .local(-1), title: "Leche", personIds: nil),
            .completeTask(ref: .local(-2), listRef: .local(-1), completed: true),
            .deleteList(ref: .local(-1))
        ])
        XCTAssertTrue(queue.isEmpty)
    }

    func testUpdateOverPendingListCreateMerges() {
        let queue = enqueue([
            .createList(local: -1, name: "Compra", color: "#6923E2", sort: "custom", widget: true, dashboard: true),
            .updateList(ref: .local(-1), name: "Súper", color: "#112233", sort: "title", widget: false, dashboard: true)
        ])
        XCTAssertEqual(queue.map(\.kind), [.createList(local: -1, name: "Súper", color: "#112233", sort: "title", widget: false, dashboard: true)])
    }

    func testInFlightOpIsNeverModified() {
        let create = op(.createTask(local: -1, listRef: .remote(2), title: "Leche", personIds: [5]))
        let queue = enqueue([
            .updateTask(ref: .local(-1), listRef: .remote(2), title: "Leche entera", personIds: nil),
            .deleteTask(ref: .local(-1), listRef: .remote(2))
        ], inFlight: create.id, into: [create])
        XCTAssertEqual(queue.first, create, "la op en vuelo sigue intacta")
        XCTAssertEqual(queue.map(\.kind), [create.kind, .deleteTask(ref: .local(-1), listRef: .remote(2))],
                       "el update se anula y el delete queda al final para resolverse con el ack")
    }

    func testInFlightCompleteIsNotReplacedButFollowedByTheNew() {
        let first = op(.completeTask(ref: .remote(7), listRef: .remote(2), completed: true))
        let queue = enqueue([.completeTask(ref: .remote(7), listRef: .remote(2), completed: false)], inFlight: first.id, into: [first])
        XCTAssertEqual(queue.count, 2)
        XCTAssertEqual(queue.first, first)
    }

    func testResolvedLocalRefMatchesRemoteRef() {
        // El create de la lista -1 ya se confirmó como 40: un delete por el ID real anula sus tareas.
        let queue = enqueue([
            .createTask(local: -2, listRef: .local(-1), title: "Leche", personIds: nil),
            .deleteList(ref: .remote(40))
        ], idMap: [-1: 40])
        XCTAssertEqual(queue.map(\.kind), [.deleteList(ref: .remote(40))])
    }

    /// 0038: editar una tarea aún local con personas las lleva al create (lo que verá `create_task`).
    func testUpdateOverPendingCreateCarriesNewPersons() {
        let queue = enqueue([
            .createTask(local: -1, listRef: .remote(2), title: "Leche", personIds: nil),
            .updateTask(ref: .local(-1), listRef: .remote(2), title: "Leche", personIds: [3, 4])
        ])
        XCTAssertEqual(queue.map(\.kind), [.createTask(local: -1, listRef: .remote(2), title: "Leche", personIds: [3, 4])])
    }
}
