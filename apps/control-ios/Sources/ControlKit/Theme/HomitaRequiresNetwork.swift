import SwiftUI

/// Escrituras sin conexión (E0-06, punto 5): el control se atenúa y no responde mientras no haya
/// red. El banner global de `RootView` ya explica el motivo («Sin conexión.»); para VoiceOver el
/// control lo repite como pista.
struct HomitaRequiresNetwork: ViewModifier {
    func body(content: Content) -> some View {
        let offline = DataFreshness.shared.isOffline
        content
            .disabled(offline)
            .opacity(offline ? 0.45 : 1)
            .accessibilityHint(offline ? "No disponible sin conexión" : "")
    }
}

extension View {
    /// Atenúa y desactiva el control cuando no hay red. Úsalo en botones que escriben en el servidor.
    func homitaRequiresNetwork() -> some View {
        modifier(HomitaRequiresNetwork())
    }
}
