import Foundation

/// `/shopping*` (0045, menus-compra): la Compra del hogar. Todas llevan `X-Home-Id`.
public struct ShoppingRepository {
    public let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    /// `GET shopping` → `{revision, items}` (sin los artículos ocultos).
    public func list() async throws -> ShoppingList {
        try await client.send(APIRequest(method: .get, path: "shopping"), as: ShoppingList.self)
    }

    /// `GET shopping/preview?plan_id=`: lo que entraría desde el plan (solo lectura).
    public func preview(planId: Int64) async throws -> ShoppingPreview {
        try await client.send(
            APIRequest(method: .get, path: "shopping/preview", query: [URLQueryItem(name: "plan_id", value: String(planId))]),
            as: ShoppingPreview.self)
    }

    /// `POST shopping/sync` → `{added, updated, removed}`.
    public func sync(planId: Int64, clientRequestId: String? = nil) async throws -> ShoppingSyncResult {
        try await client.send(
            APIRequest(method: .post, path: "shopping/sync",
                       body: try client.encode(ShoppingSyncBody(planId: planId, clientRequestId: clientRequestId))),
            as: ShoppingSyncResult.self)
    }

    /// `POST shopping/item/create` (201, también en reintento con el mismo `client_request_id`).
    public func create(label: String?, quantity: Double? = nil, unit: String? = nil, section: String? = nil,
                       foodId: Int64? = nil, clientRequestId: String = UUID().uuidString.lowercased()) async throws -> ShoppingItem {
        let body = ShoppingItemCreateBody(label: label, quantity: quantity, unit: unit, section: section,
                                          foodId: foodId, clientRequestId: clientRequestId)
        return try await client.send(
            APIRequest(method: .post, path: "shopping/item/create", body: try client.encode(body)), as: ShoppingItem.self)
    }

    /// `PATCH shopping/item/check`: `pending` desmarca, `checked` marca, `skipped` es «ya lo tengo».
    public func setState(id: Int64, state: String) async throws -> ShoppingItem {
        try await client.send(
            APIRequest(method: .patch, path: "shopping/item/check", body: try client.encode(ShoppingItemCheckBody(id: id, state: state))),
            as: ShoppingItem.self)
    }

    /// `PATCH shopping/item/update`: la cantidad editada deja de sincronizarse con el menú.
    public func updateQuantity(id: Int64, quantity: Double, unit: String? = nil) async throws -> ShoppingItem {
        try await client.send(
            APIRequest(method: .patch, path: "shopping/item/update",
                       body: try client.encode(ShoppingItemQtyBody(id: id, quantity: quantity, unit: unit))),
            as: ShoppingItem.self)
    }

    /// `DELETE shopping/item/delete?id=`: manual se borra; de origen menú queda oculto.
    public func delete(id: Int64) async throws {
        _ = try await client.send(
            APIRequest(method: .delete, path: "shopping/item/delete", query: [URLQueryItem(name: "id", value: String(id))]),
            as: ShoppingDeleteResult.self)
    }

    /// `DELETE shopping/checked` → `{cleared}`.
    @discardableResult
    public func clearChecked() async throws -> Int {
        try await client.send(APIRequest(method: .delete, path: "shopping/checked"), as: ShoppingClearResult.self).cleared
    }
}

struct ShoppingDeleteResult: Decodable { let id: Int64?; let deleted: Bool? }
