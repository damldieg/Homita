import XCTest
@testable import ControlKit

/// Cola offline (D-024): `Ref` y `PendingOp` sobreviven a la ida y vuelta JSON en todos sus casos.
final class PendingOpTests: XCTestCase {
    private func roundTrip(_ op: PendingOp) throws -> PendingOp {
        try JSONDecoder().decode(PendingOp.self, from: JSONEncoder().encode(op))
    }

    func testEveryKindRoundTrips() throws {
        let kinds: [PendingOp.Kind] = [
            .createTask(local: -1, listRef: .remote(2), title: "Leche", personIds: [5]),
            .createTask(local: -2, listRef: .local(-3), title: "Pan", personIds: nil),
            .updateTask(ref: .remote(7), listRef: .remote(2), title: "Leche entera", personIds: []),
            .completeTask(ref: .local(-1), listRef: .remote(2), completed: true),
            .deleteTask(ref: .remote(7), listRef: .remote(2)),
            .createList(local: -3, name: "Compra", color: "#6923E2", sort: "custom", widget: true, dashboard: false),
            .updateList(ref: .remote(2), name: "Súper", color: "#112233", sort: "title", widget: false, dashboard: true),
            .deleteList(ref: .local(-3)),
            .createShoppingItem(local: -4, label: "Leche", quantity: 2, unit: "l", section: "lacteos", foodId: 12),
            .createShoppingItem(local: -5, label: nil, quantity: nil, unit: "ud", section: nil, foodId: 9, state: "checked"),
            .checkShoppingItem(ref: .remote(30)),
            .uncheckShoppingItem(ref: .local(-4)),
            .haveShoppingItem(ref: .remote(31))
        ]
        for kind in kinds {
            let op = PendingOp(createdAt: Date(timeIntervalSince1970: 1_700_000_000), homeId: "1", attempts: 2, kind: kind)
            XCTAssertEqual(try roundTrip(op), op, "\(kind)")
        }
    }

    func testRefFromIdAndResolution() {
        XCTAssertEqual(Ref(id: 7), .remote(7))
        XCTAssertEqual(Ref(id: -1), .local(-1))
        XCTAssertEqual(Ref.local(-1).resolved(with: [-1: 40]), 40)
        XCTAssertNil(Ref.local(-2).resolved(with: [-1: 40]))
        XCTAssertEqual(Ref.local(-2).displayId(with: [:]), -2)
        XCTAssertEqual(Ref.remote(9).resolved(with: [:]), 9)
    }

    func testClientRequestIdIsLowercasedUUID() {
        let id = UUID()
        let op = PendingOp(id: id, homeId: "1", kind: .deleteList(ref: .remote(1)))
        XCTAssertEqual(op.clientRequestId, id.uuidString.lowercased())
    }

    func testShoppingKindsExposeRefStateAndSubject() {
        let create = PendingOp.Kind.createShoppingItem(local: -4, label: "Leche", quantity: nil, unit: "ud", section: nil, foodId: nil)
        XCTAssertEqual(create.shoppingRef, .local(-4))
        XCTAssertEqual(create.createdLocal, .local(-4))
        XCTAssertTrue(create.isCreate)
        XCTAssertTrue(create.isShoppingOp)
        XCTAssertFalse(create.isTaskOp)
        XCTAssertNil(create.listRef)
        XCTAssertEqual(create.subject, "«Leche»")
        XCTAssertEqual(PendingOp.Kind.checkShoppingItem(ref: .remote(3)).shoppingState, "checked")
        XCTAssertEqual(PendingOp.Kind.uncheckShoppingItem(ref: .remote(3)).shoppingState, "pending")
        XCTAssertEqual(PendingOp.Kind.haveShoppingItem(ref: .remote(3)).shoppingState, "skipped")
        XCTAssertNil(create.shoppingState)
        XCTAssertFalse(PendingOp.Kind.checkShoppingItem(ref: .remote(3)).isDelete)
        XCTAssertTrue(PendingOp.Kind.checkShoppingItem(ref: .remote(3)).references(.remote(3)))
        XCTAssertNil(PendingOp.Kind.deleteList(ref: .remote(1)).shoppingRef)
    }
}
