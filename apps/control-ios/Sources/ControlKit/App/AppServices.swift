import Foundation

/// Raíz de composición: config + sesión única + cliente API + repositorios. Sin DI framework.
public struct AppServices {
    public let config: AppConfig
    public let session: SessionStore
    public let auth: AuthService
    public let calendars: CalendarRepository
    public let events: EventRepository
    public let routines: RoutineRepository
    public let taskLists: TaskListRepository
    public let tasks: TaskRepository
    public let persons: PersonRepository
    public let homes: HomeRepository
    public let homeContext: HomeContextStore

    public init(config: AppConfig, session: SessionStore, tokenStore: TokenStore, http: URLSession = .shared) {
        self.config = config
        self.session = session
        let homeContext = HomeContextStore(store: tokenStore)
        self.homeContext = homeContext
        let client = APIClient(
            baseURL: config.planifyBaseURL,
            session: http,
            tokenProvider: { [weak session] in session?.accessToken },
            homeIdProvider: { [weak homeContext] in homeContext?.activeHomeId }
        )
        client.onSessionExpired = { [weak session, weak homeContext] in
            Task { @MainActor in
                // Mismo orden que signOut(): primero el hogar activo, luego la sesión (C3).
                homeContext?.clear()
                ReadCache.shared.clear()
                DataFreshness.shared.markFresh()
                session?.signOut()
                await HomitaSync.shared.reset()
            }
        }
        let auth = AuthService(client: client, session: session, config: config, http: http)
        client.refresher = auth
        self.auth = auth
        calendars = CalendarRepository(client: client)
        events = EventRepository(client: client)
        routines = RoutineRepository(client: client)
        taskLists = TaskListRepository(client: client)
        tasks = TaskRepository(client: client)
        persons = PersonRepository(client: client)
        homes = HomeRepository(client: client)
    }

    /// Cierra sesión: limpia primero el hogar activo y luego la sesión. Único camino de logout.
    public func signOut() {
        homeContext.clear()
        ReadCache.shared.clear()
        Task { @MainActor in
            DataFreshness.shared.markFresh()
            // Avisos, datos de widgets y Live Activity del usuario anterior fuera.
            await HomitaSync.shared.reset()
        }
        session.signOut()
    }

    /// Servicios propios para el refresco en segundo plano, cuando el sistema lanza la app sin
    /// interfaz: misma config y misma sesión del Keychain que la app.
    public static func makeBackground() -> AppServices {
        let tokenStore = KeychainTokenStore()
        let session = SessionStore(store: tokenStore)
        session.restore()
        return AppServices(config: AppConfig.load(), session: session, tokenStore: tokenStore)
    }
}
