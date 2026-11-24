import Foundation

/// Fechas del menú: semanas y días como `YYYY-MM-DD` en la zona del hogar (nunca la del dispositivo).
public enum MealWeek {
    public static func calendar(_ timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = Locale(identifier: "es_ES")
        return calendar
    }

    public static func string(_ date: Date, timeZone: TimeZone) -> String {
        let c = calendar(timeZone).dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Mediodía del día `YYYY-MM-DD` en esa zona (evita saltos de horario de verano); nil si no es fecha.
    public static func date(_ day: String, timeZone: TimeZone) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, day.count == 10 else { return nil }
        return calendar(timeZone).date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }

    /// ISO: lunes = 1 … domingo = 7.
    public static func isoWeekday(_ day: String, timeZone: TimeZone) -> Int? {
        guard let date = date(day, timeZone: timeZone) else { return nil }
        let weekday = calendar(timeZone).component(.weekday, from: date) // domingo = 1
        return weekday == 1 ? 7 : weekday - 1
    }

    public static func addDays(_ day: String, _ days: Int, timeZone: TimeZone) -> String? {
        guard let date = date(day, timeZone: timeZone),
              let moved = calendar(timeZone).date(byAdding: .day, value: days, to: date) else { return nil }
        return string(moved, timeZone: timeZone)
    }

    /// Primer día de la semana (según `weekStartDay`, ISO 1…7) que contiene `date`.
    public static func weekStart(containing date: Date, weekStartDay: Int, timeZone: TimeZone) -> String {
        let today = string(date, timeZone: timeZone)
        let weekday = isoWeekday(today, timeZone: timeZone) ?? 1
        let back = (weekday - weekStartDay + 7) % 7
        return addDays(today, -back, timeZone: timeZone) ?? today
    }

    /// Los 7 días de la semana que empieza en `weekStart`.
    public static func days(of weekStart: String, timeZone: TimeZone) -> [String] {
        (0..<7).compactMap { addDays(weekStart, $0, timeZone: timeZone) }
    }
}
