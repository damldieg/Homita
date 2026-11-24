import XCTest
@testable import ControlKit

final class MealsStoreTests: XCTestCase {
    private let profileJSON = """
    {"home_id":7,"timezone":"Europe/Madrid","can_edit":true,
     "profile":{"week_start_day":1,"shopping_day":6,"equipment":[],"group_by_section":true},
     "slots":[{"slot":"dinner","enabled":true,"time":"21:00"},{"slot":"lunch","enabled":true,"time":"14:00"},
              {"slot":"snack","enabled":false,"time":"17:30"}],
     "members":[],"candidates":[],
     "schedule":[{"home_member_id":3,"weekday":2,"slot":"lunch","status":"out"}]}
    """

    private func planJSON(revision: Int, status: String = "draft", extra: String = "") -> String {
        """
        {"id":9,"week_start":"2026-11-23","status":"\(status)","revision":\(revision),"accepted_at":null,
         "accepted_by":null,"updated_at":"2026-11-24T10:00:00",
         "items":[{"id":11,"day":"2026-11-23","slot":"lunch","position":0,"kind":"free_text","recipe_id":null,
           "title":"Pasta","servings":null,"cook_member_id":null,"members":[3]}\(extra)]}
        """
    }

    /// 24 nov 2026 (martes) a mediodía UTC: la semana empieza el lunes 23.
    private let tuesday = Date(timeIntervalSince1970: 1_795_521_600)

    private func makeStore() -> MealsStore {
        let client = APIClient(baseURL: URL(string: "https://test.supabase.co/functions/v1/api")!,
                               session: StubURLProtocol.session(), tokenProvider: { "tok" }, homeIdProvider: { "7" },
                               readCache: ReadCache(directory: FileManager.default.temporaryDirectory
                                   .appendingPathComponent("readcache-\(UUID().uuidString)")))
        let date = tuesday
        return MealsStore(meals: MealRepository(client: client), activeHomeId: { "7" }, now: { date })
    }

    private func route(plan: @escaping (URLRequest) -> StubURLProtocol.Stub) {
        StubURLProtocol.reset { req in
            let path = req.url?.path ?? ""
            if path.hasSuffix("/meal/profile") { return StubURLProtocol.Stub(json: self.profileJSON) }
            if path.hasSuffix("/meal/plan/check") { return StubURLProtocol.Stub(json: "[]") }
            return plan(req)
        }
    }

    private func calls(_ suffix: String) -> [URLRequest] {
        StubURLProtocol.requests.filter { $0.url?.path.hasSuffix(suffix) == true }
    }

    func testLoadsProfileAndPlanForCurrentWeek() async throws {
        route { _ in StubURLProtocol.Stub(json: self.planJSON(revision: 2)) }
        let store = makeStore()
        await store.load()
        XCTAssertEqual(store.state, .loaded)
        XCTAssertEqual(store.weekStart, "2026-11-23")
        XCTAssertEqual(store.days.first, "2026-11-23")
        XCTAssertEqual(store.days.last, "2026-11-29")
        XCTAssertEqual(store.enabledSlots.map(\.slot), ["lunch", "dinner"])
        XCTAssertEqual(store.items(day: "2026-11-23", slot: "lunch").map(\.title), ["Pasta"])
        XCTAssertTrue(store.isOut(memberId: 3, day: "2026-11-24", slot: "lunch"))
        XCTAssertFalse(store.isOut(memberId: 3, day: "2026-11-24", slot: "dinner"))
        XCTAssertFalse(store.isDirty)
        XCTAssertEqual(calls("/meal/plan").first?.url?.query, "week_start=2026-11-23")
    }

