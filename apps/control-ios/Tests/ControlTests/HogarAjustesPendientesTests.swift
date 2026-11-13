import XCTest
@testable import ControlKit

private final class ActiveBox: @unchecked Sendable {
    var active: String? = "2"
}

/// Pendientes de Hogar y Ajustes del wireframe: resúmenes del menú, filtros de auditoría, cuenta
/// sin cambios y fallo de carga de Personas.
final class HogarAjustesPendientesTests: XCTestCase {
    // MARK: - Resúmenes del menú Administración

    func testAdministratorsSummaryPluralises() {
        XCTAssertEqual(HomeAdminSummary.administrators(1), "1 administrador")
        XCTAssertEqual(HomeAdminSummary.administrators(2), "2 administradores")
        XCTAssertNil(HomeAdminSummary.administrators(nil))
    }

    func testMembersSummary() {
        XCTAssertEqual(HomeAdminSummary.members(0), "Sin miembros")
        XCTAssertEqual(HomeAdminSummary.members(1), "1 miembro")
        XCTAssertEqual(HomeAdminSummary.members(4), "4 miembros")
        XCTAssertNil(HomeAdminSummary.members(nil))
    }

    func testInvitationsSummary() {
        XCTAssertEqual(HomeAdminSummary.invitations(0), "Sin pendientes")
        XCTAssertEqual(HomeAdminSummary.invitations(1), "1 pendiente")
        XCTAssertEqual(HomeAdminSummary.invitations(3), "3 pendientes")
        XCTAssertNil(HomeAdminSummary.invitations(nil))
    }

    func testSummaryStoreCountsAndSkipsInvitationsWithoutPermission() async {
        let box = ActiveBox()
        StubURLProtocol.reset(ContractFixtures.response)
        let client = APIClient(
            baseURL: URL(string: "https://test.supabase.co/functions/v1/api")!,
            session: StubURLProtocol.session(),
            tokenProvider: { "test-access" },
            homeIdProvider: { box.active },
            readCache: ReadCache(directory: FileManager.default.temporaryDirectory.appendingPathComponent("readcache-\(UUID().uuidString)"))
        )
        let repo = HomeRepository(client: client)

        let withInvites = AdminSummaryStore(repo: repo, homeId: 2, activeHomeId: { box.active })
        XCTAssertTrue(withInvites.isLoading)
        await withInvites.load(includeInvitations: true)
        XCTAssertFalse(withInvites.isLoading)
        XCTAssertEqual(withInvites.administrators, 1)
        XCTAssertEqual(withInvites.members, 1)
        XCTAssertEqual(withInvites.invitations, 2)

        let without = AdminSummaryStore(repo: repo, homeId: 2, activeHomeId: { box.active })
        await without.load(includeInvitations: false)
        XCTAssertNil(without.invitations)
    }

