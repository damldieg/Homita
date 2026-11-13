import XCTest
@testable import ControlKit

final class InicioTaskPagingTests: XCTestCase {
    private let ids = [4, 7, 9]

    func testNeighborMovesForwardAndBack() {
        XCTAssertEqual(InicioTaskPaging.neighbor(of: 4, in: ids, forward: true), 7)
        XCTAssertEqual(InicioTaskPaging.neighbor(of: 7, in: ids, forward: true), 9)
        XCTAssertEqual(InicioTaskPaging.neighbor(of: 9, in: ids, forward: false), 7)
    }

    func testNeighborStopsAtTheEnds() {
        XCTAssertNil(InicioTaskPaging.neighbor(of: 9, in: ids, forward: true))
        XCTAssertNil(InicioTaskPaging.neighbor(of: 4, in: ids, forward: false))
    }

    func testNeighborIgnoresUnknownListOrSingleList() {
        XCTAssertNil(InicioTaskPaging.neighbor(of: 5, in: ids, forward: true))
        XCTAssertNil(InicioTaskPaging.neighbor(of: 4, in: [4], forward: true))
        XCTAssertNil(InicioTaskPaging.neighbor(of: 4, in: [], forward: false))
    }

    func testOnlyClearlyHorizontalLongDragsAreSwipes() {
        XCTAssertTrue(InicioTaskPaging.isHorizontalSwipe(width: -80, height: 10))
        XCTAssertTrue(InicioTaskPaging.isHorizontalSwipe(width: 70, height: -20))
        XCTAssertFalse(InicioTaskPaging.isHorizontalSwipe(width: 40, height: 0))      // corto
        XCTAssertFalse(InicioTaskPaging.isHorizontalSwipe(width: 80, height: 60))     // diagonal
        XCTAssertFalse(InicioTaskPaging.isHorizontalSwipe(width: 10, height: 120))    // scroll vertical
    }
}
