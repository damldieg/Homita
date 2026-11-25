import Foundation
#if os(iOS)
import AVFoundation
import Speech
#endif

#if os(iOS)
/// Sesión de audio compartida por el dictado y la voz de Kito: `.playAndRecord` con altavoz y bajando otras apps.
@MainActor
enum KitoAudioSession {
    static func activate() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .duckOthers])
        try session.setActive(true)
    }

    /// Devuelve el audio a las demás apps.
    static func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

/// Dictado real: `SFSpeechRecognizer` (es-ES, en el dispositivo si se puede) sobre `AVAudioEngine`.
@MainActor
public final class KitoSpeechRecognizer: KitoSpeechRecognizing {
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "es-ES"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var onEvent: (@MainActor (KitoSpeechEvent) -> Void)?
    private var generation = 0
    private var observer: NSObjectProtocol?

    public init() {}

    public func requestPermission() async -> KitoSpeechPermission {
        let speech: Bool = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
        guard speech else { return .denied }
        let microphone = await AVAudioApplication.requestRecordPermission()
        return microphone ? .granted : .denied
    }

    public func start(onEvent: @escaping @MainActor (KitoSpeechEvent) -> Void) throws {
        cancel()
        guard let recognizer, recognizer.isAvailable else { throw KitoSpeechError() }
        try KitoAudioSession.activate()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        self.request = request
        self.onEvent = onEvent
        generation += 1
        let mine = generation
        do {
            Self.installTap(on: engine, request: request)
            engine.prepare()
            try engine.start()
        } catch {
            teardown()
            throw error
        }
        task = Self.makeTask(recognizer: recognizer, request: request) { [weak self] text, isFinal, failed in
            Task { @MainActor in self?.handle(generation: mine, text: text, isFinal: isFinal, failed: failed) }
        }
        observer = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
            Task { @MainActor in self?.interrupted(generation: mine) }
        }
    }

    public func stop() {
        guard request != nil else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
    }

    public func cancel() {
        generation += 1
        task?.cancel()
        teardown()
    }

    private func handle(generation mine: Int, text: String?, isFinal: Bool, failed: Bool) {
        guard mine == generation, let onEvent else { return }
        if failed {
            teardown()
            onEvent(.failed)
        } else if let text {
            if isFinal {
                teardown()
                onEvent(.final(text))
            } else {
                onEvent(.partial(text))
            }
        }
    }

    private func interrupted(generation mine: Int) {
        guard mine == generation, let onEvent else { return }
        cancel()
        onEvent(.interrupted)
    }

    private func teardown() {
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        request = nil
        task = nil
        onEvent = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        KitoAudioSession.deactivate()
    }

    // Fuera del MainActor: el tap de audio y el callback del reconocedor corren en hilos propios.
    private nonisolated static func installTap(on engine: AVAudioEngine, request: SFSpeechAudioBufferRecognitionRequest) {
        let input = engine.inputNode
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
            request.append(buffer)
        }
    }

    private nonisolated static func makeTask(
        recognizer: SFSpeechRecognizer,
        request: SFSpeechAudioBufferRecognitionRequest,
        handler: @escaping @Sendable (String?, Bool, Bool) -> Void
    ) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, error in
            handler(result?.bestTranscription.formattedString, result?.isFinal ?? false, error != nil)
        }
    }
}
#endif

/// Reconocedor por defecto de la app: el real en iOS; en el host de tests, uno que nunca concede permiso.
@MainActor
public func makeLiveKitoRecognizer() -> KitoSpeechRecognizing {
    #if os(iOS)
    return KitoSpeechRecognizer()
    #else
    return KitoUnavailableRecognizer()
    #endif
}

/// Sin dictado (host de tests): deniega el permiso.
@MainActor
final class KitoUnavailableRecognizer: KitoSpeechRecognizing {
    func requestPermission() async -> KitoSpeechPermission { .denied }
    func start(onEvent: @escaping @MainActor (KitoSpeechEvent) -> Void) throws { throw KitoSpeechError() }
    func stop() {}
    func cancel() {}
}
