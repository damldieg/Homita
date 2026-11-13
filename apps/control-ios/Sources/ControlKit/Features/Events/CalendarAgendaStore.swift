import Foundation

/// Estado de la agenda de eventos por día: un día elegido (`anchor`) y la semana que lo contiene para la tira.
/// Lee `GET event` de la semana visible con `routine=false`: las sesiones de rutina no se mezclan con los
/// eventos, tienen su propio segmento (Rutinas). Una sola petición por semana alimenta tira y lista.
@Observable
public final class CalendarAgendaStore {
    /// Día elegido; cambia con la tira, las flechas, el gesto de deslizar o el selector de fecha.
    public var anchor: Date
    public private(set) var events: [EventEntry] = []
    public private(set) var isLoading = false
    /// Primera carga del rango visible completada (el loader sustituye al vacío hasta entonces).
    public private(set) var hasLoaded = false
    public var errorMessage: String?

    private let repo: EventRepository
    public let grid: CalendarGrid
    private let now: () -> Date
    /// Generación de cargas: cada `load()` la incrementa. Una respuesta de un rango anterior
    /// (navegación rápida) se descarta y no pisa `events` ni `errorMessage` (R1-01).
    private var generation = 0

    public init(repo: EventRepository, grid: CalendarGrid = CalendarGrid(), now: @escaping () -> Date = { Date() }) {
        self.repo = repo
        self.grid = grid
        self.now = now
        self.anchor = grid.day(of: now())
    }

    private var timezone: String { grid.timeZone.identifier }

    /// Los 7 días (lunes a domingo) de la semana del día elegido: tira y rango de la consulta.
    public var visibleDays: [Date] {
        grid.visibleDays(mode: .week, anchor: anchor)
    }

    public var isToday: Bool {
        grid.day(of: anchor) == grid.day(of: now())
    }

    /// Eventos de un día, ordenados por hora.
    public func events(on day: Date) -> [EventEntry] {
        let start = grid.day(of: day)
        return events
            .filter { event in
                guard let date = PHPDateTime.parse(event.date_at, timeZone: grid.timeZone) else { return false }
                return grid.day(of: date) == start
            }
            .sorted { $0.date_at < $1.date_at }
    }

    public func load() async {
        generation &+= 1
        let token = generation
        isLoading = true
        guard let range = grid.queryRange(days: visibleDays) else {
            isLoading = false
            hasLoaded = true
            return
        }
        do {
            // routine: false → solo eventos; las sesiones de rutina se ven en el segmento Rutinas.
            let filters = EventFilters(startDate: range.start, endDate: range.end, routine: false, timezone: timezone)
            let result = try await repo.index(filters)
            guard token == generation else { return }
            events = result
            errorMessage = nil
        } catch {
            // Una carga cancelada (p. ej. al salir de la pestaña) no muestra error.
            if token == generation, !Task.isCancelled {
                errorMessage = (error as? APIError)?.userMessage ?? error.localizedDescription
            }
        }
        // Solo la carga más reciente apaga el loader; una cancelada no cuenta como primera carga (N2-02).
        if token == generation {
            isLoading = false
            if !Task.isCancelled { hasLoaded = true }
        }
    }

    /// Mueve el día elegido (±1 día) y recarga solo si cambia de semana.
    public func move(_ steps: Int) async {
        await select(grid.shift(anchor, mode: .day, by: steps))
    }

    /// Elige un día (tira, flechas, deslizar o selector). Recarga solo si cambia la semana visible (R1-07).
    public func select(_ day: Date) async {
        let before = visibleDays
        anchor = grid.day(of: day)
        guard visibleDays != before else { return }
        await load()
    }

    /// Vuelve a hoy.
    public func goToToday() async {
        await select(now())
    }
}
