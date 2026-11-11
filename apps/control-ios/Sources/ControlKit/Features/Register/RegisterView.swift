import SwiftUI

/// Registro (`POST user/create`), solo visible si `GET /config` → `allow_registration=true`
/// (producción lo tiene desactivado). Validación de cliente igual que el contrato PHP.
public struct RegisterView: View {
    let services: AppServices

    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var isWorking = false

    public init(services: AppServices) {
        self.services = services
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HomitaCard {
                    VStack(alignment: .leading, spacing: 14) {
                        HomitaSectionHeader(title: "Cuenta", systemImage: "person.badge.plus")
                        HomitaField(placeholder: "Nombre", text: $name)
                        HomitaField(placeholder: "Email", text: $email, isEmail: true)
                        HomitaField(placeholder: "Contraseña (mínimo 8)", text: $password, isSecure: true)
                    }
                }
                HomitaPrimaryButton(title: "Crear cuenta", isEnabled: isValid, isLoading: isWorking) {
                    Task { await register() }
                }
            }
            .padding(20)
        }
        .background(Palette.background.ignoresSafeArea())
        .navigationTitle("Registrarse")
        .homitaNavigationBar()
        .errorAlert($errorMessage)
        .overlay {
            if isWorking {
                HomitaLoadingOverlay(message: "Creando cuenta…")
            }
        }
        .disabled(isWorking)
    }

    private var isValid: Bool {
        name.codepointCount >= 3 && name.codepointCount <= 50
            && !email.trimmingCharacters(in: .whitespaces).isEmpty
            && password.codepointCount >= 8
    }

    private func register() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await services.auth.register(
                name: name.trimmingCharacters(in: .whitespaces),
                email: email.trimmingCharacters(in: .whitespaces),
                password: password
            )
        } catch {
            errorMessage = (error as? APIError)?.userMessage ?? error.localizedDescription
        }
    }
}
