import SwiftUI

/// Elige la vista de cada tarjeta por `tipo`: `confirmacion` tiene su tarjeta con botones; un tipo desconocido
/// muestra su campo `texto` si lo tiene y, si no, se omite. Nunca falla.
struct KitoCardRenderer: View {
    /// Mensaje al que pertenecen las tarjetas (con el índice identifica cada tarjeta).
    var messageId: UUID?
    let cards: [KitoCard]
    var onConfirm: (Int) -> Void = { _ in }
    var onCancel: (Int) -> Void = { _ in }
    var onAppearConfirmation: (Int) -> Void = { _ in }

    private struct Item: Identifiable {
        let id: String
        let index: Int
        let card: KitoCard
    }

    private var items: [Item] {
        cards.enumerated().map { Item(id: "\(messageId?.uuidString ?? "-")#\($0.offset)", index: $0.offset, card: $0.element) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            ForEach(items) { item in
                if let confirmation = KitoConfirmation(card: item.card) {
                    KitoConfirmationCard(
                        confirmation: confirmation,
                        onConfirm: { onConfirm(item.index) },
                        onCancel: { onCancel(item.index) },
                        onAppear: { onAppearConfirmation(item.index) }
                    )
                } else if case .string(let texto)? = item.card.datos["texto"], !texto.isEmpty {
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
