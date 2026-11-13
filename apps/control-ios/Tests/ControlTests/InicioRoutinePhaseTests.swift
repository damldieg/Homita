import XCTest
@testable import ControlKit

/// Estados de «Rutinas de hoy» en Inicio (E1-04): finalizada, en curso, aviso y más tarde.
/// Hora fija 19:30 UTC; ventana de 60 min desde el inicio.
final class InicioRoutinePhaseTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!

    private final class ClockBox: @unchecked Sendable {
        var now: Date
        let timeZone: TimeZone
        init(now: Date, timeZone: TimeZone) { self.now = now; self.timeZone = timeZone }
    }

    private func routine(_ id: Int, time: String) throws -> RoutineEntry {
        let json = #"{"id":\#(id),"calendar_id":3,"title":"R\#(id)","time":"\#(time)","start_date":"2026-11-02"}"#
        return try JSONDecoder().decode(RoutineEntry.self, from: Data(json.utf8))
    }

    private func makeStore(box: ClockBox) -> InicioStore {
        StubURLProtocol.reset { _ in .init(json: "[]") }
        let client = makeTestClient()
        return InicioStore(
            events: EventRepository(client: client), tasks: TaskRepository(client: client),
            routines: RoutineRepository(client: client), taskLists: TaskListRepository(client: client),
            clock: { LocalClock(now: box.now, timeZone: box.timeZone) }
        )
    }

    func testFinishedInProgressSoonAndLaterAt1930() throws {
        let box = ClockBox(now: PHPDateTime.parse("2026-11-09 19:30:00", timeZone: utc)!, timeZone: utc)
        let store = makeStore(box: box)
        let finished = try routine(1, time: "08:00")   // inició hace más de 60 min
        let inProgress = try routine(2, time: "19:00")  // inició hace 30 min: quedan 30 min
        let soon = try routine(3, time: "20:00")        // empieza en 30 min
        let later = try routine(4, time: "22:00")       // empieza en 2 h 30 min

        XCTAssertEqual(store.phase(of: finished), .done)
        XCTAssertEqual(store.phase(of: inProgress), .now)
        XCTAssertEqual(store.phase(of: soon), .soon)
        XCTAssertEqual(store.phase(of: later), .later)

        XCTAssertEqual(store.minutesLeftInWindow(of: inProgress), 30)
        XCTAssertEqual(store.minutesUntilStart(of: soon), 30)
        XCTAssertEqual(store.minutesUntilStart(of: later), 150)
        XCTAssertNil(store.minutesLeftInWindow(of: finished))
        XCTAssertNil(store.minutesLeftInWindow(of: soon))
    }

    func testBarFractionsForSoonAndInProgress() throws {
        let box = ClockBox(now: PHPDateTime.parse("2026-11-09 19:30:00", timeZone: utc)!, timeZone: utc)
        let store = makeStore(box: box)
        let inProgress = try routine(2, time: "19:00")
        let soon = try routine(3, time: "20:00")
        XCTAssertEqual(store.windowFraction(of: inProgress) ?? -1, 0.5, accuracy: 0.001)
        XCTAssertEqual(store.windowFraction(of: soon) ?? -1, 0.5, accuracy: 0.001)
        XCTAssertNil(store.windowFraction(of: try routine(4, time: "22:00")))
    }

    func testRoutineWithoutTimeIsLater() throws {
        let box = ClockBox(now: PHPDateTime.parse("2026-11-09 19:30:00", timeZone: utc)!, timeZone: utc)
        let store = makeStore(box: box)
        XCTAssertEqual(store.phase(of: try routine(5, time: "")), .later)
    }
}
