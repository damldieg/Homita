import XCTest
@testable import ControlKit

final class MemberPresentationTests: XCTestCase {
    func testLinkLabels() {
        XCTAssertEqual(MemberRules.linkStatusLabel(linked: true), "Vinculada")
        XCTAssertEqual(MemberRules.linkStatusLabel(linked: false), "Sin cuenta")
    }

    func testStatusAndKindLabels() {
        XCTAssertEqual(MemberRules.statusLabel("active"), "Activo")
        XCTAssertEqual(MemberRules.statusLabel("inactive"), "Inactivo")
        XCTAssertEqual(MemberRules.statusLabel("otro"), "otro")
        XCTAssertEqual(MemberRules.kindLabel("pet"), "Mascota")
        XCTAssertEqual(MemberRules.kindLabel("robot"), "robot")
    }
}
