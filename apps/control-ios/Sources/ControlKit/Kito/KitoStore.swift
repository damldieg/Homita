import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Estado del chat de Kito para un usuario y un hogar. Guarda cada mensaje en el móvil (`KitoHistoryStore`)
/// y envía el historial reciente a la Edge `asistente`. Si la petición falla, el mensaje del usuario se
/// conserva y `failure` explica el motivo y `retry()` lo reenvía sin duplicarlo.
@MainActor
@Observable
public final class KitoStore {
    public private(set) var messages: [KitoMessage]
    public private(set) var isSending = false
    public private(set) var failure: KitoFailure?
    /// Último cupo diario que informó la Edge (solo en memoria).
    public private(set) var usage: KitoReply.Usage?
    public var errorText: String? { failure?.text }
    /// Id del mensaje que Kito está leyendo en voz alta (para el botón de altavoz).
    public private(set) var speakingId: UUID?
    /// Si hay voz disponible (en el host de tests no la hay y no se pinta el altavoz).
    public var canSpeak: Bool { speaker != nil }

    private let api: KitoAPI
    private let historyStore: KitoHistoryStore
    private let userId: Int
    private let homeId: String
    private let timezone: () -> String
    private let speaker: KitoSpeaking?
    private let voiceMode: () -> KitoVoiceMode
    private let isVoiceOverRunning: () -> Bool
    /// Lo pone la vista: con el chat cerrado las respuestas no se leen.
    private var isChatVisible = true
    /// Sube al borrar la conversación; una respuesta en vuelo de otra época se descarta.
    private var epoch = 0

    public init(
        api: KitoAPI,
        historyStore: KitoHistoryStore,
        userId: Int,
        homeId: String,
        timezone: @escaping () -> String = { TimeZone.current.identifier },
        speaker: KitoSpeaking? = nil,
        voiceMode: @escaping () -> KitoVoiceMode = { KitoVoiceSettings.load() },
        isVoiceOverRunning: @escaping () -> Bool = KitoStore.systemVoiceOverRunning
    ) {
        self.api = api
        self.historyStore = historyStore
        self.userId = userId
        self.homeId = homeId
        self.timezone = timezone
        self.speaker = speaker
        self.voiceMode = voiceMode
        self.isVoiceOverRunning = isVoiceOverRunning
        self.messages = historyStore.load(userId: userId, homeId: homeId)
        speaker?.onChange = { [weak self] id in self?.speakingId = id }
    }

    public nonisolated static func systemVoiceOverRunning() -> Bool {
        #if canImport(UIKit)
        return MainActor.assumeIsolated { UIAccessibility.isVoiceOverRunning }
        #else
        return false
        #endif
    }

    /// Envía un mensaje del usuario y añade la respuesta de Kito. Ignora textos vacíos y envíos en curso.
    /// `origen` dice si se escribió o se dictó.
    public func send(_ raw: String, origen: KitoOrigen = .texto) async {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        guard text.count <= KitoLimits.maxChars else {
            failure = KitoFailure(text: KitoErrorCopy.tooLong(), retryable: false)
            return
        }

        messages.append(KitoMessage(role: .user, text: text, origen: origen))
        persist()
        await ask()
    }

    /// Reenvía el historial actual tras un fallo, sin añadir otro mensaje del usuario.
    public func retry() async {
        guard !isSending, let failure, failure.retryable, messages.last?.role == .user else { return }
        await ask()
    }

    /// Borra la conversación del usuario y hogar activos (los demás hogares y usuarios no cambian).
    public func clearConversation() {
        epoch += 1
        stopSpeaking()
        messages = []
        failure = nil
        usage = nil
        persist()
    }

    private func ask() async {
        isSending = true
        failure = nil
        let startEpoch = epoch
        defer { isSending = false }

        do {
            let reply = try await api.ask(history: messages, timezone: timezone())
            guard startEpoch == epoch else { return }
            let origen = messages.last(where: { $0.role == .user })?.origen ?? .texto
            let answer = KitoMessage(role: .assistant, text: reply.texto, cards: reply.tarjetas.isEmpty ? nil : reply.tarjetas)
            messages.append(answer)
            usage = reply.uso ?? usage
            persist()
            let auto = KitoSpeechPolicy.shouldSpeak(
                origen: origen, mode: voiceMode(), voiceOverOn: isVoiceOverRunning(), chatVisible: isChatVisible
            )
            if auto { speak(answer) }
        } catch {
            guard startEpoch == epoch else { return }
            failure = KitoFailure(text: KitoErrorCopy.text(for: error), retryable: KitoErrorCopy.isRetryable(error))
        }
    }

    // MARK: - Voz

    /// Botón de altavoz de una respuesta: lee si no suena y calla si ya suena. Siempre lee, haya VoiceOver o no.
    public func toggleSpeech(for message: KitoMessage) {
        if speakingId == message.id { stopSpeaking() } else { speak(message) }
    }

    /// Kito se calla en el acto.
    public func stopSpeaking() {
        speaker?.stop()
    }

    /// La vista del chat se ha abierto.
    public func chatDidOpen() { isChatVisible = true }

    /// La hoja del chat se ha cerrado: Kito se calla y no lee lo que llegue después.
    public func chatDidClose() {
        isChatVisible = false
        stopSpeaking()
    }

    /// Empieza un dictado: Kito se calla.
    public func dictationDidStart() { stopSpeaking() }

    private func speak(_ message: KitoMessage) {
        let text = KitoSpeechText.clean(message.text)
        guard !text.isEmpty else { return }
        speaker?.speak(text, id: message.id)
    }

    /// Mensaje para el usuario según el error de la Edge (429 límite, 502 modelo, red, sesión).
    public static func message(for error: Error) -> String {
        KitoErrorCopy.text(for: error)
    }

    private func persist() {
        try? historyStore.save(messages, userId: userId, homeId: homeId)
    }
}
