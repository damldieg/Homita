import XCTest
@testable import ControlKit

/// Agenda de eventos por día: pide la semana del día elegido con `routine=false` y solo recarga al cambiar de semana.
@MainActor
final class CalendarAgendaStoreTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!
    // Miércoles 2025-11-12 12:00 UTC.
    private let now = Date(timeIntervalSince1970: 1_762_948_800)

    private func makeStore() -> CalendarAgendaStore {
        StubURLProtocol.reset { _ in StubURLProtocol.Stub(json: "[]") }
        return CalendarAgendaStore(repo: EventRepository(client: makeTestClient()), grid: CalendarGrid(timeZone: utc), now: { self.now })
    }

    private func query(_ request: URLRequest, _ name: String) -> String? {
        URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value
    }

    func testLoadRequestsOnlyEventsOfTheVisibleWeek() async throws {
        let store = makeStore()
        await store.load()
        let request = try XCTUnwrap(StubURLProtocol.requests.last)
        XCTAssertEqual(query(request, "routine"), "false", "las sesiones de rutina no se mezclan con los eventos")
        XCTAssertEqual(store.visibleDays.count, 7)
        let days = store.visibleDays
        XCTAssertEqual(query(request, "start_date"), LocalClock.epochString(for: try XCTUnwrap(days.first), timeZone: utc))
    }

    func testMovingWithinTheSameWeekDoesNotReload() async {
        let store = makeStore()
        await store.load()
        let before = StubURLProtocol.requests.count
        await store.move(1) // jueves, misma semana
        XCTAssertEqual(StubURLProtocol.requests.count, before)
        XCTAssertEqual(store.grid.calendar.component(.day, from: store.anchor), 13)
    }

    func testMovingAcrossWeeksReloads() async {
        let store = makeStore()
        await store.load()
        let before = StubURLProtocol.requests.count
        await store.select(store.grid.shift(store.anchor, mode: .day, by: 7)) // semana siguiente
        XCTAssertEqual(StubURLProtocol.requests.count, before + 1)
    }

    func testGoToTodayReturnsAndIsTodayFlag() async {
        let store = makeStore()
        await store.load()
        XCTAssertTrue(store.isToday)
        await store.select(store.grid.shift(store.anchor, mode: .day, by: 30))
        XCTAssertFalse(store.isToday)
        await store.goToToday()
        XCTAssertTrue(store.isToday)
    }
}
