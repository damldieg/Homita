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

    func testRequiresConfirmationResetPermissions() {
        XCTAssertTrue(HomeAdminAccess.requiresConfirmation(action: .resetPermissions))
        XCTAssertFalse(HomeAdminAccess.requiresConfirmation(action: .editPermissions))
    }

    func testRowActionsNeverEmitResetPermissions() {
        for callerRole in ["admin", "member"] {
            for rowRole in ["admin", "member"] {
                for isPersonal in [true, false] {
                    for editable in [true, false, nil] as [Bool?] {
                        let row = MembershipItem(membershipId: 1, appUserId: 5, name: "X", email: "x@x",
                                                 role: rowRole, permissions: [])
                        for caller in [5, 6] {
                            let actions = HomeAdminAccess.rowActions(
                                callerRole: callerRole, row: row, callerAppUserId: caller,
                                isPersonal: isPersonal, permissionEditable: editable, adminCount: 2)
                            XCTAssertFalse(actions.contains(.resetPermissions))
                        }
                    }
                }
            }
        }
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

    func testMembersVisibleToEveryoneManagedOnlyByAdmin() {
        for role in ["admin", "member", "adult", "child"] {
            XCTAssertTrue(HomeAdminScreenModel(role: role).showMembers, role)
        }
        let admin = HomeAdminScreenModel(role: "admin")
        XCTAssertTrue(admin.canCreateMembers)
        XCTAssertTrue(admin.canEditMembers)
        let member = HomeAdminScreenModel(role: "member")
        XCTAssertFalse(member.canCreateMembers)
        XCTAssertFalse(member.canEditMembers)
        XCTAssertTrue(HomeAdminAccess.canManageMembers(role: "admin"))
        XCTAssertFalse(HomeAdminAccess.canManageMembers(role: "member"))
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

    func testMemberErrorMessagesInSpanish() {
        func msg(_ m: String) -> String { APIError.http(status: 400, message: m).userMessage }
        XCTAssertEqual(msg("Invalid member"), "Tipo de miembro no válido")
        XCTAssertEqual(msg("Name is required (max 50 characters)"), "El nombre es obligatorio (máx. 50 caracteres)")
        XCTAssertEqual(msg("Color must be #RRGGBB"), "El color debe ser #RRGGBB")
        XCTAssertEqual(msg("Member ID is required"), "Falta el identificador del miembro")
        XCTAssertEqual(APIError.http(status: 403, message: "Not Allowed").homeAdminMessage,
                       "Solo un administrador puede realizar esta acción")
    }
}


final class PermissionRulesTests: XCTestCase {
    private let catalog = [
        PermissionCatalogEntry(code: "calendar.read", domain: "calendar", description: ""),
        PermissionCatalogEntry(code: "calendar.write", domain: "calendar", description: ""),
        PermissionCatalogEntry(code: "task.read", domain: "task", description: "")
    ]
    private let defaults = [
        PermissionDefaults(kind: "adult", permissions: ["task.read", "calendar.write", "calendar.read"]),
        PermissionDefaults(kind: "child", permissions: ["task.read", "calendar.read"]),
        PermissionDefaults(kind: "guest", permissions: ["bogus.code", "calendar.read"])
    ]

    private func item(role: String = "member", kind: String? = "child", editable: Bool = true,
                      permissions: [String] = ["calendar.write"]) -> PermissionItem {
        PermissionItem(membershipId: 8, appUserId: 9, name: "Beto", email: "b@x", role: role, kind: kind,
                       editable: editable, permissions: permissions)
    }

    func testLockReasonAdminTarget() {
        XCTAssertEqual(PermissionRules.lockReason(callerRole: "admin", item: item(role: "admin", editable: false)),
                       "Administrador: todos los accesos")
        // Prioridad: destino admin gana sobre caller member.
        XCTAssertEqual(PermissionRules.lockReason(callerRole: "member", item: item(role: "admin", editable: false)),
                       "Administrador: todos los accesos")
    }

    func testLockReasonMemberCaller() {
        XCTAssertEqual(PermissionRules.lockReason(callerRole: "member", item: item(editable: false)),
                       "Solo un administrador puede editar accesos")
    }

    func testLockReasonEditableIsNil() {
        XCTAssertNil(PermissionRules.lockReason(callerRole: "admin", item: item()))
    }

    func testLockReasonFallback() {
        XCTAssertEqual(PermissionRules.lockReason(callerRole: "admin", item: item(editable: false)),
                       "Este miembro no admite edición de accesos")
    }

    func testCanResetVisibility() {
        struct Case { let name: String; let caller: String; let item: PermissionItem; let expected: Bool }
        let cases = [
            Case(name: "ok", caller: "admin", item: item(), expected: true),
            Case(name: "caller member", caller: "member", item: item(), expected: false),
            Case(name: "destino admin", caller: "admin", item: item(role: "admin"), expected: false),
            Case(name: "sin kind", caller: "admin", item: item(kind: nil), expected: false),
            Case(name: "kind sin defaults", caller: "admin", item: item(kind: "pet"), expected: false),
            Case(name: "defaults fuera de catalogo", caller: "admin", item: item(kind: "guest"), expected: false),
            Case(name: "no editable", caller: "admin", item: item(editable: false), expected: false)
        ]
        for c in cases {
            XCTAssertEqual(PermissionRules.canReset(callerRole: c.caller, item: c.item, defaults: defaults,
                                                    catalog: catalog), c.expected, c.name)
        }
    }

    func testResetPermissionsSortedFullSet() {
        XCTAssertEqual(PermissionRules.resetPermissions(for: item(kind: "adult"), defaults: defaults, catalog: catalog),
                       ["calendar.read", "calendar.write", "task.read"])
        XCTAssertEqual(PermissionRules.resetPermissions(for: item(), defaults: defaults, catalog: catalog),
                       ["calendar.read", "task.read"])
        XCTAssertNil(PermissionRules.resetPermissions(for: item(kind: nil), defaults: defaults, catalog: catalog))
    }

    func testUnknownCodes() {
        let it = item(permissions: ["zeta.x", "calendar.read", "alfa.y"])
        XCTAssertEqual(PermissionRules.unknownCodes(item: it, catalog: catalog), ["alfa.y", "zeta.x"])
        XCTAssertEqual(PermissionRules.unknownCodes(item: item(), catalog: catalog), [])
    }

    func testKindSummaryGroupsByKindAndDomain() {
        let summary = PermissionRules.kindSummary(defaults: defaults, catalog: catalog)
        XCTAssertEqual(summary.map(\.kind), ["adult", "child", "guest"])
        XCTAssertEqual(summary[0].domains, [
            KindSummary.Domain(domain: "calendar", codes: ["calendar.read", "calendar.write"]),
            KindSummary.Domain(domain: "task", codes: ["task.read"])
        ])
        // guest: "bogus.code" fuera del catálogo se omite.
        XCTAssertEqual(summary[2].domains, [KindSummary.Domain(domain: "calendar", codes: ["calendar.read"])])
        XCTAssertEqual(PermissionRules.kindSummary(defaults: [], catalog: catalog), [])
    }
}
