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
    public func save(item: PermissionItem, draft: PermissionDraft) async -> Bool {
        guard item.editable, item.role == "member" else {
            errorMessage = "Este miembro no admite edición de accesos"
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
