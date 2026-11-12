import SwiftUI

/// Vacío dentro de una tarjeta (E0-04): una línea con el texto real, sin ilustración ni botón.
/// Cada tarjeta conserva su propio vacío; no sustituye a `HomitaEmptyState` de pantalla completa.
struct HomitaEmptyNote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(HomitaFont.inter(15, relativeTo: .body))
            .foregroundStyle(Palette.inkSoft)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(text)
    }
}
