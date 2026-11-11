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
        List {
            if model.showSettings {
                NavigationLink {
                    HomeSettingsView(services: services, home: home)
                } label: {
                    Label("Configuración", systemImage: "gearshape")
                }
            }
            if model.showAdministrators {
                NavigationLink {
                    HomeAdministratorsView(services: services, home: home)
                } label: {
                    Label("Administradores", systemImage: "person.badge.key")
                }
            }
            if model.showMembers {
                NavigationLink {
                    HomeMembersView(services: services, home: home)
                } label: {
                    Label("Miembros", systemImage: "person.2")
                }
            }
            if model.showInvitations {
                NavigationLink {
                    HomeInvitationsView(services: services, home: home)
                } label: {
                    Label("Invitaciones", systemImage: "envelope.badge")
                }
            }
            if model.showPermissions {
                NavigationLink {
                    MemberPermissionsView(services: services, home: home)
                } label: {
                    Label("Accesos", systemImage: "lock.shield")
                }
            }
            if model.showAudit {
                NavigationLink {
                    HomeAuditView(services: services, home: home)
                } label: {
                    Label("Auditoría", systemImage: "list.bullet.clipboard")
                }
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
        Form {
            switch store.state {
            case .idle, .loading:
                HomeLoadingView()
            case .failed(let message):
                HomeErrorView(message: message) { Task { await store.load() } }
            case .loaded:
                if let detail = store.detail {
                    Section("Hogar") {
                        if canEdit {
                            TextField("Nombre", text: $name)
                        } else {
                            LabeledContent("Nombre", value: detail.name)
                        }
                        if canEdit {
                            Button {
                                showZones = true
                            } label: {
                                LabeledContent("Zona horaria", value: timezone)
                            }
                        } else {
                            LabeledContent("Zona horaria", value: detail.timezone)
                        }
                        if detail.isPersonal {
                            Text("Hogar personal").foregroundStyle(.secondary)
                        }
                    }
                    Section {
                        LabeledContent("Creado", value: detail.createdAt)
                        LabeledContent("Actualizado", value: detail.updatedAt)
                    }
                    if canEdit {
                        Section {
                            Button("Guardar cambios") {
                                Task { await store.save(name: name, timezone: timezone) }
                            }
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
                HStack {
                    Text(id)
                    Spacer()
                    if id == selection { Image(systemName: "checkmark") }
                }
            }
        }
        .searchable(text: $query)
        .navigationTitle("Zona horaria")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() } }
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
        List {
            switch store.state {
            case .idle, .loading:
                HomeLoadingView()
            case .failed(let message):
                HomeErrorView(message: message) { Task { await store.load() } }
            case .loaded:
                ForEach(store.items, id: \.membershipId) { item in
                    row(item)
                }
            }
        }
        .navigationTitle("Administradores")
        .refreshable { await store.load() }
        .errorAlert($store.errorMessage)
        .confirmationDialog(
            confirmationTitle,
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
            titleVisibility: .visible
        ) {
            if let (action, item) = pending {
                Button(confirmationButton(action), role: .destructive) {
                    Task { await perform(action, item) }
                }
            }
            Button("Cancelar", role: .cancel) {}
        }
        .task { await store.load() }
    }

    @ViewBuilder
    private func row(_ item: MembershipItem) -> some View {
        let actions = HomeAdminAccess.rowActions(
            callerRole: home.role, row: item, callerAppUserId: callerId, isPersonal: home.isPersonal,
            adminCount: store.items.filter { $0.role == "admin" }.count
        )
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(item.name)
                if item.appUserId == callerId { Text("(tú)").foregroundStyle(.secondary) }
                Spacer()
                Text(item.role == "admin" ? "Administrador" : "Miembro")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(item.email).font(.caption).foregroundStyle(.secondary)
            if !actions.isEmpty {
                HStack {
                    if actions.contains(.promote) {
                        Button("Hacer admin") { request(.promote, item) }
                    }
                    if actions.contains(.demote) {
                        Button("Quitar admin") { request(.demote, item) }
                    }
                    if actions.contains(.transfer) {
                        Button("Transferir") { request(.transfer, item) }
                    }
                    if actions.contains(.remove) {
                        Button("Quitar", role: .destructive) { request(.remove, item) }
                    }
                    if actions.contains(.leave) {
                        Button("Salir", role: .destructive) { request(.leave, item) }
                    }
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
        }
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
        List {
            switch store.state {
            case .idle, .loading:
                HomeLoadingView()
            case .failed(let message):
                HomeErrorView(message: message) { Task { await store.load() } }
            case .loaded:
                ForEach(store.response?.memberships ?? [], id: \.membershipId) { item in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(item.name)
                            Text(item.role == "admin" ? "Administrador: todos los accesos" : "\(item.permissions.count) accesos")
                                .font(.caption).foregroundStyle(.secondary)
                            if let reason = PermissionRules.lockReason(callerRole: home.role, item: item),
                               item.role != "admin" {
                                Text(reason).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if item.editable && item.role == "member" && HomeAdminAccess.isAdmin(role: home.role) {
                            Button("Editar") { editing = item }.buttonStyle(.borderless)
                        }
                    }
                }
                kindSummarySection
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
}

extension MemberPermissionsView {
    /// Resumen solo lectura de qué cubre cada tipo; oculto sin defaults.
    @ViewBuilder
    fileprivate var kindSummarySection: some View {
        let summary = PermissionRules.kindSummary(defaults: store.response?.defaults ?? [],
                                                  catalog: store.response?.catalog ?? [])
        if !summary.isEmpty {
            Section("Qué cubre cada tipo") {
                ForEach(summary, id: \.kind) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(MemberRules.kindLabel(entry.kind))
                        Text(entry.domains.map { "\($0.domain): \($0.codes.joined(separator: ", "))" }
                            .joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
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
        Form {
            if !unknown.isEmpty {
                Section {
                    EmptyView()
                } footer: {
                    Text("Este miembro tiene accesos no reconocidos (\(unknown.joined(separator: ", "))). Guardar puede fallar.")
                        .foregroundStyle(.orange)
                }
            }
            ForEach(groupedCatalog(catalog), id: \.domain) { group in
                Section(group.domain) {
                    ForEach(group.entries, id: \.code) { entry in
                        Toggle(isOn: Binding(get: { draft.isOn(entry.code) }, set: { _ in draft.toggle(entry.code) })) {
                            VStack(alignment: .leading) {
                                Text(entry.description)
                                Text(entry.code).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            if canReset {
                Section {
                    Button("Restablecer a tipo", role: .destructive) { confirmingReset = true }
                }
            }
        }
        .navigationTitle(item.name)
        .errorAlert(Binding(get: { store.errorMessage }, set: { store.errorMessage = $0 }))
        .confirmationDialog(
            "Se sobrescribirán los accesos personalizados de \(item.name) con los de su tipo.",
            isPresented: $confirmingReset,
            titleVisibility: .visible
        ) {
            Button("Restablecer", role: .destructive) {
                Task { if await store.reset(item: item, callerRole: callerRole) { dismiss() } }
            }
            Button("Cancelar", role: .cancel) {}
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Guardar") {
                    Task { if await store.save(item: item, draft: draft, callerRole: callerRole) { dismiss() } }
                }
                .disabled(!draft.isDirty)
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
        List {
            if !HomeAdminAccess.canViewAudit(role: home.role) {
                Text("Solo un administrador puede ver la auditoría").foregroundStyle(.secondary)
            } else {
                switch store.state {
                case .idle, .loading:
                    HomeLoadingView()
                case .failed(let message):
                    HomeErrorView(message: message) { Task { await store.load() } }
                case .loaded:
                    ForEach(store.items, id: \.id) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.action).font(.headline)
                            Text("\(item.actorName ?? "Sistema") · \(item.createdAt)")
                                .font(.caption).foregroundStyle(.secondary)
                            ForEach(item.payload.lines, id: \.self) { line in
                                Text(line).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if store.hasMore {
                        Button("Cargar más") { Task { await store.loadMore() } }
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
        List {
            switch store.state {
            case .idle, .loading:
                HomeLoadingView()
            case .failed(let message):
                HomeErrorView(message: message) { Task { await store.load() } }
            case .loaded:
                ForEach(store.items) { member in
                    if model.canEditMembers {
                        Button { memberToEdit = member } label: { row(member) }
                            .buttonStyle(.plain)
                    } else {
                        row(member)
                    }
                }
                if store.items.isEmpty {
                    Text("Sin miembros").foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Miembros")
        .toolbar {
            if model.canCreateMembers {
                ToolbarItem(placement: .primaryAction) {
                    Button { showCreate = true } label: { Label("Agregar", systemImage: "plus") }
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
        HStack {
            Circle()
                .fill(Color(hex: member.color ?? MemberValidation.defaultColor))
                .frame(width: 12, height: 12)
            VStack(alignment: .leading, spacing: 2) {
                Text(member.name)
                Text("\(MemberRules.kindLabel(member.kind)) · \(MemberRules.statusLabel(member.status)) · \(MemberRules.linkStatusLabel(linked: member.linked))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .opacity(member.status == MemberStatus.inactive.rawValue ? 0.6 : 1)
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
        Form {
            Section("Miembro") {
                TextField("Nombre (1-50)", text: $name)
                ColorPicker("Color", selection: $color, supportsOpacity: false)
                    .onChange(of: color) { colorTouched = true }
                Picker("Tipo", selection: $kind) {
                    if kind == nil { Text(editing.map { "\($0.kind) (sin cambiar)" } ?? "Elegir").tag(MemberKind?.none) }
                    ForEach(MemberRules.availableKinds(linked: linked), id: \.self) {
                        Text(MemberRules.kindLabel($0.rawValue)).tag(MemberKind?.some($0))
                    }
                }
                if let editing {
                    Picker("Estado", selection: $status) {
                        if status == nil { Text("\(editing.status) (sin cambiar)").tag(MemberStatus?.none) }
                        ForEach(MemberStatus.allCases, id: \.self) {
                            Text(MemberRules.statusLabel($0.rawValue)).tag(MemberStatus?.some($0))
                        }
                    }
                    LabeledContent("Cuenta", value: MemberRules.linkStatusLabel(linked: linked))
                }
            }
            Section {
                Button(editing == nil ? "Agregar" : "Guardar") { saveTapped() }
                    .disabled(MemberValidation.trimmedName(name).isEmpty || isWorking)
            }
        }
        .navigationTitle(editing == nil ? "Nuevo miembro" : "Editar miembro")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
        }
        .confirmationDialog(
            "Cambiar el tipo restablece los permisos de esta persona a los valores del nuevo tipo",
            isPresented: $confirmReset, titleVisibility: .visible
        ) {
            Button("Cambiar tipo", role: .destructive) { Task { await save() } }
            Button("Cancelar", role: .cancel) {}
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
        List {
            switch store.state {
            case .idle, .loading:
                HomeLoadingView()
            case .failed(let message):
                HomeErrorView(message: message) { Task { await store.load() } }
            case .loaded:
                ForEach(store.items) { item in
                    row(item)
                }
                if store.items.isEmpty {
                    Text("Sin invitaciones pendientes").foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Invitaciones")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showCreate = true } label: { Label("Crear", systemImage: "plus") }
            }
        }
        .refreshable { await store.load() }
        .errorAlert($store.errorMessage)
        .sheet(isPresented: $showCreate) {
            NavigationStack { InvitationCreateView(store: store, callerRole: home.role) }
        }
        .confirmationDialog(
            "¿Revocar la invitación?",
            isPresented: Binding(get: { toRevoke != nil }, set: { if !$0 { toRevoke = nil } }),
            titleVisibility: .visible
        ) {
            if let item = toRevoke {
                Button("Revocar", role: .destructive) { Task { await store.revoke(item) } }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("El código dejará de funcionar.")
        }
        .task { await store.load() }
        .onDisappear { store.clearCode() }
    }

    private func row(_ item: InvitationItem) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.memberName ?? MemberRules.kindLabel(item.kind))
                Text("\(MemberRules.kindLabel(item.kind)) · caduca \(item.expiresAt)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Revocar", role: .destructive) { toRevoke = item }
                .buttonStyle(.borderless)
        }
    }
}

/// Hoja de creación: tipo (según rol) y miembro sin cuenta opcional.
struct InvitationCreateView: View {
    let store: InvitationStore
    let callerRole: String

    @Environment(\.dismiss) private var dismiss
    @State private var kind: MemberKind
    @State private var memberId: Int?
    @State private var isWorking = false

    init(store: InvitationStore, callerRole: String) {
        self.store = store
        self.callerRole = callerRole
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
        Form {
            Section {
                Text(code).font(.body.monospaced()).textSelection(.enabled)
                Button("Copiar") { copy(code) }
            } footer: {
                Text("Solo se muestra una vez. Compártelo con la persona invitada; caduca en 7 días.")
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Listo") { store.clearCode(); dismiss() }
            }
        }
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
        Form {
            Section("Tipo") {
                Picker("Tipo", selection: $kind) {
                    ForEach(InvitationRules.allowedKinds(callerRole: callerRole), id: \.self) { k in
                        Text(MemberRules.kindLabel(k.rawValue)).tag(k)
                    }
                }
                .disabled(memberId != nil)
            }
            Section {
                Picker("Miembro", selection: $memberId) {
                    Text("Ninguno").tag(Int?.none)
                    ForEach(selectable) { m in
                        Text("\(m.name) · \(MemberRules.kindLabel(m.kind))").tag(Int?.some(m.id))
                    }
                }
            } header: {
                Text("Vincular a un miembro (opcional)")
            } footer: {
                Text("Solo miembros sin cuenta. Al aceptar, la cuenta queda vinculada a ese miembro.")
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Crear") { Task { await create() } }.disabled(isWorking)
            }
        }
    }

    private func create() async {
        isWorking = true
        defer { isWorking = false }
        let ok = await store.create(kind: memberId == nil ? kind : nil, memberId: memberId, callerRole: callerRole)
        // Miembro ya no invitable (400 o lista recargada): se reelige, nunca se manda genérico.
        if !ok, let id = memberId, !selectable.contains(where: { $0.id == id }) { memberId = nil }
    }
}
