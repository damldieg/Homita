import SwiftUI

/// Elige la vista de cada tarjeta por `tipo`. Aún no hay tipos concretos: uno desconocido muestra su
/// campo `texto` si lo tiene y, si no, se omite. Nunca falla.
struct KitoCardRenderer: View {
    let cards: [KitoCard]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            ForEach(Array(cards.enumerated()), id: \.offset) { _, card in
                if case .string(let texto)? = card.datos["texto"], !texto.isEmpty {
                    Text(texto)
                        .font(HomitaFont.inter(14))
                        .foregroundStyle(Palette.ink)
                        .padding(Spacing.s3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: Radius.md).fill(Palette.surface))
                        .overlay(RoundedRectangle(cornerRadius: Radius.md).stroke(Palette.line, lineWidth: 1))
                }
            }
        }
    }
}
