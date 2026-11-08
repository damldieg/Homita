import Foundation

/// Regla de una rutina (`frequency` + `interval` + `days` ISO + inicio/fin). La materialización
/// real la hace el backend; este tipo valida el formulario (mismas reglas que `Routine.php`) y
/// calcula si una fecha toca, para la vista previa del editor y la etiqueta de próxima sesión.
public struct RoutineRule: Equatable, Sendable {
    public enum Frequency: String, CaseIterable, Sendable {
        case daily
        case weekly
        case monthly
    }

    public enum ValidationError: Error, Equatable, Sendable {
        case frequency
        case interval
        case days
        case dateRange
    }

    public let frequency: Frequency
    /// Cada cuántos días/semanas/meses (1-99 en el contrato).
    public let interval: Int
    /// Días ISO 1-7 (solo semanal).
    public let days: [Int]
    public let startDate: Date
    public let endDate: Date?

    public init(frequency: Frequency, interval: Int, days: [Int], startDate: Date, endDate: Date?) throws {
        guard (1...99).contains(interval) else { throw ValidationError.interval }
        if frequency == .weekly {
            guard !days.isEmpty, days.allSatisfy({ (1...7).contains($0) }), Set(days).count == days.count else {
                throw ValidationError.days
            }
        }
        if let endDate, endDate < startDate {
            throw ValidationError.dateRange
        }
        self.frequency = frequency
        self.interval = interval
        self.days = days.sorted()
        self.startDate = startDate
        self.endDate = endDate
    }

    /// ¿Toca la rutina en `date` (mismo día local)? Semántica del editor: diaria cada N días desde
    /// el inicio; semanal en los días ISO elegidos cada N semanas contadas desde la semana ISO del
    /// inicio; mensual cada N meses el mismo día del mes que el inicio.
    public func occurs(on date: Date, timeZone: TimeZone = .current) -> Bool {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = timeZone
        let startDay = calendar.startOfDay(for: startDate)
        let day = calendar.startOfDay(for: date)
        guard day >= startDay else { return false }
        if let endDate, day > calendar.startOfDay(for: endDate) { return false }

        switch frequency {
        case .daily:
            guard let days = calendar.dateComponents([.day], from: startDay, to: day).day else { return false }
            return days % interval == 0
        case .weekly:
            // `weekday` de Foundation es 1=domingo…7=sábado: se convierte a ISO 1=lunes…7=domingo
            // (los `days` del contrato son días ISO).
            let weekday = ((calendar.component(.weekday, from: day) + 5) % 7) + 1
            guard days.contains(weekday) else { return false }
            guard let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: startDay)?.start,
                  let week = calendar.dateComponents([.weekOfYear], from: startOfWeek, to: day).weekOfYear else {
                return false
            }
            return week % interval == 0
        case .monthly:
            guard let months = calendar.dateComponents([.month], from: startDay, to: day).month else { return false }
            guard months % interval == 0 else { return false }
            return calendar.component(.day, from: day) == calendar.component(.day, from: startDay)
        }
    }
}
