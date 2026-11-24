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

    // MARK: Carga y marcado

    func testLoadGroupsBySectionInAisleOrderWithPendingFirst() async throws {
        StubURLProtocol.reset { _ in
            StubURLProtocol.Stub(json: self.listJSON(revision: 2, [
                self.item(1, "Leche", section: "lacteos", qty: 1, unit: "l"),
                self.item(2, "Zanahoria", state: "checked"),
                self.item(3, "Tomate"),
                self.item(4, "Pan", section: "panaderia", origin: "manual", qty: nil, unit: "ud"),
            ]))
        }
        let store = makeStore()
        await store.load()
        XCTAssertEqual(store.state, .loaded)
        XCTAssertEqual(store.revision, 2)
        XCTAssertEqual(store.sections.map(\.section), ["verdura", "lacteos", "panaderia"])
        XCTAssertEqual(store.sections[0].items.map(\.label), ["Tomate", "Zanahoria"], "lo pendiente primero")
        XCTAssertEqual(store.pendingCount, 3)
        XCTAssertEqual(store.checkedCount, 1)
        XCTAssertEqual(calls("/shopping").count, 1)
    }

    func testToggleMarksOptimisticallyAndSendsState() async throws {
        StubURLProtocol.reset { req in
            if req.url?.path.hasSuffix("/shopping/item/check") == true {
                return StubURLProtocol.Stub(json: self.item(1, "Tomate", state: "checked"))
            }
            return StubURLProtocol.Stub(json: self.listJSON(revision: 1, [self.item(1, "Tomate")]))
        }
        let store = makeStore()
        await store.load()
        await store.toggle(store.items[0])
        XCTAssertTrue(store.items[0].isChecked)
        let body = String(data: try XCTUnwrap(calls("/shopping/item/check").first?.capturedBody), encoding: .utf8) ?? ""
        XCTAssertEqual(body, #"{"id":1,"state":"checked"}"#)
        XCTAssertEqual(calls("/shopping/item/check").first?.httpMethod, "PATCH")
    }

    func testToggleRevertsWhenServerFails() async throws {
        StubURLProtocol.reset { req in
            if req.url?.path.hasSuffix("/shopping/item/check") == true { return StubURLProtocol.Stub(status: 500, json: "{}") }
            return StubURLProtocol.Stub(json: self.listJSON(revision: 1, [self.item(1, "Tomate")]))
        }
        let store = makeStore()
        await store.load()
        await store.toggle(store.items[0])
        XCTAssertTrue(store.items[0].isPending)
        XCTAssertNotNil(store.errorMessage)
    }

    // MARK: Aviso de cambios

    func testRevisionBumpProducesPlusMinusNotice() async throws {
        var response = listJSON(revision: 1, [item(1, "Tomate"), item(2, "Cebolla"), item(3, "Pasta", qty: 200)])
        StubURLProtocol.reset { _ in StubURLProtocol.Stub(json: response) }
        let store = makeStore()
        await store.load()
        XCTAssertNil(store.changeNotice, "la primera carga no avisa")

        response = listJSON(revision: 2, [item(1, "Tomate"), item(3, "Pasta", qty: 300), item(4, "Arroz"), item(5, "Ajo")])
        await store.load()
        XCTAssertEqual(store.changeNotice, "El menú ha cambiado la lista: +2 −1 ~1")
        store.dismissChanges()
        XCTAssertNil(store.changeNotice)

        await store.load()
        XCTAssertNil(store.changeNotice, "sin subida de revisión no hay aviso")
    }

    func testNoteSyncAfterAcceptSetsNoticeAndReview() async throws {
        StubURLProtocol.reset { _ in StubURLProtocol.Stub(json: self.listJSON(revision: 1, [self.item(1, "Tomate")])) }
        let store = makeStore()
        await store.load()
        store.noteSync(ShoppingSyncResult(added: 4, updated: 0, removed: 0))
        XCTAssertEqual(store.changeNotice, "Lista de la compra actualizada: +4")
        XCTAssertTrue(store.showsReviewBanner)
    }

    // MARK: Altas, cantidad y vaciado

    func testAddManualWithFoodSendsFoodAndClientRequestId() async throws {
        let created = #"{"id":10,"label":"Leche","food_id":5,"quantity":2,"unit":"l","section":"lacteos","origin":"manual","plan_id":null,"sources":[],"qty_overridden":false,"state":"pending"}"#
        StubURLProtocol.reset { req in
            if req.url?.path.hasSuffix("/shopping/item/create") == true { return StubURLProtocol.Stub(status: 201, json: created) }
            return StubURLProtocol.Stub(json: self.listJSON(revision: 1, []))
        }
        let store = makeStore()
        await store.load()
        let food = Food(id: 5, name: "Leche", section: "lacteos", defaultUnit: "l")
        let ok = await store.add(label: "Leche", quantity: 2, unit: "l", food: food)
        XCTAssertTrue(ok)
        XCTAssertEqual(store.items.map(\.label), ["Leche"])
        let body = try XCTUnwrap(calls("/shopping/item/create").first?.capturedBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["food_id"] as? Int, 5)
        XCTAssertEqual(json["section"] as? String, "lacteos")
        XCTAssertNotNil(UUID(uuidString: json["client_request_id"] as? String ?? ""))
        let empty = await store.add(label: "  ")
        XCTAssertFalse(empty)
    }

    func testSuggestUsesCatalogFromTwoLetters() async throws {
        StubURLProtocol.reset { _ in StubURLProtocol.Stub(json: self.listJSON(revision: 1, [])) }
        let store = makeStore(searchFoods: { query in [Food(id: 1, name: query + "ina")] })
        await store.suggest("a")
        XCTAssertTrue(store.suggestions.isEmpty)
        await store.suggest("har")
        XCTAssertEqual(store.suggestions.map(\.name), ["harina"])
    }

    func testUpdateQuantityAndClearChecked() async throws {
        StubURLProtocol.reset { req in
            let path = req.url?.path ?? ""
            if path.hasSuffix("/shopping/item/update") {
                return StubURLProtocol.Stub(json: self.item(1, "Tomate", qty: 750).replacingOccurrences(of: #""qty_overridden":false"#, with: #""qty_overridden":true"#))
            }
            if path.hasSuffix("/shopping/checked") { return StubURLProtocol.Stub(json: #"{"cleared":1}"#) }
            return StubURLProtocol.Stub(json: self.listJSON(revision: 1, [self.item(1, "Tomate"), self.item(2, "Cebolla", state: "checked")]))
        }
        let store = makeStore()
        await store.load()
        await store.updateQuantity(store.items[0], quantity: 750)
        XCTAssertEqual(store.items[0].quantity, 750)
        XCTAssertTrue(store.items[0].qtyOverridden)
        await store.clearChecked()
        XCTAssertEqual(store.items.map(\.label), ["Tomate"])
        XCTAssertEqual(calls("/shopping/checked").first?.httpMethod, "DELETE")
    }
}
