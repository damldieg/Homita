import SwiftUI

private func reload(_ services: AppServices) -> () async -> Void {
    { await services.homeContext.load(using: services.homes) }
}

/// Entrada de administración del hogar: secciones según el rol (`HomeAdminScreenModel`).
struct HomeAdminView: View {
    let services: AppServices
    let home: HomeItem

    /// `home.invite` de la fila propia de `home/membership`; vacío hasta cargar o si falla (A1).
    @State private var ownPermissions: [String] = []

    var body: some View {
        let model = HomeAdminScreenModel(role: home.role, permissions: ownPermissions)
        HomitaForm {
            if model.showSettings {
                NavigationLink {
                    HomeSettingsView(services: services, home: home)
                } label: {
                    HomitaLinkRow(title: "Configuración", systemImage: "gearshape", tint: "#6E6358")
                }
                .buttonStyle(.plain)
            }
            if model.showAdministrators {
                NavigationLink {
                    HomeAdministratorsView(services: services, home: home)
                } label: {
                    HomitaLinkRow(title: "Administradores", systemImage: "person.badge.key", tint: Palette.accentHex)
                }
                .buttonStyle(.plain)
            }
            if model.showMembers {
                NavigationLink {
                    HomeMembersView(services: services, home: home)
                } label: {
                    HomitaLinkRow(title: "Miembros", systemImage: "person.2", tint: Palette.onlineHex)
                }
                .buttonStyle(.plain)
            }
            if model.showInvitations {
                NavigationLink {
                    HomeInvitationsView(services: services, home: home)
                } label: {
                    HomitaLinkRow(title: "Invitaciones", systemImage: "envelope.badge", tint: "#F5A623")
                }
                .buttonStyle(.plain)
            }
            if model.showPermissions {
                NavigationLink {
                    MemberPermissionsView(services: services, home: home)
                } label: {
                    HomitaLinkRow(title: "Accesos", systemImage: "lock.shield", tint: Palette.accentHex)
                }
                .buttonStyle(.plain)
            }
            if model.showAudit {
                NavigationLink {
                    HomeAuditView(services: services, home: home)
                } label: {
                    HomitaLinkRow(title: "Auditoría", systemImage: "list.bullet.clipboard", tint: "#6E6358")
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle(home.name)
        .task { await loadOwnPermissions() }
    }

    /// Permisos propios para decidir "Invitaciones". Un admin no lo necesita (tiene todos).
    private func loadOwnPermissions() async {
        guard !HomeAdminAccess.isAdmin(role: home.role), let callerId = services.session.session?.id else { return }
        let rows = try? await services.homes.memberships(homeId: home.homeId)
        ownPermissions = rows?.first { $0.appUserId == callerId }?.permissions ?? []
    }
}

/// Detalle del hogar; nombre y zona editables solo para admin.
struct HomeSettingsView: View {
    let services: AppServices
    let home: HomeItem

    @State private var store: HomeSettingsStore
    @State private var name = ""
    @State private var timezone = ""
    @State private var showZones = false

    init(services: AppServices, home: HomeItem) {
        self.services = services
        self.home = home
        let homeContext = services.homeContext
        _store = State(initialValue: HomeSettingsStore(
            repo: services.homes, homeId: home.homeId,
            activeHomeId: { homeContext.activeHomeId },
            reloadHome: { await homeContext.load(using: services.homes) }
        ))
    }

    private var canEdit: Bool { HomeAdminAccess.canEditSettings(role: home.role) }

    var body: some View {
        HomitaForm {
            switch store.state {
            case .idle, .loading:
                HomeLoadingView()
            case .failed(let message):
                HomeErrorView(message: message) { Task { await store.load() } }
            case .loaded:
                if let detail = store.detail {
                    HomitaPanel("Hogar", systemImage: "house") {
                        if canEdit {
                            HomitaField(placeholder: "Nombre", text: $name)
                            Button {
                                showZones = true
                            } label: {
                                HomitaLabeledRow("Zona horaria") {
                                    Text(timezone).font(HomitaFont.geist(15, relativeTo: .body)).foregroundStyle(Palette.inkSoft)
                                    Image(systemName: "chevron.right").foregroundStyle(Palette.inkMuted)
                                }
                            }
                            .buttonStyle(.plain)
                        } else {
                            HomitaLabeledRow("Nombre") { Text(detail.name).foregroundStyle(Palette.inkSoft) }
                            HomitaLabeledRow("Zona horaria") { Text(detail.timezone).foregroundStyle(Palette.inkSoft) }
                        }
                        if detail.isPersonal {
                            HomitaFootnote(text: "Hogar personal")
                        }
                    }
                    HomitaPanel("Registro", systemImage: "clock") {
                        HomitaLabeledRow("Creado") { Text(detail.createdAt).foregroundStyle(Palette.inkSoft) }
                        HomitaLabeledRow("Actualizado") { Text(detail.updatedAt).foregroundStyle(Palette.inkSoft) }
                    }
                    if canEdit {
                        HomitaButton(title: "Guardar cambios") {
                            Task { await store.save(name: name, timezone: timezone) }
                        }
                    }
                }
            }
        }
        .navigationTitle("Configuración")
        .errorAlert($store.errorMessage)
        .sheet(isPresented: $showZones) {
            NavigationStack { TimeZonePickerView(selection: $timezone, current: store.detail?.timezone ?? "") }
        }
        .task {
            await store.load()
            if let detail = store.detail {
                name = detail.name
                timezone = detail.timezone
            }
        }
    }
}

/// Selector de zona IANA con búsqueda (sin texto libre: evita `400 Invalid timezone`).
struct TimeZonePickerView: View {
    @Binding var selection: String
    var current: String = ""
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var identifiers: [String] {
        var all = TimeZone.knownTimeZoneIdentifiers
        if !current.isEmpty, !all.contains(current) { all.append(current) }
        all.sort()
        guard !query.isEmpty else { return all }
        return all.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        List(identifiers, id: \.self) { id in
            Button {
                selection = id
                dismiss()
            } label: {
                HomitaLabeledRow(id) {
                    if id == selection {
                        Image(systemName: "checkmark").foregroundStyle(Palette.accent)
                    }
                }
            }
            .buttonStyle(.plain)
            .homitaRow()
        }
        .homitaList()
        .searchable(text: $query)
        .navigationTitle("Zona horaria")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cerrar") { dismiss() }
                    .foregroundStyle(Palette.ink)
            }
        }
    }
}

/// Administradores y membresías. Las acciones salen de `HomeAdminAccess.rowActions`.
struct HomeAdministratorsView: View {
    let services: AppServices
    let home: HomeItem

