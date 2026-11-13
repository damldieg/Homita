import SwiftUI

/// Escrituras sin conexión (E0-06, punto 5): el control se atenúa y no responde mientras no haya
/// red. Con `reason`, debajo aparece la explicación del wireframe («No se puede guardar ahora.»);
/// sin ella, el banner global de `RootView` ya da el motivo. Para VoiceOver el control lo repite
/// como pista.
struct HomitaRequiresNetwork: ViewModifier {
    var reason: String?

    func body(content: Content) -> some View {
        let offline = DataFreshness.shared.isOffline
        VStack(alignment: .leading, spacing: Spacing.s2) {
            content
                .disabled(offline)
                .opacity(offline ? 0.45 : 1)
                .accessibilityHint(offline ? "No disponible sin conexión" : "")
            if offline, let reason {
                Text(reason)
                    .font(HomitaFont.inter(13, relativeTo: .footnote))
                    .foregroundStyle(Palette.inkSoft)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

extension View {
    /// Atenúa y desactiva el control cuando no hay red. Úsalo en botones que escriben en el servidor.
    /// `reason` añade una línea explicativa bajo el control mientras no hay conexión.
    func homitaRequiresNetwork(reason: String? = nil) -> some View {
        modifier(HomitaRequiresNetwork(reason: reason))
    }
}
