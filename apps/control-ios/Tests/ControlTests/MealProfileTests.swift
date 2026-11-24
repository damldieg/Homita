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
     "candidates":[{"id":3,"home_id":7,"kind":"adult","name":"Ana","color":"#112233","status":"active","linked":true},
       {"id":5,"home_id":7,"kind":"child","name":"Leo","color":null,"status":"active","linked":false}],
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
        XCTAssertEqual(profile.candidates.map(\.id), [3, 5])
        XCTAssertEqual(profile.candidates[1].kind, "child")
    }

    /// R1-01: la pantalla carga A1 solo de `GET meal/profile`; `GET home/member` (403 sin `home.view`) no se llama.
    func testStoreLoadsCandidatesWithoutHomeMemberCall() async throws {
        StubURLProtocol.reset { req in
            if req.url?.path.contains("/home/member") == true {
                return StubURLProtocol.Stub(status: 403, json: #"{"error":"Not Allowed"}"#)
            }
            return StubURLProtocol.Stub(json: self.profileJSON)
        }
        let store = MealProfileStore(meals: MealRepository(client: makeTestClient()), activeHomeId: { "7" })
        await store.load()
        XCTAssertEqual(store.state, .loaded)
        XCTAssertEqual(store.candidates.map(\.id), [3, 5])
        XCTAssertEqual(store.profile?.members.map(\.homeMemberId), [3])
        XCTAssertFalse(StubURLProtocol.requests.contains { $0.url?.path.contains("/home/member") == true })
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

    private func out(_ day: Int, _ slot: String) -> MealScheduleEntry {
        MealScheduleEntry(homeMemberId: 3, weekday: day, slot: slot, status: "out")
    }
    private func home(_ day: Int, _ slot: String) -> MealScheduleEntry {
        MealScheduleEntry(homeMemberId: 3, weekday: day, slot: slot, status: "home")
    }

    func testOutScheduleModes() throws {
        let profile = try JSONCoding.decoder().decode(MealProfile.self, from: Data(profileJSON.utf8))
        func run(_ modes: [Int: OutMode], _ current: [MealScheduleEntry]) -> [MealScheduleEntry] {
            MealRules.outSchedule(modes: modes, eaters: [3], slots: profile.slots, current: current)
        }
        // (a) día completo
        XCTAssertEqual(run([3: .full], []), [out(3, "lunch"), out(3, "dinner")])
        // (b) solo comida: la cena que estaba fuera vuelve a casa
        XCTAssertEqual(run([3: .lunch], [out(3, "lunch"), out(3, "dinner")]), [home(3, "dinner")])
        XCTAssertEqual(run([3: .lunch], []), [out(3, "lunch")])
        // (c) solo cena
        XCTAssertEqual(run([3: .dinner], [out(3, "lunch"), out(3, "dinner")]), [home(3, "lunch")])
        XCTAssertEqual(run([3: .dinner], []), [out(3, "dinner")])
        // (d) ninguno: todo lo que estaba fuera vuelve a casa
        XCTAssertEqual(run([:], [out(3, "lunch"), out(3, "dinner")]), [home(3, "lunch"), home(3, "dinner")])
        // (e) sin cambios
        XCTAssertEqual(run([3: .full], [out(3, "lunch"), out(3, "dinner")]), [])
        XCTAssertEqual(run([:], []), [])
    }

    func testOutModesReadsSchedule() throws {
        var profile = try JSONCoding.decoder().decode(MealProfile.self, from: Data(profileJSON.utf8))
        profile.schedule = [
            out(1, "lunch"), out(1, "dinner"), out(2, "lunch"), out(3, "dinner"),
            MealScheduleEntry(homeMemberId: 3, weekday: 4, slot: "breakfast", status: "out"),
        ]
        XCTAssertEqual(MealRules.outModes(profile), [1: .full, 2: .lunch, 3: .dinner])
        // día mixto: otro comensal sin `out` → ninguno
        var two = profile
        two.members.append(two.members[0])
        two.members[1].homeMemberId = 9
        XCTAssertEqual(MealRules.outModes(two), [:])
        // franja inactiva: con solo la cena activa, cena fuera = día completo
        profile.slots[0].enabled = false
        XCTAssertEqual(MealRules.outModes(profile)[1], .full)
        XCTAssertEqual(MealRules.outModes(profile)[3], .full)
        XCTAssertNil(MealRules.outModes(profile)[2])
    }

    func testMealGetIsNotCached() {
        XCTAssertFalse(ReadCache.isCacheable(APIRequest(method: .get, path: "meal/profile")))
    }
}
