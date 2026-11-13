import SwiftUI

/// Color de calendario, lista o persona (P-06): muestras fijas y «Personalizado», que despliega el
/// selector del sistema. Mismo contrato `#RRGGBB` que el resto de la app.
struct HomitaColorField: View {
    let title: String
    @Binding var color: Color
    @State private var showCustom = false

    private var currentHex: String { color.hexString }
    private var isFixed: Bool { Palette.swatches.contains(currentHex) }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s3) {
            Text(title)
                .font(HomitaFont.inter(14, weight: .semibold, relativeTo: .footnote))
                .foregroundStyle(Palette.inkSoft)
            // Cuadrícula adaptativa: las muestras se acomodan al ancho de la pantalla (no se salen).
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: Spacing.s2)], alignment: .leading, spacing: Spacing.s2) {
                ForEach(Palette.swatches, id: \.self) { hex in
                    Button {
                        color = Color(hex: hex)
                        showCustom = false
                    } label: {
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 30, height: 30)
                            .overlay(Circle().stroke(Palette.ink, lineWidth: currentHex == hex && !showCustom ? 2 : 0).padding(-4))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Color \(hex)")
                    .accessibilityAddTraits(currentHex == hex ? .isSelected : [])
                }
            }
            Button {
                showCustom.toggle()
            } label: {
                Text("Personalizado")
                    .font(HomitaFont.inter(13, weight: .semibold, relativeTo: .footnote))
                    .foregroundStyle(Palette.accent)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            if showCustom || !isFixed {
                ColorPicker("Color personalizado", selection: $color, supportsOpacity: false)
                    .font(HomitaFont.inter(17, relativeTo: .body))
                    .foregroundStyle(Palette.ink)
            }
        }
    }
}