    @State private var store: MembershipStore
    @State private var pending: (MembershipRowAction, MembershipItem)?

    init(services: AppServices, home: HomeItem) {
        self.services = services
        self.home = home
        let homeContext = services.homeContext
        _store = State(initialValue: MembershipStore(
            repo: services.homes, homeId: home.homeId,
            callerAppUserId: services.session.session?.id,
            activeHomeId: { homeContext.activeHomeId },
            reloadHome: reload(services)
        ))
    }

    private var callerId: Int? { services.session.session?.id }

    var body: some View {
        HomitaForm {
            switch store.state {
            case .idle, .loading:
                HomeLoadingView()
            case .failed(let message):
                HomeErrorView(message: message) { Task { await store.load() } }
            case .loaded:
                HomitaPanel("Personas del hogar", systemImage: "person.badge.key", count: store.items.count) {
                    ForEach(store.items, id: \.membershipId) { item in
                        row(item)
                    }
                }
            }
        }
        .navigationTitle("Administradores")
        .refreshable { await store.load() }
        .errorAlert($store.errorMessage)
        .homitaConfirm(confirmationTitle, isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                       confirmTitle: pending.map { confirmationButton($0.0) } ?? "Confirmar") {
            if let (action, item) = pending {
                Task { await perform(action, item) }
            }
        }
        .task { await store.load() }
    }

