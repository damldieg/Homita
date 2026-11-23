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
        let suite = try XCTUnwrap(UserDefaults(suiteName: "test.inicio.layout.\(UUID().uuidString)"))
        defer { suite.removePersistentDomain(forName: suite.dictionaryRepresentation().keys.first ?? "") }
        let store = InicioLayoutStore(defaults: suite)
        XCTAssertEqual(store.load(), InicioLayout(), "sin nada guardado, el orden por defecto")

        var layout = InicioLayout()
        layout.move(from: IndexSet(integer: 2), to: 0)
        layout.setVisible(.events, false)
        store.save(layout)
        XCTAssertEqual(store.load(), layout)
    }
}
