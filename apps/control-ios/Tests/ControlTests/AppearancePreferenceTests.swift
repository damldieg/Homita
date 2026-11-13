import XCTest
@testable import ControlKit

/// Preferencia de apariencia (Ajustes): sistema, claro u oscuro.
final class AppearancePreferenceTests: XCTestCase {
    func testSystemFollowsDeviceMode() {
        XCTAssertTrue(AppearancePreference.system.resolvedIsDark(systemDark: true))
        XCTAssertFalse(AppearancePreference.system.resolvedIsDark(systemDark: false))
        XCTAssertNil(AppearancePreference.system.colorScheme)
    }

    func testExplicitChoiceIgnoresDeviceMode() {
        XCTAssertFalse(AppearancePreference.light.resolvedIsDark(systemDark: true))
        XCTAssertTrue(AppearancePreference.dark.resolvedIsDark(systemDark: false))
    }
}
