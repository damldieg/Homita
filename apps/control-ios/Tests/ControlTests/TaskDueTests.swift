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

    // MARK: - Cobertura de AC4 (cambiar la fecha reprograma) y AC6 (completar o vencer quita el aviso)

    /// AC4: cambiar la fecha cambia la hora de cada aviso. Los ids no llevan la fecha, así que
    /// `replaceAll` (que borra los pendientes `homita.*`) deja solo los nuevos.
    func testChangingDueMovesEveryReminder() throws {
        let before = try task(1, due: "2026-12-03 18:00:00")
        let after = try task(1, due: "2026-12-04 18:00:00")
        let old = NotificationPlanner.dueNotifications([before], now: now, timeZone: utc, myPersonIds: nil)
        let new = NotificationPlanner.dueNotifications([after], now: now, timeZone: utc, myPersonIds: nil)
        XCTAssertEqual(old.map(\.id), new.map(\.id))
        for (a, b) in zip(old, new) {
            XCTAssertEqual(b.fireDate.timeIntervalSince(a.fireDate), 24 * 3600, accuracy: 1)
        }
    }

    /// AC6: una tarea completada no deja avisos pendientes.
    func testCompletedTaskHasNoReminders() throws {
        let done = try task(1, due: "2026-12-03 18:00:00", done: true)
        XCTAssertTrue(NotificationPlanner.dueNotifications([done], now: now, timeZone: utc, myPersonIds: nil).isEmpty)
    }

    /// AC6: al vencer, el banner desaparece (la hora límite ya no es futura).
    func testBannerGoneAfterDueTime() throws {
        let due = try task(1, due: "2026-12-01 09:30:00")
        XCTAssertNil(TaskDue.banner(tasks: [due], now: now, roster: [], currentUserId: nil, dismissed: []))
    }

    /// AC6: al completar, el banner desaparece aunque la fecha siga siendo futura.
    func testBannerGoneWhenCompleted() throws {
        let done = try task(1, due: "2026-12-01 12:00:00", done: true)
        XCTAssertNil(TaskDue.banner(tasks: [done], now: now, roster: [], currentUserId: nil, dismissed: []))
    }

    // MARK: - Resumen de prioridad alta (propias + hogar sin asignar, agrupadas por lista)

    func testHighPriorityForMeKeepsMineAndUnassignedOnly() throws {
        let roster = [try person(10, appUserId: 7), try person(11, appUserId: 8)]
        let mine = try task(1, due: nil, persons: [10])
        let unassigned = try task(2, due: nil)
        let theirs = try task(3, due: nil, persons: [11])
        let media = try task(4, due: nil, priority: "media")
        let done = try task(5, due: nil, done: true)
        let result = TaskDue.highPriorityForMe([mine, unassigned, theirs, media, done], roster: roster, currentUserId: 7)
        XCTAssertEqual(result.map(\.id), [1, 2])
    }

    func testGroupedByListSortsListsAndTasks() throws {
        let listJSON = { (id: Int, name: String) in """
            {"id":\(id),"task_list_id":\(id),"title":"\(name) tarea","completed_at":null,"order":1,"priority":"alta",
             "due_at":null,"task_list_name":"\(name)","task_list_color":"#000000"}
            """ }
        let fromList = try JSONDecoder().decode(TaskEntry.self, from: Data(listJSON(9, "Hogar").utf8))
        let groups = TaskDue.groupedByList([fromList, try task(4, due: nil)])
        XCTAssertEqual(groups.map(\.name), ["Hogar", "Tareas"])
    }

    /// AC2: sin tareas, el texto es «Sin tareas de prioridad alta» y no hay enlace; con tareas, enlace.
    func testHighPrioritySummaryWithAndWithoutTasks() {
        let none = TaskDue.highPrioritySummary(count: 0)
        XCTAssertEqual(none.text, "Sin tareas de prioridad alta")
        XCTAssertFalse(none.showsLink)
        let some = TaskDue.highPrioritySummary(count: 3)
        XCTAssertEqual(some.text, "3 de prioridad alta")
        XCTAssertTrue(some.showsLink)
    }

    /// R1-01/R1-02: listas con el mismo nombre se ordenan por id; un nombre vacío se muestra como «Tareas».
    func testGroupedByListTieBreaksAndFallbackName() throws {
        func listed(_ id: Int, _ name: String?) throws -> TaskEntry {
            let nameJSON = name.map { "\"\($0)\"" } ?? "null"
            return try JSONDecoder().decode(TaskEntry.self, from: Data("""
            {"id":\(id),"task_list_id":\(id),"title":"T\(id)","completed_at":null,"order":1,"priority":"alta",
             "due_at":null,"task_list_name":\(nameJSON),"task_list_color":"#000000"}
            """.utf8))
        }
        let groups = TaskDue.groupedByList([try listed(7, "Compra"), try listed(3, "Compra"), try listed(5, "")])
        XCTAssertEqual(groups.map(\.id), [3, 7, 5])
        XCTAssertEqual(groups.map(\.name), ["Compra", "Compra", "Tareas"])
    }
}
