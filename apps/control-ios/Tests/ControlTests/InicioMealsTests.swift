import XCTest
@testable import ControlKit

/// «Comidas de hoy» en Inicio: reloj del hogar, fases por hora y bloque oculto sin menú.
@MainActor
final class InicioMealsTests: XCTestCase {
    private func makeStore(deviceNow: String = "2026-11-24 00:00:00", json: String) -> InicioStore {
        StubURLProtocol.reset { _ in StubURLProtocol.Stub(json: json) }
        let client = makeTestClient()
        let utc = TimeZone(identifier: "UTC")!
        let now = PHPDateTime.parse(deviceNow, timeZone: utc)!
        return InicioStore(
            events: EventRepository(client: client), tasks: TaskRepository(client: client),
            routines: RoutineRepository(client: client), taskLists: TaskListRepository(client: client),
            meals: MealRepository(client: client),
            clock: { LocalClock(now: now, timeZone: utc) })
    }

    private func today(nowLocal: String, tz: String = "Pacific/Auckland") -> String {
        let item: (Int, String, String, String) -> String = { id, slot, time, title in
            #"{"item_id":\#(id),"slot":"\#(slot)","time":"\#(time)","kind":"recipe","title":"\#(title)","recipe_id":\#(id),"servings":4,"cook_member_id":null,"members":[]}"#
        }
        let items = [item(3, "dinner", "21:00", "Tortilla"), item(1, "breakfast", "08:00", "Tostadas"),
                     item(2, "lunch", "14:00", "Lentejas")].joined(separator: ",")
        return #"{"has_plan":true,"date":"2026-11-24","timezone":"\#(tz)","now_local":"\#(nowLocal)","items":[\#(items)]}"#
    }

    func testClockUsesHomeZoneAndNowLocalNotTheDevice() async throws {
        let store = makeStore(json: today(nowLocal: "09:15"))
        await store.loadMeals()
        let clock = try XCTUnwrap(store.mealsClock)
        XCTAssertEqual(clock.timeZone.identifier, "Pacific/Auckland")
        XCTAssertEqual(PHPDateTime.format(clock.now, timeZone: clock.timeZone), "2026-11-24 09:15:00")
        XCTAssertEqual(StubURLProtocol.requests.map { $0.url?.path.hasSuffix("/meal/today") }, [true])
    }

    func testPhasesFollowTheHomeHour() async {
        let store = makeStore(json: today(nowLocal: "13:30"))
        await store.loadMeals()
        XCTAssertEqual(store.todayMeals.map(\.title), ["Tostadas", "Lentejas", "Tortilla"])
        XCTAssertEqual(store.todayMeals.map { store.phase(of: $0) }, [.done, .soon, .later])
        XCTAssertEqual(store.minutesUntil(meal: store.todayMeals[1]), 30)
    }

    func testInProgressWithinAnHourAfterStart() async {
        let store = makeStore(json: today(nowLocal: "14:20"))
        await store.loadMeals()
        XCTAssertEqual(store.phase(of: store.todayMeals[1]), .now)
        XCTAssertEqual(store.phase(of: store.todayMeals[0]), .done)
    }

    func testHiddenWithoutAcceptedPlan() async {
        let store = makeStore(json: #"{"has_plan":false,"date":"2026-11-24","timezone":"Europe/Madrid","now_local":"09:00","items":[]}"#)
        XCTAssertFalse(store.showsMeals)
        await store.loadMeals()
        XCTAssertFalse(store.showsMeals)
        XCTAssertTrue(store.todayMeals.isEmpty)
    }

    func testShownWithPlanEvenWithoutItemsToday() async {
        let store = makeStore(json: #"{"has_plan":true,"date":"2026-11-24","timezone":"Europe/Madrid","now_local":"09:00","items":[]}"#)
        await store.loadMeals()
        XCTAssertTrue(store.showsMeals)
        XCTAssertTrue(store.todayMeals.isEmpty)
    }

    func testStoreWithoutMealsRepoNeverRequestsMeals() async {
        StubURLProtocol.reset { _ in StubURLProtocol.Stub(json: "[]") }
        let client = makeTestClient()
        let store = InicioStore(events: EventRepository(client: client), tasks: TaskRepository(client: client),
                                routines: RoutineRepository(client: client), taskLists: TaskListRepository(client: client))
        await store.loadMeals()
        XCTAssertFalse(store.showsMeals)
        XCTAssertTrue(StubURLProtocol.requests.isEmpty)
    }
}
