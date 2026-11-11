import XCTest
@testable import ControlKit

final class InicioStoreTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!

    private func makeStore(_ handler: @escaping (URLRequest) -> StubURLProtocol.Stub) -> InicioStore {
        StubURLProtocol.reset(handler)
        let client = makeTestClient()
        let now = PHPDateTime.parse("2026-11-09 10:00:00", timeZone: utc)!
        return InicioStore(
            events: EventRepository(client: client), tasks: TaskRepository(client: client),
            routines: RoutineRepository(client: client), taskLists: TaskListRepository(client: client),
            clock: { [utc] in LocalClock(now: now, timeZone: utc) }
        )
    }

    private func route(_ request: URLRequest) -> String {
        let path = request.url?.path ?? ""
        return path.range(of: "/functions/v1/api/").map { String(path[$0.upperBound...]) } ?? path
    }

    func testLoadUsesOnlyEventTaskRoutineWithDayWindow() async throws {
        let store = makeStore(ContractFixtures.response)
        await store.load()
        let requests = StubURLProtocol.requests
        XCTAssertEqual(Set(requests.map(route)), ["event", "task", "routine"])
        XCTAssertFalse(requests.contains { route($0).hasPrefix("home") })
        let eventRequest = try XCTUnwrap(requests.first { route($0) == "event" })
        let query = Dictionary(eventRequest.capturedQuery.map { ($0.0, $0.1 ?? "") }, uniquingKeysWith: { a, _ in a })
        XCTAssertEqual(query["start_date"]?.count, 10)
        XCTAssertEqual(query["end_date"]?.count, 10)
        XCTAssertEqual(Int(query["end_date"] ?? "")! - Int(query["start_date"] ?? "")!, 86_399)
        XCTAssertEqual(query["routine"], "false")
        XCTAssertEqual(query["timezone"], utc.identifier)
        XCTAssertEqual(store.eventsState, .loaded)
        XCTAssertEqual(store.tasksState, .loaded)
        XCTAssertEqual(store.routinesState, .loaded)
    }

    func testTaskFailureDoesNotEmptyOtherSections() async {
        let store = makeStore { request in
            switch self.route(request) {
            case "task":
                return StubURLProtocol.Stub(status: 500, json: #"{"error":"boom"}"#)
            case "event":
                return StubURLProtocol.Stub(json: "[\(ContractFixtures.event.replacingOccurrences(of: "2026-11-08", with: "2026-11-09"))]")
            case "routine":
                return StubURLProtocol.Stub(json: "[\(ContractFixtures.routine)]")
            default:
                return StubURLProtocol.Stub(status: 500)
            }
        }
        await store.load()
        XCTAssertEqual(store.eventsState, .loaded)
        XCTAssertEqual(store.routinesState, .loaded)
        if case .failed = store.tasksState {} else { XCTFail("tasksState debería ser .failed") }
        XCTAssertEqual(store.todayEvents.count, 1)
        XCTAssertEqual(store.routines.count, 1)
    }

    func testToggleCompleteSendsCompleteAndReloadsTasks() async throws {
        let store = makeStore(ContractFixtures.response)
        let task = try decodeFixture(TaskEntry.self, ContractFixtures.task)
        await store.toggleComplete(task)
        let requests = StubURLProtocol.requests
        XCTAssertEqual(requests.first.map(route), "task/complete")
        XCTAssertEqual(requests.first?.httpMethod, "PATCH")
        XCTAssertEqual(requests.last.map(route), "task")
    }
}
