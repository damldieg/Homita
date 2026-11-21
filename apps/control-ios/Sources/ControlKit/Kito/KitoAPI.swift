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

    /// Base de la Edge `asistente` a partir de la de `api` (`…/functions/v1/api` → `…/functions/v1`).
    public static func functionsBaseURL(fromAPIBaseURL api: URL) -> URL {
        let trimmed = api.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let slash = trimmed.lastIndex(of: "/"), let base = URL(string: String(trimmed[..<slash])) else { return api }
        return base
    }
}
