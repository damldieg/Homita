import Foundation

/// Menú semanal, recetas y catálogo (0044, menus-semana). Los ids son `bigint` en el servidor
/// (`Int64`); las fechas llegan como `YYYY-MM-DD` y las marcas de tiempo sin zona, así que se
/// guardan como texto.

/// Franjas del planificador en orden de día.
public enum MealSlotKind {
    public static let order = ["breakfast", "midmorning", "lunch", "snack", "dinner"]

    public static func title(_ slot: String) -> String {
        switch slot {
        case "breakfast": return "Desayuno"
        case "midmorning": return "Media mañana"
        case "lunch": return "Comida"
        case "snack": return "Merienda"
        case "dinner": return "Cena"
        default: return slot
        }
    }
}

/// Unidades de ingrediente admitidas por el servidor.
public enum RecipeUnit {
    public static let all = ["g", "kg", "ml", "l", "ud", "cda", "cdta", "pizca", "al gusto"]
}

/// Alimento del catálogo: común (`homeId == nil`) o del hogar.
public struct Food: Codable, Equatable, Sendable, Identifiable {
    public var id: Int64
    public var homeId: Int64?
    public var name: String
    public var section: String
    public var allergens: [String]
    public var defaultUnit: String
    public var gramsPerUnit: Double?

    public init(id: Int64, homeId: Int64? = nil, name: String, section: String = "otros", allergens: [String] = [],
                defaultUnit: String = "g", gramsPerUnit: Double? = nil) {
        self.id = id
        self.homeId = homeId
        self.name = name
        self.section = section
        self.allergens = allergens
        self.defaultUnit = defaultUnit
        self.gramsPerUnit = gramsPerUnit
    }

    enum CodingKeys: String, CodingKey {
        case id, homeId = "home_id", name, section, allergens, defaultUnit = "default_unit", gramsPerUnit = "grams_per_unit"
    }
}

/// Alta de un alimento propio.
public struct FoodInput: Encodable, Equatable, Sendable {
    public var name: String
    public var section: String?
    public var allergens: [String]?
    public var defaultUnit: String?
    public var gramsPerUnit: Double?

    public init(name: String, section: String? = nil, allergens: [String]? = nil, defaultUnit: String? = nil,
                gramsPerUnit: Double? = nil) {
        self.name = name
        self.section = section
        self.allergens = allergens
        self.defaultUnit = defaultUnit
        self.gramsPerUnit = gramsPerUnit
    }

    enum CodingKeys: String, CodingKey {
        case name, section, allergens, defaultUnit = "default_unit", gramsPerUnit = "grams_per_unit"
    }
}

/// Ingrediente: `foodId` (catálogo) o `label` (texto libre). Al enviar, los nil no se mandan.
public struct RecipeIngredient: Codable, Equatable, Sendable, Identifiable {
    public var id: Int64?
    public var position: Int?
    public var foodId: Int64?
    public var label: String?
    public var quantity: Double?
    public var unit: String?

    public init(foodId: Int64? = nil, label: String? = nil, quantity: Double? = nil, unit: String? = nil,
                id: Int64? = nil, position: Int? = nil) {
        self.id = id
        self.position = position
        self.foodId = foodId
        self.label = label
        self.quantity = quantity
        self.unit = unit
    }

    enum CodingKeys: String, CodingKey {
        case id, position, foodId = "food_id", label, quantity, unit
    }

    /// Ingrediente válido: algo del catálogo o texto, y una unidad conocida si hay.
    public var isValid: Bool {
        let hasLabel = !(label?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        guard foodId != nil || hasLabel else { return false }
        if let unit, !RecipeUnit.all.contains(unit) { return false }
        if let quantity, quantity < 0 { return false }
        return true
    }

    /// Solo lo que el servidor lee (sin `id` ni `position`: el orden es el de la lista).
    func forRequest() -> RecipeIngredient {
        RecipeIngredient(foodId: foodId, label: label, quantity: quantity, unit: unit)
    }
}

/// Fila de `GET recipe`.
public struct RecipeSummary: Codable, Equatable, Sendable, Identifiable {
    public var id: Int64
    public var name: String
    public var servings: Int
    public var minutes: Int?
    public var slots: [String]
}

/// Ficha de `GET recipe/detail` (y respuesta de create/update).
public struct Recipe: Codable, Equatable, Sendable, Identifiable {
    public var id: Int64
    public var name: String
    public var servings: Int
    public var minutes: Int?
    public var slots: [String]
    public var steps: [String]?
    public var ingredients: [RecipeIngredient]
    /// Derivados de los ingredientes con `food_id`.
    public var allergens: [String]
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name, servings, minutes, slots, steps, ingredients, allergens, updatedAt = "updated_at"
    }
}

/// Alta o edición de receta. `minutes` y `steps` se envían siempre (null los borra); en edición
/// la lista de ingredientes reemplaza la completa.
public struct RecipeInput: Encodable, Equatable, Sendable {
    public var name: String
    public var servings: Int
    public var minutes: Int?
    public var slots: [String]
    public var steps: [String]?
    public var ingredients: [RecipeIngredient]

    public init(name: String, servings: Int = 2, minutes: Int? = nil, slots: [String] = [], steps: [String]? = nil,
                ingredients: [RecipeIngredient] = []) {
        self.name = name
        self.servings = servings
        self.minutes = minutes
        self.slots = slots
        self.steps = steps
        self.ingredients = ingredients
    }

