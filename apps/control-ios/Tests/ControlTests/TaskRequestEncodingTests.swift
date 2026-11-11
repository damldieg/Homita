import XCTest
@testable import ControlKit

/// Cuerpos de task/create y task/update con personas (0025): sin `person_ids` no se envía nada
/// (el servidor no toca personas); con array se envía tal cual.
final class TaskRequestEncodingTests: XCTestCase {
    private func json<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }

    func testCreateWithPersonsEncodesIds() throws {
        let body = try json(CreateTaskRequest(task_list_id: 3, title: "Pan", person_ids: [5, 9]))
        XCTAssertEqual(body["person_ids"] as? [Int], [5, 9])
    }

    func testCreateWithoutPersonsOmitsKey() throws {
        let body = try json(CreateTaskRequest(task_list_id: 3, title: "Pan"))
        XCTAssertNil(body["person_ids"])
    }

    func testUpdateWithEmptyArrayClearsPersons() throws {
        let body = try json(UpdateTaskRequest(id: 1, title: "Pan", person_ids: []))
        XCTAssertEqual(body["person_ids"] as? [Int], [])
    }
}
