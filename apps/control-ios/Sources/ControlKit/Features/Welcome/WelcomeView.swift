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
                    // Mismo icono que la app y que el final de la animación de arranque.
                    ZStack {
                        RoundedRectangle(cornerRadius: 96 * 27 / 120, style: .continuous).fill(Brand.sage)
                        HomitaMark().frame(width: 96, height: 96)
                    }
                    .frame(width: 96, height: 96)
                    Text("Homita")
                        .font(HomitaFont.inter(40, weight: .bold, relativeTo: .largeTitle))
                        .foregroundStyle(Palette.ink)
                    Text("Tu panel de control familiar")
                        .font(HomitaFont.inter(17, relativeTo: .body))
                        .foregroundStyle(Palette.inkSoft)
                    Spacer()
                    HomitaPrimaryButton(title: "Iniciar sesión") { showLogin = true }
                        .homitaRequiresNetwork()
                        .accessibilityIdentifier("bienvenida.iniciar-sesion")
                    if services.auth.allowRegistration {
                        HomitaButton(title: "Registrarse", kind: .secondary) { showRegister = true }
                            .homitaRequiresNetwork()
                            .accessibilityIdentifier("bienvenida.registrarse")
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
