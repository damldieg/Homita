import Foundation

/// Fechas del contrato («yyyy-MM-dd HH:mm:ss», hora local) mostradas en el idioma del sistema (U1).
/// Si el texto no se puede leer, se devuelve tal cual: nunca se pierde el dato.
public enum DateDisplay {
    /// Ejemplo en es: «dom 8 nov, 9:30».
    public static func dateTime(_ raw: String, timeZone: TimeZone = .current, locale: Locale = DeviceLocale.current) -> String {
        guard let date = PHPDateTime.parse(raw, timeZone: timeZone) else { return raw }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate("EEE d MMM H:mm")
        return formatter.string(from: date)
    }

    /// Rango de un evento de varios días, p. ej. «10 nov → 20 nov» (inicio → fin inclusive). `nil`
    /// si no hay fin, si no se puede leer o si el fin cae el mismo día del inicio.
    public static func eventRange(dateAt: String, endDate: String?, timeZone: TimeZone = .current, locale: Locale = DeviceLocale.current) -> String? {
        guard let endDate, !endDate.isEmpty,
              let start = PHPDateTime.parse(dateAt, timeZone: timeZone),
              let end = PHPDateTime.parseDay(endDate, timeZone: timeZone) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        if calendar.isDate(start, inSameDayAs: end) { return nil }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate("d MMM")
        return "\(formatter.string(from: start)) → \(formatter.string(from: end))"
    }
}
