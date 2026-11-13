import Foundation

/// Estado de carga común de las pantallas de administración.
public enum HomeAdminLoadState: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case failed(String)
}

func homeAdminMessage(_ error: Error) -> String {
    (error as? APIError)?.homeAdminMessage ?? error.localizedDescription
}

func membershipActionMessage(_ error: Error) -> String {
    (error as? APIError)?.membershipActionMessage ?? error.localizedDescription
}

/// Configuración del hogar: detalle y edición de nombre/zona (solo admin).
@Observable
public final class HomeSettingsStore {
    public private(set) var detail: HomeDetailFull?
    public private(set) var state: HomeAdminLoadState = .idle
    public var errorMessage: String?

    private let repo: HomeRepository
    public let homeId: Int
    private let activeHomeId: () -> String?
    private let reloadHome: () async -> Void

    public init(repo: HomeRepository, homeId: Int, activeHomeId: @escaping () -> String?,
                reloadHome: @escaping () async -> Void = {}) {
        self.repo = repo
        self.homeId = homeId
        self.activeHomeId = activeHomeId
        self.reloadHome = reloadHome
    }

    private var isActive: Bool { activeHomeId() == String(homeId) }

    public func load() async {
        state = .loading
        do {
            let result = try await repo.detail(id: homeId)
            guard isActive else { return }
            detail = result
            state = .loaded
        } catch {
            guard isActive else { return }
            state = .failed(homeAdminMessage(error))
        }
    }

    /// Validación de cliente: nombre 1..50 codepoints (recortado); la zona debe estar entre los IANA
    /// conocidos salvo que sea la actual del hogar (que no se envía y el servidor ya aceptó).
    public static func validate(name: String, timezone: String, current: String? = nil) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "El nombre es obligatorio" }
        if trimmed.codepointCount > 50 { return "El nombre admite como máximo 50 caracteres" }
        if timezone != current, !TimeZone.knownTimeZoneIdentifiers.contains(timezone) { return "Zona horaria no válida" }
        return nil
    }

    /// Guarda; `timezone` solo se envía si cambió. Devuelve `true` si se guardó.
    @discardableResult
    public func save(name: String, timezone: String) async -> Bool {
        if let message = Self.validate(name: name, timezone: timezone, current: detail?.timezone) {
            errorMessage = message
            return false
        }
        guard isActive else { return false }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let sentTimezone = (timezone == detail?.timezone) ? nil : timezone
        do {
            let result = try await repo.update(id: homeId, name: trimmed, timezone: sentTimezone)
            guard isActive else { return false }
            detail = result
            await reloadHome()
            return true
        } catch {
            errorMessage = homeAdminMessage(error)
            return false
        }
    }
}

/// Administradores: lista y acciones. Tras salir, transferir o cambiar el propio rol se recarga
/// `homeContext` (la verdad es del servidor).
@Observable
public final class MembershipStore {
    public private(set) var items: [MembershipItem] = []
    public private(set) var state: HomeAdminLoadState = .idle
    public var errorMessage: String?

    private let repo: HomeRepository
    public let homeId: Int
    private let activeHomeId: () -> String?
    private let reloadHome: () async -> Void
    private let callerAppUserId: Int?

    public init(repo: HomeRepository, homeId: Int, callerAppUserId: Int?, activeHomeId: @escaping () -> String?,
                reloadHome: @escaping () async -> Void) {
        self.repo = repo
        self.homeId = homeId
        self.callerAppUserId = callerAppUserId
        self.activeHomeId = activeHomeId
        self.reloadHome = reloadHome
    }

    private var isActive: Bool { activeHomeId() == String(homeId) }

    public func load() async {
        state = .loading
        do {
            let result = try await repo.memberships(homeId: homeId)
            guard isActive else { return }
            items = result
            state = .loaded
        } catch {
            guard isActive else { return }
            state = .failed(homeAdminMessage(error))
        }
    }

    /// Cambia el rol; si es la propia fila, recarga el contexto (el rol cambia el gating).
    public func changeRole(_ item: MembershipItem, to role: String) async {
        guard isActive else { return }
        do {
            _ = try await repo.changeRole(homeId: homeId, membershipId: item.membershipId, role: role)
            if item.appUserId == callerAppUserId { await reloadHome() }
            if isActive { await load() }
        } catch {
            errorMessage = membershipActionMessage(error)
        }
    }

