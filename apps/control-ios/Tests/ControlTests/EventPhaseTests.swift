import XCTest
@testable import ControlKit

/// D-020: clasificación «en curso» por día y zona del dispositivo.
final class EventPhaseTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!

    private func event(_ dateAt: String = "2026-11-10 09:00:00", end: String? = "2026-11-20") -> EventEntry {
        EventEntry(id: 1, calendar_id: 1, title: "Vacaciones", date_at: dateAt, created_at: nil, updated_at: nil,
                   routine_id: nil, routine_date: nil, calendar_color: nil, calendar_name: nil, alarm: nil,
                   persons: nil, end_date: end)
    }

    private func clock(_ iso: String, _ zone: TimeZone? = nil) -> LocalClock {
        let f = ISO8601DateFormatter()
        return LocalClock(now: f.date(from: iso)!, timeZone: zone ?? utc)
    }

    func testDayBeforeStartIsUpcoming() {
        XCTAssertEqual(event().phase(clock: clock("2026-11-09T12:00:00Z")), .upcoming)
    }

    func testStartDayIsOngoingEvenBeforeTheTime() {
        XCTAssertEqual(event().phase(clock: clock("2026-11-10T00:30:00Z")), .ongoing)
    }

    func testMiddleDayIsOngoing() {
        XCTAssertEqual(event().phase(clock: clock("2026-11-15T12:00:00Z")), .ongoing)
    }

    func testEndDayIsInclusive() {
        XCTAssertEqual(event().phase(clock: clock("2026-11-20T23:59:00Z")), .ongoing)
    }

    func testDayAfterEndIsPast() {
        XCTAssertEqual(event().phase(clock: clock("2026-11-21T00:00:00Z")), .past)
    }

    func testWithoutEndIsNeverOngoing() {
        let single = event(end: nil)
        XCTAssertFalse(single.isOngoing(today: "2026-11-10"))
        XCTAssertEqual(single.phase(clock: clock("2026-11-10T12:00:00Z")), .upcoming)
    }

    func testMalformedEndIsNotOngoing() {
        for bad in ["", "abc", "2026-13-40", "2026/11/20", "20-11"] {
            XCTAssertFalse(event(end: bad).isOngoing(today: "2026-11-15"), bad)
        }
    }

    func testSameInstantDifferentDayByTimeZone() {
        // 2026-11-20T23:30Z: en UTC es el 20 (en curso); en Madrid (+1) ya es el 21 (pasado).
        let madrid = TimeZone(identifier: "Europe/Madrid")!
        let instant = "2026-11-20T23:30:00Z"
        XCTAssertEqual(event().phase(clock: clock(instant, utc)), .ongoing)
        XCTAssertEqual(event().phase(clock: clock(instant, madrid)), .past)
    }

    func testEndEqualToStartDayIsSingleDayNotOngoing() {
        let same = event(end: "2026-11-10")
        XCTAssertNil(same.validEndDay)
        XCTAssertFalse(same.isOngoing(today: "2026-11-10"))
        XCTAssertEqual(same.phase(clock: clock("2026-11-09T12:00:00Z")), .upcoming)
        XCTAssertEqual(same.phase(clock: clock("2026-11-10T12:00:00Z")), .upcoming)
        XCTAssertEqual(same.phase(clock: clock("2026-11-11T00:00:00Z")), .past)
        // Fin anterior al inicio: tampoco es rango.
        XCTAssertNil(event(end: "2026-11-09").validEndDay)
        // Fin un día después: sí es rango.
        XCTAssertTrue(event(end: "2026-11-11").isOngoing(today: "2026-11-11"))
    }
}
