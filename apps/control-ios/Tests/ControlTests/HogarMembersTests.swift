import XCTest
@testable import ControlKit

final class HogarMembersTests: XCTestCase {
    private func member(_ id: Int, kind: String, name: String, status: String = "active", linked: Bool) throws -> HomeMember {
        try decodeFixture(HomeMember.self, """
        {"id":\(id),"home_id":2,"kind":"\(kind)","name":"\(name)","color":null,"status":"\(status)","linked":\(linked)}
        """)
    }

    private func permissions() throws -> PermissionsResponse {
        try decodeFixture(PermissionsResponse.self, ContractFixtures.permissionGetWithKind)
    }

    func testComposeAccountsThenMembersWithoutAccount() throws {
        let members = [
            try member(1, kind: "adult", name: "Ana", linked: true),
            try member(2, kind: "child", name: "Luz", linked: false),
            try member(3, kind: "pet", name: "Miko", linked: false),
            try member(4, kind: "child", name: "Inactivo", status: "inactive", linked: false)
        ]
        let rows = HogarMemberRows.compose(members: members, permissions: try permissions(), callerAppUserId: 1)
        XCTAssertEqual(rows.map(\.name), ["Ana", "Beto", "Cris", "Luz", "Miko"])
        XCTAssertEqual(rows.filter(\.isMe).map(\.name), ["Ana"])
        XCTAssertEqual(rows.map(\.hasAccount), [true, true, true, false, false])
        XCTAssertEqual(rows[3].kindLabel, "Niño")
        XCTAssertEqual(rows[4].kindLabel, "Mascota")
        XCTAssertEqual(rows[0].kindLabel, "Adulto")
        XCTAssertEqual(rows[0].roleLabel, "Administrador")
        XCTAssertNil(rows[3].roleLabel)
    }

    func testPermissionsUseCatalogDescriptionAndKeepUnknownCodes() throws {
        let json = #"{"catalog":[{"code":"calendar.read","domain":"calendar","description":"Ver calendario"}],"defaults":[],"memberships":[{"membership_id":8,"app_user_id":9,"name":"Beto","email":"b@x.es","role":"member","kind":"child","editable":true,"permissions":["calendar.read","raro.codigo"]}]}"#
        let response = try decodeFixture(PermissionsResponse.self, json)
        let rows = HogarMemberRows.compose(members: [], permissions: response, callerAppUserId: nil)
        XCTAssertEqual(rows.first?.permissions, ["Ver calendario", "raro.codigo"])
        XCTAssertEqual(rows.first?.isMe, false)
    }

    func testInitialOfName() {
        XCTAssertEqual(HogarMemberRows.initial(of: " ana"), "A")
        XCTAssertEqual(HogarMemberRows.initial(of: ""), "?")
    }

    func testAccountWithoutKindHasNoKindLabel() throws {
        let rows = HogarMemberRows.compose(members: [], permissions: try permissions(), callerAppUserId: 11)
        let cris = try XCTUnwrap(rows.first { $0.name == "Cris" })
        XCTAssertNil(cris.kindLabel)
        XCTAssertTrue(cris.isMe)
    }

    func testPermissionsPreviewCutsToThreeInBackendOrder() {
        func row(_ perms: [String]) -> HogarMemberRow {
            HogarMemberRow(id: "x", name: "X", initial: "X", kindLabel: nil, roleLabel: nil,
                           permissions: perms, isMe: false, hasAccount: true)
        }
        let many = row(["a", "b", "c", "d"])
        XCTAssertEqual(many.permissionsPreview, ["a", "b", "c"])
        XCTAssertTrue(many.hasMorePermissions)
        let few = row(["a", "b", "c"])
        XCTAssertEqual(few.permissionsPreview, ["a", "b", "c"])
        XCTAssertFalse(few.hasMorePermissions)
        XCTAssertEqual(row([]).permissionsPreview, [])
    }
}
