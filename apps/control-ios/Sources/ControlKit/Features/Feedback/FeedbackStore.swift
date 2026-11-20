import Foundation

/// Estado del formulario de feedback: borrador, selectores dependientes y envío.
@Observable
public final class FeedbackStore {
    public private(set) var draft = FeedbackDraft()
    public private(set) var isWorking = false
    /// Error del último envío; el borrador se conserva para reintentar.
    public var errorMessage: String?
    /// El envío terminó bien: la pantalla muestra el agradecimiento y se cierra.
    public private(set) var didSend = false

    private let send: (FeedbackRequest) async throws -> Void

    public init(send: @escaping (FeedbackRequest) async throws -> Void) {
        self.send = send
    }

    public convenience init(repo: FeedbackRepository) {
        self.init(send: { try await repo.send($0) })
    }

    public var sections: [FeedbackSection] { FeedbackCatalog.sections }

    /// Pantallas de la sección elegida (vacío sin sección).
    public var screens: [FeedbackScreen] { draft.section?.screens ?? [] }

    /// Acciones de la pantalla elegida (vacío sin pantalla).
    public var actions: [String] { draft.screen?.actions ?? [] }

    public var text: String {
        get { draft.text }
        set { draft.text = FeedbackDraft.clamped(newValue) }
    }

    /// Cambiar de sección reinicia pantalla y acción.
    public func selectSection(_ section: FeedbackSection) {
        guard draft.section != section else { return }
        draft.section = section
        draft.screenName = nil
        draft.action = nil
    }

    /// Cambiar de pantalla reinicia la acción; si la pantalla solo admite una, se elige sola.
    public func selectScreen(_ screen: FeedbackScreen) {
        guard draft.screenName != screen.name else { return }
        draft.screenName = screen.name
        draft.action = screen.actions.count == 1 ? screen.actions[0] : nil
    }

    /// Ignora acciones que no son de la pantalla elegida.
    public func selectAction(_ action: String) {
        guard actions.contains(action) else { return }
        draft.action = action
    }

    public func selectKind(_ kind: FeedbackKind?) {
        draft.kind = kind
    }

    /// Vuelve al formulario vacío (borrador, error y estado de envío). Se llama al abrir la pantalla.
    public func reset() {
        draft = FeedbackDraft()
        errorMessage = nil
        didSend = false
    }

    /// Envío habilitado: borrador válido, sin envío en curso y con conexión.
    public func canSubmit(isOffline: Bool) -> Bool {
        draft.isValid && !isWorking && !isOffline
    }

    /// Envía el feedback. Sin conexión no se encola (el botón queda deshabilitado). Devuelve si fue bien.
    @discardableResult
    public func submit(isOffline: Bool = false) async -> Bool {
        guard canSubmit(isOffline: isOffline), let request = draft.request else { return false }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await send(request)
            didSend = true
            return true
        } catch {
            errorMessage = (error as? APIError)?.feedbackMessage ?? error.localizedDescription
            return false
        }
    }
}
