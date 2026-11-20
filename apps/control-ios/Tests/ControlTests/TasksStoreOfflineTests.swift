import XCTest
@testable import ControlKit

/// `TasksStore` e `InicioStore` con cola offline (D-024): AC1 (escrituras offline visibles al
/// momento y marcadas como pendientes), AC3 (recarga tras el replay), guard de `generation`,
/// reordenar solo con red y cola vacía, y la clave de idempotencia en los creates (AC7, cliente).
@MainActor
final class TasksStoreOfflineTests: XCTestCase {
    private var directory: URL!

    /// Estado de red que leen el store y el coordinador.
    private final class Network {
        var online = true
    }

    /// Respuestas mutables entre llamadas (el handler del stub corre fuera del hilo principal).
    private final class Server: @unchecked Sendable {
        private let lock = NSLock()
        private var _tasks = #"[{"id":7,"task_list_id":2,"title":"Leche"}]"#
        private var _taskDelay: TimeInterval = 0
        var tasks: String {
            get { lock.lock(); defer { lock.unlock() }; return _tasks }
            set { lock.lock(); _tasks = newValue; lock.unlock() }
        }
        var taskDelay: TimeInterval {
            get { lock.lock(); defer { lock.unlock() }; return _taskDelay }
            set { lock.lock(); _taskDelay = newValue; lock.unlock() }
        }
    }

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("outbox-store-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    nonisolated private static func route(_ request: URLRequest) -> String {
        let path = request.url?.path ?? ""
        return path.range(of: "/functions/v1/api/").map { String(path[$0.upperBound...]) } ?? path
    }

    private var routes: [String] { StubURLProtocol.requests.map(Self.route) }

