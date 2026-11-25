import Foundation

/// Permiso de micrófono y reconocimiento de voz, ya resuelto.
public enum KitoSpeechPermission: Equatable, Sendable {
    case granted
    case denied
}

/// Lo que el reconocedor cuenta mientras escucha.
public enum KitoSpeechEvent: Equatable, Sendable {
    /// Transcripción parcial (se ve en vivo en el campo).
    case partial(String)
    /// Transcripción final: el reconocedor ha terminado.
    case final(String)
    /// El reconocimiento ha fallado.
    case failed
    /// Llamada, Siri o cambio de ruta: el audio se ha cortado.
    case interrupted
}

/// Error al arrancar el reconocedor (no disponible, sin micrófono…).
public struct KitoSpeechError: Error, Equatable {
    public init() {}
}

/// Reconocimiento de voz tras un protocolo para poder probar el dictado sin audio real.
@MainActor
public protocol KitoSpeechRecognizing: AnyObject {
    /// Pide (o consulta, si ya se decidió) micrófono y reconocimiento. Solo se llama al pulsar el micro.
    func requestPermission() async -> KitoSpeechPermission
    /// Empieza a escuchar. Los eventos llegan en el hilo principal.
    func start(onEvent: @escaping @MainActor (KitoSpeechEvent) -> Void) throws
    /// Deja de escuchar y pide el resultado final.
    func stop()
    /// Corta todo sin resultado.
    func cancel()
}

/// Controlador del dictado: estado, transcripción parcial y fin por toque o por silencio.
/// Cancelar descarta el texto y no envía; una transcripción vacía tampoco envía.
@MainActor
@Observable
public final class KitoDictation {
    public enum State: Equatable {
        case idle
        /// Pidiendo permisos (solo la primera vez).
        case requesting
        case listening
        /// Se ha pedido parar y se espera el resultado final.
        case finishing
        /// Permiso denegado: micro desactivado y aviso con acceso a Ajustes.
        case denied
        case failed
    }

    /// Programa una acción tras un tiempo y devuelve cómo cancelarla (inyectable para probar).
    public typealias Scheduler = @MainActor (TimeInterval, @escaping @MainActor () -> Void) -> () -> Void

    public private(set) var state: State = .idle
    /// Transcripción en curso.
    public private(set) var partial = ""

    /// Se llama al pulsar el micro, antes de pedir permisos (Kito se calla).
    public var onStart: () -> Void = {}
    /// Texto final no vacío, ya recortado.
    public var onFinish: (String) -> Void = { _ in }

    public var isActive: Bool { state == .requesting || state == .listening || state == .finishing }
    public var isListening: Bool { state == .listening }

    private let recognizer: KitoSpeechRecognizing
    private let silenceDelay: TimeInterval
    private let noSpeechDelay: TimeInterval
    private let finishTimeout: TimeInterval
    private let schedule: Scheduler
    private var cancelTimer: (() -> Void)?
    /// Sube con cada dictado nuevo o cancelado; descarta respuestas tardías (permisos, eventos).
    private var generation = 0

    public init(
        recognizer: KitoSpeechRecognizing,
        silenceDelay: TimeInterval = 1.5,
        noSpeechDelay: TimeInterval = 6,
        finishTimeout: TimeInterval = 1.5,
        schedule: Scheduler? = nil
    ) {
        self.recognizer = recognizer
        self.silenceDelay = silenceDelay
        self.noSpeechDelay = noSpeechDelay
        self.finishTimeout = finishTimeout
        self.schedule = schedule ?? Self.sleepScheduler
    }

    /// Planificador real: `Task.sleep`.
    public static let sleepScheduler: Scheduler = { delay, action in
        let task = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            if !Task.isCancelled { action() }
        }
        return { task.cancel() }
    }

    /// Un toque en el micro: empieza o, si ya escucha, termina y envía.
    public func toggle() {
        switch state {
        case .idle, .failed:
            begin()
        case .listening:
            stopAndFinish()
        case .requesting, .finishing, .denied:
            break
        }
    }

    /// Descarta el dictado: sin enviar y sin parcial.
    public func cancel() {
        guard state != .idle || !partial.isEmpty else { return }
        generation += 1
        clearTimer()
        recognizer.cancel()
        partial = ""
        if state != .denied { state = .idle }
    }

    /// Tras volver de Ajustes: si estaba denegado, vuelve a consultar el permiso (sin diálogo si ya se decidió).
    public func recheckIfDenied() {
        guard state == .denied else { return }
        generation += 1
        let mine = generation
        Task { @MainActor in
            let permission = await recognizer.requestPermission()
            if mine == generation, state == .denied, permission == .granted { state = .idle }
        }
    }

    private func begin() {
        generation += 1
        let mine = generation
        partial = ""
        state = .requesting
        onStart()
        Task { @MainActor in
            let permission = await recognizer.requestPermission()
            guard mine == generation, state == .requesting else { return }
            guard permission == .granted else {
                state = .denied
                return
            }
            do {
                try recognizer.start { [weak self] event in self?.handle(event, generation: mine) }
                state = .listening
                arm(after: noSpeechDelay)
            } catch {
                state = .failed
            }
        }
    }

    private func handle(_ event: KitoSpeechEvent, generation mine: Int) {
        guard mine == generation, isActive else { return }
        switch event {
        case .partial(let text):
            partial = text
            if state == .listening { arm(after: silenceDelay) }
        case .final(let text):
            finish(with: text.isEmpty ? partial : text)
        case .failed:
            if partial.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                clearTimer()
                recognizer.cancel()
                partial = ""
                state = .failed
            } else {
                finish(with: partial)
            }
        case .interrupted:
            cancel()
        }
    }

    private func stopAndFinish() {
        guard state == .listening else { return }
        state = .finishing
        recognizer.stop()
        arm(after: finishTimeout)
    }

    private func arm(after delay: TimeInterval) {
        clearTimer()
        cancelTimer = schedule(delay) { [weak self] in
            guard let self else { return }
            switch self.state {
            case .listening: self.stopAndFinish()
            case .finishing: self.finish(with: self.partial)
            default: break
            }
        }
    }

    private func clearTimer() {
        cancelTimer?()
        cancelTimer = nil
    }

    private func finish(with text: String) {
        generation += 1
        clearTimer()
        recognizer.cancel()
        let result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        partial = ""
        state = .idle
        if !result.isEmpty { onFinish(result) }
    }
}
