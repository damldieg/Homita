import Foundation

/// Textos de error de Kito con su voz (cercano y sobrio). Un solo sitio para todos.
public enum KitoErrorCopy {
    public static let dailyLimit = "Por hoy ya hemos hablado mucho. Mañana sigo aquí."
    public static let modelFailure = "Me he despistado un momento. ¿Lo intentamos otra vez?"
    public static let offline = "Ahora mismo no tengo conexión."
    public static let homeNotFound = "No encuentro tu hogar activo. Vuelve a elegirlo y lo intentamos."
    public static let sessionExpired = "Tu sesión ha caducado. Entra de nuevo y seguimos."
    public static let decoding = "No he entendido bien mi propia respuesta. ¿Lo intentamos otra vez?"
    public static let generic = "Algo ha fallado. ¿Lo intentamos otra vez?"

    public static func tooLong(max: Int = KitoLimits.maxChars) -> String {
        "Eso es muy largo para mí. ¿Lo dejas en menos de \(max) caracteres?"
    }

    /// Texto para un error de la Edge o de la red.
    public static func text(for error: Error) -> String {
        guard let apiError = error as? APIError else { return generic }
        switch apiError {
        case .http(let status, _):
            switch status {
            case 429: return dailyLimit
            case 404: return homeNotFound
            case 500...599: return modelFailure
            default: return generic
            }
        case .network: return offline
        case .sessionExpired: return sessionExpired
        case .decoding: return decoding
        }
    }

    /// Si volver a intentarlo tiene sentido (el límite diario y la sesión caducada no se arreglan reenviando).
    public static func isRetryable(_ error: Error) -> Bool {
        guard let apiError = error as? APIError else { return true }
        switch apiError {
        case .http(let status, _): return status != 429 && status != 404
        case .sessionExpired: return false
        case .network, .decoding: return true
        }
    }
}

/// Fallo del último envío: el texto de Kito y si se puede reintentar.
public struct KitoFailure: Equatable, Sendable {
    public let text: String
    public let retryable: Bool

    public init(text: String, retryable: Bool) {
        self.text = text
        self.retryable = retryable
    }
}