    @ViewBuilder
    private func row(_ item: MembershipItem) -> some View {
        let actions = HomeAdminAccess.rowActions(
            callerRole: home.role, row: item, callerAppUserId: callerId, isPersonal: home.isPersonal,
            adminCount: store.items.filter { $0.role == "admin" }.count
        )
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(item.name)
                    .font(HomitaFont.geist(17, weight: .medium, relativeTo: .body))
                    .foregroundStyle(Palette.ink)
                if item.appUserId == callerId {
                    Text("(tú)").font(HomitaFont.geist(14, relativeTo: .footnote)).foregroundStyle(Palette.inkSoft)
                }
                Spacer()
                HomitaBadge(title: item.role == "admin" ? "Administrador" : "Miembro",
                            tintHex: item.role == "admin" ? Palette.accentHex : "#6E6358")
            }
            Text(item.email)
                .font(HomitaFont.geist(13, relativeTo: .footnote))
                .foregroundStyle(Palette.inkSoft)
            if !actions.isEmpty {
                HStack(spacing: 8) {
                    if actions.contains(.promote) {
                        HomitaChipButton(title: "Hacer admin") { request(.promote, item) }
                    }
                    if actions.contains(.demote) {
                        HomitaChipButton(title: "Quitar admin") { request(.demote, item) }
                    }
                    if actions.contains(.transfer) {
                        HomitaChipButton(title: "Transferir") { request(.transfer, item) }
                    }
                    if actions.contains(.remove) {
                        HomitaChipButton(title: "Quitar", kind: .destructive) { request(.remove, item) }
                    }
                    if actions.contains(.leave) {
                        HomitaChipButton(title: "Salir", kind: .destructive) { request(.leave, item) }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func request(_ action: MembershipRowAction, _ item: MembershipItem) {
        if HomeAdminAccess.requiresConfirmation(action: action) {
            pending = (action, item)
        } else {
            Task { await perform(action, item) }
        }
    }

    private func perform(_ action: MembershipRowAction, _ item: MembershipItem) async {
        switch action {
        case .promote: await store.changeRole(item, to: "admin")
        case .demote: await store.changeRole(item, to: "member")
        case .transfer: await store.transfer(to: item)
        case .remove, .leave: await store.remove(item)
        case .editPermissions, .resetPermissions: break
        }
    }

    private var confirmationTitle: String {
        guard let (action, item) = pending else { return "" }
        switch action {
        case .remove: return "¿Quitar a \(item.name) del hogar?"
        case .leave: return "¿Salir de este hogar?"
        case .transfer: return "¿Transferir la administración a \(item.name)? Pasarás a ser miembro."
        case .demote: return "¿Quitar el rol de administrador a \(item.name)?"
        default: return ""
        }
    }

    private func confirmationButton(_ action: MembershipRowAction) -> String {
        switch action {
        case .remove: return "Quitar"
        case .leave: return "Salir"
        case .transfer: return "Transferir"
        default: return "Confirmar"
        }
    }
}

/// Accesos por miembro (solo admin): grupos por `domain`; admins no editables.
struct MemberPermissionsView: View {
    let services: AppServices
    let home: HomeItem

    @State private var store: PermissionStore
    @State private var editing: PermissionItem?

    init(services: AppServices, home: HomeItem) {
        self.services = services
        self.home = home
        let homeContext = services.homeContext
        _store = State(initialValue: PermissionStore(
            repo: services.homes, homeId: home.homeId, activeHomeId: { homeContext.activeHomeId }
        ))
    }

    var body: some View {
        HomitaForm {
            switch store.state {
            case .idle, .loading:
                HomeLoadingView()
            case .failed(let message):
                HomeErrorView(message: message) { Task { await store.load() } }
            case .loaded:
                HomitaPanel("Accesos por persona", systemImage: "lock.shield", count: store.response?.memberships.count ?? 0) {
                    ForEach(store.response?.memberships ?? [], id: \.membershipId) { item in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                    .font(HomitaFont.geist(17, weight: .medium, relativeTo: .body))
                                    .foregroundStyle(Palette.ink)
                                Text(item.role == "admin" ? "Administrador: todos los accesos" : "\(item.permissions.count) accesos")
                                    .font(HomitaFont.geist(13, relativeTo: .footnote))
                                    .foregroundStyle(Palette.inkSoft)
                                if let reason = PermissionRules.lockReason(callerRole: home.role, item: item),
                                   item.role != "admin" {
                                    Text(reason)
                                        .font(HomitaFont.geist(12, relativeTo: .caption))
                                        .foregroundStyle(Palette.inkMuted)
                                }
                            }
                            Spacer()
                            if item.editable && item.role == "member" && HomeAdminAccess.isAdmin(role: home.role) {
                                HomitaChipButton(title: "Editar") { editing = item }
                            }
                        }
                    }
                }
                kindSummary
            }
        }
        .navigationTitle("Accesos")
        .refreshable { await store.load() }
        .errorAlert(Binding(get: { editing == nil ? store.errorMessage : nil },
                            set: { store.errorMessage = $0 }))
        .sheet(item: Binding(get: { editing.map { IdentifiedPermission(item: $0) } },
                             set: { editing = $0?.item })) { wrapper in
            NavigationStack {
                PermissionEditorView(store: store, item: wrapper.item, callerRole: home.role)
            }
        }
        .task { await store.load() }
    }

    /// Resumen solo lectura de qué cubre cada tipo; oculto sin defaults.
    @ViewBuilder
    private var kindSummary: some View {
        let summary = PermissionRules.kindSummary(defaults: store.response?.defaults ?? [],
                                                  catalog: store.response?.catalog ?? [])
        if !summary.isEmpty {
            HomitaPanel("Qué cubre cada tipo", systemImage: "questionmark.circle", tint: Palette.inkSoft) {
                ForEach(summary, id: \.kind) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(MemberRules.kindLabel(entry.kind))
                            .font(HomitaFont.geist(17, weight: .medium, relativeTo: .body))
                            .foregroundStyle(Palette.ink)
                        Text(entry.domains.map { "\($0.domain): \($0.codes.joined(separator: ", "))" }
                            .joined(separator: " · "))
                            .font(HomitaFont.geist(13, relativeTo: .footnote))
                            .foregroundStyle(Palette.inkSoft)
                    }
                }
            }
        }
    }
}

