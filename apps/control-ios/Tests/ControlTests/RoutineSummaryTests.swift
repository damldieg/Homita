import XCTest
@testable import ControlKit

/// Resumen en lenguaje natural de la regla (E3-06).
final class RoutineSummaryTests: XCTestCase {
    func testDailyOneAndSeveralDays() {
        XCTAssertEqual(RoutineSummary.text(frequency: "daily", interval: 1, days: [], hour: "09:30"), "Todos los días a las 09:30")
        XCTAssertEqual(RoutineSummary.text(frequency: "daily", interval: 3, days: [], hour: "09:30"), "Cada 3 días a las 09:30")
    }

    func testWeeklyListsDaysInIsoOrder() {
        XCTAssertEqual(
            RoutineSummary.text(frequency: "weekly", interval: 2, days: [5, 1, 3], hour: "20:00"),
            "Cada 2 semanas los lunes, miércoles y viernes a las 20:00"
        )
        XCTAssertEqual(
            RoutineSummary.text(frequency: "weekly", interval: 1, days: [6, 7], hour: "10:00"),
            "Todas las semanas los sábados y domingos a las 10:00"
        )
    }

    func testMonthly() {
        XCTAssertEqual(RoutineSummary.text(frequency: "monthly", interval: 1, days: [], hour: "08:00"), "Todos los meses a las 08:00")
    }
}
