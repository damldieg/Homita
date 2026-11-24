import Foundation

/// Estados de un artículo de la Compra (0045): pendiente, comprado o «ya lo tengo».
public enum ShoppingState {
    public static let pending = "pending"
    public static let checked = "checked"
    /// «Ya lo tengo»: no hay que comprarlo, pero la sincronización no lo vuelve a crear.
    public static let skipped = "skipped"
}

/// Origen de un artículo: a mano o calculado desde el menú aceptado.
public enum ShoppingOrigin {
    public static let manual = "manual"
    public static let menu = "menu"
}

/// Plato que aporta a un artículo de origen menú («para qué plato es»).
public struct ShoppingSource: Codable, Equatable, Sendable {
    public var planItemId: Int64?
    public var recipeId: Int64?
    public var name: String?
    public var qty: Double?
    public var unit: String?

    public init(planItemId: Int64? = nil, recipeId: Int64? = nil, name: String? = nil, qty: Double? = nil, unit: String? = nil) {
        self.planItemId = planItemId
        self.recipeId = recipeId
        self.name = name
        self.qty = qty
        self.unit = unit
    }

    enum CodingKeys: String, CodingKey {
        case planItemId = "plan_item_id", recipeId = "recipe_id", name, qty, unit
    }
}

/// Artículo de la Compra del hogar. Los ids son bigint (`Int64`); `checkedBy` es el id del usuario.
public struct ShoppingItem: Codable, Equatable, Sendable, Identifiable {
    public var id: Int64
    public var label: String
    public var foodId: Int64?
    public var quantity: Double?
    public var unit: String
    public var section: String
    public var origin: String
    public var planId: Int64?
    public var sources: [ShoppingSource]
    public var qtyOverridden: Bool
    public var state: String
    public var checkedAt: String?
    public var checkedBy: Int64?
    public var createdAt: String?
    public var updatedAt: String?

    public init(id: Int64, label: String, foodId: Int64? = nil, quantity: Double? = nil, unit: String = "ud",
                section: String = "otros", origin: String = ShoppingOrigin.manual, planId: Int64? = nil,
                sources: [ShoppingSource] = [], qtyOverridden: Bool = false, state: String = ShoppingState.pending,
                checkedAt: String? = nil, checkedBy: Int64? = nil, createdAt: String? = nil, updatedAt: String? = nil) {
        self.id = id
        self.label = label
        self.foodId = foodId
        self.quantity = quantity
        self.unit = unit
        self.section = section
        self.origin = origin
        self.planId = planId
        self.sources = sources
        self.qtyOverridden = qtyOverridden
        self.state = state
        self.checkedAt = checkedAt
        self.checkedBy = checkedBy
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, label, foodId = "food_id", quantity, unit, section, origin, planId = "plan_id", sources
        case qtyOverridden = "qty_overridden", state, checkedAt = "checked_at", checkedBy = "checked_by"
        case createdAt = "created_at", updatedAt = "updated_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int64.self, forKey: .id)
        label = try c.decode(String.self, forKey: .label)
        foodId = try c.decodeIfPresent(Int64.self, forKey: .foodId)
        quantity = try c.decodeIfPresent(Double.self, forKey: .quantity)
        unit = try c.decodeIfPresent(String.self, forKey: .unit) ?? "ud"
        section = try c.decodeIfPresent(String.self, forKey: .section) ?? "otros"
        origin = try c.decodeIfPresent(String.self, forKey: .origin) ?? ShoppingOrigin.manual
        planId = try c.decodeIfPresent(Int64.self, forKey: .planId)
        sources = try c.decodeIfPresent([ShoppingSource].self, forKey: .sources) ?? []
        qtyOverridden = try c.decodeIfPresent(Bool.self, forKey: .qtyOverridden) ?? false
        state = try c.decodeIfPresent(String.self, forKey: .state) ?? ShoppingState.pending
        checkedAt = try c.decodeIfPresent(String.self, forKey: .checkedAt)
        checkedBy = try c.decodeIfPresent(Int64.self, forKey: .checkedBy)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt)
    }

    public var isPending: Bool { state == ShoppingState.pending }
    public var isChecked: Bool { state == ShoppingState.checked }
    public var isSkipped: Bool { state == ShoppingState.skipped }

    /// «2 kg», «250 g», «3 ud» o vacío sin cantidad.
    public var quantityText: String {
        ShoppingFormat.quantity(quantity, unit: unit)
    }
}