struct IdentifiedPermission: Identifiable {
    let item: PermissionItem
    var id: Int { item.membershipId }
}

struct PermissionEditorView: View {
    let store: PermissionStore
    let item: PermissionItem
    let callerRole: String

    @Environment(\.dismiss) private var dismiss
    @State private var draft: PermissionDraft
    @State private var confirmingReset = false

    init(store: PermissionStore, item: PermissionItem, callerRole: String) {
        self.store = store
        self.item = item
        self.callerRole = callerRole
        _draft = State(initialValue: PermissionDraft(permissions: item.permissions))
    }

    var body: some View {
        let catalog = store.response?.catalog ?? []
        let unknown = PermissionRules.unknownCodes(item: item, catalog: catalog)
        let canReset = PermissionRules.canReset(callerRole: callerRole, item: item,
                                                defaults: store.response?.defaults ?? [], catalog: catalog)
        HomitaForm {
            if !unknown.isEmpty {
                HomitaErrorText(text: "Este miembro tiene accesos no reconocidos (\(unknown.joined(separator: ", "))). Guardar puede fallar.")
            }
            ForEach(groupedCatalog(catalog), id: \.domain) { group in
                HomitaPanel(group.domain, systemImage: "square.grid.2x2") {
                    ForEach(group.entries, id: \.code) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            HomitaToggle(title: entry.description, isOn: Binding(
                                get: { draft.isOn(entry.code) },
                                set: { _ in draft.toggle(entry.code) }
                            ))
                            Text(entry.code)
                                .font(HomitaFont.mono(11, relativeTo: .caption2))
                                .foregroundStyle(Palette.inkMuted)
                        }
                    }
                }
            }
            if canReset {
                HomitaButton(title: "Restablecer a tipo", kind: .secondary) { confirmingReset = true }
            }
        }
        .navigationTitle(item.name)
        .errorAlert(Binding(get: { store.errorMessage }, set: { store.errorMessage = $0 }))
        .homitaConfirm("Se sobrescribirán los accesos personalizados de \(item.name) con los de su tipo.",
                       isPresented: $confirmingReset, confirmTitle: "Restablecer") {
            Task { if await store.reset(item: item, callerRole: callerRole) { dismiss() } }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancelar") { dismiss() }
                    .foregroundStyle(Palette.ink)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Guardar") {
                    Task { if await store.save(item: item, draft: draft, callerRole: callerRole) { dismiss() } }
                }
                .disabled(!draft.isDirty)
                .foregroundStyle(Palette.ink)
            }
        }
    }
}

