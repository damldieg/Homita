import SwiftUI
import CoreText

/// Tipografía Homita: Geist y GeistMono del dashboard, registradas desde el bundle del paquete
/// (`Resources/Fonts`). Si el registro falla, SwiftUI usa la fuente del sistema sin romper nada.
enum HomitaFont {
    /// Registra una vez las fuentes del paquete en el proceso.
    static let registered: Bool = {
        let names = ["geist_regular", "geist_light", "geist_medium", "geist_semibold", "geist_bold", "geist_mono_medium"]
        var ok = true
        for name in names {
            guard let url = Bundle.module.url(forResource: name, withExtension: "ttf") else {
                ok = false
                continue
            }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        return ok
    }()

    /// Fuente Geist con escalado de Dynamic Type (`relativeTo`), como el resto de la app.
    static func geist(_ size: CGFloat, weight: Font.Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        _ = registered
        return .custom(postScriptName(for: weight), size: size, relativeTo: style)
    }

    /// Números y horas en monoespaciada (como el reloj del dashboard).
    static func mono(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        _ = registered
        return .custom("GeistMono-Medium", size: size, relativeTo: style)
    }

    private static func postScriptName(for weight: Font.Weight) -> String {
        switch weight {
        case .light, .ultraLight, .thin: return "Geist-Light"
        case .medium: return "Geist-Medium"
        case .semibold: return "Geist-SemiBold"
        case .bold, .heavy, .black: return "Geist-Bold"
        default: return "Geist-Regular"
        }
    }
}
