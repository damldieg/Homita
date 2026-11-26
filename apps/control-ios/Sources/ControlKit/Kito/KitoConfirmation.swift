import Foundation

/// Estado de una tarjeta de confirmación. Se guarda como texto en `datos["estado"]` de la tarjeta (el
/// historial ya conserva todas las claves); un valor ausente es `pendiente` y uno desconocido, `desconocido`.
public enum KitoConfirmationState: String, Equatable, Sendable {
    case pendiente, enviando, hecho, cancelado, caducado, parcial, error, desconocido

    public init(rawValue: String) {
        self = Self.allCases.first { $0.rawValue == rawValue } ?? .desconocido
    }

    private static let allCases: [KitoConfirmationState] = [
        .pendiente, .enviando, .hecho, .cancelado, .caducado, .parcial, .error, .desconocido
    ]

    /// Ya no admite acciones del usuario (todo salvo `pendiente`; `enviando` tampoco admite botones).
    public var isResolved: Bool { self != .pendiente && self != .enviando }
}

extension KitoConfirmationState {
    /// Etiqueta corta del estado en la tarjeta. `pendiente` no tiene (se muestran los botones).
    public var label: String {
        switch self {
        case .pendiente: return ""
        case .enviando: return "Enviando…"
        case .hecho: return "Hecho"
        case .cancelado: return "Cancelado"
        case .caducado: return "Ha caducado, pídemelo otra vez"
        case .parcial: return "Se ha hecho solo una parte"
        case .error: return "No se ha podido hacer"
        case .desconocido: return "No sé si se llegó a hacer. Comprueba la app y, si falta, pídemelo otra vez"
        }
    }

    /// Texto del mensaje de Kito que se añade al historial al resolver una confirmación, para que Kito
    /// sepa cómo acabó. `detalle` es el texto del servidor o el motivo.
    func historyText(detalle: String?) -> String {
        let extra = (detalle?.isEmpty == false) ? ": \(detalle!)" : "."
        switch self {
        case .hecho: return "Hecho\(extra)"
        case .cancelado: return "Cancelado. No he hecho ningún cambio."
        case .parcial: return "Solo se ha hecho una parte\(extra)"
        case .caducado: return "La confirmación ha caducado y no se ha hecho nada."
        case .error: return "No se ha podido hacer\(extra)"
        case .desconocido: return "No sé si se llegó a hacer. Hay que comprobarlo."
        case .pendiente, .enviando: return ""
        }
    }
}

/// Resultado tipado de `POST asistente/confirmar`.
public enum KitoConfirmOutcome: Equatable, Sendable {
    /// 200: todo hecho.
    case hecho(texto: String, cambios: [KitoChange])
    /// 403: firma no válida o caducada; no se ejecutó nada.
    case rechazado
    /// 409: una acción falló; `texto` y `cambios` dicen lo que sí se hizo.
    case parcial(texto: String?, cambios: [KitoChange])
    /// 503: falta el secreto en el servidor; no se ejecutó nada.
    case sinSecreto
    /// 401 sin sesión válida.
    case sesionCaducada
    /// Otro código HTTP (400, 404, 405, 5xx…).
    case otro(status: Int)
    /// Red caída, tiempo agotado o respuesta ilegible: no se sabe si se ejecutó.
    case desconocido

    static func make(status: Int, data: Data) -> KitoConfirmOutcome {
        let decoder = JSONCoding.decoder()
        switch status {
        case 200...299:
            guard let body = try? decoder.decode(KitoConfirmBody.self, from: data) else { return .desconocido }
            return .hecho(texto: body.texto ?? "", cambios: body.cambios)
        case 403:
            return .rechazado
        case 409:
            let body = try? decoder.decode(KitoConfirmBody.self, from: data)
            return .parcial(texto: body?.texto, cambios: body?.cambios ?? [])
        case 503:
            return .sinSecreto
        default:
            return .otro(status: status)
        }
    }
}

struct KitoConfirmRequest: Encodable, Equatable {
    let token: String
    let timezone: String
}

/// Cuerpo de 200 y 409 de `asistente/confirmar`; todo tolerante.
struct KitoConfirmBody: Decodable {
    let texto: String?
    let cambios: [KitoChange]

    private enum CodingKeys: String, CodingKey { case texto, cambios }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        texto = try? c.decodeIfPresent(String.self, forKey: .texto)
        cambios = (try? c.decodeIfPresent(KitoChangeList.self, forKey: .cambios))?.changes ?? []
    }
}

/// Vista tipada de una tarjeta `confirmacion`. `nil` si la tarjeta es de otro tipo.
public struct KitoConfirmation: Equatable, Sendable {
    public static let tipo = "confirmacion"
    /// Margen frente a latencia y desfase del reloj del móvil: se da por caducada 5 s antes.
    public static let expiryMargin: TimeInterval = 5

    public let token: String?
    public let texto: String
    /// `nil` si falta o no se puede leer: se trata como caducada (falla cerrada).
    public let caduca: Date?
    public let acciones: [JSONValue]
    public let estado: KitoConfirmationState
    /// Texto que devuelve el servidor tras confirmar (qué se hizo), si lo hay.
    public let detalle: String?

    public init?(card: KitoCard) {
        guard card.tipo == Self.tipo else { return nil }
        if case .string(let t)? = card.datos["token"] { token = t } else { token = nil }
        if case .string(let t)? = card.datos["texto"] { texto = t } else { texto = "" }
        if case .string(let s)? = card.datos["caduca"] { caduca = Self.parseExpiry(s) } else { caduca = nil }
        if case .array(let a)? = card.datos["acciones"] { acciones = a } else { acciones = [] }
        if case .string(let s)? = card.datos["estado"] { estado = KitoConfirmationState(rawValue: s) } else { estado = .pendiente }
        if case .string(let t)? = card.datos["detalle"], !t.isEmpty { detalle = t } else { detalle = nil }
    }

    /// ¿Caducada a `now`? Sin fecha válida, sí.
    public func isExpired(at now: Date) -> Bool {
        guard let caduca else { return true }
        return caduca.addingTimeInterval(-Self.expiryMargin) <= now
    }

    /// La misma tarjeta con otro estado (y detalle opcional). El resto de claves no cambian.
    public static func card(_ card: KitoCard, estado: KitoConfirmationState, detalle: String? = nil) -> KitoCard {
        var datos = card.datos
        datos["estado"] = .string(estado.rawValue)
        if let detalle, !detalle.isEmpty { datos["detalle"] = .string(detalle) } else { datos["detalle"] = nil }
        return KitoCard(tipo: card.tipo, datos: datos)
    }

    /// ISO 8601 con o sin fracciones de segundo; cualquier otra cosa es `nil`.
    public static func parseExpiry(_ raw: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFraction.date(from: raw) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw)
    }
}
