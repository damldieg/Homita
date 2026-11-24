import XCTest
@testable import ControlKit

/// Compra sin conexión (D-024): marcar y alta pasan por la cola, el overlay las pinta y el replay las envía.
@MainActor
final class ShoppingStoreOfflineTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("outbox-shopstore-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private final class Network: @unchecked Sendable { var online = true }

    /// Lo que devuelve el servidor falso en `GET shopping`.
    private final class Server: @unchecked Sendable {
        var items = [Server.json(1, "Tomate")]
        var failCheckWithNetwork = false

        static func json(_ id: Int, _ label: String, state: String = "pending") -> String {
            ##"{"id":\##(id),"label":"\##(label)","unit":"ud","section":"verdura","origin":"manual","state":"\##(state)"}"##
        }
    }

    nonisolated private static func route(_ request: URLRequest) -> String {
        let path = request.url?.path ?? ""
        return path.range(of: "/functions/v1/api/").map { String(path[$0.upperBound...]) } ?? path
    }

    private var routes: [String] { StubURLProtocol.requests.map(Self.route) }

    private func body(_ request: URLRequest) -> [String: Any] {
        request.capturedBody.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] } ?? [:]
    }

    private func makeStore(_ server: Server, network: Network) -> (ShoppingStore, OutboxStore, APIClient) {
        StubURLProtocol.reset { request in
            switch Self.route(request) {
            case "shopping":
                return .init(json: "{\"revision\":1,\"items\":[\(server.items.joined(separator: ","))]}")
            case "shopping/item/create":
                return .init(status: 201, json: Server.json(40, "Leche"))
            case "shopping/item/check":
                if server.failCheckWithNetwork { return .offline }
                return .init(json: Server.json(1, "Tomate", state: "checked"))
            default:
                return ContractFixtures.response(for: request)
            }
        }
        let client = makeTestClient()
        let outbox = OutboxStore(userId: 1, homeId: "2", directory: directory)
        let defaults = UserDefaults(suiteName: "shopping-offline-\(UUID().uuidString)")!
        let store = ShoppingStore(repo: ShoppingRepository(client: client), outbox: outbox, isOnline: { network.online },
                                  defaults: defaults, activeHomeId: { "2" })
        return (store, outbox, client)
    }

    func testOfflineCheckIsPaintedAsPendingWithoutRequest() async throws {
        let network = Network()
        let (store, outbox, _) = makeStore(Server(), network: network)
        await store.load()
        network.online = false
        await store.toggle(try XCTUnwrap(store.items.first))

        XCTAssertEqual(routes, ["shopping"], "sin red no se envía nada")
        XCTAssertEqual(store.items.first?.state, "checked")
        XCTAssertEqual(store.pendingIds, [1])
        XCTAssertEqual(outbox.pendingCount, 1)
        XCTAssertNil(store.errorMessage)

        await store.toggle(try XCTUnwrap(store.items.first))
        XCTAssertEqual(store.items.first?.state, "pending")
        XCTAssertEqual(outbox.ops.map(\.kind), [.uncheckShoppingItem(ref: .remote(1))], "marcar y desmarcar se colapsan")
    }

    func testOnlineCheckSendsAndLeavesQueueEmpty() async throws {
        let network = Network()
        let (store, outbox, _) = makeStore(Server(), network: network)
        await store.load()
        await store.toggle(try XCTUnwrap(store.items.first))
        XCTAssertEqual(routes, ["shopping", "shopping/item/check"])
        XCTAssertTrue(outbox.isEmpty)
        XCTAssertEqual(store.items.first?.state, "checked")
        XCTAssertTrue(store.pendingIds.isEmpty)
    }

    func testNetworkFailureWhileSendingQueuesTheCheck() async throws {
        let server = Server()
        server.failCheckWithNetwork = true
        let (store, outbox, _) = makeStore(server, network: Network())
        await store.load()
        await store.toggle(try XCTUnwrap(store.items.first))
        XCTAssertEqual(outbox.ops.map(\.kind), [.checkShoppingItem(ref: .remote(1))])
        XCTAssertEqual(store.items.first?.state, "checked", "el overlay lo pinta aunque la foto del servidor siga pendiente")
        XCTAssertNil(store.errorMessage)
    }

    func testOfflineAddShowsLocalRowAndMarkMergesIntoCreate() async throws {
        let network = Network()
        let (store, outbox, _) = makeStore(Server(), network: network)
        await store.load()
        network.online = false
        let ok = await store.add(label: "Leche", quantity: 2, unit: "l")
        XCTAssertTrue(ok)
        let added = try XCTUnwrap(store.items.first { $0.label == "Leche" })
        XCTAssertLessThan(added.id, 0)
        XCTAssertTrue(store.pendingIds.contains(added.id))

        await store.toggle(added)
        XCTAssertEqual(outbox.pendingCount, 1, "el marcar se funde en el alta")
        XCTAssertEqual(store.items.first { $0.label == "Leche" }?.state, "checked")
        XCTAssertEqual(routes, ["shopping"])
    }

    func testBackOnlineReplaysCreateWithClientRequestIdAndNoDuplicates() async throws {
        let network = Network()
        let server = Server()
        let (store, outbox, client) = makeStore(server, network: network)
        await store.load()
        network.online = false
        await store.add(label: "Leche", quantity: 2, unit: "l")
        await store.toggle(try XCTUnwrap(store.items.first { $0.id == 1 }))
        let createOp = try XCTUnwrap(outbox.ops.first { $0.kind.isCreate })
        let generation = outbox.generation

        network.online = true
        let replayer = OutboxReplayer(tasks: TaskRepository(client: client), taskLists: TaskListRepository(client: client),
                                      shopping: ShoppingRepository(client: client), isOnline: { network.online })
        let summary = await replayer.replay(outbox)

        XCTAssertEqual(summary.stop, .drained)
        XCTAssertEqual(routes, ["shopping", "shopping/item/create", "shopping/item/check"], "FIFO")
        let create = try XCTUnwrap(StubURLProtocol.requests.first { Self.route($0) == "shopping/item/create" })
        XCTAssertEqual(body(create)["client_request_id"] as? String, createOp.clientRequestId)
        XCTAssertGreaterThan(outbox.generation, generation)
        XCTAssertEqual(outbox.idMap.values.sorted(), [40])

        server.items = [Server.json(1, "Tomate", state: "checked"), Server.json(40, "Leche")]
        await store.load()
        XCTAssertEqual(store.items.map(\.id).sorted(), [1, 40], "sin fila duplicada")
        XCTAssertTrue(store.pendingIds.isEmpty)
    }

    func testEditingOrDeletingAnUnsyncedItemIsRejectedWithoutRequest() async throws {
        let network = Network()
        let (store, _, _) = makeStore(Server(), network: network)
        await store.load()
        network.online = false
        await store.add(label: "Leche")
        let local = try XCTUnwrap(store.items.first { $0.id < 0 })
        await store.updateQuantity(local, quantity: 3)
        XCTAssertNotNil(store.errorMessage)
        store.errorMessage = nil
        await store.delete(local)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertEqual(routes, ["shopping"])
    }

    func testOnlineAddSendsAndReloadsTheList() async throws {
        let server = Server()
        let (store, outbox, _) = makeStore(server, network: Network())
        await store.load()
        server.items.append(Server.json(40, "Leche"))
        let ok = await store.add(label: "Leche", unit: "ud")
        XCTAssertTrue(ok)
        XCTAssertEqual(routes, ["shopping", "shopping/item/create", "shopping"])
        XCTAssertTrue(outbox.isEmpty)
        XCTAssertEqual(store.items.map(\.id).sorted(), [1, 40])
    }
}
