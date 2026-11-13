import Foundation

/// Estado de las vistas de calendario mes/semana/día (B3). Lee `GET event` del rango visible
/// SIN filtrar `routine`, así las sesiones de rutina aparecen junto a los eventos.
@Observable
public final class CalendarAgendaStore {
    public var mode: CalendarMode = .month
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

    /// Días del modo actual (cuadrícula, semana o día).
    public var visibleDays: [Date] {
        grid.visibleDays(mode: mode, anchor: anchor)
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
            // routine: nil → el servidor devuelve eventos y sesiones de rutina.
            let filters = EventFilters(startDate: range.start, endDate: range.end, timezone: timezone)
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

    /// Cambia el modo y recarga el rango correspondiente.
    public func setMode(_ newMode: CalendarMode) async {
        mode = newMode
        await load()
    }

    /// Mueve la fecha ancla un paso (mes, semana o día según el modo) y recarga.
    public func move(_ steps: Int) async {
        anchor = grid.shift(anchor, mode: mode, by: steps)
        await load()
    }

    /// Selecciona un día (toque en la cuadrícula). Recarga solo si cambia el rango visible (R1-07).
    public func select(_ day: Date) async {
        let before = visibleDays
        anchor = grid.day(of: day)
        guard visibleDays != before else { return }
        await load()
    }
}
