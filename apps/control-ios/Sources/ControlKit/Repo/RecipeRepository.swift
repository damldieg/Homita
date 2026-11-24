import Foundation

/// `/recipe*` y `/food*` (0044, menus-semana). Cuelgan de la raíz, no de `meal/*`: llevan
/// `X-Home-Id` por la regla de `RequestBuilder.sendsHomeHeader`.
public struct RecipeRepository {
    public let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    // MARK: Recetas

    /// `GET recipe?q=&slot=&max_minutes=`
    public func list(query: String? = nil, slot: String? = nil, maxMinutes: Int? = nil) async throws -> [RecipeSummary] {
        var items: [URLQueryItem] = []
        if let query, !query.isEmpty { items.append(URLQueryItem(name: "q", value: query)) }
        if let slot { items.append(URLQueryItem(name: "slot", value: slot)) }
        if let maxMinutes { items.append(URLQueryItem(name: "max_minutes", value: String(maxMinutes))) }
        return try await client.send(APIRequest(method: .get, path: "recipe", query: items), as: [RecipeSummary].self)
    }

    /// `GET recipe/detail?id=`
    public func detail(id: Int64) async throws -> Recipe {
        try await client.send(
            APIRequest(method: .get, path: "recipe/detail", query: [URLQueryItem(name: "id", value: String(id))]),
            as: Recipe.self)
    }

    /// `POST recipe/create` (201).
    public func create(_ input: RecipeInput) async throws -> Recipe {
        try await client.send(
            APIRequest(method: .post, path: "recipe/create", body: try client.encode(input)), as: Recipe.self)
    }

    /// `PATCH recipe/update` body `{id, …}`; los ingredientes reemplazan la lista completa.
    public func update(id: Int64, _ input: RecipeInput) async throws -> Recipe {
        try await client.send(
            APIRequest(method: .patch, path: "recipe/update", body: try client.encode(RecipeUpdateBody(id: id, input: input))),
            as: Recipe.self)
    }

    /// `DELETE recipe/delete?id=`
    public func delete(id: Int64) async throws {
        _ = try await client.send(
            APIRequest(method: .delete, path: "recipe/delete", query: [URLQueryItem(name: "id", value: String(id))]),
            as: OkResponse.self)
    }

    // MARK: Catálogo

    /// `GET food?q=&limit=`: común + del hogar.
    public func searchFood(_ query: String, limit: Int = 20) async throws -> [Food] {
        try await client.send(
            APIRequest(method: .get, path: "food",
                       query: [URLQueryItem(name: "q", value: query), URLQueryItem(name: "limit", value: String(limit))]),
            as: [Food].self)
    }

    /// `POST food/create` (201).
    public func createFood(_ input: FoodInput) async throws -> Food {
        try await client.send(
            APIRequest(method: .post, path: "food/create", body: try client.encode(input)), as: Food.self)
    }

    /// `DELETE food/delete?id=`: solo alimentos propios.
    public func deleteFood(id: Int64) async throws {
        _ = try await client.send(
            APIRequest(method: .delete, path: "food/delete", query: [URLQueryItem(name: "id", value: String(id))]),
            as: OkResponse.self)
    }
}

/// `{id, name, servings, …}`: el id se une al cuerpo de la receta.
struct RecipeUpdateBody: Encodable {
    let id: Int64
    let input: RecipeInput

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: DynamicKey.self)
        try c.encode(id, forKey: DynamicKey("id"))
        try c.encode(input.name, forKey: DynamicKey("name"))
        try c.encode(input.servings, forKey: DynamicKey("servings"))
        try c.encode(input.minutes, forKey: DynamicKey("minutes"))
        try c.encode(input.slots, forKey: DynamicKey("slots"))
        try c.encode(input.steps, forKey: DynamicKey("steps"))
        try c.encode(input.ingredients.map { $0.forRequest() }, forKey: DynamicKey("ingredients"))
    }
}

struct DynamicKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ value: String) { stringValue = value }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}
