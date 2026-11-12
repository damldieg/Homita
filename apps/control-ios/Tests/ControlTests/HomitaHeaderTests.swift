import XCTest
@testable import ControlKit

/// Cabecera estándar (E0-02): como máximo dos acciones circulares.
final class HomitaHeaderTests: XCTestCase {
    func testMaxTwoActions() {
        XCTAssertEqual(HomitaHeaderLayout.maxActions, 2)
    }

    func testVisibleActionCountIsClamped() {
        XCTAssertEqual(HomitaHeaderLayout.visibleActionCount(0), 0)
        XCTAssertEqual(HomitaHeaderLayout.visibleActionCount(1), 1)
        XCTAssertEqual(HomitaHeaderLayout.visibleActionCount(2), 2)
        XCTAssertEqual(HomitaHeaderLayout.visibleActionCount(5), 2)
        XCTAssertEqual(HomitaHeaderLayout.visibleActionCount(-1), 0)
    }
}
