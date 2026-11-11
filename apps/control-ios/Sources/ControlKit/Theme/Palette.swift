import SwiftUI

/// Paleta Homita, la misma del dashboard (`apps/dashboard/.../ui/theme/Theme.kt`): crema cálido,
/// tarjetas casi blancas y tinta café. Los colores de calendarios, listas y personas vienen del
/// servidor; aquí solo van los neutros y el acento de marca (B2, sustituye `#6923E2`).
enum Palette {
    static let background = Color(hex: "#F7EEE2")
    static let rail = Color(hex: "#F0E3D2")
    static let card = Color(hex: "#FFFDF9")
    static let cardBorder = Color(hex: "#EFE2D0")
    static let line = Color(hex: "#EADBC6")
    static let ink = Color(hex: "#221D18")
    static let inkSoft = Color(hex: "#6E6358")
    static let inkMuted = Color(hex: "#A6998A")
    /// Acento de marca: títulos destacados y controles activos (como «Hoy» en el dashboard).
    static let accent = Color(hex: "#C8243B")
    static let warm = Color(hex: "#F5A623")
    static let online = Color(hex: "#3BA55C")
    static let accentHex = "#C8243B"
    static let onlineHex = "#3BA55C"
    /// Color por defecto de calendarios, listas y rutinas sin color del servidor.
    static let fallbackItem = "#6923E2"
}
