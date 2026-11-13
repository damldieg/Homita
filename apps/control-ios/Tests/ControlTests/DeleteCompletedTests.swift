import XCTest
@testable import ControlKit

/// Borrado masivo de completadas (E2-09): en paralelo, una sola recarga y aviso si algo falla.
final class DeleteCompletedTests: XCTestCase {
    private let tasksJSON = #"[{"id":1,"task_list_id":5,"title":"A","completed_at":"2026-11-09 10:00:00"},{"id":2,"task_list_id":5,"title":"B","completed_at":"2026-11-09 10:00:00"},{"id":3,"task_list_id":5,"title":"C","completed_at":"2026-11-09 10:00:00"},{"id":4,"task_list_id":5,"title":"D","completed_at":null}]"#

    private func route(_ request: URLRequest) -> String {
        let path = request.url?.path ?? ""
        return path.range(of: "/functions/v1/api/").map { String(path[$0.upperBound...]) } ?? path
    }

    private func makeStore(deleteStatus: Int) async -> TasksStore {
        StubURLProtocol.reset { [tasksJSON] request in
            if self.route(request) == "task/delete" {
                return deleteStatus == 200 ? .init(json: "{}") : .init(status: deleteStatus, json: "{\"error\":\"boom\"}")
            }
            return .init(json: tasksJSON)
        }
        let client = makeTestClient()
        let store = TasksStore(taskLists: TaskListRepository(client: client), tasks: TaskRepository(client: client))
        await store.loadTasks()
        return store
    }

    func testDeletesEveryCompletedTaskAndReloadsOnce() async {
        let store = await makeStore(deleteStatus: 200)
        StubURLProtocol.reset { [tasksJSON] request in
            self.route(request) == "task/delete" ? .init(json: "{}") : .init(json: tasksJSON)
        }
        await store.deleteCompleted(listId: 5)

        let requests = StubURLProtocol.requests
        XCTAssertEqual(requests.filter { route($0) == "task/delete" }.count, 3, "una petición por tarea completada")
        XCTAssertEqual(requests.filter { route($0) == "task" }.count, 1, "una sola recarga al final")
        XCTAssertFalse(store.isDeletingCompleted)
        XCTAssertNil(store.writeFailure)
    }

    func testFailuresAreReportedAndDeletingFlagClears() async {
        let store = await makeStore(deleteStatus: 500)
        await store.deleteCompleted(listId: 5)
        XCTAssertEqual(store.writeFailure?.message, "No se pudieron eliminar 3 de 3 tareas completadas")
        XCTAssertFalse(store.isDeletingCompleted)
    }
}
