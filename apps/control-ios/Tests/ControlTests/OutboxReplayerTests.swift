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

    /// R1-02: la UI y `BackgroundRefresh` tienen replayers distintos sobre la misma `OutboxStore`. El
    /// vuelo único es por store: cada op sale una vez y en orden, también la encolada durante el vuelo.
    func testTwoReplayersOnSameStoreSendEachOpOnceInOrder() async {
        let overrides = [
            "task/update": StubURLProtocol.Stub(json: ContractFixtures.task, delay: 0.1),
            "task/complete": StubURLProtocol.Stub(json: ContractFixtures.task, delay: 0.1)
        ]
        let first = makeReplayer(overrides)
        let client = makeTestClient()
        let second = OutboxReplayer(tasks: TaskRepository(client: client), taskLists: TaskListRepository(client: client), isOnline: { true })
        let outbox = makeOutbox([
            .updateTask(ref: .remote(9), listRef: .remote(2), title: "A", personIds: nil),
            .completeTask(ref: .remote(7), listRef: .remote(2), completed: true)
        ])

        let pass1 = Task { await first.replay(outbox) }
        while outbox.inFlightId == nil { await Task.yield() }
        // Llega durante el vuelo de «A»: va al final, no se funde con la op en vuelo.
        outbox.enqueue(PendingOp(homeId: "2", kind: .updateTask(ref: .remote(9), listRef: .remote(2), title: "B", personIds: nil)))
        let pass2 = Task { await second.replay(outbox) }
        let results = await [pass1.value, pass2.value]

        XCTAssertEqual(routes, ["task/update", "task/complete", "task/update"], "cada op se envía una sola vez")
        let titles = StubURLProtocol.requests.filter { Self.route($0) == "task/update" }.map { body($0)["title"] as? String }
        XCTAssertEqual(titles, ["A", "B"], "el último cambio del usuario llega el último")
        XCTAssertEqual(results[0], results[1], "el segundo replayer espera a la misma pasada")
        XCTAssertEqual(results[0], ReplaySummary(acked: 3, discarded: 0, stop: .drained))
        XCTAssertTrue(outbox.isEmpty)
        XCTAssertNil(outbox.replayTask)
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

    // MARK: - 0038: personas al reproducir (AC-5, AC-9)

    /// Personas del hogar: Ana (cuenta 1), Beto (cuenta 9) y Luz (sin cuenta).
    private static let roster = ##"[{"id":1,"user_id":1,"name":"Ana","color":"#FF0000","app_user_id":1},{"id":2,"user_id":1,"name":"Beto","color":"#00FF00","app_user_id":9},{"id":3,"user_id":1,"name":"Luz","color":"#0000FF"}]"##
    /// ACL de la lista 2 solo con la cuenta 1 (Beto perdió el acceso).
    private static let membersWithoutBeto = #"[{"tlu_id":10,"user_id":1,"name":"Demo","email":"demo@homita.example","role":"owner"}]"#
    private static let invalidPerson = StubURLProtocol.Stub(status: 400, json: #"{"error":"Invalid person"}"#)
    private static let created = StubURLProtocol.Stub(status: 201, json: #"{"id":70,"task_list_id":2,"title":"Pan"}"#)

    /// Respuestas por ruta en secuencia (contador por ruta): la última se repite.
    private final class Sequence: @unchecked Sendable {
        private let lock = NSLock()
        private var counts: [String: Int] = [:]
        func next(_ route: String, _ stubs: [StubURLProtocol.Stub]) -> StubURLProtocol.Stub {
            lock.lock(); defer { lock.unlock() }
            let index = counts[route, default: 0]
            counts[route] = index + 1
            return stubs[min(index, stubs.count - 1)]
        }
    }

    /// Replayer con `persons` y stubs secuenciales por ruta; el resto, fixtures del contrato.
    private func makeSequencedReplayer(_ sequences: [String: [StubURLProtocol.Stub]]) -> OutboxReplayer {
        let sequence = Sequence()
        StubURLProtocol.reset { request in
            let route = Self.route(request)
            if let stubs = sequences[route] { return sequence.next(route, stubs) }
            return ContractFixtures.response(for: request)
        }
        let client = makeTestClient()
        return OutboxReplayer(tasks: TaskRepository(client: client), taskLists: TaskListRepository(client: client),
                              persons: PersonRepository(client: client), isOnline: { true })
    }

    private var createBodies: [[String: Any]] {
        StubURLProtocol.requests.filter { Self.route($0) == "task/create" }.map(body)
    }

    func testCreateWithPersonsIsSentOnceWithPersonsAndKey() async {
        let replayer = makeSequencedReplayer(["task/create": [Self.created]])
        let outbox = makeOutbox([.createTask(local: -1, listRef: .remote(2), title: "Pan", personIds: [1])])
        let op = outbox.ops[0]
        let summary = await replayer.replay(outbox)
        XCTAssertEqual(summary, ReplaySummary(acked: 1, discarded: 0, stop: .drained))
        XCTAssertEqual(routes, ["task/create"], "una sola petición")
        XCTAssertEqual(createBodies[0]["person_ids"] as? [Int], [1])
        XCTAssertEqual(createBodies[0]["client_request_id"] as? String, op.clientRequestId)
        XCTAssertTrue(outbox.notices.isEmpty)
    }

    func testInvalidPersonResendsWithAssignableOnesAndNotice() async {
        let replayer = makeSequencedReplayer([
            "task/create": [Self.invalidPerson, Self.created],
            "person": [StubURLProtocol.Stub(json: Self.roster)],
            "task-list/user": [StubURLProtocol.Stub(json: Self.membersWithoutBeto)]
        ])
        let outbox = makeOutbox([.createTask(local: -1, listRef: .remote(2), title: "Pan", personIds: [1, 2], priority: "alta")])
        let op = outbox.ops[0]
        let summary = await replayer.replay(outbox)
        XCTAssertEqual(summary, ReplaySummary(acked: 1, discarded: 0, stop: .drained))
        XCTAssertEqual(routes, ["task/create", "person", "task-list/user", "task/create"])
        let bodies = createBodies
        XCTAssertEqual(bodies[0]["person_ids"] as? [Int], [1, 2])
        XCTAssertEqual(bodies[1]["person_ids"] as? [Int], [1], "se quita solo la persona sin acceso")
        XCTAssertEqual(bodies[1]["client_request_id"] as? String, op.clientRequestId, "misma clave")
        XCTAssertEqual(bodies[1]["priority"] as? String, "alta", "se conserva la prioridad")
        XCTAssertEqual(bodies[1]["title"] as? String, "Pan")
        XCTAssertTrue(outbox.isEmpty, "la tarea no se descarta")
        XCTAssertEqual(outbox.idMap, [-1: 70])
        XCTAssertEqual(outbox.notices.map(\.message), ["«Pan» se sincronizó sin asignar a Beto: ya no tiene acceso a la lista."])
    }

    func testSecondInvalidPersonResendsWithoutPersons() async {
        let replayer = makeSequencedReplayer([
            "task/create": [Self.invalidPerson, Self.invalidPerson, Self.created],
            "person": [StubURLProtocol.Stub(json: Self.roster)],
            "task-list/user": [StubURLProtocol.Stub(json: Self.membersWithoutBeto)]
        ])
        let outbox = makeOutbox([.createTask(local: -1, listRef: .remote(2), title: "Pan", personIds: [1, 2], priority: "baja")])
        let op = outbox.ops[0]
        let summary = await replayer.replay(outbox)
        XCTAssertEqual(summary, ReplaySummary(acked: 1, discarded: 0, stop: .drained))
        let bodies = createBodies
        XCTAssertEqual(bodies.count, 3)
        XCTAssertEqual(bodies[1]["person_ids"] as? [Int], [1])
        XCTAssertNil(bodies[2]["person_ids"], "último escalón: sin la clave")
        XCTAssertEqual(bodies[2]["client_request_id"] as? String, op.clientRequestId)
        XCTAssertEqual(bodies[2]["priority"] as? String, "baja")
        XCTAssertTrue(outbox.isEmpty)
        XCTAssertEqual(outbox.notices.map(\.message), ["«Pan» se sincronizó sin asignar a Ana y Beto: ya no tienen acceso a la lista."])
    }

    func testInvalidPersonWithoutAssignableGoesStraightToNoPersons() async {
        let replayer = makeSequencedReplayer([
            "task/create": [Self.invalidPerson, Self.created],
            "person": [StubURLProtocol.Stub(json: Self.roster)],
            "task-list/user": [StubURLProtocol.Stub(json: Self.membersWithoutBeto)]
        ])
        let outbox = makeOutbox([.createTask(local: -1, listRef: .remote(2), title: "Pan", personIds: [3])])
        let summary = await replayer.replay(outbox)
        XCTAssertEqual(summary.acked, 1)
        XCTAssertEqual(createBodies.count, 2)
        XCTAssertNil(createBodies[1]["person_ids"])
        XCTAssertEqual(outbox.notices.map(\.message), ["«Pan» se sincronizó sin asignar a Luz: ya no tiene acceso a la lista."])
    }

    func testRosterNetworkErrorKeepsOpAndRetries() async {
        let replayer = makeSequencedReplayer([
            "task/create": [Self.invalidPerson],
            "person": [.offline]
        ])
        let outbox = makeOutbox([.createTask(local: -1, listRef: .remote(2), title: "Pan", personIds: [1, 2])])
        let original = outbox.ops[0]
        let summary = await replayer.replay(outbox)
        XCTAssertEqual(summary, ReplaySummary(acked: 0, discarded: 0, stop: .retryable))
        XCTAssertEqual(outbox.ops.map(\.kind), [original.kind], "la op se conserva sin reescribir")
        XCTAssertEqual(outbox.ops.first?.attempts, 1)
        XCTAssertNil(outbox.inFlightId)
        XCTAssertTrue(outbox.notices.isEmpty)
        let reloaded = OutboxStore(userId: 1, homeId: "2", directory: directory)
        XCTAssertEqual(reloaded.ops.first?.attempts, 1, "el intento queda en disco")
    }

    func testRewrittenOpIsPersistedBeforeResend() async {
        let replayer = makeSequencedReplayer([
            "task/create": [Self.invalidPerson, StubURLProtocol.Stub(status: 503, json: #"{"error":"boom"}"#)],
            "person": [StubURLProtocol.Stub(json: Self.roster)],
            "task-list/user": [StubURLProtocol.Stub(json: Self.membersWithoutBeto)]
        ])
        let outbox = makeOutbox([.createTask(local: -1, listRef: .remote(2), title: "Pan", personIds: [1, 2], priority: "alta")])
        let summary = await replayer.replay(outbox)
        XCTAssertEqual(summary.stop, .retryable)
        let expected = PendingOp.Kind.createTask(local: -1, listRef: .remote(2), title: "Pan", personIds: [1], priority: "alta")
        XCTAssertEqual(outbox.ops.map(\.kind), [expected])
        XCTAssertEqual(OutboxStore(userId: 1, homeId: "2", directory: directory).ops.map(\.kind), [expected],
                       "la reescritura persiste: un cierre a mitad no reenvía la lista original")
    }

    func testOtherBadRequestStillDiscards() async {
        let replayer = makeSequencedReplayer([
            "task/create": [StubURLProtocol.Stub(status: 400, json: #"{"error":"Invalid priority"}"#)]
        ])
        let outbox = makeOutbox([.createTask(local: -1, listRef: .remote(2), title: "Pan", personIds: [1], priority: "x")])
        let summary = await replayer.replay(outbox)
        XCTAssertEqual(summary, ReplaySummary(acked: 0, discarded: 1, stop: .drained))
        XCTAssertEqual(routes, ["task/create"], "no pide roster")
        XCTAssertEqual(outbox.notices.count, 1)
        XCTAssertTrue(outbox.notices[0].message.hasPrefix("No se pudo sincronizar «Pan»."))
    }

    func testInvalidPersonWithoutPersonsInOpDiscards() async {
        let replayer = makeSequencedReplayer(["task/create": [Self.invalidPerson]])
        let outbox = makeOutbox([.createTask(local: -1, listRef: .remote(2), title: "Pan", personIds: nil)])
        let summary = await replayer.replay(outbox)
        XCTAssertEqual(summary, ReplaySummary(acked: 0, discarded: 1, stop: .drained))
        XCTAssertEqual(routes, ["task/create"])
        XCTAssertEqual(outbox.notices.map(\.message),
                       ["No se pudo sincronizar «Pan». Alguna persona elegida no se puede asignar en esta lista"])
    }

    func testInvalidPersonWithoutPersonsRepositoryDiscards() async {
        let replayer = makeReplayer(["task/create": Self.invalidPerson])
        let outbox = makeOutbox([.createTask(local: -1, listRef: .remote(2), title: "Pan", personIds: [1])])
        let summary = await replayer.replay(outbox)
        XCTAssertEqual(summary, ReplaySummary(acked: 0, discarded: 1, stop: .drained))
        XCTAssertEqual(routes, ["task/create"])
    }

    func testAssigneeNoticeText() {
        XCTAssertEqual(OutboxReplayer.assigneeNotice(title: "Pan", removedNames: []),
                       "«Pan» se sincronizó sin asignar a una persona: ya no tiene acceso a la lista.")
        XCTAssertEqual(OutboxReplayer.assigneeNotice(title: "Pan", removedNames: ["Ana", "Beto", "Luz"]),
                       "«Pan» se sincronizó sin asignar a Ana, Beto y Luz: ya no tienen acceso a la lista.")
    }
}
