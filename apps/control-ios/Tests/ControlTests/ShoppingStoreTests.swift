import XCTest
@testable import ControlKit

final class ShoppingStoreTests: XCTestCase {
    private func item(_ id: Int, _ label: String, section: String = "verdura", state: String = "pending",
                      origin: String = "menu", qty: Double? = 500, unit: String = "g", sources: String = "[]") -> String {
        """
        {"id":\(id),"label":"\(label)","food_id":null,"quantity":\(qty.map { String($0) } ?? "null"),"unit":"\(unit)",
         "section":"\(section)","origin":"\(origin)","plan_id":9,"sources":\(sources),"qty_overridden":false,
         "state":"\(state)"}
        """
    }

    private func listJSON(revision: Int, _ items: [String]) -> String {
        "{\"revision\":\(revision),\"items\":[\(items.joined(separator: ","))]}"
    }

    private func makeStore(searchFoods: @escaping (String) async throws -> [Food] = { _ in [] }) -> ShoppingStore {
        let client = APIClient(baseURL: URL(string: "https://test.supabase.co/functions/v1/api")!,
                               session: StubURLProtocol.session(), tokenProvider: { "tok" }, homeIdProvider: { "7" },
                               readCache: ReadCache(directory: FileManager.default.temporaryDirectory
                                   .appendingPathComponent("readcache-\(UUID().uuidString)")))
        let defaults = UserDefaults(suiteName: "shopping-tests-\(UUID().uuidString)")!
        return ShoppingStore(repo: ShoppingRepository(client: client), searchFoods: searchFoods,
                             defaults: defaults, activeHomeId: { "7" })
    }

    private func calls(_ suffix: String) -> [URLRequest] {
        StubURLProtocol.requests.filter { $0.url?.path.hasSuffix(suffix) == true }
    }

    // MARK: Revisión

    func testReviewBannerAppearsAfterGenerationAndClearsOnFinish() async throws {
        StubURLProtocol.reset { _ in
            StubURLProtocol.Stub(json: self.listJSON(revision: 1, [self.item(1, "Tomate"), self.item(2, "Pilas", origin: "manual")]))
        }
        let store = makeStore()
        await store.load()
        XCTAssertFalse(store.showsReviewBanner)

        store.markGenerated(ShoppingSyncResult(added: 0, updated: 2, removed: 0))
        XCTAssertFalse(store.showsReviewBanner, "sin artículos nuevos no hay nada que revisar")

        store.markGenerated(ShoppingSyncResult(added: 1, updated: 0, removed: 0))
        XCTAssertTrue(store.showsReviewBanner)
        XCTAssertEqual(store.reviewItems.map(\.label), ["Tomate"], "solo lo que viene del menú")

        store.startReview()
        XCTAssertTrue(store.isReviewing)
        XCTAssertFalse(store.showsReviewBanner)

        store.finishReview()
        XCTAssertFalse(store.isReviewing)
        XCTAssertFalse(store.reviewPending)
        XCTAssertFalse(store.showsReviewBanner)
    }

    func testReviewHaveItMarksSkippedAndUndoes() async throws {
        var stateNow = "pending"
        StubURLProtocol.reset { req in
            let path = req.url?.path ?? ""
            if path.hasSuffix("/shopping/item/check") {
                stateNow = stateNow == "pending" ? "skipped" : "pending"
                return StubURLProtocol.Stub(json: self.item(1, "Tomate", state: stateNow))
            }
            return StubURLProtocol.Stub(json: self.listJSON(revision: 1, [self.item(1, "Tomate")]))
        }
        let store = makeStore()
        await store.load()
        await store.haveIt(store.items[0])
        XCTAssertTrue(store.items[0].isSkipped)
        XCTAssertEqual(store.reviewItems.count, 1, "sigue visible en la revisión para poder deshacer")
        await store.haveIt(store.items[0])
        XCTAssertTrue(store.items[0].isPending)
        XCTAssertEqual(calls("/shopping/item/check").count, 2)
    }
}
