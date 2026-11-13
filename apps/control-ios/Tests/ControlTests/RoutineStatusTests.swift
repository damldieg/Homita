import XCTest
@testable import ControlKit

/// `RoutineStatus`: caducada (> inicio + 1 h), en curso ([inicio, inicio + 1 h]), resto y sin hora fija.
final class RoutineStatusTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    func testExpiredAfterOneHour() {
        XCTAssertEqual(RoutineStatus.evaluate(start: start, now: start.addingTimeInterval(3601)), .expired)
    }

    func testInProgressWithinWindowInclusive() {
        XCTAssertEqual(RoutineStatus.evaluate(start: start, now: start), .inProgress)
        XCTAssertEqual(RoutineStatus.evaluate(start: start, now: start.addingTimeInterval(1800)), .inProgress)
        XCTAssertEqual(RoutineStatus.evaluate(start: start, now: start.addingTimeInterval(3600)), .inProgress)
    }

    func testNormalBeforeStart() {
        XCTAssertEqual(RoutineStatus.evaluate(start: start, now: start.addingTimeInterval(-1)), .normal)
    }

    func testNoFixedTimeIsNormal() {
        XCTAssertEqual(RoutineStatus.evaluate(start: nil, now: start), .normal)
    }

    func testStartTodayParsing() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertNotNil(RoutineStatus.startToday(time: "09:30", now: now, timeZone: utc))
        XCTAssertNotNil(RoutineStatus.startToday(time: "09:30:00", now: now, timeZone: utc))
        XCTAssertNil(RoutineStatus.startToday(time: "", now: now, timeZone: utc))
        XCTAssertNil(RoutineStatus.startToday(time: "25:00", now: now, timeZone: utc))
    }

    func testRelevantStartPicksLatestStarted() {
        let early = start.addingTimeInterval(-7200)
        let late = start.addingTimeInterval(-600)
        let future = start.addingTimeInterval(600)
        XCTAssertEqual(RoutineStatus.relevantStart(among: [early, late, future], now: start), late)
        XCTAssertNil(RoutineStatus.relevantStart(among: [future], now: start))
    }

    func testRoutinesWithoutTimeGoLast() throws {
        let json = { (id: Int, time: String) in
            #"{"id":\#(id),"calendar_id":1,"title":"R\#(id)","time":"\#(time)","start_date":"2026-11-02"}"#
        }
        let entries = try [json(1, ""), json(2, "09:00"), json(3, "08:00")].map {
            try JSONDecoder().decode(RoutineEntry.self, from: Data($0.utf8))
        }
        XCTAssertEqual(entries.map(\.hasFixedTime), [false, true, true])
        let ordered = entries.filter(\.hasFixedTime) + entries.filter { !$0.hasFixedTime }
        XCTAssertEqual(ordered.map(\.id), [2, 3, 1])
    }
}

/// Estado sobre la ocurrencia mostrada (la próxima), no sobre la de hoy.
final class RoutineShownStatusTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testDailyRoutinePassedTodayShowsNormalForTomorrow() {
        let started = now.addingTimeInterval(-7200) // hoy hace 2 h: caducada
        let tomorrow = now.addingTimeInterval(86_400 - 7200)
        XCTAssertEqual(RoutineStatus.evaluate(start: started, now: now), .expired)
        XCTAssertEqual(RoutineStatus.evaluateShown(started: started, next: tomorrow, now: now), .normal)
    }

    func testInProgressWinsEvenWithNext() {
        let started = now.addingTimeInterval(-600)
        XCTAssertEqual(RoutineStatus.evaluateShown(started: started, next: now.addingTimeInterval(80_000), now: now), .inProgress)
    }

    func testWithoutNextFallsBackToToday() {
        XCTAssertEqual(RoutineStatus.evaluateShown(started: now.addingTimeInterval(-7200), next: nil, now: now), .expired)
        XCTAssertEqual(RoutineStatus.evaluateShown(started: nil, next: nil, now: now), .normal)
    }

    /// Aviso (E1-04): aún no empieza y a ≤ 60 min del inicio.
    func testIsSoonWithinOneHourBeforeStart() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertTrue(RoutineStatus.isSoon(start: start, now: start.addingTimeInterval(-3600)))
        XCTAssertTrue(RoutineStatus.isSoon(start: start, now: start.addingTimeInterval(-1800)))
        XCTAssertFalse(RoutineStatus.isSoon(start: start, now: start.addingTimeInterval(-3601)))
        XCTAssertFalse(RoutineStatus.isSoon(start: start, now: start), "ya empieza: en curso, no aviso")
        XCTAssertFalse(RoutineStatus.isSoon(start: nil, now: start))
    }
}
