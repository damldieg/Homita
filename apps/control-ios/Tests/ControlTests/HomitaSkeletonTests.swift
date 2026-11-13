import XCTest
@testable import ControlKit

/// Esqueleton de carga (E0-03): el brillo se anima salvo con Reduce Motion.
final class HomitaSkeletonTests: XCTestCase {
    func testShimmerAnimatesWithoutReduceMotion() {
        XCTAssertTrue(HomitaSkeletonLayout.shimmerEnabled(reduceMotion: false))
    }

    func testShimmerIsStaticWithReduceMotion() {
        XCTAssertFalse(HomitaSkeletonLayout.shimmerEnabled(reduceMotion: true))
    }
}
