import XCTest
@testable import ControlKit

/// `RoutineStore.routineSections` / `status(for:in:)` y marcas diarias de `InicioStore` (lógica pura, sin UI).
final class RoutineSectionsTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!

    private final class ClockBox: @unchecked Sendable {
        var now: Date
        let timeZone: TimeZone
        init(now: Date, timeZone: TimeZone) { self.now = now; self.timeZone = timeZone }
    }

    private func routineJSON(_ id: Int, time: String) -> String {
        #"{"id":\#(id),"calendar_id":3,"title":"R\#(id)","time":"\#(time)","start_date":"2026-11-02"}"#
    }

    private func sessionJSON(_ id: Int, routine: Int, at: String) -> String {
        #"{"id":\#(id),"calendar_id":3,"title":"R\#(routine)","date_at":"\#(at)","routine_id":\#(routine)}"#
    }

    private func makeStore(now: String, zone: TimeZone, routines: [String], sessions: [String]) async -> RoutineStore {
        StubURLProtocol.reset { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("/routine") { return .init(json: "[\(routines.joined(separator: ","))]") }
            if path.hasSuffix("/event") { return .init(json: "[\(sessions.joined(separator: ","))]") }
            return .init(status: 500, json: "Not Found")
        }
        let client = makeTestClient()
        let date = PHPDateTime.parse(now, timeZone: zone)!
        let store = RoutineStore(
            repo: RoutineRepository(client: client), events: EventRepository(client: client),
            clock: { LocalClock(now: date, timeZone: zone) }
        )
        await store.load()
        return store
    }

    func testSectionsGroupTodayTomorrowNextWeekAndSortNoTimeLast() async {
        let store = await makeStore(
            now: "2026-11-09 10:30:00", zone: utc,
            routines: [
                routineJSON(1, time: ""), routineJSON(2, time: "11:00"), routineJSON(3, time: "08:00"),
                routineJSON(4, time: "09:00")
            ],
            sessions: [
                sessionJSON(1, routine: 1, at: "2026-11-09 10:45:00"),   // sin hora, hoy
                sessionJSON(2, routine: 2, at: "2026-11-09 11:00:00"),   // hora fija, hoy
                sessionJSON(3, routine: 3, at: "2026-11-10 08:00:00"),   // mañana
                sessionJSON(4, routine: 4, at: "2026-11-13 09:00:00")    // posterior
            ]
        )
        let sections = store.routineSections
        XCTAssertEqual(sections.map(\.group), [.today, .tomorrow, .nextWeek])
        // Hora fija antes que sin hora aunque la sin hora sea más próxima.
        XCTAssertEqual(sections[0].routines.map(\.id), [2, 1])
        XCTAssertEqual(sections[1].routines.map(\.id), [3])
        XCTAssertEqual(sections[2].routines.map(\.id), [4])
    }

    func testTomorrowUsesCalendarAcrossDST() async {
        let madrid = TimeZone(identifier: "Europe/Madrid")!
        // 2026-03-29 el día dura 23 h: now + 86400 caería en el 30.
        let store = await makeStore(
            now: "2026-03-28 23:30:00", zone: madrid,
            routines: [routineJSON(1, time: "08:00")],
            sessions: [sessionJSON(1, routine: 1, at: "2026-03-29 08:00:00")]
        )
        XCTAssertEqual(store.routineSections.map(\.group), [.tomorrow])
    }

    func testStatusInProgressExpiredAndNormal() async {
        let store = await makeStore(
            now: "2026-11-09 10:30:00", zone: utc,
            routines: [routineJSON(1, time: "10:00"), routineJSON(2, time: "08:00"), routineJSON(3, time: "08:00"),
                       routineJSON(4, time: "")],
            sessions: [
                sessionJSON(1, routine: 1, at: "2026-11-09 10:00:00"),
                sessionJSON(2, routine: 2, at: "2026-11-09 08:00:00"),
                sessionJSON(3, routine: 3, at: "2026-11-09 08:00:00"),
                sessionJSON(4, routine: 3, at: "2026-11-10 08:00:00")
            ]
        )
        let byId = Dictionary(uniqueKeysWithValues: store.routines.map { ($0.id, $0) })
        XCTAssertEqual(store.status(for: byId[1]!), .inProgress)
        XCTAssertEqual(store.status(for: byId[2]!), .expired)
        // Con próxima ocurrencia mañana: normal en general, caducada dentro de "Hoy".
        XCTAssertEqual(store.status(for: byId[3]!), .normal)
        XCTAssertEqual(store.status(for: byId[3]!, in: .today), .expired)
        XCTAssertEqual(store.status(for: byId[3]!, in: .tomorrow), .normal)
        XCTAssertEqual(store.status(for: byId[4]!, in: .today), .normal)
    }

    /// D-1: sin marca manual. «Hecha» es solo el horario (caducada); una rutina en aviso o en curso no cuenta.
    func testInicioDoneIsOnlyTheClock() async throws {
        StubURLProtocol.reset { _ in .init(json: "[]") }
        let client = makeTestClient()
        let box = ClockBox(now: PHPDateTime.parse("2026-11-09 19:30:00", timeZone: utc)!, timeZone: utc)
        let store = InicioStore(
            events: EventRepository(client: client), tasks: TaskRepository(client: client),
            routines: RoutineRepository(client: client), taskLists: TaskListRepository(client: client),
            clock: { LocalClock(now: box.now, timeZone: box.timeZone) }
        )
        let decoder = JSONDecoder()
        let early = try decoder.decode(RoutineEntry.self, from: Data(routineJSON(1, time: "08:00").utf8))
        let soon = try decoder.decode(RoutineEntry.self, from: Data(routineJSON(2, time: "20:00").utf8))

        XCTAssertEqual(store.status(for: early), .expired)
        XCTAssertEqual(store.status(for: soon), .normal)
        XCTAssertTrue(store.isSoon(soon), "a 30 min del inicio está en aviso")
        XCTAssertFalse(store.isSoon(early))
        XCTAssertEqual(store.minutesUntilStart(of: soon), 30)
    }

    private func ruleJSON(_ id: Int, time: String, frequency: String, days: String = "[]", active: Bool = true) -> String {
        #"{"id":\#(id),"calendar_id":3,"title":"R\#(id)","time":"\#(time)","start_date":"2026-11-02","frequency":"\#(frequency)","interval":1,"days":\#(days),"active":\#(active)}"#
    }

    /// CAL-02: «Hoy» lista todas las rutinas del día, no solo las que tienen una sesión futura.
    func testTodayKeepsStartedAndFinishedRoutinesEvenIfNextIsTomorrow() async {
        let store = await makeStore(
            now: "2026-11-09 10:30:00", zone: utc,
            routines: [routineJSON(1, time: "10:00"), routineJSON(2, time: "08:00"), routineJSON(3, time: "12:00")],
            sessions: [
                sessionJSON(1, routine: 1, at: "2026-11-09 10:00:00"), sessionJSON(2, routine: 1, at: "2026-11-10 10:00:00"),
                sessionJSON(3, routine: 2, at: "2026-11-09 08:00:00"), sessionJSON(4, routine: 2, at: "2026-11-10 08:00:00"),
                sessionJSON(5, routine: 3, at: "2026-11-09 12:00:00")
            ]
        )
        let sections = store.routineSections
        XCTAssertEqual(sections.map(\.group), [.today, .tomorrow])
        // En curso y por empezar por hora; la caducada al final.
        XCTAssertEqual(sections[0].routines.map(\.id), [1, 3, 2])
        XCTAssertEqual(sections[1].routines.map(\.id), [2, 1])
        let byId = Dictionary(uniqueKeysWithValues: store.routines.map { ($0.id, $0) })
        XCTAssertEqual(store.status(for: byId[1]!, in: .today), .inProgress)
        XCTAssertEqual(store.status(for: byId[2]!, in: .today), .expired)
    }

    /// Sin sesiones generadas, la regla decide qué toca hoy; las pausadas también salen en «Hoy».
    func testTodayUsesRuleWhenNoSessionsAndIncludesPaused() async {
        let store = await makeStore(
            now: "2026-11-09 10:30:00", zone: utc,   // lunes
            routines: [
                ruleJSON(1, time: "10:00", frequency: "daily"),
                ruleJSON(2, time: "08:00", frequency: "daily", active: false),
                ruleJSON(3, time: "09:00", frequency: "weekly", days: "[2]"),   // martes
                ruleJSON(4, time: "09:00", frequency: "weekly", days: "[3]")    // miércoles
            ],
            sessions: []
        )
        let sections = store.routineSections
        XCTAssertEqual(sections.map(\.group), [.today, .tomorrow, .nextWeek])
        XCTAssertEqual(sections[0].routines.map(\.id), [2, 1], "la pausada también sale; por hora")
        XCTAssertEqual(Set(sections[1].routines.map(\.id)), [1, 3], "mañana por regla, solo activas")
        XCTAssertEqual(sections[2].routines.map(\.id), [4])
        let byId = Dictionary(uniqueKeysWithValues: store.routines.map { ($0.id, $0) })
        XCTAssertEqual(store.status(for: byId[1]!, in: .today), .inProgress, "la regla da el inicio de hoy")
        XCTAssertEqual(store.status(for: byId[2]!, in: .today), .normal, "pausada: no corre, no caduca")
    }

    func testRoutineTodayOnlyIsNotRepeatedInNextWeek() async {
        let store = await makeStore(
            now: "2026-11-09 18:00:00", zone: utc,
            routines: [routineJSON(1, time: "08:00")],
            sessions: [sessionJSON(1, routine: 1, at: "2026-11-09 08:00:00")]
        )
        XCTAssertEqual(store.routineSections.map(\.group), [.today], "sin próxima sesión, caducada y solo en Hoy")
    }
}
