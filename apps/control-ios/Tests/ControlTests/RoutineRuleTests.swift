import XCTest
@testable import ControlKit

/// `RoutineRule`: validación del formulario (mismas reglas que `Routine.php`) y ocurrencias
/// (diaria cada N días, semanal cada N semanas en días ISO 1-7, mensual cada N meses).
final class RoutineRuleTests: XCTestCase {
    private var utc: TimeZone { TimeZone(identifier: "UTC")! }

    /// Día a mediodía UTC (sin bordes de DST) — 2026-11-02 es lunes.
    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = utc
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    // MARK: - Validación

    func testIntervalBounds() {
        XCTAssertThrowsError(try RoutineRule(frequency: .daily, interval: 0, days: [], startDate: day(2026, 11, 2), endDate: nil)) { error in
            XCTAssertEqual(error as? RoutineRule.ValidationError, .interval)
        }
        XCTAssertThrowsError(try RoutineRule(frequency: .daily, interval: 100, days: [], startDate: day(2026, 11, 2), endDate: nil)) { error in
            XCTAssertEqual(error as? RoutineRule.ValidationError, .interval)
        }
        XCTAssertNoThrow(try RoutineRule(frequency: .daily, interval: 99, days: [], startDate: day(2026, 11, 2), endDate: nil))
    }

    func testWeeklyRequiresISODays() {
        XCTAssertThrowsError(try RoutineRule(frequency: .weekly, interval: 1, days: [], startDate: day(2026, 11, 2), endDate: nil)) { error in
            XCTAssertEqual(error as? RoutineRule.ValidationError, .days)
        }
        XCTAssertThrowsError(try RoutineRule(frequency: .weekly, interval: 1, days: [1, 8], startDate: day(2026, 11, 2), endDate: nil)) { error in
            XCTAssertEqual(error as? RoutineRule.ValidationError, .days)
        }
        XCTAssertThrowsError(try RoutineRule(frequency: .weekly, interval: 1, days: [1, 1], startDate: day(2026, 11, 2), endDate: nil)) { error in
            XCTAssertEqual(error as? RoutineRule.ValidationError, .days)
        }
    }

    func testEndDateMustNotPrecedeStart() {
        XCTAssertThrowsError(try RoutineRule(frequency: .daily, interval: 1, days: [], startDate: day(2026, 11, 2), endDate: day(2026, 11, 1))) { error in
            XCTAssertEqual(error as? RoutineRule.ValidationError, .dateRange)
        }
    }

    func testDaysAreSorted() throws {
        let rule = try RoutineRule(frequency: .weekly, interval: 1, days: [5, 1], startDate: day(2026, 11, 2), endDate: nil)
        XCTAssertEqual(rule.days, [1, 5])
    }

    // MARK: - Ocurrencias

    func testDailyEveryNDays() throws {
        let rule = try RoutineRule(frequency: .daily, interval: 3, days: [], startDate: day(2026, 11, 2), endDate: nil)
        XCTAssertTrue(rule.occurs(on: day(2026, 11, 2), timeZone: utc))
        XCTAssertTrue(rule.occurs(on: day(2026, 11, 5), timeZone: utc))
        XCTAssertTrue(rule.occurs(on: day(2026, 11, 8), timeZone: utc))
        XCTAssertFalse(rule.occurs(on: day(2026, 11, 3), timeZone: utc))
        XCTAssertFalse(rule.occurs(on: day(2026, 11, 1), timeZone: utc), "antes del inicio no toca")
    }

    func testWeeklyEveryNWeeksOnISODays() throws {
        // Semanal cada 2 semanas, lunes (1) y miércoles (3); inicio lunes 2026-11-02.
        let rule = try RoutineRule(frequency: .weekly, interval: 2, days: [3, 1], startDate: day(2026, 11, 2), endDate: nil)
        XCTAssertTrue(rule.occurs(on: day(2026, 11, 2), timeZone: utc), "lunes de la semana 0")
        XCTAssertTrue(rule.occurs(on: day(2026, 11, 4), timeZone: utc), "miércoles de la semana 0")
        XCTAssertFalse(rule.occurs(on: day(2026, 11, 3), timeZone: utc), "martes no elegido")
        XCTAssertFalse(rule.occurs(on: day(2026, 11, 9), timeZone: utc), "semana 1: no toca")
        XCTAssertFalse(rule.occurs(on: day(2026, 11, 11), timeZone: utc), "semana 1: no toca")
        XCTAssertTrue(rule.occurs(on: day(2026, 11, 16), timeZone: utc), "semana 2: toca")
    }

    func testMonthlyEveryNMonthsSameDay() throws {
        let monthly = try RoutineRule(frequency: .monthly, interval: 1, days: [], startDate: day(2026, 11, 2), endDate: nil)
        XCTAssertTrue(monthly.occurs(on: day(2026, 12, 2), timeZone: utc))
        XCTAssertFalse(monthly.occurs(on: day(2026, 12, 3), timeZone: utc))

        let everyTwo = try RoutineRule(frequency: .monthly, interval: 2, days: [], startDate: day(2026, 11, 2), endDate: nil)
        XCTAssertFalse(everyTwo.occurs(on: day(2026, 12, 2), timeZone: utc))
        XCTAssertTrue(everyTwo.occurs(on: day(2027, 1, 2), timeZone: utc))
    }

    func testEndDateStopsOccurrences() throws {
        let rule = try RoutineRule(frequency: .daily, interval: 1, days: [], startDate: day(2026, 11, 2), endDate: day(2026, 11, 4))
        XCTAssertTrue(rule.occurs(on: day(2026, 11, 4), timeZone: utc))
        XCTAssertFalse(rule.occurs(on: day(2026, 11, 5), timeZone: utc))
    }
}
