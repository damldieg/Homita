import XCTest
import UserNotifications
import HomitaShared
@testable import ControlKit

private final class FakeCenter: NotificationCenterProtocol {
    var requests: [UNNotificationRequest] = []
    var deliveredCleared = false

    func add(_ request: UNNotificationRequest) async throws {
        requests.removeAll { $0.identifier == request.identifier }
        requests.append(request)
    }
    func pendingNotificationRequests() async -> [UNNotificationRequest] { requests }
    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        requests.removeAll { identifiers.contains($0.identifier) }
    }
    func removeAllDeliveredNotifications() { deliveredCleared = true }

    var daily: [UNNotificationRequest] { requests.filter { $0.identifier == DailySummaryPlanner.identifier } }
}

final class NotificationSchedulerTests: XCTestCase {
    private let summary = DailySummary(title: "Tu resumen de hoy", body: "1 tarea: T1", eventCount: 0, taskCount: 1, link: .tareas)

    private func trigger(_ request: UNNotificationRequest) throws -> UNCalendarNotificationTrigger {
        try XCTUnwrap(request.trigger as? UNCalendarNotificationTrigger)
    }

    func testActivateSchedulesOneRepeatingTrigger() async throws {
        let center = FakeCenter()
        await NotificationScheduler(center: center).scheduleDailySummary(summary, hour: 8, minute: 0)
        XCTAssertEqual(center.daily.count, 1)
        let trigger = try trigger(center.daily[0])
        XCTAssertTrue(trigger.repeats)
        XCTAssertEqual(trigger.dateComponents.hour, 8)
        XCTAssertEqual(trigger.dateComponents.minute, 0)
    }

    func testChangingTimeLeavesOnlyTheNewOne() async throws {
        let center = FakeCenter()
        let scheduler = NotificationScheduler(center: center)
        await scheduler.scheduleDailySummary(summary, hour: 8, minute: 0)
        await scheduler.scheduleDailySummary(summary, hour: 20, minute: 15)
        XCTAssertEqual(center.daily.count, 1)
        let trigger = try trigger(center.daily[0])
        XCTAssertEqual(trigger.dateComponents.hour, 20)
        XCTAssertEqual(trigger.dateComponents.minute, 15)
    }

    func testRemoveLeavesNone() async {
        let center = FakeCenter()
        let scheduler = NotificationScheduler(center: center)
        await scheduler.scheduleDailySummary(summary, hour: 8, minute: 0)
        await scheduler.removeDailySummary()
        XCTAssertTrue(center.daily.isEmpty)
        await scheduler.removeDailySummary() // sin nada pendiente no falla
        XCTAssertTrue(center.requests.isEmpty)
    }

    func testReplaceAllClearsDailyAndRescheduleDoesNotDuplicate() async {
        let center = FakeCenter()
        let scheduler = NotificationScheduler(center: center)
        await scheduler.scheduleDailySummary(summary, hour: 8, minute: 0)
        await scheduler.replaceAll(with: [])
        XCTAssertTrue(center.daily.isEmpty)
        await scheduler.scheduleDailySummary(summary, hour: 8, minute: 0)
        await scheduler.replaceAll(with: [])
        await scheduler.scheduleDailySummary(summary, hour: 8, minute: 0)
        XCTAssertEqual(center.daily.count, 1)
    }

    func testTotalPendingStaysWithinLimitWithPlannerAtCap() async {
        let center = FakeCenter()
        let scheduler = NotificationScheduler(center: center)
        let fire = Date().addingTimeInterval(86_400)
        let planned = (0..<NotificationPlanner.maxPending).map {
            PlannedNotification(id: "homita.event.\($0)", kind: .event, title: "E", body: "b", fireDate: fire, link: .calendario)
        }
        await scheduler.replaceAll(with: planned)
        await scheduler.scheduleDailySummary(summary, hour: 8, minute: 0)
        XCTAssertEqual(center.requests.count, NotificationPlanner.maxPending + 1)
        XCTAssertLessThanOrEqual(center.requests.count, 61)
    }

    func testOldPreferencesJSONDecodesWithDefaults() throws {
        let json = #"{"eventReminders":false,"routineReminders":true,"taskDigest":true,"taskDigestHour":7,"taskDigestMinute":30,"widgets":false,"routineLiveActivity":true}"#
        let prefs = try JSONDecoder().decode(NotificationPreferences.self, from: Data(json.utf8))
        XCTAssertFalse(prefs.eventReminders)
        XCTAssertTrue(prefs.taskDigest)
        XCTAssertEqual(prefs.taskDigestHour, 7)
        XCTAssertEqual(prefs.taskDigestMinute, 30)
        XCTAssertFalse(prefs.widgets)
        XCTAssertFalse(prefs.dailySummary)
        XCTAssertEqual(prefs.dailySummaryHour, 8)
        XCTAssertEqual(prefs.dailySummaryMinute, 0)
        XCTAssertTrue(NotificationPreferences(eventReminders: false, routineReminders: false, dailySummary: true).anyReminder)
    }
}
