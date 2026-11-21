import Foundation

/// Estado del chat de Kito para un usuario y un hogar. Guarda cada mensaje en el móvil (`KitoHistoryStore`)
/// y envía el historial reciente a la Edge `asistente`. Si la petición falla, el mensaje del usuario se
/// conserva y `errorText` explica el motivo; el usuario puede volver a enviarlo.
@MainActor
@Observable
public final class KitoStore {
    public private(set) var messages: [KitoMessage]
    public private(set) var isSending = false
    public private(set) var errorText: String?

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
            errorText = "El mensaje es demasiado largo (máximo \(KitoLimits.maxChars) caracteres)."
            return
        }

        messages.append(KitoMessage(role: .user, text: text))
        persist()
        isSending = true
        errorText = nil
        defer { isSending = false }

        do {
            let reply = try await api.ask(history: messages, timezone: timezone())
            messages.append(KitoMessage(role: .assistant, text: reply.texto))
            persist()
        } catch {
            errorText = Self.message(for: error)
        }
    }

    /// Mensaje para el usuario según el error de la Edge (429 límite, 502 modelo, red, sesión).
    public static func message(for error: Error) -> String {
        guard let apiError = error as? APIError else { return "Algo ha fallado. Inténtalo de nuevo." }
        switch apiError {
        case .http(let status, _):
            switch status {
            case 429: return "Has llegado al límite de mensajes de hoy. Podrás volver a escribirme mañana."
            case 502: return "Kito no puede responder ahora. Inténtalo de nuevo en un momento."
            case 404: return "No encuentro el hogar activo. Vuelve a seleccionarlo."
            default: return "Kito no está disponible ahora. Inténtalo más tarde."
            }
        case .network: return "Sin conexión. Inténtalo cuando vuelva la red."
        case .sessionExpired: return "Tu sesión ha caducado. Vuelve a entrar."
        case .decoding: return "La respuesta de Kito no se ha entendido. Inténtalo de nuevo."
        }
    }

    private func persist() {
        try? historyStore.save(messages, userId: userId, homeId: homeId)
    }
}
