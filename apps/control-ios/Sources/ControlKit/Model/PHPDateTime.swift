import Foundation

/// Fechas del contrato PHP: `Y-m-d H:i:s` (`date_at`, `created_at`, …) y `Y-m-d`
/// (`start_date`, `end_date`, `routine_date`). Son horas locales flotantes: se parsean y
/// formatean con `en_US_POSIX` en la zona actual, sin conversión (igual que Android/dashboard).
public enum PHPDateTime {
    /// `Y-m-d H:i:s`.
    public static let dateTimeTemplate = "yyyy-MM-dd HH:mm:ss"
    /// `Y-m-d`.
    public static let dayTemplate = "yyyy-MM-dd"

    private static let cacheLock = NSLock()
    private static var cache: [String: DateFormatter] = [:]

    private static func formatter(_ template: String, timeZone: TimeZone) -> DateFormatter {
        let key = "\(template)|\(timeZone.identifier)"
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let cached = cache[key] { return cached }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = template
        formatter.timeZone = timeZone
        cache[key] = formatter
        return formatter
    }

    /// `"2026-11-08 09:30:00"` → Date en la zona dada (por defecto la actual).
    public static func parse(_ string: String, timeZone: TimeZone = .current) -> Date? {
        formatter(dateTimeTemplate, timeZone: timeZone).date(from: string)
    }

    /// Date → `"Y-m-d H:i:s"` (hora local flotante).
    public static func format(_ date: Date, timeZone: TimeZone = .current) -> String {
        formatter(dateTimeTemplate, timeZone: timeZone).string(from: date)
    }

    /// `"2026-11-08"` → Date (00:00 en la zona dada).
    public static func parseDay(_ string: String, timeZone: TimeZone = .current) -> Date? {
        formatter(dayTemplate, timeZone: timeZone).date(from: string)
    }

    /// Date → `"Y-m-d"`.
    public static func formatDay(_ date: Date, timeZone: TimeZone = .current) -> String {
        formatter(dayTemplate, timeZone: timeZone).string(from: date)
    }
}
