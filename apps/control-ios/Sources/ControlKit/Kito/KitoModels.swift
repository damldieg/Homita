import Foundation

/// Autor de un mensaje del chat de Kito.
public enum KitoRole: String, Codable, Sendable {
    case user
    case assistant
}

/// Mensaje del chat. El historial vive solo en el móvil (`KitoHistoryStore`); el servidor no lo guarda.
public struct KitoMessage: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let role: KitoRole
    public let text: String
    public let date: Date

    public init(id: UUID = UUID(), role: KitoRole, text: String, date: Date = Date()) {
        self.id = id
        self.role = role
        self.text = text
        self.date = date
    }
}

/// Cuerpo de `POST asistente`: solo role y content, y los últimos mensajes del historial.
struct KitoAPIRequest: Encodable, Equatable {
    struct Item: Encodable, Equatable {
        let role: String
        let content: String
    }

    let messages: [Item]
    let timezone: String

    /// El servidor admite como máximo `maxMessages` mensajes y el último debe ser del usuario.
    static func make(history: [KitoMessage], timezone: String, maxMessages: Int = KitoLimits.maxMessages) -> KitoAPIRequest {
        let recientes = history.suffix(maxMessages).map { Item(role: $0.role.rawValue, content: $0.text) }
        return KitoAPIRequest(messages: Array(recientes), timezone: timezone)
    }
}

/// Respuesta de `POST asistente`. Las tarjetas (fase 2) se ignoran hasta que la app las pinte.
public struct KitoReply: Decodable, Equatable, Sendable {
    public struct Usage: Decodable, Equatable, Sendable {
        public let usados: Int
        public let limite: Int
    }

    public let texto: String
    public let uso: Usage?
}

/// Límites que la app conoce del contrato. El tope diario lo decide el servidor (`fn_assistant_daily_limit`).
public enum KitoLimits {
    /// Máximo de mensajes que se envían en cada petición (contrato de la Edge `asistente`).
    public static let maxMessages = 20
    /// Máximo de caracteres por mensaje (contrato de la Edge `asistente`).
    public static let maxChars = 2000
}
