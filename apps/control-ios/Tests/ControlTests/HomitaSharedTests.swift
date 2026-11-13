import XCTest
import HomitaShared
@testable import ControlKit

final class HomitaSharedTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!

    private func date(_ text: String) -> Date { PHPDateTime.parse(text, timeZone: utc)! }

    private func snapshot() -> HomitaSnapshot {
        HomitaSnapshot(
            generatedAt: date("2026-11-09 07:00:00"), dayStart: date("2026-11-09 00:00:00"), homeName: "Casa",
            routines: [
                .init(id: 1, title: "Desayuno", colorHex: "#0E9F6E", start: date("2026-11-09 08:00:00")),
                .init(id: 2, title: "Deberes", colorHex: "#6D28D9", start: date("2026-11-09 17:30:00")),
                .init(id: 3, title: "Baño", colorHex: "#0284C7", start: date("2026-11-09 20:00:00")),
                .init(id: 4, title: "Libre", colorHex: "#F59E0B", start: nil),
            ]
        )
    }

    // MARK: Deep links

    func testDeepLinkRoundTrip() {
        for link in HomitaDeepLink.allCases {
            XCTAssertEqual(HomitaDeepLink(url: link.url), link)
        }
        XCTAssertEqual(HomitaDeepLink.nuevaTarea.url.absoluteString, "homita://nueva-tarea")
    }

    func testDeepLinkRejectsForeignOrUnknown() {
        XCTAssertNil(HomitaDeepLink(string: "https://nueva-tarea"))
        XCTAssertNil(HomitaDeepLink(string: "homita://otra-cosa"))
        XCTAssertNil(HomitaDeepLink(string: ""))
    }

    func testDeepLinkCenterOpenAndConsume() {
        let center = DeepLinkCenter()
        XCTAssertTrue(center.open(url: HomitaDeepLink.rutinas.url))
        XCTAssertEqual(center.pending, .rutinas)
        center.consume(.tareas) // otro enlace: no consume
        XCTAssertEqual(center.pending, .rutinas)
        center.consume(.rutinas)
        XCTAssertNil(center.pending)
        XCTAssertFalse(center.open(url: URL(string: "https://example.com")!))
    }

    // MARK: Preferencias

    func testPreferencesDefaultsAndRoundTrip() throws {
        let suite = "homita-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = NotificationPreferencesStore(defaults: defaults)
        XCTAssertEqual(store.load(), NotificationPreferences())
        XCTAssertTrue(store.load().eventReminders && store.load().widgets && store.load().routineLiveActivity)
        XCTAssertFalse(store.load().taskDigest)
        var changed = store.load()
        changed.widgets = false
        changed.routineLiveActivity = false
        changed.taskDigest = true
        changed.taskDigestHour = 7
        changed.taskDigestMinute = 5
        store.save(changed)
        XCTAssertEqual(store.load(), changed)
        XCTAssertEqual(store.load().taskDigestTimeText, "07:05")
    }

    func testPreferencesClampDigestTime() {
        let prefs = NotificationPreferences(taskDigestHour: 99, taskDigestMinute: -4)
        XCTAssertEqual(prefs.taskDigestHour, 23)
        XCTAssertEqual(prefs.taskDigestMinute, 0)
    }

    // MARK: Snapshot

    func testSnapshotStoreRoundTripAndClear() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("snap-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SnapshotStore(directory: directory)
        XCTAssertNil(store.load())
        XCTAssertTrue(store.save(snapshot()))
        XCTAssertEqual(store.load(), snapshot())
        store.clear()
        XCTAssertNil(store.load())
    }

    func testSnapshotStoreWithoutContainerDoesNothing() {
        let store = SnapshotStore(directory: nil)
        XCTAssertFalse(store.save(snapshot()))
        XCTAssertNil(store.load())
    }

    func testRoutinePhases() {
        let routine = snapshot().routines[0] // 08:00
        XCTAssertEqual(routine.phase(at: date("2026-11-09 06:30:00")), .later)
        XCTAssertEqual(routine.phase(at: date("2026-11-09 07:00:00")), .soon)
        XCTAssertEqual(routine.phase(at: date("2026-11-09 08:00:00")), .now)
        XCTAssertEqual(routine.phase(at: date("2026-11-09 09:00:00")), .now)
        XCTAssertEqual(routine.phase(at: date("2026-11-09 09:00:01")), .done)
        XCTAssertEqual(snapshot().routines[3].phase(at: date("2026-11-09 12:00:00")), .anytime)
    }

    func testSharedWindowsMatchAppRoutineStatus() {
        XCTAssertEqual(HomitaShared.routineWindow, RoutineStatus.window)
        XCTAssertEqual(HomitaShared.routineSoonWindow, RoutineStatus.soonWindow)
    }

    func testFocusRoutineIsCurrentThenNext() {
        let snap = snapshot()
        XCTAssertEqual(snap.focusRoutine(at: date("2026-11-09 08:30:00"))?.id, 1)
        XCTAssertEqual(snap.focusRoutine(at: date("2026-11-09 12:00:00"))?.id, 2)
        XCTAssertEqual(snap.focusRoutine(at: date("2026-11-09 20:30:00"))?.id, 3)
        XCTAssertNil(snap.focusRoutine(at: date("2026-11-09 21:30:00")))
    }

    func testDoneCountAndBoundaries() {
        let snap = snapshot()
        XCTAssertEqual(snap.doneCount(at: date("2026-11-09 12:00:00")), 1)
        let boundaries = snap.boundaries(after: date("2026-11-09 17:00:00"))
        XCTAssertEqual(boundaries.first, date("2026-11-09 17:30:00"))
        XCTAssertEqual(boundaries, boundaries.sorted())
        XCTAssertTrue(boundaries.allSatisfy { $0 > date("2026-11-09 17:00:00") })
    }

    func testStaleWhenDayChanges() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        XCTAssertFalse(snapshot().isStale(at: date("2026-11-09 23:59:00"), calendar: calendar))
        XCTAssertTrue(snapshot().isStale(at: date("2026-11-10 00:01:00"), calendar: calendar))
    }

    func testSignedOutSnapshot() {
        XCTAssertFalse(HomitaSnapshot.signedOut().signedIn)
    }

    // MARK: Constructor del snapshot

    func testBuilderKeepsTodaysEventsRoutinesAndPendingTasks() throws {
        let now = date("2026-11-09 10:00:00")
        let events = try JSONDecoder().decode([EventEntry].self, from: Data("""
        [{"id":1,"calendar_id":1,"title":"Dentista","date_at":"2026-11-09 16:00:00","calendar_color":"#0284C7"},
         {"id":2,"calendar_id":1,"title":"Mañana","date_at":"2026-11-10 16:00:00"},
         {"id":3,"calendar_id":1,"title":"Sesión","date_at":"2026-11-09 18:00:00","routine_id":9}]
        """.utf8))
        let routines = try JSONDecoder().decode([RoutineEntry].self, from: Data("""
        [{"id":4,"calendar_id":1,"title":"Desayuno","days":null,"time":"08:00:00","start_date":"2026-11-01",
          "end_date":null,"active":1,"frequency":"daily","interval":1,"calendar_color":"#0E9F6E"},
         {"id":5,"calendar_id":1,"title":"Pausada","days":null,"time":"09:00:00","start_date":"2026-11-01",
          "end_date":null,"active":0,"frequency":"daily","interval":1}]
        """.utf8))
        let tasks = try JSONDecoder().decode([TaskEntry].self, from: Data("""
        [{"id":1,"task_list_id":1,"title":"Pan","completed_at":null,"order":1,"task_list_name":"Compra"},
         {"id":2,"task_list_id":1,"title":"Hecha","completed_at":"2026-11-09 08:00:00","order":2}]
        """.utf8))
        let snap = SnapshotBuilder.build(events: events, routines: routines, tasks: tasks, homeName: "Casa", now: now, timeZone: utc)
        XCTAssertEqual(snap.events.map(\.title), ["Dentista"])
        XCTAssertEqual(snap.routines.map(\.title), ["Desayuno"])
        XCTAssertEqual(snap.routines.first?.start, date("2026-11-09 08:00:00"))
        XCTAssertEqual(snap.pendingTaskCount, 1)
        XCTAssertEqual(snap.tasks.first?.listName, "Compra")
        XCTAssertEqual(snap.homeName, "Casa")
        XCTAssertTrue(snap.signedIn)
        XCTAssertEqual(snap.dayStart, date("2026-11-09 00:00:00"))
    }
}
