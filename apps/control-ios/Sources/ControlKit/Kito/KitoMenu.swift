import Foundation

/// Resultado local de la tarjeta `menu`. Se guarda como texto en `datos["resultado"]` (el historial conserva
/// todas las claves); ausente es `pendiente` y un valor desconocido, `desconocido`. El `estado` de la propia
/// tarjeta es el del plan (borrador, aceptado…) y no se toca.
public enum KitoMenuResult: String, Equatable, Sendable {
    case pendiente, enviando, aceptado, desactualizado, error, desconocido

    public init(rawValue: String) {
        switch rawValue {
        case "pendiente": self = .pendiente
        case "enviando": self = .enviando
        case "aceptado": self = .aceptado
        case "desactualizado": self = .desactualizado
        case "error": self = .error
        default: self = .desconocido
        }
    }

    /// Texto del resultado en la tarjeta (vacío mientras está pendiente).
    public var label: String {
        switch self {
        case .pendiente: return ""
        case .enviando: return "Aceptando…"
        case .aceptado: return "Menú aceptado"
        case .desactualizado: return "El menú ha cambiado; pídeme que lo vuelva a proponer"
        case .error: return "No se ha podido aceptar. Inténtalo otra vez"
        case .desconocido: return "No sé si se aceptó. Mira la pestaña Menú"
        }
    }

    /// Aún admite el botón «Aceptar».
    public var canAccept: Bool { self == .pendiente || self == .error }
}

/// Casilla (plato) de la tarjeta `menu`.
public struct KitoMenuDish: Equatable, Sendable {
    public let id: Int64?
    /// Día ISO `yyyy-MM-dd`.
    public let dia: String
    public let franja: String
    public let franjaEs: String
    public let titulo: String
    /// `rejected` (a cambiar), `locked` (se queda) o `nil`.
    public let estado: String?
    public let motivo: String?

    public var isRejected: Bool { estado == "rejected" }
}

/// Vista tipada de una tarjeta `menu` que emite Kito. `nil` si la tarjeta es de otro tipo o no trae plan ni
/// revisión legibles (sin ellos no se puede aceptar). Los campos que sobran o faltan no la rompen.
public struct KitoMenu: Equatable, Sendable {
    public static let tipo = "menu"

    public let planId: Int64
    public let revision: Int
    /// Lunes de la semana (`yyyy-MM-dd`).
    public let semana: String
    /// Estado del plan en servidor (`draft`, `accepted`…).
    public let estadoPlan: String
    public let casillas: [KitoMenuDish]
    public let resultado: KitoMenuResult

    public init?(card: KitoCard) {
        guard card.tipo == Self.tipo,
              let planId = Self.int(card.datos["plan_id"]), let revision = Self.int(card.datos["revision"]) else { return nil }
        self.planId = planId
        self.revision = Int(revision)
        semana = Self.string(card.datos["semana"]) ?? ""
        estadoPlan = Self.string(card.datos["estado"]) ?? ""
        if case .array(let items)? = card.datos["casillas"] {
            casillas = items.compactMap { item -> KitoMenuDish? in
                guard case .object(let o) = item, let dia = Self.string(o["dia"]) else { return nil }
                let franja = Self.string(o["franja"]) ?? ""
                return KitoMenuDish(
                    id: Self.int(o["id"]), dia: dia, franja: franja,
                    franjaEs: Self.string(o["franja_es"]) ?? franja,
                    titulo: Self.string(o["titulo"]) ?? "", estado: Self.string(o["estado"]),
                    motivo: Self.string(o["motivo"]))
            }
        } else {
            casillas = []
        }
        if case .string(let s)? = card.datos["resultado"] { resultado = KitoMenuResult(rawValue: s) } else { resultado = .pendiente }
    }

    /// Platos que la persona ha marcado para cambiar.
    public var rejected: [KitoMenuDish] { casillas.filter(\.isRejected) }

    /// Días con platos, en orden, con sus platos (orden de la tarjeta dentro de cada día).
    public var days: [(dia: String, dishes: [KitoMenuDish])] {
        var order: [String] = []
        var map: [String: [KitoMenuDish]] = [:]
        for dish in casillas {
            if map[dish.dia] == nil { order.append(dish.dia) }
            map[dish.dia, default: []].append(dish)
        }
        return order.sorted().map { ($0, map[$0] ?? []) }
    }

    /// La misma tarjeta con otro resultado local.
    public static func card(_ card: KitoCard, resultado: KitoMenuResult) -> KitoCard {
        var datos = card.datos
        datos["resultado"] = .string(resultado.rawValue)
        return KitoCard(tipo: card.tipo, datos: datos)
    }

    private static func int(_ v: JSONValue?) -> Int64? {
        if case .number(let n)? = v, n.isFinite, n == n.rounded(), abs(n) < 9e15 { return Int64(n) }
        return nil
    }

    private static func string(_ v: JSONValue?) -> String? {
        if case .string(let s)? = v, !s.isEmpty { return s }
        return nil
    }
}
