import XCTest
import HomitaShared
@testable import ControlKit

final class DailySummaryPlannerTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!
    private var day: Date { PHPDateTime.parse("2026-11-09 08:00:00", timeZone: utc)! }
    private let mine: Set<Int> = [7]

    private func persons(_ ids: [Int]) -> String {
        "[" + ids.map { "{\"id\":\($0),\"user_id\":1,\"name\":\"P\($0)\",\"color\":\"#000000\"}" }.joined(separator: ",") + "]"
    }

    private func event(_ id: Int, _ dateAt: String, persons ids: [Int] = [7], end: String? = nil,
                       routineId: Int? = nil) throws -> EventEntry {
        let endJSON = end.map { #""\#($0)""# } ?? "null"
        let routineJSON = routineId.map(String.init) ?? "null"
        let json = """
        {"id":\(id),"calendar_id":1,"title":"E\(id)","date_at":"\(dateAt)","routine_id":\(routineJSON),
         "end_date":\(endJSON),"persons":\(persons(ids))}
        """
        return try JSONDecoder().decode(EventEntry.self, from: Data(json.utf8))
    }

    private func task(_ id: Int, persons ids: [Int] = [7], done: Bool = false) throws -> TaskEntry {
        let completed = done ? #""2026-11-09 07:00:00""# : "null"
        let json = """
        {"id":\(id),"task_list_id":1,"title":"T\(id)","completed_at":\(completed),"order":\(id),"persons":\(persons(ids))}
        """
        return try JSONDecoder().decode(TaskEntry.self, from: Data(json.utf8))
    }

    private func summary(events: [EventEntry] = [], tasks: [TaskEntry] = [], ids: Set<Int>? = [7]) -> DailySummary? {
        DailySummaryPlanner.summary(events: events, tasks: tasks, myPersonIds: ids, day: day, timeZone: utc)
    }

    func testTodayEventsOfMineAreIncluded() throws {
        let result = try XCTUnwrap(summary(events: [
            try event(1, "2026-11-09 18:30:00"), try event(2, "2026-11-10 09:00:00")
        ]))
        XCTAssertEqual(result.eventCount, 1)
        XCTAssertEqual(result.taskCount, 0)
        XCTAssertTrue(result.body.contains("18:30 E1"))
        XCTAssertFalse(result.body.contains("E2"))
    }

    func testMultiDayEventIsExcluded() throws {
        XCTAssertNil(summary(events: [try event(1, "2026-11-09 10:00:00", end: "2026-11-12")]))
    }

    func testEndDateNotAfterStartStillCountsAsSingleDay() throws {
        XCTAssertEqual(summary(events: [try event(1, "2026-11-09 10:00:00", end: "2026-11-09")])?.eventCount, 1)
    }

    func testMidnightEventIsAllDay() throws {
        let result = try XCTUnwrap(summary(events: [try event(1, "2026-11-09 00:00:00")]))
        XCTAssertEqual(result.eventCount, 1)
        XCTAssertTrue(result.body.contains("Todo el día E1"))
        XCTAssertFalse(result.body.contains("00:00"))
    }

    func testRoutineSessionIsExcluded() throws {
        XCTAssertNil(summary(events: [try event(1, "2026-11-09 10:00:00", routineId: 5)]))
    }

    func testOthersEventsAndTasksAreExcluded() throws {
        XCTAssertNil(summary(events: [try event(1, "2026-11-09 10:00:00", persons: [8])],
                             tasks: [try task(1, persons: [8]), try task(2, persons: [])]))
    }

    func testPendingTasksOfMineAreIncludedAndCompletedExcluded() throws {
        let result = try XCTUnwrap(summary(tasks: [try task(1), try task(2, done: true), try task(3, persons: [9])]))
        XCTAssertEqual(result.taskCount, 1)
        XCTAssertEqual(result.eventCount, 0)
        XCTAssertTrue(result.body.contains("T1"))
        XCTAssertFalse(result.body.contains("T2"))
    }

    func testBodyCountsAndLimitsTitles() throws {
        let result = try XCTUnwrap(summary(
            events: [try event(1, "2026-11-09 09:00:00"), try event(2, "2026-11-09 10:00:00")],
            tasks: [try task(3), try task(4), try task(5)]
        ))
        XCTAssertTrue(result.body.hasPrefix("2 eventos, 3 tareas: "))
        XCTAssertTrue(result.body.hasSuffix("…"))
        XCTAssertFalse(result.body.contains("T4"))
    }

    func testNoLinkedPersonReturnsNil() throws {
        let events = [try event(1, "2026-11-09 10:00:00")]
        XCTAssertNil(summary(events: events, tasks: [try task(1)], ids: []))
        XCTAssertNil(summary(events: events, tasks: [try task(1)], ids: nil))
    }

    func testNothingReturnsNil() {
        XCTAssertNil(summary())
    }
}
