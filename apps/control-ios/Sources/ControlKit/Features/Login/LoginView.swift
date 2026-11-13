import SwiftUI

/// Login (`POST user/auth`). Si el refresco falla y la sesión caduca, el motivo se muestra aquí.
public struct LoginView: View {
    let services: AppServices

    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var isWorking = false

    public init(services: AppServices) {
        self.services = services
    }

    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
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