    private func profileJSON(enabled: [String: Bool]) -> String {
        let slots = ["breakfast", "lunch", "snack", "dinner"].map {
            "{\"slot\":\"\($0)\",\"enabled\":\(enabled[$0] ?? false),\"time\":\"12:00\"}"
        }.joined(separator: ",")
        return profileJSON.replacingOccurrences(
            of: #"(?s)\"slots\":\[.*?\}\],"#, with: "\"slots\":[\(slots)],", options: .regularExpression)
    }

    /// El perfil cambia por otro camino (`MealProfileView`) y la Semana, al volver a entrar, lo refleja.
    func testReloadsProfileSoDisabledSlotsDisappearAndReturn() async throws {
        var current = profileJSON(enabled: ["breakfast": true, "lunch": true, "dinner": true])
        StubURLProtocol.reset { req in
            let path = req.url?.path ?? ""
            if path.hasSuffix("/meal/profile") { return StubURLProtocol.Stub(json: current) }
            if path.hasSuffix("/meal/plan/check") { return StubURLProtocol.Stub(json: "[]") }
            return StubURLProtocol.Stub(json: self.planJSON(revision: 2))
        }
        let store = makeStore()
        await store.load()
        XCTAssertEqual(store.enabledSlots.map(\.slot), ["breakfast", "lunch", "dinner"])

        current = profileJSON(enabled: ["breakfast": true, "dinner": true])
        await store.load()
        XCTAssertEqual(store.enabledSlots.map(\.slot), ["breakfast", "dinner"])

        current = profileJSON(enabled: ["dinner": true])
        await store.load()
        XCTAssertEqual(store.enabledSlots.map(\.slot), ["dinner"])

        current = profileJSON(enabled: ["breakfast": true, "lunch": true, "dinner": true])
        await store.load()
        XCTAssertEqual(store.enabledSlots.map(\.slot), ["breakfast", "lunch", "dinner"])
    }

    func testReloadKeepsLocalEditsButRefreshesProfile() async throws {
        var current = profileJSON(enabled: ["lunch": true, "dinner": true])
        StubURLProtocol.reset { req in
            let path = req.url?.path ?? ""
            if path.hasSuffix("/meal/profile") { return StubURLProtocol.Stub(json: current) }
            if path.hasSuffix("/meal/plan/check") { return StubURLProtocol.Stub(json: "[]") }
            return StubURLProtocol.Stub(json: self.planJSON(revision: 2))
        }
        let store = makeStore()
        await store.load()
        store.add(MealPlanItem(day: "2026-11-24", slot: "dinner", kind: "free_text", title: "Sopa"))
        current = profileJSON(enabled: ["dinner": true])
        await store.load()
        XCTAssertEqual(store.enabledSlots.map(\.slot), ["dinner"])
        XCTAssertTrue(store.isDirty)
        XCTAssertEqual(store.items(day: "2026-11-24", slot: "dinner").map(\.title), ["Sopa"])
    }

    /// R1-05: «sin avisos (comprobado)» solo para casillas evaluables; texto libre, sobras e ingredientes
    /// sin catálogo quedan «sin comprobar», y con cambios locales nada está comprobado.
    func testCheckStatusDistinguishesCleanFromUnchecked() async throws {
        let extra = """
        ,{"id":12,"day":"2026-11-23","slot":"dinner","position":0,"kind":"recipe","recipe_id":5,
          "title":"Lentejas","servings":2,"cook_member_id":null,"members":[3]},
         {"id":13,"day":"2026-11-24","slot":"dinner","position":0,"kind":"recipe","recipe_id":6,
          "title":"Con sal","servings":2,"cook_member_id":null,"members":[3]},
         {"id":14,"day":"2026-11-25","slot":"dinner","position":0,"kind":"eat_out","recipe_id":null,
          "title":"","servings":null,"cook_member_id":null,"members":[3]}
        """
        let json = planJSON(revision: 2, extra: extra).replacingOccurrences(
            of: #""items":"#, with: #""unchecked_item_ids":[11,13],"items":"#)
        route { _ in StubURLProtocol.Stub(json: json) }
        let store = makeStore()
        await store.load()
        let byId = Dictionary(uniqueKeysWithValues: store.items.compactMap { item in item.id.map { ($0, item) } })
        XCTAssertEqual(store.checkStatus(for: try XCTUnwrap(byId[11])), .unchecked)
        XCTAssertEqual(store.checkStatus(for: try XCTUnwrap(byId[12])), .clean)
        XCTAssertEqual(store.checkStatus(for: try XCTUnwrap(byId[13])), .unchecked)
        XCTAssertEqual(store.checkStatus(for: try XCTUnwrap(byId[14])), .notApplicable)
        XCTAssertEqual(store.uncheckedCount, 2)
        store.add(MealPlanItem(day: "2026-11-26", slot: "lunch", kind: "recipe", recipeId: 5))
        XCTAssertEqual(store.checkStatus(for: try XCTUnwrap(byId[12])), .unchecked)
        XCTAssertEqual(store.uncheckedCount, 4)
    }

    func testPlanWithoutUncheckedListIsNeverCleanByDefault() async throws {
        route { _ in StubURLProtocol.Stub(json: self.planJSON(revision: 2)) }
        let store = makeStore()
        await store.load()
        XCTAssertEqual(store.checkStatus(for: try XCTUnwrap(store.items.first)), .unchecked)
    }

    func testNoPlanStartsWithRevisionZero() async throws {
        route { req in
            if req.httpMethod == "PATCH" { return StubURLProtocol.Stub(json: self.planJSON(revision: 1)) }
            return StubURLProtocol.Stub(json: "null")
        }
        let store = makeStore()
        await store.load()
        XCTAssertNil(store.plan)
        store.add(MealPlanItem(day: "2026-11-23", slot: "lunch", kind: "free_text", title: "Pasta"))
        XCTAssertTrue(store.isDirty)
        let saved = await store.save()
        XCTAssertTrue(saved)
        let body = String(data: try XCTUnwrap(calls("/meal/plan/items").first?.capturedBody), encoding: .utf8) ?? ""
        XCTAssertTrue(body.contains(#""expected_revision":0"#), body)
        XCTAssertEqual(store.plan?.revision, 1)
        XCTAssertFalse(store.isDirty)
    }

    func testSaveSendsOnlyChangesWithCurrentRevision() async throws {
        route { req in
            if req.httpMethod == "PATCH" { return StubURLProtocol.Stub(json: self.planJSON(revision: 3)) }
            return StubURLProtocol.Stub(json: self.planJSON(revision: 2))
        }
        let store = makeStore()
        await store.load()
        let existing = try XCTUnwrap(store.items.first)
        var edited = existing
        edited.title = "Arroz"
        store.replace(existing, with: edited)
        store.add(MealPlanItem(day: "2026-11-25", slot: "dinner", kind: "eat_out"))
        _ = await store.save()
        let body = String(data: try XCTUnwrap(calls("/meal/plan/items").first?.capturedBody), encoding: .utf8) ?? ""
        XCTAssertTrue(body.contains(#""expected_revision":2"#), body)
        XCTAssertTrue(body.contains(#""title":"Arroz""#), body)
        XCTAssertTrue(body.contains(#""kind":"eat_out""#), body)
        XCTAssertTrue(body.contains(#""delete_ids":[]"#), body)
    }

    func testStaleRevisionReloadsDiscardsLocalAndNotifies() async throws {
        var reads = 0
        route { req in
            if req.httpMethod == "PATCH" {
                return StubURLProtocol.Stub(status: 409, json: #"{"error":"Stale meal plan revision"}"#)
            }
            reads += 1
            return StubURLProtocol.Stub(json: self.planJSON(revision: reads == 1 ? 2 : 5))
        }
        let store = makeStore()
        await store.load()
        store.remove(try XCTUnwrap(store.items.first))
        XCTAssertTrue(store.isDirty)
        let saved = await store.save()
        XCTAssertFalse(saved)
        XCTAssertEqual(store.plan?.revision, 5)
        XCTAssertEqual(store.items.count, 1)
        XCTAssertFalse(store.isDirty)
        XCTAssertEqual(store.notice, "El menú ha cambiado en otro dispositivo. Se ha recargado.")
        XCTAssertNil(store.errorMessage)
    }

    func testAcceptSavesFirstThenAcceptsWithNewRevision() async throws {
        route { req in
            let path = req.url?.path ?? ""
            if path.hasSuffix("/items") { return StubURLProtocol.Stub(json: self.planJSON(revision: 3)) }
            if path.hasSuffix("/accept") { return StubURLProtocol.Stub(json: self.planJSON(revision: 4, status: "accepted")) }
            return StubURLProtocol.Stub(json: self.planJSON(revision: 2))
        }
        let store = makeStore()
        await store.load()
        store.add(MealPlanItem(day: "2026-11-26", slot: "lunch", kind: "leftovers"))
        await store.accept()
        let order = StubURLProtocol.requests.compactMap { $0.url?.path.components(separatedBy: "/api/").last }
            .filter { $0.hasSuffix("items") || $0.hasSuffix("accept") }
        XCTAssertEqual(order, ["meal/plan/items", "meal/plan/accept"])
        let body = String(data: try XCTUnwrap(calls("/accept").first?.capturedBody), encoding: .utf8) ?? ""
        XCTAssertEqual(body, #"{"expected_revision":3,"plan_id":9}"#)
        XCTAssertTrue(store.isAccepted)
        XCTAssertEqual(store.plan?.revision, 4)
    }

    func testMenuChangedHookFiresOnAcceptNotOnDraftSave() async throws {
        route { req in
            let path = req.url?.path ?? ""
            if path.hasSuffix("/items") { return StubURLProtocol.Stub(json: self.planJSON(revision: 3)) }
            if path.hasSuffix("/accept") { return StubURLProtocol.Stub(json: self.planJSON(revision: 4, status: "accepted")) }
            return StubURLProtocol.Stub(json: self.planJSON(revision: 2))
        }
        let store = makeStore()
        var fired = 0
        store.onMenuChanged = { fired += 1 }
        await store.load()
        store.add(MealPlanItem(day: "2026-11-26", slot: "lunch", kind: "leftovers"))
        await store.save()
        XCTAssertEqual(fired, 0, "guardar un borrador no toca el widget")
        await store.accept()
        XCTAssertEqual(fired, 1)
    }

    func testPrepareAcceptLoadsPreviewThenAcceptKeepsShoppingSummary() async throws {
        let previewJSON = #"{"plan_id":9,"items":[{"agg_key":"f1|g","label":"Arroz","food_id":1,"quantity":250,"unit":"g","section":"cereales","sources":[{"plan_item_id":11,"recipe_id":2,"name":"Paella","qty":250,"unit":"g"}]}]}"#
        route { req in
            let path = req.url?.path ?? ""
            if path.hasSuffix("/shopping/preview") { return StubURLProtocol.Stub(json: previewJSON) }
            if path.hasSuffix("/accept") {
                return StubURLProtocol.Stub(json: self.planJSON(revision: 4, status: "accepted")
                    .replacingOccurrences(of: #""revision":4,"#, with: #""revision":4,"shopping_sync":{"added":3,"updated":1,"removed":0},"#))
            }
            return StubURLProtocol.Stub(json: self.planJSON(revision: 2))
        }
        let store = makeStore()
        await store.load()
        await store.prepareAccept()
        XCTAssertEqual(store.acceptPreview?.items.first?.label, "Arroz")
        XCTAssertEqual(calls("/shopping/preview").first?.url?.query, "plan_id=9")
        XCTAssertTrue(calls("/accept").isEmpty, "mostrar el resumen no acepta")
        store.cancelAccept()
        XCTAssertNil(store.acceptPreview)

        await store.prepareAccept()
        await store.accept()
        XCTAssertNil(store.acceptPreview)
        XCTAssertTrue(store.isAccepted)
        XCTAssertEqual(store.acceptedShopping, ShoppingSyncResult(added: 3, updated: 1, removed: 0))
    }

    func testPrepareAcceptOpensEmptySheetWhenPreviewFails() async throws {
        route { req in
            if req.url?.path.hasSuffix("/shopping/preview") == true { return StubURLProtocol.Stub(status: 500, json: "{}") }
            return StubURLProtocol.Stub(json: self.planJSON(revision: 2))
        }
        let store = makeStore()
        await store.load()
        await store.prepareAccept()
        XCTAssertEqual(store.acceptPreview?.items.count, 0)
    }

    func testCopyDayReplacesTargetWithCloneWithoutIds() async throws {
        let extra = #",{"id":12,"day":"2026-11-24","slot":"dinner","position":0,"kind":"eat_out","recipe_id":null,"title":"","servings":null,"cook_member_id":null,"members":[]}"#
        route { _ in StubURLProtocol.Stub(json: self.planJSON(revision: 2, extra: extra)) }
        let store = makeStore()
        await store.load()
        store.copyDay(from: "2026-11-23", to: "2026-11-24")
        XCTAssertEqual(store.items(day: "2026-11-24", slot: "dinner").count, 0)
        let clones = store.items(day: "2026-11-24", slot: "lunch")
        XCTAssertEqual(clones.map(\.title), ["Pasta"])
        XCTAssertNil(clones.first?.id)
        XCTAssertEqual(clones.first?.members, [3])
        let changes = store.pendingChanges()
        XCTAssertEqual(changes.deleteIds, [12])
        XCTAssertEqual(changes.items.count, 1)
        store.discardChanges()
        XCTAssertFalse(store.isDirty)
    }

    func testRepeatPreviousWeekCopiesAndExistsIsNotified() async throws {
        route { req in
            if req.url?.path.hasSuffix("/copy") == true { return StubURLProtocol.Stub(status: 201, json: self.planJSON(revision: 1)) }
            return StubURLProtocol.Stub(json: "null")
        }
        let store = makeStore()
        await store.load()
        await store.repeatPreviousWeek()
        let body = String(data: try XCTUnwrap(calls("/copy").first?.capturedBody), encoding: .utf8) ?? ""
        XCTAssertEqual(body, #"{"from_week":"2026-11-16","to_week":"2026-11-23"}"#)
        XCTAssertNotNil(store.plan)

        route { req in
            if req.url?.path.hasSuffix("/copy") == true { return StubURLProtocol.Stub(status: 409, json: #"{"error":"Meal plan exists"}"#) }
            return StubURLProtocol.Stub(json: "null")
        }
        let other = makeStore()
        await other.load()
        await other.repeatPreviousWeek()
        XCTAssertEqual(other.notice, "Esa semana ya tiene un menú")
    }

    func testShiftWeekLoadsThatWeek() async throws {
        route { _ in StubURLProtocol.Stub(json: "null") }
        let store = makeStore()
        await store.load()
        await store.shiftWeek(by: 1)
        XCTAssertEqual(store.weekStart, "2026-11-30")
        XCTAssertEqual(calls("/meal/plan").last?.url?.query, "week_start=2026-11-30")
        await store.goToCurrentWeek()
        XCTAssertEqual(store.weekStart, "2026-11-23")
    }

    func testWeekStartRespectsConfiguredDay() {
        let madrid = TimeZone(identifier: "Europe/Madrid")!
        XCTAssertEqual(MealWeek.weekStart(containing: tuesday, weekStartDay: 7, timeZone: madrid), "2026-11-22")
        XCTAssertEqual(MealWeek.weekStart(containing: tuesday, weekStartDay: 2, timeZone: madrid), "2026-11-24")
        // 23:30 UTC del lunes ya es martes en Auckland
        let late = Date(timeIntervalSince1970: 1_795_521_600 - 45_000)
        XCTAssertEqual(MealWeek.string(late, timeZone: TimeZone(identifier: "Pacific/Auckland")!), "2026-11-24")
    }
}
