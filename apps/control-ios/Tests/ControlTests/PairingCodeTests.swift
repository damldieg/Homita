import XCTest
@testable import ControlKit

/// Código de vinculación leído de texto o de QR (dashboard-vinculacion-qr).
final class PairingCodeTests: XCTestCase {
    func testAcceptsSixDigitsWithSurroundingSpaces() {
        XCTAssertEqual(PairingCode.parse("584965"), "584965")
        XCTAssertEqual(PairingCode.parse(" 584965\n"), "584965")
    }

    func testRejectsAnythingThatIsNotExactlySixDigits() {
        XCTAssertNil(PairingCode.parse("58496"))
        XCTAssertNil(PairingCode.parse("5849655"))
        XCTAssertNil(PairingCode.parse("584 965"))
        XCTAssertNil(PairingCode.parse("https://homita.example/584965"))
        XCTAssertNil(PairingCode.parse("58496a"))
        XCTAssertNil(PairingCode.parse(""))
    }
}
