import XCTest
import CoreText
import SwiftUI
@testable import ControlKit

/// Inter (E0-01): los cuatro pesos del diseño están en el bundle y se resuelven por su nombre
/// PostScript. Si no se registran, CoreText cae a la fuente del sistema y el nombre no coincide.
final class HomitaFontTests: XCTestCase {
    func testInterWeightsAreRegistered() {
        XCTAssertTrue(HomitaFont.registered)
        let expected: [(Font.Weight, String)] = [
            (.regular, "Inter-Regular"),
            (.medium, "Inter-Medium"),
            (.semibold, "Inter-SemiBold"),
            (.bold, "Inter-Bold"),
        ]
        for (weight, name) in expected {
            XCTAssertEqual(HomitaFont.interPostScriptName(for: weight), name)
            let font = CTFontCreateWithName(name as CFString, 17, nil)
            XCTAssertEqual(CTFontCopyPostScriptName(font) as String, name, "No resuelve \(name)")
        }
    }

    func testInterFallsBackToRegularForLightWeights() {
        XCTAssertEqual(HomitaFont.interPostScriptName(for: .light), "Inter-Regular")
        XCTAssertEqual(HomitaFont.interPostScriptName(for: .ultraLight), "Inter-Regular")
    }
}
