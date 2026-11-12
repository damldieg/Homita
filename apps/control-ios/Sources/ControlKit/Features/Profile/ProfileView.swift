import SwiftUI

/// Perfil: datos de cuenta (`PATCH user/update`: nombre, email y contraseña opcional), acceso a
/// Personas, unirse a un hogar con un código de invitación (1.15) y cierre de sesión (local: no
/// hay endpoint de revocación). «Mis hogares» y la administración del hogar viven en la pestaña Hogar.
public struct ProfileView: View {
    let services: AppServices

    @State private var personStore: PersonStore
    @State private var didLoadPersons = false
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var isWorking = false
    @State private var showSignOutConfirm = false

    public init(services: AppServices) {
        self.services = services
        _personStore = State(initialValue: PersonStore(repo: services.persons))
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Título propio: el título grande de la barra no se ve con el scroll de tarjetas.
                    Text("Ajustes")
                        .font(HomitaFont.inter(34, weight: .bold, relativeTo: .largeTitle))
                        .foregroundStyle(Palette.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                    accountCard
                    familyCard
                    invitationsCard
                    HomitaButton(title: "Cerrar sesión", kind: .secondary) {
                        showSignOutConfirm = true
                    }
                    Text("Con firma gratuita la app caduca a los 7 días; reinstálala y vuelve a iniciar sesión.")
                        .font(HomitaFont.inter(13, relativeTo: .footnote))
                        .foregroundStyle(Palette.inkSoft)
                        .multilineTextAlignment(.center)
                }
                .padding(20)
            }
            .background(Palette.background.ignoresSafeArea())
            .homitaNavigationBar()
            .errorAlert($errorMessage)
            .homitaConfirm("¿Cerrar sesión en este iPhone?", isPresented: $showSignOutConfirm, confirmTitle: "Cerrar sesión") {
                services.signOut()
            }
            .overlay {
                if isWorking {
                    HomitaLoadingOverlay(message: "Guardando…")
                }
            }
            .onAppear {
                name = services.session.session?.name ?? ""
                email = services.session.session?.email ?? ""
                // Personas: carga al aparecer la pestaña (una vez, sin bloquear); el refresco
                // manual queda en PersonsView (.refreshable).
                if !didLoadPersons {
                    didLoadPersons = true
                    Task { await personStore.load() }
                }
            }
        }
    }

    // MARK: - Tarjetas

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HomitaSectionHeader(title: "Cuenta", systemImage: "person.crop.circle")
            HomitaField(placeholder: "Nombre", text: $name)
            HomitaField(placeholder: "Email", text: $email, isEmail: true)
            HomitaField(placeholder: "Nueva contraseña (opcional, mínimo 8)", text: $password, isSecure: true)
            HomitaPrimaryButton(title: "Guardar cambios", isEnabled: isValid && !isWorking, isLoading: isWorking) {
                Task { await save() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Palette.cardBorder, lineWidth: 1))
    }

    private var familyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HomitaSectionHeader(title: "Familia", systemImage: "person.2")
            NavigationLink {
                PersonsView(store: personStore)
            } label: {
                linkRow(title: "Personas", systemImage: "person.2.fill", tint: Palette.accentHex)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Palette.cardBorder, lineWidth: 1))
    }

    // 1.15 (D-016): fuera del `if case .ready`, visible también sin hogar activo.
    private var invitationsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HomitaSectionHeader(title: "Invitaciones", systemImage: "envelope.badge")
            NavigationLink {
                AcceptInvitationView(services: services)
            } label: {
                linkRow(title: "Unirse a un hogar con un código", systemImage: "person.badge.plus", tint: Palette.onlineHex)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Palette.cardBorder, lineWidth: 1))
    }

    /// Fila de navegación dentro de una tarjeta: baldosa de color, título y chevron.
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

    // MARK: - Lógica

    private var isValid: Bool {
        name.codepointCount >= 3 && name.codepointCount <= 50
            && !email.trimmingCharacters(in: .whitespaces).isEmpty
            && (password.isEmpty || password.codepointCount >= 8)
    }

    private func save() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await services.auth.updateProfile(
                name: name.trimmingCharacters(in: .whitespaces),
                email: email.trimmingCharacters(in: .whitespaces),
                password: password.isEmpty ? nil : password
            )
            password = ""
        } catch {
            errorMessage = (error as? APIError)?.userMessage ?? error.localizedDescription
        }
    }
}
