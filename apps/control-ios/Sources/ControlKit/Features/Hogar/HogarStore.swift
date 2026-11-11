import Foundation

/// Estado de la pestaña Hogar: miembros con tipo y permisos (dos lecturas: `GET home/member` y
/// `GET home/permission`) y gating de «Invitar». Con la guarda `isActive` (patrón de
/// `HomeMembersStore`) una respuesta de otro hogar no pisa el estado.
@Observable
public final class HogarStore {
    public private(set) var rows: [HogarMemberRow] = []
    public private(set) var state: HomeAdminLoadState = .idle
    public private(set) var canInvite = false
    public private(set) var callerRole: String

    private let repo: HomeRepository
    public let homeId: Int
    private let callerAppUserId: Int?
    private let activeHomeId: () -> String?

    /// `homeRole` es el rol del hogar según `GET home` (se usa hasta conocer la fila propia).
    public init(repo: HomeRepository, homeId: Int, homeRole: String, callerAppUserId: Int?,
                activeHomeId: @escaping () -> String?) {
        self.repo = repo
        self.homeId = homeId
        self.callerRole = homeRole
        self.callerAppUserId = callerAppUserId
        self.activeHomeId = activeHomeId
    }

    private var isActive: Bool { activeHomeId() == String(homeId) }

    public func load() async {
        state = .loading
        do {
            async let membersCall = repo.members(homeId: homeId)
            async let permissionsCall = repo.permissions(homeId: homeId)
            let (members, permissions) = try await (membersCall, permissionsCall)
            guard isActive else { return }
            rows = HogarMemberRows.compose(members: members, permissions: permissions, callerAppUserId: callerAppUserId)
            let own = permissions.memberships.first { $0.appUserId == callerAppUserId }
            if let own { callerRole = own.role }
            canInvite = HomeAdminAccess.canInvite(role: callerRole, permissions: own?.permissions ?? [])
            state = .loaded
        } catch {
            guard isActive else { return }
            state = .failed(homeAdminMessage(error))
        }
    }
}
