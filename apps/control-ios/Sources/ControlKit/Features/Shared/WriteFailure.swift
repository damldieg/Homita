import Foundation

/// Fallo de una escritura (crear, editar, borrar, completar) para el toast (E0-05, c): el mensaje
/// y, si el fallo es de red o del servidor, la propia escritura para reintentarla.
public struct WriteFailure: Identifiable {
    public let id = UUID()
    public let message: String
    /// Repite la escritura fallida y devuelve si esta vez fue bien. `nil` = sin «Reintentar».
    public let retry: (() async -> Bool)?

    public init(message: String, retry: (() async -> Bool)? = nil) {
        self.message = message
        self.retry = retry
    }

    /// Fallo a partir del error: mensaje del servidor (`APIError.userMessage`) y «Reintentar» solo
    /// si la causa lo admite (`APIError.isRetryable`: sin conexión o 5xx).
    public init(error: Error, retry: @escaping () async -> Bool) {
        let apiError = error as? APIError
        self.message = apiError?.writeMessage ?? error.localizedDescription
        self.retry = (apiError?.isRetryable ?? false) ? retry : nil
    }
}

/// Store con escrituras: recuerda la última escritura fallida para el toast con «Reintentar».
/// Las lecturas no pasan por aquí: conservan su mensaje de sección (`errorMessage`/estado).
public protocol WriteFailureReporting: AnyObject {
    var writeFailure: WriteFailure? { get set }
}

extension WriteFailureReporting {
    /// Ejecuta la escritura; si falla, guarda el fallo con la misma escritura como reintento.
    /// Devuelve si fue bien. La escritura recibe el store en vez de capturarlo, para que el
    /// reintento guardado en `writeFailure` no retenga el store (sin ciclo de referencias).
    @discardableResult
    func performWrite(_ write: @escaping (Self) async throws -> Void) async -> Bool {
        do {
            try await write(self)
            return true
        } catch {
            writeFailure = WriteFailure(error: error) { [weak self] in
                await self?.performWrite(write) ?? false
            }
            return false
        }
    }

    /// Rechazo de cliente antes de enviar (p. ej. título duplicado): toast sin «Reintentar».
    func rejectWrite(_ message: String) {
        writeFailure = WriteFailure(message: message)
    }
}
