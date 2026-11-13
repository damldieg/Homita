import SwiftUI

/// Colores de la marca nueva (ver brand/BRAND.md). La paleta de la interfaz (`Palette`) no cambia.
enum Brand {
    static let sage = Color(hex: "#4F7A63")
    static let forest = Color(hex: "#2F4A3A")
    static let terra = Color(hex: "#D9663B")
    static let mustard = Color(hex: "#E9B44C")
    static let cream = Color(hex: "#F4EFE6")
    /// Mismo crema que `Palette.background` y que la pantalla de arranque (LaunchBackground).
    static let launch = Color(hex: "#F7EEE2")
}

/// Trazos de la «h de hogar» sobre la cuadrícula 120×120 de brand/tools/build_masters.py.
struct HomitaMarkShape: Shape {
    enum Part { case stem, roof }
    var part: Part

    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 120
        let ox = rect.midX - 60 * s, oy = rect.midY - 60 * s
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + x * s, y: oy + y * s) }
        var path = Path()
        switch part {
        case .stem:
            path.move(to: p(36, 24)); path.addLine(to: p(36, 96))
        case .roof:
            path.move(to: p(36, 62)); path.addLine(to: p(60, 42)); path.addLine(to: p(84, 62)); path.addLine(to: p(84, 96))
        }
        return path
    }
}

/// La marca animable: `stem` y `roof` (0…1) dibujan los trazos, `dot` escala la luz y `glow` lanza un halo.
struct HomitaMark: View {
    var stem: CGFloat = 1
    var roof: CGFloat = 1
    var dot: CGFloat = 1
    var glow: CGFloat = 0
    var stroke: Color = Brand.cream
    var light: Color = Brand.mustard

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height) / 120
            let style = StrokeStyle(lineWidth: 12 * s, lineCap: .round, lineJoin: .round)
            let dotCenter = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2 + 18 * s)
            ZStack {
                // trim(0) con extremo redondo dejaría un punto: se oculta hasta que empieza a dibujarse.
                HomitaMarkShape(part: .stem).trim(from: 0, to: stem).stroke(stroke, style: style)
                    .opacity(stem > 0.001 ? 1 : 0)
                HomitaMarkShape(part: .roof).trim(from: 0, to: roof).stroke(stroke, style: style)
                    .opacity(roof > 0.001 ? 1 : 0)
                Circle().fill(light.opacity(0.5))
                    .frame(width: 14 * s, height: 14 * s)
                    .scaleEffect(1 + glow * 3.5)
                    .opacity(glow > 0 ? 1 - glow : 0)
                    .position(dotCenter)
                Circle().fill(light)
                    .frame(width: 14 * s, height: 14 * s)
                    .scaleEffect(dot)
                    .position(dotCenter)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}
