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

    // MARK: dots

    func testDotsEmpty() {
        XCTAssertEqual(InicioTaskPaging.dots(count: 0, current: 0), [])
    }

    func testDotsUpToFiveOnePerList() {
        for n in 1...5 {
            for c in 0..<n {
                let dots = InicioTaskPaging.dots(count: n, current: c)
                XCTAssertEqual(dots.count, n)
                XCTAssertEqual(dots.map(\.listIndex), Array(0..<n))
                XCTAssertTrue(dots.allSatisfy { !$0.faded })
                XCTAssertEqual(dots.enumerated().filter { $0.element.highlighted }.map(\.offset), [c])
            }
        }
    }

    private func summary(_ n: Int, _ c: Int) -> (idx: [Int?], hi: Int?, faded: [Int]) {
        let d = InicioTaskPaging.dots(count: n, current: c)
        return (d.map(\.listIndex), d.firstIndex { $0.highlighted }, d.indices.filter { d[$0].faded })
    }

    func testDotsSixLists() {
        for c in [0, 1] {
            let r = summary(6, c)
            XCTAssertEqual(r.idx, [0, 1, 2, 3, 4])
            XCTAssertEqual(r.faded, [4])
            XCTAssertEqual(r.hi, c)
        }
        let r2 = summary(6, 2)
        XCTAssertEqual(r2.idx, [1, 2, 3, 4, 5])
        XCTAssertEqual(r2.faded, [0])
        XCTAssertEqual(r2.hi, 1)
        let r5 = summary(6, 5)
        XCTAssertEqual(r5.idx, [1, 2, 3, 4, 5])
        XCTAssertEqual(r5.faded, [0])
        XCTAssertEqual(r5.hi, 4)
    }

    func testDotsSevenListsLast() {
        let r = summary(7, 6)
        XCTAssertEqual(r.idx, [2, 3, 4, 5, 6])
        XCTAssertEqual(r.faded, [0])
        XCTAssertEqual(r.hi, 4)
    }
}
