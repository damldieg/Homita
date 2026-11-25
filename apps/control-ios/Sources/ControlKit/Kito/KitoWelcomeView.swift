import SwiftUI

/// Bienvenida del chat vacío: avatar grande, saludo, qué sabe hacer y sugerencias que se envían al tocar.
struct KitoWelcomeView: View {
    let userName: String?
    var now: Date = Date()
    let onSuggestion: (String) -> Void

    var body: some View {
        VStack(spacing: Spacing.s4) {
            KitoAvatar(size: 96)
            VStack(spacing: Spacing.s1) {
                Text(KitoGreeting.salutation(date: now))
                    .font(HomitaFont.inter(14, weight: .medium, relativeTo: .subheadline))
                    .foregroundStyle(Palette.inkSoft)
                Text(KitoGreeting.text(name: userName))
                    .font(HomitaFont.inter(22, weight: .bold, relativeTo: .title2))
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.center)
            }
            .accessibilityElement(children: .combine)
            Text(KitoGreeting.capabilities)
                .font(HomitaFont.inter(15))
                .foregroundStyle(Palette.inkSoft)
                .multilineTextAlignment(.center)
            KitoFlowLayout(spacing: Spacing.s2) {
                ForEach(KitoSuggestions.all, id: \.self) { suggestion in
                    HomitaChipButton(title: suggestion) { onSuggestion(suggestion) }
                        .accessibilityLabel(suggestion)
                        .accessibilityHint("Se lo pregunta a Kito")
                }
            }
        }
        .padding(.top, Spacing.s8)
        .padding(.horizontal, Spacing.s2)
        .frame(maxWidth: .infinity)
    }
}

/// Flujo envolvente centrado: los elementos van en filas y saltan de línea al llenarse.
struct KitoFlowLayout: Layout {
    var spacing: CGFloat = 8

    private func rows(_ subviews: Subviews, width: CGFloat) -> [[Int]] {
        var rows: [[Int]] = [[]]
        var x: CGFloat = 0
        for (i, sub) in subviews.enumerated() {
            let w = sub.sizeThatFits(.unspecified).width
            if x > 0, x + w > width { rows.append([]); x = 0 }
            rows[rows.count - 1].append(i)
            x += w + spacing
        }
        return rows
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        var height: CGFloat = 0
        for row in rows(subviews, width: width) {
            height += (row.map { subviews[$0].sizeThatFits(.unspecified).height }.max() ?? 0) + spacing
        }
        return CGSize(width: width, height: max(0, height - spacing))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(subviews, width: bounds.width) {
            let sizes = row.map { subviews[$0].sizeThatFits(.unspecified) }
            let total = sizes.reduce(0) { $0 + $1.width } + spacing * CGFloat(max(0, row.count - 1))
            var x = bounds.minX + (bounds.width - total) / 2
            let rowHeight = sizes.map(\.height).max() ?? 0
            for (index, size) in zip(row, sizes) {
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += rowHeight + spacing
        }
    }
}
