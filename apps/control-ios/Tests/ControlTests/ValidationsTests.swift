import XCTest
@testable import ControlKit

/// `EventValidation`, `PersonActions` y longitud en codepoints (`mb_strlen` de PHP).
final class ValidationsTests: XCTestCase {
    func testEventValidation() {
        XCTAssertEqual(EventValidation.validate(title: "", dateAt: "2026-11-08 09:30:00"), "El título es obligatorio")
        XCTAssertEqual(EventValidation.validate(title: "   ", dateAt: "2026-11-08 09:30:00"), "El título es obligatorio")
        XCTAssertEqual(EventValidation.validate(title: "Reunión", dateAt: ""), "La fecha es obligatoria")
        XCTAssertNil(EventValidation.validate(title: "Reunión", dateAt: "2026-11-08 09:30:00"))
    }

    func testPersonActionsByEditable() {
        XCTAssertEqual(PersonActions.available(editable: true), [.edit, .delete])
        XCTAssertEqual(PersonActions.available(editable: false), [])
    }

    func testCodepointCountMatchesMbStrlen() {
        XCTAssertEqual("Demo".codepointCount, 4)
        XCTAssertEqual("año".codepointCount, 3) // ñ es 1 codepoint (2 en UTF-16 no aplica)
        XCTAssertEqual("😀".codepointCount, 1) // emoji astral: 1 codepoint, 2 unidades UTF-16
        XCTAssertEqual("😀".utf16.count, 2)
    }
}
