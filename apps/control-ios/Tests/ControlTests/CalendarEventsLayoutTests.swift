import XCTest
@testable import ControlKit

/// Vista semanal de eventos: navegación por semanas, barras de varios días, apilado, «Día N de M» y fecha en español.
@MainActor
final class CalendarEventsLayoutTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!
    // Semana lunes 2026-11-09 … domingo 2026-11-15.
    private let week = ["2026-11-09", "2026-11-10", "2026-11-11", "2026-11-12", "2026-11-13", "2026-11-14", "2026-11-15"]

    private func event(_ id: Int, _ start: String, end: String? = nil, color: String? = "#0E9F6E") -> EventEntry {
        var entry = EventEntry(
            id: id, calendar_id: 3, title: "E\(id)", date_at: "\(start) 09:00:00", created_at: nil, updated_at: nil,
            routine_id: nil, routine_date: nil, calendar_color: color, calendar_name: nil, alarm: nil, persons: nil
        )
        entry.end_date = end
        return entry
    }

    private func dayDate(_ ymd: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = utc
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: ymd)!
    }

    // MARK: - AC1 navegación

    func testSwipeLeftIsNextWeekAndRightIsPrevious() {
        XCTAssertEqual(CalendarWeekLayout.weekStep(swipeWidth: -120, height: 10), 1)
        XCTAssertEqual(CalendarWeekLayout.weekStep(swipeWidth: 120, height: -10), -1)
    }

    func testShortOrDiagonalDragIsNotAWeekSwipe() {
        XCTAssertNil(CalendarWeekLayout.weekStep(swipeWidth: -30, height: 0), "recorrido corto")
        XCTAssertNil(CalendarWeekLayout.weekStep(swipeWidth: -80, height: 60), "más vertical que el umbral")
    }

    func testMoveWeekKeepsWeekdayAndReloads() async {
        StubURLProtocol.reset { _ in StubURLProtocol.Stub(json: "[]") }
        let now = dayDate("2026-11-11").addingTimeInterval(12 * 3600) // miércoles
        let store = CalendarAgendaStore(repo: EventRepository(client: makeTestClient()), grid: CalendarGrid(timeZone: utc), now: { now })
        await store.load()
        let before = StubURLProtocol.requests.count
        await store.moveWeek(1)
        XCTAssertEqual(store.dayString(store.anchor), "2026-11-18")
        XCTAssertEqual(store.grid.calendar.component(.weekday, from: store.anchor), 4, "sigue en miércoles")
        XCTAssertEqual(StubURLProtocol.requests.count, before + 1, "otra semana: recarga")
        await store.moveWeek(-2)
        XCTAssertEqual(store.dayString(store.anchor), "2026-11-04")
        await store.goToToday()
        XCTAssertTrue(store.isToday)
        await store.select(dayDate("2026-11-13"))
        XCTAssertEqual(store.dayString(store.anchor), "2026-11-13", "tocar un día lo selecciona")
    }

    // MARK: - AC4 barras de varios días

    func testSpanInsideWeekIsRoundedOnBothEnds() {
        let spans = CalendarWeekLayout.spans(events: [event(1, "2026-11-10", end: "2026-11-12")], weekDays: week)
        XCTAssertEqual(spans, [EventWeekSpan(eventId: 1, colorHex: "#0E9F6E", startColumn: 1, endColumn: 3,
                                             continuesBefore: false, continuesAfter: false, row: 0)])
    }

    func testSpanCrossingWeeksIsClippedAndMarksContinuation() {
        let spans = CalendarWeekLayout.spans(events: [event(1, "2026-11-05", end: "2026-11-20")], weekDays: week)
        XCTAssertEqual(spans.count, 1)
        XCTAssertEqual(spans[0].startColumn, 0)
        XCTAssertEqual(spans[0].endColumn, 6)
        XCTAssertTrue(spans[0].continuesBefore)
        XCTAssertTrue(spans[0].continuesAfter)
    }

    func testSingleDayAndOutOfWeekEventsHaveNoBar() {
        let spans = CalendarWeekLayout.spans(events: [
            event(1, "2026-11-10"),
            event(2, "2026-11-10", end: "2026-11-10"),
            event(3, "2026-11-16", end: "2026-11-18"),
            event(4, "2026-11-01", end: "2026-11-08"),
        ], weekDays: week)
        XCTAssertTrue(spans.isEmpty)
    }

    func testOverlappingSpansStackInRowsAndReuseFreeRows() {
        let spans = CalendarWeekLayout.spans(events: [
            event(1, "2026-11-09", end: "2026-11-11"),
            event(2, "2026-11-10", end: "2026-11-13"),
            event(3, "2026-11-12", end: "2026-11-14"),
        ], weekDays: week)
        let rows = Dictionary(uniqueKeysWithValues: spans.map { ($0.eventId, $0.row) })
        XCTAssertEqual(rows[1], 0)
        XCTAssertEqual(rows[2], 1, "se solapa con el 1")
        XCTAssertEqual(rows[3], 0, "la fila 0 queda libre desde el jueves")
        XCTAssertEqual(CalendarWeekLayout.rowCount(spans), 2)
    }

    func testMissingColorUsesFallback() {
        let spans = CalendarWeekLayout.spans(events: [event(1, "2026-11-10", end: "2026-11-11", color: nil)], weekDays: week)
        XCTAssertEqual(spans.first?.colorHex, Palette.fallbackItem)
    }

    func testDayLabelCountsEachDayOfTheRange() {
        let trip = event(1, "2026-11-28", end: "2026-12-02") // cruza mes
        XCTAssertEqual(CalendarWeekLayout.dayLabel(of: trip, on: "2026-11-28"), "Día 1 de 5")
        XCTAssertEqual(CalendarWeekLayout.dayLabel(of: trip, on: "2026-11-30"), "Día 3 de 5")
        XCTAssertEqual(CalendarWeekLayout.dayLabel(of: trip, on: "2026-12-02"), "Día 5 de 5")
        XCTAssertNil(CalendarWeekLayout.dayLabel(of: trip, on: "2026-12-03"))
        XCTAssertNil(CalendarWeekLayout.dayLabel(of: event(2, "2026-11-28"), on: "2026-11-28"), "un solo día")
    }

    // MARK: - AC5 fecha en español

    func testDayTitleIsSpanishWithOnlyInitialCapital() {
        XCTAssertEqual(CalendarWeekLayout.dayTitle(dayDate("2026-11-23"), timeZone: utc), "Lunes, 23 de noviembre")
    }

    func testWeekdayLettersStartOnMonday() {
        XCTAssertEqual(CalendarWeekLayout.weekdayLetters(), ["L", "M", "X", "J", "V", "S", "D"])
    }

    func testLocaleIsSpanishSpain() {
        XCTAssertEqual(CalendarWeekLayout.locale.identifier, "es_ES")
    }
}
