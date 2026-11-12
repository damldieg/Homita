import XCTest
@testable import ControlKit

/// `EventCountdown`: formato y límite de 120 min, como el dashboard Android.
final class EventCountdownTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000_000)

    private func label(secondsAhead: TimeInterval) -> String? {
        EventCountdown.label(from: now, to: now.addingTimeInterval(secondsAhead))
    }

    func testMinutes() { XCTAssertEqual(label(secondsAhead: 25 * 60), "en 25 min") }
    func testExactHour() { XCTAssertEqual(label(secondsAhead: 60 * 60), "en 1 h") }
    func testHourAndMinutes() { XCTAssertEqual(label(secondsAhead: 70 * 60), "en 1 h 10 min") }
    func testNow() { XCTAssertEqual(label(secondsAhead: 0), "ahora") }
    func testUnderOneMinuteIsNow() { XCTAssertEqual(label(secondsAhead: 59), "ahora") }
    func testPastIsNil() { XCTAssertNil(label(secondsAhead: -5 * 60)) }
    func testOverLimitIsNil() { XCTAssertNil(label(secondsAhead: 121 * 60)) }
    func testLimitIncluded() { XCTAssertEqual(label(secondsAhead: 120 * 60), "en 2 h") }

    func testDateAtParsing() {
        let start = now.addingTimeInterval(25 * 60)
        XCTAssertEqual(EventCountdown.label(dateAt: PHPDateTime.format(start), now: now), "en 25 min")
        XCTAssertNil(EventCountdown.label(dateAt: "basura", now: now))
    }
}
