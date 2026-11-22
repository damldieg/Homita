import XCTest
@testable import ControlKit

/// Prioridad de tarea (0037, D-026): decode tolerante, requests, cola offline (fixture de una op
/// encolada antes de la prioridad), compactor, overlay y orden/filtro en cliente.
final class TaskPriorityTests: XCTestCase {
    private func json<T: Encodable>(_ value: T) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as! [String: Any]
    }

    private func task(_ id: Int, _ priority: String?, order: Int, completed: Bool = false, list: Int = 2) -> TaskEntry {
        TaskEntry(
            id: id, task_list_id: list, title: "T\(id)", completed_at: completed ? "2026-11-20 10:00:00" : nil,
            created_at: nil, updated_at: nil, order: FlexInt(order), task_list_color: nil, task_list_name: nil,
            persons: nil, priority: priority
        )
    }

    // MARK: - Modelo

    func testDecodeAbsentKnownAndUnknownPriority() throws {
        let data = Data(#"""
        [{"id":1,"task_list_id":2,"title":"A"},
         {"id":2,"task_list_id":2,"title":"B","priority":"alta"},
         {"id":3,"task_list_id":2,"title":"C","priority":"urgentisima"},
         {"id":4,"task_list_id":2,"title":"D","priority":null}]
        """#.utf8)
        let tasks = try JSONDecoder().decode([TaskEntry].self, from: data)
        XCTAssertEqual(tasks.map(\.priority), [nil, "alta", "urgentisima", nil])
        XCTAssertEqual(tasks.map(\.priorityValue), [.media, .alta, .media, .media], "ausente o desconocida → media")
    }

    func testPriorityRankAndLabel() {
        XCTAssertEqual(TaskPriority.allCases.map(\.rank), [1, 2, 3])
        XCTAssertEqual(TaskPriority.allCases.map(\.label), ["Alta", "Media", "Baja"])
        XCTAssertEqual(TaskPriority(raw: "baja"), .baja)
        XCTAssertEqual(TaskPriority(raw: "ALTA"), .media, "sensible a mayúsculas, como la API")
    }

    func testPriorityTint() {
        XCTAssertEqual(TaskPriority.allCases.map(\.tintHex), [Palette.accentHex, Palette.soonHex, Palette.sageHex])
    }

    // MARK: - Requests

    func testCreateAndUpdateEncodePriorityOnlyWhenPresent() throws {
        XCTAssertNil(try json(CreateTaskRequest(task_list_id: 3, title: "Pan"))["priority"])
        XCTAssertEqual(try json(CreateTaskRequest(task_list_id: 3, title: "Pan", priority: "alta"))["priority"] as? String, "alta")
        XCTAssertNil(try json(UpdateTaskRequest(id: 1, title: "Pan"))["priority"])
        XCTAssertEqual(try json(UpdateTaskRequest(id: 1, title: "Pan", priority: "baja"))["priority"] as? String, "baja")
    }

    // MARK: - Cola offline

    /// JSON tal como lo escribía la build de 0035 (D-024), sin la clave `priority`: se sigue leyendo
    /// y, al volver a codificarlo, tampoco aparece la clave (R4).
    func testLegacyQueuedOpsDecodeWithoutPriority() throws {
        let legacy = Data(#"""
        [{"id":"8A1F5A8E-2B7C-4F4E-9A0B-1C2D3E4F5A6B","createdAt":721692800,"homeId":"2","attempts":1,
          "kind":{"createTask":{"local":-1,"listRef":{"remote":{"_0":2}},"title":"Leche","personIds":[5]}}},
         {"id":"9B2F5A8E-2B7C-4F4E-9A0B-1C2D3E4F5A6B","createdAt":721692801,"homeId":"2","attempts":0,
          "kind":{"updateTask":{"ref":{"remote":{"_0":7}},"listRef":{"remote":{"_0":2}},"title":"Pan"}}}]
        """#.utf8)
        let ops = try JSONDecoder().decode([PendingOp].self, from: legacy)
        XCTAssertEqual(ops.map(\.kind), [
            .createTask(local: -1, listRef: .remote(2), title: "Leche", personIds: [5], priority: nil),
            .updateTask(ref: .remote(7), listRef: .remote(2), title: "Pan", personIds: nil, priority: nil)
        ])
        let reencoded = String(decoding: try JSONEncoder().encode(ops), as: UTF8.self)
        XCTAssertFalse(reencoded.contains("priority"))
        XCTAssertEqual(try JSONDecoder().decode([PendingOp].self, from: Data(reencoded.utf8)), ops)
    }

    func testOpsWithPriorityRoundTrip() throws {
        for kind: PendingOp.Kind in [
            .createTask(local: -1, listRef: .remote(2), title: "Leche", personIds: nil, priority: "alta"),
            .updateTask(ref: .remote(7), listRef: .remote(2), title: "Pan", personIds: [], priority: "baja")
        ] {
            let op = PendingOp(createdAt: Date(timeIntervalSince1970: 1_700_000_000), homeId: "1", kind: kind)
            XCTAssertEqual(try JSONDecoder().decode(PendingOp.self, from: JSONEncoder().encode(op)), op)
        }
    }

    func testCompactorMergesPriorityLastNonNilWins() {
        let op = { (kind: PendingOp.Kind) in PendingOp(homeId: "1", kind: kind) }
        var queue = OutboxCompactor.enqueue(op(.createTask(local: -1, listRef: .remote(2), title: "Leche", personIds: nil, priority: "alta")), into: [], inFlight: nil)
        queue = OutboxCompactor.enqueue(op(.updateTask(ref: .local(-1), listRef: .remote(2), title: "Leche entera", personIds: nil)), into: queue, inFlight: nil)
        XCTAssertEqual(queue.map(\.kind), [.createTask(local: -1, listRef: .remote(2), title: "Leche entera", personIds: nil, priority: "alta")])
        queue = OutboxCompactor.enqueue(op(.updateTask(ref: .local(-1), listRef: .remote(2), title: "Leche entera", personIds: nil, priority: "baja")), into: queue, inFlight: nil)
        XCTAssertEqual(queue.map(\.kind), [.createTask(local: -1, listRef: .remote(2), title: "Leche entera", personIds: nil, priority: "baja")])

        var updates = OutboxCompactor.enqueue(op(.updateTask(ref: .remote(7), listRef: .remote(2), title: "A", personIds: nil, priority: "alta")), into: [], inFlight: nil)
        updates = OutboxCompactor.enqueue(op(.updateTask(ref: .remote(7), listRef: .remote(2), title: "B", personIds: nil)), into: updates, inFlight: nil)
        XCTAssertEqual(updates.map(\.kind), [.updateTask(ref: .remote(7), listRef: .remote(2), title: "B", personIds: nil, priority: "alta")])
    }

    func testOverlayAppliesPendingPriority() throws {
        let milk = task(7, "media", order: 1)
        let result = PendingOverlay.apply(
            ops: [
                PendingOp(homeId: "1", kind: .updateTask(ref: .remote(7), listRef: .remote(2), title: "Leche", personIds: nil, priority: "alta")),
                PendingOp(homeId: "1", kind: .createTask(local: -1, listRef: .remote(2), title: "Pan", personIds: nil)),
                PendingOp(homeId: "1", kind: .createTask(local: -2, listRef: .remote(2), title: "Sal", personIds: nil, priority: "baja"))
            ],
            idMap: [:], tasks: [milk], lists: []
        )
        XCTAssertEqual(result.tasks.map(\.priorityValue), [.alta, .media, .baja])
        XCTAssertEqual(result.tasks.first { $0.id == -1 }?.priority, "media", "create offline sin prioridad → media, como el servidor")
        // Update sin prioridad conserva la que había.
        let kept = PendingOverlay.apply(
            ops: [PendingOp(homeId: "1", kind: .updateTask(ref: .remote(7), listRef: .remote(2), title: "Leche 2", personIds: nil))],
            idMap: [:], tasks: [task(7, "baja", order: 1)], lists: []
        )
        XCTAssertEqual(kept.tasks.first?.priority, "baja")
    }

    // MARK: - Orden y filtro (función pura)

    func testListModeWithoutFilterIsUnchanged() {
        let tasks = [task(1, "baja", order: 1), task(2, "alta", order: 2), task(3, nil, order: 3), task(4, "alta", order: 1, completed: true)]
        XCTAssertEqual(TaskPriorityOrdering.apply(tasks, sort: .list, filter: nil), tasks)
    }

    func testPrioritySortTieBreaksByListOrderAndKeepsCompletedLast() {
        let tasks = [
            task(1, "baja", order: 1), task(2, "alta", order: 2), task(3, nil, order: 3),
            task(4, "alta", order: 4), task(5, "alta", order: 1, completed: true), task(6, "baja", order: 2, completed: true)
        ]
        let sorted = TaskPriorityOrdering.apply(tasks, sort: .priority, filter: nil)
        XCTAssertEqual(sorted.map(\.id), [2, 4, 3, 1, 5, 6])
    }

    func testFilterKeepsOnlyThatPriority() {
        let tasks = [task(1, "baja", order: 1), task(2, "alta", order: 2), task(3, nil, order: 3)]
        XCTAssertEqual(TaskPriorityOrdering.apply(tasks, sort: .list, filter: .media).map(\.id), [3], "nil cuenta como media")
        XCTAssertEqual(TaskPriorityOrdering.apply(tasks, sort: .priority, filter: .alta).map(\.id), [2])
    }
}

/// `TasksStore` con orden y filtro por prioridad (0037): valores por defecto = vista de siempre,
/// preferencias en UserDefaults, pendientes offline incluidas y reordenar desactivado.
@MainActor
final class TaskPriorityStoreTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("outbox-priority-\(UUID().uuidString)", isDirectory: true)
        suite = "TaskPriorityStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: suite)
    }

    nonisolated private static func route(_ request: URLRequest) -> String {
        let path = request.url?.path ?? ""
        return path.range(of: "/functions/v1/api/").map { String(path[$0.upperBound...]) } ?? path
    }

    private static let serverTasks = #"""
    [{"id":1,"task_list_id":2,"title":"Pan","order":1,"priority":"baja"},
     {"id":2,"task_list_id":2,"title":"Leche","order":2,"priority":"alta"},
     {"id":3,"task_list_id":2,"title":"Sal","order":3}]
    """#

    private final class Network { var online = true }

    private func makeStore(network: Network = Network()) async -> (TasksStore, OutboxStore) {
        StubURLProtocol.reset { request in
            switch (request.httpMethod ?? "GET", Self.route(request)) {
            case ("GET", "task"): return StubURLProtocol.Stub(json: Self.serverTasks)
            case ("GET", "task-list"): return StubURLProtocol.Stub(json: "[\(ContractFixtures.taskList)]")
            default: return ContractFixtures.response(for: request)
            }
        }
        let client = makeTestClient()
        let outbox = OutboxStore(userId: 1, homeId: "2", directory: directory)
        let store = TasksStore(
            taskLists: TaskListRepository(client: client), tasks: TaskRepository(client: client),
            outbox: outbox, isOnline: { network.online }, defaults: defaults
        )
        await store.loadLists()
        await store.loadTasks()
        return (store, outbox)
    }

    func testDefaultsAreListOrderWithoutFilter() async {
        let (store, _) = await makeStore()
        XCTAssertEqual(store.sortMode, .list)
        XCTAssertNil(store.priorityFilter)
        XCTAssertFalse(store.hasPriorityView)
        XCTAssertEqual(store.pendingTasks.map(\.id), [1, 2, 3], "mismo orden que el servidor")
    }

    func testSortAndFilterPersistAcrossStores() async {
        let (store, _) = await makeStore()
        store.sortMode = .priority
        XCTAssertEqual(store.pendingTasks.map(\.id), [2, 3, 1])
        store.priorityFilter = .baja
        XCTAssertEqual(store.pendingTasks.map(\.id), [1])

        let (again, _) = await makeStore()
        XCTAssertEqual(again.sortMode, .priority)
        XCTAssertEqual(again.priorityFilter, .baja)
        again.priorityFilter = nil
        let (third, _) = await makeStore()
        XCTAssertNil(third.priorityFilter, "«Todas» también se guarda")
    }

    func testOfflinePendingTaskIsSortedAndFiltered() async {
        let network = Network()
        let (store, _) = await makeStore(network: network)
        network.online = false
        let created = await store.createTask(title: "Huevos", listId: 2, priority: .alta)
        XCTAssertTrue(created)
        store.sortMode = .priority
        XCTAssertEqual(store.pendingTasks.map(\.title), ["Leche", "Huevos", "Sal", "Pan"])
        store.priorityFilter = .alta
        XCTAssertEqual(store.pendingTasks.map(\.title), ["Leche", "Huevos"])
    }

    func testReorderDisabledWithPrioritySortOrFilter() async {
        let (store, _) = await makeStore()
        store.listFilterId = 2
        XCTAssertTrue(store.canReorder, "lista personalizada, con red y cola vacía")
        store.sortMode = .priority
        XCTAssertFalse(store.canReorder)
        store.sortMode = .list
        store.priorityFilter = .media
        XCTAssertFalse(store.canReorder)
    }

    /// R1-01: el detalle de lista muestra el orden de la lista y no aplica la vista por prioridad,
    /// así que «Reordenar» sigue disponible aunque haya un orden o filtro global por prioridad.
    func testListDetailKeepsReorderWithPriorityView() async {
        let network = Network()
        let (store, _) = await makeStore(network: network)
        store.listFilterId = 2
        store.sortMode = .priority
        XCTAssertFalse(store.canReorder, "la pestaña Tareas bloquea el reorden")
        XCTAssertTrue(store.canReorderList, "el detalle de lista mantiene «Reordenar» con orden por prioridad")
        store.sortMode = .list
        store.priorityFilter = .alta
        XCTAssertTrue(store.canReorderList, "el detalle de lista mantiene «Reordenar» con filtro por prioridad")
        network.online = false
        XCTAssertFalse(store.canReorderList, "sin red no se reordena ni en el detalle")
    }

    func testReplaySendsQueuedPriority() async {
        StubURLProtocol.reset { request in ContractFixtures.response(for: request) }
        let client = makeTestClient()
        let replayer = OutboxReplayer(tasks: TaskRepository(client: client), taskLists: TaskListRepository(client: client), isOnline: { true })
        let outbox = OutboxStore(userId: 1, homeId: "2", directory: directory)
        outbox.enqueue(PendingOp(homeId: "2", kind: .createTask(local: -1, listRef: .remote(2), title: "Huevos", personIds: nil, priority: "alta")))
        outbox.enqueue(PendingOp(homeId: "2", kind: .updateTask(ref: .remote(7), listRef: .remote(2), title: "Pan", personIds: nil, priority: "baja")))
        outbox.enqueue(PendingOp(homeId: "2", kind: .updateTask(ref: .remote(8), listRef: .remote(2), title: "Sal", personIds: nil)))
        await replayer.replay(outbox)
        let bodies = StubURLProtocol.requests.map {
            (try? JSONSerialization.jsonObject(with: $0.capturedBody ?? Data())) as? [String: Any] ?? [:]
        }
        XCTAssertEqual(StubURLProtocol.requests.map(Self.route), ["task/create", "task/update", "task/update"])
        XCTAssertEqual(bodies[0]["priority"] as? String, "alta")
        XCTAssertEqual(bodies[1]["priority"] as? String, "baja")
        XCTAssertNil(bodies[2]["priority"])
    }

    func testCreateAndUpdateSendPriorityOnlyWhenChosenOrChanged() async throws {
        let (store, _) = await makeStore()
        let leche = try XCTUnwrap(store.tasks.first { $0.id == 2 })
        StubURLProtocol.reset { request in ContractFixtures.response(for: request) }
        await store.createTask(title: "Huevos", listId: 2, priority: .alta)
        await store.updateTask(leche, title: "Leche entera", priority: .alta)
        await store.updateTask(leche, title: "Leche entera", priority: .baja)
        let bodies = StubURLProtocol.requests
            .filter { ["task/create", "task/update"].contains(Self.route($0)) }
            .map { (try? JSONSerialization.jsonObject(with: $0.capturedBody ?? Data())) as? [String: Any] ?? [:] }
        XCTAssertEqual(bodies.count, 3)
        XCTAssertEqual(bodies[0]["priority"] as? String, "alta")
        XCTAssertNil(bodies[1]["priority"], "sin cambio de prioridad no se envía (no pisa a otro usuario)")
        XCTAssertEqual(bodies[2]["priority"] as? String, "baja")
    }
}
