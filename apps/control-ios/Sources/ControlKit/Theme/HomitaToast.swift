import SwiftUI

/// Aviso no bloqueante bajo la barra de pestañas (E0-05, c): mensaje, «Reintentar» opcional y
/// cierre. Sustituye a la alerta «Aviso / OK» en los fallos de escritura.
struct HomitaToastView: View {
    let message: String
    var retry: (() -> Void)?
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: Spacing.s3) {
            Text(message)
                .font(HomitaFont.inter(15, relativeTo: .body))
                .foregroundStyle(Palette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let retry {
                Button("Reintentar", action: retry)
                    .font(HomitaFont.inter(15, weight: .semibold, relativeTo: .body))
                    .foregroundStyle(Palette.accent)
                    .frame(minHeight: 44)
            }
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.inkSoft)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Cerrar aviso")
        }
        .padding(.leading, Spacing.s4)
        .padding(.trailing, Spacing.s2)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.md))
        .overlay(RoundedRectangle(cornerRadius: Radius.md).stroke(Palette.line, lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .padding(.horizontal, Spacing.s4)
    }
}

extension View {
    /// Muestra un toast mientras `message` no sea nil. «Reintentar» llama a `retry` y cierra el aviso.
    func homitaToast(_ message: Binding<String?>, retry: (() -> Void)? = nil) -> some View {
        overlay(alignment: .bottom) {
            if let text = message.wrappedValue {
                HomitaToastView(
                    message: text,
                    retry: retry.map { action in
                        { message.wrappedValue = nil; action() }
                    },
                    dismiss: { message.wrappedValue = nil }
                )
                .padding(.bottom, Spacing.s4)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: message.wrappedValue)
    }
}
