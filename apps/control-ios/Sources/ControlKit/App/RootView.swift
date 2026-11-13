import SwiftUI

/// Raíz de la app: sin sesión → Welcome → Login/Register; con sesión → 5 pestañas
/// (Inicio, Tareas, Calendario, Hogar, Perfil). Es el único punto público del módulo: el proyecto Xcode del
/// usuario hace `WindowGroup { RootView() }` (ver README.md).
public struct RootView: View {
    @State private var session: SessionStore
    @State private var services: AppServices
    /// Animación de marca activa (arranque en frío, login o reapertura con sesión); nil = ninguna.
    @State private var intro: HomitaIntro.Style?
    @AppStorage(AppearancePreference.storageKey) private var appearance = AppearancePreference.system.rawValue
    @Environment(\.scenePhase) private var scenePhase

    public init() {
        _ = HomitaFont.registered
        HomitaAppearance.apply()
        HomitaComponents.applyTheme()
        let config = AppConfig.load()
        let tokenStore = KeychainTokenStore()
        let session = SessionStore(store: tokenStore)
        session.restore()
        ConnectivityMonitor.shared.start()
        #if DEBUG
        // Solo para la suite de UI (build Debug): arranca sin sesión guardada; el Keychain del simulador persiste entre corridas.
        if ProcessInfo.processInfo.arguments.contains("-uiTestingResetSession") {
            session.signOut()
        }
        #endif
        _session = State(initialValue: session)
        _intro = State(initialValue: session.session == nil ? .first : .returning)
        _services = State(initialValue: AppServices(config: config, session: session, tokenStore: tokenStore))
    }

    /// Hogar activo aún sin resolver (primera carga o tras reiniciar): no se muestran pestañas.
    private var isResolvingHome: Bool {
        guard services.homeContext.activeHomeId == nil else { return false }
        switch services.homeContext.state {
        case .unresolved, .loading: return true
        case .ready, .noHome, .failed: return false
        }
    }

    /// Cambia al iniciar/cerrar sesión o al cambiar de hogar: reprograma avisos, widgets y Live Activity.
    private var syncKey: String {
        "\(session.session?.id ?? 0)|\(services.homeContext.activeHomeId ?? "")"
    }

    public var body: some View {
        ZStack {
            Group {
                if session.session == nil {
                    WelcomeView(services: services)
                } else if isResolvingHome {
                    // Carga inicial: solo esqueleto a pantalla completa, sin pestañas ni barra inferior.
                    HomeLoadingView()
                } else {
                    MainTabView(services: services)
                }
            }
            .task(id: session.session?.id) {
                await services.homeContext.load(using: services.homes)
            }
            Color.clear
                .frame(width: 0, height: 0)
                .task(id: syncKey) {
                    guard session.session != nil, services.homeContext.activeHomeId != nil else { return }
                    HomitaSync.shared.attach(services)
                    await HomitaSync.shared.refresh(force: true)
                }
            if let style = intro {
                HomitaIntro(style: style) { intro = nil }
                    .transition(.identity)
                    .zIndex(1)
            }
        }
        .environment(session)
        // Widgets, Live Activity y notificaciones abren la app con `homita://…`.
        .onOpenURL { DeepLinkCenter.shared.open(url: $0) }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task { await HomitaSync.shared.refresh() }
            case .background:
                #if os(iOS)
                BackgroundRefresh.schedule()
                #endif
            default:
                break
            }
        }
        // Sin sesión → con sesión = login recién hecho (no se dispara en el arranque ni al refrescar el token).
        .onChange(of: session.session?.id) { old, new in
            if old == nil, new != nil { intro = .login }
        }
        .preferredColorScheme((AppearancePreference(rawValue: appearance) ?? .system).colorScheme)
    }
}

struct MainTabView: View {
    let services: AppServices
    @State private var selectedTab = 0 // 0 Inicio, 1 Tareas, 2 Calendario, 3 Hogar, 4 Perfil
    @State private var taskListRequest: Int? // lista pedida desde Inicio
    @State private var calendarSegment = 0 // 0 Eventos, 1 Rutinas, 2 Calendarios
    private let deepLinks = DeepLinkCenter.shared

    var body: some View {
        let state = services.homeContext.state
        // 1.15c: al cambiar de hogar las pestañas se reconstruyen (stores y datos del hogar anterior fuera).
        // Cambiar de hogar o pulsar «Reintentar» (E0-06) recrea las pestañas y recarga sus datos.
        let homeKey = (services.homeContext.activeHomeId ?? "") + "#\(DataFreshness.shared.reloadToken)"
        TabView(selection: $selectedTab) {
            HomeGate(services: services, state: state) {
                InicioView(services: services) { destination in
                    switch destination {
                    case .tasks: taskListRequest = nil; selectedTab = 1
                    case .taskList(let id): taskListRequest = id; selectedTab = 1
                    case .routines: calendarSegment = 1; selectedTab = 2
                    case .events: calendarSegment = 0; selectedTab = 2
                    case .home: selectedTab = 3
                    }
                }
            }
            .id(homeKey)
            .tabItem { Label("Inicio", systemImage: "house") }
            .tag(0)
            HomeGate(services: services, state: state) {
                TasksRootView(services: services, listRequest: $taskListRequest)
            }
            .id(homeKey)
            .tabItem { Label("Tareas", systemImage: "checklist") }
            .tag(1)
            HomeGate(services: services, state: state) {
                CalendarsRootView(services: services, segment: $calendarSegment)
            }
            .id(homeKey)
            .tabItem { Label("Calendario", systemImage: "calendar") }
            .tag(2)
            HomeGate(services: services, state: state) {
                if case .ready(let home) = state {
                    HogarView(services: services, home: home)
                }
            }
            .id(homeKey)
            .tabItem { Label("Hogar", systemImage: "person.2") }
            .tag(3)
            ProfileView(services: services, onOpenHome: { selectedTab = 3 })
                .tabItem { Label("Ajustes", systemImage: "gearshape") }
                .tag(4)
        }
        .tint(Palette.accent)
        .safeAreaInset(edge: .top) {
            HomitaOfflineBanner(freshness: DataFreshness.shared)
        }
        .onChange(of: deepLinks.pending) { _, link in handle(link) }
        .task { handle(deepLinks.pending) }
    }

    /// Lleva a la pestaña del enlace. «Nueva tarea/evento» y «Ajustes › Notificaciones» los termina
    /// de atender la pantalla de destino (Inicio, Ajustes), que consume el enlace.
    private func handle(_ link: HomitaDeepLink?) {
        guard let link else { return }
        switch link {
        case .nuevaTarea, .nuevoEvento:
            selectedTab = 0
        case .rutinas:
            calendarSegment = 1; selectedTab = 2; deepLinks.consume(link)
        case .calendario:
            calendarSegment = 0; selectedTab = 2; deepLinks.consume(link)
        case .tareas:
            taskListRequest = nil; selectedTab = 1; deepLinks.consume(link)
        case .ajustesNotificaciones:
            selectedTab = 4
        }
    }
}
