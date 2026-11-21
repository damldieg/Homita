import XCTest
@testable import ControlKit

/// `InicioItem`: ids únicos por tipo (la hoja de Inicio usa `.sheet(item:)`).
final class InicioItemTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    func testIdsAreUniquePerKindEvenWithSameNumericId() throws {
        let event = try decode(EventEntry.self, #"{"id":5,"calendar_id":3,"title":"E","date_at":"2026-11-08 09:30:00"}"#)
        let task = try decode(TaskEntry.self, #"{"id":5,"task_list_id":2,"title":"T"}"#)
        let routine = try decode(RoutineEntry.self, #"{"id":5,"calendar_id":3,"title":"R","time":"09:00","start_date":"2026-11-02"}"#)
        let ids = [InicioItem.event(event).id, InicioItem.task(task).id, InicioItem.routine(routine).id]
        XCTAssertEqual(Set(ids).count, 3)
        XCTAssertEqual(InicioItem.event(event).kind, .event)
        XCTAssertEqual(InicioItem.task(task).kind, .task)
        XCTAssertEqual(InicioItem.routine(routine).kind, .routine)
    }

    func testEquality() throws {
        let task = try decode(TaskEntry.self, #"{"id":7,"task_list_id":2,"title":"Leche"}"#)
        XCTAssertEqual(InicioItem.task(task), InicioItem.task(task))
        let other = try decode(TaskEntry.self, #"{"id":8,"task_list_id":2,"title":"Leche"}"#)
        XCTAssertNotEqual(InicioItem.task(task), InicioItem.task(other))
    }
}
