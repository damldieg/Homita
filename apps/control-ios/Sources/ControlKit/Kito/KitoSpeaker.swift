import Foundation
#if os(iOS)
import AVFoundation
#endif

// MARK: - Limpieza del texto para voz

/// Deja la respuesta lista para leerla en voz alta: sin Markdown, emojis ni URLs, con pausas donde había
/// viñetas, títulos o saltos de línea, y las horas «09:30» como «9 y 30». Función pura, sin audio.
public enum KitoSpeechText {
    public static func clean(_ raw: String) -> String {
        var lines: [String] = []
        for rawLine in raw.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            line = replace(line, #"^(#{1,6}\s+|>+\s*|[-*•+]\s+|\d{1,2}[.)]\s+)"#, "")
            line = replace(line, #"!?\[([^\]]*)\]\([^)]*\)"#, "$1")
            line = replace(line, #"(?i)\b(?:https?://|www\.)\S+"#, "")
            line = spokenTimes(line)
            line = replace(line, #"[*`~|]+"#, "")
            line = replace(line, #"(?<![\p{L}\p{N}])_+|_+(?![\p{L}\p{N}])"#, "")
            line = removeEmoji(line)
            line = replace(line, #"\s+"#, " ").trimmingCharacters(in: .whitespaces)
            guard line.contains(where: { $0.isLetter || $0.isNumber }) else { continue }
            if let last = line.last, !".!?…:;,".contains(last) { line += "." }
            lines.append(line)
        }
        return lines.joined(separator: " ")
    }

    /// «09:30» → «9 y 30»; «09:00» → «9 en punto». Fuera de 00:00–23:59 se deja como está.
    private static func spokenTimes(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"(?<![\d:])(\d{1,2}):(\d{2})(?![\d:])"#) else { return text }
        var result = text
        let range = NSRange(text.startIndex..., in: text)
        for match in regex.matches(in: text, range: range).reversed() {
            guard let whole = Range(match.range, in: result),
                  let hr = Range(match.range(at: 1), in: text), let mr = Range(match.range(at: 2), in: text),
                  let hour = Int(text[hr]), let minute = Int(text[mr]), hour < 24, minute < 60 else { continue }
            result.replaceSubrange(whole, with: minute == 0 ? "\(hour) en punto" : "\(hour) y \(minute)")
        }
        return result
    }

    private static func removeEmoji(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            let v = scalar.value
            let isEmoji = scalar.properties.isEmojiPresentation || (scalar.properties.isEmoji && v > 0x2100)
            if isEmoji || v == 0xFE0F || v == 0x200D || v == 0x20E3 { continue }
            scalars.append(scalar)
        }
        return String(scalars)
    }

    private static func replace(_ text: String, _ pattern: String, _ template: String) -> String {
        text.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
    }
}

// MARK: - Cuándo habla Kito

/// Ajuste «Kito responde con voz».
public enum KitoVoiceMode: String, CaseIterable, Identifiable, Sendable {
    case soloSiLeHablo
    case siempre
    case nunca

    public var id: String { rawValue }

    /// Valor por defecto.
    public static let standard: KitoVoiceMode = .soloSiLeHablo

    public var title: String {
        switch self {
        case .soloSiLeHablo: "Solo si le hablo"
        case .siempre: "Siempre"
        case .nunca: "Nunca"
        }
    }
}

/// Ajuste guardado en `UserDefaults` (la clave la comparte `@AppStorage` en la cabecera del chat).
public enum KitoVoiceSettings {
    public static let key = "kito.voiceMode"

    public static func load(_ defaults: UserDefaults = .standard) -> KitoVoiceMode {
        defaults.string(forKey: key).flatMap(KitoVoiceMode.init(rawValue:)) ?? .standard
    }

    public static func save(_ mode: KitoVoiceMode, _ defaults: UserDefaults = .standard) {
        defaults.set(mode.rawValue, forKey: key)
    }
}

/// Regla de la lectura automática de una respuesta. El botón de altavoz manual no pasa por aquí.
public enum KitoSpeechPolicy {
    public static func shouldSpeak(origen: KitoOrigen, mode: KitoVoiceMode, voiceOverOn: Bool, chatVisible: Bool) -> Bool {
        guard chatVisible, !voiceOverOn else { return false }
        switch mode {
        case .nunca: return false
        case .siempre: return true
        case .soloSiLeHablo: return origen == .voz
        }
    }
}

// MARK: - Elección de voz

/// Una voz instalada, reducida a lo que importa para elegir.
public struct KitoVoiceCandidate: Equatable, Sendable {
    public enum Quality: Int, Comparable, Sendable {
        case standard = 0, enhanced, premium
        public static func < (a: Quality, b: Quality) -> Bool { a.rawValue < b.rawValue }
    }

    public let identifier: String
    public let language: String
    public let quality: Quality

    public init(identifier: String, language: String, quality: Quality) {
        self.identifier = identifier
        self.language = language
        self.quality = quality
    }
}

public enum KitoVoiceChoice {
    /// Mejor voz es-ES (premium > enhanced > estándar); si no hay, la mejor de cualquier español; si no, nil.
    public static func best(from candidates: [KitoVoiceCandidate]) -> KitoVoiceCandidate? {
        func key(_ code: String) -> String { code.replacingOccurrences(of: "_", with: "-").lowercased() }
        func pick(_ list: [KitoVoiceCandidate]) -> KitoVoiceCandidate? {
            // max(by:) devuelve el último empate; se invierte para quedarse con el primero de la lista.
            list.reversed().max { $0.quality < $1.quality }
        }
        return pick(candidates.filter { key($0.language) == "es-es" })
            ?? pick(candidates.filter { key($0.language).hasPrefix("es") })
    }
}

// MARK: - Sintetizador

/// Voz de Kito tras un protocolo para probar la lógica sin audio.
@MainActor
public protocol KitoSpeaking: AnyObject {
    /// Se llama con el id del mensaje que suena, o con `nil` al terminar o parar.
    var onChange: ((UUID?) -> Void)? { get set }
    /// Lee `text` (ya limpio). Si hay otra lectura, la sustituye.
    func speak(_ text: String, id: UUID)
    /// Calla en el acto.
    func stop()
}

#if os(iOS)
/// Voz real: `AVSpeechSynthesizer` en el dispositivo, con la mejor voz es-ES instalada.
@MainActor
public final class KitoSpeaker: NSObject, KitoSpeaking, AVSpeechSynthesizerDelegate {
    public var onChange: ((UUID?) -> Void)?

    private let synthesizer = AVSpeechSynthesizer()
    private var current: (utterance: AVSpeechUtterance, id: UUID)?
    private var observers: [NSObjectProtocol] = []

    public override init() {
        super.init()
        synthesizer.delegate = self
        let center = NotificationCenter.default
        // Llamada, Siri o cambio de ruta (auriculares fuera): callar sin error.
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
            Task { @MainActor in self?.stop() }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable else { return }
            Task { @MainActor in self?.stop() }
        })
    }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    public func speak(_ text: String, id: UUID) {
        guard !text.isEmpty else { return }
        if current != nil { synthesizer.stopSpeaking(at: .immediate) }
        try? KitoAudioSession.activate()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.preferredVoice()
        current = (utterance, id)
        onChange?(id)
        synthesizer.speak(utterance)
    }

    public func stop() {
        guard current != nil else { return }
        current = nil
        synthesizer.stopSpeaking(at: .immediate)
        onChange?(nil)
        KitoAudioSession.deactivate()
    }

    /// La mejor voz es-ES instalada; si no hay, la que el sistema asocie a es-ES.
    static func preferredVoice() -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        let candidates = voices.map {
            KitoVoiceCandidate(identifier: $0.identifier, language: $0.language, quality: Self.quality($0.quality))
        }
        if let best = KitoVoiceChoice.best(from: candidates), let voice = AVSpeechSynthesisVoice(identifier: best.identifier) {
            return voice
        }
        return AVSpeechSynthesisVoice(language: "es-ES")
    }

    private static func quality(_ q: AVSpeechSynthesisVoiceQuality) -> KitoVoiceCandidate.Quality {
        switch q {
        case .premium: .premium
        case .enhanced: .enhanced
        default: .standard
        }
    }

    // Delegado: puede llegar fuera del MainActor; solo se compara la identidad de la locución.
    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let key = ObjectIdentifier(utterance)
        Task { @MainActor in self.ended(key) }
    }

    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let key = ObjectIdentifier(utterance)
        Task { @MainActor in self.ended(key) }
    }

    private func ended(_ key: ObjectIdentifier) {
        guard let current, ObjectIdentifier(current.utterance) == key else { return }
        self.current = nil
        onChange?(nil)
        KitoAudioSession.deactivate()
    }
}
#endif

/// Sintetizador por defecto de la app: el real en iOS; en el host de tests, ninguno.
@MainActor
public func makeLiveKitoSpeaker() -> KitoSpeaking? {
    #if os(iOS)
    return KitoSpeaker()
    #else
    return nil
    #endif
}
