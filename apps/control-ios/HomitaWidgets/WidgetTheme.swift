import SwiftUI
import UIKit

/// Colores de Homita para los widgets (valores de `docs/design/ios/tokens.css`, claro/oscuro).
/// La extensión no enlaza `ControlKit` (límite de memoria): solo `HomitaShared`.
enum WidgetTheme {
    static let background = dynamic(light: "#F4EEE3", dark: "#1B1713")
    static let surface = dynamic(light: "#FDFBF7", dark: "#241E19")
    static let line = dynamic(light: "#EDE5D6", dark: "#3A322A")
    static let ink = dynamic(light: "#2F4A3A", dark: "#F4ECE0")
    static let inkSoft = dynamic(light: "#6F655A", dark: "#BFB3A4")
    static let accent = dynamic(light: "#B04A27", dark: "#F09A74")
    static let now = dynamic(light: "#3F7D4E", dark: "#7FD19A")
    static let soon = dynamic(light: "#A66F00", dark: "#F5C842")

    private static func dynamic(light: String, dark: String) -> Color {
        Color(uiColor: UIColor { trait in
            UIColor(Color(hex: trait.userInterfaceStyle == .dark ? dark : light))
        })
    }
}

extension Color {
    /// `#RRGGBB`; gris si no se puede leer.
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard cleaned.count == 6, let value = UInt32(cleaned, radix: 16) else {
            self = .gray
            return
        }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

/// Rango válido para `Text(timerInterval:)`: nunca con el inicio después del final (si no, revienta).
func countdownRange(to end: Date, from now: Date = Date()) -> ClosedRange<Date> {
    min(now, end)...end
}
