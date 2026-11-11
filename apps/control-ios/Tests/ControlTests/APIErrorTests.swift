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
}
