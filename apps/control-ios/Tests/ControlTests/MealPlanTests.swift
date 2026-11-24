import XCTest
@testable import ControlKit

final class MealPlanTests: XCTestCase {
    private let planJSON = """
    {"id":9007199254740993,"week_start":"2026-11-23","status":"draft","revision":3,"accepted_at":null,
     "accepted_by":null,"updated_at":"2026-11-24T10:00:00",
     "items":[{"id":11,"day":"2026-11-23","slot":"lunch","position":0,"kind":"recipe","recipe_id":5,
       "title":"Lentejas","servings":4,"cook_member_id":null,"members":[3,5]},
      {"id":12,"day":"2026-11-24","slot":"dinner","position":0,"kind":"eat_out","recipe_id":null,
       "title":"","servings":null,"cook_member_id":3,"members":[]}]}
    """

    private func makeClient() -> APIClient {
        APIClient(baseURL: URL(string: "https://test.supabase.co/functions/v1/api")!,
                  session: StubURLProtocol.session(), tokenProvider: { "tok" }, homeIdProvider: { "7" },
                  readCache: ReadCache(directory: FileManager.default.temporaryDirectory
                      .appendingPathComponent("readcache-\(UUID().uuidString)")))
    }

    private func body(_ r: URLRequest) -> String { String(data: r.capturedBody ?? Data(), encoding: .utf8) ?? "" }