/// Respuesta de `GET shopping`: artículos visibles (sin los ocultos) y la revisión de la sincronización.
public struct ShoppingList: Codable, Equatable, Sendable {
    public var revision: Int
    public var items: [ShoppingItem]

    public init(revision: Int, items: [ShoppingItem]) {
        self.revision = revision
        self.items = items
    }
}

/// Resultado de una sincronización con el menú: `{added, updated, removed}`.
public struct ShoppingSyncResult: Codable, Equatable, Sendable {
    public var added: Int
    public var updated: Int
    public var removed: Int

    public init(added: Int, updated: Int, removed: Int) {
        self.added = added
        self.updated = updated
        self.removed = removed
    }

    public var isEmpty: Bool { added == 0 && updated == 0 && removed == 0 }

    /// «+2 −1» (solo las partes distintas de cero; «~3» = cantidades cambiadas).
    public var summary: String {
        var parts: [String] = []
        if added > 0 { parts.append("+\(added)") }
        if removed > 0 { parts.append("−\(removed)") }
        if updated > 0 { parts.append("~\(updated)") }
        return parts.joined(separator: " ")
    }
}

/// Línea de `GET shopping/preview`: lo que entraría en la Compra desde un plan.
public struct ShoppingPreviewItem: Decodable, Equatable, Sendable {
    public var aggKey: String
    public var label: String
    public var foodId: Int64?
    public var quantity: Double?
    public var unit: String
    public var section: String
    public var sources: [ShoppingSource]

    enum CodingKeys: String, CodingKey {
        case aggKey = "agg_key", label, foodId = "food_id", quantity, unit, section, sources
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        aggKey = try c.decode(String.self, forKey: .aggKey)
        label = try c.decode(String.self, forKey: .label)
        foodId = try c.decodeIfPresent(Int64.self, forKey: .foodId)
        quantity = try c.decodeIfPresent(Double.self, forKey: .quantity)
        unit = try c.decodeIfPresent(String.self, forKey: .unit) ?? "ud"
        section = try c.decodeIfPresent(String.self, forKey: .section) ?? "otros"
        sources = try c.decodeIfPresent([ShoppingSource].self, forKey: .sources) ?? []
    }

    public var quantityText: String { ShoppingFormat.quantity(quantity, unit: unit) }
}

public struct ShoppingPreview: Decodable, Equatable, Sendable {
    public var planId: Int64
    public var items: [ShoppingPreviewItem]

    public init(planId: Int64, items: [ShoppingPreviewItem]) {
        self.planId = planId
        self.items = items
    }

    enum CodingKeys: String, CodingKey {
        case planId = "plan_id", items
    }
}

/// Cuerpos de las escrituras de la Compra.
public struct ShoppingItemCreateBody: Encodable, Equatable, Sendable {
    public var label: String?
    public var quantity: Double?
    public var unit: String?
    public var section: String?
    public var foodId: Int64?
    public var clientRequestId: String

    enum CodingKeys: String, CodingKey {
        case label, quantity, unit, section, foodId = "food_id", clientRequestId = "client_request_id"
    }
}

struct ShoppingItemCheckBody: Encodable { let id: Int64; let state: String }
struct ShoppingItemQtyBody: Encodable { let id: Int64; let quantity: Double; let unit: String? }
struct ShoppingSyncBody: Encodable {
    let planId: Int64
    let clientRequestId: String?
    enum CodingKeys: String, CodingKey { case planId = "plan_id", clientRequestId = "client_request_id" }
}
public struct ShoppingClearResult: Decodable, Equatable, Sendable { public var cleared: Int }

/// Textos de cantidad y de sección de la Compra.
public enum ShoppingFormat {
    public static func quantity(_ value: Double?, unit: String) -> String {
        guard let value else { return "" }
        let number = value == value.rounded() ? String(Int(value)) : String(format: "%g", (value * 100).rounded() / 100)
        return "\(number) \(unit)"
    }

    /// Orden de pasillo y título de cada sección del catálogo.
    public static let sectionOrder = ["verdura", "fruta", "carne", "embutido", "pescado", "marisco", "lacteos", "huevos",
                                      "legumbres", "cereales", "panaderia", "despensa", "aceites", "especias", "bebidas",
                                      "congelados", "otros"]

    public static func sectionTitle(_ section: String) -> String {
        switch section {
        case "lacteos": return "Lácteos"
        case "panaderia": return "Panadería"
        default: return section.prefix(1).uppercased() + section.dropFirst()
        }
    }
}
