import XCTest
@testable import ControlKit

/// 0039 (D-025, A14): tareas completadas ocultas a los 3 días. El servidor deja de traerlas en
/// `GET task` y cualquier escritura sobre ellas responde 500 `{"error":"Not Found"}`, igual que una
/// inexistente. Los stores recargan ante ese error para que la tarea desaparezca de la pantalla.
@MainActor
final class TasksStoreHiddenTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("tasks-hidden-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Foto del servidor mutable: `hidden` = ids que el servidor ya no trae (ocultas).
    private final class Server: @unchecked Sendable {
        private let lock = NSLock()
        private var _hidden: Set<Int> = []
        var hidden: Set<Int> {
            get { lock.lock(); defer { lock.unlock() }; return _hidden }
            set { lock.lock(); defer { lock.unlock() }; _hidden = newValue }
        }
    }

    private static let rows: [(Int, String)] = [
        (1, #"{"id":1,"task_list_id":5,"title":"A","completed_at":"2026-11-15 10:00:00"}"#),
        (2, #"{"id":2,"task_list_id":5,"title":"B","completed_at":"2026-11-21 10:00:00"}"#),
        (3, #"{"id":3,"task_list_id":5,"title":"C","completed_at":null}"#)
    ]
    private static let notFound = StubURLProtocol.Stub(status: 500, json: #"{"error":"Not Found"}"#)

    nonisolated private static func route(_ request: URLRequest) -> String {
        let path = request.url?.path ?? ""
        return path.range(of: "/functions/v1/api/").map { String(path[$0.upperBound...]) } ?? path
    }

    nonisolated private static func bodyId(_ request: URLRequest) -> Int? {
        guard let data = request.capturedBody,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object["id"] as? Int
    }

    /// `GET task` sin las ocultas; las escrituras (y el detail) sobre una oculta, 500 «Not Found».
    private func installStub(_ server: Server) {
        StubURLProtocol.reset { request in
            let route = Self.route(request)
            let hidden = server.hidden
            switch (request.httpMethod ?? "GET", route) {
            case ("GET", "task"):
                let visible = Self.rows.filter { !hidden.contains($0.0) }.map(\.1)
                return StubURLProtocol.Stub(json: "[\(visible.joined(separator: ","))]")
            case ("GET", "task/detail"):
                let id = request.capturedQuery.first { $0.0 == "id" }?.1.flatMap(Int.init)
                guard let id, !hidden.contains(id), let row = Self.rows.first(where: { $0.0 == id }) else { return Self.notFound }
                return StubURLProtocol.Stub(json: row.1)
            case (_, "task/complete"), (_, "task/update"), (_, "task/order"), (_, "task/delete"):
                if let id = Self.bodyId(request) ?? request.capturedQuery.first(where: { $0.0 == "id" })?.1.flatMap(Int.init),
                   hidden.contains(id) {
                    return Self.notFound
                }
                return ContractFixtures.response(for: request)
            default:
                return ContractFixtures.response(for: request)
            }
        }
    }

    private func makeStore(_ server: Server, outbox: OutboxStore? = nil) -> TasksStore {
        installStub(server)
        let client = makeTestClient()
        return TasksStore(taskLists: TaskListRepository(client: client), tasks: TaskRepository(client: client),
                          outbox: outbox, isOnline: { true },
                          defaults: UserDefaults(suiteName: "tasks-hidden-\(UUID().uuidString)")!)
    }

    private var writeRoutes: [String] {
        StubURLProtocol.requests.filter { $0.httpMethod != "GET" }.map(Self.route)
    }

    // MARK: - Listado

    func testHiddenTaskDisappearsAfterReload() async {
        let server = Server()
        let store = makeStore(server)
        await store.loadTasks()
        XCTAssertEqual(store.tasks.map(\.id), [1, 2, 3])

        server.hidden = [1]
        await store.loadTasks()
        XCTAssertEqual(store.tasks.map(\.id), [2, 3], "la oculta ya no está tras recargar")
        XCTAssertFalse(store.completedTasks.contains { $0.id == 1 })
    }

    func testQueuedOpsDoNotReintroduceHiddenTask() async throws {
        let server = Server()
        let outbox = OutboxStore(userId: 1, homeId: "2", directory: directory)
        let store = makeStore(server, outbox: outbox)
        await store.loadTasks()
        let hiddenTask = try XCTUnwrap(store.tasks.first { $0.id == 1 })
        outbox.enqueue(PendingOp(homeId: "2", kind: .updateTask(ref: .remote(1), listRef: .remote(5), title: "A2", personIds: nil)))
        outbox.enqueue(PendingOp(homeId: "2", kind: .completeTask(ref: .remote(1), listRef: .remote(5), completed: !hiddenTask.isCompleted)))

        server.hidden = [1]
        await store.loadTasks()
        XCTAssertEqual(store.tasks.map(\.id), [2, 3], "el overlay no reintroduce la oculta")
        XCTAssertFalse(store.pendingTaskIds.contains(1))
    }

    // MARK: - Escrituras en línea

    func testInlineCompleteOnHiddenTaskReloadsAndRemovesIt() async throws {
        let server = Server()
        let store = makeStore(server)
        await store.loadTasks()
        let task = try XCTUnwrap(store.tasks.first { $0.id == 1 })

        server.hidden = [1]
        installStub(server)
        await store.toggleComplete(task)

        XCTAssertEqual(writeRoutes, ["task/complete"])
        XCTAssertEqual(StubURLProtocol.requests.filter { $0.httpMethod == "GET" && Self.route($0) == "task" }.count, 1,
                       "recarga tras el Not Found")
        XCTAssertEqual(store.tasks.map(\.id), [2, 3])
        XCTAssertNotNil(store.writeFailure, "complete/update siguen avisando con el toast")
    }

    func testInlineCompleteOnHiddenTaskWithOutboxReloadsAndDoesNotQueue() async throws {
        let server = Server()
        let outbox = OutboxStore(userId: 1, homeId: "2", directory: directory)
        let store = makeStore(server, outbox: outbox)
        await store.loadTasks()
        let task = try XCTUnwrap(store.tasks.first { $0.id == 1 })

        server.hidden = [1]
        await store.toggleComplete(task)

        XCTAssertTrue(outbox.isEmpty, "un Not Found no se encola")
        XCTAssertEqual(store.tasks.map(\.id), [2, 3])
    }

    func testInlineUpdateOnHiddenTaskReloadsAndRemovesIt() async throws {
        let server = Server()
        let store = makeStore(server)
        await store.loadTasks()
        let task = try XCTUnwrap(store.tasks.first { $0.id == 1 })

        server.hidden = [1]
        let ok = await store.updateTask(task, title: "A2")

        XCTAssertFalse(ok)
        XCTAssertEqual(store.tasks.map(\.id), [2, 3])
    }

    func testInlineDeleteOnHiddenTaskIsSilentSuccess() async throws {
        let server = Server()
        let store = makeStore(server)
        await store.loadTasks()
        let task = try XCTUnwrap(store.tasks.first { $0.id == 1 })

        server.hidden = [1]
        await store.deleteTask(task)

        XCTAssertNil(store.writeFailure, "delete con Not Found = éxito sin toast")
        XCTAssertEqual(store.tasks.map(\.id), [2, 3])
    }

    func testDeleteCompletedCountsNotFoundAsDeleted() async {
        let server = Server()
        let store = makeStore(server)
        await store.loadTasks()

        server.hidden = [1]
        await store.deleteCompleted(listId: 5)

        XCTAssertEqual(writeRoutes.filter { $0 == "task/delete" }.count, 2, "una petición por completada")
        XCTAssertNil(store.writeFailure, "un Not Found no cuenta como fallo")
        XCTAssertFalse(store.isDeletingCompleted)
    }

    // MARK: - Inicio

    func testInicioUpdateOnHiddenTaskReloadsAndRemovesIt() async throws {
        let server = Server()
        installStub(server)
        let client = makeTestClient()
        let store = InicioStore(
            events: EventRepository(client: client), tasks: TaskRepository(client: client),
            routines: RoutineRepository(client: client), taskLists: TaskListRepository(client: client),
            outbox: nil, isOnline: { true }
        )
        await store.loadTasks()
        let task = try XCTUnwrap(store.tasks.first { $0.id == 3 })

        server.hidden = [3]
        let ok = await store.updateTask(task, title: "C2")

        XCTAssertFalse(ok)
        XCTAssertNotNil(store.writeFailure)
        XCTAssertFalse(store.tasks.contains { $0.id == 3 }, "la oculta desaparece tras el Not Found")
    }

    // MARK: - Detail

    func testDetailOfHiddenTaskIsNotFound() async {
        let server = Server()
        server.hidden = [1]
        installStub(server)
        let repo = TaskRepository(client: makeTestClient())
        do {
            _ = try await repo.detail(id: 1)
            XCTFail("una oculta no debe decodificarse")
        } catch let error as APIError {
            XCTAssertEqual(error, .http(status: 500, message: "Not Found"))
            XCTAssertTrue(error.isNotFound)
        } catch {
            XCTFail("error inesperado: \(error)")
        }
    }
}
