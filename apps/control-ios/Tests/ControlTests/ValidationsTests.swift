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

    func testEventEndDateValidation() {
        let start = "2026-11-10 09:00:00"
        // RN-2: fin anterior al día de inicio → error; mismo día, posterior o ausente → válido.
        XCTAssertEqual(EventValidation.validate(title: "Vacaciones", dateAt: start, endDate: "2026-11-05"),
                       "La fecha de fin no puede ser anterior al inicio")
        XCTAssertNil(EventValidation.validate(title: "Vacaciones", dateAt: start, endDate: "2026-11-10"))
        XCTAssertNil(EventValidation.validate(title: "Vacaciones", dateAt: start, endDate: "2026-11-20"))
        XCTAssertNil(EventValidation.validate(title: "Vacaciones", dateAt: start, endDate: nil))
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
