import XCTest
import HomitaShared
@testable import ControlKit

final class SnapshotMealsTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!
    private func date(_ text: String) -> Date { PHPDateTime.parse(text, timeZone: utc)! }

    private func meals() -> HomitaSnapshot.Meals {
        .init(date: "2026-11-09", timezone: "UTC", hasPlan: true, items: [
            .init(slot: "breakfast", time: "08:00", title: "Tostadas"),
            .init(slot: "lunch", time: "14:00", title: "Lentejas"),
            .init(slot: "dinner", time: "21:00", title: "Tortilla"),
        ])
    }

    func testOldSnapshotWithoutMealsDecodes() throws {
        let json = """
        {"generatedAt":"2026-11-09T07:00:00Z","dayStart":"2026-11-09T00:00:00Z","signedIn":true,
         "routines":[],"events":[],"pendingTaskCount":0,"tasks":[]}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snap = try decoder.decode(HomitaSnapshot.self, from: Data(json.utf8))
        XCTAssertNil(snap.meals)
        XCTAssertTrue(snap.signedIn)
    }

    func testMealsRoundTrip() throws {
        let snap = HomitaSnapshot(
            generatedAt: date("2026-11-09 07:00:00"), dayStart: date("2026-11-09 00:00:00"), meals: meals())
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let back = try decoder.decode(HomitaSnapshot.self, from: try encoder.encode(snap))
        XCTAssertEqual(back, snap)
    }

    func testCurrentSlotAndBoundaries() {
        let m = meals()
        XCTAssertEqual(m.currentIndex(at: date("2026-11-09 07:00:00")), 0)
        XCTAssertEqual(m.currentIndex(at: date("2026-11-09 08:00:00")), 0)
        XCTAssertEqual(m.currentIndex(at: date("2026-11-09 09:00:00")), 1)
        XCTAssertNil(m.currentIndex(at: date("2026-11-09 22:00:00")))
        XCTAssertEqual(m.boundaries(after: date("2026-11-09 09:00:00")),
                       [date("2026-11-09 14:00:00"), date("2026-11-09 21:00:00")])
    }

    func testStaleDayAndNoPlanAreHidden() {
        XCTAssertEqual(meals().visibleItems(at: date("2026-11-10 08:00:00")), [])
        let none = HomitaSnapshot.Meals(date: "2026-11-09", timezone: "UTC", hasPlan: false, items: meals().items)
        XCTAssertEqual(none.visibleItems(at: date("2026-11-09 08:00:00")), [])
    }
}
