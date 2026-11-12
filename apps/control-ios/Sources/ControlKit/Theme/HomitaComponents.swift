import SwiftUI
#if canImport(ComponentsKit)
import ComponentsKit

/// Tema de ComponentsKit con la paleta Homita (B2). La librería solo existe en iOS: en el host
/// macOS (`swift test`) este archivo queda fuera por `canImport`.
enum HomitaComponents {
    static func applyTheme() {
        var theme = Theme.current
        theme.colors.background = uc(Palette.backgroundHex)
        theme.colors.secondaryBackground = uc(Palette.surfaceHex)
        theme.colors.foreground = uc(Palette.inkHex)
        theme.colors.secondaryForeground = uc(Palette.inkSoftHex)
        theme.colors.divider = uc(Palette.lineHex)
        theme.colors.primary = ComponentColor(main: uc(Palette.accentHex), contrast: uc(Palette.whiteHex))
        theme.colors.accent = ComponentColor(main: uc(Palette.soonHex), contrast: uc(Palette.inkHex))
        Theme.current = theme
    }
}
#else
enum HomitaComponents {
    static func applyTheme() {}
}
#endif

/// Botón principal de Homita: `SUButton` de ComponentsKit en iOS (con su propio estado de carga),
/// `Button` de SwiftUI en el host macOS.
struct HomitaPrimaryButton: View {
    let title: String
    var isEnabled: Bool = true
    var isLoading: Bool = false
    let action: () -> Void

    var body: some View {
        #if canImport(ComponentsKit)
        SUButton(model: model, action: action)
            .frame(maxWidth: .infinity)
        #else
        Button(action: action) {
            Text(title)
                .font(HomitaFont.inter(17, weight: .semibold, relativeTo: .body))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!isEnabled || isLoading)
        #endif
    }

    #if canImport(ComponentsKit)
    private var model: ButtonVM {
        ButtonVM {
            $0.title = title
            $0.color = ComponentColor(main: uc(Palette.accentHex), contrast: uc(Palette.whiteHex))
            $0.isFullWidth = true
            $0.size = .large
            $0.isEnabled = isEnabled && !isLoading
            $0.isLoading = isLoading
        }
    }
    #endif
}

#if canImport(ComponentsKit)
/// Color de la paleta como `UniversalColor` adaptativo (claro/oscuro).
func uc(_ hex: String) -> UniversalColor { .universal(.color(Palette.adaptive(hex))) }
#endif
