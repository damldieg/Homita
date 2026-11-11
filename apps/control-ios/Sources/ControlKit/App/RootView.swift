import SwiftUI

/// Raíz de la app: sin sesión → Welcome → Login/Register; con sesión → 3 pestañas
/// (Tareas, Calendario, Perfil). Es el único punto público del módulo: el proyecto Xcode del
/// usuario hace `WindowGroup { RootView() }` (ver README.md).
public struct RootView: View {
    @State private var session: SessionStore
    @State private var services: AppServices

    public init() {
        let config = AppConfig.load()
        let tokenStore = KeychainTokenStore()
        let session = SessionStore(store: tokenStore)
        session.restore()
        _session = State(initialValue: session)
        _services = State(initialValue: AppServices(config: config, session: session, tokenStore: tokenStore))
    }

    public var body: some View {
        Group {
            if session.session == nil {
                WelcomeView(services: services)
            } else {
                MainTabView(services: services)
                    .task(id: session.session?.id) {
                        await services.homeContext.load(using: services.homes)
                    }
            }
        }
        .environment(session)
    }
}

struct MainTabView: View {
    let services: AppServices

    var body: some View {
        let state = services.homeContext.state
        // 1.15c: al cambiar de hogar las pestañas se reconstruyen (stores y datos del hogar anterior fuera).
        let homeKey = services.homeContext.activeHomeId ?? ""
        TabView {
            HomeGate(services: services, state: state) {
                TasksRootView(services: services)
            }
            .id(homeKey)
            .tabItem { Label("Tareas", systemImage: "checklist") }
            HomeGate(services: services, state: state) {
                CalendarsRootView(services: services)
            }
            .id(homeKey)
            .tabItem { Label("Calendario", systemImage: "calendar") }
            ProfileView(services: services)
                .tabItem { Label("Perfil", systemImage: "person.crop.circle") }
        }
    }
}
