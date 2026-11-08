import SwiftUI

/// Raíz de la app: sin sesión → Welcome → Login/Register; con sesión → 3 pestañas
/// (Tareas, Calendario, Perfil). Es el único punto público del módulo: el proyecto Xcode del
/// usuario hace `WindowGroup { RootView() }` (ver README.md).
public struct RootView: View {
    @State private var session: SessionStore
    @State private var services: AppServices

    public init() {
        let config = AppConfig.load()
        let session = SessionStore(store: KeychainTokenStore())
        session.restore()
        _session = State(initialValue: session)
        _services = State(initialValue: AppServices(config: config, session: session))
    }

    public var body: some View {
        Group {
            if session.session == nil {
                WelcomeView(services: services)
            } else {
                MainTabView(services: services)
            }
        }
        .environment(session)
    }
}

struct MainTabView: View {
    let services: AppServices

    var body: some View {
        TabView {
            TasksRootView(services: services)
                .tabItem { Label("Tareas", systemImage: "checklist") }
            CalendarsRootView(services: services)
                .tabItem { Label("Calendario", systemImage: "calendar") }
            ProfileView(services: services)
                .tabItem { Label("Perfil", systemImage: "person.crop.circle") }
        }
    }
}