/// Auditoría (solo admin) con "Cargar más".
struct HomeAuditView: View {
    let services: AppServices
    let home: HomeItem

    @State private var store: AuditStore

    init(services: AppServices, home: HomeItem) {
        self.services = services
        self.home = home
        let homeContext = services.homeContext
        _store = State(initialValue: AuditStore(
            repo: services.homes, homeId: home.homeId, activeHomeId: { homeContext.activeHomeId }
        ))
    }

    var body: some View {
        HomitaForm {
            if !HomeAdminAccess.canViewAudit(role: home.role) {
                HomitaFootnote(text: "Solo un administrador puede ver la auditoría")
            } else {
                switch store.state {
                case .idle, .loading:
                    HomeLoadingView()
                case .failed(let message):
                    HomeErrorView(message: message) { Task { await store.load() } }
                case .loaded:
                    ForEach(store.items, id: \.id) { item in
                        HomitaCard {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.action)
                                    .font(HomitaFont.geist(16, weight: .semibold, relativeTo: .body))
                                    .foregroundStyle(Palette.ink)
                                Text("\(item.actorName ?? "Sistema") · \(item.createdAt)")
                                    .font(HomitaFont.geist(13, relativeTo: .footnote))
                                    .foregroundStyle(Palette.inkSoft)
                                ForEach(item.payload.lines, id: \.self) { line in
                                    Text(line)
                                        .font(HomitaFont.geist(12, relativeTo: .caption))
                                        .foregroundStyle(Palette.inkMuted)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    if store.hasMore {
                        HomitaButton(title: "Cargar más", kind: .secondary) { Task { await store.loadMore() } }
                    }
                }
            }
        }
        .navigationTitle("Auditoría")
        .refreshable { await store.load() }
        .errorAlert($store.errorMessage)
        .task { if HomeAdminAccess.canViewAudit(role: home.role) { await store.load() } }
    }
}

extension HomeMember: Identifiable {}

/// Miembros del hogar. Solo lectura salvo para admin (alta y edición).
struct HomeMembersView: View {
    let services: AppServices
    let home: HomeItem

    @State private var store: HomeMembersStore
    @State private var showCreate = false
    @State private var memberToEdit: HomeMember?

    init(services: AppServices, home: HomeItem) {
        self.services = services
        self.home = home
        let homeContext = services.homeContext
        // Deuda 1.15: el payload no identifica la fila del caller; `isOwnRow` nunca dispara la recarga.
        _store = State(initialValue: HomeMembersStore(
            repo: services.homes, homeId: home.homeId,
            activeHomeId: { homeContext.activeHomeId },
            isOwnRow: { _ in false },
            onOwnRowChanged: reload(services)
        ))
    }

    private var model: HomeAdminScreenModel { HomeAdminScreenModel(role: home.role) }

    var body: some View {
        HomitaForm {
            switch store.state {
            case .idle, .loading:
                HomeLoadingView()
            case .failed(let message):
                HomeErrorView(message: message) { Task { await store.load() } }
            case .loaded:
                HomitaPanel("Miembros", systemImage: "person.2", count: store.items.count) {
                    ForEach(store.items) { member in
                        if model.canEditMembers {
                            Button { memberToEdit = member } label: { row(member) }
                                .buttonStyle(.plain)
                        } else {
                            row(member)
                        }
                    }
                    if store.items.isEmpty {
                        HomitaFootnote(text: "Sin miembros")
                    }
                }
            }
        }
        .navigationTitle("Miembros")
        .toolbar {
            if model.canCreateMembers {
                ToolbarItem(placement: .primaryAction) {
                    Button { showCreate = true } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(Palette.ink)
                            .accessibilityLabel("Agregar")
                    }
                }
            }
        }
        .refreshable { await store.load() }
        .errorAlert($store.errorMessage)
        .sheet(isPresented: $showCreate) {
            NavigationStack { MemberEditorView(store: store, editing: nil) }
        }
        .sheet(item: $memberToEdit) { member in
            NavigationStack { MemberEditorView(store: store, editing: member) }
        }
        .task { await store.load() }
    }

    private func row(_ member: HomeMember) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(hex: member.color ?? MemberValidation.defaultColor))
                .frame(width: 14, height: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text(member.name)
                    .font(HomitaFont.geist(17, weight: .medium, relativeTo: .body))
                    .foregroundStyle(Palette.ink)
                Text("\(MemberRules.kindLabel(member.kind)) · \(MemberRules.statusLabel(member.status)) · \(MemberRules.linkStatusLabel(linked: member.linked))")
                    .font(HomitaFont.geist(13, relativeTo: .footnote))
                    .foregroundStyle(Palette.inkSoft)
            }
            Spacer()
        }
        .opacity(member.status == MemberStatus.inactive.rawValue ? 0.6 : 1)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

