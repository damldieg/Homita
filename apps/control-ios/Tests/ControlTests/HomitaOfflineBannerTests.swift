import XCTest
@testable import ControlKit

/// AC8: textos del banner sin conexión con la cola offline (D-024).
final class HomitaOfflineBannerTests: XCTestCase {
    func testNoBannerOnlineWithoutPending() {
        XCTAssertNil(HomitaOfflineBanner.message(isOffline: false, staleSince: nil, pendingCount: 0))
    }

    func testOfflineWithoutPending() {
        XCTAssertEqual(HomitaOfflineBanner.message(isOffline: true, staleSince: nil, pendingCount: 0), "Sin conexión.")
    }

    func testOfflinePendingPlural() {
        XCTAssertEqual(HomitaOfflineBanner.message(isOffline: true, staleSince: nil, pendingCount: 3),
                       "Sin conexión. 3 cambios pendientes.")
    }

    func testOfflinePendingSingular() {
        XCTAssertEqual(HomitaOfflineBanner.message(isOffline: true, staleSince: nil, pendingCount: 1),
                       "Sin conexión. 1 cambio pendiente.")
    }

    func testOnlineWithPendingQueue() {
        XCTAssertEqual(HomitaOfflineBanner.message(isOffline: false, staleSince: nil, pendingCount: 2),
                       "2 cambios pendientes de sincronizar")
        XCTAssertEqual(HomitaOfflineBanner.message(isOffline: false, staleSince: nil, pendingCount: 1),
                       "1 cambio pendiente de sincronizar")
    }

    func testStaleCacheKeepsTextAndAddsCount() throws {
        let since = try XCTUnwrap(Calendar(identifier: .gregorian).date(from: DateComponents(
            timeZone: .current, year: 2026, month: 11, day: 20, hour: 19, minute: 12
        )))
        XCTAssertEqual(HomitaOfflineBanner.message(isOffline: true, staleSince: since, pendingCount: 0),
                       "Sin conexión. Mostrando datos de las 19:12.")
        XCTAssertEqual(HomitaOfflineBanner.message(isOffline: true, staleSince: since, pendingCount: 2),
                       "Sin conexión. Mostrando datos de las 19:12. 2 cambios pendientes.")
    }
}
