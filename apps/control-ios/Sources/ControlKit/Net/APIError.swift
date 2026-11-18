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

    /// Mensaje para las pantallas de administración del hogar (`home/*`): el permiso exigido es
    /// admin, no propietario. El resto delega en `userMessage`.
    public var homeAdminMessage: String {
        if isOwnerOnly { return "Solo un administrador puede realizar esta acción" }
        return userMessage
    }

    /// Mensaje para degradar/quitar/salir: un 403 `Not Allowed` puede ser falta de permiso o último
    /// admin y el servidor no lo distingue, así que el texto es neutro.
    public var membershipActionMessage: String {
        if isOwnerOnly { return "No se puede completar la acción: el hogar debe conservar al menos un administrador" }
        return userMessage
    }

    /// Mensaje para crear, listar y revocar invitaciones (1.15b).
    public var invitationAdminMessage: String {
        if case .http(let status, let message) = self {
            switch (status, message) {
            case (403, "Not Allowed"): return "No tienes permiso para crear esta invitación"
            case (400, "Invalid member"): return "Ese miembro ya no se puede invitar; la lista se ha actualizado"
            case (404, "Not Found"): return "La invitación ya no existe: se usó, se revocó o caducó"
            case (400, "Already member"): return "Esa persona ya es miembro del hogar"
            case (400, "Invalid email"): return "Revisa el email de la invitación"
            default: break
            }
        }
        return userMessage
    }

    /// Mensaje para aceptar una invitación (1.15). El servidor responde el mismo 404 para un código
    /// inexistente, usado, revocado o caducado (sin oráculo), así que el texto los agrupa.
    public var invitationMessage: String {
        if case .http(let status, let message) = self {
            switch (status, message) {
            case (404, "Not Found"): return "El código no es válido, ya se usó o ha caducado"
            case (403, "Not Allowed"): return "Esta invitación es para otro email"
            case (400, "Already member"): return "Ya eres miembro de ese hogar"
            case (400, "Invitation code is required"): return "Introduce el código de invitación"
            case (400, "Invalid member"): return "La invitación ya no es válida para ese miembro"
            default: break
            }
        }
        return userMessage
    }

    /// Mensaje del toast de una escritura (crear, editar, borrar, compartir): un 403 `Not Allowed`
    /// es falta de permiso de edición (0029) o acción solo del propietario; el servidor no lo
    /// distingue, así que el texto cubre ambos. El resto delega en `userMessage`.
    public var writeMessage: String {
        if isOwnerOnly {
            return "No tienes permiso para hacer este cambio. Pide al propietario que te dé permiso de edición."
        }
        return userMessage
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
            case "Invalid member": return "Tipo de miembro no válido"
            case "Name is required (max 50 characters)": return "El nombre es obligatorio (máx. 50 caracteres)"
            case "Color must be #RRGGBB": return "El color debe ser #RRGGBB"
            case "Member ID is required": return "Falta el identificador del miembro"
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
