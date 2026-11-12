import Foundation

/// Resumen en lenguaje natural de la regla de una rutina (E3-06). Puro, sin UI.
/// Ejemplos: «Todos los días a las 09:30», «Cada 2 semanas los lunes, miércoles y viernes a las 20:00».
public enum RoutineSummary {
    private static let weekdayNames = ["lunes", "martes", "miércoles", "jueves", "viernes", "sábados", "domingos"]

    /// `frequency`: "daily" | "weekly" | "monthly" (como en el editor). `days`: ISO 1 (lunes) a 7 (domingo).
    /// `hour`: "HH:mm".
    public static func text(frequency: String, interval: Int, days: [Int], hour: String) -> String {
        let every = max(interval, 1)
        switch frequency {
        case "daily":
            return every == 1 ? "Todos los días a las \(hour)" : "Cada \(every) días a las \(hour)"
        case "weekly":
            let names = days.sorted().compactMap(weekdayName)
            let on = names.isEmpty ? "" : " los \(joined(names))"
            return every == 1 ? "Todas las semanas\(on) a las \(hour)" : "Cada \(every) semanas\(on) a las \(hour)"
        case "monthly":
            return every == 1 ? "Todos los meses a las \(hour)" : "Cada \(every) meses a las \(hour)"
        default:
            return "Sin frecuencia definida"
        }
    }

    static func weekdayName(_ iso: Int) -> String? {
        (1...7).contains(iso) ? weekdayNames[iso - 1] : nil
    }

    /// «a», «a y b», «a, b y c».
    static func joined(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        default: return items.dropLast().joined(separator: ", ") + " y " + items[items.count - 1]
        }
    }
}