/// Editor de miembro (alta si `editing == nil`). Cambiar el tipo de un vinculado pide confirmación.
struct MemberEditorView: View {
    let store: HomeMembersStore
    let editing: HomeMember?

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var color: Color
    /// nil = valor original desconocido del servidor sin elegir: no se envía.
    @State private var kind: MemberKind?
    @State private var status: MemberStatus?
    @State private var colorTouched = false
    @State private var isWorking = false
    @State private var confirmReset = false

    init(store: HomeMembersStore, editing: HomeMember?) {
        self.store = store
        self.editing = editing
        _name = State(initialValue: editing?.name ?? "")
        _color = State(initialValue: Color(hex: editing?.color ?? MemberValidation.defaultColor))
        _kind = State(initialValue: editing.map { MemberKind(rawValue: $0.kind) } ?? .adult)
        _status = State(initialValue: editing.map { MemberStatus(rawValue: $0.status) } ?? .active)
    }

    private var linked: Bool { editing?.linked ?? false }

    var body: some View {
        HomitaForm {
            HomitaPanel("Miembro", systemImage: "person.crop.circle") {
                HomitaField(placeholder: "Nombre (1-50)", text: $name)
                ColorPicker("Color", selection: $color, supportsOpacity: false)
                    .font(HomitaFont.geist(17, weight: .medium, relativeTo: .body))
                    .foregroundStyle(Palette.ink)
                    .onChange(of: color) { colorTouched = true }
                Text("Tipo")
                    .font(HomitaFont.geist(14, weight: .semibold, relativeTo: .footnote))
                    .foregroundStyle(Palette.inkSoft)
                HomitaRadioGroup(
                    selection: $kind,
                    items: MemberRules.availableKinds(linked: linked).map { (id: $0, title: MemberRules.kindLabel($0.rawValue)) }
                )
                if kind == nil, let editing {
                    HomitaFootnote(text: "\(editing.kind) (sin cambiar)")
                }
                if let editing {
                    Text("Estado")
                        .font(HomitaFont.geist(14, weight: .semibold, relativeTo: .footnote))
                        .foregroundStyle(Palette.inkSoft)
                    HomitaRadioGroup(
                        selection: $status,
                        items: MemberStatus.allCases.map { (id: $0, title: MemberRules.statusLabel($0.rawValue)) }
                    )
                    if status == nil {
                        HomitaFootnote(text: "\(editing.status) (sin cambiar)")
                    }
                    HomitaLabeledRow("Cuenta") {
                        Text(MemberRules.linkStatusLabel(linked: linked)).foregroundStyle(Palette.inkSoft)
                    }
                }
            }
            HomitaButton(
                title: editing == nil ? "Agregar" : "Guardar",
                isEnabled: !MemberValidation.trimmedName(name).isEmpty && !isWorking,
                isLoading: isWorking
            ) {
                saveTapped()
            }
        }
        .navigationTitle(editing == nil ? "Nuevo miembro" : "Editar miembro")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancelar") { dismiss() }
                    .foregroundStyle(Palette.ink)
            }
        }
        .homitaConfirm("Cambiar el tipo restablece los permisos de esta persona a los valores del nuevo tipo",
                       isPresented: $confirmReset, confirmTitle: "Cambiar tipo") {
            Task { await save() }
        }
        .errorAlert(Binding(get: { store.errorMessage }, set: { store.errorMessage = $0 }))
    }

    private func saveTapped() {
        if let editing, MemberRules.needsPermissionResetWarning(member: editing, newKind: kind) {
            confirmReset = true
        } else {
            Task { await save() }
        }
    }

    private func save() async {
        isWorking = true
        defer { isWorking = false }
        let ok: Bool
        if let editing {
            ok = await store.update(editing, kind: kind, status: status, name: name,
                                    color: colorTouched ? color.hexString : nil)
        } else {
            ok = await store.create(kind: kind ?? .adult, name: name, color: color.hexString)
        }
        if ok { dismiss() }
    }
}

