import Foundation

/// Reloj local para los filtros de fecha del contrato. El backend guarda fechas como texto local
/// (`Y-m-d H:i:s`) y los filtros `start_date`/`end_date` son epochs de 10 dígitos que se comparan
/// contra ese texto: el valor correcto es la hora local expresada como epoch "como si fuese UTC"
/// (igual que Android: `((nowMillis + offset) / 1000)`). Un epoch de 13 dígitos NO es error:
/// el backend lo ignora y queda sin filtro.
public struct LocalClock: Equatable, Sendable {
    public let now: Date
    public let timeZone: TimeZone

    public init(now: Date = Date(), timeZone: TimeZone = .current) {
        self.now = now
        self.timeZone = timeZone
    }

    /// Epoch de 10 dígitos de `now` (para `start_date`/`end_date`).
    public var localNowEpoch: String {
        Self.epochString(for: now, timeZone: timeZone)
    }

    /// Epoch de 10 dígitos del primer día del mes en curso a las 00:00 (para las sesiones de
    /// rutina de la vista mensual, como Android: `YearMonth.now().atDay(1).atStartOfDay()`).
    public var monthStartEpoch: String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month], from: now)
        let components = DateComponents(year: parts.year, month: parts.month, day: 1, hour: 0, minute: 0, second: 0)
        guard let start = calendar.date(from: components) else { return localNowEpoch }
        return Self.epochString(for: start, timeZone: timeZone)
    }

    /// Hora local como epoch de 10 dígitos: `epoch + offset de zona`, sin milisegundos.
    public static func epochString(for date: Date, timeZone: TimeZone) -> String {
        let seconds = date.timeIntervalSince1970 + Double(timeZone.secondsFromGMT(for: date))
        return String(Int(seconds.rounded(.down)))
    }
}
