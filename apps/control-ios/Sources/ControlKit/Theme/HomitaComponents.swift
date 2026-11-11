import SwiftUI
#if canImport(ComponentsKit)
import ComponentsKit

/// Tema de ComponentsKit con la paleta Homita (B2). La librería solo existe en iOS: en el host
/// macOS (`swift test`) este archivo queda fuera por `canImport`.
enum HomitaComponents {
    static func applyTheme() {
        var theme = Theme.current
        theme.colors.background = uc("#F7EEE2")
        theme.colors.secondaryBackground = uc("#FFFDF9")
        theme.colors.foreground = uc("#221D18")
        theme.colors.secondaryForeground = uc("#6E6358")
        theme.colors.divider = uc("#B9AA96")
        theme.colors.primary = ComponentColor(main: uc("#C8243B"), contrast: uc("#FFFFFF"))
        theme.colors.accent = ComponentColor(main: uc("#F5A623"), contrast: uc("#221D18"))
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
                .font(HomitaFont.geist(17, weight: .semibold, relativeTo: .body))
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
            $0.color = ComponentColor(main: uc("#C8243B"), contrast: uc("#FFFFFF"))
            $0.isFullWidth = true
            $0.size = .large
            $0.isEnabled = isEnabled && !isLoading
            $0.isLoading = isLoading
        }
    }
    #endif
}

#if canImport(ComponentsKit)
/// Color fijo de la paleta Homita como `UniversalColor` de ComponentsKit.
func uc(_ hex: String) -> UniversalColor { .universal(.hex(hex)) }
#endif
