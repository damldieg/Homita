import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Botón flotante de Kito: la cara de Urki (asset `UrkiAvatar`). Si el asset no está en la app, muestra
/// un símbolo de huella para que la pantalla no quede vacía.
struct KitoButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            avatar
                .frame(width: 56, height: 56)
                .clipShape(Circle())
                .background(Circle().fill(.background))
                .shadow(color: .black.opacity(0.18), radius: 6, x: 0, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Abrir a Kito")
        .accessibilityHint("Chat con el asistente de Homita")
    }

    /// Asset del avatar disponible en la app (el PNG lo añade el proyecto Xcode, no este paquete).
    static var hasAvatarAsset: Bool {
        #if canImport(UIKit)
        UIImage(named: "UrkiAvatar") != nil
        #else
        false
        #endif
    }

    @ViewBuilder
    private var avatar: some View {
        if Self.hasAvatarAsset {
            Image("UrkiAvatar")
                .resizable()
                .scaledToFill()
        } else {
            Image(systemName: "pawprint.fill")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.accentColor.opacity(0.15))
        }
    }
}
