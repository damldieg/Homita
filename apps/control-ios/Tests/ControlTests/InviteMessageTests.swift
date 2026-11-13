import XCTest
@testable import ControlKit

final class InviteMessageTests: XCTestCase {
    func testMessageIncludesHomeNameAndCodeAndSteps() {
        let code = "0123456789abcdef0123456789abcdef"
        let text = InvitationCreateView.inviteMessage(code: code, homeName: "Casa Diego")

        XCTAssertTrue(text.contains("«Casa Diego»"))
        XCTAssertTrue(text.contains(code))
        XCTAssertTrue(text.contains("Ajustes › Unirse a un hogar con un código"))
        XCTAssertTrue(text.contains("7 días"))
    }
}
