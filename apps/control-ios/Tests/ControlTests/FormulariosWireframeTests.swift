import XCTest
@testable import ControlKit

/// Ajustes de formularios contra el wireframe: marca de «cambiado» en Accesos y validación del nombre.
final class FormulariosWireframeTests: XCTestCase {
    func testDraftMarksOnlyChangedPermissions() {
        var draft = PermissionDraft(permissions: ["event.create", "event.edit"])
        XCTAssertFalse(draft.isChanged("event.create"))
        draft.toggle("event.create")
        XCTAssertTrue(draft.isChanged("event.create"))
        XCTAssertFalse(draft.isChanged("event.edit"))
        draft.toggle("task.create")
        XCTAssertTrue(draft.isChanged("task.create"))
        draft.toggle("task.create")
        XCTAssertFalse(draft.isChanged("task.create"))
    }

    func testDraftRevertingClearsChange() {
        var draft = PermissionDraft(permissions: ["a"])
        draft.toggle("a")
        draft.toggle("a")
        XCTAssertFalse(draft.isChanged("a"))
        XCTAssertFalse(draft.isDirty)
    }

    func testEmptyPersonNameShowsRequiredMessage() {
        XCTAssertEqual(MemberValidation.nameMessage("   "), "El nombre es obligatorio")
        XCTAssertNil(MemberValidation.nameMessage("Ana"))
    }
}
