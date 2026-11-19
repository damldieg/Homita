import Foundation

/// Feedback de la app. `POST feedback` no lleva `X-Home-Id` (no es una ruta `home/*`).
public struct FeedbackRepository {
    public let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    /// `POST feedback` body `{seccion,subseccion,tipo,texto}` → 201 `{ok:true}` (el cuerpo no se usa).
    public func send(_ body: FeedbackRequest) async throws {
        _ = try await client.send(APIRequest(method: .post, path: "feedback", body: try client.encode(body)))
    }
}
