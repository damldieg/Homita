import Foundation

/// Hogares del usuario: listar, crear y fijar el predeterminado. Ninguna de estas tres rutas
/// lleva `X-Home-Id` (la regla vive en `RequestBuilder`).
public struct HomeRepository {
    public let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    /// `GET home` → hogares activos del usuario, ordenados por `home_id`.
    public func list() async throws -> [HomeItem] {
        try await client.send(APIRequest(method: .get, path: "home"), as: [HomeItem].self)
    }

    /// `POST home/create` body `{name}` → 201 `HOME_DETAIL`.
    public func create(name: String) async throws -> HomeDetail {
        try await client.send(
            APIRequest(method: .post, path: "home/create", body: try client.encode(CreateHomeBody(name: name))),
            as: HomeDetail.self
        )
    }

    /// `PATCH home/default` body `{home_id}` → `{default_home_id}`. Sin uso en UI hasta 1.12.
    public func setDefault(homeId: Int) async throws -> DefaultHomeResponse {
        try await client.send(
            APIRequest(method: .patch, path: "home/default", body: try client.encode(SetDefaultHomeBody(homeId: homeId))),
            as: DefaultHomeResponse.self
        )
    }
}
