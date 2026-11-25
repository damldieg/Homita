import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Hoja del chat de Kito: historial en el móvil, bienvenida, entrada de texto y estado de envío.
struct KitoChatView: View {
    let store: KitoStore
    var userName: String?
    @State private var dictation: KitoDictation
    @State private var draft = ""
    @State private var confirmingClear = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    @MainActor
    init(store: KitoStore, userName: String? = nil, dictation: KitoDictation? = nil) {
        self.store = store
        self.userName = userName
        _dictation = State(initialValue: dictation ?? KitoDictation(recognizer: makeLiveKitoRecognizer()))
    }

    var body: some View {
        VStack(spacing: 0) {
            KitoHeader(canClear: !store.messages.isEmpty, onClear: { confirmingClear = true }, onClose: { dismiss() })
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Spacing.s1) {
                        if store.messages.isEmpty && !store.isSending {
                            KitoWelcomeView(userName: userName) { suggestion in send(suggestion) }
                        }
                        ForEach(Array(store.messages.enumerated()), id: \.element.id) { index, message in
                            if startsNewDay(index) {
                                dayLabel(message.date)
                            }
                            KitoMessageBubble(
                                message: message,
                                isLastInGroup: isLastInGroup(index),
                                onToggleSpeech: store.canSpeak ? { store.toggleSpeech(for: message) } : nil,
                                isSpeaking: store.speakingId == message.id
                            )
                                .padding(.top, startsGroup(index) ? Spacing.s2 : 0)
                                .transition(entryTransition)
                                .id(message.id)
                        }
                        if store.isSending {
                            KitoTypingBubble().padding(.top, Spacing.s2).transition(entryTransition).id("typing")
                        }
                        if let failure = store.failure, !store.isSending {
                            KitoErrorBubble(failure: failure) { Task { await store.retry() } }
                                .padding(.top, Spacing.s2)
                                .transition(entryTransition)
                                .id("failure")
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(Spacing.gutter)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: store.messages.count)
                }
                .onChange(of: store.messages.count) { _, _ in scrollToBottom(proxy) }
                .onChange(of: store.isSending) { _, _ in scrollToBottom(proxy) }
                .onChange(of: store.failure) { _, _ in scrollToBottom(proxy) }
            }
            KitoInputBar(
                draft: $draft,
                dictation: dictation,
                isSending: store.isSending,
                notice: KitoQuota.remainingNotice(store.usage),
                noticeIsSoft: KitoQuota.isExhausted(store.usage),
                onSend: { send(draft); draft = "" }
            )
        }
        .background(Palette.background.ignoresSafeArea())
        .onChange(of: store.messages.last?.id) { _, _ in lightHaptic() }
        .onAppear {
            store.chatDidOpen()
            dictation.onStart = { store.dictationDidStart() }
            dictation.onFinish = { text in Task { await store.send(text, origen: .voz) } }
            dictation.recheckIfDenied()
        }
        .onDisappear {
            dictation.cancel()
            store.chatDidClose()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                dictation.recheckIfDenied()
            } else {
                dictation.cancel()
                store.stopSpeaking()
            }
        }
        .confirmationDialog("¿Borrar la conversación?", isPresented: $confirmingClear, titleVisibility: .visible) {
            Button("Borrar conversación", role: .destructive) { store.clearConversation() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Se borra el historial de este hogar en tu móvil. No se puede deshacer.")
        }
    }

    // MARK: - Agrupación

    private var entryTransition: AnyTransition {
        reduceMotion ? .identity : .opacity.combined(with: .offset(y: 8))
    }

    private func startsGroup(_ index: Int) -> Bool {
        index == 0 || store.messages[index - 1].role != store.messages[index].role
    }

    private func isLastInGroup(_ index: Int) -> Bool {
        index == store.messages.count - 1 || store.messages[index + 1].role != store.messages[index].role
    }

    private func startsNewDay(_ index: Int) -> Bool {
        index == 0 || !Calendar.current.isDate(store.messages[index - 1].date, inSameDayAs: store.messages[index].date)
    }

    private func dayLabel(_ date: Date) -> some View {
        Text(KitoGreeting.dayLabel(for: date))
            .font(HomitaFont.inter(12, weight: .medium, relativeTo: .caption))
            .foregroundStyle(Palette.inkSoft)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.s2)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Acciones

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { proxy.scrollTo("bottom", anchor: .bottom) }
    }

    private func lightHaptic() {
        #if canImport(UIKit)
        if store.messages.last?.role == .assistant {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        #endif
    }

    private func send(_ text: String) {
        Task { await store.send(text) }
    }
}