extension InvitationItem: Identifiable {}

/// Invitaciones pendientes del hogar: crear (código visible una sola vez, copiable) y revocar.
struct HomeInvitationsView: View {
    let services: AppServices
    let home: HomeItem

    @State private var store: InvitationStore
    @State private var showCreate = false
    @State private var toRevoke: InvitationItem?

    init(services: AppServices, home: HomeItem) {
        self.services = services
        self.home = home
        let homeContext = services.homeContext
        _store = State(initialValue: InvitationStore(
            repo: services.homes, homeId: home.homeId,
            activeHomeId: { homeContext.activeHomeId }
        ))
    }

    var body: some View {
        HomitaForm {
            switch store.state {
            case .idle, .loading:
                HomeLoadingView()
            case .failed(let message):
                HomeErrorView(message: message) { Task { await store.load() } }
            case .loaded:
                HomitaPanel("Pendientes", systemImage: "envelope.badge", count: store.items.count) {
                    ForEach(store.items) { item in
                        row(item)
                    }
                    if store.items.isEmpty {
                        HomitaFootnote(text: "Sin invitaciones pendientes")
                    }
                }
            }
        }
        .navigationTitle("Invitaciones")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showCreate = true } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(Palette.ink)
                        .accessibilityLabel("Crear invitación")
                }
            }
        }
        .refreshable { await store.load() }
        .errorAlert($store.errorMessage)
        .sheet(isPresented: $showCreate) {
            NavigationStack { InvitationCreateView(store: store, callerRole: home.role, homeName: home.name) }
        }
        .homitaConfirm("¿Revocar la invitación? El código dejará de funcionar.",
                       isPresented: Binding(get: { toRevoke != nil }, set: { if !$0 { toRevoke = nil } }),
                       confirmTitle: "Revocar") {
            if let item = toRevoke {
                Task { await store.revoke(item) }
            }
        }
        .task { await store.load() }
        .onDisappear { store.clearCode() }
    }

    private func row(_ item: InvitationItem) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.memberName ?? MemberRules.kindLabel(item.kind))
                    .font(HomitaFont.geist(17, weight: .medium, relativeTo: .body))
                    .foregroundStyle(Palette.ink)
                Text("\(MemberRules.kindLabel(item.kind)) · caduca \(item.expiresAt)")
                    .font(HomitaFont.geist(13, relativeTo: .footnote))
                    .foregroundStyle(Palette.inkSoft)
            }
            Spacer()
            HomitaChipButton(title: "Revocar", kind: .destructive) { toRevoke = item }
        }
        .padding(.vertical, 4)
    }
}

/// Hoja de creación: tipo (según rol) y miembro sin cuenta opcional.
struct InvitationCreateView: View {
    let store: InvitationStore
    let callerRole: String
    let homeName: String

    @Environment(\.dismiss) private var dismiss
    @State private var kind: MemberKind
    @State private var memberId: Int?
    @State private var isWorking = false

    init(store: InvitationStore, callerRole: String, homeName: String) {
        self.store = store
        self.callerRole = callerRole
        self.homeName = homeName
        _kind = State(initialValue: InvitationRules.allowedKinds(callerRole: callerRole).first ?? .guest)
    }

