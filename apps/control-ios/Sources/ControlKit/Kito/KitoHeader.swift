import SwiftUI

/// Cabecera del chat: avatar, nombre, subtítulo, menú con «Borrar conversación» y cerrar.
struct KitoHeader: View {
    let canClear: Bool
    let onClear: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: Spacing.s3) {
            KitoAvatar(size: 36)
            VStack(alignment: .leading, spacing: 0) {
                Text("Kito")
                    .font(HomitaFont.inter(17, weight: .bold, relativeTo: .headline))
                    .foregroundStyle(Palette.ink)
                Text("Tu ayudante de casa")
                    .font(HomitaFont.inter(13, relativeTo: .caption))
                    .foregroundStyle(Palette.inkSoft)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: Spacing.s2)
            Menu {
                Button(role: .destructive, action: onClear) {
                    Label("Borrar conversación", systemImage: "trash")
                }
                .disabled(!canClear)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("Más opciones")
            .accessibilityHint("Incluye borrar la conversación")
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cerrar")
        }
        .padding(.horizontal, Spacing.gutter)
        .padding(.vertical, Spacing.s2)
        .background(Palette.background)
        .overlay(alignment: .bottom) { Palette.line.frame(height: 1) }
    }
}
