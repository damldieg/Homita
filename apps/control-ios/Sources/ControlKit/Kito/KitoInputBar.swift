import SwiftUI

/// Barra de entrada: campo redondeado sobre fondo hundido, hueco reservado para el dictado y botón enviar.
struct KitoInputBar: View {
    @Binding var draft: String
    let isSending: Bool
    let notice: String?
    let noticeIsSoft: Bool
    let onSend: () -> Void

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    var body: some View {
        VStack(spacing: Spacing.s1) {
            HStack(alignment: .bottom, spacing: Spacing.s2) {
                TextField("", text: $draft, prompt: Text("Escribe a Kito").foregroundStyle(Palette.inkMuted), axis: .vertical)
                    .lineLimit(1...4)
                    .font(HomitaFont.inter(16))
                    .foregroundStyle(Palette.ink)
                    .tint(Palette.accent)
                    .submitLabel(.send)
                    .onSubmit { if canSend { onSend() } }
                    .padding(.horizontal, Spacing.s4)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 22).fill(Palette.surface))
                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(Palette.line, lineWidth: 1))
                // Hueco para el micro de dictado (paso 3): ancho fijo, invisible y fuera de VoiceOver.
                Color.clear.frame(width: 0, height: 40).accessibilityHidden(true)
                Button(action: onSend) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Palette.onFill)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(canSend ? Palette.accent : Palette.inkMuted.opacity(0.5)))
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .accessibilityLabel("Enviar")
                .accessibilityHint(canSend ? "Envía el mensaje a Kito" : "Escribe un mensaje para enviarlo")
            }
            if let notice {
                Text(notice)
                    .font(HomitaFont.inter(12, relativeTo: .caption))
                    .foregroundStyle(noticeIsSoft ? Palette.inkSoft : Palette.inkMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Spacing.s2)
                    .accessibilityLabel(notice)
            }
        }
        .padding(.horizontal, Spacing.s3)
        .padding(.vertical, Spacing.s2)
        .background(Palette.backgroundSunken)
    }
}
