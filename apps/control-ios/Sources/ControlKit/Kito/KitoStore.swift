import Foundation

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

    private let api: KitoAPI
    private let historyStore: KitoHistoryStore
    private let userId: Int
    private let homeId: String
    private let timezone: () -> String

    public init(
        api: KitoAPI,
        historyStore: KitoHistoryStore,
        userId: Int,
        homeId: String,
        timezone: @escaping () -> String = { TimeZone.current.identifier }
    ) {
        self.api = api
        self.historyStore = historyStore
        self.userId = userId
        self.homeId = homeId
        self.timezone = timezone
        self.messages = historyStore.load(userId: userId, homeId: homeId)
    }

    /// Envía un mensaje del usuario y añade la respuesta de Kito. Ignora textos vacíos y envíos en curso.
    public func send(_ raw: String) async {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        guard text.count <= KitoLimits.maxChars else {
            failure = KitoFailure(text: KitoErrorCopy.tooLong(), retryable: false)
            return
        }

        messages.append(KitoMessage(role: .user, text: text))
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
        messages = []
        failure = nil
        usage = nil
        persist()
    }

    private func ask() async {
        isSending = true
        failure = nil
        defer { isSending = false }

        do {
            let reply = try await api.ask(history: messages, timezone: timezone())
            messages.append(KitoMessage(role: .assistant, text: reply.texto, cards: reply.tarjetas.isEmpty ? nil : reply.tarjetas))
            usage = reply.uso ?? usage
            persist()
        } catch {
            failure = KitoFailure(text: KitoErrorCopy.text(for: error), retryable: KitoErrorCopy.isRetryable(error))
        }
    }

    /// Mensaje para el usuario según el error de la Edge (429 límite, 502 modelo, red, sesión).
    public static func message(for error: Error) -> String {
        KitoErrorCopy.text(for: error)
    }

    private func persist() {
        try? historyStore.save(messages, userId: userId, homeId: homeId)
    }
}
