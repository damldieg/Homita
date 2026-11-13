import SwiftUI
import HomitaShared

/// Perfil: datos de cuenta (`PATCH user/update`: nombre, email y contraseña opcional), acceso a
/// Personas, unirse a un hogar con un código de invitación (1.15) y cierre de sesión (local: no
/// hay endpoint de revocación). «Mis hogares» y la administración del hogar viven en la pestaña Hogar.
public struct ProfileView: View {
    let services: AppServices
    /// Lleva a la pestaña Hogar («Ver el hogar» tras unirse con un código).
    var onOpenHome: () -> Void = {}

    @State private var personStore: PersonStore
    @State private var didLoadPersons = false
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var isWorking = false
    @State private var showSignOutConfirm = false
    @State private var showNotifications = false
    @AppStorage(AppearancePreference.storageKey) private var appearance = AppearancePreference.system.rawValue
    @Environment(\.colorScheme) private var colorScheme

    public init(services: AppServices, onOpenHome: @escaping () -> Void = {}) {
        self.services = services
        self.onOpenHome = onOpenHome
        _personStore = State(initialValue: PersonStore(repo: services.persons))
    }

    /// Interruptor de modo oscuro: refleja la preferencia (o el sistema si no hay preferencia) y la guarda.
    private var darkModeBinding: Binding<Bool> {
        Binding(
            get: { (AppearancePreference(rawValue: appearance) ?? .system).resolvedIsDark(systemDark: colorScheme == .dark) },
            set: { appearance = ($0 ? AppearancePreference.dark : AppearancePreference.light).rawValue }
        )
    }

    /// Versión corta del bundle (`CFBundleShortVersionString`); «—» si no se puede leer.
    static var appVersion: String {
        let short = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "—"
        guard let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String, !build.isEmpty else {
            return short
        }
        return "\(short) (\(build))"
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
                    notificationsCard
                    HomitaCard {
                        HomitaToggle(title: "Modo oscuro", isOn: darkModeBinding)
                            .accessibilityIdentifier("ajustes.modo-oscuro")
                    }
                    HomitaButton(title: "Cerrar sesión", kind: .secondary) {
                        showSignOutConfirm = true
                    }
                    .accessibilityIdentifier("ajustes.cerrar-sesion")
                    Text("Con firma gratuita la app caduca a los 7 días; reinstálala y vuelve a iniciar sesión.")
                        .font(HomitaFont.inter(13, relativeTo: .footnote))
                        .foregroundStyle(Palette.inkSoft)
                        .multilineTextAlignment(.center)
                    // E5-01 [Nuevo]: versión de la app al pie de Ajustes.
                    Text("Versión \(Self.appVersion)")
                        .font(HomitaFont.inter(12, relativeTo: .caption))
                        .foregroundStyle(Palette.inkMuted)
                }
                .padding(20)
            }
            .background(Palette.background.ignoresSafeArea())
            .homitaNavigationBar()
            .errorAlert($errorMessage)
            .navigationDestination(isPresented: $showNotifications) { NotificationSettingsView() }
            // `homita://ajustes-notificaciones` (widgets desactivados, permiso denegado…).
            .task { openNotificationsIfRequested(DeepLinkCenter.shared.pending) }
            .onChange(of: DeepLinkCenter.shared.pending) { _, link in openNotificationsIfRequested(link) }
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
            .accessibilityIdentifier("ajustes.nombre")
            HomitaField(placeholder: "Email", text: $email, isEmail: true)
            .accessibilityIdentifier("ajustes.email")
            HomitaField(placeholder: "Nueva contraseña (opcional, mínimo 8)", text: $password, isSecure: true)
            .accessibilityIdentifier("ajustes.contrasena")
            HomitaPrimaryButton(title: "Guardar cambios", isEnabled: isValid && hasChanges && !isWorking, isLoading: isWorking) {
                Task { await save() }
            }
            .homitaRequiresNetwork()
            .accessibilityIdentifier("ajustes.guardar-cuenta")
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
                linkRow(title: "Personas", systemImage: "person.2.fill", tint: Palette.accentHex,
                        detail: personStore.persons.isEmpty ? nil : "\(personStore.persons.count)")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("ajustes.personas")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Palette.cardBorder, lineWidth: 1))
    }

    private var notificationsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HomitaSectionHeader(title: "Notificaciones", systemImage: "bell")
            Button { showNotifications = true } label: {
                linkRow(title: "Avisos, widgets y pantalla de bloqueo", systemImage: "bell.badge", tint: Palette.accentHex)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("ajustes.notificaciones")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Palette.cardBorder, lineWidth: 1))
    }

    private func openNotificationsIfRequested(_ link: HomitaDeepLink?) {
        guard link == .ajustesNotificaciones else { return }
        showNotifications = true
    }

    // 1.15 (D-016): fuera del `if case .ready`, visible también sin hogar activo.
    private var invitationsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HomitaSectionHeader(title: "Invitaciones", systemImage: "envelope.badge")
            NavigationLink {
                AcceptInvitationView(services: services, onOpenHome: onOpenHome)
            } label: {
                linkRow(title: "Unirse a un hogar con un código", systemImage: "person.badge.plus", tint: Palette.onlineHex)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("ajustes.unirse")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Palette.cardBorder, lineWidth: 1))
    }

    /// Fila de navegación dentro de una tarjeta: baldosa de color, título y chevron.
    private func linkRow(title: String, systemImage: String, tint: String, detail: String? = nil) -> some View {
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
            if let detail {
                Text(detail)
                    .font(HomitaFont.inter(15, relativeTo: .subheadline))
                    .foregroundStyle(Palette.inkSoft)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.inkMuted)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    // MARK: - Lógica

    /// «Guardar cambios» solo se activa si algo cambió respecto a la sesión (o hay contraseña nueva).
    private var hasChanges: Bool {
        Self.hasAccountChanges(
            name: name, email: email, password: password,
            sessionName: services.session.session?.name ?? "", sessionEmail: services.session.session?.email ?? ""
        )
    }

    static func hasAccountChanges(name: String, email: String, password: String,
                                  sessionName: String, sessionEmail: String) -> Bool {
        !password.isEmpty
            || name.trimmingCharacters(in: .whitespaces) != sessionName
            || email.trimmingCharacters(in: .whitespaces) != sessionEmail
    }

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
