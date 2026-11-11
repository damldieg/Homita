import XCTest
@testable import ControlKit

/// Contrato de `GET task` con personas asignadas (migración 0024): el campo es opcional para no
/// romper respuestas sin `persons`.
final class TaskPersonsDecodingTests: XCTestCase {
    private func decode(_ json: String) throws -> TaskEntry {
        try JSONDecoder().decode(TaskEntry.self, from: Data(json.utf8))
    }

    func testDecodesAssignedPersons() throws {
        let task = try decode("""
        {"id":1,"task_list_id":2,"title":"Comprar pan","completed_at":null,"created_at":null,
         "updated_at":null,"order":0,"task_list_color":null,"task_list_name":"Casa",
         "persons":[{"id":5,"user_id":9,"name":"Ana","color":"#6923E2"}]}
        """)
        XCTAssertEqual(task.persons?.map(\.name), ["Ana"])
    }

    func testMissingPersonsDecodesAsNil() throws {
        let task = try decode("""
        {"id":1,"task_list_id":2,"title":"Comprar pan","completed_at":null,"created_at":null,
         "updated_at":null,"order":0,"task_list_color":null,"task_list_name":"Casa"}
        """)
        XCTAssertNil(task.persons)
    }
}
