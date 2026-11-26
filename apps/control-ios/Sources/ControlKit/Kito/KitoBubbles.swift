import SwiftUI

/// Forma de burbuja: esquinas de 18 pt y la de la cola más cerrada en el último mensaje del grupo.
private func kitoBubbleShape(isUser: Bool, tail: Bool) -> UnevenRoundedRectangle {
    let big: CGFloat = 18
    let small: CGFloat = 6
    return UnevenRoundedRectangle(
        topLeadingRadius: big,
        bottomLeadingRadius: (!isUser && tail) ? small : big,
        bottomTrailingRadius: (isUser && tail) ? small : big,
        topTrailingRadius: big
    )
}

/// Hueco del avatar de 28 pt a la izquierda de las burbujas de Kito, con el avatar solo si `visible`.
private struct KitoAvatarSlot: View {
    let visible: Bool

    var body: some View {
        Group {
            if visible { KitoAvatar(size: 28) } else { Color.clear }
        }
        .frame(width: 28, height: 28)
    }
}

/// Burbuja de un mensaje. `isLastInGroup` pone la cola y, en Kito, el avatar.
struct KitoMessageBubble: View {
    let message: KitoMessage
    let isLastInGroup: Bool
    /// Altavoz de la respuesta: `nil` si no hay voz disponible.
    var onToggleSpeech: (() -> Void)?
    var isSpeaking = false
    /// Acciones de las tarjetas de confirmación (índice de la tarjeta en el mensaje).
    var onConfirm: (Int) -> Void = { _ in }
    var onCancel: (Int) -> Void = { _ in }
    var onAppearConfirmation: (Int) -> Void = { _ in }

    private var isUser: Bool { message.role == .user }

    private var spokenTime: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.timeStyle = .short
        f.dateStyle = .none
        return f.string(from: message.date)
    }

    var body: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: Spacing.s2) {
            HStack(alignment: .bottom, spacing: Spacing.s2) {
                if isUser {
                    Spacer(minLength: 48)
                } else {
                    KitoAvatarSlot(visible: isLastInGroup)
                }
                Text(KitoMarkdown.attributed(message.text))
                    .font(HomitaFont.inter(16))
                    .foregroundStyle(Palette.ink)
                    .tint(Palette.accent)
                    .textSelection(.enabled)
                    .padding(.horizontal, Spacing.s3)
                    .padding(.vertical, 10)
                    .background(
                        kitoBubbleShape(isUser: isUser, tail: isLastInGroup).fill(isUser ? Palette.accentSoft : Palette.surface)
                    )
                    .overlay {
                        if !isUser { kitoBubbleShape(isUser: false, tail: isLastInGroup).stroke(Palette.line, lineWidth: 1) }
                    }
                if !isUser { Spacer(minLength: 48) }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(isUser ? "Tú" : "Kito"), \(spokenTime): \(String(KitoMarkdown.attributed(message.text).characters))")
            // Fuera del `.combine` de la burbuja: elemento propio para VoiceOver.
            if !isUser, let onToggleSpeech {
                Button(action: onToggleSpeech) {
                    Image(systemName: isSpeaking ? "stop.circle.fill" : "speaker.wave.2")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(isSpeaking ? Palette.accent : Palette.inkSoft)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .padding(.leading, 28 + Spacing.s2 - 8)
                .padding(.top, -Spacing.s2)
                .accessibilityLabel(isSpeaking ? "Parar" : "Escuchar respuesta")
            }
            if let cards = message.cards, !cards.isEmpty {
                KitoCardRenderer(
                    messageId: message.id, cards: cards,
                    onConfirm: onConfirm, onCancel: onCancel, onAppearConfirmation: onAppearConfirmation
                )
                    .padding(.leading, 28 + Spacing.s2)
            }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }
}

/// «Kito está pensando»: burbuja con tres puntos que se encienden por turnos (quietos con «Reducir movimiento»).
struct KitoTypingBubble: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .bottom, spacing: Spacing.s2) {
            KitoAvatarSlot(visible: true)
            TimelineView(.periodic(from: .now, by: 0.4)) { context in
                let step = Int(context.date.timeIntervalSinceReferenceDate / 0.4) % 3
                HStack(spacing: 5) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .fill(Palette.inkMuted)
                            .frame(width: 7, height: 7)
                            .opacity(reduceMotion || index == step ? 1 : 0.35)
                    }
                }
                .padding(.horizontal, Spacing.s4)
                .padding(.vertical, 14)
                .background(kitoBubbleShape(isUser: false, tail: true).fill(Palette.surface))
                .overlay(kitoBubbleShape(isUser: false, tail: true).stroke(Palette.line, lineWidth: 1))
            }
            Spacer(minLength: 48)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Kito está pensando")
    }
}

/// Error con la voz de Kito, como burbuja suya. «Reintentar» solo si reenviar puede ayudar.
struct KitoErrorBubble: View {
    let failure: KitoFailure
    let retry: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: Spacing.s2) {
            KitoAvatarSlot(visible: true)
            VStack(alignment: .leading, spacing: Spacing.s2) {
                Text(failure.text)
                    .font(HomitaFont.inter(16))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if failure.retryable {
                    HomitaChipButton(title: "Reintentar", action: retry)
                        .accessibilityLabel("Reintentar")
                        .accessibilityHint("Vuelve a enviar tu último mensaje a Kito")
                }
            }
            .padding(.horizontal, Spacing.s3)
            .padding(.vertical, 10)
            .background(kitoBubbleShape(isUser: false, tail: true).fill(Palette.surface))
            .overlay(kitoBubbleShape(isUser: false, tail: true).stroke(Palette.line, lineWidth: 1))
            Spacer(minLength: 48)
        }
        .accessibilityElement(children: .contain)
    }
}
