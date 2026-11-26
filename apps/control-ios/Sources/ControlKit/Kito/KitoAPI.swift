import Foundation

/// Cliente de la Edge `asistente` (hermana de `api`). Usa el mismo `APIClient` con la base de funciones
/// (`…/functions/v1`), así hereda Bearer, refresco de sesión y `X-Home-Id` (ver `RequestBuilder`).
public final class KitoAPI {
    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    /// Envía el historial reciente y devuelve la respuesta de Kito.
    /// Errores: `APIError.http(429, …)` límite diario; `.http(502, …)` fallo del modelo; `.network` sin red.
    public func ask(history: [KitoMessage], timezone: String) async throws -> KitoReply {
        let body = KitoAPIRequest.make(history: history, timezone: timezone)
        let request = try client.request(method: .post, path: "asistente", body: body)
        return try await client.send(request, as: KitoReply.self)
    }

    /// Confirma una propuesta de Kito: `POST asistente/confirmar` con `{token, timezone}`. No llama al modelo.
    /// Nunca lanza: el resultado, incluidos 403, 409 y fallos de red, se devuelve tipado. No reintenta.
    public func confirm(token: String, timezone: String) async -> KitoConfirmOutcome {
        do {
            let request = try client.request(method: .post, path: "asistente/confirmar", body: KitoConfirmRequest(token: token, timezone: timezone))
            let (status, data) = try await client.sendRaw(request)
            return KitoConfirmOutcome.make(status: status, data: data)
        } catch let error as APIError {
            if case .sessionExpired = error { return .sesionCaducada }
            return .desconocido
        } catch {
            return .desconocido
        }
    }

    /// Base de la Edge `asistente` a partir de la de `api` (`…/functions/v1/api` → `…/functions/v1`).
    public static func functionsBaseURL(fromAPIBaseURL api: URL) -> URL {
        let trimmed = api.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let slash = trimmed.lastIndex(of: "/"), let base = URL(string: String(trimmed[..<slash])) else { return api }
        return base
    }
}
