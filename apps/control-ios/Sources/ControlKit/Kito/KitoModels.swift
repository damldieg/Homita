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
    /// Tarjetas de la respuesta. `nil` en el historial antiguo, que no las guardaba.
    public let cards: [KitoCard]?

    public init(id: UUID = UUID(), role: KitoRole, text: String, date: Date = Date(), cards: [KitoCard]? = nil) {
        self.id = id
        self.role = role
        self.text = text
        self.date = date
        self.cards = cards
    }

    private enum CodingKeys: String, CodingKey { case id, role, text, date, cards }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        role = try c.decode(KitoRole.self, forKey: .role)
        text = try c.decode(String.self, forKey: .text)
        date = try c.decode(Date.self, forKey: .date)
        cards = try c.decodeIfPresent([KitoCard].self, forKey: .cards)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(role, forKey: .role)
        try c.encode(text, forKey: .text)
        try c.encode(date, forKey: .date)
        try c.encodeIfPresent(cards, forKey: .cards)
    }
}

/// Valor JSON libre, para el contenido de las tarjetas (los tipos nuevos no tocan el decode).
public enum JSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }
}

/// Tarjeta de una respuesta de Kito: un `tipo` y el resto de campos como `datos`.
public struct KitoCard: Codable, Equatable, Sendable {
    public let tipo: String
    public let datos: [String: JSONValue]

    public init(tipo: String, datos: [String: JSONValue] = [:]) {
        self.tipo = tipo
        self.datos = datos
    }

    private struct Key: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        guard let tipoKey = Key(stringValue: "tipo") else { throw DecodingError.dataCorruptedError(forKey: Key(stringValue: "tipo")!, in: c, debugDescription: "tipo") }
        tipo = try c.decode(String.self, forKey: tipoKey)
        var datos: [String: JSONValue] = [:]
        for key in c.allKeys where key.stringValue != "tipo" {
            if let value = try? c.decode(JSONValue.self, forKey: key) { datos[key.stringValue] = value }
        }
        self.datos = datos
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        for (k, v) in datos { if let key = Key(stringValue: k) { try c.encode(v, forKey: key) } }
        if let key = Key(stringValue: "tipo") { try c.encode(tipo, forKey: key) }
    }
}

/// Lista de tarjetas que descarta los elementos mal formados en vez de fallar.
private struct KitoCardList: Decodable {
    let cards: [KitoCard]

    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        var out: [KitoCard] = []
        while !c.isAtEnd {
            if let card = try? c.decode(KitoCard.self) { out.append(card) } else { _ = try? c.decode(JSONValue.self) }
        }
        cards = out
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

/// Respuesta de `POST asistente`. `tarjetas` ausente o `null` es una lista vacía.
public struct KitoReply: Decodable, Equatable, Sendable {
    public struct Usage: Decodable, Equatable, Sendable {
        public let usados: Int
        public let limite: Int

        public init(usados: Int, limite: Int) {
            self.usados = usados
            self.limite = limite
        }
    }

    public let texto: String
    public let tarjetas: [KitoCard]
    public let uso: Usage?

    private enum CodingKeys: String, CodingKey { case texto, tarjetas, uso }

    public init(texto: String, tarjetas: [KitoCard] = [], uso: Usage? = nil) {
        self.texto = texto
        self.tarjetas = tarjetas
        self.uso = uso
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        texto = try c.decode(String.self, forKey: .texto)
        tarjetas = (try? c.decodeIfPresent(KitoCardList.self, forKey: .tarjetas))?.cards ?? []
        uso = try? c.decodeIfPresent(Usage.self, forKey: .uso)
    }
}

/// Límites que la app conoce del contrato. El tope diario lo decide el servidor (`fn_assistant_daily_limit`).
public enum KitoLimits {
    /// Máximo de mensajes que se envían en cada petición (contrato de la Edge `asistente`).
    public static let maxMessages = 20
    /// Máximo de caracteres por mensaje (contrato de la Edge `asistente`).
    public static let maxChars = 2000
}
