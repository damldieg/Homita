import XCTest
@testable import ControlKit

/// Recetas comunes precargadas por país (0047, menus-recetas-precargadas): decodificación de `home_id` y
/// `country`, y filtro por país de `RecipesStore`.
final class RecipeCountryTests: XCTestCase {
    private let listJSON = """
    [{"id":1,"home_id":null,"country":"ES","name":"Paella valenciana","servings":4,"minutes":70,"slots":["lunch"]},
     {"id":2,"home_id":null,"country":"AR","name":"Empanadas de carne","servings":6,"minutes":75,"slots":["lunch","dinner"]},
     {"id":3,"home_id":null,"country":"ES","name":"Gazpacho andaluz","servings":4,"minutes":15,"slots":["lunch","dinner"]},
     {"id":4,"home_id":7,"country":null,"name":"Mi receta","servings":2,"minutes":null,"slots":[]},
     {"id":5,"name":"Respuesta antigua","servings":2,"minutes":10,"slots":["dinner"]}]
    """

    private func makeClient() -> APIClient {
        APIClient(baseURL: URL(string: "https://test.supabase.co/functions/v1/api")!,
                  session: StubURLProtocol.session(), tokenProvider: { "tok" }, homeIdProvider: { "7" },
                  readCache: ReadCache(directory: FileManager.default.temporaryDirectory
                      .appendingPathComponent("readcache-\(UUID().uuidString)")))
    }

    func testDecodeSummariesWithCountry() async throws {
        StubURLProtocol.reset { _ in StubURLProtocol.Stub(json: self.listJSON) }
        let list = try await RecipeRepository(client: makeClient()).list()
        XCTAssertEqual(list.map(\.country), ["ES", "AR", "ES", nil, nil])
        XCTAssertEqual(list.map(\.isCommon), [true, true, true, false, true])
        XCTAssertEqual(list[3].homeId, 7)
    }

    func testDecodeRecipeDetailWithCountry() async throws {
        let json = """
        {"id":1,"home_id":null,"country":"AR","name":"Locro criollo","servings":8,"minutes":180,"slots":["lunch"],
         "steps":["Remoja el maíz."],"created_by":null,"updated_at":"2026-11-26T10:00:00",
         "ingredients":[{"id":1,"position":0,"food_id":null,"label":"Maíz blanco seco","quantity":400,"unit":"g","optional":false}],
         "allergens":[]}
        """
        StubURLProtocol.reset { _ in StubURLProtocol.Stub(json: json) }
        let recipe = try await RecipeRepository(client: makeClient()).detail(id: 1)
        XCTAssertEqual(recipe.country, "AR")
        XCTAssertTrue(recipe.isCommon)
        XCTAssertEqual(recipe.ingredients.first?.label, "Maíz blanco seco")
    }

    func testStoreFiltersCommonRecipesByCountry() async throws {
        StubURLProtocol.reset { _ in StubURLProtocol.Stub(json: self.listJSON) }
        let store = RecipesStore(repo: RecipeRepository(client: makeClient()), activeHomeId: { "7" })
        await store.load()
        XCTAssertEqual(Set(store.countries), ["ES", "AR"])
        XCTAssertEqual(store.recipes.count, 5)
        store.country = "AR"
        // Solo recorta las comunes: la propia (id 4) se queda; la común sin país (id 5) también se descarta.
        XCTAssertEqual(store.recipes.map(\.id), [2, 4])
        store.country = nil
        XCTAssertEqual(store.recipes.count, 5)
    }

    func testPickerStoreExcludesCommonRecipes() async throws {
        StubURLProtocol.reset { _ in StubURLProtocol.Stub(json: self.listJSON) }
        let store = RecipesStore(repo: RecipeRepository(client: makeClient()), activeHomeId: { "7" })
        store.includeCommon = false
        await store.load()
        XCTAssertEqual(store.recipes.map(\.id), [4])
        XCTAssertTrue(store.countries.isEmpty)
    }

    func testCountryNameIsLocalizedInSpanish() {
        XCTAssertEqual(RecipeCountry.name("ES"), "España")
        XCTAssertEqual(RecipeCountry.name("AR"), "Argentina")
    }
}