    enum CodingKeys: String, CodingKey { case name, servings, minutes, slots, steps, ingredients }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(servings, forKey: .servings)
        try c.encode(minutes, forKey: .minutes)
        try c.encode(slots, forKey: .slots)
        try c.encode(steps, forKey: .steps)
        try c.encode(ingredients.map { $0.forRequest() }, forKey: .ingredients)
    }
}

/// Casilla del menú. Sin `id` es nueva; `members == nil` deja los comensales por defecto del
/// servidor y `[]` significa nadie.
public struct MealPlanItem: Codable, Equatable, Sendable, Identifiable {
    public var id: Int64?
    public var day: String
    public var slot: String
    public var position: Int
    public var kind: String
    public var recipeId: Int64?
    public var title: String
    public var servings: Int?
    public var cookMemberId: Int64?
    public var members: [Int64]?

    public init(id: Int64? = nil, day: String, slot: String, position: Int = 0, kind: String, recipeId: Int64? = nil,
                title: String = "", servings: Int? = nil, cookMemberId: Int64? = nil, members: [Int64]? = nil) {
        self.id = id
        self.day = day
        self.slot = slot
        self.position = position
        self.kind = kind
        self.recipeId = recipeId
        self.title = title
        self.servings = servings
        self.cookMemberId = cookMemberId
        self.members = members
    }

    enum CodingKeys: String, CodingKey {
        case id, day, slot, position, kind, recipeId = "recipe_id", title, servings
        case cookMemberId = "cook_member_id", members
    }

    /// Identidad estable para listas: el id del servidor o una clave de casilla nueva.
    public var key: String { id.map { "i\($0)" } ?? "n-\(day)-\(slot)-\(position)" }
}

public enum MealPlanStatus {
    public static let draft = "draft"
    public static let accepted = "accepted"
    public static let archived = "archived"
}

/// Plan semanal completo; toda escritura devuelve el plan con la `revision` nueva.
public struct MealPlan: Codable, Equatable, Sendable, Identifiable {
    public var id: Int64
    public var weekStart: String
    public var status: String
    public var revision: Int
    public var acceptedAt: String?
    public var acceptedBy: Int64?
    public var updatedAt: String?
    public var items: [MealPlanItem]

    enum CodingKeys: String, CodingKey {
        case id, weekStart = "week_start", status, revision, acceptedAt = "accepted_at"
        case acceptedBy = "accepted_by", updatedAt = "updated_at", items
    }

    public var isAccepted: Bool { status == MealPlanStatus.accepted }
}

/// Aviso de `GET meal/plan/check`: `code` en `allergen`, `intolerance`, `diet` o `member_out`.
public struct MealIssue: Decodable, Equatable, Sendable {
    public var itemId: Int64
    public var day: String
    public var slot: String
    public var memberId: Int64
    public var code: String
    /// Valores de texto del detalle (`allergen`, `ingredient`, `diet`, `status`).
    public var detail: [String: String]

    enum CodingKeys: String, CodingKey {
        case itemId = "item_id", day, slot, memberId = "member_id", code, detail
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        itemId = try c.decode(Int64.self, forKey: .itemId)
        day = try c.decode(String.self, forKey: .day)
        slot = try c.decode(String.self, forKey: .slot)
        memberId = try c.decode(Int64.self, forKey: .memberId)
        code = try c.decode(String.self, forKey: .code)
        detail = (try? c.decode([String: String].self, forKey: .detail)) ?? [:]
    }
}

/// Casilla de hoy en `GET meal/today`.
public struct MealTodayItem: Codable, Equatable, Sendable, Identifiable {
    public var itemId: Int64
    public var slot: String
    /// Hora local del hogar, `HH:mm`.
    public var time: String
    public var kind: String
    public var title: String
    public var recipeId: Int64?
    public var servings: Int?
    public var cookMemberId: Int64?
    public var members: [Int64]
    public var id: Int64 { itemId }

    enum CodingKeys: String, CodingKey {
        case itemId = "item_id", slot, time, kind, title, recipeId = "recipe_id", servings
        case cookMemberId = "cook_member_id", members
    }
}

/// `GET meal/today`: `hasPlan == false` es «sin menú aceptado» (el bloque se oculta);
/// `hasPlan` con `items` vacío es «menú sin casillas hoy». `timezone` y `nowLocal` son los del hogar.
public struct MealsToday: Codable, Equatable, Sendable {
    public var hasPlan: Bool
    public var date: String
    public var timezone: String
    public var nowLocal: String
    public var items: [MealTodayItem]

    enum CodingKeys: String, CodingKey {
        case hasPlan = "has_plan", date, timezone, nowLocal = "now_local", items
    }
}

struct MealPlanItemsBody: Encodable {
    let weekStart: String
    let expectedRevision: Int
    let items: [MealPlanItem]
    let deleteIds: [Int64]

    enum CodingKeys: String, CodingKey {
        case weekStart = "week_start", expectedRevision = "expected_revision", items, deleteIds = "delete_ids"
    }
}

struct MealPlanAcceptBody: Encodable {
    let planId: Int64
    let expectedRevision: Int
    enum CodingKeys: String, CodingKey { case planId = "plan_id", expectedRevision = "expected_revision" }
}

struct MealPlanArchiveBody: Encodable {
    let planId: Int64
    enum CodingKeys: String, CodingKey { case planId = "plan_id" }
}

struct MealPlanCopyBody: Encodable {
    let fromWeek: String
    let toWeek: String
    enum CodingKeys: String, CodingKey { case fromWeek = "from_week", toWeek = "to_week" }
}
