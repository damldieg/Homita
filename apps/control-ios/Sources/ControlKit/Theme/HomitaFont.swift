import SwiftUI
import CoreText

/// Tipografía Homita: Inter para el texto (E0-01, según el diseño) y GeistMono para números y horas.
/// Las fuentes se registran desde el bundle del paquete (`Resources/Fonts`). Si el registro falla,
/// SwiftUI usa la fuente del sistema sin romper nada.
enum HomitaFont {
    /// Registra una vez las fuentes del paquete en el proceso.
    static let registered: Bool = {
        let names = [
            "geist_mono_medium",
            "Inter-Regular", "Inter-Medium", "Inter-SemiBold", "Inter-Bold",
        ]
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

    /// Nombres PostScript de Inter por peso, como los exporta el archivo `.ttf`.
    static func interPostScriptName(for weight: Font.Weight) -> String {
        switch weight {
        case .medium: return "Inter-Medium"
        case .semibold: return "Inter-SemiBold"
        case .bold, .heavy, .black: return "Inter-Bold"
        default: return "Inter-Regular"
        }
    }

    /// Fuente Inter (tipografía del diseño, E0-01) con escalado de Dynamic Type.
    static func inter(_ size: CGFloat, weight: Font.Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        _ = registered
        return .custom(interPostScriptName(for: weight), size: size, relativeTo: style)
    }

    /// Números y horas en monoespaciada (GeistMono; el diseño no define mono).
    static func mono(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        _ = registered
        return .custom("GeistMono-Medium", size: size, relativeTo: style)
    }
}
