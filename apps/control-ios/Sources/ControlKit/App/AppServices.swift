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
    public let feedback: FeedbackRepository
    public let homeContext: HomeContextStore
    /// Kito (asistente): cliente de la Edge `asistente` e historial local por usuario y hogar.
    public let kitoAPI: KitoAPI
    public let kitoHistory: KitoHistoryStore
    /// Reproduce la cola offline del hogar activo (D-024); uno por app, vuelo único por cola.
    public let outboxReplayer: OutboxReplayer

    /// En el hilo principal: crea el replayer de la cola offline (`@MainActor`).
    @MainActor
    public init(config: AppConfig, session: SessionStore, tokenStore: TokenStore, http: URLSession = .shared) {
        self.config = config
        self.session = session
        let homeContext = HomeContextStore(store: tokenStore)
        self.homeContext = homeContext
        let kitoHistory = KitoHistoryStore(directory: KitoHistoryStore.defaultDirectory())
        self.kitoHistory = kitoHistory
        let client = APIClient(
            baseURL: config.homitaBaseURL,
            session: http,
            tokenProvider: { [weak session] in session?.accessToken },
            homeIdProvider: { [weak homeContext] in homeContext?.activeHomeId }
        )
        // La cola offline no se toca aquí: se conserva al caducar la sesión (D-024, R1).
        client.onSessionExpired = { [weak session, weak homeContext] in
            Task { @MainActor in
                // Mismo orden que signOut(): primero el hogar activo, luego la sesión (C3).
                homeContext?.clear()
                ReadCache.shared.clear()
                DataFreshness.shared.markFresh()
                if let uid = session?.session?.id { kitoHistory.clear(userId: uid) }
                session?.signOut()
                await HomitaSync.shared.reset()
            }
        }
        let auth = AuthService(client: client, session: session, config: config, http: http)
        client.refresher = auth
        self.auth = auth
        // Kito usa la base de funciones y la misma sesión, refresco y hogar que `api`.
        let kitoClient = APIClient(
            baseURL: KitoAPI.functionsBaseURL(fromAPIBaseURL: config.homitaBaseURL),
            session: http,
            tokenProvider: { [weak session] in session?.accessToken },
            homeIdProvider: { [weak homeContext] in homeContext?.activeHomeId }
        )
        kitoClient.refresher = auth
        kitoClient.onSessionExpired = client.onSessionExpired
        self.kitoAPI = KitoAPI(client: kitoClient)
        calendars = CalendarRepository(client: client)
        events = EventRepository(client: client)
        routines = RoutineRepository(client: client)
        taskLists = TaskListRepository(client: client)
        tasks = TaskRepository(client: client)
        persons = PersonRepository(client: client)
        homes = HomeRepository(client: client)
        feedback = FeedbackRepository(client: client)
        outboxReplayer = OutboxReplayer(tasks: tasks, taskLists: taskLists)
    }

    /// Cola offline del usuario en el hogar activo; nil sin sesión o sin hogar.
    @MainActor
    public var activeOutbox: OutboxStore? {
        guard let userId = session.session?.id, let homeId = homeContext.activeHomeId else { return nil }
        return OutboxRegistry.shared.store(user: userId, home: homeId)
    }

    /// Reproduce la cola del hogar activo (red recuperada, primer plano, segundo plano, «Reintentar»).
    /// Las colas de otros hogares esperan a que ese hogar vuelva a estar activo.
    @MainActor
    @discardableResult
    public func replayOutbox() async -> ReplaySummary? {
        guard let outbox = activeOutbox, !outbox.isEmpty else { return nil }
        return await outboxReplayer.replay(outbox)
    }

    /// Cierra sesión: limpia primero el hogar activo y luego la sesión. Único camino de logout.
    /// Borra también las colas offline (los cambios pendientes se pierden, D-024).
    @MainActor
    public func signOut() {
        homeContext.clear()
        ReadCache.shared.clear()
        OutboxRegistry.shared.removeAll()
        Task { @MainActor in
            DataFreshness.shared.markFresh()
            // Avisos, datos de widgets y Live Activity del usuario anterior fuera.
            await HomitaSync.shared.reset()
        }
        if let uid = session.session?.id { kitoHistory.clear(userId: uid) }
        session.signOut()
    }

    /// Servicios propios para el refresco en segundo plano, cuando el sistema lanza la app sin
    /// interfaz: misma config y misma sesión del Keychain que la app.
    @MainActor
    public static func makeBackground() -> AppServices {
        let tokenStore = KeychainTokenStore()
        let session = SessionStore(store: tokenStore)
        session.restore()
        return AppServices(config: AppConfig.load(), session: session, tokenStore: tokenStore)
    }
}
