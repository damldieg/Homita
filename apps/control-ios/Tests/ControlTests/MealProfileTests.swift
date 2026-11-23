import XCTest
@testable import ControlKit

final class MealProfileTests: XCTestCase {
    private let profileJSON = """
    {"home_id":7,"timezone":"Europe/Madrid","can_edit":true,
     "profile":{"week_start_day":1,"shopping_day":6,"cook_minutes_weekday":null,"cook_minutes_weekend":60,
       "cook_skill":null,"equipment":["stove","oven","microwave"],"freezer_space":null,"repeat_policy":null,
       "leftovers":null,"dessert":null,"budget_weekly":120.5,"task_list_id":null,"group_by_section":true,
       "preferences":{"x":1},"schema_version":1},
     "slots":[{"slot":"lunch","enabled":true,"time":"14:00"},{"slot":"dinner","enabled":true,"time":"21:00"}],
     "members":[{"home_member_id":3,"name":"Ana","kind":"adult","color":"#112233","linked":true,"is_me":true,
       "age_band":"adult","portion_size":null,"allergies_answered":true,
       "allergies":[{"allergen":"egg","severity":"no_traces"}],"diet":"omnivore","diet_note":null,"goals":[],
       "dislikes":["coliflor"],"favorites":[],"quirks":null,"spice":1,"preferences":{}}],
     "schedule":[{"home_member_id":3,"weekday":2,"slot":"lunch","status":"out"}]}
    """

    func testDecodeProfile() async throws {
        StubURLProtocol.reset { _ in StubURLProtocol.Stub(json: self.profileJSON) }
        let profile = try await MealRepository(client: makeTestClient()).profile()
        let sent = try XCTUnwrap(StubURLProtocol.requests.last)
        XCTAssertEqual(sent.httpMethod, "GET")
        XCTAssertTrue(sent.url?.path.hasSuffix("/api/meal/profile") == true)
        XCTAssertEqual(profile.homeId, 7)
        XCTAssertEqual(profile.profile.budgetWeekly, 120.5)
        XCTAssertEqual(profile.profile.cookMinutesWeekend, 60)
        XCTAssertEqual(profile.slots.map(\.time), ["14:00", "21:00"])
        XCTAssertEqual(profile.members[0].allergies, [MealAllergy(allergen: "egg", severity: "no_traces")])
        XCTAssertTrue(profile.members[0].isMe)
        XCTAssertEqual(profile.schedule[0].status, "out")
    }