    public func transfer(to item: MembershipItem) async {
        guard isActive else { return }
        if item.appUserId == callerAppUserId {
            errorMessage = "No puedes transferirte la administración a ti mismo"
            return
        }
        do {
            _ = try await repo.transfer(homeId: homeId, toMembershipId: item.membershipId)
            await reloadHome()
            if isActive { await load() }
        } catch {
            errorMessage = homeAdminMessage(error)
        }
    }

    /// Quita una membresía. Si es la propia (salir) recarga el contexto (puede caer a `.noHome`);
    /// si el servidor responde 403 (último admin, etc.) muestra el error y no asume éxito.
    public func remove(_ item: MembershipItem) async {
        guard isActive else { return }
        do {
            try await repo.remove(homeId: homeId, membershipId: item.membershipId)
            if item.appUserId == callerAppUserId {
                await reloadHome()
            } else if isActive {
                await load()
            }
        } catch {
            errorMessage = membershipActionMessage(error)
        }
    }
}

/// Miembros del hogar: lista, alta y edición. La recarga de `homeContext` (`onOwnRowChanged`) solo
/// se dispara cuando `isOwnRow` reconoce la fila editada como la del caller; hoy el payload no
/// identifica esa fila, así que la vista la cablea a `{ _ in false }` hasta 1.15.
@Observable
public final class HomeMembersStore {
    public private(set) var items: [HomeMember] = []
    public private(set) var state: HomeAdminLoadState = .idle
    public var errorMessage: String?

    private let repo: HomeRepository
    public let homeId: Int
    private let activeHomeId: () -> String?
    private let isOwnRow: (HomeMember) -> Bool
    private let onOwnRowChanged: () async -> Void

    public init(repo: HomeRepository, homeId: Int, activeHomeId: @escaping () -> String?,
                isOwnRow: @escaping (HomeMember) -> Bool = { _ in false },
                onOwnRowChanged: @escaping () async -> Void = {}) {
        self.repo = repo
        self.homeId = homeId
        self.activeHomeId = activeHomeId
        self.isOwnRow = isOwnRow
        self.onOwnRowChanged = onOwnRowChanged
    }

    private var isActive: Bool { activeHomeId() == String(homeId) }

    public func load() async {
        state = .loading
        do {
            let result = try await repo.members(homeId: homeId)
            guard isActive else { return }
            items = result
            state = .loaded
        } catch {
            guard isActive else { return }
            state = .failed(homeAdminMessage(error))
        }
    }

    /// Alta (nombre recortado, validado en cliente). `true` si se creó.
    @discardableResult
    public func create(kind: MemberKind, name: String, color: String) async -> Bool {
        if let message = MemberValidation.validate(name: name, color: color) {
            errorMessage = message
            return false
        }
        guard isActive else { return false }
        do {
            _ = try await repo.createMember(homeId: homeId, kind: kind, name: MemberValidation.trimmedName(name), color: color)
            if isActive { await load() }
            return true
        } catch {
            errorMessage = homeAdminMessage(error)
            return false
        }
    }

    /// Edición con solo los campos cambiados. `true` si se guardó (o no había cambios que enviar).
    @discardableResult
    public func update(_ member: HomeMember, kind: MemberKind?, status: MemberStatus?,
                       name: String, color: String?) async -> Bool {
        if let message = MemberValidation.validate(name: name, color: color ?? MemberValidation.defaultColor) {
            errorMessage = message
            return false
        }
        if member.linked && kind == .pet {
            errorMessage = "Una persona vinculada a una cuenta no puede ser mascota"
            return false
        }
        guard let body = MemberRules.makeUpdateBody(original: member, kind: kind, status: status, name: name, color: color) else {
            return true
        }
        guard isActive else { return false }
        do {
            _ = try await repo.updateMember(body)
            if body.kind != nil, isOwnRow(member) { await onOwnRowChanged() }
            if isActive { await load() }
            return true
        } catch {
            errorMessage = homeAdminMessage(error)
            return false
        }
    }
}

/// Accesos: catálogo + permisos por miembro, con borrador.
@Observable
public final class PermissionStore {
    public private(set) var response: PermissionsResponse?
    public private(set) var state: HomeAdminLoadState = .idle
    public var errorMessage: String?

    private let repo: HomeRepository
    public let homeId: Int
    private let activeHomeId: () -> String?

    public init(repo: HomeRepository, homeId: Int, activeHomeId: @escaping () -> String?) {
        self.repo = repo
        self.homeId = homeId
        self.activeHomeId = activeHomeId
    }

