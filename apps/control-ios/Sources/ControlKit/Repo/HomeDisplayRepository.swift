import Foundation

/// Pantallas del hogar (dashboard-pantalla-hogar, 0049): listar, vincular con el código de la pantalla, editar y
/// revocar. Todas llevan `X-Home-Id` (regla de `RequestBuilder`: `home/*`). Solo gestionan quien tiene
/// `display.manage` o `calendar.manage` (lo decide el servidor).
extension HomeRepository {
    /// `GET home/display` → pantallas activas del hogar.
    public func displays(homeId: Int) async throws -> [HomeDisplay] {
        try await client.send(
            APIRequest(method: .get, path: "home/display", query: [URLQueryItem(name: "home_id", value: String(homeId))]),
            as: [HomeDisplay].self
        )
    }

    /// `POST home/display/link-confirm` `{code,name}` → 201 con la pantalla vinculada.
    public func confirmDisplayLink(code: String, name: String) async throws -> DisplayLinked {
        try await client.send(
            APIRequest(method: .post, path: "home/display/link-confirm",
                       body: try client.encode(LinkDisplayBody(code: code, name: name))),
            as: DisplayLinked.self
        )
    }

    /// `PATCH home/display/update` → `{id}` (R1-02: el servidor no devuelve la pantalla completa; la lista se relee).
    public func updateDisplay(_ body: UpdateDisplayBody) async throws -> DisplayUpdated {
        try await client.send(
            APIRequest(method: .patch, path: "home/display/update", body: try client.encode(body)),
            as: DisplayUpdated.self
        )
    }

    /// `POST home/display/revoke` `{id}` → `{id, revoked}`. La pantalla deja de leer el hogar al momento.
    public func revokeDisplay(id: Int) async throws -> RevokedDisplay {
        try await client.send(
            APIRequest(method: .post, path: "home/display/revoke", body: try client.encode(RevokeDisplayBody(id: id))),
            as: RevokedDisplay.self
        )
    }
}

/// Respuesta de `POST home/display/revoke`.
public struct RevokedDisplay: Codable, Equatable, Sendable {
    public let id: Int
    public let revoked: Bool
}
