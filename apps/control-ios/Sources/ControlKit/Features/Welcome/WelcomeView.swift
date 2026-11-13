import SwiftUI

/// Pantalla de bienvenida: acceso a Login y (solo si `GET /config` lo permite) a Registro.
public struct WelcomeView: View {
    let services: AppServices

    @State private var showLogin = false
    @State private var showRegister = false

    public init(services: AppServices) {
        self.services = services
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Palette.background.ignoresSafeArea()
                VStack(spacing: 16) {
                    Spacer()
                    // Mismo glifo que el icono de la app: «H» sobre amarillo cálido.
                    RoundedRectangle(cornerRadius: 22)
                        .fill(Palette.warm)
                        .frame(width: 96, height: 96)
                        .overlay {
                            Text("H")
                                .font(HomitaFont.inter(56, weight: .bold, relativeTo: .largeTitle))
                                .foregroundStyle(Palette.ink)
                        }
                    Text("Homita")
                        .font(HomitaFont.inter(40, weight: .bold, relativeTo: .largeTitle))
                        .foregroundStyle(Palette.ink)
                    Text("Tu panel de control familiar")
                        .font(HomitaFont.inter(17, relativeTo: .body))
                        .foregroundStyle(Palette.inkSoft)
                    Spacer()
                    HomitaPrimaryButton(title: "Iniciar sesión") { showLogin = true }
                    if services.auth.allowRegistration {
                        HomitaButton(title: "Registrarse", kind: .secondary) { showRegister = true }
                    }
                }
                .padding(24)
            }
            .navigationDestination(isPresented: $showLogin) {
                LoginView(services: services)
            }
            .navigationDestination(isPresented: $showRegister) {
                RegisterView(services: services)
            }
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            #endif
            .task {
                await services.auth.fetchConfig()
            }
        }
        .tint(Palette.accent)
    }
}
