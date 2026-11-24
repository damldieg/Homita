import XCTest
@testable import ControlKit

final class ShoppingModelsTests: XCTestCase {
    func testDecodesListWithBigintIdsAndSources() throws {
        let json = """
        {"revision":3,"items":[
          {"id":9007199254740993,"label":"Tomate","food_id":12,"quantity":500.0,"unit":"g","section":"verdura",
           "origin":"menu","plan_id":9,"sources":[{"plan_item_id":4,"recipe_id":2,"name":"Ensalada","qty":500,"unit":"g"}],
           "qty_overridden":false,"state":"pending","checked_at":null,"checked_by":null,
           "created_at":"2026-11-24T10:00:00","updated_at":"2026-11-24T10:00:00"},
          {"id":2,"label":"Pilas","food_id":null,"quantity":null,"unit":"ud","section":"otros","origin":"manual",
           "plan_id":null,"sources":null,"qty_overridden":false,"state":"skipped"}]}
        """
        let list = try JSONDecoder().decode(ShoppingList.self, from: Data(json.utf8))
        XCTAssertEqual(list.revision, 3)
        XCTAssertEqual(list.items[0].id, 9_007_199_254_740_993)
        XCTAssertEqual(list.items[0].sources.first?.name, "Ensalada")
        XCTAssertEqual(list.items[0].quantityText, "500 g")
        XCTAssertTrue(list.items[1].isSkipped)
        XCTAssertEqual(list.items[1].quantityText, "")
        XCTAssertTrue(list.items[1].sources.isEmpty)
    }

    func testSyncSummaryAndPlanShoppingSync() throws {
        XCTAssertEqual(ShoppingSyncResult(added: 2, updated: 0, removed: 1).summary, "+2 −1")
        XCTAssertTrue(ShoppingSyncResult(added: 0, updated: 0, removed: 0).isEmpty)
        let plan = """
        {"id":9,"week_start":"2026-11-23","status":"accepted","revision":4,"items":[],
         "shopping_sync":{"added":3,"updated":1,"removed":0}}
        """
        let decoded = try JSONDecoder().decode(MealPlan.self, from: Data(plan.utf8))
        XCTAssertEqual(decoded.shoppingSync, ShoppingSyncResult(added: 3, updated: 1, removed: 0))
    }

    func testDecodesPreview() throws {
        let json = """
        {"plan_id":9,"items":[{"agg_key":"f1|g","label":"Arroz","food_id":1,"quantity":250,"unit":"g",
          "section":"cereales","sources":[]}]}
        """
        let preview = try JSONDecoder().decode(ShoppingPreview.self, from: Data(json.utf8))
        XCTAssertEqual(preview.items.first?.quantityText, "250 g")
    }
}
