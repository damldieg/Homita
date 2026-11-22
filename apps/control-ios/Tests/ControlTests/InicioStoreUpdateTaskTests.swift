import XCTest
@testable import ControlKit

/// `InicioStore.updateTask`: editar título y personas desde Inicio, en línea y con la cola offline.
@MainActor
final class InicioStoreUpdateTaskTests: XCTestCase {
    private var directory: URL!
    private final class Network { var online = true }

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("inicio-update-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    nonisolated private static func route(_ request: URLRequest) -> String {
        let path = request.url?.path ?? ""
        return path.range(of: "/functions/v1/api/").map { String(path[$0.upperBound...]) } ?? path
    }

    private func installStub() {
        StubURLProtocol.reset { request in
            switch (request.httpMethod ?? "GET", Self.route(request)) {
            case ("GET", "task"): return StubURLProtocol.Stub(json: "[\(ContractFixtures.task)]")
            case ("GET", "task-list"): return StubURLProtocol.Stub(json: "[\(ContractFixtures.taskList)]")
            default: return ContractFixtures.response(for: request)
            }
        }
    }

    private func makeStore(outbox: OutboxStore?, network: Network = Network()) -> InicioStore {
        installStub()
        let client = makeTestClient()
        return InicioStore(
            events: EventRepository(client: client), tasks: TaskRepository(client: client),
            routines: RoutineRepository(client: client), taskLists: TaskListRepository(client: client),
            outbox: outbox, isOnline: { network.online }
        )
    }

    func testOnlineUpdateWritesAndReloads() async throws {
        let store = makeStore(outbox: nil)
        await store.loadTasks()
        let leche = try XCTUnwrap(store.tasks.first { $0.id == 7 })
        StubURLProtocol.reset { request in
            if Self.route(request) == "task", request.httpMethod == "GET" {
                return StubURLProtocol.Stub(json: #"[{"id":7,"task_list_id":2,"title":"Leche entera"}]"#)
            }
            return ContractFixtures.response(for: request)
        }
        let ok = await store.updateTask(leche, title: "Leche entera", personIds: [1])
        XCTAssertTrue(ok)
        let writes = StubURLProtocol.requests.filter { $0.httpMethod != "GET" }
        XCTAssertEqual(writes.count, 1)
        XCTAssertEqual(Self.route(writes[0]), "task/update")
        let body = try XCTUnwrap(writes[0].capturedBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        XCTAssertEqual(body["id"] as? Int, 7)
        XCTAssertEqual(body["title"] as? String, "Leche entera")
        XCTAssertEqual(body["person_ids"] as? [Int], [1])
        XCTAssertEqual(store.tasks.first { $0.id == 7 }?.title, "Leche entera", "recarga tras guardar")
        XCTAssertNil(store.writeFailure)
    }

    func testOfflineUpdateQueuesAndOverlayShowsNewTitle() async throws {
        let network = Network()
        let outbox = OutboxStore(userId: 1, homeId: "2", directory: directory)
        let store = makeStore(outbox: outbox, network: network)
        await store.loadTasks()
        await store.loadTaskLists()
        installStub()
        network.online = false
        let leche = try XCTUnwrap(store.tasks.first { $0.id == 7 })

        let ok = await store.updateTask(leche, title: "Leche entera")
        XCTAssertTrue(ok)
        XCTAssertEqual(outbox.pendingCount, 1)
        XCTAssertEqual(store.tasks.first { $0.id == 7 }?.title, "Leche entera")
        XCTAssertTrue(store.pendingTaskIds.contains(7))
        XCTAssertTrue(StubURLProtocol.requests.isEmpty, "sin red no se intenta ninguna petición")
        XCTAssertNil(store.writeFailure)
    }

    func testEditingLocalTaskMergesIntoPendingCreate() async throws {
        let network = Network()
        let outbox = OutboxStore(userId: 1, homeId: "2", directory: directory)
        let store = makeStore(outbox: outbox, network: network)
        await store.loadTasks()
        await store.loadTaskLists()
        installStub()
        network.online = false

        let created = await store.createTask(title: "Pan", listId: 2)
        XCTAssertTrue(created)
        let pan = try XCTUnwrap(store.tasks.first { $0.title == "Pan" })
        XCTAssertLessThan(pan.id, 0)

        let ok = await store.updateTask(pan, title: "Pan integral")
        XCTAssertTrue(ok)
        XCTAssertEqual(outbox.pendingCount, 1, "el update se funde en el create pendiente")
        XCTAssertEqual(store.tasks.filter { $0.id < 0 }.count, 1, "sin segunda fila")
        XCTAssertEqual(store.tasks.first { $0.id < 0 }?.title, "Pan integral")
        XCTAssertTrue(store.pendingTaskIds.contains(pan.id))
    }

    /// R2-01: la prioridad editada desde Inicio se envía solo si cambió (la tarea del fixture es `media`).
    func testOnlinePriorityIsSentOnlyWhenChanged() async throws {
        let store = makeStore(outbox: nil)
        await store.loadTasks()
        let leche = try XCTUnwrap(store.tasks.first { $0.id == 7 })
        XCTAssertEqual(leche.priorityValue, .media)

        let saved1 = await store.updateTask(leche, title: "Leche", personIds: nil, priority: .media)
        XCTAssertTrue(saved1)
        var writes = StubURLProtocol.requests.filter { $0.httpMethod != "GET" }
        XCTAssertEqual(writes.count, 1)
        var body = try XCTUnwrap(writes[0].capturedBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        XCTAssertNil(body["priority"], "prioridad sin cambiar → no se envía")

        installStub()
        let saved2 = await store.updateTask(leche, title: "Leche", personIds: nil, priority: .alta)
        XCTAssertTrue(saved2)
        writes = StubURLProtocol.requests.filter { $0.httpMethod != "GET" }
        XCTAssertEqual(writes.count, 1)
        XCTAssertEqual(Self.route(writes[0]), "task/update")
        body = try XCTUnwrap(writes[0].capturedBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        XCTAssertEqual(body["priority"] as? String, "alta", "prioridad cambiada → se envía")
        XCTAssertNil(store.writeFailure)
    }

    func testOfflinePriorityChangeIsQueued() async throws {
        let network = Network()
        let outbox = OutboxStore(userId: 1, homeId: "2", directory: directory)
        let store = makeStore(outbox: outbox, network: network)
        await store.loadTasks()
        await store.loadTaskLists()
        installStub()
        network.online = false
        let leche = try XCTUnwrap(store.tasks.first { $0.id == 7 })

        let saved3 = await store.updateTask(leche, title: "Leche", personIds: nil, priority: .baja)
        XCTAssertTrue(saved3)
        XCTAssertEqual(outbox.ops.map(\.kind), [.updateTask(ref: .remote(7), listRef: .remote(2), title: "Leche", personIds: nil, priority: "baja")])
        XCTAssertEqual(store.tasks.first { $0.id == 7 }?.priorityValue, .baja, "el overlay muestra la prioridad en cola")
        XCTAssertTrue(StubURLProtocol.requests.isEmpty)
    }
}
