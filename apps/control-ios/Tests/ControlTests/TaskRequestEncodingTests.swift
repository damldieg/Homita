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

    /// Idempotencia (0035): sin clave no se envía nada; con clave aparece `client_request_id`.
    func testCreateTaskOmitsClientRequestIdByDefault() throws {
        let body = try json(CreateTaskRequest(task_list_id: 3, title: "Pan"))
        XCTAssertNil(body["client_request_id"])
    }

    func testCreateTaskEncodesClientRequestId() throws {
        let key = "8a1f5a8e-2b7c-4f4e-9a0b-1c2d3e4f5a6b"
        let body = try json(CreateTaskRequest(task_list_id: 3, title: "Pan", client_request_id: key))
        XCTAssertEqual(body["client_request_id"] as? String, key)
    }

    func testCreateTaskListClientRequestIdOnlyWhenPresent() throws {
        let without = try json(CreateTaskListRequest(name: "Compra", color: nil, sort: nil, widget: nil, dashboard: nil))
        XCTAssertNil(without["client_request_id"])
        let key = "8a1f5a8e-2b7c-4f4e-9a0b-1c2d3e4f5a6b"
        let with = try json(CreateTaskListRequest(name: "Compra", color: nil, sort: nil, widget: nil, dashboard: nil, client_request_id: key))
        XCTAssertEqual(with["client_request_id"] as? String, key)
    }

    func testUpdateWithEmptyArrayClearsPersons() throws {
        let body = try json(UpdateTaskRequest(id: 1, title: "Pan", person_ids: []))
        XCTAssertEqual(body["person_ids"] as? [Int], [])
    }
}
