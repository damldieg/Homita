import XCTest
@testable import ControlKit

/// Canal `KitoChanges`: contadores por tipo, mapeo a almacenes y compuerta de «recargar una sola vez».
@MainActor
final class KitoChangesTests: XCTestCase {
    private func change(_ tipo: String) -> KitoChange { KitoChange(tipo: tipo, id: "1", op: "crear") }

    func testPublishOnlyIncrementsAffectedKinds() {
        let changes = KitoChanges()
        changes.publish([change("tarea"), change("tarea")])
        XCTAssertEqual(changes.counters[.tarea], 1, "una vez por publicación y tipo")
        XCTAssertNil(changes.counters[.evento])
        changes.publish([change("evento")])
        XCTAssertEqual(changes.counters[.evento], 1)
        XCTAssertEqual(changes.counters[.tarea], 1)
    }

    func testEmptyOrUnknownChangesChangeNothing() {
        let changes = KitoChanges()
        changes.publish([])
        changes.publish([change("desconocido")])
        XCTAssertTrue(changes.counters.isEmpty)
        XCTAssertEqual(changes.counter(for: KitoReloadTargets.inicio), 0)
    }

    func testReloadMappingPerStore() {
        func after(_ tipo: String) -> [String: Int] {
            let c = KitoChanges()
            c.publish([change(tipo)])
            return [
                "tareas": c.counter(for: KitoReloadTargets.tasks),
                "agenda": c.counter(for: KitoReloadTargets.agenda),
                "calendarios": c.counter(for: KitoReloadTargets.calendars),
                "rutinas": c.counter(for: KitoReloadTargets.routines),
                "inicio": c.counter(for: KitoReloadTargets.inicio)
            ]
        }
        XCTAssertEqual(after("tarea"), ["tareas": 1, "agenda": 0, "calendarios": 0, "rutinas": 0, "inicio": 1])
        XCTAssertEqual(after("lista"), ["tareas": 1, "agenda": 0, "calendarios": 0, "rutinas": 0, "inicio": 1])
        XCTAssertEqual(after("evento"), ["tareas": 0, "agenda": 1, "calendarios": 0, "rutinas": 0, "inicio": 1])
        XCTAssertEqual(after("rutina"), ["tareas": 0, "agenda": 0, "calendarios": 0, "rutinas": 1, "inicio": 1])
        XCTAssertEqual(after("calendario"), ["tareas": 0, "agenda": 1, "calendarios": 1, "rutinas": 0, "inicio": 1])
    }

    func testGateReloadsOncePerChange() {
        let changes = KitoChanges()
        var gate = KitoReloadGate(seen: changes.counter(for: KitoReloadTargets.tasks))
        XCTAssertFalse(gate.shouldReload(current: changes.counter(for: KitoReloadTargets.tasks)), "sin cambios no recarga")
        changes.publish([change("tarea")])
        XCTAssertTrue(gate.shouldReload(current: changes.counter(for: KitoReloadTargets.tasks)), "onChange")
        XCTAssertFalse(gate.shouldReload(current: changes.counter(for: KitoReloadTargets.tasks)), "onAppear posterior no repite")
        changes.publish([change("evento")])
        XCTAssertFalse(gate.shouldReload(current: changes.counter(for: KitoReloadTargets.tasks)), "otro tipo no recarga Tareas")
    }

    func testTabNotMountedReloadsOnceOnAppear() {
        let changes = KitoChanges()
        var gate = KitoReloadGate(seen: changes.counter(for: KitoReloadTargets.routines))
        changes.publish([change("rutina")])
        changes.publish([change("rutina")])
        XCTAssertTrue(gate.shouldReload(current: changes.counter(for: KitoReloadTargets.routines)))
        XCTAssertFalse(gate.shouldReload(current: changes.counter(for: KitoReloadTargets.routines)))
    }

    func testNewTabStartsFromCurrentCounterAndDoesNotReloadTwice() {
        let changes = KitoChanges()
        changes.publish([change("tarea")])
        var gate = KitoReloadGate(seen: changes.counter(for: KitoReloadTargets.tasks))
        XCTAssertFalse(gate.shouldReload(current: changes.counter(for: KitoReloadTargets.tasks)))
    }

    func testStoreAfterClearKeepsPublishingToTheSameChannel() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("kito-ch-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let client = APIClient(
            baseURL: URL(string: "https://test.supabase.co/functions/v1")!, session: StubURLProtocol.session(),
            tokenProvider: { "t" }, homeIdProvider: { "7" }, readCache: ReadCache(directory: dir.appendingPathComponent("c"))
        )
        let changes = KitoChanges()
        func store() -> KitoStore {
            KitoStore(api: KitoAPI(client: client), historyStore: KitoHistoryStore(directory: dir.appendingPathComponent("h")),
                      userId: 1, homeId: "7", timezone: { "UTC" }, changes: changes)
        }
        StubURLProtocol.reset { _ in StubURLProtocol.Stub(json: #"{"texto":"ok","cambios":[{"tipo":"tarea","id":1,"op":"crear"}]}"#) }
        let first = store()
        await first.send("a")
        first.clearConversation()
        let second = store()
        await second.send("b")
        XCTAssertEqual(changes.counters[.tarea], 2)
    }
}
