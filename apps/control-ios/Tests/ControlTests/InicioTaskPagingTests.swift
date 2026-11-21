import XCTest
@testable import ControlKit

final class InicioTaskPagingTests: XCTestCase {
    private let ids = [4, 7, 9]

    func testNeighborMovesForwardAndBack() {
        XCTAssertEqual(InicioTaskPaging.neighbor(of: 4, in: ids, forward: true), 7)
        XCTAssertEqual(InicioTaskPaging.neighbor(of: 7, in: ids, forward: true), 9)
        XCTAssertEqual(InicioTaskPaging.neighbor(of: 9, in: ids, forward: false), 7)
    }

    func testNeighborStopsAtTheEnds() {
        XCTAssertNil(InicioTaskPaging.neighbor(of: 9, in: ids, forward: true))
        XCTAssertNil(InicioTaskPaging.neighbor(of: 4, in: ids, forward: false))
    }

    func testNeighborIgnoresUnknownListOrSingleList() {
        XCTAssertNil(InicioTaskPaging.neighbor(of: 5, in: ids, forward: true))
        XCTAssertNil(InicioTaskPaging.neighbor(of: 4, in: [4], forward: true))
        XCTAssertNil(InicioTaskPaging.neighbor(of: 4, in: [], forward: false))
    }

    func testOnlyClearlyHorizontalLongDragsAreSwipes() {
        XCTAssertTrue(InicioTaskPaging.isHorizontalSwipe(width: -80, height: 10))
        XCTAssertTrue(InicioTaskPaging.isHorizontalSwipe(width: 70, height: -20))
        XCTAssertFalse(InicioTaskPaging.isHorizontalSwipe(width: 40, height: 0))      // corto
        XCTAssertFalse(InicioTaskPaging.isHorizontalSwipe(width: 80, height: 60))     // diagonal
        XCTAssertFalse(InicioTaskPaging.isHorizontalSwipe(width: 10, height: 120))    // scroll vertical
    }
}

/// Orden de las páginas de la tarjeta de tareas por `position` de la lista (0040).
@MainActor
final class InicioTaskPagesOrderTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!

    private func task(_ id: Int, list: Int) -> String {
        #"{"id":\#(id),"task_list_id":\#(list),"title":"T\#(id)","completed_at":null,"order":\#(id),"task_list_name":"L\#(list)"}"#
    }

    private func list(_ id: Int, position: String?) -> String {
        let extra = position.map { ##","position":\##($0)"## } ?? ""
        return ##"{"id":\##(id),"name":"L\##(id)","color":"#6923E2","sort":"custom"\##(extra)}"##
    }

    /// Carga tareas (listas 4, 7, 9 en ese orden de aparición) y las listas del servidor con `lists`.
    private func pageIds(lists: [String]) async -> [Int] {
        let tasks = [task(1, list: 4), task(2, list: 7), task(3, list: 9)].joined(separator: ",")
        let listsJson = lists.joined(separator: ",")
        StubURLProtocol.reset { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("/task-list") { return StubURLProtocol.Stub(json: "[\(listsJson)]") }
            if path.hasSuffix("/task") { return StubURLProtocol.Stub(json: "[\(tasks)]") }
            return StubURLProtocol.Stub(json: "[]")
        }
        let client = makeTestClient()
        let now = PHPDateTime.parse("2026-11-09 10:00:00", timeZone: utc)!
        let store = InicioStore(
            events: EventRepository(client: client), tasks: TaskRepository(client: client),
            routines: RoutineRepository(client: client), taskLists: TaskListRepository(client: client),
            clock: { [utc] in LocalClock(now: now, timeZone: utc) }
        )
        await store.loadTasks()
        await store.loadTaskLists()
        return store.pendingTaskPages.map(\.id)
    }

    func testPagesFollowListPosition() async {
        let ids = await pageIds(lists: [list(4, position: "2"), list(7, position: "3"), list(9, position: "1")])
        XCTAssertEqual(ids, [9, 4, 7])
    }

    func testListsWithoutPositionGoLastKeepingTheCurrentOrder() async {
        let ids = await pageIds(lists: [list(4, position: nil), list(7, position: "1"), list(9, position: nil)])
        XCTAssertEqual(ids, [7, 4, 9])
    }

    func testTiesAndUnknownListsKeepTheCurrentOrder() async {
        let ids = await pageIds(lists: [list(4, position: "1"), list(7, position: "1")])
        XCTAssertEqual(ids, [4, 7, 9])
    }

    func testServerWithoutPositionKeyKeepsTheCurrentOrder() async throws {
        let ids = await pageIds(lists: [list(4, position: nil), list(7, position: nil), list(9, position: nil)])
        XCTAssertEqual(ids, [4, 7, 9])
        let decoded = try JSONDecoder().decode(TaskListEntry.self, from: Data(list(4, position: nil).utf8))
        XCTAssertNil(decoded.positionValue)
    }

    /// `loadTasks()` pide también `/task-list` y las páginas salen ordenadas sin llamar a `loadTaskLists()`.
    func testLoadTasksFetchesListsAndOrdersPages() async {
        let tasks = [task(1, list: 4), task(2, list: 7), task(3, list: 9)].joined(separator: ",")
        let lists = [list(4, position: "2"), list(7, position: nil), list(9, position: "1")].joined(separator: ",")
        StubURLProtocol.reset { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("/task-list") { return StubURLProtocol.Stub(json: "[\(lists)]") }
            if path.hasSuffix("/task") { return StubURLProtocol.Stub(json: "[\(tasks)]") }
            return StubURLProtocol.Stub(json: "[]")
        }
        let store = makeStore()
        await store.loadTasks()
        XCTAssertEqual(store.tasksState, .loaded)
        XCTAssertEqual(store.pendingTaskPages.map(\.id), [9, 4, 7])
    }

    /// Si `/task-list` falla, las tareas cargan igual, sin error y con el orden de siempre.
    func testTaskListFailureDoesNotBlockTasks() async {
        let tasks = [task(1, list: 4), task(2, list: 7)].joined(separator: ",")
        StubURLProtocol.reset { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("/task-list") { return StubURLProtocol.Stub(status: 500, json: #"{"error":"boom"}"#) }
            if path.hasSuffix("/task") { return StubURLProtocol.Stub(json: "[\(tasks)]") }
            return StubURLProtocol.Stub(json: "[]")
        }
        let store = makeStore()
        await store.loadTasks()
        XCTAssertEqual(store.tasksState, .loaded)
        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(store.pendingTaskPages.map(\.id), [4, 7])
    }

    private func makeStore() -> InicioStore {
        let client = makeTestClient()
        let now = PHPDateTime.parse("2026-11-09 10:00:00", timeZone: utc)!
        return InicioStore(
            events: EventRepository(client: client), tasks: TaskRepository(client: client),
            routines: RoutineRepository(client: client), taskLists: TaskListRepository(client: client),
            clock: { [utc] in LocalClock(now: now, timeZone: utc) }
        )
    }
}
