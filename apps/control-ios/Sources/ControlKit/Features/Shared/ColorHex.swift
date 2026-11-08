import SwiftUI

/// Color `#RRGGBB` (formato del contrato) ↔ `Color` de SwiftUI.
extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    /// `#RRGGBB` del color actual (espacio sRGB).
    var hexString: String {
        let components = rgbComponents
        return String(
            format: "#%02X%02X%02X",
            Int((components.red * 255).rounded()),
            Int((components.green * 255).rounded()),
            Int((components.blue * 255).rounded())
        )
    }

    private var rgbComponents: (red: Double, green: Double, blue: Double) {
        #if os(iOS)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        UIColor(self).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return (Double(red), Double(green), Double(blue))
        #elseif os(macOS)
        let converted = NSColor(self).usingColorSpace(.sRGB) ?? .black
        return (Double(converted.redComponent), Double(converted.greenComponent), Double(converted.blueComponent))
        #else
        return (0, 0, 0)
        #endif
    }
}
