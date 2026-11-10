import XCTest
@testable import ControlKit

final class HomeAdminAccessTests: XCTestCase {
    private func row(_ id: Int, user: Int, role: String) -> MembershipItem {
        MembershipItem(membershipId: id, appUserId: user, name: "N", email: "e", role: role)
    }

    func testMemberOnlyLeaveOnSelf() {
        XCTAssertFalse(HomeAdminAccess.canEditSettings(role: "member"))
        XCTAssertFalse(HomeAdminAccess.canViewAudit(role: "member"))
        XCTAssertFalse(HomeAdminAccess.canManageRoles(role: "member"))
        XCTAssertEqual(HomeAdminAccess.rowActions(callerRole: "member", row: row(1, user: 5, role: "member"),
                                                  callerAppUserId: 5, isPersonal: false), [.leave])
        XCTAssertEqual(HomeAdminAccess.rowActions(callerRole: "member", row: row(2, user: 6, role: "admin"),
                                                  callerAppUserId: 5, isPersonal: false), [])
        XCTAssertEqual(HomeAdminAccess.rowActions(callerRole: "member", row: row(3, user: 7, role: "member"),
                                                  callerAppUserId: 5, isPersonal: false), [])
    }

    func testAdminOnOtherMember() {
        let actions = HomeAdminAccess.rowActions(callerRole: "admin", row: row(2, user: 6, role: "member"),
                                                 callerAppUserId: 5, isPersonal: false)
        XCTAssertEqual(actions, [.promote, .transfer, .remove, .editPermissions])
    }

    func testAdminOnOtherAdmin() {
        let actions = HomeAdminAccess.rowActions(callerRole: "admin", row: row(2, user: 6, role: "admin"),
                                                 callerAppUserId: 5, isPersonal: false)
        XCTAssertEqual(actions, [.demote, .remove])
        XCTAssertFalse(actions.contains(.editPermissions))
        XCTAssertFalse(actions.contains(.transfer))
    }

    func testAdminOnSelf() {
        let actions = HomeAdminAccess.rowActions(callerRole: "admin", row: row(1, user: 5, role: "admin"),
                                                 callerAppUserId: 5, isPersonal: false)
        XCTAssertEqual(actions, [.leave, .demote])
        XCTAssertFalse(actions.contains(.transfer))
    }

    func testPersonalHidesTransferAndRemove() {
        let other = HomeAdminAccess.rowActions(callerRole: "admin", row: row(2, user: 6, role: "member"),
                                               callerAppUserId: 5, isPersonal: true)
        XCTAssertFalse(other.contains(.transfer))
        XCTAssertFalse(other.contains(.remove))
        let admin = HomeAdminAccess.rowActions(callerRole: "admin", row: row(2, user: 6, role: "admin"),
                                               callerAppUserId: 5, isPersonal: true)
        XCTAssertFalse(admin.contains(.remove))
        let me = HomeAdminAccess.rowActions(callerRole: "admin", row: row(1, user: 5, role: "admin"),
                                            callerAppUserId: 5, isPersonal: true)
        XCTAssertFalse(me.contains(.leave))
    }

    func testNotEditablePermissionHidesEditor() {
        let actions = HomeAdminAccess.rowActions(callerRole: "admin", row: row(2, user: 6, role: "member"),
                                                 callerAppUserId: 5, isPersonal: false, permissionEditable: false)
        XCTAssertFalse(actions.contains(.editPermissions))
    }

    func testUnknownCallerIdHidesLeave() {
        let actions = HomeAdminAccess.rowActions(callerRole: "member", row: row(1, user: 5, role: "member"),
                                                 callerAppUserId: nil, isPersonal: false)
        XCTAssertEqual(actions, [])
    }

