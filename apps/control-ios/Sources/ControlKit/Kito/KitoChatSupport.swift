import Foundation

/// Aviso de cupo diario bajo la entrada del chat.
public enum KitoQuota {
    /// Con cuántos mensajes restantes empieza a avisar.
    public static let threshold = 10

    /// «Te quedan N mensajes hoy.» cuando quedan `threshold` o menos; `nil` si no hay datos o sobra cupo.
    public static func remainingNotice(_ uso: KitoReply.Usage?) -> String? {
        guard let uso else { return nil }
        let restantes = uso.limite - uso.usados
        guard restantes <= threshold else { return nil }
        switch restantes {
        case ...0: return "Hoy ya no me quedan mensajes."
        case 1: return "Te queda 1 mensaje hoy."
        default: return "Te quedan \(restantes) mensajes hoy."
        }
    }

    /// `true` si el cupo está agotado (el aviso va en tono más suave).
    public static func isExhausted(_ uso: KitoReply.Usage?) -> Bool {
        guard let uso else { return false }
        return uso.limite - uso.usados <= 0
    }
}

/// Sugerencias de la bienvenida. En código para poder cambiarlas por skill más adelante.
public enum KitoSuggestions {
    public static let all = [
        "¿Qué tengo hoy?",
        "¿Qué tareas tengo pendientes?",
        "¿Qué rutinas tengo mañana?",
        "¿Qué hay en la lista de la compra?",
        "¿Cómo comparto una lista?",
    ]
}

/// Textos de la bienvenida y etiquetas de día del chat.
public enum KitoGreeting {
    /// Saludo según la hora: noche antes de las 6 y desde las 20, mañana hasta las 13, tarde el resto.
    public static func salutation(date: Date = Date(), calendar: Calendar = .current) -> String {
        let hour = calendar.component(.hour, from: date)
        if hour < 6 || hour >= 20 { return "Buenas noches" }
        if hour < 13 { return "Buenos días" }
        return "Buenas tardes"
    }

    /// «¡Hola, Ana! Soy Kito.»; sin nombre, «¡Hola! Soy Kito.». Solo la primera palabra del nombre.
    public static func text(name: String?) -> String {
        let first = name?.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
        return first.isEmpty ? "¡Hola! Soy Kito." : "¡Hola, \(first)! Soy Kito."
    }

    public static let capabilities = "Pregúntame qué tienes hoy, qué hay pendiente o cómo se hace algo en Homita."

    /// «Hoy», «Ayer» o la fecha larga, para los separadores de día.
    public static func dayLabel(for date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Hoy" }
        if let ayer = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: ayer) { return "Ayer" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "d 'de' MMMM"
        return formatter.string(from: date)
    }
}

/// Markdown ligero de las respuestas: negrita, cursiva, enlaces y listas con guion.
public enum KitoMarkdown {
    public static func attributed(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        var result = AttributedString()
        let lines = text.components(separatedBy: "\n")
        for (index, line) in lines.enumerated() {
            let converted = bullet(line)
            if let parsed = try? AttributedString(markdown: converted, options: options) {
                result.append(parsed)
            } else {
                result.append(AttributedString(converted))
            }
            if index < lines.count - 1 { result.append(AttributedString("\n")) }
        }
        return result
    }

    /// `- x` o `* x` (con sangría opcional) pasa a `• x`.
    private static func bullet(_ line: String) -> String {
        let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
        guard let first = trimmed.first, first == "-" || first == "*" else { return line }
        let rest = trimmed.dropFirst()
        guard rest.first == " " else { return line }
        return "• " + rest.drop(while: { $0 == " " })
    }
}
