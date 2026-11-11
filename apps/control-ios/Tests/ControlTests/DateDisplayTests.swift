import XCTest
@testable import ControlKit

/// U1: fechas del contrato localizadas; texto no parseable se devuelve tal cual.
final class DateDisplayTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!
    private let es = Locale(identifier: "es_ES")

    func testContractDateIsLocalizedNotRaw() {
        let shown = DateDisplay.dateTime("2026-11-08 09:30:00", timeZone: utc, locale: es)
        XCTAssertNotEqual(shown, "2026-11-08 09:30:00")
        XCTAssertTrue(shown.contains("8"), shown)
        XCTAssertTrue(shown.contains("9:30"), shown)
    }

    func testUnparseableTextIsReturnedAsIs() {
        XCTAssertEqual(DateDisplay.dateTime("no es fecha", timeZone: utc, locale: es), "no es fecha")
        XCTAssertEqual(DateDisplay.dateTime("", timeZone: utc, locale: es), "")
    }
}
