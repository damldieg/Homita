import Foundation

/// Modos de la vista de calendario (B3).
public enum CalendarMode: Int, CaseIterable, Identifiable, Sendable {
    case month, week, day

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .month: "Mes"
        case .week: "Semana"
        case .day: "Día"
        }
    }
}

/// Cálculo puro de días visibles y rangos de consulta del calendario (B3). Semana empieza en lunes.
/// La zona horaria se inyecta para poder probarlo sin depender del dispositivo.
public struct CalendarGrid: Sendable {
    public let calendar: Calendar
    public let timeZone: TimeZone

    public init(timeZone: TimeZone = .current) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.firstWeekday = 2
        calendar.locale = DeviceLocale.current
        self.calendar = calendar
        self.timeZone = timeZone
    }

    /// Días que se muestran para el modo y la fecha ancla. Mes: cuadrícula de 5 o 6 semanas completas
    /// (incluye días de los meses vecinos para rellenar); semana: lunes a domingo; día: solo el ancla.
    public func visibleDays(mode: CalendarMode, anchor: Date) -> [Date] {
        switch mode {
        case .month:
            guard let monthStart = calendar.dateInterval(of: .month, for: anchor)?.start,
                  let gridStart = calendar.dateInterval(of: .weekOfYear, for: monthStart)?.start,
                  let monthEnd = calendar.date(byAdding: .day, value: -1, to: calendar.dateInterval(of: .month, for: anchor)?.end ?? anchor)
            else { return [calendar.startOfDay(for: anchor)] }
            let lastWeekStart = calendar.dateInterval(of: .weekOfYear, for: monthEnd)?.start ?? monthEnd
            let weeks = (calendar.dateComponents([.day], from: gridStart, to: lastWeekStart).day ?? 0) / 7 + 1
            return (0..<(weeks * 7)).compactMap { calendar.date(byAdding: .day, value: $0, to: gridStart) }
        case .week:
            guard let start = calendar.dateInterval(of: .weekOfYear, for: anchor)?.start else { return [anchor] }
            return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
        case .day:
            return [calendar.startOfDay(for: anchor)]
        }
    }

    /// Desplaza la fecha ancla un paso del modo: mes ±1 mes, semana ±7 días, día ±1 día.
    public func shift(_ anchor: Date, mode: CalendarMode, by steps: Int) -> Date {
        switch mode {
        case .month: return calendar.date(byAdding: .month, value: steps, to: anchor) ?? anchor
        case .week: return calendar.date(byAdding: .day, value: 7 * steps, to: anchor) ?? anchor
        case .day: return calendar.date(byAdding: .day, value: steps, to: anchor) ?? anchor
        }
    }

    /// Epochs locales (10 dígitos) de inicio y fin del rango de días visibles: `start_date` y
    /// `end_date` de `GET event` (fin = último segundo del último día).
    public func queryRange(days: [Date]) -> (start: String, end: String)? {
        guard let first = days.first, let last = days.last,
              let endOfLast = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: last)),
              let endSecond = calendar.date(byAdding: .second, value: -1, to: endOfLast)
        else { return nil }
        return (
            LocalClock.epochString(for: calendar.startOfDay(for: first), timeZone: timeZone),
            LocalClock.epochString(for: endSecond, timeZone: timeZone)
        )
    }

    /// Inicio del día local de una fecha.
    public func day(of date: Date) -> Date {
        calendar.startOfDay(for: date)
    }
}
