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
}
