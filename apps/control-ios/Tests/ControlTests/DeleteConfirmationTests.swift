import XCTest
@testable import ControlKit

/// Textos de borrado (E0-07, D-7).
final class DeleteConfirmationTests: XCTestCase {
    func testSingleItemNamesIt() {
        XCTAssertEqual(
            DeleteConfirmation.message(names: ["Comprar pan"], consequence: "Se eliminará la tarea."),
            "¿Eliminar «Comprar pan»?\nSe eliminará la tarea."
        )
    }

    func testSeveralItemsUseCount() {
        XCTAssertEqual(
            DeleteConfirmation.message(names: ["A", "B", "C"], consequence: "Se eliminarán las tareas."),
            "¿Eliminar 3 elementos?\nSe eliminarán las tareas."
        )
    }
}
