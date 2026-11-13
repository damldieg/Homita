import SwiftUI

/// Login (`POST user/auth`). Si el refresco falla y la sesión caduca, el motivo se muestra aquí.
public struct LoginView: View {
    let services: AppServices
    /// Aviso encima del formulario (p. ej. tras registrarse sin sesión automática).
    let notice: String?

    @State private var email: String
    @State private var password: String
    @State private var errorMessage: String?
    @State private var isWorking = false

    /// `email`/`password` precargan el formulario (registro sin sesión automática).
    public init(services: AppServices, email: String = "", password: String = "", notice: String? = nil) {
        self.services = services
        self.notice = notice
        _email = State(initialValue: email)
        _password = State(initialValue: password)
    }

    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let notice {
                    HomitaCard {
                        HomitaFootnote(text: notice)
                    }
                    .accessibilityIdentifier("login.aviso")
                }
                HomitaCard {
                    VStack(alignment: .leading, spacing: 14) {
                        HomitaSectionHeader(title: "Cuenta", systemImage: "person.crop.circle")
                        HomitaField(placeholder: "Email", text: $email, isEmail: true)
                            .accessibilityIdentifier("login.email")
                        HomitaField(placeholder: "Contraseña", text: $password, isSecure: true)
                            .accessibilityIdentifier("login.contrasena")
                    }
                }
                HomitaPrimaryButton(title: "Iniciar sesión", isEnabled: canSubmit, isLoading: isWorking) {
                    Task { await login() }
                }
                .homitaRequiresNetwork()
                .accessibilityIdentifier("login.iniciar-sesion")
            }
            .padding(20)
        }
        .background(Palette.background.ignoresSafeArea())
        .navigationTitle("Iniciar sesión")
        .homitaNavigationBar()
        .errorAlert($errorMessage)
        .overlay {
            if isWorking {
                HomitaLoadingOverlay(message: "Entrando…")
            }
        }
        .disabled(isWorking)
    }

    private func login() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await services.auth.login(email: email.trimmingCharacters(in: .whitespaces), password: password)
        } catch {
            errorMessage = (error as? APIError)?.userMessage ?? error.localizedDescription
        }
    }
}
