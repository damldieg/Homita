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

    // MARK: - Selección por día (semana lun 2026-11-09 a dom 2026-11-15)

    private let vacations = #"{"id":900,"calendar_id":3,"title":"Vacaciones","date_at":"2026-11-10 09:00:00","end_date":"2026-11-20"}"#

    private func instant(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    private func dayDate(_ ymd: String, _ zone: TimeZone? = nil) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone ?? utc
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: ymd)!
    }

    private func simple(_ id: Int, _ dateAt: String, end: String? = nil) -> String {
        let endPart = end.map { #","end_date":"\#($0)""# } ?? ""
        return #"{"id":\#(id),"calendar_id":3,"title":"E\#(id)","date_at":"\#(dateAt)"\#(endPart)}"#
    }

    private func makeStore(json: [String], nowAt: String = "2026-11-12T12:00:00Z", zone: TimeZone? = nil) async -> CalendarAgendaStore {
        let body = "[" + json.joined(separator: ",") + "]"
        StubURLProtocol.reset { _ in StubURLProtocol.Stub(json: body) }
        let instantNow = instant(nowAt)
        let store = CalendarAgendaStore(
            repo: EventRepository(client: makeTestClient()),
            grid: CalendarGrid(timeZone: zone ?? utc),
            now: { instantNow }
        )
        await store.load()
        return store
    }

    private func ids(_ events: [EventEntry]) -> [Int] { events.map(\.id) }

    func testEventsOnDayAreOnlyThoseStartingThatDayOrderedByTime() async {
        let store = await makeStore(json: [
            simple(3, "2026-11-12 23:59:59"), simple(1, "2026-11-12 00:00:00"),
            simple(2, "2026-11-12 10:00:00"), simple(4, "2026-11-13 00:00:00"), simple(5, "2026-11-11 08:00:00"),
        ])
        XCTAssertEqual(ids(store.listEvents(on: dayDate("2026-11-12"))), [1, 2, 3])
    }

    func testOngoingOnStartDayMiddleAndEndDay() async {
        let store = await makeStore(json: [vacations])
        for day in ["2026-11-10", "2026-11-15", "2026-11-20"] {
            XCTAssertEqual(ids(store.ongoing(on: dayDate(day))), [900], day)
        }
    }

    func testOngoingExcludesDayBeforeStartAndDayAfterEnd() async {
        let store = await makeStore(json: [vacations])
        XCTAssertTrue(store.ongoing(on: dayDate("2026-11-09")).isEmpty)
        XCTAssertTrue(store.ongoing(on: dayDate("2026-11-21")).isEmpty)
    }

    func testOngoingEventAppearsInOngoingNotInDayList() async {
        let store = await makeStore(json: [vacations, simple(1, "2026-11-10 12:00:00")])
        let day = dayDate("2026-11-10")
        XCTAssertEqual(ids(store.ongoing(on: day)), [900])
        XCTAssertEqual(ids(store.listEvents(on: day)), [1])
        XCTAssertEqual(ids(store.dayEvents(on: day)), [900, 1])
    }

    func testMultiDayStartedBeforeVisibleWeekShowsOngoing() async {
        let store = await makeStore(json: [vacations], nowAt: "2026-11-18T12:00:00Z")
        let day = dayDate("2026-11-17")
        XCTAssertTrue(store.events(on: day).isEmpty)
        XCTAssertEqual(ids(store.ongoing(on: day)), [900])
    }

    func testMoveAndSelectChangeOngoingByDay() async {
        let store = await makeStore(json: [vacations])
        await store.select(dayDate("2026-11-21"))
        XCTAssertTrue(store.ongoing(on: store.anchor).isEmpty)
        await store.select(dayDate("2026-11-20"))
        XCTAssertEqual(ids(store.ongoing(on: store.anchor)), [900])
        await store.move(1)
        XCTAssertTrue(store.ongoing(on: store.anchor).isEmpty)
        await store.move(-1)
        XCTAssertEqual(ids(store.ongoing(on: store.anchor)), [900])
    }

    func testEndEqualToStartDayIsNotOngoing() async {
        let store = await makeStore(json: [simple(1, "2026-11-12 10:00:00", end: "2026-11-12")])
        let day = dayDate("2026-11-12")
        XCTAssertTrue(store.ongoing(on: day).isEmpty)
        XCTAssertEqual(ids(store.listEvents(on: day)), [1])
    }

    func testMalformedOrNilEndDateIsNotOngoing() async {
        let store = await makeStore(json: [
            simple(1, "2026-11-10 10:00:00"),
            simple(2, "2026-11-10 10:00:00", end: ""),
            simple(3, "2026-11-10 10:00:00", end: "2026-13-40"),
        ])
        XCTAssertTrue(store.ongoing(on: dayDate("2026-11-12")).isEmpty)
        XCTAssertTrue(store.ongoing(on: dayDate("2026-11-10")).isEmpty)
    }

    func testMidnightBoundaryInDeviceTimeZone() async {
        let madrid = TimeZone(identifier: "Europe/Madrid")!
        let json = [vacations, simple(7, "2026-11-21 00:00:00")]
        let store = await makeStore(json: json, nowAt: "2026-11-20T23:30:00Z", zone: madrid)
        XCTAssertEqual(store.grid.calendar.component(.day, from: store.anchor), 21)
        XCTAssertTrue(store.ongoing(on: store.anchor).isEmpty)
        XCTAssertEqual(ids(store.listEvents(on: store.anchor)), [7])
        XCTAssertEqual(ids(store.ongoing(on: dayDate("2026-11-20", madrid))), [900])
        XCTAssertTrue(store.listEvents(on: dayDate("2026-11-20", madrid)).isEmpty)

        let utcStore = await makeStore(json: json, nowAt: "2026-11-20T23:30:00Z")
        XCTAssertEqual(utcStore.grid.calendar.component(.day, from: utcStore.anchor), 20)
        XCTAssertEqual(ids(utcStore.ongoing(on: utcStore.anchor)), [900])
    }

    func testEmptyDayHasNoEventsAndNoOngoing() async {
        let store = await makeStore(json: [])
        let day = dayDate("2026-11-12")
        XCTAssertTrue(store.listEvents(on: day).isEmpty)
        XCTAssertTrue(store.ongoing(on: day).isEmpty)
        XCTAssertTrue(store.dayEvents(on: day).isEmpty)
    }

    func testWeekBoundaryDaysQueryRangeCoversMondayToSunday() async throws {
        _ = await makeStore(json: [])
        let request = try XCTUnwrap(StubURLProtocol.requests.last)
        let monday = dayDate("2026-11-09")
        let sunday = dayDate("2026-11-15")
        XCTAssertEqual(query(request, "start_date"), LocalClock.epochString(for: monday, timeZone: utc))
        let sundayEnd = sunday.addingTimeInterval(86_399)
        XCTAssertEqual(query(request, "end_date"), LocalClock.epochString(for: sundayEnd, timeZone: utc))
    }
}
