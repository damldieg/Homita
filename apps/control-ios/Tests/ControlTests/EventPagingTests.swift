import XCTest
@testable import ControlKit

/// I2: «Pasados» pide limit/offset del contrato y «Cargar más» trae la página siguiente.
@MainActor
final class EventPagingTests: XCTestCase {
    private final class Flag: @unchecked Sendable { var count = 0 }

    private func events(_ count: Int) -> String {
        let items = (0..<count).map {
            #"{"id":\#($0 + 1),"calendar_id":3,"title":"E\#($0)","date_at":"2026-01-01 10:00:00"}"#
        }
        return "[" + items.joined(separator: ",") + "]"
    }

    private func clock() -> LocalClock {
        LocalClock(now: Date(timeIntervalSince1970: 1_762_586_400), timeZone: TimeZone(identifier: "UTC")!)
    }

    /// Pasados: primera página llena (50); página con offset=50: 3 filas. Próximos: vacío.
    private func stubPages() {
        StubURLProtocol.reset { request in
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            func value(_ name: String) -> String? { query.first { $0.name == name }?.value }
            if value("start_date") != nil { return StubURLProtocol.Stub(json: "[]") }
            if value("offset") == "50" { return StubURLProtocol.Stub(json: self.events(3)) }
            return StubURLProtocol.Stub(json: self.events(50))
        }
    }

    private func pastRequests() -> [URLRequest] {
        StubURLProtocol.requests.filter { URLComponents(url: $0.url!, resolvingAgainstBaseURL: false)?.queryItems?.contains { $0.name == "end_date" } == true }
    }

    func testFirstPageRequestsLimitAndOffsetAndMarksMore() async {
        stubPages()
        let store = EventStore(repo: EventRepository(client: makeTestClient()), clock: { self.clock() })
        await store.load()
        XCTAssertEqual(store.past.count, 50)
        XCTAssertTrue(store.hasMorePast)
        let query = URLComponents(url: try! XCTUnwrap(pastRequests().last?.url), resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(query.first { $0.name == "limit" }?.value, "50")
        XCTAssertEqual(query.first { $0.name == "offset" }?.value, "0")
    }

    func testLoadMoreAppendsNextPageAndStopsWhenShort() async {
        stubPages()
        let store = EventStore(repo: EventRepository(client: makeTestClient()), clock: { self.clock() })
        await store.load()
        await store.loadMorePast()
        XCTAssertEqual(store.past.count, 53)
        XCTAssertFalse(store.hasMorePast, "una página corta indica que no hay más")
        let before = pastRequests().count
        await store.loadMorePast()
        XCTAssertEqual(pastRequests().count, before, "sin más páginas no hay petición")
    }
}
