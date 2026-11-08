import Foundation

/// Personas: CRUD. Las compartidas (co-miembros de calendario) llegan con `editable=false` y son
/// solo lectura; PATCH/DELETE no creador → 500 `Not Found` (paridad A7, no es 403).
public struct PersonRepository {
    public let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    /// `GET person` → familia (propios ∪ co-miembros), orden `name` NOCASE,id.
    public func index() async throws -> [PersonEntry] {
        try await client.send(APIRequest(method: .get, path: "person"), as: [PersonEntry].self)
    }

    /// `POST person/create` body `{name,color}` (`#RRGGBB`) → 200 person+`editable:true`.
    public func create(_ request: CreatePersonRequest) async throws -> PersonEntry {
        try await client.send(
            APIRequest(method: .post, path: "person/create", body: try client.encode(request)),
            as: PersonEntry.self
        )
    }

    /// `PATCH person/update` body `{id,name,color}` → person+`editable`.
    public func update(_ request: UpdatePersonRequest) async throws -> PersonEntry {
        try await client.send(
            APIRequest(method: .patch, path: "person/update", body: try client.encode(request)),
            as: PersonEntry.self
        )
    }

    /// `DELETE person/delete` body `{id}` → `{success:true}` (solo creador).
    public func delete(id: Int) async throws {
        _ = try await client.send(
            APIRequest(method: .delete, path: "person/delete", body: try client.encode(DeleteRequest(id: id))),
            as: OkResponse.self
        )
    }
}
