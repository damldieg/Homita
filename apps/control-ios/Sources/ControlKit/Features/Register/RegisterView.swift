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
        Form {
            Section("Cuenta") {
                TextField("Nombre", text: $name)
                EmailTextField(prompt: "Email", text: $email)
                SecureField("Contraseña (mínimo 8)", text: $password)
            }
            Section {
                Button {
                    Task { await register() }
                } label: {
                    if isWorking {
                        ProgressView()
                    } else {
                        Text("Crear cuenta")
                    }
                }
                .disabled(!isValid || isWorking)
            }
        }
        .navigationTitle("Registrarse")
        .errorAlert($errorMessage)
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
