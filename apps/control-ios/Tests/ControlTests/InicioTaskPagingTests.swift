import XCTest
@testable import ControlKit

/// Puntos del paginador de «Tareas pendientes»: ventana de 5, un solo activo y difuminado en los extremos.
final class InicioTaskPagingTests: XCTestCase {
    /// Una sola fuente de verdad: para cada página hay exactamente un punto activo, y es esa página.
    func testExactlyOneActiveDotMatchesTheVisiblePage() {
        for count in [1, 3, 5, 6, 8] {
            for current in 0..<count {
                let dots = InicioTaskPaging.dots(count: count, current: current)
                let active = dots.filter(\.highlighted).compactMap(\.listIndex)
                XCTAssertEqual(active, [current], "n=\(count) actual=\(current)")
            }
        }
    }

    /// La ventana nunca muestra más de 5 puntos, aunque haya más listas.
    func testWindowNeverShowsMoreThanFive() {
        for current in 0..<8 {
            XCTAssertLessThanOrEqual(InicioTaskPaging.dots(count: 8, current: current).count, 5)
        }
    }

    /// Difuminado en los extremos solo si hay listas ocultas a ese lado.
    func testEdgesFadeOnlyWhenMoreListsAreHidden() {
        // Al inicio: el último punto se difumina (quedan listas a la derecha), el primero no.
        let start = InicioTaskPaging.dots(count: 8, current: 0)
        XCTAssertFalse(start.first!.faded)
        XCTAssertTrue(start.last!.faded)
        // Al final: el primero se difumina (quedan a la izquierda), el último no.
        let end = InicioTaskPaging.dots(count: 8, current: 7)
        XCTAssertTrue(end.first!.faded)
        XCTAssertFalse(end.last!.faded)
        // Con 5 o menos no hay difuminado.
        XCTAssertFalse(InicioTaskPaging.dots(count: 5, current: 2).contains { $0.faded })
    }

    /// La ventana se desplaza cuando el activo llega al centro (no se queda fija en 2-3).
    func testWindowSlidesWhileActiveMoves() {
        let middle = InicioTaskPaging.dots(count: 8, current: 4).compactMap(\.listIndex)
        XCTAssertEqual(middle, [3, 4, 5, 6, 7])
    }
}
