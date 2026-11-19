import XCTest
@testable import ControlKit

/// D-020 / CA-9 y CA-11: «En curso» sale de Próximos y Pasados; la paginación usa el count bruto.
@MainActor
final class EventOngoingStoreTests: XCTestCase {
    private let vacation = #"{"id":900,"calendar_id":3,"title":"Vacaciones","date_at":"2026-11-10 09:00:00","end_date":"2026-11-20"}"#

    private func clock(_ day: String) -> LocalClock {
        let date = ISO8601DateFormatter().date(from: "\(day)T12:00:00Z")!
        return LocalClock(now: date, timeZone: TimeZone(identifier: "UTC")!)
    }

    private func single(_ id: Int, _ dateAt: String = "2026-01-01 10:00:00") -> String {
        #"{"id":\#(id),"calendar_id":3,"title":"E\#(id)","date_at":"\#(dateAt)"}"#
    }

    private func stub(upcoming: [String], pastFirst: [String], pastCount: Int = 50) {
        StubURLProtocol.reset { request in
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            func value(_ name: String) -> String? { query.first { $0.name == name }?.value }
            if value("start_date") != nil { return StubURLProtocol.Stub(json: "[" + upcoming.joined(separator: ",") + "]") }
            if value("offset") == "50" { return StubURLProtocol.Stub(json: "[" + self.single(777) + "]") }
            let filler = (0..<(pastCount - pastFirst.count)).map { self.single($0 + 1) }
            return StubURLProtocol.Stub(json: "[" + (pastFirst + filler).joined(separator: ",") + "]")
        }
    }

    private func store(_ day: String) -> EventStore {
        EventStore(repo: EventRepository(client: makeTestClient()), clock: { self.clock(day) })
    }

    func testOngoingOnlyInOngoingOnBoundaryDays() async {
        for day in ["2026-11-10", "2026-11-15", "2026-11-20"] {
            stub(upcoming: [vacation], pastFirst: [vacation])
            let s = store(day)
            await s.load()
            XCTAssertEqual(s.ongoing.map(\.id), [900], day)
            XCTAssertFalse(s.upcoming.contains { $0.id == 900 }, day)
            XCTAssertFalse(s.past.contains { $0.id == 900 }, day)
        }
    }

    func testBeforeStartOnlyUpcoming() async {
        stub(upcoming: [vacation], pastFirst: [], pastCount: 0)
        let s = store("2026-11-09")
        await s.load()
        XCTAssertTrue(s.ongoing.isEmpty)
        XCTAssertEqual(s.upcoming.map(\.id), [900])
    }

    func testAfterEndOnlyPast() async {
        stub(upcoming: [], pastFirst: [vacation], pastCount: 1)
        let s = store("2026-11-21")
        await s.load()
        XCTAssertTrue(s.ongoing.isEmpty)
        XCTAssertTrue(s.upcoming.isEmpty)
        XCTAssertEqual(s.past.map(\.id), [900])
    }

    func testFullPastPageWithOngoingKeepsRawCountForPaging() async {
        stub(upcoming: [vacation], pastFirst: [vacation])
        let s = store("2026-11-15")
        await s.load()
        XCTAssertEqual(s.past.count, 49)
        XCTAssertTrue(s.hasMorePast, "la página bruta venía llena (50)")
        await s.loadMorePast()
        let offsets = StubURLProtocol.requests.compactMap { r -> String? in
            URLComponents(url: r.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "offset" }?.value
        }
        XCTAssertEqual(offsets.last, "50", "el offset avanza con el count bruto, no con el filtrado")
        XCTAssertEqual(s.past.count, 50)
        XCTAssertFalse(s.hasMorePast)
    }

    func testEventsWithoutEndKeepListsUnchanged() async {
        stub(upcoming: [single(1, "2026-11-16 10:00:00"), single(2, "2026-11-17 10:00:00")], pastFirst: [], pastCount: 3)
        let s = store("2026-11-15")
        await s.load()
        XCTAssertTrue(s.ongoing.isEmpty)
        XCTAssertEqual(s.upcoming.map(\.id), [1, 2])
        XCTAssertEqual(s.past.count, 3)
    }
}
