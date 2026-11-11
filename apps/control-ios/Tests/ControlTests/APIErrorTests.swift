import XCTest
@testable import ControlKit

final class APIErrorTests: XCTestCase {
    func testHomeAdminMessage403() {
        XCTAssertEqual(APIError.http(status: 403, message: "Not Allowed").homeAdminMessage,
                       "Solo un administrador puede realizar esta acción")
    }

    func testHomeAdminMessage404() {
        XCTAssertEqual(APIError.http(status: 404, message: "Not Found").homeAdminMessage, "No encontrado")
    }

    func testHomeAdminMessageDelegates() {
        XCTAssertEqual(APIError.http(status: 400, message: "Invalid timezone").homeAdminMessage, "Invalid timezone")
        XCTAssertEqual(APIError.network("x").homeAdminMessage, APIError.network("x").userMessage)
    }

    func testUserMessageUnchanged() {
        XCTAssertEqual(APIError.http(status: 403, message: "Not Allowed").userMessage,
                       "Solo el propietario puede realizar esta acción")
    }

    func testMembershipActionMessageIsNeutral() {
        let m = APIError.http(status: 403, message: "Not Allowed").membershipActionMessage
        XCTAssertFalse(m.contains("Solo un administrador"))
        XCTAssertTrue(m.contains("al menos un administrador"))
        XCTAssertEqual(APIError.http(status: 400, message: "X").membershipActionMessage, "X")
    }

    func testInvitationMessage() {
        XCTAssertEqual(APIError.http(status: 404, message: "Not Found").invitationMessage,
                       "El código no es válido, ya se usó o ha caducado")
        XCTAssertEqual(APIError.http(status: 403, message: "Not Allowed").invitationMessage,
                       "Esta invitación es para otro email")
        XCTAssertEqual(APIError.http(status: 400, message: "Already member").invitationMessage,
                       "Ya eres miembro de ese hogar")
        XCTAssertEqual(APIError.http(status: 400, message: "Invitation code is required").invitationMessage,
                       "Introduce el código de invitación")
        XCTAssertEqual(APIError.http(status: 400, message: "Invalid member").invitationMessage,
                       "La invitación ya no es válida para ese miembro")
        XCTAssertEqual(APIError.network("x").invitationMessage, APIError.network("x").userMessage)
    }

    func testInvitationAdminMessage() {
        XCTAssertEqual(APIError.http(status: 400, message: "Already member").invitationAdminMessage,
                       "Esa persona ya es miembro del hogar")
        XCTAssertEqual(APIError.http(status: 400, message: "Invalid email").invitationAdminMessage,
                       "Revisa el email de la invitación")
        XCTAssertEqual(APIError.http(status: 403, message: "Not Allowed").invitationAdminMessage,
                       "No tienes permiso para crear esta invitación")
    }
}