    func testDecodePlanWithBigintIds() async throws {
        StubURLProtocol.reset { _ in StubURLProtocol.Stub(json: self.planJSON) }
        let plan = try await MealRepository(client: makeClient()).plan(weekStart: "2026-11-23")
        let sent = try XCTUnwrap(StubURLProtocol.requests.last)
        XCTAssertEqual(sent.httpMethod, "GET")
        XCTAssertEqual(sent.url?.query, "week_start=2026-11-23")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "X-Home-Id"), "7")
        XCTAssertNil(sent.capturedBody)
        let p = try XCTUnwrap(plan)
        XCTAssertEqual(p.id, 9007199254740993)
        XCTAssertEqual(p.revision, 3)
        XCTAssertFalse(p.isAccepted)
        XCTAssertEqual(p.items.map(\.members), [[3, 5], []])
        XCTAssertEqual(p.items[1].cookMemberId, 3)
    }

    func testPlanNullMeansNoPlan() async throws {
        StubURLProtocol.reset { _ in StubURLProtocol.Stub(json: "null") }
        let plan = try await MealRepository(client: makeClient()).plan(weekStart: "2026-11-23")
        XCTAssertNil(plan)
    }

    func testPlanWritesShape() async throws {
        StubURLProtocol.reset { _ in StubURLProtocol.Stub(json: self.planJSON) }
        let repo = MealRepository(client: makeClient())
        let new = MealPlanItem(day: "2026-11-23", slot: "lunch", kind: "free_text", title: "Pasta")
        let edit = MealPlanItem(id: 11, day: "2026-11-23", slot: "dinner", kind: "recipe", recipeId: 5, title: "X",
                                servings: 2, members: [])
        _ = try await repo.saveItems(weekStart: "2026-11-23", expectedRevision: 0, items: [new, edit], deleteIds: [12])
        _ = try await repo.accept(planId: 9, expectedRevision: 3)
        _ = try await repo.archive(planId: 9, expectedRevision: 4)
        _ = try await repo.copyWeek(from: "2026-11-16", to: "2026-11-23")
        let sent = StubURLProtocol.requests
        XCTAssertEqual(sent.map { $0.httpMethod ?? "" }, ["PATCH", "POST", "POST", "POST"])
        XCTAssertEqual(sent.compactMap { $0.url?.path.components(separatedBy: "/api/").last },
                       ["meal/plan/items", "meal/plan/accept", "meal/plan/archive", "meal/plan/copy"])
        XCTAssertEqual(body(sent[0]),
            #"{"delete_ids":[12],"expected_revision":0,"items":[{"day":"2026-11-23","kind":"free_text","position":0,"slot":"lunch","title":"Pasta"},{"day":"2026-11-23","id":11,"kind":"recipe","members":[],"position":0,"recipe_id":5,"servings":2,"slot":"dinner","title":"X"}],"week_start":"2026-11-23"}"#)
        XCTAssertEqual(body(sent[1]), #"{"expected_revision":3,"plan_id":9}"#)
        XCTAssertEqual(body(sent[2]), #"{"expected_revision":4,"plan_id":9}"#)
        XCTAssertEqual(body(sent[3]), #"{"from_week":"2026-11-16","to_week":"2026-11-23"}"#)
    }

    func testStaleRevisionIs409WithOwnMessage() async throws {
        StubURLProtocol.reset { _ in StubURLProtocol.Stub(status: 409, json: #"{"error":"Stale meal plan revision"}"#) }
        do {
            _ = try await MealRepository(client: makeClient()).saveItems(weekStart: "2026-11-23", expectedRevision: 1, items: [])
            XCTFail("debía fallar")
        } catch let error as APIError {
            XCTAssertTrue(error.isStaleRevision)
            XCTAssertFalse(error.isMealPlanExists)
            XCTAssertEqual(error.userMessage, "El menú ha cambiado en otro dispositivo. Se ha recargado.")
        }
        let exists = APIError.http(status: 409, message: "Meal plan exists")
        XCTAssertTrue(exists.isMealPlanExists)
        XCTAssertEqual(exists.userMessage, "Esa semana ya tiene un menú")
    }

    func testCheckAndTodayDecode() async throws {
        StubURLProtocol.reset { req in
            if req.url?.path.hasSuffix("/meal/plan/check") == true {
                return StubURLProtocol.Stub(json: #"[{"item_id":11,"day":"2026-11-23","slot":"lunch","member_id":3,"code":"allergen","detail":{"allergen":"egg","ingredient":"Huevos"}},{"item_id":12,"day":"2026-11-24","slot":"dinner","member_id":5,"code":"member_out","detail":{"status":"out"}}]"#)
            }
            return StubURLProtocol.Stub(json: #"{"has_plan":true,"date":"2026-11-24","timezone":"Pacific/Auckland","now_local":"09:15","items":[{"item_id":11,"slot":"lunch","time":"14:00","kind":"recipe","title":"Lentejas","recipe_id":5,"servings":4,"cook_member_id":null,"members":[3]}]}"#)
        }
        let repo = MealRepository(client: makeClient())
        let issues = try await repo.check(planId: 9)
        XCTAssertEqual(issues.map(\.code), ["allergen", "member_out"])
        XCTAssertEqual(issues[0].detail["allergen"], "egg")
        XCTAssertEqual(issues[1].memberId, 5)
        let today = try await repo.today()
        XCTAssertTrue(today.hasPlan)
        XCTAssertEqual(today.timezone, "Pacific/Auckland")
        XCTAssertEqual(today.nowLocal, "09:15")
        XCTAssertEqual(today.items[0].recipeId, 5)
        XCTAssertEqual(StubURLProtocol.requests.last?.url?.query, nil)
        _ = try await repo.today(date: "2026-11-25")
        XCTAssertEqual(StubURLProtocol.requests.last?.url?.query, "date=2026-11-25")
    }

    func testRecipeRepositoryShapesAndDecode() async throws {
        let recipeJSON = #"{"id":5,"name":"Lentejas","servings":4,"minutes":40,"slots":["lunch"],"steps":null,"created_by":1,"updated_at":"2026-11-24T10:00:00","ingredients":[{"id":1,"position":0,"food_id":77,"label":"Lentejas","quantity":250.5,"unit":"g"},{"id":2,"position":1,"food_id":null,"label":"agua","quantity":null,"unit":"al gusto"}],"allergens":["gluten"]}"#
        StubURLProtocol.reset { req in
            let path = req.url?.path ?? ""
            if path.hasSuffix("/recipe") { return StubURLProtocol.Stub(json: #"[{"id":5,"name":"Lentejas","servings":4,"minutes":null,"slots":[]}]"#) }
            if path.hasSuffix("/food") { return StubURLProtocol.Stub(json: #"[{"id":77,"home_id":null,"name":"Lentejas","section":"legumbres","allergens":[],"default_unit":"g","grams_per_unit":null}]"#) }
            if path.hasSuffix("/food/create") { return StubURLProtocol.Stub(status: 201, json: #"{"id":78,"home_id":7,"name":"Mi salsa","section":"otros","allergens":["gluten"],"default_unit":"ml","grams_per_unit":null}"#) }
            if path.hasSuffix("/delete") || path.hasSuffix("/delete") { return StubURLProtocol.Stub(json: #"{"success":true}"#) }
            return StubURLProtocol.Stub(status: path.hasSuffix("/create") ? 201 : 200, json: recipeJSON)
        }
        let repo = RecipeRepository(client: makeClient())
        let list = try await repo.list(query: "lent", slot: "lunch", maxMinutes: 45)
        XCTAssertEqual(list.map(\.id), [5])
        XCTAssertEqual(StubURLProtocol.requests.last?.url?.query?.split(separator: "&").sorted().joined(separator: "&"),
                       "max_minutes=45&q=lent&slot=lunch")
        let foods = try await repo.searchFood("lent")
        XCTAssertEqual(foods[0].section, "legumbres")
        XCTAssertNil(foods[0].homeId)
        let detail = try await repo.detail(id: 5)
        XCTAssertEqual(detail.ingredients[0].quantity, 250.5)
        XCTAssertEqual(detail.ingredients[1].foodId, nil)
        XCTAssertEqual(detail.allergens, ["gluten"])
        XCTAssertNil(detail.steps)

        let input = RecipeInput(name: "Lentejas", servings: 4, minutes: nil, slots: ["lunch"], steps: nil,
                                ingredients: [RecipeIngredient(foodId: 77, label: "Lentejas", quantity: 250, unit: "g", id: 1, position: 0),
                                              RecipeIngredient(label: "agua", unit: "al gusto")])
        _ = try await repo.create(input)
        _ = try await repo.update(id: 5, input)
        try await repo.delete(id: 5)
        let created = try await repo.createFood(FoodInput(name: "Mi salsa", allergens: ["gluten"], defaultUnit: "ml"))
        XCTAssertEqual(created.homeId, 7)
        try await repo.deleteFood(id: 78)
        let sent = Array(StubURLProtocol.requests.suffix(5))
        XCTAssertEqual(sent.map { $0.httpMethod ?? "" }, ["POST", "PATCH", "DELETE", "POST", "DELETE"])
        let ing = #""ingredients":[{"food_id":77,"label":"Lentejas","quantity":250,"unit":"g"},{"label":"agua","unit":"al gusto"}]"#
        XCTAssertEqual(body(sent[0]), #"{"#+ing+#","minutes":null,"name":"Lentejas","servings":4,"slots":["lunch"],"steps":null}"#)
        XCTAssertTrue(body(sent[1]).contains(#""id":5"#))
        XCTAssertTrue(body(sent[1]).contains(#""minutes":null"#))
        XCTAssertEqual(sent[2].url?.query, "id=5")
        XCTAssertEqual(body(sent[3]), #"{"allergens":["gluten"],"default_unit":"ml","name":"Mi salsa"}"#)
        XCTAssertEqual(sent[4].url?.query, "id=78")
        XCTAssertEqual(sent.map { $0.value(forHTTPHeaderField: "X-Home-Id") ?? "" }, Array(repeating: "7", count: 5))
    }

    func testIngredientValidity() {
        XCTAssertTrue(RecipeIngredient(foodId: 1, unit: "g").isValid)
        XCTAssertTrue(RecipeIngredient(label: "sal", unit: "pizca").isValid)
        XCTAssertFalse(RecipeIngredient(label: "  ").isValid)
        XCTAssertFalse(RecipeIngredient(foodId: 1, unit: "taza").isValid)
        XCTAssertFalse(RecipeIngredient(foodId: 1, quantity: -1, unit: "g").isValid)
    }
}
