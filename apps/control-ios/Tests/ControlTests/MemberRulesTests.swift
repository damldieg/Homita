import XCTest
@testable import ControlKit

final class MemberRulesTests: XCTestCase {
    private func member(kind: String = "adult", status: String = "active", linked: Bool = false) -> HomeMember {
        HomeMember(id: 1, homeId: 2, kind: kind, name: "Ana", color: "#FF0000", status: status, linked: linked)
    }

    func testPetHiddenForLinked() {
        XCTAssertFalse(MemberRules.availableKinds(linked: true).contains(.pet))
        XCTAssertEqual(MemberRules.availableKinds(linked: true).count, 4)
        XCTAssertTrue(MemberRules.availableKinds(linked: false).contains(.pet))
    }

    func testResetWarningOnlyForLinkedKindChange() {
        XCTAssertTrue(MemberRules.needsPermissionResetWarning(member: member(linked: true), newKind: .child))
        XCTAssertFalse(MemberRules.needsPermissionResetWarning(member: member(linked: true), newKind: .adult))
        XCTAssertFalse(MemberRules.needsPermissionResetWarning(member: member(linked: false), newKind: .child))
    }

    func testUpdateBodyOnlyChangedFields() {
        let body = MemberRules.makeUpdateBody(original: member(), kind: .adult, status: .inactive,
                                              name: " Ana ", color: "#ff0000")
        XCTAssertEqual(body, UpdateMemberBody(id: 1, status: .inactive))
        let named = MemberRules.makeUpdateBody(original: member(), kind: .child, status: .active,
                                               name: " Bea ", color: "#00FF00")
        XCTAssertEqual(named, UpdateMemberBody(id: 1, kind: .child, name: "Bea", color: "#00FF00"))
    }

    func testUpdateBodyNilWithoutChangesAndRejectsPetForLinked() {
        XCTAssertNil(MemberRules.makeUpdateBody(original: member(), kind: .adult, status: .active, name: "Ana", color: "#FF0000"))
        XCTAssertNil(MemberRules.makeUpdateBody(original: member(linked: true), kind: .pet, status: .active, name: "Ana", color: "#FF0000"))
        XCTAssertNotNil(MemberRules.makeUpdateBody(original: member(linked: false), kind: .pet, status: .active, name: "Ana", color: "#FF0000"))
    }

    func testNameEditWithUnknownKindStatusAndNilColorSendsOnlyName() {
        let original = HomeMember(id: 1, homeId: 2, kind: "robot", name: "Ana", color: nil, status: "paused", linked: false)
        let body = MemberRules.makeUpdateBody(original: original, kind: nil, status: nil, name: "Bea", color: nil)
        XCTAssertEqual(body, UpdateMemberBody(id: 1, name: "Bea"))
        let encoded = try? JSONSerialization.jsonObject(with: JSONEncoder().encode(body)) as? [String: Any]
        XCTAssertEqual(Set(encoded?.keys.map { $0 } ?? []), ["id", "name"])
    }

    func testExplicitChoiceOnUnknownOriginalIsSent() {
        let original = HomeMember(id: 1, homeId: 2, kind: "robot", name: "Ana", color: nil, status: "paused", linked: false)
        let body = MemberRules.makeUpdateBody(original: original, kind: .guest, status: .active, name: "Ana", color: "#112233")
        XCTAssertEqual(body, UpdateMemberBody(id: 1, kind: .guest, status: .active, color: "#112233"))
    }

    func testNoWarningWithoutKindChoice() {
        XCTAssertFalse(MemberRules.needsPermissionResetWarning(member: member(kind: "robot", linked: true), newKind: nil))
    }
}
