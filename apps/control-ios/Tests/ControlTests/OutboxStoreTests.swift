import XCTest
@testable import ControlKit

/// AC4: persistencia, aislamiento y borrado de la cola offline (`OutboxStore` y `OutboxRegistry`).
@MainActor
final class OutboxStoreTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("outbox-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func create(_ title: String, in store: OutboxStore) -> PendingOp {
        let op = PendingOp(homeId: store.homeId, kind: .createTask(local: store.makeLocalId(), listRef: .remote(2), title: title, personIds: nil))
        store.enqueue(op)
        return op
    }

    // MARK: - OutboxStore

    func testReloadsFromDiskInANewInstance() {
        let first = OutboxStore(userId: 1, homeId: "2", directory: directory)
        let op = create("Leche", in: first)
        let second = OutboxStore(userId: 1, homeId: "2", directory: directory)
        XCTAssertEqual(second.ops, [op])
        XCTAssertEqual(second.nextLocalId, -2, "el contador de temporales también persiste")
    }

    func testAckStoresMappingRemovesOpAndBumpsGeneration() {
        let store = OutboxStore(userId: 1, homeId: "2", directory: directory)
        let op = create("Leche", in: store)
        store.ack(op.id, remoteId: 70)
        XCTAssertTrue(store.isEmpty)
        XCTAssertEqual(store.generation, 1)
        XCTAssertEqual(store.resolve(-1), 70)
        XCTAssertEqual(store.ref(for: -1), .remote(70))
        XCTAssertEqual(store.ref(for: -9), .local(-9))
        let reloaded = OutboxStore(userId: 1, homeId: "2", directory: directory)
        XCTAssertEqual(reloaded.idMap, [-1: 70], "el idMap se conserva en disco")
    }

    func testUsersAndHomesAreIsolated() {
        let a = OutboxStore(userId: 1, homeId: "2", directory: directory)
        _ = create("De A", in: a)
        XCTAssertTrue(OutboxStore(userId: 1, homeId: "3", directory: directory).isEmpty, "otro hogar del mismo usuario")
        XCTAssertTrue(OutboxStore(userId: 9, homeId: "2", directory: directory).isEmpty, "otro usuario en el mismo hogar")
        XCTAssertEqual(OutboxStore(userId: 1, homeId: "2", directory: directory).pendingCount, 1)
    }

    func testDiscardRemovesDependentsTransitivelyAndAddsNotice() {
        let store = OutboxStore(userId: 1, homeId: "2", directory: directory)
        let list = PendingOp(homeId: "2", kind: .createList(local: -1, name: "Compra", color: "#6923E2", sort: "custom", widget: true, dashboard: true))
        store.enqueue(list)
        store.enqueue(PendingOp(homeId: "2", kind: .createTask(local: -2, listRef: .local(-1), title: "Leche", personIds: nil)))
        store.enqueue(PendingOp(homeId: "2", kind: .completeTask(ref: .local(-2), listRef: .local(-1), completed: true)))
        let other = PendingOp(homeId: "2", kind: .completeTask(ref: .remote(7), listRef: .remote(3), completed: true))
        store.enqueue(other)
        store.discard(list.id, notice: "aviso")
        XCTAssertEqual(store.ops, [other])
        XCTAssertEqual(store.notices.map(\.message), ["aviso"])
    }

    func testFileIsWrittenWithProtectionAndExcludedFromBackup() throws {
        let store = OutboxStore(userId: 1, homeId: "2", directory: directory)
        _ = create("Leche", in: store)
        XCTAssertTrue(OutboxStore.writingOptions.contains(.completeFileProtectionUntilFirstUserAuthentication))
        XCTAssertTrue(OutboxStore.writingOptions.contains(.atomic))
        XCTAssertEqual(OutboxStore.fileProtection, .completeUntilFirstUserAuthentication)
        let values = try store.fileURL.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true)
        #if os(iOS)
        // En el dispositivo o simulador el atributo se lee tal cual (en macOS no se aplica igual, R11).
        let attributes = try FileManager.default.attributesOfItem(atPath: store.fileURL.path)
        XCTAssertEqual(attributes[.protectionKey] as? FileProtectionType, .completeUntilFirstUserAuthentication)
        #endif
        XCTAssertTrue(store.fileURL.path.hasSuffix("/1/2.json"))
    }

    // MARK: - OutboxRegistry

    func testRegistryReturnsSameInstanceForSamePair() {
        let registry = OutboxRegistry(directory: directory)
        XCTAssertTrue(registry.store(user: 1, home: "2") === registry.store(user: 1, home: "2"))
        XCTAssertFalse(registry.store(user: 1, home: "2") === registry.store(user: 1, home: "3"))
    }

    func testRemoveAllDeletesDirectoryAndInstances() {
        let registry = OutboxRegistry(directory: directory)
        let store = registry.store(user: 1, home: "2")
        _ = create("Leche", in: store)
        registry.removeAll()
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        XCTAssertTrue(store.isEmpty, "la instancia que tenga la UI también queda vacía")
        XCTAssertTrue(registry.store(user: 1, home: "2").isEmpty)
    }

    func testRetainOnlyKeepsOnlyTheGivenUser() {
        let registry = OutboxRegistry(directory: directory)
        _ = create("De 1", in: registry.store(user: 1, home: "2"))
        _ = create("De 9", in: registry.store(user: 9, home: "2"))
        // Cola de otro usuario solo en disco (de una sesión anterior).
        _ = create("De 5", in: OutboxStore(userId: 5, homeId: "4", directory: directory))
        registry.retainOnly(userId: 1)
        let fresh = OutboxRegistry(directory: directory)
        XCTAssertEqual(fresh.store(user: 1, home: "2").pendingCount, 1)
        XCTAssertTrue(fresh.store(user: 9, home: "2").isEmpty)
        XCTAssertTrue(fresh.store(user: 5, home: "4").isEmpty)
        XCTAssertTrue(registry.store(user: 9, home: "2").isEmpty)
    }

    // MARK: - 0038

    func testAckWithNoticeAddsNoticeAndPersistsRemoval() {
        let store = OutboxStore(userId: 1, homeId: "2", directory: directory)
        let op = create("Pan", in: store)
        store.ack(op.id, remoteId: 70, notice: "aviso")
        XCTAssertEqual(store.notices.map(\.message), ["aviso"])
        XCTAssertEqual(store.generation, 1)
        let reloaded = OutboxStore(userId: 1, homeId: "2", directory: directory)
        XCTAssertTrue(reloaded.isEmpty, "el ack con aviso se guarda en la cola")
        XCTAssertEqual(reloaded.idMap, [-1: 70])
    }

    func testReplaceKindOnlyTouchesFirstOrInFlightOpAndPersists() {
        let store = OutboxStore(userId: 1, homeId: "2", directory: directory)
        let first = create("Pan", in: store)
        let second = create("Leche", in: store)
        let rewritten = PendingOp.Kind.createTask(local: -1, listRef: .remote(2), title: "Pan", personIds: [1])
        store.replaceKind(first.id, with: rewritten)
        store.replaceKind(second.id, with: .createTask(local: -2, listRef: .remote(2), title: "Leche", personIds: [9]))
        XCTAssertEqual(store.ops.map(\.kind), [rewritten, second.kind], "la segunda op no se toca")
        XCTAssertEqual(OutboxStore(userId: 1, homeId: "2", directory: directory).ops.map(\.kind), [rewritten, second.kind])
        XCTAssertEqual(store.ops.first?.id, first.id, "conserva id y clave")
    }
}
