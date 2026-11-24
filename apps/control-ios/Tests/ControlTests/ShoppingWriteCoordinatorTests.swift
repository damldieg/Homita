import XCTest
@testable import ControlKit

/// Decisión «enviar o encolar» de las escrituras de la Compra (mismo patrón que las tareas).
@MainActor
final class ShoppingWriteCoordinatorTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("outbox-shop-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    nonisolated private static func route(_ request: URLRequest) -> String {
        let path = request.url?.path ?? ""
        return path.range(of: "/functions/v1/api/").map { String(path[$0.upperBound...]) } ?? path
    }

    private static let item = ##"{"id":40,"label":"Leche","unit":"ud","section":"otros","origin":"manual","state":"pending"}"##

    private func makeCoordinator(online: Bool = true, _ handler: @escaping (URLRequest) -> StubURLProtocol.Stub)
        -> (ShoppingWriteCoordinator, OutboxStore) {
        StubURLProtocol.reset(handler)
        let client = makeTestClient()
        let outbox = OutboxStore(userId: 1, homeId: "2", directory: directory)
        return (ShoppingWriteCoordinator(outbox: outbox, shopping: ShoppingRepository(client: client), isOnline: { online }), outbox)
    }

    private func createKind(_ outbox: OutboxStore) -> PendingOp.Kind {
        .createShoppingItem(local: outbox.makeLocalId(), label: "Leche", quantity: nil, unit: "ud", section: nil, foodId: nil)
    }

    func testOfflineQueuesWithoutRequest() async throws {
        let (coordinator, outbox) = makeCoordinator(online: false) { _ in .init() }
        let outcome = try await coordinator.perform(coordinator.makeOp(createKind(outbox)))
        XCTAssertEqual(outcome, .queued)
        XCTAssertTrue(StubURLProtocol.requests.isEmpty)
        XCTAssertEqual(outbox.pendingCount, 1)
    }

    func testOnlineSendsCreateAndReturnsRemoteId() async throws {
        let (coordinator, outbox) = makeCoordinator { _ in .init(status: 201, json: Self.item) }
        let op = coordinator.makeOp(createKind(outbox))
        let outcome = try await coordinator.perform(op)
        XCTAssertEqual(outcome, .sent(remoteId: 40))
        XCTAssertTrue(outbox.isEmpty)
        let data = try XCTUnwrap(StubURLProtocol.requests.first?.capturedBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["client_request_id"] as? String, op.clientRequestId)
    }

    func testNetworkErrorQueuesTheSameOp() async throws {
        let (coordinator, outbox) = makeCoordinator { _ in .offline }
        let op = coordinator.makeOp(createKind(outbox))
        let outcome = try await coordinator.perform(op)
        XCTAssertEqual(outcome, .queued)
        XCTAssertEqual(outbox.ops.map(\.id), [op.id], "se encola la misma op (misma clave)")
    }

    func testServerErrorIsThrownAndNotQueued() async {
        let (coordinator, outbox) = makeCoordinator { _ in .init(status: 500, json: #"{"error":"boom"}"#) }
        do {
            try await coordinator.perform(coordinator.makeOp(.checkShoppingItem(ref: .remote(5))))
            XCTFail("debía lanzar")
        } catch {
            XCTAssertTrue(outbox.isEmpty)
        }
    }

    func testNonEmptyQueueKeepsFIFO() async throws {
        let (coordinator, outbox) = makeCoordinator { _ in .init(json: Self.item) }
        outbox.enqueue(coordinator.makeOp(.checkShoppingItem(ref: .remote(5))))
        let outcome = try await coordinator.perform(coordinator.makeOp(.checkShoppingItem(ref: .remote(6))))
        XCTAssertEqual(outcome, .queued)
        XCTAssertTrue(StubURLProtocol.requests.isEmpty)
        XCTAssertEqual(outbox.pendingCount, 2)
    }

    func testUnresolvedLocalRefIsQueued() async throws {
        let (coordinator, outbox) = makeCoordinator { _ in .init(json: Self.item) }
        let outcome = try await coordinator.perform(coordinator.makeOp(.checkShoppingItem(ref: .local(-9))))
        XCTAssertEqual(outcome, .queued)
        XCTAssertEqual(outbox.pendingCount, 1)
    }
}
