import Foundation

/// Body de `POST /feedback`: `{seccion, subseccion, tipo, texto}` (sin `user_id`: lo pone el
/// servidor con el JWT).
public struct FeedbackRequest: Codable, Equatable, Sendable {
    public let seccion: String
    public let subseccion: String
    public let tipo: String
    public let texto: String

    public init(seccion: String, subseccion: String, tipo: String, texto: String) {
        self.seccion = seccion
        self.subseccion = subseccion
        self.tipo = tipo
        self.texto = texto
    }
}

/// Borrador del formulario de feedback: validación y mapeo al request (puro, sin red).
public struct FeedbackDraft: Equatable, Sendable {
    /// Límite de caracteres del texto en UTF-16 code units, igual que el servidor
    /// (`FEEDBACK_TEXTO_MAX`, `String.length` de JS); un emoji cuenta 2 en ambos lados.
    public static let maxLength = 2000

    public var section: FeedbackSection?
    public var areaName: String?
    public var action: FeedbackAction?
    public var kind: FeedbackKind?
    public var text: String

    public init(section: FeedbackSection? = nil, areaName: String? = nil, action: FeedbackAction? = nil,
                kind: FeedbackKind? = nil, text: String = "") {
        self.section = section
        self.areaName = areaName
        self.action = action
        self.kind = kind
        self.text = text
    }

    /// Longitud del texto en UTF-16 code units (el criterio del servidor).
    public static func length(of text: String) -> Int { text.utf16.count }

    /// Recorta a `maxLength` UTF-16 code units sin partir un grapheme (emoji).
    public static func clamped(_ text: String) -> String {
        var out = ""
        var used = 0
        for ch in text {
            let n = ch.utf16.count
            if used + n > maxLength { break }
            out.append(ch)
            used += n
        }
        return out
    }

    public var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var area: FeedbackArea? {
        guard let section, let areaName else { return nil }
        return section.area(named: areaName)
    }

    /// `"<sub-área>: <acción>"` (D2); `nil` si falta alguna de las dos.
    public var subseccion: String? {
        guard let area, let action, area.actions.contains(action) else { return nil }
        return "\(area.name): \(action.rawValue)"
    }

    /// Texto no vacío (tras recortar), sección, sub-área y acción elegidas y tipo elegido.
    public var isValid: Bool {
        !trimmedText.isEmpty && Self.length(of: trimmedText) <= Self.maxLength
            && section != nil && subseccion != nil && kind != nil
    }

    public var request: FeedbackRequest? {
        guard isValid, let section, let subseccion, let kind else { return nil }
        return FeedbackRequest(seccion: section.name, subseccion: subseccion, tipo: kind.rawValue, texto: trimmedText)
    }
}
