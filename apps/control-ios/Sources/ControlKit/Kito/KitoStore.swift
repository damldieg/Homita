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
    /// Lo que se pinta: sin los resultados de confirmación (que solo viven en el historial).
    public var visibleMessages: [KitoMessage] { messages.filter { !$0.oculto } }
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
    private let now: () -> Date
    private let changes: (any KitoChangePublishing)?
    /// Tokens con una confirmación en vuelo: segunda barrera contra el doble toque (el token vale 2 min en servidor).
    private var inFlight: Set<String> = []

    public init(
        api: KitoAPI,
        historyStore: KitoHistoryStore,
        userId: Int,
        homeId: String,
        timezone: @escaping () -> String = { TimeZone.current.identifier },
        speaker: KitoSpeaking? = nil,
        voiceMode: @escaping () -> KitoVoiceMode = { KitoVoiceSettings.load() },
        isVoiceOverRunning: @escaping () -> Bool = KitoStore.systemVoiceOverRunning,
        now: @escaping () -> Date = { Date() },
        changes: (any KitoChangePublishing)? = nil
    ) {
        self.api = api
        self.historyStore = historyStore
        self.userId = userId
        self.homeId = homeId
        self.timezone = timezone
        self.speaker = speaker
        self.voiceMode = voiceMode
        self.isVoiceOverRunning = isVoiceOverRunning
        self.now = now
        self.changes = changes
        let normalized = Self.normalize(historyStore.load(userId: userId, homeId: homeId), now: now())
        self.messages = normalized.messages
        speaker?.onChange = { [weak self] id in self?.speakingId = id }
        if normalized.changed { persist() }
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
            changes?.publish(reply.cambios)
            let auto = KitoSpeechPolicy.shouldSpeak(
                origen: origen, mode: voiceMode(), voiceOverOn: isVoiceOverRunning(), chatVisible: isChatVisible
            )
            if auto { speak(answer) }
        } catch {
            guard startEpoch == epoch else { return }
            failure = KitoFailure(text: KitoErrorCopy.text(for: error), retryable: KitoErrorCopy.isRetryable(error))
        }
    }

    // MARK: - Confirmaciones

    /// Confirma la propuesta de una tarjeta `confirmacion`. Solo actúa sobre una tarjeta `pendiente` y no caducada:
    /// persiste `enviando` ANTES de la petición, llama una sola vez y no reintenta nunca (el token es reusable en
    /// servidor y un reintento podría duplicar eventos, rutinas o calendarios).
    public func confirm(messageId: UUID, cardIndex: Int) async {
        guard let found = confirmation(messageId: messageId, cardIndex: cardIndex), found.confirmation.estado == .pendiente else { return }
        guard let token = found.confirmation.token, !found.confirmation.isExpired(at: now()) else {
            resolveCard(messageId: messageId, index: cardIndex, estado: .caducado)
            return
        }
        guard !inFlight.contains(token) else { return }
        inFlight.insert(token)
        defer { inFlight.remove(token) }
        resolveCard(messageId: messageId, index: cardIndex, estado: .enviando)
        let startEpoch = epoch

        let outcome = await api.confirm(token: token, timezone: timezone())

        // El servidor sí ejecutó (aunque sea en parte): las pestañas se recargan aunque la conversación ya no sea esta.
        switch outcome {
        case .hecho(_, let cambios), .parcial(_, let cambios): changes?.publish(cambios)
        default: break
        }
        guard startEpoch == epoch else { return }
        let (estado, detalle) = Self.resolution(for: outcome)
        resolveCard(messageId: messageId, index: cardIndex, estado: estado, detalle: detalle, answer: true)
    }

    /// Cancelar es solo local: no llama al servidor.
    public func cancel(messageId: UUID, cardIndex: Int) {
        guard let found = confirmation(messageId: messageId, cardIndex: cardIndex), found.confirmation.estado == .pendiente else { return }
        resolveCard(messageId: messageId, index: cardIndex, estado: .cancelado, answer: true)
    }

    /// Marca como caducada una tarjeta pendiente cuyo plazo ha pasado (sin llamar al servidor). Devuelve si cambió.
    @discardableResult
    public func expireIfNeeded(messageId: UUID, cardIndex: Int) -> Bool {
        guard let found = confirmation(messageId: messageId, cardIndex: cardIndex),
              found.confirmation.estado == .pendiente, found.confirmation.isExpired(at: now()) else { return false }
        resolveCard(messageId: messageId, index: cardIndex, estado: .caducado)
        return true
    }

    /// Estado actual de una tarjeta `confirmacion` (nil si no existe o es de otro tipo).
    public func confirmationState(messageId: UUID, cardIndex: Int) -> KitoConfirmationState? {
        confirmation(messageId: messageId, cardIndex: cardIndex)?.confirmation.estado
    }

    private func confirmation(messageId: UUID, cardIndex: Int) -> (messageIndex: Int, confirmation: KitoConfirmation)? {
        guard let mi = messages.firstIndex(where: { $0.id == messageId }),
              let cards = messages[mi].cards, cards.indices.contains(cardIndex),
              let confirmation = KitoConfirmation(card: cards[cardIndex]) else { return nil }
        return (mi, confirmation)
    }

    /// Reemplaza el mensaje (mismo id, misma posición) con la tarjeta en su nuevo estado y persiste. Nunca añade
    /// el mensaje otra vez. Con `answer`, añade además un mensaje de Kito con el resultado para el turno siguiente.
    func resolveCard(messageId: UUID, index: Int, estado: KitoConfirmationState, detalle: String? = nil, answer: Bool = false) {
        guard let found = confirmation(messageId: messageId, cardIndex: index) else { return }
        let old = messages[found.messageIndex]
        var cards = old.cards ?? []
        cards[index] = KitoConfirmation.card(cards[index], estado: estado, detalle: detalle)
        messages[found.messageIndex] = KitoMessage(id: old.id, role: old.role, text: old.text, date: old.date, cards: cards, origen: old.origen, oculto: old.oculto)
        if answer {
            let text = estado.historyText(detalle: detalle)
            if !text.isEmpty { messages.append(KitoMessage(role: .assistant, text: text, oculto: true)) }
        }
        persist()
    }

    /// Estado final y detalle según el resultado del servidor. Ninguno reabilita la tarjeta.
    static func resolution(for outcome: KitoConfirmOutcome) -> (KitoConfirmationState, String?) {
        switch outcome {
        case .hecho(let texto, _):
            return (.hecho, texto.isEmpty ? nil : texto)
        case .rechazado:
            return (.caducado, nil)
        case .parcial(let texto, _):
            return (.parcial, (texto?.isEmpty == false) ? texto : "Revisa y pídemelo otra vez")
        case .sinSecreto:
            return (.error, "Kito no puede confirmar ahora mismo")
        case .sesionCaducada:
            return (.error, "Tu sesión ha caducado")
        case .otro(let status):
            return status >= 500 ? (.desconocido, nil) : (.error, "Pídemelo otra vez")
        case .desconocido:
            return (.desconocido, nil)
        }
    }

    /// Al cargar el historial: `enviando` (la app se cerró a mitad) pasa a `desconocido` sin reintento, y una
    /// tarjeta pendiente ya caducada pasa a `caducado`.
    static func normalize(_ messages: [KitoMessage], now: Date) -> (messages: [KitoMessage], changed: Bool) {
        var changed = false
        let out = messages.map { message -> KitoMessage in
            guard let cards = message.cards else { return message }
            var newCards = cards
            for (i, card) in cards.enumerated() {
                guard let c = KitoConfirmation(card: card) else { continue }
                if c.estado == .enviando {
                    newCards[i] = KitoConfirmation.card(card, estado: .desconocido)
                } else if c.estado == .pendiente, c.isExpired(at: now) {
                    newCards[i] = KitoConfirmation.card(card, estado: .caducado)
                }
            }
            guard newCards != cards else { return message }
            changed = true
            return KitoMessage(id: message.id, role: message.role, text: message.text, date: message.date, cards: newCards, origen: message.origen, oculto: message.oculto)
        }
        return (out, changed)
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

/// Destino de los cambios que hace Kito (para recargar las pantallas). Lo implementa `KitoChanges`.
@MainActor
public protocol KitoChangePublishing: AnyObject {
    func publish(_ changes: [KitoChange])
}
