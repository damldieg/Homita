import XCTest
@testable import ControlKit

/// Normalización y validación del código de invitación (1.15): 32 hex en minúsculas.
final class InvitationCodeTests: XCTestCase {
    func testNormalizeTrimsWhitespaceAndLowercases() {
        XCTAssertEqual(InvitationCode.normalize("  0123456789ABCDEF0123456789abcdef\n"),
                       "0123456789abcdef0123456789abcdef")
    }

    func testValidCodes() {
        XCTAssertTrue(InvitationCode.isValid("0123456789abcdef0123456789abcdef"))
        XCTAssertTrue(InvitationCode.isValid(" 0123456789ABCDEF0123456789ABCDEF\t"))
    }

    func testInvalidCodes() {
        XCTAssertFalse(InvitationCode.isValid(""))
        XCTAssertFalse(InvitationCode.isValid("xyz"))
        XCTAssertFalse(InvitationCode.isValid("0123456789abcdef0123456789abcde"))    // 31
        XCTAssertFalse(InvitationCode.isValid("0123456789abcdef0123456789abcdef0"))  // 33
        XCTAssertFalse(InvitationCode.isValid("0123456789abcdef0123456789abcdeg"))   // g
        XCTAssertFalse(InvitationCode.isValid("0123456789abcdef 0123456789abcde"))   // espacio interior
    }
}
