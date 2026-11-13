import XCTest
import HomitaShared
@testable import ControlKit

final class NotificationPlannerTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!
    private lazy var now = PHPDateTime.parse("2026-11-09 10:00:00", timeZone: utc)!

    private func event(_ id: Int, at dateAt: String, alarm: Int?, routineId: Int? = nil) throws -> EventEntry {
        let alarmJSON = alarm.map(String.init) ?? "null"
        let routineJSON = routineId.map(String.init) ?? "null"
        let json = """
        {"id":\(id),"calendar_id":1,"title":"Cumple","date_at":"\(dateAt)","routine_id":\(routineJSON),
         "calendar_name":"Familia","alarm":\(alarmJSON)}
        """
        return try JSONDecoder().decode(EventEntry.self, from: Data(json.utf8))
    }

    private func routine(
        _ id: Int, time: String = "08:00:00", alarm: Int?, active: Int = 1, personIds: [Int]? = nil
    ) throws -> RoutineEntry {
        let alarmJSON = alarm.map(String.init) ?? "null"
        let personsJSON = personIds.map { ids in
            ",\"persons\":[" + ids.map { "{\"id\":\($0),\"user_id\":1,\"name\":\"P\($0)\",\"color\":\"#000000\"}" }.joined(separator: ",") + "]"
        } ?? ""
        let json = """
        {"id":\(id),"calendar_id":1,"title":"Desayuno","days":null,"time":"\(time)","start_date":"2026-11-01",
         "end_date":null,"active":\(active),"frequency":"daily","interval":1,"alarm":\(alarmJSON)\(personsJSON)}
        """
        return try JSONDecoder().decode(RoutineEntry.self, from: Data(json.utf8))
    }

    private func task(_ id: Int, title: String, done: Bool = false) throws -> TaskEntry {
        let completed = done ? "\"2026-11-09 09:00:00\"" : "null"
        let json = """
        {"id":\(id),"task_list_id":1,"title":"\(title)","completed_at":\(completed),"order":\(id)}
        """
        return try JSONDecoder().decode(TaskEntry.self, from: Data(json.utf8))
    }

    private func plan(
        events: [EventEntry] = [], routines: [RoutineEntry] = [], tasks: [TaskEntry] = [],
        prefs: NotificationPreferences = NotificationPreferences()
    ) -> [PlannedNotification] {
        NotificationPlanner.plan(
            events: events, routines: routines, pendingTasks: tasks, preferences: prefs, now: now, timeZone: utc
        )
    }

    func testRoutineAlertsOnlyForAssignedPerson() throws {
        let routines = [
            try routine(1, alarm: 0, personIds: [7]),
            try routine(2, alarm: 0, personIds: [8]),
            try routine(3, alarm: 0),
        ]
        let mine = NotificationPlanner.plan(
            events: [], routines: routines, pendingTasks: [], preferences: NotificationPreferences(),
            now: now, timeZone: utc, myPersonIds: [7]
        )
        XCTAssertFalse(mine.isEmpty)
        XCTAssertTrue(mine.allSatisfy { $0.id.hasPrefix("homita.routine.1.") })
        let unlinked = NotificationPlanner.plan(
            events: [], routines: routines, pendingTasks: [], preferences: NotificationPreferences(),
            now: now, timeZone: utc, myPersonIds: []
        )
        XCTAssertTrue(unlinked.isEmpty)
    }

    func testEventFiresAlarmMinutesBeforeStart() throws {
        let planned = plan(events: [try event(7, at: "2026-11-09 18:30:00", alarm: 15)])
        XCTAssertEqual(planned.count, 1)
        let item = try XCTUnwrap(planned.first)
        XCTAssertEqual(item.fireDate, PHPDateTime.parse("2026-11-09 18:15:00", timeZone: utc))
        XCTAssertEqual(item.title, "Cumple")
        XCTAssertEqual(item.body, "Empieza en 15 min · 18:30 · Familia")
        XCTAssertEqual(item.link, .calendario)
        XCTAssertEqual(item.kind, .event)
    }

    func testEventWithoutAlarmPastFireOrRoutineSessionIsSkipped() throws {
        let planned = plan(events: [
            try event(1, at: "2026-11-09 18:30:00", alarm: nil),
            try event(2, at: "2026-11-09 10:05:00", alarm: 30), // el aviso ya pasó
            try event(3, at: "2026-11-09 18:30:00", alarm: 10, routineId: 5),
        ])
        XCTAssertTrue(planned.isEmpty)
    }

    func testAlarmZeroSaysStartsNow() throws {
        let item = try XCTUnwrap(plan(events: [try event(1, at: "2026-11-09 12:00:00", alarm: 0)]).first)
        XCTAssertEqual(item.body, "Empieza ahora · 12:00 · Familia")
        XCTAssertEqual(item.fireDate, PHPDateTime.parse("2026-11-09 12:00:00", timeZone: utc))
    }

    func testDailyRoutineSchedulesNextSixDaysSkippingTodayPast() throws {
        // Hoy 08:00 ya pasó (son las 10:00): quedan los 6 días siguientes.
        let planned = plan(routines: [try routine(4, alarm: 0)])
        XCTAssertEqual(planned.count, 6)
        XCTAssertEqual(planned.first?.fireDate, PHPDateTime.parse("2026-11-10 08:00:00", timeZone: utc))
        XCTAssertEqual(planned.first?.id, "homita.routine.4.20261110")
        XCTAssertEqual(planned.first?.link, .rutinas)
    }

    func testRoutineLeadSubtractsAlarm() throws {
        let planned = plan(routines: [try routine(4, time: "20:00:00", alarm: 30)])
        XCTAssertEqual(planned.first?.fireDate, PHPDateTime.parse("2026-11-09 19:30:00", timeZone: utc))
        XCTAssertEqual(planned.first?.body, "Empieza en 30 min · 20:00")
    }

    func testRoutineWithoutAlarmOrInactiveIsSkipped() throws {
        XCTAssertTrue(plan(routines: [try routine(1, alarm: nil), try routine(2, alarm: 5, active: 0)]).isEmpty)
    }

    func testTogglesOffProduceNothing() throws {
        let prefs = NotificationPreferences(eventReminders: false, routineReminders: false, taskDigest: false)
        let planned = plan(
            events: [try event(1, at: "2026-11-09 18:30:00", alarm: 15)],
            routines: [try routine(4, alarm: 0)], tasks: [try task(1, title: "Pan")], prefs: prefs
        )
        XCTAssertTrue(planned.isEmpty)
        XCTAssertFalse(prefs.anyReminder)
    }

    func testEachToggleOnlyAffectsItsKind() throws {
        let events = [try event(1, at: "2026-11-09 18:30:00", alarm: 15)]
        let routines = [try routine(4, alarm: 0)]
        let onlyEvents = plan(events: events, routines: routines,
                              prefs: NotificationPreferences(eventReminders: true, routineReminders: false))
        XCTAssertEqual(Set(onlyEvents.map(\.kind)), [.event])
        let onlyRoutines = plan(events: events, routines: routines,
                                prefs: NotificationPreferences(eventReminders: false, routineReminders: true))
        XCTAssertEqual(Set(onlyRoutines.map(\.kind)), [.routine])
    }

    func testDigestUsesConfiguredTimeAndCountsOnlyFirst() throws {
        let tasks = [try task(1, title: "Pan"), try task(2, title: "Leche"), try task(3, title: "Hecha", done: true)]
        let prefs = NotificationPreferences(eventReminders: false, routineReminders: false, taskDigest: true,
                                            taskDigestHour: 9, taskDigestMinute: 30)
        let planned = plan(tasks: tasks, prefs: prefs)
        XCTAssertEqual(planned.count, 6) // hoy 09:30 ya pasó
        XCTAssertEqual(planned.first?.fireDate, PHPDateTime.parse("2026-11-10 09:30:00", timeZone: utc))
        XCTAssertEqual(planned.first?.body, "Tienes 2 tareas pendientes: Pan, Leche")
        XCTAssertEqual(planned.last?.body, "Revisa tus tareas pendientes")
        XCTAssertEqual(planned.first?.link, .tareas)
    }

    func testDigestSkippedWithoutPendingTasks() throws {
        let prefs = NotificationPreferences(eventReminders: false, routineReminders: false, taskDigest: true)
        XCTAssertTrue(plan(tasks: [try task(1, title: "Hecha", done: true)], prefs: prefs).isEmpty)
    }

    func testCapsPendingAndKeepsEarliest() throws {
        var events: [EventEntry] = []
        for index in 0..<100 {
            let minute = String(format: "%02d", index % 60)
            let hour = String(format: "%02d", 11 + index / 60)
            events.append(try event(index + 1, at: "2026-11-09 \(hour):\(minute):00", alarm: 0))
        }
        let planned = plan(events: events)
        XCTAssertEqual(planned.count, NotificationPlanner.maxPending)
        XCTAssertEqual(planned, planned.sorted { $0.fireDate < $1.fireDate })
    }

    func testLeadText() {
        XCTAssertEqual(NotificationPlanner.leadText(0), "Empieza ahora")
        XCTAssertEqual(NotificationPlanner.leadText(5), "Empieza en 5 min")
        XCTAssertEqual(NotificationPlanner.leadText(60), "Empieza en 1 h")
        XCTAssertEqual(NotificationPlanner.leadText(90), "Empieza en 1 h 30 min")
        XCTAssertEqual(NotificationPlanner.leadText(1440), "Empieza en 1 día")
        XCTAssertEqual(NotificationPlanner.leadText(2880), "Empieza en 2 días")
    }
}
