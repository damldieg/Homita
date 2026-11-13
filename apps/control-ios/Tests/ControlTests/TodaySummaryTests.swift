import XCTest
@testable import ControlKit

final class TodaySummaryTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!

    /// Lunes 9 de noviembre de 2026, 10:00 UTC.
    private var monday: Date { PHPDateTime.parse("2026-11-09 10:00:00", timeZone: utc)! }

    private func event(_ id: Int, _ dateAt: String) throws -> EventEntry {
        try decodeFixture(EventEntry.self, #"{"id":\#(id),"calendar_id":3,"title":"E\#(id)","date_at":"\#(dateAt)"}"#)
    }

    private func task(_ id: Int, order: Int, done: Bool = false) throws -> TaskEntry {
        let completed = done ? #""2026-11-09 08:00:00""# : "null"
        return try decodeFixture(TaskEntry.self, #"{"id":\#(id),"task_list_id":2,"title":"T\#(id)","completed_at":\#(completed),"order":\#(order)}"#)
    }

    private func routine(_ id: Int, time: String = "09:00", start: String, end: String? = nil, frequency: String?,
                         interval: Int? = 1, days: [Int]? = nil, active: Bool = true) throws -> RoutineEntry {
        let freq = frequency.map { #""\#($0)""# } ?? "null"
        let endJSON = end.map { #""\#($0)""# } ?? "null"
        let daysJSON = days.map { "[" + $0.map(String.init).joined(separator: ",") + "]" } ?? "null"
        let intervalJSON = interval.map(String.init) ?? "null"
        return try decodeFixture(RoutineEntry.self, """
        {"id":\(id),"calendar_id":3,"title":"R\(id)","time":"\(time)","start_date":"\(start)","end_date":\(endJSON),\
        "active":\(active),"frequency":\(freq),"interval":\(intervalJSON),"days":\(daysJSON)}
        """)
    }

    // MARK: dayRange

    func testDayRangeIsTenDigitsAndSpansTheDay() throws {
        let clock = LocalClock(now: monday, timeZone: utc)
        let range = clock.dayRange
        XCTAssertEqual(range.start.count, 10)
        XCTAssertEqual(range.end.count, 10)
        XCTAssertEqual(Int(range.end)! - Int(range.start)!, 86_399)
        let midnight = PHPDateTime.parse("2026-11-09 00:00:00", timeZone: utc)!
        XCTAssertEqual(range.start, String(Int(midnight.timeIntervalSince1970)))
    }

    func testDayRangeUsesLocalOffset() throws {
        let madrid = TimeZone(identifier: "Europe/Madrid")!
        let now = PHPDateTime.parse("2026-11-09 10:00:00", timeZone: madrid)!
        let range = LocalClock(now: now, timeZone: madrid).dayRange
        // Hora local como epoch "como si fuese UTC": 00:00 local == medianoche UTC del mismo día.
        let utcMidnight = PHPDateTime.parse("2026-11-09 00:00:00", timeZone: utc)!
        XCTAssertEqual(range.start, String(Int(utcMidnight.timeIntervalSince1970)))
    }

    // MARK: eventos

    func testEventsKeepOnlyTodayAndSortByTime() throws {
        let list = [
            try event(1, "2026-11-09 18:00:00"),
            try event(2, "2026-11-08 23:59:59"),
            try event(3, "2026-11-09 08:30:00"),
            try event(4, "2026-11-10 00:00:00")
        ]
        let today = TodaySummary.events(list, on: monday, timeZone: utc)
        XCTAssertEqual(today.map(\.id), [3, 1])
    }

    func testEventsIgnoreUnreadableDates() throws {
        let list = [try event(1, "no-es-fecha"), try event(2, "2026-11-09 09:00:00")]
        XCTAssertEqual(TodaySummary.events(list, on: monday, timeZone: utc).map(\.id), [2])
    }

    func testSplitEventsSeparatesPastFromUpcoming() throws {
        let list = [
            try event(1, "2026-11-09 08:00:00"),  // 2 h antes: pasado
            try event(2, "2026-11-09 09:00:00"),  // justo 1 h antes: pasado
            try event(3, "2026-11-09 09:30:00"),  // en curso (30 min): sigue arriba
            try event(4, "2026-11-09 20:00:00"),  // próximo
        ]
        let split = TodaySummary.splitEvents(list, now: monday, timeZone: utc)
        XCTAssertEqual(split.past.map(\.id), [1, 2])
        XCTAssertEqual(split.upcoming.map(\.id), [3, 4])
    }

    func testSplitEventsKeepsUnreadableDatesUpcoming() throws {
        let split = TodaySummary.splitEvents([try event(1, "no-es-fecha")], now: monday, timeZone: utc)
        XCTAssertTrue(split.past.isEmpty)
        XCTAssertEqual(split.upcoming.map(\.id), [1])
    }

    // MARK: tareas

    func testPendingTasksAreLimitedAndOrdered() throws {
        var list = try (1...8).map { try task($0, order: 10 - $0) }
        list.append(try task(99, order: 0, done: true))
        let pending = TodaySummary.pendingTasks(list, limit: 5)
        XCTAssertEqual(pending.count, 5)
        XCTAssertEqual(pending.map(\.id), [8, 7, 6, 5, 4])
        XCTAssertFalse(pending.contains { $0.id == 99 })
        XCTAssertEqual(TodaySummary.taskLimit, 5)
    }

    // MARK: rutinas

    func testWeeklyMondayOnlyOccursOnMonday() throws {
        let weekly = try routine(1, start: "2026-11-02", frequency: "weekly", days: [1])
        XCTAssertEqual(TodaySummary.routines([weekly], on: monday, timeZone: utc).map(\.id), [1])
        let tuesday = PHPDateTime.parse("2026-11-10 10:00:00", timeZone: utc)!
        XCTAssertTrue(TodaySummary.routines([weekly], on: tuesday, timeZone: utc).isEmpty)
    }

    func testDailyEveryTwoDaysAlternates() throws {
        let daily = try routine(1, start: "2026-11-08", frequency: "daily", interval: 2)
        let sunday = PHPDateTime.parse("2026-11-08 10:00:00", timeZone: utc)!
        let tuesday = PHPDateTime.parse("2026-11-10 10:00:00", timeZone: utc)!
        XCTAssertEqual(TodaySummary.routines([daily], on: sunday, timeZone: utc).count, 1)
        XCTAssertTrue(TodaySummary.routines([daily], on: monday, timeZone: utc).isEmpty)
        XCTAssertEqual(TodaySummary.routines([daily], on: tuesday, timeZone: utc).count, 1)
    }

    func testMonthlyOccursOnSameDayOfMonth() throws {
        let monthly = try routine(1, start: "2026-10-09", frequency: "monthly")
        XCTAssertEqual(TodaySummary.routines([monthly], on: monday, timeZone: utc).count, 1)
    }

    func testInactiveAndExpiredRoutinesAreHidden() throws {
        let inactive = try routine(1, start: "2026-11-01", frequency: "daily", active: false)
        let expired = try routine(2, start: "2026-10-01", end: "2026-11-05", frequency: "daily")
        let future = try routine(3, start: "2026-11-20", frequency: "daily")
        XCTAssertTrue(TodaySummary.routines([inactive, expired, future], on: monday, timeZone: utc).isEmpty)
    }

    func testRoutinesSortedByTime() throws {
        let late = try routine(1, time: "20:00", start: "2026-11-01", frequency: "daily")
        let early = try routine(2, time: "07:30", start: "2026-11-01", frequency: "daily")
        XCTAssertEqual(TodaySummary.routines([late, early], on: monday, timeZone: utc).map(\.id), [2, 1])
    }

    func testNilFrequencyIsWeeklyWithDaysElseOmitted() throws {
        let legacyWeekly = try routine(1, start: "2026-11-02", frequency: nil, interval: nil, days: [1])
        let legacyNoDays = try routine(2, start: "2026-11-02", frequency: nil, interval: nil, days: nil)
        XCTAssertEqual(legacyWeekly.rule(timeZone: utc)?.frequency, .weekly)
        XCTAssertNil(legacyNoDays.rule(timeZone: utc))
        XCTAssertEqual(TodaySummary.routines([legacyWeekly, legacyNoDays], on: monday, timeZone: utc).map(\.id), [1])
    }
}
