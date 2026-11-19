import Foundation

/// Fase de un evento respecto a «hoy» (D-020): un evento de varios días está «en curso» desde el día
/// de inicio hasta su último día (ambos inclusive), sin mirar la hora.
public enum EventPhase: Equatable, Sendable {
    case upcoming
    case ongoing
    case past
}

extension LocalClock {
    /// Día de calendario de `now` en `timeZone` (`yyyy-MM-dd`, gregoriano, `en_US_POSIX`).
    public var todayString: String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: now)
    }
}

extension EventEntry {
    /// Día de inicio (`yyyy-MM-dd`): prefijo de 10 caracteres de `date_at`.
    var startDay: String { String(date_at.prefix(10)) }

    /// `end_date` solo si es una fecha `yyyy-MM-dd` válida; nulo o malformado = sin fin.
    var validEndDay: String? {
        guard let end = end_date, end.count >= 10 else { return nil }
        let day = String(end.prefix(10))
        let parts = day.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m), (1...31).contains(d), y > 0 else { return nil }
        return day
    }

    /// «En curso» solo con fin válido y `inicio <= hoy <= fin`. Comparación de textos `yyyy-MM-dd`
    /// (orden lexicográfico = cronológico). Sin fin nunca está en curso.
    public func isOngoing(today: String) -> Bool {
        guard let end = validEndDay else { return false }
        return startDay <= today && today <= end
    }

    /// Fase con el día de `clock` (zona del dispositivo, DD-9). Sin fin: `upcoming`/`past` por el día
    /// de inicio solo si hace falta distinguir; los listados del servidor ya vienen separados, así
    /// que aquí un evento sin fin posterior a hoy es `upcoming` y el resto `past`.
    public func phase(clock: LocalClock) -> EventPhase {
        let today = clock.todayString
        if isOngoing(today: today) { return .ongoing }
        let last = validEndDay ?? startDay
        return today > last ? .past : .upcoming
    }
}
