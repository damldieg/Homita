import Foundation

/// Errores de red/contrato. El backend responde `{"error":"<msg>"}` con mensajes literales del
/// contrato (inventario del change control-api, local, no versionado; ver
/// `supabase/functions/api/usecases/`); las desviaciones de la Edge
/// frente a PHP quedan reflejadas aquí (401 en vez de 500 `Not Found`, 403 `Not Allowed`, …).
public enum APIError: Error, Equatable {
    case http(status: Int, message: String)
    case network(String)
    case decoding(String)
    case sessionExpired

    /// 500 `Not Found` = no miembro / no existe (no es fallo de sesión: mostrar "No encontrado").
    public var isNotFound: Bool {
        if case .http(let status, let message) = self {
            return (status == 500 || status == 404) && message == "Not Found"
        }
        return false
    }

    /// 403 `Not Allowed` = solo propietario (owner-only): mostrar aviso, no reintentar.
    public var isOwnerOnly: Bool {
        if case .http(let status, let message) = self {
            return status == 403 && message == "Not Allowed"
        }
        return false
    }

    /// Mensaje en español para la UI.
    public var userMessage: String {
        switch self {
        case .http(_, let message):
            if isNotFound { return "No encontrado" }
            if isOwnerOnly { return "Solo el propietario puede realizar esta acción" }
            switch message {
            case "Unauthorized": return "No autorizado"
            case "Invalid credentials": return "Email o contraseña incorrectos"
            case "User cannot remove themselves": return "No puedes quitarte a ti mismo"
            case "Email already exists": return "Ese email ya está registrado"
            default: return message
            }
        case .network:
            return "Error de conexión. Comprueba la red."
        case .decoding:
            return "Error al leer la respuesta del servidor"
        case .sessionExpired:
            return "Tu sesión ha caducado. Inicia sesión de nuevo."
        }
    }
}

/// Parsea el cuerpo de error `{"error":"<msg>"}` del contrato.
struct ErrorEnvelope: Decodable {
    let error: String?
}
