import XCTest
@testable import ControlKit

final class HomeAdminModelsTests: XCTestCase {
    func testHomeDetailFull() throws {
        let d = try decodeFixture(HomeDetailFull.self, ContractFixtures.homeDetailFull)
        XCTAssertEqual(d, HomeDetailFull(id: 2, name: "Familia", timezone: "Europe/Madrid", isPersonal: false,
                                         createdAt: "2026-11-01 10:00:00", updatedAt: "2026-11-02 11:00:00"))
    }

    func testMembershipItemAndStates() throws {
        let m = try decodeFixture(MembershipItem.self, ContractFixtures.membershipItem)
        XCTAssertEqual(m.membershipId, 7)
        XCTAssertEqual(m.appUserId, 1)
        XCTAssertEqual(m.permissions, ["calendar.read", "calendar.write"])
        let s = try decodeFixture(MembershipState.self, ContractFixtures.membershipState)
        XCTAssertEqual(s.role, "admin")
        let t = try decodeFixture(TransferState.self, ContractFixtures.transferState)
        XCTAssertEqual(t.toMembershipId, 8)
    }

    func testPermissionGetKindAbsentAndPresent() throws {
        let g = try decodeFixture(PermissionsResponse.self, ContractFixtures.permissionGet)
        XCTAssertEqual(g.catalog.count, 3)
        XCTAssertEqual(g.defaults.first?.kind, "adult")
        XCTAssertEqual(g.memberships[0].kind, "adult")
        XCTAssertNil(g.memberships[1].kind)
        XCTAssertFalse(g.memberships[0].editable)
        XCTAssertTrue(g.memberships[1].editable)
    }

    func testPermissionState() throws {
        let s = try decodeFixture(PermissionState.self, ContractFixtures.permissionState)
        XCTAssertEqual(s.granted, ["task.read"])
        XCTAssertEqual(s.revoked, [])
    }

    func testHomeMember() throws {
        let list = try decodeFixture([HomeMember].self, ContractFixtures.homeMemberList)
        XCTAssertEqual(list.first?.kind, "adult")
        XCTAssertEqual(list.first?.linked, true)
    }

    func testAuditItemsLenientPayload() throws {
        let items = try decodeFixture([AuditItem].self, ContractFixtures.auditList)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].targetId, 8)
        XCTAssertEqual(items[0].actorName, "Ana")
        XCTAssertEqual(items[0].payload.values["role"], "admin")
        XCTAssertEqual(items[0].payload.values["granted"], "[…]")
        XCTAssertEqual(items[0].payload.values["nested"], "{…}")
        XCTAssertEqual(items[0].payload.values["n"], "3")
        XCTAssertEqual(items[0].payload.values["flag"], "true")
        XCTAssertNil(items[0].payload.values["none"])
        XCTAssertEqual(items[0].payload.lines.first, "flag: true")
        XCTAssertNil(items[1].targetId)
        XCTAssertNil(items[1].actorName)
        XCTAssertNil(items[1].actorAppUserId)
        XCTAssertTrue(items[1].payload.values.isEmpty)
    }

    func testAuditPayloadNonObjectDoesNotFail() throws {
        let item = try decodeFixture(AuditItem.self, #"{"id":1,"action":"x","target_type":"t","payload":"texto","created_at":"c"}"#)
        XCTAssertTrue(item.payload.values.isEmpty)
    }
}
