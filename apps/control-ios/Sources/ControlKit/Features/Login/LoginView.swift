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

    public var body: some View {
        Form {
            Section("Cuenta") {
                EmailTextField(prompt: "Email", text: $email)
                SecureField("Contraseña", text: $password)
            }
            Section {
                Button {
                    Task { await login() }
                } label: {
                    if isWorking {
                        ProgressView()
                    } else {
                        Text("Iniciar sesión")
                    }
                }
                .disabled(email.trimmingCharacters(in: .whitespaces).isEmpty || password.isEmpty || isWorking)
            }
        }
        .navigationTitle("Iniciar sesión")
        .errorAlert($errorMessage)
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
