import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Cara redonda de Urki (asset `UrkiAvatar`). Si el asset no está en la app, símbolo de huella con la paleta.
struct KitoAvatar: View {
    let size: CGFloat

    /// Asset del avatar disponible en la app (el PNG lo añade el proyecto Xcode, no este paquete).
    static var hasAvatarAsset: Bool {
        #if canImport(UIKit)
        UIImage(named: "UrkiAvatar") != nil
        #else
        false
        #endif
    }

    var body: some View {
        Group {
            if Self.hasAvatarAsset {
                Image("UrkiAvatar")
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "pawprint.fill")
                    .font(.system(size: size * 0.42))
                    .foregroundStyle(Palette.accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Palette.accentSoft)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}
