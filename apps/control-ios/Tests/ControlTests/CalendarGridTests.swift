import XCTest
@testable import ControlKit

/// B3: días visibles, desplazamiento y rangos de consulta del calendario (zona fija Europe/Madrid).
final class CalendarGridTests: XCTestCase {
    private let grid = CalendarGrid(timeZone: TimeZone(identifier: "Europe/Madrid")!)

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        var c = grid.calendar
        c.timeZone = grid.timeZone
        return c.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    func testMonthGridStartsOnMondayAndCoversWholeMonth() {
        // 2026-11: el 1 es domingo; la cuadrícula empieza el lunes 26-10 y acaba en un domingo.
        let days = grid.visibleDays(mode: .month, anchor: date(2026, 11, 11))
        XCTAssertEqual(days.count % 7, 0)
        XCTAssertEqual(grid.calendar.component(.weekday, from: days.first!), 2, "lunes")
        XCTAssertTrue(days.contains { grid.calendar.isDate($0, inSameDayAs: date(2026, 11, 1)) })
        XCTAssertTrue(days.contains { grid.calendar.isDate($0, inSameDayAs: date(2026, 11, 30)) })
        XCTAssertEqual(days.count, 42, "noviembre 2026 ocupa 6 filas")
    }

    func testWeekIsMondayToSunday() {
        let days = grid.visibleDays(mode: .week, anchor: date(2026, 11, 11))
        XCTAssertEqual(days.count, 7)
        XCTAssertEqual(grid.calendar.component(.weekday, from: days.first!), 2)
        XCTAssertTrue(days.contains { grid.calendar.isDate($0, inSameDayAs: date(2026, 11, 11)) })
    }

    func testDayQueryRangeCoversLocalDayInTenDigitEpochs() {
        let days = grid.visibleDays(mode: .day, anchor: date(2026, 11, 11))
        guard let range = grid.queryRange(days: days) else { return XCTFail("sin rango") }
        XCTAssertEqual(range.start.count, 10)
        XCTAssertEqual(range.end.count, 10)
        XCTAssertEqual(Int(range.end)! - Int(range.start)!, 86_399, "un día completo menos un segundo")
    }

    func testShiftMovesByModeUnit() {
        let anchor = date(2026, 11, 11)
        XCTAssertTrue(grid.calendar.isDate(grid.shift(anchor, mode: .month, by: 1), inSameDayAs: date(2026, 12, 11)))
        XCTAssertTrue(grid.calendar.isDate(grid.shift(anchor, mode: .week, by: -1), inSameDayAs: date(2026, 11, 4)))
        XCTAssertTrue(grid.calendar.isDate(grid.shift(anchor, mode: .day, by: 1), inSameDayAs: date(2026, 11, 12)))
    }

    /// Meses de 4 y 5 filas (R1-06): febrero 2027 empieza en lunes y cabe en 4 semanas; junio 2026 en 5.
    func testMonthGridRowCountsFollowCalendar() {
        XCTAssertEqual(grid.visibleDays(mode: .month, anchor: date(2027, 2, 10)).count, 28)
        XCTAssertEqual(grid.visibleDays(mode: .month, anchor: date(2026, 6, 10)).count, 35)
    }
}
