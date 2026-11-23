import XCTest
import HomitaShared
@testable import ControlKit

/// Orden y visibilidad de los bloques de Inicio (tarjeta [12]).
final class InicioLayoutTests: XCTestCase {
    /// Escenario «orden por defecto».
    func testDefaultOrderIsTheCurrentOne() {
        XCTAssertEqual(InicioLayout().visibleBlocks, [.routines, .events, .tasks])
    }

    /// Escenario «reordenar bloques»: arrastrar tareas a la primera posición.
    func testMoveTasksToTheFirstPosition() {
        var layout = InicioLayout()
        layout.move(from: IndexSet(integer: 2), to: 0)
        XCTAssertEqual(layout.order, [.tasks, .routines, .events])
    }

    /// Escenario «ocultar un bloque»: los demás conservan su orden.
    func testHidingOneBlockKeepsTheOthersInOrder() {
        var layout = InicioLayout()
        layout.setVisible(.events, false)
        XCTAssertEqual(layout.visibleBlocks, [.routines, .tasks])
        layout.setVisible(.events, true)
        XCTAssertEqual(layout.visibleBlocks, [.routines, .events, .tasks])
    }

    /// Escenario «ocultar todos»: nada visible, y el orden se conserva para cuando vuelvan.
    func testHidingAllLeavesNothingVisibleButKeepsOrder() {
        var layout = InicioLayout(order: [.tasks, .events, .routines])
        for block in InicioBlock.allCases { layout.setVisible(block, false) }
        XCTAssertTrue(layout.visibleBlocks.isEmpty)
        XCTAssertEqual(layout.order, [.tasks, .events, .routines])
    }

    /// Un orden guardado con un bloque repetido o que falta se corrige al leerlo.
    func testNormalizedOrderRepairsDuplicatesAndMissingBlocks() {
        XCTAssertEqual(InicioLayout(order: [.tasks, .tasks]).order, [.tasks, .routines, .events])
    }

    /// Escenario «la configuración persiste en el iPhone»: ida y vuelta por el almacén.
    func testStoreRoundTripKeepsOrderAndHidden() throws {
        let name = "test.inicio.layout.\(UUID().uuidString)"
        let suite = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }
        let store = InicioLayoutStore(defaults: suite)
        XCTAssertEqual(store.load(), InicioLayout(), "sin nada guardado, el orden por defecto")

        var layout = InicioLayout()
        layout.move(from: IndexSet(integer: 2), to: 0)
        layout.setVisible(.events, false)
        store.save(layout)
        XCTAssertEqual(store.load(), layout)
    }

    /// R2-01: lo que se lee de disco se normaliza igual que al crear (repetidos e incompletos).
    func testDecodingNormalizesStoredOrder() throws {
        let json = #"{"order":["tasks","tasks"],"hidden":[]}"#
        let layout = try JSONDecoder().decode(InicioLayout.self, from: Data(json.utf8))
        XCTAssertEqual(layout.order, [.tasks, .routines, .events])
    }

    /// R2-01: un valor desconocido no se decodifica; el almacén cae al orden por defecto.
    func testUnknownBlockFallsBackToDefaultLayout() throws {
        let name = "test.inicio.layout.unknown.\(UUID().uuidString)"
        let suite = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }
        suite.set(Data(#"{"order":["nope"],"hidden":[]}"#.utf8), forKey: InicioLayoutStore.key)
        XCTAssertEqual(InicioLayoutStore(defaults: suite).load(), InicioLayout())
    }

    /// R2-01: más casos de `move`: arriba a abajo, abajo a arriba y al mismo sitio.
    func testMoveCases() {
        var down = InicioLayout()
        down.move(from: IndexSet(integer: 0), to: 3)
        XCTAssertEqual(down.order, [.events, .tasks, .routines])

        var up = InicioLayout()
        up.move(from: IndexSet(integer: 2), to: 1)
        XCTAssertEqual(up.order, [.routines, .tasks, .events])

        var same = InicioLayout()
        same.move(from: IndexSet(integer: 1), to: 1)
        XCTAssertEqual(same.order, [.routines, .events, .tasks])
    }
}