    func testSummaryStoreFailsPerSummary() async {
        let box = ActiveBox()
        StubURLProtocol.reset { request in
            if request.url?.path.hasSuffix("home/invitation") == true {
                return StubURLProtocol.Stub(status: 500, json: #"{"error":"boom"}"#)
            }
            return ContractFixtures.response(for: request)
        }
        let client = APIClient(
            baseURL: URL(string: "https://test.supabase.co/functions/v1/api")!,
            session: StubURLProtocol.session(),
            tokenProvider: { "test-access" },
            homeIdProvider: { box.active },
            readCache: ReadCache(directory: FileManager.default.temporaryDirectory.appendingPathComponent("readcache-\(UUID().uuidString)"))
        )
        let store = AdminSummaryStore(repo: HomeRepository(client: client), homeId: 2, activeHomeId: { box.active })
        await store.load(includeInvitations: true)
        XCTAssertEqual(store.administrators, 1)
        XCTAssertNil(store.invitations, "un resumen que falla queda en nil sin tumbar los demás")
    }

    // MARK: - Filtros de auditoría

    private func item(_ id: Int, _ action: String, actor: String?) -> AuditItem {
        AuditItem(id: id, action: action, targetType: "home", actorName: actor, createdAt: "2026-11-02 11:00:00")
    }

    func testAuditGroupsFromAction() {
        XCTAssertEqual(AuditFilter.Group.of(action: "home.invitation.create"), .invitations)
        XCTAssertEqual(AuditFilter.Group.of(action: "home.permission.grant"), .permissions)
        XCTAssertEqual(AuditFilter.Group.of(action: "membership.role_changed"), .members)
        XCTAssertEqual(AuditFilter.Group.of(action: "home.updated"), .home)
    }

    func testAuditFilterByGroupAndActor() {
        let items = [
            item(1, "home.invitation.create", actor: "Ana"),
            item(2, "home.permission.grant", actor: "Ana"),
            item(3, "home.invitation.revoke", actor: nil),
        ]
        XCTAssertEqual(AuditFilter().apply(to: items).count, 3, "sin filtro no se quita nada")
        XCTAssertEqual(AuditFilter(group: .invitations).apply(to: items).map(\.id), [1, 3])
        XCTAssertEqual(AuditFilter(actor: "Ana").apply(to: items).map(\.id), [1, 2])
        XCTAssertEqual(AuditFilter(actor: AuditFilter.system).apply(to: items).map(\.id), [3])
        XCTAssertEqual(AuditFilter(group: .invitations, actor: "Ana").apply(to: items).map(\.id), [1])
    }

    func testAuditActorsSortedWithSystemLast() {
        let items = [
            item(1, "home.updated", actor: "Beto"),
            item(2, "home.updated", actor: nil),
            item(3, "home.updated", actor: "Ana"),
            item(4, "home.updated", actor: "Ana"),
        ]
        XCTAssertEqual(AuditFilter.actors(in: items), ["Ana", "Beto", "Sistema"])
        XCTAssertEqual(AuditFilter.actors(in: [item(1, "home.updated", actor: "Ana")]), ["Ana"])
    }

    // MARK: - Cuenta sin cambios

    func testAccountHasNoChangesWhenFormMatchesSession() {
        XCTAssertFalse(ProfileView.hasAccountChanges(
            name: "Ana", email: "ana@x.es", password: "", sessionName: "Ana", sessionEmail: "ana@x.es"))
        XCTAssertFalse(ProfileView.hasAccountChanges(
            name: " Ana ", email: "ana@x.es ", password: "", sessionName: "Ana", sessionEmail: "ana@x.es"),
            "los espacios sobrantes no cuentan como cambio")
    }

    func testAccountChangesDetected() {
        XCTAssertTrue(ProfileView.hasAccountChanges(
            name: "Ana B", email: "ana@x.es", password: "", sessionName: "Ana", sessionEmail: "ana@x.es"))
        XCTAssertTrue(ProfileView.hasAccountChanges(
            name: "Ana", email: "otra@x.es", password: "", sessionName: "Ana", sessionEmail: "ana@x.es"))
        XCTAssertTrue(ProfileView.hasAccountChanges(
            name: "Ana", email: "ana@x.es", password: "12345678", sessionName: "Ana", sessionEmail: "ana@x.es"))
    }

    // MARK: - Personas: fallo de la primera lectura

    func testPersonsFirstLoadFailureIsInlineNotAlert() async {
        StubURLProtocol.reset { _ in StubURLProtocol.Stub(status: 500, json: #"{"error":"boom"}"#) }
        let store = PersonStore(repo: PersonRepository(client: makeTestClient()))
        await store.load()
        XCTAssertNotNil(store.loadFailure)
        XCTAssertNil(store.errorMessage)
    }

    func testPersonsLoadSuccessClearsFailure() async {
        StubURLProtocol.reset { _ in StubURLProtocol.Stub(status: 500, json: #"{"error":"boom"}"#) }
        let store = PersonStore(repo: PersonRepository(client: makeTestClient()))
        await store.load()
        XCTAssertNotNil(store.loadFailure)
        StubURLProtocol.reset(ContractFixtures.response)
        await store.load()
        XCTAssertNil(store.loadFailure)
    }

    func testPersonDeleteReturnsWhetherItWorked() async throws {
        StubURLProtocol.reset(ContractFixtures.response)
        let store = PersonStore(repo: PersonRepository(client: makeTestClient()))
        let person = try JSONDecoder().decode(PersonEntry.self, from: Data(ContractFixtures.person.utf8))
        let ok = await store.delete(person)
        XCTAssertTrue(ok)

        StubURLProtocol.reset { _ in StubURLProtocol.Stub(status: 500, json: #"{"error":"boom"}"#) }
        let failed = await store.delete(person)
        XCTAssertFalse(failed)
        XCTAssertNotNil(store.writeFailure)
    }
}