    private var isActive: Bool { activeHomeId() == String(homeId) }

    public func load() async {
        state = .loading
        do {
            let result = try await repo.permissions(homeId: homeId)
            guard isActive else { return }
            response = result
            state = .loaded
        } catch {
            guard isActive else { return }
            state = .failed(homeAdminMessage(error))
        }
    }

    /// Envía el estado final completo del borrador. Solo sobre filas `editable && member`.
    @discardableResult
    public func save(item: PermissionItem, draft: PermissionDraft, callerRole: String) async -> Bool {
        guard HomeAdminAccess.isAdmin(role: callerRole) else {
            errorMessage = PermissionRules.memberCallerReason
            return false
        }
        guard item.editable, item.role == "member" else {
            errorMessage = PermissionRules.lockReason(callerRole: callerRole, item: item)
                ?? PermissionRules.fallbackReason
            return false
        }
        guard isActive else { return false }
        do {
            _ = try await repo.setPermissions(homeId: homeId, membershipId: item.membershipId,
                                              permissions: draft.finalPermissions)
            if isActive { await load() }
            return true
        } catch {
            errorMessage = homeAdminMessage(error)
            return false
        }
    }

    /// Restablece al set completo de defaults del tipo del miembro (sin endpoint propio).
    /// Sin condiciones (sin kind, sin defaults, fuera de catálogo, caller no admin) no llama a la red.
    @discardableResult
    public func reset(item: PermissionItem, callerRole: String) async -> Bool {
        guard let response,
              PermissionRules.canReset(callerRole: callerRole, item: item,
                                       defaults: response.defaults, catalog: response.catalog),
              let permissions = PermissionRules.resetPermissions(for: item, defaults: response.defaults,
                                                                 catalog: response.catalog)
        else {
            errorMessage = PermissionRules.lockReason(callerRole: callerRole, item: item)
                ?? "No hay accesos por defecto para este tipo"
            return false
        }
        guard isActive else { return false }
        do {
            _ = try await repo.setPermissions(homeId: homeId, membershipId: item.membershipId,
                                              permissions: permissions)
            if isActive { await load() }
            return true
        } catch {
            errorMessage = homeAdminMessage(error)
            return false
        }
    }
}

/// Auditoría (solo admin): primera página y "Cargar más" por `before_id`.
@Observable
public final class AuditStore {
    public private(set) var items: [AuditItem] = []
    public private(set) var state: HomeAdminLoadState = .idle
    public private(set) var hasMore = false
    public var errorMessage: String?

    private let repo: HomeRepository
    public let homeId: Int
    private let limit: Int
    private let activeHomeId: () -> String?

    public init(repo: HomeRepository, homeId: Int, limit: Int = AuditPager.pageSize,
                activeHomeId: @escaping () -> String?) {
        self.repo = repo
        self.homeId = homeId
        self.limit = limit
        self.activeHomeId = activeHomeId
    }

    private var isActive: Bool { activeHomeId() == String(homeId) }

    public func load() async {
        state = .loading
        do {
            let page = try await repo.audit(homeId: homeId, limit: limit, beforeId: nil)
            guard isActive else { return }
            items = page
            hasMore = AuditPager.hasMore(received: page.count, limit: limit)
            state = .loaded
        } catch {
            guard isActive else { return }
            state = .failed(homeAdminMessage(error))
        }
    }

    public func loadMore() async {
        guard hasMore, let before = AuditPager.nextBeforeId(items: items) else { return }
        do {
            let page = try await repo.audit(homeId: homeId, limit: limit, beforeId: before)
            guard isActive else { return }
            items = AuditPager.merge(items, page)
            hasMore = AuditPager.hasMore(received: page.count, limit: limit)
        } catch {
            errorMessage = homeAdminMessage(error)
        }
    }
}

/// Invitaciones del hogar (1.15b): pendientes, crear y revocar. El código de una invitación nueva
/// vive solo en `createdCode` (memoria): no entra en `items`, ni en logs ni en errores, y se
/// borra con `clearCode()` al cerrar la vista.
@Observable
public final class InvitationStore {
    public private(set) var items: [InvitationItem] = []
    public private(set) var state: HomeAdminLoadState = .idle
    public var errorMessage: String?
    public private(set) var createdCode: String?
    /// Miembros invitables (selector de `member_id`); se rellena con `loadMembers`.
    public private(set) var members: [HomeMember] = []

