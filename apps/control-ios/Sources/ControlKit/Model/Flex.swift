import Foundation

/// Bool flexible del contrato PHP: los flags SQLite (`widget`/`dashboard`) llegan como 0/1 y otros
/// campos (`active`, `editable`, `allow_registration`) como bool JSON. Acepta `true/false`, `0/1`,
/// `"0"/"1"`, `"true"/"false"`; cualquier otro valor es error de decodificación.
public struct FlexBool: Codable, Equatable, Sendable {
    public let value: Bool

    public init(_ value: Bool) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let bool = try? container.decode(Bool.self) {
            value = bool
            return
        }
        if let int = try? container.decode(Int.self) {
            switch int {
            case 0: value = false
            case 1: value = true
            default:
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "FlexBool no acepta \(int)")
            }
            return
        }
        if let string = try? container.decode(String.self) {
            switch string {
            case "0", "false": value = false
            case "1", "true": value = true
            default:
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "FlexBool no acepta \"\(string)\"")
            }
            return
        }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "FlexBool espera bool, 0/1 o \"0\"/\"1\"")
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

/// Entero flexible del contrato: acepta JSON int o string de dígitos (`getInputInt` de PHP).
public struct FlexInt: Codable, Equatable, Sendable {
    public let value: Int

    public init(_ value: Int) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let int = try? container.decode(Int.self) {
            value = int
            return
        }
        if let string = try? container.decode(String.self), string.allSatisfy({ $0.isASCII && $0.isNumber }), let int = Int(string) {
            value = int
            return
        }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "FlexInt espera int o string numérico")
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}