    private var selectable: [HomeMember] {
        InvitationRules.selectableMembers(store.members, callerRole: callerRole)
    }

    var body: some View {
        Group {
            if let code = store.createdCode {
                codeForm(code)
            } else {
                form
            }
        }
        .navigationTitle(store.createdCode == nil ? "Nueva invitación" : "Invitación creada")
        .errorAlert(Binding(get: { store.errorMessage }, set: { store.errorMessage = $0 }))
        .task { await store.loadMembers() }
        // El código sobrevive hasta que el usuario cierra la hoja; aquí se borra.
        .onDisappear { store.clearCode() }
        .onChange(of: selectable.map(\.id)) { _, ids in
            if let id = memberId, !ids.contains(id) { memberId = nil }
        }
    }

    private func codeForm(_ code: String) -> some View {
        HomitaForm {
            HomitaPanel("Código", systemImage: "ticket") {
                Text(code)
                    .font(HomitaFont.mono(20))
                    .foregroundStyle(Palette.ink)
                    .textSelection(.enabled)
                HomitaFootnote(text: "Solo se muestra una vez. Compártelo con la persona invitada; caduca en 7 días.")
            }
            HomitaButton(title: "Copiar código", kind: .secondary) { copy(code) }
            ShareLink(item: Self.inviteMessage(code: code, homeName: homeName)) {
                Label("Compartir invitación", systemImage: "square.and.arrow.up")
                    .font(HomitaFont.geist(17, weight: .semibold, relativeTo: .body))
                    .foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Palette.card, in: RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Palette.line, lineWidth: 1.5))
            }
            .accessibilityHint("Abre las opciones para enviar el código por mensaje, correo u otra app")
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Listo") { store.clearCode(); dismiss() }
                    .foregroundStyle(Palette.ink)
            }
        }
    }

    /// Texto que se envía: explica qué hacer al recibirlo, sin depender de que el código se entienda solo.
    static func inviteMessage(code: String, homeName: String) -> String {
        "Te invito a unirte a mi hogar «\(homeName)» en Homita.\n\n"
            + "1. Abre Homita y entra con tu cuenta (o crea una).\n"
            + "2. Ve a Perfil › Unirse a un hogar con un código.\n"
            + "3. Pega este código: \(code)\n\n"
            + "El código caduca en 7 días y solo sirve una vez."
    }

    private func copy(_ text: String?) {
        guard let text else { return }
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }

    private var form: some View {
        HomitaForm {
            HomitaPanel("Tipo", systemImage: "person.crop.circle.badge.questionmark") {
                HomitaRadioGroup(
                    selection: Binding(get: { kind }, set: { kind = $0 ?? kind }),
                    items: InvitationRules.allowedKinds(callerRole: callerRole).map { (id: $0, title: MemberRules.kindLabel($0.rawValue)) }
                )
                .disabled(memberId != nil)
            }
            HomitaPanel("Vincular a un miembro (opcional)", systemImage: "link") {
                HomitaRadioGroup(
                    selection: Binding(get: { memberId ?? Self.noMember }, set: { memberId = ($0 == Self.noMember) ? nil : $0 }),
                    items: [(id: Self.noMember, title: "Ninguno")] + selectable.map { (id: $0.id, title: "\($0.name) · \(MemberRules.kindLabel($0.kind))") }
                )
                HomitaFootnote(text: "Solo miembros sin cuenta. Al aceptar, la cuenta queda vinculada a ese miembro.")
            }
            HomitaButton(title: "Crear", isEnabled: !isWorking, isLoading: isWorking) {
                Task { await create() }
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancelar") { dismiss() }
                    .foregroundStyle(Palette.ink)
            }
        }
    }

    /// «Ninguno» en el selector de miembro (no es un id real).
    private static let noMember = -1

    private func create() async {
        isWorking = true
        defer { isWorking = false }
        let ok = await store.create(kind: memberId == nil ? kind : nil, memberId: memberId, callerRole: callerRole)
        // Miembro ya no invitable (400 o lista recargada): se reelige, nunca se manda genérico.
        if !ok, let id = memberId, !selectable.contains(where: { $0.id == id }) { memberId = nil }
    }
}
