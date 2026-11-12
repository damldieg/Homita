import SwiftUI

/// Esqueleton de carga (E0-03): bloques con la misma altura que el contenido real, con un brillo
/// que se desplaza. Sustituye al texto «Cargando…». Con Reduce Motion se queda estático.
struct HomitaSkeletonBlock: View {
    var height: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: Radius.sm)
            .fill(Palette.surface2)
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
            .skeleton()
            .accessibilityHidden(true)
    }
}

/// Varias filas de esqueleton apiladas. Se lee como un único elemento «Cargando…» para VoiceOver.
struct HomitaSkeletonRows: View {
    var count: Int = 2
    var height: CGFloat = 52
    var label: String = "Cargando"

    var body: some View {
        VStack(spacing: Spacing.s3) {
            ForEach(0..<count, id: \.self) { _ in
                HomitaSkeletonBlock(height: height)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }
}

/// Brillo del esqueleton: se desplaza en bucle salvo con Reduce Motion (E0-03).
struct HomitaSkeletonModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay {
                if HomitaSkeletonLayout.shimmerEnabled(reduceMotion: reduceMotion) {
                    GeometryReader { geometry in
                        let band = geometry.size.width * 0.6
                        LinearGradient(
                            colors: [.clear, Color.white.opacity(0.35), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: band)
                        .offset(x: (geometry.size.width + band) * phase - band)
                        .onAppear {
                            withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) {
                                phase = 1
                            }
                        }
                    }
                    .allowsHitTesting(false)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
    }
}

extension View {
    /// Aplica el brillo de esqueleton (E0-03). Sin movimiento con Reduce Motion.
    func skeleton() -> some View {
        modifier(HomitaSkeletonModifier())
    }
}

/// Reglas del esqueleton que no dependen de la vista (testables).
enum HomitaSkeletonLayout {
    /// El brillo se anima salvo que el usuario pida reducir el movimiento.
    static func shimmerEnabled(reduceMotion: Bool) -> Bool {
        !reduceMotion
    }
}
