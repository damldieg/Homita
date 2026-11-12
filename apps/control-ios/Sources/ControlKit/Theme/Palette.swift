import SwiftUI

/// Tokens de color de Control iOS, con los valores de `docs/design/ios/tokens.css` (E0-01).
///
/// Cada color tiene variante clara y oscura cuando `tokens.css` la define; si no, usa el mismo
/// valor en ambos modos. Los nombres de la paleta anterior (`card`, `ink`, `warm`…) se conservan
/// como alias hasta que las vistas migren a los tokens (E0-01, T3).
enum Palette {
    // MARK: Superficies y texto

    static let background = Color.token(light: "#F4EEE3", dark: "#1B1713")
    static let backgroundSunken = Color.token(light: "#EFE7D8", dark: "#26201A")
    static let surface = Color.token(light: "#FDFBF7", dark: "#241E19")
    static let surface2 = Color.token(light: "#F8F3EA", dark: "#2C251F")
    static let line = Color.token(light: "#EDE5D6", dark: "#3A322A")
    static let ink = Color.token(light: "#1D1612", dark: "#F4ECE0")
    static let inkSoft = Color.token(light: "#6F655A", dark: "#BFB3A4")
    static let inkMuted = Color.token(light: "#8F8579", dark: "#988C7D")

    // MARK: Acción y estados

    /// Acción principal. El valor en hex se expone para APIs que no aceptan `Color` (ComponentsKit).
    static let accent = Color.token(light: accentHex, dark: "#E5485F")
    static let accentPress = Color.token(light: "#952634")
    static let accentSoft = Color.token(light: "#F4DDE0", dark: "#4A1F27")
    static let ok = Color.token(light: "#2F5E3B")
    static let okSoft = Color.token(light: "#E6F0E0", dark: "#1E3A2A")
    static let warn = Color.token(light: "#7A5800")
    static let warnSoft = Color.token(light: "#FFF4CC", dark: "#43321A")
    static let err = Color.token(light: "#B3261E")
    static let errSoft = Color.token(light: "#F9DEDC", dark: "#4A2220")
    static let info = Color.token(light: "#3B5BDB")
    static let infoSoft = Color.token(light: "#E0E7FB", dark: "#232C52")

    // MARK: Estados de rutina («Rutinas de hoy»)

    /// En curso.
    static let now = Color.token(light: "#3F7D4E")
    static let nowStrong = Color.token(light: "#2F5E3B")
    static let nowBg = Color.token(light: "#E6F0E0")
    static let nowTrack = Color.token(light: "#C8DDC0")
    /// Aviso (≤ 60 min).
    static let soon = Color.token(light: "#D9A400")
    static let soonStrong = Color.token(light: "#5C4300")
    static let soonText = Color.token(light: "#7A5800")
    static let soonBg = Color.token(light: "#FFF4CC")
    static let soonFill = Color.token(light: "#A66F00")
    static let soonTrack = Color.token(light: "#F6E3A1")
    static let soonTile = Color.token(light: "#F5C842")
    /// Aún no empieza.
    static let farBg = Color.token(light: "#F8F3EA")

    // MARK: Personas (colores de referencia; los reales llegan del servidor)

    static let person1 = Color.token(light: "#6D28D9")
    static let person2 = Color.token(light: "#0E9F6E")
    static let person3 = Color.token(light: "#F59E0B")
    static let person4 = Color.token(light: "#E11D48")
    static let person5 = Color.token(light: "#0284C7")

    // MARK: Hex para APIs que no aceptan `Color`

    static let accentHex = "#B5313F"
    /// Color de completado (casilla de tarea). Token `--now`.
    static let onlineHex = "#3F7D4E"
    /// Color por defecto de calendarios, listas y rutinas sin color del servidor.
    static let fallbackItem = "#6923E2"
    static let inkHex = "#1D1612"
    static let inkSoftHex = "#6F655A"
    static let inkMutedHex = "#8F8579"
    static let backgroundHex = "#F4EEE3"
    static let surfaceHex = "#FDFBF7"
    static let lineHex = "#EDE5D6"
    static let okHex = "#2F5E3B"
    /// Ámbar del diseño (`--soon`), para enlaces de aviso y pendientes.
    static let soonHex = "#D9A400"
    /// Contraste sobre acento y sobre tintes oscuros.
    static let whiteHex = "#FFFFFF"

    // MARK: Alias de la paleta anterior (vistas actuales)

    static let card = surface
    static let cardBorder = line
    static let rail = backgroundSunken
    static let warm = soon
    static let online = now
}

/// Escala de espaciado de 4 (E0-01). Valores de `tokens.css`.
enum Spacing {
    static let s1: CGFloat = 4
    static let s2: CGFloat = 8
    static let s3: CGFloat = 12
    static let s4: CGFloat = 16
    static let s5: CGFloat = 20
    static let s6: CGFloat = 24
    static let s8: CGFloat = 32
    /// Margen lateral de pantalla.
    static let gutter: CGFloat = 16
    /// Separación entre tarjetas.
    static let cardGap: CGFloat = 12
}

/// Radios de esquina de E0-01. Valores de `tokens.css`.
enum Radius {
    static let sm: CGFloat = 10
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let pill: CGFloat = 999
}

extension Color {
    /// Color de token con variante de modo oscuro. Sin `dark`, el mismo valor en ambos modos.
    /// En macOS (solo para `swift test`) usa siempre la variante clara.
    static func token(light: String, dark: String? = nil) -> Color {
        #if os(iOS)
        guard let dark else { return Color(hex: light) }
        return Color(uiColor: UIColor { trait in
            UIColor(Color(hex: trait.userInterfaceStyle == .dark ? dark : light))
        })
        #else
        return Color(hex: light)
        #endif
    }
}
