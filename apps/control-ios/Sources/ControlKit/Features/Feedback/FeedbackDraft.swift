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
    /// Límite de caracteres del texto (igual que el servidor, `FEEDBACK_TEXTO_MAX`).
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
        !trimmedText.isEmpty && text.count <= Self.maxLength
            && section != nil && subseccion != nil && kind != nil
    }

    public var request: FeedbackRequest? {
        guard isValid, let section, let subseccion, let kind else { return nil }
        return FeedbackRequest(seccion: section.name, subseccion: subseccion, tipo: kind.rawValue, texto: trimmedText)
    }
}