    func testLastAdminCannotDemoteRemoveOrLeave() {
        let me = row(1, user: 5, role: "admin")
        let alone = HomeAdminAccess.rowActions(callerRole: "admin", row: me, callerAppUserId: 5,
                                               isPersonal: false, adminCount: 1)
        XCTAssertFalse(alone.contains(.demote))
        XCTAssertFalse(alone.contains(.leave))
        XCTAssertFalse(alone.contains(.remove))
        let two = HomeAdminAccess.rowActions(callerRole: "admin", row: me, callerAppUserId: 5,
                                             isPersonal: false, adminCount: 2)
        XCTAssertTrue(two.contains(.demote))
        XCTAssertTrue(two.contains(.leave))
    }

    func testOtherAdminRowsWithTwoAdmins() {
        let other = row(2, user: 6, role: "admin")
        let two = HomeAdminAccess.rowActions(callerRole: "admin", row: other, callerAppUserId: 5,
                                             isPersonal: false, adminCount: 2)
        XCTAssertEqual(two, [.demote, .remove])
        let one = HomeAdminAccess.rowActions(callerRole: "member", row: other, callerAppUserId: 5,
                                             isPersonal: false, adminCount: 1)
        XCTAssertEqual(one, [])
    }

    func testRequiresConfirmation() {
        for a in [MembershipRowAction.remove, .leave, .transfer, .demote] {
            XCTAssertTrue(HomeAdminAccess.requiresConfirmation(action: a))
        }
        XCTAssertFalse(HomeAdminAccess.requiresConfirmation(action: .promote))
        XCTAssertFalse(HomeAdminAccess.requiresConfirmation(action: .editPermissions))
    }

    func testScreenModel() {
        let member = HomeAdminScreenModel(role: "member")
        XCTAssertTrue(member.showSettings)
        XCTAssertTrue(member.showAdministrators)
        XCTAssertFalse(member.showPermissions)
        XCTAssertFalse(member.showAudit)
        XCTAssertFalse(member.canEdit)
        let admin = HomeAdminScreenModel(role: "admin")
        XCTAssertTrue(admin.showPermissions && admin.showAudit && admin.canEdit)
    }
}

final class PermissionDraftTests: XCTestCase {
    func testToggleAndDirty() {
        var d = PermissionDraft(permissions: ["b", "a"])
        XCTAssertFalse(d.isDirty)
        d.toggle("c")
        XCTAssertTrue(d.isDirty)
        XCTAssertEqual(d.finalPermissions, ["a", "b", "c"])
        d.toggle("c")
        XCTAssertFalse(d.isDirty)
        d.toggle("a")
        XCTAssertEqual(d.finalPermissions, ["b"])
        XCTAssertFalse(d.isOn("a"))
    }
}

final class GroupedCatalogTests: XCTestCase {
    func testGroupsByDomainSorted() {
        let g = groupedCatalog([
            PermissionCatalogEntry(code: "task.read", domain: "task", description: ""),
            PermissionCatalogEntry(code: "calendar.write", domain: "calendar", description: ""),
            PermissionCatalogEntry(code: "calendar.read", domain: "calendar", description: "")
        ])
        XCTAssertEqual(g.map(\.domain), ["calendar", "task"])
        XCTAssertEqual(g[0].entries.map(\.code), ["calendar.read", "calendar.write"])
    }
}

final class AuditPagerTests: XCTestCase {
    private func item(_ id: Int) -> AuditItem { AuditItem(id: id, action: "a", targetType: "t", createdAt: "c") }

    func testNextBeforeIdIsLast() {
        XCTAssertEqual(AuditPager.nextBeforeId(items: [item(12), item(11)]), 11)
        XCTAssertNil(AuditPager.nextBeforeId(items: []))
    }

    func testHasMore() {
        XCTAssertTrue(AuditPager.hasMore(received: 50, limit: 50))
        XCTAssertFalse(AuditPager.hasMore(received: 49, limit: 50))
    }

    func testMergeNoDuplicates() {
        let merged = AuditPager.merge([item(12), item(11)], [item(11), item(10)])
        XCTAssertEqual(merged.map(\.id), [12, 11, 10])
    }
}
