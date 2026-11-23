import Foundation

/// Tramo de un evento de varios días dentro de una semana de la tira (columnas 0 = lunes … 6 = domingo).
public struct EventWeekSpan: Equatable, Sendable {
    public let eventId: Int
    public let colorHex: String
    /// Primera y última columna (inclusive) que ocupa la barra en esta semana.
    public let startColumn: Int
    public let endColumn: Int
    /// `true` si el evento empezó en una semana anterior: borde izquierdo recto con flecha.
    public let continuesBefore: Bool
    /// `true` si el evento sigue en una semana posterior: borde derecho recto con flecha.
    public let continuesAfter: Bool
    /// Fila (0 = la primera) en la que se apila la barra para no solaparse con otras.
    public let row: Int
}

/// Lógica pura de la vista semanal de eventos: navegación por semanas, barras de varios días,
/// apilado de solapados, «Día N de M» y título de fecha en español.
public enum CalendarWeekLayout {
    /// Locale fijo de la pantalla de eventos (fecha y selector).
    public static let locale = Locale(identifier: "es_ES")

    // MARK: - Navegación

    /// Semanas que avanza un arrastre sobre la tira: hacia la izquierda +1 (siguiente), hacia la derecha −1;
    /// `nil` si no es un swipe claramente horizontal (mismo umbral que la paginación de Inicio).
    public static func weekStep(swipeWidth width: Double, height: Double) -> Int? {
        guard InicioTaskPaging.isHorizontalSwipe(width: width, height: height) else { return nil }
        return width < 0 ? 1 : -1
    }

    // MARK: - Eventos de varios días

    /// Barras de los eventos de varios días que tocan la semana `weekDays` (7 textos `yyyy-MM-dd`, de lunes
    /// a domingo). Se apilan en filas: cada evento va a la primera fila libre en todas sus columnas.
    public static func spans(events: [EventEntry], weekDays: [String]) -> [EventWeekSpan] {
        guard let first = weekDays.first, let last = weekDays.last else { return [] }
        struct Candidate { let event: EventEntry; let start: String; let end: String; let startCol: Int; let endCol: Int }
        let candidates: [Candidate] = events.compactMap { event in
            guard let end = event.validEndDay else { return nil }
            let start = event.startDay
            guard start <= last, end >= first,
                  let startCol = weekDays.firstIndex(where: { $0 >= start }),
                  let endCol = weekDays.lastIndex(where: { $0 <= end }) else { return nil }
            return Candidate(event: event, start: start, end: end, startCol: startCol, endCol: endCol)
        }
        // Orden estable: empieza antes primero; a igual inicio, el más largo; luego por id.
        let sorted = candidates.sorted { a, b in
            if a.startCol != b.startCol { return a.startCol < b.startCol }
            if a.endCol != b.endCol { return a.endCol > b.endCol }
            return a.event.id < b.event.id
        }
        var rowEnds: [Int] = [] // última columna ocupada en cada fila
        var result: [EventWeekSpan] = []
        for item in sorted {
            let row: Int
            if let free = rowEnds.firstIndex(where: { $0 < item.startCol }) {
                row = free
                rowEnds[free] = item.endCol
            } else {
                row = rowEnds.count
                rowEnds.append(item.endCol)
            }
            result.append(EventWeekSpan(
                eventId: item.event.id,
                colorHex: item.event.calendar_color ?? Palette.fallbackItem,
                startColumn: item.startCol,
                endColumn: item.endCol,
                continuesBefore: item.start < first,
                continuesAfter: item.end > last,
                row: row
            ))
        }
        return result
    }

    /// Número de filas que ocupan las barras.
    public static func rowCount(_ spans: [EventWeekSpan]) -> Int {
        (spans.map(\.row).max() ?? -1) + 1
    }

    /// Posición del día `day` (`yyyy-MM-dd`) dentro de un evento de varios días: `(n, total)`, p. ej. (2, 5).
    /// `nil` si el evento es de un solo día o el día queda fuera de su rango.
    public static func dayPosition(of event: EventEntry, on day: String) -> (index: Int, total: Int)? {
        guard let end = event.validEndDay, event.startDay <= day, day <= end,
              let start = dayNumber(event.startDay), let last = dayNumber(end), let current = dayNumber(day)
        else { return nil }
        return (current - start + 1, last - start + 1)
    }

    /// Etiqueta «Día N de M» de un evento de varios días en el día dado; `nil` si no aplica.
    public static func dayLabel(of event: EventEntry, on day: String) -> String? {
        dayPosition(of: event, on: day).map { "Día \($0.index) de \($0.total)" }
    }

    // MARK: - Fecha

    /// Título del día en español con solo la inicial en mayúscula: «Lunes, 23 de noviembre».
    public static func dayTitle(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
        let text = formatter.string(from: date).lowercased(with: locale)
        return text.prefix(1).uppercased(with: locale) + text.dropFirst()
    }

    /// Letras de los días en español, de lunes a domingo («L M X J V S D»).
    public static func weekdayLetters() -> [String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        guard symbols.count == 7 else { return ["L", "M", "X", "J", "V", "S", "D"] }
        // veryShort… empieza en domingo (índice 0); se rota para que la semana empiece en lunes.
        return Array(symbols[1...]) + [symbols[0]]
    }

    // MARK: - Auxiliares

    /// Días transcurridos desde 1970-01-01 para un texto `yyyy-MM-dd` (gregoriano, UTC).
    static func dayNumber(_ ymd: String) -> Int? {
        let parts = ymd.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        guard let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else { return nil }
        return Int((date.timeIntervalSince1970 / 86_400).rounded())
    }
}
