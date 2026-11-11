import SwiftUI

private func reload(_ services: AppServices) -> () async -> Void {
    { await services.homeContext.load(using: services.homes) }
}

/// Entrada de administración del hogar: secciones según el rol (`HomeAdminScreenModel`).
struct HomeAdminView: View {
    let services: AppServices
    let home: HomeItem

    var body: some View {
        let model = HomeAdminScreenModel(role: home.role)
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
        case .editPermissions: break
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
                        }
                        Spacer()
                        if item.editable && item.role == "member" && HomeAdminAccess.isAdmin(role: home.role) {
                            Button("Editar") { editing = item }.buttonStyle(.borderless)
                        }
                    }
                }
            }
        }
        .navigationTitle("Accesos")
        .refreshable { await store.load() }
        .errorAlert($store.errorMessage)
        .sheet(item: Binding(get: { editing.map { IdentifiedPermission(item: $0) } },
                             set: { editing = $0?.item })) { wrapper in
            NavigationStack {
                PermissionEditorView(store: store, item: wrapper.item)
            }
        }
        .task { await store.load() }
    }
}

struct IdentifiedPermission: Identifiable {
    let item: PermissionItem
    var id: Int { item.membershipId }
}

struct PermissionEditorView: View {
    let store: PermissionStore
    let item: PermissionItem

    @Environment(\.dismiss) private var dismiss
    @State private var draft: PermissionDraft

    init(store: PermissionStore, item: PermissionItem) {
        self.store = store
        self.item = item
        _draft = State(initialValue: PermissionDraft(permissions: item.permissions))
    }

    var body: some View {
        Form {
            ForEach(groupedCatalog(store.response?.catalog ?? []), id: \.domain) { group in
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
        }
        .navigationTitle(item.name)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Guardar") {
                    Task { if await store.save(item: item, draft: draft) { dismiss() } }
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
