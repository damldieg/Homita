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

    /// R1-03: «Eliminar lista» sin red solo para el propietario (o una lista creada offline).
    func testDeleteEnabled() {
        XCTAssertTrue(TaskListEditorFields.deleteEnabled(isLocalList: false, isOnline: true, isOwner: false, pendingCount: 0), "con red y cola vacía decide el servidor")
        XCTAssertTrue(TaskListEditorFields.deleteEnabled(isLocalList: false, isOnline: true, isOwner: nil, pendingCount: 0))
        XCTAssertTrue(TaskListEditorFields.deleteEnabled(isLocalList: false, isOnline: false, isOwner: true, pendingCount: 0))
        XCTAssertFalse(TaskListEditorFields.deleteEnabled(isLocalList: false, isOnline: false, isOwner: false, pendingCount: 0), "no propietario sin red")
        XCTAssertFalse(TaskListEditorFields.deleteEnabled(isLocalList: false, isOnline: false, isOwner: nil, pendingCount: 0), "miembros desconocidos sin red")
        XCTAssertTrue(TaskListEditorFields.deleteEnabled(isLocalList: true, isOnline: false, isOwner: nil, pendingCount: 0), "lista creada offline")
    }

    /// R2-02: con red pero la cola del hogar no vacía el borrado se encola; misma regla que sin red.
    func testDeleteEnabledOnlineWithPendingQueue() {
        XCTAssertFalse(TaskListEditorFields.deleteEnabled(isLocalList: false, isOnline: true, isOwner: false, pendingCount: 2), "no propietario con cola no vacía")
        XCTAssertTrue(TaskListEditorFields.deleteEnabled(isLocalList: false, isOnline: true, isOwner: true, pendingCount: 2), "propietario con cola no vacía")
        XCTAssertTrue(TaskListEditorFields.deleteEnabled(isLocalList: true, isOnline: true, isOwner: nil, pendingCount: 2), "lista creada offline con cola no vacía")
        XCTAssertFalse(TaskListEditorFields.deleteEnabled(isLocalList: false, isOnline: true, isOwner: nil, pendingCount: 1), "miembros desconocidos con cola no vacía")
        XCTAssertFalse(TaskListEditorFields.deleteEnabled(isLocalList: false, isOnline: false, isOwner: false, pendingCount: 3), "no propietario sin red y con cola")
    }

    func testSignOutMessage() {
        XCTAssertEqual(ProfileView.signOutMessage(pendingCount: 0), "¿Cerrar sesión en este iPhone?")
        XCTAssertEqual(ProfileView.signOutMessage(pendingCount: 1),
                       "Tienes 1 cambio sin sincronizar; se perderá. ¿Cerrar sesión en este iPhone?")
        XCTAssertEqual(ProfileView.signOutMessage(pendingCount: 4),
                       "Tienes 4 cambios sin sincronizar; se perderán. ¿Cerrar sesión en este iPhone?")
    }
}
