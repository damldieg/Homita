import SwiftUI

/// Pestaña Hogar: selector de hogar activo, miembros con tipo y permisos, invitar por código y
/// enlace a la administración. Es solo lectura salvo crear invitaciones; el código se ve una sola
/// vez, al crearla (no hay ruta para releerlo).
public struct HogarView: View {
    let services: AppServices
    let home: HomeItem
    @State private var store: HogarStore
    @State private var invitationStore: InvitationStore
    @State private var showInvite = false
    @State private var permissionsRow: HogarMemberRow?

    public init(services: AppServices, home: HomeItem) {
        self.services = services
        self.home = home
        let homeContext = services.homeContext
        _store = State(initialValue: HogarStore(
            repo: services.homes, homeId: home.homeId, homeRole: home.role,
            callerAppUserId: services.session.session?.id,
            activeHomeId: { homeContext.activeHomeId }
        ))
        _invitationStore = State(initialValue: InvitationStore(
            repo: services.homes, homeId: home.homeId,
            activeHomeId: { homeContext.activeHomeId }
        ))
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Text("Hogar")
                        .font(HomitaFont.inter(34, weight: .bold, relativeTo: .largeTitle))
                        .foregroundStyle(Palette.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                    switcherCard
                    membersCard
                    if store.canInvite {
                        inviteCard
                    }
                    adminCard
                }
                .padding(20)
            }
            .background(Palette.background.ignoresSafeArea())
            .homitaNavigationBar()
            .refreshable { await store.load() }
            .task { await store.load() }
            .sheet(item: $permissionsRow) { row in
                permissionsSheet(row)
            }
            .sheet(isPresented: $showInvite) {
                NavigationStack { InvitationCreateView(store: invitationStore, callerRole: store.callerRole, homeName: home.name) }
            }
        }
    }

    // MARK: - Tarjetas

    private var switcherCard: some View {
        card {
            HomitaSectionHeader(title: "Hogar activo", count: services.homeContext.homes.count, systemImage: "house")
            ForEach(HomeSwitcher.rows(homes: services.homeContext.homes,
                                      activeHomeId: services.homeContext.activeHomeId)) { row in
                Button {
                    services.homeContext.select(homeId: row.id)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.name)
                                .font(HomitaFont.inter(17, weight: .medium, relativeTo: .body))
                                .foregroundStyle(Palette.ink)
                            Text(row.roleLabel)
                                .font(HomitaFont.inter(13, relativeTo: .footnote))
                                .foregroundStyle(Palette.inkSoft)
                        }
                        Spacer()
                        if row.isActive {
                            HomitaBadge(title: "Activo", tintHex: Palette.onlineHex)
                        }
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(row.isActive ? .isSelected : [])
            }
            if let error = services.homeContext.persistenceError {
                Text(error)
                    .font(HomitaFont.inter(13, relativeTo: .footnote))
                    .foregroundStyle(Palette.accent)
            }
        }
    }

    private var membersCard: some View {
        card {
            HomitaSectionHeader(title: "Miembros", count: store.state == .loaded ? store.rows.count : nil,
                                systemImage: "person.2")
            switch store.state {
            case .idle, .loading:
                Text("Cargando…")
                    .font(HomitaFont.inter(15, relativeTo: .body))
                    .foregroundStyle(Palette.inkSoft)
            case .failed(let message):
                Text(message)
                    .font(HomitaFont.inter(15, relativeTo: .body))
                    .foregroundStyle(Palette.accent)
                HomitaButton(title: "Reintentar", kind: .secondary) { Task { await store.load() } }
            case .loaded:
                if store.rows.isEmpty {
                    Text("Sin miembros")
                        .font(HomitaFont.inter(15, relativeTo: .body))
                        .foregroundStyle(Palette.inkSoft)
                }
                ForEach(store.rows) { row in
                    memberRow(row)
                }
            }
        }
    }

    private func memberRow(_ row: HogarMemberRow) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(row.initial)
                .font(HomitaFont.inter(16, weight: .bold, relativeTo: .body))
                .foregroundStyle(Palette.accent)
                .frame(width: 36, height: 36)
                .background(Palette.accent.opacity(0.14), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(row.name)
                        .font(HomitaFont.inter(17, weight: .medium, relativeTo: .body))
                        .foregroundStyle(Palette.ink)
                    if row.isMe {
                        HomitaBadge(title: "tú", tintHex: Palette.onlineHex)
                    }
                }
                Text([row.kindLabel, row.roleLabel].compactMap { $0 }.joined(separator: " · "))
                    .font(HomitaFont.inter(13, relativeTo: .footnote))
                    .foregroundStyle(Palette.inkSoft)
                if !row.permissions.isEmpty {
                    Text(row.permissionsPreview.joined(separator: ", "))
                        .font(HomitaFont.inter(13, relativeTo: .footnote))
                        .foregroundStyle(Palette.inkMuted)
                    if row.hasMorePermissions {
                        Button("Ver más") { permissionsRow = row }
                            .font(HomitaFont.inter(13, weight: .medium, relativeTo: .footnote))
                            .foregroundStyle(Palette.accent)
                            .buttonStyle(.plain)
                            .accessibilityHint("Abre el catálogo completo de permisos")
                    }
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: row.hasMorePermissions ? .contain : .combine)
    }

    private func permissionsSheet(_ row: HogarMemberRow) -> some View {
        NavigationStack {
            ScrollView {
                card {
                    HomitaSectionHeader(title: row.name, count: row.permissions.count, systemImage: "checkmark.shield")
                    ForEach(Array(row.permissions.enumerated()), id: \.offset) { _, permission in
                        Text(permission)
                            .font(HomitaFont.inter(15, relativeTo: .body))
                            .foregroundStyle(Palette.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 2)
                    }
                }
                .padding(20)
            }
            .background(Palette.background.ignoresSafeArea())
            .navigationTitle("Permisos del hogar")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .homitaNavigationBar()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Cerrar") { permissionsRow = nil }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var inviteCard: some View {
        card {
            HomitaSectionHeader(title: "Invitar", systemImage: "envelope.badge")
            Text("Crea un código de invitación y compártelo. Solo se muestra al crearlo.")
                .font(HomitaFont.inter(13, relativeTo: .footnote))
                .foregroundStyle(Palette.inkSoft)
            HomitaButton(title: "Crear invitación") { showInvite = true }
            NavigationLink {
                HomeInvitationsView(services: services, home: home)
            } label: {
                linkRow(title: "Invitaciones pendientes", systemImage: "tray", tint: Palette.soonHex)
            }
            .buttonStyle(.plain)
        }
    }

    private var adminCard: some View {
        card {
            NavigationLink {
                HomeAdminView(services: services, home: home)
            } label: {
                linkRow(title: "Administración", systemImage: "gearshape", tint: Palette.soonHex)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Piezas

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Palette.cardBorder, lineWidth: 1))
    }

    private func linkRow(title: String, systemImage: String, tint: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color(hex: tint))
                .frame(width: 36, height: 36)
                .background(Color(hex: tint).opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
            Text(title)
                .font(HomitaFont.inter(17, weight: .medium, relativeTo: .body))
                .foregroundStyle(Palette.ink)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.inkMuted)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
