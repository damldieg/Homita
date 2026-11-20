import XCTest
@testable import ControlKit

/// Replay de la cola offline (AC2, AC3 FIFO, AC5): bodies reales por StubURLProtocol.
@MainActor
final class OutboxReplayerTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("outbox-replay-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private final class Flag: @unchecked Sendable { var count = 0 }
    private final class FailingRefresher: TokenRefreshing, @unchecked Sendable {
        func refreshSession() async throws { throw APIError.sessionExpired }
    }

    nonisolated private static func route(_ request: URLRequest) -> String {
        let path = request.url?.path ?? ""
        return path.range(of: "/functions/v1/api/").map { String(path[$0.upperBound...]) } ?? path
    }

    private func body(_ request: URLRequest) -> [String: Any] {
        guard let data = request.capturedBody else { return [:] }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    private var routes: [String] { StubURLProtocol.requests.map(Self.route) }

    /// Cliente sobre el stub: `overrides` por ruta; el resto, fixtures del contrato.
    private func makeReplayer(
        refresher: (any TokenRefreshing)? = nil,
        onExpired: (@Sendable () -> Void)? = nil,
        isOnline: @escaping @MainActor () -> Bool = { true },
        _ overrides: [String: StubURLProtocol.Stub] = [:]
    ) -> OutboxReplayer {
        StubURLProtocol.reset { request in
            overrides[Self.route(request)] ?? ContractFixtures.response(for: request)
        }
        let client = makeTestClient(refresher: refresher)
        client.onSessionExpired = onExpired
        return OutboxReplayer(tasks: TaskRepository(client: client), taskLists: TaskListRepository(client: client), isOnline: isOnline)
    }

    private func makeOutbox(_ kinds: [PendingOp.Kind]) -> OutboxStore {
        let outbox = OutboxStore(userId: 1, homeId: "2", directory: directory)
        for kind in kinds { outbox.enqueue(PendingOp(homeId: "2", kind: kind)) }
        return outbox
    }

    // MARK: - AC2 y AC3

    func testTaskInLocalListUsesRemoteId() async throws {
        let replayer = makeReplayer([
            "task-list/create": StubURLProtocol.Stub(status: 201, json: ##"{"id":40,"name":"Viaje","color":"#112233","sort":"custom"}"##),
            "task/create": StubURLProtocol.Stub(status: 201, json: #"{"id":70,"task_list_id":40,"title":"Pasaporte"}"#)
        ])
        let outbox = makeOutbox([
            .createList(local: -1, name: "Viaje", color: "#112233", sort: "custom", widget: true, dashboard: true),
            .createTask(local: -2, listRef: .local(-1), title: "Pasaporte", personIds: nil)
        ])
        let listOp = outbox.ops[0]
        let taskOp = outbox.ops[1]

        let summary = await replayer.replay(outbox)

        XCTAssertEqual(summary, ReplaySummary(acked: 2, discarded: 0, stop: .drained))
        let requests = StubURLProtocol.requests
        XCTAssertEqual(requests.map(Self.route), ["task-list/create", "task/create"])
        XCTAssertEqual(body(requests[0])["client_request_id"] as? String, listOp.clientRequestId)
        let taskBody = body(requests[1])
        XCTAssertEqual(taskBody["task_list_id"] as? Int, 40, "la tarea viaja con el ID real de la lista")
        XCTAssertEqual(taskBody["client_request_id"] as? String, taskOp.clientRequestId)
        XCTAssertEqual(outbox.idMap, [-1: 40, -2: 70])
        XCTAssertTrue(outbox.isEmpty)
    }

    func testFIFOOrder() async {
        let replayer = makeReplayer()
        let outbox = makeOutbox([
            .completeTask(ref: .remote(7), listRef: .remote(2), completed: true),
            .updateList(ref: .remote(2), name: "Compra", color: "#6923E2", sort: "custom", widget: true, dashboard: true),
            .deleteTask(ref: .remote(8), listRef: .remote(2)),
            .updateTask(ref: .remote(9), listRef: .remote(2), title: "Pan", personIds: nil)
        ])
        await replayer.replay(outbox)
        XCTAssertEqual(routes, ["task/complete", "task-list/update", "task/delete", "task/update"])
    }

    func testGenerationBumps() async {
        let replayer = makeReplayer()
        let outbox = makeOutbox([
            .completeTask(ref: .remote(7), listRef: .remote(2), completed: true),
            .deleteTask(ref: .remote(8), listRef: .remote(2))
        ])
        XCTAssertEqual(outbox.generation, 0)
        await replayer.replay(outbox)
        XCTAssertEqual(outbox.generation, 2, "una subida por ack")
    }

    func testConcurrentReplaysShareOnePass() async {
        let replayer = makeReplayer(["task/complete": StubURLProtocol.Stub(json: ContractFixtures.task, delay: 0.1)])
        let outbox = makeOutbox([.completeTask(ref: .remote(7), listRef: .remote(2), completed: true)])
        async let first = replayer.replay(outbox)
        async let second = replayer.replay(outbox)
        let results = await [first, second]
        XCTAssertEqual(routes, ["task/complete"], "vuelo único: la op se envía una vez")
        XCTAssertEqual(results[0], results[1])
    }

    func testOfflineDoesNotSend() async {
        let replayer = makeReplayer(isOnline: { false })
        let outbox = makeOutbox([.completeTask(ref: .remote(7), listRef: .remote(2), completed: true)])
        let summary = await replayer.replay(outbox)
        XCTAssertEqual(summary.stop, .offline)
        XCTAssertTrue(StubURLProtocol.requests.isEmpty)
        XCTAssertEqual(outbox.pendingCount, 1)
    }

    func testCancelledReplayKeepsEverything() async {
        let replayer = makeReplayer()
        let outbox = makeOutbox([
            .completeTask(ref: .remote(7), listRef: .remote(2), completed: true),
            .deleteTask(ref: .remote(8), listRef: .remote(2))
        ])
        let task = Task { await replayer.replay(outbox) }
        task.cancel()
        let summary = await task.value
        XCTAssertEqual(summary.stop, .cancelled)
        XCTAssertEqual(outbox.pendingCount, 2)
        XCTAssertNil(outbox.inFlightId)
    }

    // MARK: - AC5: errores

    func testNetworkErrorKeepsOpAndStops() async {
        let replayer = makeReplayer(["task/complete": .offline])
        let outbox = makeOutbox([
            .completeTask(ref: .remote(7), listRef: .remote(2), completed: true),
            .deleteTask(ref: .remote(8), listRef: .remote(2))
        ])
        let summary = await replayer.replay(outbox)
        XCTAssertEqual(summary.stop, .retryable)
        XCTAssertEqual(routes, ["task/complete"], "no sigue con la siguiente")
        XCTAssertEqual(outbox.pendingCount, 2)
        XCTAssertEqual(outbox.ops.first?.attempts, 1)
        XCTAssertTrue(outbox.notices.isEmpty)
    }

    func testServerErrorKeepsOpAndStops() async {
        let replayer = makeReplayer(["task/update": StubURLProtocol.Stub(status: 503, json: #"{"error":"boom"}"#)])
        let outbox = makeOutbox([
            .updateTask(ref: .remote(7), listRef: .remote(2), title: "Pan", personIds: nil),
            .deleteTask(ref: .remote(8), listRef: .remote(2))
        ])
        let summary = await replayer.replay(outbox)
        XCTAssertEqual(summary.stop, .retryable)
        XCTAssertEqual(outbox.pendingCount, 2)
        XCTAssertEqual(outbox.ops.first?.attempts, 1)
        XCTAssertEqual(outbox.generation, 0)
    }

    func testNotFoundDiscardsWithDependentsAndNotice() async {
        // `task/*` responde 500 «Not Found»: se evalúa antes que el reintento de 5xx (R5).
        let replayer = makeReplayer(["task/update": StubURLProtocol.Stub(status: 500, json: #"{"error":"Not Found"}"#)])
        let outbox = makeOutbox([
            .updateTask(ref: .remote(7), listRef: .remote(2), title: "Pan", personIds: nil),
            .completeTask(ref: .remote(7), listRef: .remote(2), completed: true),
            .completeTask(ref: .remote(9), listRef: .remote(2), completed: true)
        ])
        let summary = await replayer.replay(outbox)
        XCTAssertEqual(summary, ReplaySummary(acked: 1, discarded: 1, stop: .drained))
        XCTAssertEqual(routes, ["task/update", "task/complete"])
        XCTAssertEqual(body(StubURLProtocol.requests[1])["id"] as? Int, 9, "el complete de la tarea que no existe se descarta")
        XCTAssertEqual(outbox.notices.map(\.message), ["No se pudo sincronizar «Pan»: ya no existe."])
    }

    func testOwnerOnlyDiscardsWithNotice() async {
        let replayer = makeReplayer(["task-list/update": StubURLProtocol.Stub(status: 403, json: #"{"error":"Not Allowed"}"#)])
        let outbox = makeOutbox([
            .updateList(ref: .remote(2), name: "Súper", color: "#000000", sort: "title", widget: true, dashboard: true),
            .completeTask(ref: .remote(7), listRef: .remote(2), completed: true)
        ])
        let summary = await replayer.replay(outbox)
        XCTAssertEqual(summary, ReplaySummary(acked: 1, discarded: 1, stop: .drained))
        XCTAssertEqual(routes, ["task-list/update", "task/complete"], "un 403 no arrastra las ops de las tareas")
        XCTAssertEqual(outbox.notices.count, 1)
        XCTAssertTrue(outbox.notices[0].message.hasPrefix("No se pudo sincronizar la lista «Súper»."))
    }

    func testBadRequestOnLocalCreateDiscardsItsDependents() async {
        let replayer = makeReplayer(["task-list/create": StubURLProtocol.Stub(status: 400, json: #"{"error":"Color must be #RRGGBB"}"#)])
        let outbox = makeOutbox([
            .createList(local: -1, name: "Viaje", color: "x", sort: "custom", widget: true, dashboard: true),
            .createTask(local: -2, listRef: .local(-1), title: "Pasaporte", personIds: nil),
            .completeTask(ref: .local(-2), listRef: .local(-1), completed: true)
        ])
        let summary = await replayer.replay(outbox)
        XCTAssertEqual(summary, ReplaySummary(acked: 0, discarded: 1, stop: .drained))
        XCTAssertEqual(routes, ["task-list/create"])
        XCTAssertTrue(outbox.isEmpty)
        XCTAssertEqual(outbox.notices.map(\.message), ["No se pudo sincronizar la lista «Viaje». El color debe ser #RRGGBB"])
    }

    func testDeleteNotFoundIsSilentSuccess() async {
        let replayer = makeReplayer(["task/delete": StubURLProtocol.Stub(status: 500, json: #"{"error":"Not Found"}"#)])
        let outbox = makeOutbox([.deleteTask(ref: .remote(7), listRef: .remote(2))])
        let summary = await replayer.replay(outbox)
        XCTAssertEqual(summary, ReplaySummary(acked: 1, discarded: 0, stop: .drained))
        XCTAssertTrue(outbox.isEmpty)
        XCTAssertTrue(outbox.notices.isEmpty)
        XCTAssertEqual(outbox.generation, 1)
    }

    func testSessionExpiredPausesAndKeepsAllOps() async {
        let flag = Flag()
        let refresher = FailingRefresher() // APIClient.refresher es weak
        let replayer = makeReplayer(
            refresher: refresher, onExpired: { flag.count += 1 },
            ["task/complete": StubURLProtocol.Stub(status: 401, json: #"{"error":"Unauthorized"}"#)]
        )
        let outbox = makeOutbox([
            .completeTask(ref: .remote(7), listRef: .remote(2), completed: true),
            .deleteTask(ref: .remote(8), listRef: .remote(2))
        ])
        let summary = await replayer.replay(outbox)
        XCTAssertEqual(summary.stop, .sessionExpired)
        XCTAssertEqual(flag.count, 1, "se dispara onSessionExpired")
        XCTAssertEqual(outbox.pendingCount, 2)
        XCTAssertEqual(outbox.ops.first?.attempts, 0)
        XCTAssertTrue(outbox.notices.isEmpty)
        withExtendedLifetime(refresher) {}
    }

    func testUnresolvedLocalRefIsDiscardedSilently() async {
        let replayer = makeReplayer()
        let outbox = makeOutbox([.completeTask(ref: .local(-5), listRef: .remote(2), completed: true)])
        let summary = await replayer.replay(outbox)
        XCTAssertEqual(summary.discarded, 1)
        XCTAssertTrue(StubURLProtocol.requests.isEmpty)
        XCTAssertTrue(outbox.notices.isEmpty)
    }

    func testDecodingAfterSuccessRetriesCreatesButAcksOthers() async {
        let replayer = makeReplayer([
            "task/update": StubURLProtocol.Stub(json: "{}"),
            "task/create": StubURLProtocol.Stub(status: 201, json: "{}")
        ])
        let outbox = makeOutbox([
            .updateTask(ref: .remote(7), listRef: .remote(2), title: "Pan", personIds: nil),
            .createTask(local: -1, listRef: .remote(2), title: "Leche", personIds: nil)
        ])
        let summary = await replayer.replay(outbox)
        XCTAssertEqual(summary, ReplaySummary(acked: 1, discarded: 0, stop: .retryable))
        XCTAssertEqual(outbox.pendingCount, 1, "el create se reenviará con la misma clave")
        XCTAssertEqual(outbox.ops.first?.attempts, 1)
    }

    func testDispositionOrder() {
        let update = PendingOp.Kind.updateTask(ref: .remote(1), listRef: .remote(2), title: "x", personIds: nil)
        let delete = PendingOp.Kind.deleteTask(ref: .remote(1), listRef: .remote(2))
        XCTAssertEqual(OutboxReplayer.disposition(for: .http(status: 500, message: "Not Found"), kind: update), .discard(cascade: true))
        XCTAssertEqual(OutboxReplayer.disposition(for: .http(status: 404, message: "Not Found"), kind: delete), .ack)
        XCTAssertEqual(OutboxReplayer.disposition(for: .http(status: 403, message: "Not Allowed"), kind: update), .discard(cascade: false))
        XCTAssertEqual(OutboxReplayer.disposition(for: .sessionExpired, kind: update), .pause)
        XCTAssertEqual(OutboxReplayer.disposition(for: .http(status: 502, message: "boom"), kind: update), .retry)
        XCTAssertEqual(OutboxReplayer.disposition(for: .network("x"), kind: delete), .retry)
    }
}
