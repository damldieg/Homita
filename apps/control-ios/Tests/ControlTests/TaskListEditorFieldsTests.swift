import XCTest
@testable import ControlKit

/// Q8 (D-024): campos owner-only del editor de listas sin red; confirmación de cierre de sesión (T29).
final class TaskListEditorFieldsTests: XCTestCase {
    func testCreateAlwaysEnabled() {
        XCTAssertTrue(TaskListEditorFields.ownerFieldsEnabled(isEditing: false, isLocalList: false, isOnline: false, isOwner: nil))
    }

    func testOnlineAlwaysEnabled() {
        XCTAssertTrue(TaskListEditorFields.ownerFieldsEnabled(isEditing: true, isLocalList: false, isOnline: true, isOwner: false))
        XCTAssertTrue(TaskListEditorFields.ownerFieldsEnabled(isEditing: true, isLocalList: false, isOnline: true, isOwner: nil))
    }

    func testOfflineOnlyOwner() {
        XCTAssertTrue(TaskListEditorFields.ownerFieldsEnabled(isEditing: true, isLocalList: false, isOnline: false, isOwner: true))
        XCTAssertFalse(TaskListEditorFields.ownerFieldsEnabled(isEditing: true, isLocalList: false, isOnline: false, isOwner: false))
    }

    func testOfflineUnknownMembersDisabled() {
        XCTAssertFalse(TaskListEditorFields.ownerFieldsEnabled(isEditing: true, isLocalList: false, isOnline: false, isOwner: nil))
    }

    func testOfflineLocalListEnabled() {
        XCTAssertTrue(TaskListEditorFields.ownerFieldsEnabled(isEditing: true, isLocalList: true, isOnline: false, isOwner: nil))
    }

    func testSignOutMessage() {
        XCTAssertEqual(ProfileView.signOutMessage(pendingCount: 0), "¿Cerrar sesión en este iPhone?")
        XCTAssertEqual(ProfileView.signOutMessage(pendingCount: 1),
                       "Tienes 1 cambio sin sincronizar; se perderá. ¿Cerrar sesión en este iPhone?")
        XCTAssertEqual(ProfileView.signOutMessage(pendingCount: 4),
                       "Tienes 4 cambios sin sincronizar; se perderán. ¿Cerrar sesión en este iPhone?")
    }
}
