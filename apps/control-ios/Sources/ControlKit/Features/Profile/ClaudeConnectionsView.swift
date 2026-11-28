import SwiftUI
import HomitaShared

/// Ajustes › Claude: apps conectadas a tu cuenta por OAuth (Claude vía el MCP de Homita) y botón para revocar.
struct ClaudeConnectionsView: View {
    @State private var store: ClaudeConnectionsStore
    @State private var pendingRevoke: ClaudeConnection?
    @State private var showRevokeConfirm = false

    init(repo: ClaudeConnectionsRepository) {
        _store = State(initialValue: ClaudeConnectionsStore(repo: repo))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    HomitaSectionHeader(title: "Conexiones", systemImage: "link")
                    content
                    HomitaFootnote(text: "Claude accede a Homita con tu cuenta y tus permisos. Al revocar una conexión deja de funcionar de inmediato; para volver a usarla hay que conectarla otra vez desde Claude.")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Palette.card, in: RoundedRectangle(cornerRadius: 24))
                .overlay(RoundedRectangle(cornerRadius: 24).stroke(Palette.cardBorder, lineWidth: 1))
            }
            .padding(20)
        }
        .background(Palette.background.ignoresSafeArea())
        .navigationTitle("Claude")
        .homitaNavigationBar()
        .errorAlert($store.errorMessage)
        .task { await store.load() }
        .refreshable { await store.load() }
        .homitaConfirm(
            "¿Revocar la conexión «\(pendingRevoke?.clientName ?? "")»? Dejará de acceder a Homita.",
            isPresented: $showRevokeConfirm, confirmTitle: "Revocar"
        ) {
            guard let connection = pendingRevoke else { return }
            Task { await store.revoke(connection) }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch store.state {
        case _ where store.state == .idle || (store.state == .loading && store.connections.isEmpty):
            ProgressView().frame(maxWidth: .infinity).padding(.vertical, 12)
        case .failed(let message):
            HomitaFootnote(text: message)
            HomitaButton(title: "Reintentar", kind: .secondary) { Task { await store.load() } }
                .accessibilityIdentifier("claude.reintentar")
        default:
            if store.connections.isEmpty {
                HomitaFootnote(text: "No hay ninguna app conectada a tu cuenta.")
                    .accessibilityIdentifier("claude.vacio")
            } else {
                ForEach(store.connections) { connection in
                    row(connection)
                }
            }
        }
    }

    private func row(_ connection: ClaudeConnection) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(connection.clientName.isEmpty ? "App sin nombre" : connection.clientName)
                    .font(HomitaFont.inter(17, weight: .medium, relativeTo: .body))
                    .foregroundStyle(Palette.ink)
                if let date = connection.grantedDate {
                    Text("Conectada el \(date.formatted(date: .abbreviated, time: .omitted))")
                        .font(HomitaFont.inter(13, relativeTo: .footnote))
                        .foregroundStyle(Palette.inkSoft)
                }
            }
            Spacer()
            Button("Revocar") {
                pendingRevoke = connection
                showRevokeConfirm = true
            }
            .font(HomitaFont.inter(15, weight: .semibold, relativeTo: .subheadline))
            .foregroundStyle(Palette.err)
            .disabled(store.revokingClientId != nil)
            .accessibilityIdentifier("claude.revocar.\(connection.clientId)")
        }
        .padding(.vertical, 4)
    }
}