    private func body(_ request: URLRequest) -> [String: Any] {
        guard let data = request.capturedBody else { return [:] }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    /// Stub: `GET task` = `server.tasks`, `GET task-list` = la lista 2 (orden personalizado),
    /// `overrides` por ruta y el resto, fixtures del contrato.
    private func installStub(_ server: Server, _ overrides: [String: StubURLProtocol.Stub] = [:]) {
        StubURLProtocol.reset { request in
            let route = Self.route(request)
            if let stub = overrides[route] { return stub }
            switch (request.httpMethod ?? "GET", route) {
            case ("GET", "task"): return StubURLProtocol.Stub(json: server.tasks, delay: server.taskDelay)
            case ("GET", "task-list"): return StubURLProtocol.Stub(json: "[\(ContractFixtures.taskList)]")
            default: return ContractFixtures.response(for: request)
            }
        }
    }

    private func makeStore(_ server: Server, network: Network, _ overrides: [String: StubURLProtocol.Stub] = [:]) -> (TasksStore, OutboxStore, APIClient) {
        installStub(server, overrides)
        let client = makeTestClient()
        let outbox = OutboxStore(userId: 1, homeId: "2", directory: directory)
        let store = TasksStore(
            taskLists: TaskListRepository(client: client), tasks: TaskRepository(client: client),
            outbox: outbox, isOnline: { network.online }
        )
        return (store, outbox, client)
    }

    private func loaded(_ server: Server = Server(), network: Network, _ overrides: [String: StubURLProtocol.Stub] = [:]) async -> (TasksStore, OutboxStore, APIClient) {
        let (store, outbox, client) = makeStore(server, network: network, overrides)
        await store.loadLists()
        await store.loadTasks()
        installStub(server, overrides)
        return (store, outbox, client)
    }

    // MARK: - AC1

    func testOfflineTaskWritesShowAtOnceAsPending() async throws {
        let network = Network()
        let (store, outbox, _) = await loaded(network: network)
        network.online = false

        let created = await store.createTask(title: "Pan", listId: 2)
        XCTAssertTrue(created, "encolar cierra el editor")
        let pan = try XCTUnwrap(store.tasks.first { $0.title == "Pan" })
        XCTAssertLessThan(pan.id, 0, "ID temporal negativo")
        XCTAssertEqual(pan.task_list_name, "Compra")
        XCTAssertTrue(store.pendingTaskIds.contains(pan.id))

        let leche = try XCTUnwrap(store.tasks.first { $0.id == 7 })
        await store.toggleComplete(leche)
        XCTAssertTrue(try XCTUnwrap(store.tasks.first { $0.id == 7 }).isCompleted)

        let editedOk = await store.updateTask(try XCTUnwrap(store.tasks.first { $0.id == 7 }), title: "Leche entera")
        XCTAssertTrue(editedOk)
        XCTAssertEqual(store.tasks.first { $0.id == 7 }?.title, "Leche entera")
        XCTAssertTrue(store.pendingTaskIds.contains(7))

        await store.deleteTask(pan)
        XCTAssertFalse(store.tasks.contains { $0.title == "Pan" })
        XCTAssertFalse(outbox.ops.contains { $0.kind.isCreate }, "borrar una tarea local anula su create")

        XCTAssertTrue(StubURLProtocol.requests.isEmpty, "sin red no se intenta ninguna petición")
        XCTAssertNil(store.writeFailure)
    }

    func testOfflineListWritesShowAtOnceAsPending() async throws {
        let network = Network()
        let (store, outbox, _) = await loaded(network: network)
        network.online = false

        let saved = await store.saveList(name: "Viaje", color: "#112233", sort: "custom", widget: true, dashboard: false, editing: nil)
        XCTAssertTrue(saved)
        let viaje = try XCTUnwrap(store.taskLists.first { $0.name == "Viaje" })
        XCTAssertLessThan(viaje.id, 0)
        XCTAssertTrue(store.pendingListIds.contains(viaje.id))

        await store.createTask(title: "Pasaporte", listId: viaje.id)
        XCTAssertEqual(store.tasks.first { $0.title == "Pasaporte" }?.task_list_id, viaje.id)

        let renamed = await store.saveList(name: "Viaje a Roma", color: "#112233", sort: "custom", widget: true, dashboard: false, editing: viaje)
        XCTAssertTrue(renamed)
        XCTAssertEqual(store.taskLists.first { $0.id == viaje.id }?.name, "Viaje a Roma")
        XCTAssertEqual(store.tasks.first { $0.title == "Pasaporte" }?.task_list_name, "Viaje a Roma")

        let compra = try XCTUnwrap(store.taskLists.first { $0.id == 2 })
        await store.saveList(name: "Súper", color: compra.color, sort: "custom", widget: false, dashboard: false, editing: compra)
        XCTAssertEqual(store.taskLists.first { $0.id == 2 }?.name, "Súper")
        XCTAssertTrue(store.pendingListIds.contains(2))

        store.listFilterId = viaje.id
        await store.deleteList(try XCTUnwrap(store.taskLists.first { $0.id == viaje.id }))
        XCTAssertNil(store.listFilterId, "el filtro deja de apuntar a la lista borrada")
        XCTAssertFalse(store.taskLists.contains { $0.id == viaje.id })
        XCTAssertFalse(store.tasks.contains { $0.title == "Pasaporte" })
        XCTAssertEqual(outbox.ops.map(\.kind), [
            .updateList(ref: .remote(2), name: "Súper", color: compra.color, sort: "custom", widget: false, dashboard: false)
        ], "borrar la lista local anula su create y las ops de sus tareas")
        XCTAssertTrue(StubURLProtocol.requests.isEmpty)
    }

    func testOfflineDeleteCompletedQueuesOneDeletePerTask() async throws {
        let server = Server()
        server.tasks = #"[{"id":7,"task_list_id":2,"title":"Leche","completed_at":"2026-11-09 10:00:00"},{"id":8,"task_list_id":2,"title":"Pan"}]"#
        let network = Network()
        let (store, outbox, _) = await loaded(server, network: network)
        network.online = false
        await store.createTask(title: "Huevos", listId: 2)
        let huevos = try XCTUnwrap(store.tasks.first { $0.title == "Huevos" })
        await store.toggleComplete(huevos)

        await store.deleteCompleted(listId: 2)

        XCTAssertEqual(store.tasks.map(\.id), [8])
        XCTAssertEqual(outbox.ops.map(\.kind), [.deleteTask(ref: .remote(7), listRef: .remote(2))],
                       "la tarea local completada se anula; la remota queda como delete")
        XCTAssertFalse(store.isDeletingCompleted)
        XCTAssertNil(store.writeFailure)
        XCTAssertTrue(StubURLProtocol.requests.isEmpty)
    }

    func testNetworkErrorWhileOnlineQueuesInsteadOfFailing() async throws {
        let network = Network()
        let (store, outbox, _) = await loaded(network: network, ["task/complete": .offline])
        await store.toggleComplete(try XCTUnwrap(store.tasks.first))
        XCTAssertNil(store.writeFailure)
        XCTAssertEqual(outbox.pendingCount, 1)
        XCTAssertTrue(try XCTUnwrap(store.tasks.first).isCompleted)
        XCTAssertEqual(routes, ["task/complete"], "encolada no recarga")
    }

    func testDuplicateTitleCountsPendingRows() async {
        let network = Network()
        let (store, _, _) = await loaded(network: network)
        network.online = false
        let first = await store.createTask(title: "Pan", listId: 2)
        let second = await store.createTask(title: " pan ", listId: 2)
        XCTAssertTrue(first)
        XCTAssertFalse(second)
        XCTAssertEqual(store.writeFailure?.message, "Ya existe una tarea con ese título en la lista")
    }

    // MARK: - Recargas (R3)

    func testReloadKeepsOverlay() async throws {
        let network = Network()
        let (store, _, _) = await loaded(network: network)
        network.online = false
        await store.createTask(title: "Pan", listId: 2)
        await store.toggleComplete(try XCTUnwrap(store.tasks.first { $0.id == 7 }))

        await store.loadTasks()
        await store.loadLists()

        XCTAssertEqual(Set(store.tasks.map(\.title)), ["Leche", "Pan"], "la foto del servidor no pisa lo pendiente")
        XCTAssertTrue(try XCTUnwrap(store.tasks.first { $0.id == 7 }).isCompleted)
        XCTAssertEqual(store.pendingTaskIds.count, 2)
    }

    func testStaleReloadDiscarded() async throws {
        let server = Server()
        let network = Network()
        let (store, outbox, _) = await loaded(server, network: network)
        let op = PendingOp(homeId: "2", kind: .completeTask(ref: .remote(7), listRef: .remote(2), completed: true))
        outbox.enqueue(op)

        // La primera respuesta tarda; mientras está en vuelo llega un ack (replay) y el servidor cambia.
        server.taskDelay = 0.4
        let load = Task { await store.loadTasks() }
        try await Task.sleep(nanoseconds: 100_000_000)
        server.taskDelay = 0
        server.tasks = #"[{"id":7,"task_list_id":2,"title":"Leche","completed_at":"2026-11-09 10:00:00"}]"#
        outbox.ack(op.id)
        await load.value

        XCTAssertEqual(routes.filter { $0 == "task" }.count, 2, "el resultado previo al ack se descarta y se vuelve a pedir")
        XCTAssertTrue(try XCTUnwrap(store.tasks.first).isCompleted, "se queda la foto posterior al replay")
    }

    // MARK: - AC3

    func testReloadAfterReplay() async throws {
        let server = Server()
        let network = Network()
        let (store, outbox, client) = await loaded(server, network: network, [
            "task/create": StubURLProtocol.Stub(status: 201, json: #"{"id":70,"task_list_id":2,"title":"Pan"}"#)
        ])
        network.online = false
        await store.createTask(title: "Pan", listId: 2)
        await store.toggleComplete(try XCTUnwrap(store.tasks.first { $0.id == 7 }))
        let generation = outbox.generation

        network.online = true
        server.tasks = #"[{"id":7,"task_list_id":2,"title":"Leche","completed_at":"2026-11-09 10:00:00"},{"id":70,"task_list_id":2,"title":"Pan"}]"#
        let replayer = OutboxReplayer(tasks: TaskRepository(client: client), taskLists: TaskListRepository(client: client), isOnline: { network.online })
        let summary = await replayer.replay(outbox)
        XCTAssertEqual(summary.stop, .drained)
        XCTAssertEqual(routes, ["task/create", "task/complete"], "FIFO")
        XCTAssertGreaterThan(outbox.generation, generation, "el ack sube generation (las vistas recargan)")

        await store.loadTasks()
        XCTAssertEqual(store.tasks.map(\.id).sorted(), [7, 70], "sin fila duplicada")
        XCTAssertTrue(store.pendingTaskIds.isEmpty)
        XCTAssertEqual(store.resolve(-1), 70)
    }

    func testLocalListFilterSkipsNetworkAndRemapsAfterAck() async throws {
        let network = Network()
        let (store, outbox, client) = await loaded(network: network, [
            "task-list/create": StubURLProtocol.Stub(status: 201, json: ##"{"id":40,"name":"Viaje","color":"#112233","sort":"custom"}"##)
        ])
        network.online = false
        await store.saveList(name: "Viaje", color: "#112233", sort: "custom", widget: true, dashboard: true, editing: nil)
        let local = try XCTUnwrap(store.taskLists.first { $0.name == "Viaje" }).id
        await store.createTask(title: "Pasaporte", listId: local)

        store.listFilterId = local
        await store.loadTasks()
        await store.loadMembers(listId: local)
        XCTAssertTrue(StubURLProtocol.requests.isEmpty, "una lista local no se pide al servidor")
        XCTAssertEqual(store.tasks.map(\.title), ["Pasaporte"])
        XCTAssertTrue(store.members.isEmpty)

        network.online = true
        let replayer = OutboxReplayer(tasks: TaskRepository(client: client), taskLists: TaskListRepository(client: client), isOnline: { network.online })
        await replayer.replay(outbox)
        await store.loadTasks()
        XCTAssertEqual(store.listFilterId, 40, "el filtro pasa al ID real tras el ack")
        XCTAssertEqual(store.ref(for: local), .remote(40))
    }

    // MARK: - T19

    func testCanReorderRequiresNetworkAndEmptyQueue() async throws {
        let network = Network()
        let (store, outbox, _) = await loaded(network: network)
        store.listFilterId = 2
        XCTAssertTrue(store.canReorder)

        network.online = false
        XCTAssertFalse(store.canReorder, "sin red no se reordena")

        network.online = true
        outbox.enqueue(PendingOp(homeId: "2", kind: .completeTask(ref: .remote(7), listRef: .remote(2), completed: true)))
        XCTAssertFalse(store.canReorder, "con cambios pendientes no se reordena")
    }

    // MARK: - AC7 (cliente)

    func testOnlineCreateRetryReusesClientRequestId() async throws {
        let network = Network()
        let (store, outbox, _) = await loaded(network: network, [
            "task/create": StubURLProtocol.Stub(status: 503, json: #"{"error":"boom"}"#)
        ])
        let ok = await store.createTask(title: "Pan", listId: 2)
        XCTAssertFalse(ok)
        XCTAssertTrue(outbox.isEmpty, "un 5xx en línea no se encola")
        let retry = try XCTUnwrap(store.writeFailure?.retry)
        _ = await retry()
        let keys = StubURLProtocol.requests.filter { Self.route($0) == "task/create" }.map { body($0)["client_request_id"] as? String }
        XCTAssertEqual(keys.count, 2)
        XCTAssertNotNil(keys[0].flatMap(UUID.init(uuidString:)))
        XCTAssertEqual(keys[0], keys[1], "el reintento no duplica: misma clave")
    }

    // MARK: - Inicio (T20)

    private func makeInicio(_ server: Server, network: Network) -> (InicioStore, OutboxStore) {
        installStub(server)
        let client = makeTestClient()
        let outbox = OutboxStore(userId: 1, homeId: "2", directory: directory)
        let store = InicioStore(
            events: EventRepository(client: client), tasks: TaskRepository(client: client),
            routines: RoutineRepository(client: client), taskLists: TaskListRepository(client: client),
            outbox: outbox, isOnline: { network.online }
        )
        return (store, outbox)
    }

    func testInicioOfflineCreateAppearsInPagesAndCompleteRemovesIt() async throws {
        let network = Network()
        let server = Server()
        let (store, outbox) = makeInicio(server, network: network)
        await store.loadTasks()
        await store.loadTaskLists()
        installStub(server)
        network.online = false

        let created = await store.createTask(title: "Pan", listId: 2)
        XCTAssertTrue(created)
        let page = try XCTUnwrap(store.pendingTaskPages.first { $0.id == 2 })
        XCTAssertEqual(page.name, "Compra")
        let pan = try XCTUnwrap(page.tasks.first { $0.title == "Pan" })
        XCTAssertTrue(store.pendingTaskIds.contains(pan.id))

        await store.toggleComplete(pan)
        XCTAssertFalse(store.pendingTaskPages.flatMap(\.tasks).contains { $0.title == "Pan" }, "completar offline la quita")
        XCTAssertEqual(outbox.pendingCount, 2)
        XCTAssertTrue(StubURLProtocol.requests.isEmpty)
        XCTAssertNil(store.writeFailure)

        await store.loadTasks()
        XCTAssertEqual(store.pendingTaskPages.flatMap(\.tasks).map(\.title), ["Leche"], "la recarga no pisa el overlay")
    }
}
