import SwiftUI

/// Campo de texto multilínea de Homita (`HomitaField` es de una línea): `TextEditor` con
/// placeholder, borde como el de `HomitaField` y contador de caracteres con límite.
struct HomitaTextEditor: View {
    let placeholder: String
    @Binding var text: String
    var limit: Int = FeedbackDraft.maxLength
    var minHeight: CGFloat = 140

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            TextEditor(text: $text)
                .font(HomitaFont.inter(17, relativeTo: .body))
                .foregroundStyle(Palette.ink)
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(minHeight: minHeight)
                .background(Palette.card, in: RoundedRectangle(cornerRadius: 18))
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text(placeholder)
                            .font(HomitaFont.inter(17, relativeTo: .body))
                            .foregroundStyle(Palette.inkMuted)
                            .padding(.horizontal, 15)
                            .padding(.vertical, 18)
                            .allowsHitTesting(false)
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Palette.line, lineWidth: 1.5))
                .onChange(of: text) { _, newValue in
                    if newValue.count > limit { text = String(newValue.prefix(limit)) }
                }
                .accessibilityLabel(placeholder)
            Text("\(text.count)/\(limit)")
                .font(HomitaFont.inter(12, relativeTo: .caption))
                .foregroundStyle(Palette.inkMuted)
                .accessibilityHidden(true)
        }
    }
}
