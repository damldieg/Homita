import SwiftUI

/// Botón flotante de Kito: la cara de Urki (asset `UrkiAvatar`). Si el asset no está en la app, muestra
/// un símbolo de huella para que la pantalla no quede vacía.
struct KitoButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            KitoAvatar(size: 56)
                .background(Circle().fill(Palette.surface))
                .shadow(color: .black.opacity(0.18), radius: 6, x: 0, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Abrir a Kito")
        .accessibilityHint("Chat con el asistente de Homita")
    }
}
