import Foundation

/// Causa de un fallo de red o de contrato, para elegir el mensaje y la acción (E0-05, d).
public enum APIFailureCause: Equatable, Sendable {
    /// Sin red o sin respuesta del servidor.
    case offline
    /// Error 5xx del servidor.
    case server
    /// 401 o sesión caducada: la app cierra sesión.
    case unauthorized
    /// 403: el servidor dice por qué (mensaje del servidor).
    case forbidden
    /// Resto (4xx de validación, respuesta ilegible).
    case other
}

extension APIError {
    /// Causa del fallo, sin mirar el texto del servidor.
    public var cause: APIFailureCause {
        switch self {
        case .network:
            return .offline
        case .sessionExpired:
            return .unauthorized
        case .decoding:
            return .other
        case .http(let status, _):
            switch status {
            case 401: return .unauthorized
            case 403: return .forbidden
            case 500...599: return .server
            default: return .other
            }
        }
    }

    /// Si tiene sentido ofrecer «Reintentar»: fallos de red y del servidor, no de validación.
    public var isRetryable: Bool {
        switch cause {
        case .offline, .server: return true
        case .unauthorized, .forbidden, .other: return false
        }
    }
}
