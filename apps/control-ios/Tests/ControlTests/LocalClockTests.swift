import XCTest
@testable import ControlKit

/// `LocalClock`: los filtros del contrato son epochs de 10 dígitos con la hora local "como si
/// fuese UTC" (epoch + offset de zona), como Android.
final class LocalClockTests: XCTestCase {
    private let madrid = TimeZone(identifier: "Europe/Madrid")!
    private let utc = TimeZone(identifier: "UTC")!

    /// 2001-09-09T01:46:40Z (epoch 1000000000); en Madrid (CEST, +2h) son las 03:46:40.
    private let instant = Date(timeIntervalSince1970: 1_000_000_000)

    func testLocalNowEpochAddsOffset() {
        let clock = LocalClock(now: instant, timeZone: madrid)
        XCTAssertEqual(clock.localNowEpoch, "1000007200")
    }

    func testLocalNowEpochUTC() {
        let clock = LocalClock(now: instant, timeZone: utc)
        XCTAssertEqual(clock.localNowEpoch, "1000000000")
    }

    func testEpochIsTenDigitsWithoutMillis() {
        let clock = LocalClock(now: instant, timeZone: madrid)
        XCTAssertEqual(clock.localNowEpoch.count, 10)
        XCTAssertFalse(clock.localNowEpoch.contains("."))
    }

    func testMonthStartEpochUTC() {
        // 2001-09-01T00:00:00Z = epoch 999302400.
        let clock = LocalClock(now: instant, timeZone: utc)
        XCTAssertEqual(clock.monthStartEpoch, "999302400")
    }

    func testMonthStartEpochLocal() {
        // 2001-09-01T00:00:00+02:00: el local-as-epoch es también 999302400.
        let clock = LocalClock(now: instant, timeZone: madrid)
        XCTAssertEqual(clock.monthStartEpoch, "999302400")
    }

    func testStaticEpochString() {
        XCTAssertEqual(LocalClock.epochString(for: instant, timeZone: utc), "1000000000")
        XCTAssertEqual(LocalClock.epochString(for: instant, timeZone: madrid), "1000007200")
    }
}
