import XCTest
@testable import ControlKit

/// `PHPDateTime`: fechas `Y-m-d H:i:s` y `Y-m-d` como horas locales flotantes (parse/format en la
/// zona dada, sin conversión), incluido el día del cambio horario.
final class PHPDateTimeTests: XCTestCase {
    private let madrid = TimeZone(identifier: "Europe/Madrid")!
    private let utc = TimeZone(identifier: "UTC")!

    func testParseDateTime() throws {
        let date = try XCTUnwrap(PHPDateTime.parse("2026-11-08 09:30:00", timeZone: madrid))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = madrid
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        XCTAssertEqual(parts.year, 2026)
        XCTAssertEqual(parts.month, 11)
        XCTAssertEqual(parts.day, 8)
        XCTAssertEqual(parts.hour, 9)
        XCTAssertEqual(parts.minute, 30)
        XCTAssertEqual(parts.second, 0)
    }

    func testFormatDateTimeIsFloatingLocal() throws {
        // 2026-11-08 09:30 en Madrid = 08:30 UTC: el formato devuelve la hora local, no la UTC.
        let date = try XCTUnwrap(PHPDateTime.parse("2026-11-08 09:30:00", timeZone: madrid))
        XCTAssertEqual(PHPDateTime.format(date, timeZone: madrid), "2026-11-08 09:30:00")
        XCTAssertEqual(PHPDateTime.format(date, timeZone: utc), "2026-11-08 08:30:00")
    }

    func testRoundTrip() throws {
        for literal in ["2026-01-01 00:00:00", "2026-06-30 23:59:59", "2026-11-08 09:30:00"] {
            let date = try XCTUnwrap(PHPDateTime.parse(literal, timeZone: madrid))
            XCTAssertEqual(PHPDateTime.format(date, timeZone: madrid), literal)
        }
    }

    func testDSTSpringForwardDay() throws {
        // 2026-03-29: en Madrid las 02:00 saltan a las 03:00. Los literales vecinos son estables.
        for literal in ["2026-03-29 01:30:00", "2026-03-29 03:30:00", "2026-03-29 23:59:59"] {
            let date = try XCTUnwrap(PHPDateTime.parse(literal, timeZone: madrid))
            XCTAssertEqual(PHPDateTime.format(date, timeZone: madrid), literal)
        }
    }

    func testDSTFallBackDay() throws {
        // 2026-10-25: en Madrid las 03:00 vuelven a las 02:00 (hora repetida, primer match).
        for literal in ["2026-10-25 01:30:00", "2026-10-25 03:30:00"] {
            let date = try XCTUnwrap(PHPDateTime.parse(literal, timeZone: madrid))
            XCTAssertEqual(PHPDateTime.format(date, timeZone: madrid), literal)
        }
    }

    func testParseDay() throws {
        let date = try XCTUnwrap(PHPDateTime.parseDay("2026-11-08", timeZone: madrid))
        XCTAssertEqual(PHPDateTime.formatDay(date, timeZone: madrid), "2026-11-08")
    }

    func testInvalidLiterals() {
        XCTAssertNil(PHPDateTime.parse("2026-11-08", timeZone: madrid))
        XCTAssertNil(PHPDateTime.parse("", timeZone: madrid))
        XCTAssertNil(PHPDateTime.parseDay("8/11/2026", timeZone: madrid))
    }
}
