import SwiftUI

/// Pantalla de bienvenida: acceso a Login y (solo si `GET /config` lo permite) a Registro.
public struct WelcomeView: View {
    let services: AppServices

    public init(services: AppServices) {
        self.services = services
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Spacer()
                Image(systemName: "checklist")
                    .font(.system(size: 56))
                    .foregroundStyle(.tint)
                Text("Planify")
                    .font(.largeTitle)
                    .bold()
                Text("Tu panel de control familiar")
                    .foregroundStyle(.secondary)
                Spacer()
                NavigationLink {
                    LoginView(services: services)
                } label: {
                    Text("Iniciar sesión")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                if services.auth.allowRegistration {
                    NavigationLink {
                        RegisterView(services: services)
                    } label: {
                        Text("Registrarse")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(24)
            .navigationTitle("Bienvenido")
            .task {
                await services.auth.fetchConfig()
            }
        }
    }
}