    func testMealRequestsShapeAndHeader() async throws {
        StubURLProtocol.reset { _ in StubURLProtocol.Stub(json: #"{"success":true}"#) }
        let client = APIClient(baseURL: URL(string: "https://test.supabase.co/functions/v1/api")!,
                               session: StubURLProtocol.session(), tokenProvider: { "tok" }, homeIdProvider: { "7" },
                               readCache: ReadCache(directory: FileManager.default.temporaryDirectory
                                   .appendingPathComponent("readcache-\(UUID().uuidString)")))
        let repo = MealRepository(client: client)
        try await repo.updateHome(MealHomeUpdate(shoppingDay: 5))
        try await repo.updateMember(MealMemberUpdate(homeMemberId: 3, diet: "vegan", spice: 2))
        try await repo.setSlots([MealSlot(slot: "lunch", enabled: true, time: "14:30")])
        try await repo.setSchedule([MealScheduleEntry(homeMemberId: 3, weekday: 1, slot: "lunch", status: "out")])
        let sent = StubURLProtocol.requests
        XCTAssertEqual(sent.map { $0.httpMethod ?? "" }, ["PATCH", "PATCH", "PUT", "PUT"])
        XCTAssertEqual(sent.map { $0.value(forHTTPHeaderField: "X-Home-Id") ?? "" }, ["7", "7", "7", "7"])
        func body(_ i: Int) throws -> String { String(data: try XCTUnwrap(sent[i].capturedBody), encoding: .utf8) ?? "" }
        XCTAssertEqual(try body(0), #"{"shopping_day":5}"#)
        XCTAssertEqual(try body(1), #"{"diet":"vegan","home_member_id":3,"spice":2}"#)
        XCTAssertEqual(try body(2), #"{"slots":[{"enabled":true,"slot":"lunch","time":"14:30"}]}"#)
        XCTAssertEqual(try body(3), #"{"entries":[{"home_member_id":3,"slot":"lunch","status":"out","weekday":1}]}"#)
        XCTAssertTrue(sent[2].url?.path.hasSuffix("/api/meal/slots") == true)
    }

    func testRemoveMemberBody() throws {
        let data = try JSONCoding.encoder().encode(MealMemberUpdate(homeMemberId: 4, eats: false))
        XCTAssertEqual(String(data: data, encoding: .utf8), #"{"eats":false,"home_member_id":4}"#)
    }

    func testTasteBlockDetection() {
        XCTAssertTrue(MealMemberUpdate(homeMemberId: 1, dislikes: ["a"], spice: 1).onlyTasteBlock)
        XCTAssertFalse(MealMemberUpdate(homeMemberId: 1, diet: "vegan", spice: 1).onlyTasteBlock)
        XCTAssertFalse(MealMemberUpdate(homeMemberId: 1, ageBand: "adult").onlyTasteBlock)
    }

    func testEaterCandidatesExcludePetsAndInactive() {
        let members = [
            HomeMember(id: 1, homeId: 7, kind: "adult", name: "A"),
            HomeMember(id: 2, homeId: 7, kind: "pet", name: "Rex"),
            HomeMember(id: 3, homeId: 7, kind: "child", name: "N", status: "inactive"),
            HomeMember(id: 4, homeId: 7, kind: "guest", name: "G"),
        ]
        XCTAssertEqual(MealRules.eaterCandidates(members).map(\.id), [1, 4])
    }

    func testDefaultAgeBandAndTimes() {
        XCTAssertEqual(MealRules.defaultAgeBand(kind: "child"), "4-12")
        XCTAssertEqual(MealRules.defaultAgeBand(kind: "adult"), "adult")
        XCTAssertEqual(MealRules.minutes(fromTime: "14:05"), 845)
        XCTAssertNil(MealRules.minutes(fromTime: "25:00"))
        XCTAssertEqual(MealRules.time(fromMinutes: 845), "14:05")
    }

    func testStartCompleteNeedsAllergyAnswerForEveryone() throws {
        var profile = try JSONCoding.decoder().decode(MealProfile.self, from: Data(profileJSON.utf8))
        XCTAssertTrue(MealRules.startComplete(profile))
        profile.members[0].allergiesAnswered = false
        XCTAssertFalse(MealRules.startComplete(profile))
        profile.members = []
        XCTAssertFalse(MealRules.startComplete(profile))
    }

    func testOutScheduleAndOutDays() throws {
        var profile = try JSONCoding.decoder().decode(MealProfile.self, from: Data(profileJSON.utf8))
        let entries = MealRules.outSchedule(days: [3], eaters: [3], slots: profile.slots, current: profile.schedule)
        // miércoles fuera en comida y cena + martes (antes fuera) vuelve a casa en la comida
        XCTAssertEqual(entries.filter { $0.status == "out" }.map(\.slot).sorted(), ["dinner", "lunch"])
        XCTAssertEqual(entries.filter { $0.status == "home" }, [MealScheduleEntry(homeMemberId: 3, weekday: 2, slot: "lunch", status: "home")])
        profile.schedule = [
            MealScheduleEntry(homeMemberId: 3, weekday: 3, slot: "lunch", status: "out"),
            MealScheduleEntry(homeMemberId: 3, weekday: 3, slot: "dinner", status: "out"),
            MealScheduleEntry(homeMemberId: 3, weekday: 4, slot: "lunch", status: "out"),
        ]
        XCTAssertEqual(MealRules.outDays(profile), [3])
    }

    func testMealGetIsNotCached() {
        XCTAssertFalse(ReadCache.isCacheable(APIRequest(method: .get, path: "meal/profile")))
    }
}
