import XCTest
@testable import ControlKit

/// Decisión «enviar o encolar» de las escrituras de tareas y listas (D-024, online-first).
@MainActor
final class TaskWriteCoordinatorTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("outbox-coord-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Store mínimo con el patrón de los stores reales: la op se crea fuera del cierre de reintento.
    private final class WriterStore: WriteFailureReporting {
        var writeFailure: WriteFailure?
        let coordinator: TaskWriteCoordinator

        init(coordinator: TaskWriteCoordinator) {
            self.coordinator = coordinator
        }

        func createTask(title: String, listId: Int) async -> Bool {
            let coordinator = self.coordinator
            let op = await coordinator.makeOp(.createTask(local: coordinator.outbox.makeLocalId(), listRef: .remote(listId), title: title, personIds: nil))
            return await performWrite { store in
                _ = try await store.coordinator.perform(op)
            }
        }
    }

    nonisolated private static func route(_ request: URLRequest) -> String {
        let path = request.url?.path ?? ""
        return path.range(of: "/functions/v1/api/").map { String(path[$0.upperBound...]) } ?? path
    }

    private func clientRequestId(_ request: URLRequest) -> String? {
        guard let data = request.capturedBody,
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        return json["client_request_id"] as? String
    }

    private func makeStore(online: Bool = true, _ handler: @escaping (URLRequest) -> StubURLProtocol.Stub) -> (WriterStore, OutboxStore) {
        StubURLProtocol.reset(handler)
        let client = makeTestClient()
        let outbox = OutboxStore(userId: 1, homeId: "2", directory: directory)
        let coordinator = TaskWriteCoordinator(
            outbox: outbox, tasks: TaskRepository(client: client), taskLists: TaskListRepository(client: client),
            isOnline: { online }
        )
        return (WriterStore(coordinator: coordinator), outbox)
    }

    func testOfflineQueuesWithoutRequest() async {
        let (store, outbox) = makeStore(online: false, ContractFixtures.response)
        let ok = await store.createTask(title: "Leche", listId: 2)
        XCTAssertTrue(ok, "encolar cuenta como éxito para la UI")
        XCTAssertTrue(StubURLProtocol.requests.isEmpty)
        XCTAssertEqual(outbox.pendingCount, 1)
        XCTAssertNil(store.writeFailure)
    }

    func testOnlineSendsWithClientRequestId() async throws {
        let (store, outbox) = makeStore(ContractFixtures.response)
        let ok = await store.createTask(title: "Leche", listId: 2)
        XCTAssertTrue(ok)
        XCTAssertTrue(outbox.isEmpty)
        let create = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(Self.route(create), "task/create")
        XCTAssertNotNil(clientRequestId(create).flatMap(UUID.init(uuidString:)), "el create en línea ya lleva la clave")
    }

    func testNetworkErrorQueuesTheSameUUIDThatWasSent() async throws {
        let (store, outbox) = makeStore { request in
            Self.route(request) == "task/create" ? .offline : ContractFixtures.response(for: request)
        }
        let ok = await store.createTask(title: "Leche", listId: 2)
        XCTAssertTrue(ok)
        XCTAssertNil(store.writeFailure)
        let sent = try XCTUnwrap(StubURLProtocol.requests.first.flatMap(clientRequestId))
        XCTAssertEqual(outbox.ops.map(\.clientRequestId), [sent])
    }

    func testServerErrorKeepsWriteFailureWithRetryAndReusesTheKey() async throws {
        let (store, outbox) = makeStore { request in
            Self.route(request) == "task/create"
                ? StubURLProtocol.Stub(status: 503, json: #"{"error":"boom"}"#)
                : ContractFixtures.response(for: request)
        }
        let ok = await store.createTask(title: "Leche", listId: 2)
        XCTAssertFalse(ok)
        XCTAssertTrue(outbox.isEmpty, "un 5xx en línea no se encola")
        let retry = try XCTUnwrap(store.writeFailure?.retry)
        _ = await retry()
        let keys = StubURLProtocol.requests.filter { Self.route($0) == "task/create" }.map(clientRequestId)
        XCTAssertEqual(keys.count, 2)
        XCTAssertNotNil(keys[0])
        XCTAssertEqual(keys[0], keys[1], "el reintento reusa el mismo client_request_id")
    }

    func testValidationErrorIsRejectedAsToday() async {
        let (store, outbox) = makeStore { request in
            Self.route(request) == "task/create"
                ? StubURLProtocol.Stub(status: 422, json: #"{"error":"Title is required"}"#)
                : ContractFixtures.response(for: request)
        }
        let ok = await store.createTask(title: "Leche", listId: 2)
        XCTAssertFalse(ok)
        XCTAssertTrue(outbox.isEmpty)
        XCTAssertEqual(store.writeFailure?.message, "Title is required")
        XCTAssertNil(store.writeFailure?.retry)
    }

    func testNonEmptyQueueQueuesEvenOnline() async {
        let (store, outbox) = makeStore(ContractFixtures.response)
        outbox.enqueue(PendingOp(homeId: "2", kind: .completeTask(ref: .remote(7), listRef: .remote(2), completed: true)))
        let ok = await store.createTask(title: "Leche", listId: 2)
        XCTAssertTrue(ok)
        XCTAssertTrue(StubURLProtocol.requests.isEmpty, "mantiene el FIFO respecto a lo pendiente")
        XCTAssertEqual(outbox.pendingCount, 2)
    }
}