    private let repo: HomeRepository
    public let homeId: Int
    private let activeHomeId: () -> String?

    public init(repo: HomeRepository, homeId: Int, activeHomeId: @escaping () -> String?) {
        self.repo = repo
        self.homeId = homeId
        self.activeHomeId = activeHomeId
    }

    private var isActive: Bool { activeHomeId() == String(homeId) }

    public func load() async {
        state = .loading
        do {
            let result = try await repo.invitations(homeId: homeId)
            guard isActive else { return }
            items = InvitationRules.visible(result)
            state = .loaded
        } catch {
            guard isActive else { return }
            state = .failed(invitationError(error))
        }
    }

    public func loadMembers() async {
        guard isActive else { return }
        if let result = try? await repo.members(homeId: homeId), isActive {
            members = result
        }
    }

    /// Variante por `memberId` elegido en la UI. Si ese miembro ya no es invitable (p. ej. tras un 400
    /// `Invalid member` y recarga) no se envía nada: nunca cae a una invitación genérica sin confirmación.
    @discardableResult
    public func create(kind: MemberKind?, memberId: Int?, callerRole: String, email: String) async -> Bool {
        guard let memberId else {
            return await create(kind: kind, member: nil, callerRole: callerRole, email: email)
        }
        guard let member = InvitationRules.selectableMembers(members, callerRole: callerRole)
            .first(where: { $0.id == memberId }) else {
            errorMessage = "Ese miembro ya no se puede invitar; elígelo de nuevo"
            return false
        }
        return await create(kind: nil, member: member, callerRole: callerRole, email: email)
    }

    /// Crea la invitación (ligada a `email`) y guarda el código en `createdCode`. `false` si no se
    /// envió o falló.
    @discardableResult
    public func create(kind: MemberKind?, member: HomeMember?, callerRole: String, email: String) async -> Bool {
        guard isActive else { return false }
        guard let body = InvitationRules.makeBody(homeId: homeId, kind: kind, member: member,
                                                  callerRole: callerRole, email: email) else {
            errorMessage = "Revisa el email y el tipo de invitación"
            return false
        }
        do {
            let created = try await repo.createInvitation(body)
            guard isActive else { return false }
            createdCode = created.code
            await load()
            return true
        } catch {
            if (error as? APIError).map({ $0 == .http(status: 400, message: "Invalid member") }) == true {
                await loadMembers()
            }
            errorMessage = invitationError(error)
            return false
        }
    }

    public func revoke(_ item: InvitationItem) async {
        guard isActive else { return }
        do {
            _ = try await repo.revokeInvitation(homeId: homeId, id: item.id)
            if isActive { await load() }
        } catch {
            errorMessage = invitationError(error)
            if isActive, (error as? APIError)?.isNotFound == true { await load() }
        }
    }

    public func clearCode() { createdCode = nil }

    private func invitationError(_ error: Error) -> String {
        (error as? APIError)?.invitationAdminMessage ?? error.localizedDescription
    }
}

/// Resúmenes del menú Administración (E4-04, Nuevo): conteos de administradores, miembros e
/// invitaciones pendientes. Cada uno falla por separado: `nil` = no se pudo cargar.
@Observable
public final class AdminSummaryStore {
    public private(set) var administrators: Int?
    public private(set) var members: Int?
    public private(set) var invitations: Int?
    /// `true` hasta la primera carga: la vista muestra el subtítulo fijo mientras tanto.
    public private(set) var isLoading = true

    private let repo: HomeRepository
    public let homeId: Int
    private let activeHomeId: () -> String?

    public init(repo: HomeRepository, homeId: Int, activeHomeId: @escaping () -> String?) {
        self.repo = repo
        self.homeId = homeId
        self.activeHomeId = activeHomeId
    }

    /// `includeInvitations` = quien mira puede ver Invitaciones (admin o `home.invite`).
    public func load(includeInvitations: Bool) async {
        let memberships = try? await repo.memberships(homeId: homeId)
        let people = try? await repo.members(homeId: homeId)
        var pending: [InvitationItem]?
        if includeInvitations {
            pending = try? await repo.invitations(homeId: homeId)
        }
        guard activeHomeId() == String(homeId) else { return }
        administrators = memberships.map { rows in rows.filter { $0.role == "admin" }.count }
        members = people?.count
        invitations = pending?.count
        isLoading = false
    }
}
