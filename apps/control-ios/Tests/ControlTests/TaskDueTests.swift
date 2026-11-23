import XCTest
import HomitaShared
@testable import ControlKit

/// Fecha límite de tareas (0041, fecha-limite-vencimiento): formato, banner de Inicio, avisos y cola offline.
final class TaskDueTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!
    private lazy var now = PHPDateTime.parse("2026-12-01 10:00:00", timeZone: utc)!

    private func task(_ id: Int, due: String?, priority: String = "alta", done: Bool = false,
                      persons: [Int]? = nil) throws -> TaskEntry {
        let personsJSON = persons.map { ids in
            ",\"persons\":[" + ids.map { "{\"id\":\($0),\"user_id\":1,\"name\":\"P\($0)\",\"color\":\"#000000\"}" }.joined(separator: ",") + "]"
        } ?? ""
        let dueJSON = due.map { "\"\($0)\"" } ?? "null"
        let completed = done ? "\"2026-12-01 09:00:00\"" : "null"
        let json = """
        {"id":\(id),"task_list_id":1,"title":"Tarea \(id)","completed_at":\(completed),"order":\(id),
         "priority":"\(priority)","due_at":\(dueJSON)\(personsJSON)}
        """
        return try JSONDecoder().decode(TaskEntry.self, from: Data(json.utf8))
    }

    private func person(_ id: Int, appUserId: Int?) throws -> PersonEntry {
        let userJSON = appUserId.map(String.init) ?? "null"
        let json = """
        {"id":\(id),"user_id":1,"name":"P\(id)","color":"#000000","app_user_id":\(userJSON)}
        """
        return try JSONDecoder().decode(PersonEntry.self, from: Data(json.utf8))
    }

    // MARK: - Formato

    func testFormatRoundTripIsUTC() {
        let date = PHPDateTime.parse("2026-12-03 18:30:00", timeZone: utc)!
        XCTAssertEqual(TaskDue.format(date), "2026-12-03 18:30:00")
        XCTAssertEqual(TaskDue.date("2026-12-03 18:30:00"), date)
    }

    func testEmptyOrMissingDueIsNil() {
        XCTAssertNil(TaskDue.date(nil))
        XCTAssertNil(TaskDue.date(""))
    }

    // MARK: - Banner de Inicio

    func testBannerPicksEarliestHighPriorityFutureTask() throws {
        let later = try task(1, due: "2026-12-02 10:00:00")
        let sooner = try task(2, due: "2026-12-01 12:00:00")
        let media = try task(3, due: "2026-12-01 11:00:00", priority: "media")
        let past = try task(4, due: "2026-12-01 09:00:00")
        let done = try task(5, due: "2026-12-01 10:30:00", done: true)
        let banner = TaskDue.banner(tasks: [later, sooner, media, past, done], now: now, roster: [], currentUserId: nil, dismissed: [])
        XCTAssertEqual(banner?.task.id, 2)
    }

    func testBannerSkipsTasksAssignedToSomeoneElse() throws {
        let mineRoster = [try person(10, appUserId: 7), try person(11, appUserId: 8)]
        let others = try task(1, due: "2026-12-01 12:00:00", persons: [11])
        let mine = try task(2, due: "2026-12-02 12:00:00", persons: [10])
        let unassigned = try task(3, due: "2026-12-03 12:00:00")
        let banner = TaskDue.banner(tasks: [others, mine, unassigned], now: now, roster: mineRoster, currentUserId: 7, dismissed: [])
        XCTAssertEqual(banner?.task.id, 2)
        let onlyOthers = TaskDue.banner(tasks: [others], now: now, roster: mineRoster, currentUserId: 7, dismissed: [])
        XCTAssertNil(onlyOthers)
    }

    func testDismissedBannerDoesNotReturn() throws {
        let only = try task(1, due: "2026-12-01 12:00:00")
        XCTAssertNil(TaskDue.banner(tasks: [only], now: now, roster: [], currentUserId: nil, dismissed: [1]))
    }

    // MARK: - Avisos locales

    func testReminderLeadsAreOneDayTwelveThreeAndOneHour() throws {
        let due = try task(1, due: "2026-12-03 18:00:00")
        let planned = NotificationPlanner.dueNotifications([due], now: now, timeZone: utc, myPersonIds: nil)
        let leads = planned.map { Int(PHPDateTime.parse("2026-12-03 18:00:00", timeZone: utc)!.timeIntervalSince($0.fireDate)) }
        XCTAssertEqual(leads.sorted(), [3600, 3 * 3600, 12 * 3600, 24 * 3600])
        XCTAssertTrue(planned.allSatisfy { $0.kind == .taskDue && $0.id.hasPrefix("homita.task-due.1.") })
    }

    func testNoRemindersForNonHighPriorityOrWithoutDue() throws {
        let media = try task(1, due: "2026-12-03 18:00:00", priority: "media")
        let nodue = try task(2, due: nil)
        XCTAssertTrue(NotificationPlanner.dueNotifications([media, nodue], now: now, timeZone: utc, myPersonIds: nil).isEmpty)
    }

    func testPastRemindersAreNotScheduled() throws {
        // Vence a las 12:00 y ahora son las 10:00: 1 d, 12 h y 3 h ya pasaron (su hora de aviso es anterior
        // a ahora); solo queda el de 1 h, que suena a las 11:00.
        let soon = try task(1, due: "2026-12-01 12:00:00")
        let planned = NotificationPlanner.dueNotifications([soon], now: now, timeZone: utc, myPersonIds: nil)
        XCTAssertEqual(planned.map(\.id), ["homita.task-due.1.3600"])
    }

    func testRemindersFilterByMyPersons() throws {
        let theirs = try task(1, due: "2026-12-03 18:00:00", persons: [11])
        XCTAssertTrue(NotificationPlanner.dueNotifications([theirs], now: now, timeZone: utc, myPersonIds: [10]).isEmpty)
        let mine = try task(2, due: "2026-12-03 18:00:00", persons: [10])
        XCTAssertEqual(NotificationPlanner.dueNotifications([mine], now: now, timeZone: utc, myPersonIds: [10]).count, 4)
    }

    // MARK: - Cola offline

    func testOverlayShowsDueOfPendingCreateAndUpdate() {
        let list = TaskListEntry(
            id: 2, name: "Compra", color: "#6923E2", token: nil, sort: "custom", created_at: nil, updated_at: nil,
            widget: nil, dashboard: nil, pending_task_count: FlexInt(0), can_edit: nil
        )
        let created = PendingOp(homeId: "1", kind: .createTask(local: -1, listRef: .remote(2), title: "Pan", personIds: nil,
                                                              priority: "alta", dueAt: "2026-12-03 18:00:00"))
        let result = PendingOverlay.apply(ops: [created], idMap: [:], tasks: [], lists: [list])
        XCTAssertEqual(result.tasks.first?.due_at, "2026-12-03 18:00:00")

        let cleared = PendingOp(homeId: "1", kind: .updateTask(ref: .remote(7), listRef: .remote(2), title: "Pan", personIds: nil,
                                                              priority: nil, dueAt: ""))
        let base = try? task(7, due: "2026-12-03 18:00:00")
        let updated = PendingOverlay.apply(ops: [cleared], idMap: [:], tasks: base.map { [$0] } ?? [], lists: [list])
        XCTAssertNil(updated.tasks.first?.due_at)
    }

    func testCompactorMergesDueIntoPendingCreate() {
        let create = PendingOp(homeId: "1", kind: .createTask(local: -1, listRef: .remote(2), title: "Pan", personIds: nil,
                                                             priority: nil, dueAt: nil))
        let update = PendingOp(homeId: "1", kind: .updateTask(ref: .local(-1), listRef: .remote(2), title: "Pan", personIds: nil,
                                                             priority: nil, dueAt: "2026-12-03 18:00:00"))
        let queue = OutboxCompactor.enqueue(update, into: [create], inFlight: nil)
        XCTAssertEqual(queue.count, 1)
        guard case .createTask(_, _, _, _, _, let due) = queue[0].kind else { return XCTFail("debe quedar el create") }
        XCTAssertEqual(due, "2026-12-03 18:00:00")
    }
}
