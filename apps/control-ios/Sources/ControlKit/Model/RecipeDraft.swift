import Foundation

/// Borrador de receta del editor: nombre, raciones, tiempo, franjas, pasos e ingredientes. La lógica
/// de ingredientes (unidad, `food_id` o `label`) vive aquí para probarla sin vistas.
public struct RecipeDraft: Equatable, Sendable {
    public var id: Int64?
    public var name = ""
    public var servings = 2
    /// nil = sin tiempo indicado.
    public var minutes: Int?
    public var slots: [String] = []
    public var steps: [String] = []
    public var ingredients: [RecipeIngredient] = []

    public init() {}

    public init(_ recipe: Recipe) {
        id = recipe.id
        name = recipe.name
        servings = recipe.servings
        minutes = recipe.minutes
        slots = recipe.slots
        steps = recipe.steps ?? []
        ingredients = recipe.ingredients
    }

    /// Ingrediente del catálogo: nombre y unidad por defecto del alimento.
    public mutating func addIngredient(_ food: Food, quantity: Double? = nil) {
        ingredients.append(RecipeIngredient(foodId: food.id, label: food.name, quantity: quantity, unit: food.defaultUnit))
    }

    /// Ingrediente en texto libre (sin `food_id`); texto vacío no se añade.
    public mutating func addFreeIngredient(_ text: String, quantity: Double? = nil, unit: String = "ud") {
        let label = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else { return }
        ingredients.append(RecipeIngredient(label: label, quantity: quantity, unit: unit))
    }

    public mutating func removeIngredient(at index: Int) {
        guard ingredients.indices.contains(index) else { return }
        ingredients.remove(at: index)
    }

    public var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Válido para guardar: nombre, raciones 1…100 y todos los ingredientes con alimento o texto.
    public var isValid: Bool {
        !trimmedName.isEmpty && (1...100).contains(servings) && ingredients.allSatisfy(\.isValid)
            && (minutes.map { (0...1440).contains($0) } ?? true)
    }

    /// Cuerpo de la petición: pasos vacíos → `nil` (sin pasos) y los textos recortados.
    public func input() -> RecipeInput {
        let cleanSteps = steps.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return RecipeInput(name: trimmedName, servings: servings, minutes: minutes, slots: slots,
                           steps: cleanSteps.isEmpty ? nil : cleanSteps, ingredients: ingredients)
    }
}
