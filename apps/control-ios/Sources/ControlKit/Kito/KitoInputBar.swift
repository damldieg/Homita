import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

/// Barra de entrada: campo redondeado sobre fondo hundido, micro de dictado y botón enviar.
/// Mientras se dicta, el campo muestra la transcripción en vivo (el borrador escrito queda intacto).
struct KitoInputBar: View {
    @Binding var draft: String
    let dictation: KitoDictation
    let isSending: Bool
    let notice: String?
    let noticeIsSoft: Bool
    let onSend: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending && !dictation.isActive
    }

    private var fieldText: Binding<String> {
        Binding(
            get: { dictation.isActive ? dictation.partial : draft },
            set: { if !dictation.isActive { draft = $0 } }
        )
    }

    private var micEnabled: Bool {
        dictation.state != .denied && dictation.state != .requesting && dictation.state != .finishing && !isSending
    }

    private var dictationNotice: String? {
        switch dictation.state {
        case .failed: "No he podido escucharte. Inténtalo de nuevo o escribe tu mensaje."
        default: nil
        }
    }

    var body: some View {
        VStack(spacing: Spacing.s1) {
            HStack(alignment: .bottom, spacing: Spacing.s2) {
                TextField("", text: fieldText, prompt: Text(dictation.isActive ? "Te escucho…" : "Escribe a Kito").foregroundStyle(Palette.inkMuted), axis: .vertical)
                    .accessibilityLabel("Escribe a Kito")
                    .disabled(dictation.isActive)
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
                if dictation.isActive {
                    Button(action: dictation.cancel) {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Palette.inkSoft)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cancelar dictado")
                    .accessibilityHint("Descarta lo dictado sin enviarlo")
                }
                micButton
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
            if dictation.state == .denied { deniedNotice }
            if let dictationNotice {
                Text(dictationNotice)
                    .font(HomitaFont.inter(12, relativeTo: .caption))
                    .foregroundStyle(Palette.inkSoft)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Spacing.s2)
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

    private var micButton: some View {
        Button(action: dictation.toggle) {
            ZStack {
                Circle().fill(dictation.isListening ? Palette.accent : Palette.accentSoft)
                if dictation.isListening && !reduceMotion {
                    Circle()
                        .stroke(Palette.accent.opacity(0.5), lineWidth: 2)
                        .scaleEffect(pulse ? 1.35 : 1)
                        .opacity(pulse ? 0 : 1)
                }
                Image(systemName: dictation.isListening ? "stop.fill" : "mic.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(dictation.isListening ? Palette.onFill : Palette.accent)
            }
            .frame(width: 44, height: 44)
            .opacity(micEnabled || dictation.isListening ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .disabled(!micEnabled && !dictation.isListening)
        .accessibilityLabel(dictation.isListening ? "Parar" : "Hablar con Kito")
        .accessibilityHint(dictation.isListening ? "Termina el dictado y envía el mensaje" : "Dicta tu mensaje en voz alta")
        .onChange(of: dictation.isListening) { _, listening in
            pulse = false
            if listening && !reduceMotion {
                withAnimation(.easeOut(duration: 1.1).repeatForever(autoreverses: false)) { pulse = true }
            }
        }
    }

    private var deniedNotice: some View {
        HStack(spacing: Spacing.s2) {
            Text("Para hablar conmigo necesito el micrófono y el reconocimiento de voz. Puedes darme permiso en Ajustes.")
                .font(HomitaFont.inter(12, relativeTo: .caption))
                .foregroundStyle(Palette.inkSoft)
                .frame(maxWidth: .infinity, alignment: .leading)
            HomitaChipButton(title: "Abrir Ajustes", action: openSettings)
                .accessibilityHint("Abre los ajustes de la app para dar permiso")
        }
        .padding(.horizontal, Spacing.s2)
    }

    private func openSettings() {
        #if canImport(UIKit)
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        #endif
    }
}
