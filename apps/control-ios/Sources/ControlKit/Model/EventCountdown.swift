import Foundation

/// Cuenta atrás de un evento próximo, misma regla que `countdown` del dashboard Android:
/// minutos enteros (truncados), `nil` si ya empezó o falta más de `maxMinutes`.
public enum EventCountdown {
    /// "ahora" / "en 25 min" / "en 1 h" / "en 1 h 10 min"; `nil` fuera de rango.
    public static func label(from now: Date, to start: Date, maxMinutes: Int = 120) -> String? {
        // Truncado hacia cero, como Duration.toMinutes() en Java
        let minutes = Int((start.timeIntervalSince(now) / 60).rounded(.towardZero))
        if minutes < 0 || minutes > maxMinutes { return nil }
        switch minutes {
        case 0: return "ahora"
        case 1..<60: return "en \(minutes) min"
        default:
            let rest = minutes % 60
            return rest == 0 ? "en \(minutes / 60) h" : "en \(minutes / 60) h \(rest) min"
        }
    }

    /// Etiqueta para un `date_at` del contrato (`Y-m-d H:i:s`, hora local flotante).
    public static func label(dateAt: String, now: Date = Date()) -> String? {
        guard let start = PHPDateTime.parse(dateAt) else { return nil }
        return label(from: now, to: start)
    }
}
