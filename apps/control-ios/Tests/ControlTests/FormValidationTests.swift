import XCTest
@testable import ControlKit

/// Validación en línea de formularios (E0-10).
final class FormValidationTests: XCTestCase {
    func testTaskTitleRequiresText() {
        XCTAssertEqual(TaskTitleValidation.message(for: ""), "El título es obligatorio")
        XCTAssertEqual(TaskTitleValidation.message(for: "   "), "El título es obligatorio")
        XCTAssertNil(TaskTitleValidation.message(for: "Comprar pan"))
    }

    func testMemberNameMessages() {
        XCTAssertEqual(MemberValidation.nameMessage(""), "El nombre es obligatorio")
        XCTAssertEqual(MemberValidation.nameMessage(String(repeating: "a", count: 51)), "El nombre admite como máximo 50 caracteres")
        XCTAssertNil(MemberValidation.nameMessage("Ana"))
    }
}
