import Foundation

/// Estado de una rutina según el horario de inicio de su ocurrencia de hoy (regla pura, sin UI).
/// Se calcula en el cliente con la hora del dispositivo.
public enum RoutineStatus: Equatable, Sendable {
    /// Pasada 1 h desde el inicio.
    case expired
    /// Dentro de la hora desde el inicio (inclusive en ambos extremos).
    case inProgress
    /// Resto: aún no empieza o no tiene hora fija.
    case normal

    /// Duración de la ventana "en curso".
    public static let window: TimeInterval = 3600

    /// Estado dado el inicio de la ocurrencia (`nil` = sin hora fija → normal) y "ahora".
    public static func evaluate(start: Date?, now: Date) -> RoutineStatus {
        guard let start else { return .normal }
        if now > start.addingTimeInterval(window) { return .expired }
        if now >= start { return .inProgress }
        return .normal
    }

    /// Inicio de la ocurrencia a evaluar entre las de hoy: la última que ya empezó; si ninguna
    /// empezó (o no hay), `nil` → normal.
    public static func relevantStart(among starts: [Date], now: Date) -> Date? {
        starts.filter { $0 <= now }.max()
    }

    /// Estado sobre la ocurrencia que se muestra. `started` = última ocurrencia de hoy que ya empezó;
    /// `next` = próxima ocurrencia futura. En curso gana siempre; si hay próxima (hoy más tarde,
    /// mañana o posterior) → normal (la de hoy ya pasó y no cuenta); sin próxima, se evalúa la de hoy.
    public static func evaluateShown(started: Date?, next: Date?, now: Date) -> RoutineStatus {
        let current = evaluate(start: started, now: now)
        if current == .inProgress { return .inProgress }
        if next != nil { return .normal }
        return current
    }

    /// `"HH:mm"` o `"HH:mm:ss"` del día de `now` → Date; `nil` si no hay hora fija (vacío o ilegible).
    public static func startToday(time: String, now: Date, timeZone: TimeZone = .current) -> Date? {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2, (0...23).contains(parts[0]), (0...59).contains(parts[1]) else { return nil }
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = timeZone
        return calendar.date(bySettingHour: parts[0], minute: parts[1], second: parts.count > 2 ? parts[2] : 0, of: now)
    }
}

extension RoutineEntry {
    /// ¿Tiene hora fija de inicio? (`time` legible como hora.)
    public var hasFixedTime: Bool {
        RoutineStatus.startToday(time: time, now: Date()) != nil
    }
}
