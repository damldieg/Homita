import XCTest
@testable import ControlKit

final class RecipeDraftTests: XCTestCase {
    func testCatalogIngredientTakesFoodNameAndDefaultUnit() {
        var draft = RecipeDraft()
        draft.addIngredient(Food(id: 77, name: "Lentejas", section: "legumbres", defaultUnit: "g"), quantity: 250)
        XCTAssertEqual(draft.ingredients, [RecipeIngredient(foodId: 77, label: "Lentejas", quantity: 250, unit: "g")])
    }

    func testFreeTextIngredientHasNoFoodIdAndEmptyIsIgnored() {
        var draft = RecipeDraft()
        draft.addFreeIngredient("  un chorrito de vino  ", unit: "al gusto")
        draft.addFreeIngredient("   ")
        XCTAssertEqual(draft.ingredients.count, 1)
        XCTAssertNil(draft.ingredients[0].foodId)
        XCTAssertEqual(draft.ingredients[0].label, "un chorrito de vino")
        XCTAssertEqual(draft.ingredients[0].unit, "al gusto")
    }

    func testValidity() {
        var draft = RecipeDraft()
        XCTAssertFalse(draft.isValid) // sin nombre
        draft.name = " Lentejas "
        XCTAssertTrue(draft.isValid)
        draft.servings = 0
        XCTAssertFalse(draft.isValid)
        draft.servings = 4
        draft.ingredients = [RecipeIngredient(label: nil, unit: "g")] // ni alimento ni texto
        XCTAssertFalse(draft.isValid)
        draft.ingredients = [RecipeIngredient(foodId: 1, unit: "taza")] // unidad desconocida
        XCTAssertFalse(draft.isValid)
        draft.ingredients = [RecipeIngredient(foodId: 1, unit: "g")]
        XCTAssertTrue(draft.isValid)
        draft.minutes = 2000
        XCTAssertFalse(draft.isValid)
    }

    func testInputTrimsAndMapsEmptyStepsToNil() throws {
        var draft = RecipeDraft()
        draft.name = " Sopa "
        draft.steps = ["  ", ""]
        XCTAssertNil(draft.input().steps)
        draft.steps = [" Hervir ", ""]
        XCTAssertEqual(draft.input().steps, ["Hervir"])
        XCTAssertEqual(draft.input().name, "Sopa")
        let json = String(data: try JSONCoding.encoder().encode(draft.input()), encoding: .utf8) ?? ""
        XCTAssertTrue(json.contains(#""minutes":null"#), json)
    }

    func testDraftFromRecipeKeepsIds() {
        let recipe = Recipe(id: 5, name: "X", servings: 3, minutes: 20, slots: ["lunch"], steps: nil,
                            ingredients: [RecipeIngredient(foodId: 1, label: "A", quantity: 1, unit: "kg", id: 9, position: 0)],
                            allergens: [], updatedAt: nil)
        let draft = RecipeDraft(recipe)
        XCTAssertEqual(draft.id, 5)
        XCTAssertEqual(draft.steps, [])
        XCTAssertEqual(draft.ingredients.count, 1)
    }
}
