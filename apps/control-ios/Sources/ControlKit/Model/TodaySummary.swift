import Foundation

extension LocalClock {
    /// Ventana del día local de `now`: epoch de 10 dígitos de las 00:00 y de las 23:59:59
    /// (para `start_date`/`end_date` de `GET event`).
    public var dayRange: (start: String, end: String) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let start = calendar.startOfDay(for: now)
        let startEpoch = Self.epochString(for: start, timeZone: timeZone)
        let endEpoch = String((Int(startEpoch) ?? 0) + 86_399)
        return (startEpoch, endEpoch)
    }
}

extension RoutineEntry {
    /// Regla de la rutina para calcular si toca un día. `nil` si el contrato no alcanza para
    /// construirla: `frequency` ausente (backends antiguos) se trata como semanal solo si hay
    /// `days`; si no, se omite. También `nil` ante datos inválidos.
    public func rule(timeZone: TimeZone = .current) -> RoutineRule? {
        let resolved: RoutineRule.Frequency
        if let frequency {
            guard let parsed = RoutineRule.Frequency(rawValue: frequency) else { return nil }
            resolved = parsed
        } else if !weekdays.isEmpty {
            resolved = .weekly
        } else {
            return nil
        }
        guard let start = PHPDateTime.parseDay(String(start_date.prefix(10)), timeZone: timeZone) else { return nil }
        let end = end_date.flatMap { PHPDateTime.parseDay(String($0.prefix(10)), timeZone: timeZone) }
        return try? RoutineRule(
            frequency: resolved,
            interval: intervalValue,
            days: resolved == .weekly ? weekdays : [],
            startDate: start,
            endDate: end
        )
    }
}

/// Lógica pura del resumen de Inicio: eventos de hoy, tareas pendientes y rutinas de hoy.
public enum TodaySummary {
    /// Tareas pendientes mostradas en Inicio.
    public static let taskLimit = 5

    /// Eventos cuyo `date_at` cae en el día de `day`, ordenados por hora. El contrato no trae fin
    /// de evento: uno de varios días solo cuenta en su día de inicio.
    public static func events(_ events: [EventEntry], on day: Date, timeZone: TimeZone = .current) -> [EventEntry] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return events
            .compactMap { event -> (EventEntry, Date)? in
                guard let date = PHPDateTime.parse(event.date_at, timeZone: timeZone),
                      calendar.isDate(date, inSameDayAs: day) else { return nil }
                return (event, date)
            }
            .sorted { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0.id < $1.0.id }
            .map(\.0)
    }

    /// Margen tras el inicio de un evento antes de darlo por pasado en Inicio (el contrato no trae fin).
    public static let eventPastGrace: TimeInterval = 3600

    /// Separa los eventos de hoy en «ya pasaron» (empezaron hace más de `eventPastGrace`) y
    /// «próximos o en curso», conservando el orden recibido.
    public static func splitEvents(_ events: [EventEntry], now: Date, timeZone: TimeZone = .current)
        -> (past: [EventEntry], upcoming: [EventEntry]) {
        var past: [EventEntry] = []
        var upcoming: [EventEntry] = []
        for event in events {
            if let date = PHPDateTime.parse(event.date_at, timeZone: timeZone),
               date.addingTimeInterval(eventPastGrace) <= now {
                past.append(event)
            } else {
                upcoming.append(event)
            }
        }
        return (past, upcoming)
    }

    /// Pendientes (no completadas) por `order` y luego `id`, las primeras `limit`.
    public static func pendingTasks(_ tasks: [TaskEntry], limit: Int = taskLimit) -> [TaskEntry] {
        Array(
            tasks.filter { !$0.isCompleted }
                .sorted { $0.orderValue != $1.orderValue ? $0.orderValue < $1.orderValue : $0.id < $1.id }
                .prefix(max(limit, 0))
        )
    }

    /// Rutinas activas que tocan en `day` (`RoutineRule.occurs`), ordenadas por `time`.
    public static func routines(_ routines: [RoutineEntry], on day: Date, timeZone: TimeZone = .current) -> [RoutineEntry] {
        routines
            .filter { routine in
                guard routine.isActive, let rule = routine.rule(timeZone: timeZone) else { return false }
                return rule.occurs(on: day, timeZone: timeZone)
            }
            .sorted { $0.time != $1.time ? $0.time < $1.time : $0.id < $1.id }
    }
}
