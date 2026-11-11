import XCTest
@testable import ControlKit

/// Invitaciones ligadas a email y registro con código (change hogar-admin-miembro, 0023).
final class InvitacionRegistroTests: XCTestCase {

    func testNormalizedEmailTrimsLowercasesAndRejectsMalformed() {
        XCTAssertEqual(InvitationRules.normalizedEmail("  Ana@Ejemplo.COM "), "ana@ejemplo.com")
        XCTAssertNil(InvitationRules.normalizedEmail("sin-arroba"))
        XCTAssertNil(InvitationRules.normalizedEmail("a@b"))
        XCTAssertNil(InvitationRules.normalizedEmail("a b@c.de"))
        XCTAssertNil(InvitationRules.normalizedEmail(""))
    }

    func testMakeBodyRequiresValidEmail() {
        XCTAssertNil(InvitationRules.makeBody(homeId: 2, kind: .guest, member: nil,
                                              callerRole: "admin", email: "no-es-email"))
        XCTAssertEqual(InvitationRules.makeBody(homeId: 2, kind: .guest, member: nil,
                                                callerRole: "admin", email: " Ana@Ejemplo.com ")?.email,
                       "ana@ejemplo.com")
    }

    func testRegisterRequestSendsInvitationCodeOnlyWhenPresent() throws {
        let encoder = JSONEncoder()
        let withCode = try encoder.encode(RegisterRequest(name: "Ana", email: "ana@ejemplo.com",
                                                          password: "12345678", invitationCode: "abc"))
        XCTAssertTrue(String(decoding: withCode, as: UTF8.self).contains(#""invitation_code":"abc""#))
        let withoutCode = try encoder.encode(RegisterRequest(name: "Ana", email: "ana@ejemplo.com",
                                                             password: "12345678"))
        XCTAssertFalse(String(decoding: withoutCode, as: UTF8.self).contains("invitation_code"))
    }

    func testRegisterMessagesForInvitationErrors() {
        XCTAssertTrue(RegisterView.registerMessage(
            for: APIError.http(status: 404, message: "Invitation code is not valid")).contains("no es válido"))
        XCTAssertTrue(RegisterView.registerMessage(
            for: APIError.http(status: 403, message: "The invitation was sent to another email address"))
            .contains("otro email"))
        XCTAssertTrue(RegisterView.registerMessage(
            for: APIError.http(status: 400, message: "Email already exists")).contains("inicia sesión"))
    }

    func testInvitationRowDetailShowsEmailWhenPresent() {
        let withEmail = InvitationItem(id: 1, homeId: 2, kind: "guest", email: "ana@ejemplo.com",
                                       expiresAt: "2026-11-18 10:00:00", createdAt: "2026-11-11 10:00:00")
        XCTAssertTrue(HomeInvitationsView.rowDetail(withEmail).hasPrefix("ana@ejemplo.com · "))
        let legacy = InvitationItem(id: 2, homeId: 2, kind: "guest",
                                    expiresAt: "2026-11-18 10:00:00", createdAt: "2026-11-11 10:00:00")
        XCTAssertFalse(HomeInvitationsView.rowDetail(legacy).contains("@"))
    }
}
