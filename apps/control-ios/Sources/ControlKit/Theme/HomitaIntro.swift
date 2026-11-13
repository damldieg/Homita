import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Animaciones de la marca sobre la app. Se muestran como capa encima del contenido y se retiran solas.
///  - `.first`: arranque en frío sin sesión. Aparece el icono, se dibuja la h, se enciende la luz y sube el nombre (~2,4 s).
///  - `.login`: justo tras iniciar sesión. Fondo salvia, la h se dibuja, la luz se enciende y se abre como círculo
///    que descubre la app (~1,8 s).
///  - `.returning`: arranque en frío con sesión ya iniciada. Versión corta que tapa la carga inicial (~1,2 s).
/// Con «Reducir movimiento» solo hay fundidos, sin dibujo ni círculo.
struct HomitaIntro: View {
    enum Style { case first, login, returning }

    let style: Style
    let onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var layer: Double = 1        // opacidad de toda la capa
    @State private var tile: Double = 0         // icono (cuadrado salvia) 0…1
    @State private var stem: CGFloat = 0
    @State private var roof: CGFloat = 0
    @State private var dot: CGFloat = 0
    @State private var glow: CGFloat = 0
    @State private var word: Double = 0
    @State private var bg: Double = 0           // fondo salvia del login
    @State private var reveal: CGFloat = 0      // círculo que descubre la app (login)

    var body: some View {
        GeometryReader { geo in
            ZStack {
                switch style {
                case .first, .returning:
                    Palette.background
                    VStack(spacing: 24) {
                        iconTile(size: style == .first ? 132 : 112)
                        if style == .first {
                            Image("HomitaWordmark", bundle: .main)
                                .resizable().scaledToFit()
                                .frame(height: 44)
                                .opacity(word)
                                .offset(y: (1 - word) * 12)
                        }
                    }
                case .login:
                    Brand.sage.opacity(bg)
                    HomitaMark(stem: stem, roof: roof, dot: dot, glow: glow)
                        .frame(width: 120, height: 120)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
            .mask {
                // Login: el mask deja un agujero circular que crece desde la luz y descubre la app.
                Rectangle()
                    .overlay {
                        Circle()
                            .frame(width: reveal * hypot(geo.size.width, geo.size.height) * 2,
                                   height: reveal * hypot(geo.size.width, geo.size.height) * 2)
                            .position(x: geo.size.width / 2, y: geo.size.height / 2 + 18)
                            .blendMode(.destinationOut)
                    }
                    .compositingGroup()
                    .ignoresSafeArea()
            }
        }
        .opacity(layer)
        .allowsHitTesting(reveal == 0)
        .accessibilityHidden(true)
        .task { await run() }
    }

    private func iconTile(size: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 27 / 120, style: .continuous).fill(Brand.sage)
            HomitaMark(stem: stem, roof: roof, dot: dot, glow: glow)
                .frame(width: size, height: size)
        }
        .frame(width: size, height: size)
        .scaleEffect(0.88 + 0.12 * tile)
        .opacity(tile)
    }

    // MARK: Guion

    private func wait(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    private func run() async {
        if reduceMotion { await runReduced(); onFinish(); return }
        switch style {
        case .first:
            withAnimation(.easeOut(duration: 0.35)) { tile = 1 }
            await wait(0.3)
            withAnimation(.easeOut(duration: 0.4)) { stem = 1 }
            await wait(0.35)
            withAnimation(.easeInOut(duration: 0.45)) { roof = 1 }
            await wait(0.45)
            lightOn(haptic: false)
            await wait(0.3)
            withAnimation(.easeOut(duration: 0.45)) { word = 1 }
            await wait(0.95)
            withAnimation(.easeIn(duration: 0.35)) { layer = 0 }
            await wait(0.35)
        case .returning:
            withAnimation(.easeOut(duration: 0.2)) { tile = 1 }
            await wait(0.1)
            withAnimation(.easeOut(duration: 0.3)) { stem = 1; roof = 1 }
            await wait(0.3)
            lightOn(haptic: false)
            await wait(0.5)
            withAnimation(.easeIn(duration: 0.3)) { layer = 0 }
            await wait(0.3)
        case .login:
            withAnimation(.easeOut(duration: 0.25)) { bg = 1 }
            await wait(0.1)
            withAnimation(.easeOut(duration: 0.3)) { stem = 1 }
            await wait(0.2)
            withAnimation(.easeInOut(duration: 0.35)) { roof = 1 }
            await wait(0.4)
            lightOn(haptic: true)
            await wait(0.45)
            withAnimation(.easeInOut(duration: 0.7)) { reveal = 1 }
            await wait(0.7)
        }
        onFinish()
    }

    private func lightOn(haptic: Bool) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) { dot = 1 }
        withAnimation(.easeOut(duration: 0.7)) { glow = 1 }
        #if canImport(UIKit) && !os(macOS)
        if haptic { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
        #endif
    }

    private func runReduced() async {
        stem = 1; roof = 1; dot = 1
        withAnimation(.easeOut(duration: 0.25)) { tile = 1; bg = 1; word = 1 }
        await wait(style == .first ? 1.0 : 0.5)
        withAnimation(.easeIn(duration: 0.3)) { layer = 0 }
        await wait(0.3)
    }
}
