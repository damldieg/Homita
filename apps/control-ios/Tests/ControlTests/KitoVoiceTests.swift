import XCTest
@testable import ControlKit

/// Reconocedor falso: sin audio ni permisos reales.
@MainActor
final class FakeSpeechRecognizer: KitoSpeechRecognizing {
    var permission: KitoSpeechPermission = .granted
    var startError: Error?
    private(set) var permissionRequests = 0
    private(set) var starts = 0
    private(set) var stops = 0
    private(set) var cancels = 0
    private var onEvent: (@MainActor (KitoSpeechEvent) -> Void)?

    func requestPermission() async -> KitoSpeechPermission {
        permissionRequests += 1
        return permission
    }

    func start(onEvent: @escaping @MainActor (KitoSpeechEvent) -> Void) throws {
        if let startError { throw startError }
        starts += 1
        self.onEvent = onEvent
    }

    func stop() { stops += 1 }
    func cancel() { cancels += 1 }

    func emit(_ event: KitoSpeechEvent) { onEvent?(event) }
}

/// Reloj manual: guarda las acciones programadas y las dispara a mano.
@MainActor
final class ManualScheduler {
    private(set) var delays: [TimeInterval] = []
    private var pending: [Int: @MainActor () -> Void] = [:]
    private var next = 0

    var scheduler: KitoDictation.Scheduler {
        { [self] delay, action in
            delays.append(delay)
            let id = next
            next += 1
            pending[id] = action
            return { [self] in pending[id] = nil }
        }
    }

    var pendingCount: Int { pending.count }

    func fireAll() {
        let actions = pending
        pending = [:]
        for key in actions.keys.sorted() { actions[key]?() }
    }
}


/// Sintetizador falso: registra lo que se le pide leer.
@MainActor
final class FakeSpeaker: KitoSpeaking {
    var onChange: ((UUID?) -> Void)?
    private(set) var spoken: [(text: String, id: UUID)] = []
    private(set) var stops = 0
    private(set) var currentId: UUID?

    func speak(_ text: String, id: UUID) {
        spoken.append((text, id))
        currentId = id
        onChange?(id)
    }

    func stop() {
        stops += 1
        guard currentId != nil else { return }
        currentId = nil
        onChange?(nil)
    }
}

final class KitoVoiceTests: XCTestCase {
    // MARK: - Dictado

    @MainActor
    private func makeDictation(
        _ fake: FakeSpeechRecognizer,
        clock: ManualScheduler? = nil,
        finished: @escaping (String) -> Void = { _ in }
    ) -> KitoDictation {
        let dictation = KitoDictation(recognizer: fake, schedule: (clock ?? ManualScheduler()).scheduler)
        dictation.onFinish = finished
        return dictation
    }

    @MainActor
    private func waitUntil(_ dictation: KitoDictation, _ state: KitoDictation.State) async throws {
        for _ in 0..<200 where dictation.state != state { try await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertEqual(dictation.state, state)
    }

    @MainActor
    func testPermissionIsNotRequestedUntilTheFirstTap() async throws {
        let fake = FakeSpeechRecognizer()
        let dictation = makeDictation(fake)
        XCTAssertEqual(fake.permissionRequests, 0)
        XCTAssertEqual(dictation.state, .idle)

        dictation.toggle()
        try await waitUntil(dictation, .listening)
        XCTAssertEqual(fake.permissionRequests, 1)
        XCTAssertEqual(fake.starts, 1)
    }

    @MainActor
    func testPartialUpdatesTheTranscriptLive() async throws {
        let fake = FakeSpeechRecognizer()
        let dictation = makeDictation(fake)
        dictation.toggle()
        try await waitUntil(dictation, .listening)

        fake.emit(.partial("qué ten"))
        XCTAssertEqual(dictation.partial, "qué ten")
        fake.emit(.partial("qué tengo mañana"))
        XCTAssertEqual(dictation.partial, "qué tengo mañana")
    }

    @MainActor
    func testFinalTranscriptIsSentOnce() async throws {
        let fake = FakeSpeechRecognizer()
        var sent: [String] = []
        let dictation = makeDictation(fake) { sent.append($0) }
        dictation.toggle()
        try await waitUntil(dictation, .listening)

        fake.emit(.final("  ¿qué tengo mañana?  "))

        XCTAssertEqual(sent, ["¿qué tengo mañana?"])
        XCTAssertEqual(dictation.state, .idle)
        XCTAssertEqual(dictation.partial, "")
    }

    @MainActor
    func testEmptyOrBlankFinalSendsNothing() async throws {
        let fake = FakeSpeechRecognizer()
        var sent: [String] = []
        let dictation = makeDictation(fake) { sent.append($0) }
        for text in ["", "   \n"] {
            dictation.toggle()
            try await waitUntil(dictation, .listening)
            fake.emit(.final(text))
            XCTAssertEqual(dictation.state, .idle)
        }
        XCTAssertTrue(sent.isEmpty)
    }

    @MainActor
    func testSecondTapStopsAndSendsTheFinalText() async throws {
        let fake = FakeSpeechRecognizer()
        var sent: [String] = []
        let dictation = makeDictation(fake) { sent.append($0) }
        dictation.toggle()
        try await waitUntil(dictation, .listening)
        fake.emit(.partial("hola"))

        dictation.toggle()
        XCTAssertEqual(dictation.state, .finishing)
        XCTAssertEqual(fake.stops, 1)
        fake.emit(.final("hola Kito"))

        XCTAssertEqual(sent, ["hola Kito"])
        XCTAssertEqual(dictation.state, .idle)
    }

    @MainActor
    func testFinalNeverArrivingFallsBackToThePartial() async throws {
        let fake = FakeSpeechRecognizer()
        let clock = ManualScheduler()
        var sent: [String] = []
        let dictation = makeDictation(fake, clock: clock) { sent.append($0) }
        dictation.toggle()
        try await waitUntil(dictation, .listening)
        fake.emit(.partial("hola"))
        dictation.toggle()

        clock.fireAll()

        XCTAssertEqual(sent, ["hola"])
        XCTAssertEqual(dictation.state, .idle)
    }

    @MainActor
    func testCancelDiscardsWithoutSendingAndClearsThePartial() async throws {
        let fake = FakeSpeechRecognizer()
        var sent: [String] = []
        let dictation = makeDictation(fake) { sent.append($0) }
        dictation.toggle()
        try await waitUntil(dictation, .listening)
        fake.emit(.partial("no lo envíes"))

        dictation.cancel()
        fake.emit(.final("no lo envíes"))

        XCTAssertTrue(sent.isEmpty)
        XCTAssertEqual(dictation.partial, "")
        XCTAssertEqual(dictation.state, .idle)
        XCTAssertGreaterThanOrEqual(fake.cancels, 1)
    }

    @MainActor
    func testSilenceEndsTheDictationAndSends() async throws {
        let fake = FakeSpeechRecognizer()
        let clock = ManualScheduler()
        var sent: [String] = []
        let dictation = makeDictation(fake, clock: clock) { sent.append($0) }
        dictation.toggle()
        try await waitUntil(dictation, .listening)
        fake.emit(.partial("qué tengo"))
        XCTAssertEqual(clock.delays.last, 1.5)

        clock.fireAll()
        XCTAssertEqual(dictation.state, .finishing)
        XCTAssertEqual(fake.stops, 1)
        fake.emit(.final("qué tengo hoy"))

        XCTAssertEqual(sent, ["qué tengo hoy"])
    }

    @MainActor
    func testEachPartialRestartsTheSilenceTimer() async throws {
        let fake = FakeSpeechRecognizer()
        let clock = ManualScheduler()
        let dictation = makeDictation(fake, clock: clock)
        dictation.toggle()
        try await waitUntil(dictation, .listening)
        fake.emit(.partial("a"))
        fake.emit(.partial("a b"))
        XCTAssertEqual(clock.pendingCount, 1)
    }

    @MainActor
    func testSilenceWithoutSpeechSendsNothing() async throws {
        let fake = FakeSpeechRecognizer()
        let clock = ManualScheduler()
        var sent: [String] = []
        let dictation = makeDictation(fake, clock: clock) { sent.append($0) }
        dictation.toggle()
        try await waitUntil(dictation, .listening)

        clock.fireAll()
        fake.emit(.final(""))

        XCTAssertTrue(sent.isEmpty)
        XCTAssertEqual(dictation.state, .idle)
    }

    @MainActor
    func testDeniedPermissionDoesNotStart() async throws {
        let fake = FakeSpeechRecognizer()
        fake.permission = .denied
        let dictation = makeDictation(fake)

        dictation.toggle()
        try await waitUntil(dictation, .denied)

        XCTAssertEqual(fake.starts, 0)
        dictation.toggle()
        XCTAssertEqual(dictation.state, .denied)
        XCTAssertEqual(fake.starts, 0)
    }

    @MainActor
    func testRecheckRecoversAfterGrantingInSettings() async throws {
        let fake = FakeSpeechRecognizer()
        fake.permission = .denied
        let dictation = makeDictation(fake)
        dictation.toggle()
        try await waitUntil(dictation, .denied)

        fake.permission = .granted
        dictation.recheckIfDenied()
        try await waitUntil(dictation, .idle)
    }

    @MainActor
    func testStartFailureShowsFailedStateAndAllowsRetry() async throws {
        let fake = FakeSpeechRecognizer()
        fake.startError = KitoSpeechError()
        let dictation = makeDictation(fake)
        dictation.toggle()
        try await waitUntil(dictation, .failed)

        fake.startError = nil
        dictation.toggle()
        try await waitUntil(dictation, .listening)
    }

    @MainActor
    func testFailureAfterSpeechKeepsWhatWasHeard() async throws {
        let fake = FakeSpeechRecognizer()
        var sent: [String] = []
        let dictation = makeDictation(fake) { sent.append($0) }
        dictation.toggle()
        try await waitUntil(dictation, .listening)
        fake.emit(.partial("hola"))
        fake.emit(.failed)
        XCTAssertEqual(sent, ["hola"])
    }

    @MainActor
    func testInterruptionDiscardsQuietly() async throws {
        let fake = FakeSpeechRecognizer()
        var sent: [String] = []
        let dictation = makeDictation(fake) { sent.append($0) }
        dictation.toggle()
        try await waitUntil(dictation, .listening)
        fake.emit(.partial("hola"))

        fake.emit(.interrupted)

        XCTAssertTrue(sent.isEmpty)
        XCTAssertEqual(dictation.state, .idle)
    }

    @MainActor
    func testOnStartFiresOnTheTapBeforeThePermission() async throws {
        let fake = FakeSpeechRecognizer()
        let dictation = makeDictation(fake)
        var started = 0
        dictation.onStart = { started += 1 }
        dictation.toggle()
        XCTAssertEqual(started, 1)
        XCTAssertEqual(dictation.state, .requesting)
    }

    // MARK: - Limpieza para voz

    func testCleanSpeechTextTable() {
        let cases: [(String, String)] = [
            ("", ""),
            ("Hola, ¿qué tal?", "Hola, ¿qué tal?"),
            ("Tienes **dos tareas** y _una_ lista.", "Tienes dos tareas y una lista."),
            ("Usa `código` aquí", "Usa código aquí."),
            ("# Hoy\nTienes reunión", "Hoy. Tienes reunión."),
            ("Esto toca:\n- Comprar pan\n- Llamar a Ana\n* Pagar", "Esto toca: Comprar pan. Llamar a Ana. Pagar."),
            ("1. Primero\n2) Segundo", "Primero. Segundo."),
            ("Hecho 🎉🙂 genial 👍🏽", "Hecho genial."),
            ("Mira https://example.com/a?b=1 ahora", "Mira ahora."),
            ("Mira www.example.com/x ahora", "Mira ahora."),
            ("Abre [el calendario](https://example.com/cal) hoy", "Abre el calendario hoy."),
            ("A las 09:30 hay cole", "A las 9 y 30 hay cole."),
            ("Cena a las 09:00", "Cena a las 9 en punto."),
            ("Vuelo 23:05", "Vuelo 23 y 5."),
            ("Hora rara 27:99", "Hora rara 27:99."),
            ("Línea uno\n\n\nLínea dos", "Línea uno. Línea dos."),
            ("snake_case y 3 * 4", "snake_case y 3 4."),
            ("> cita\n---", "cita."),
            ("   \n  ", ""),
            ("Precio 5 € ©", "Precio 5 € ©."),
        ]
        for (input, expected) in cases {
            XCTAssertEqual(KitoSpeechText.clean(input), expected, "entrada: \(input.debugDescription)")
        }
    }

    // MARK: - Regla de cuándo habla

    func testSpeechPolicy() {
        func speak(_ origen: KitoOrigen, _ mode: KitoVoiceMode, vo: Bool = false, visible: Bool = true) -> Bool {
            KitoSpeechPolicy.shouldSpeak(origen: origen, mode: mode, voiceOverOn: vo, chatVisible: visible)
        }
        XCTAssertTrue(speak(.voz, .soloSiLeHablo))
        XCTAssertFalse(speak(.texto, .soloSiLeHablo))
        XCTAssertTrue(speak(.voz, .siempre))
        XCTAssertTrue(speak(.texto, .siempre))
        XCTAssertFalse(speak(.voz, .nunca))
        XCTAssertFalse(speak(.texto, .nunca))
        XCTAssertFalse(speak(.voz, .siempre, vo: true))
        XCTAssertFalse(speak(.voz, .siempre, visible: false))
    }

    func testVoiceSettingsDefaultAndPersistence() throws {
        let name = "kito-voice-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }

        XCTAssertEqual(KitoVoiceSettings.load(defaults), .soloSiLeHablo)
        KitoVoiceSettings.save(.siempre, defaults)
        XCTAssertEqual(KitoVoiceSettings.load(defaults), .siempre)
        KitoVoiceSettings.save(.nunca, defaults)
        XCTAssertEqual(KitoVoiceSettings.load(UserDefaults(suiteName: name)!), .nunca)
        defaults.set("basura", forKey: KitoVoiceSettings.key)
        XCTAssertEqual(KitoVoiceSettings.load(defaults), .soloSiLeHablo)
        XCTAssertEqual(KitoVoiceMode.allCases.map(\.title), ["Solo si le hablo", "Siempre", "Nunca"])
    }

    // MARK: - Elección de voz

    func testVoiceChoicePrefersQualityInSpanishFromSpain() {
        typealias C = KitoVoiceCandidate
        let standard = C(identifier: "std", language: "es-ES", quality: .standard)
        let enhanced = C(identifier: "enh", language: "es-ES", quality: .enhanced)
        let premium = C(identifier: "pre", language: "es-ES", quality: .premium)
        let mexican = C(identifier: "mx", language: "es-MX", quality: .premium)
        let english = C(identifier: "en", language: "en-US", quality: .premium)

        XCTAssertEqual(KitoVoiceChoice.best(from: [standard, enhanced, premium, english])?.identifier, "pre")
        XCTAssertEqual(KitoVoiceChoice.best(from: [standard, enhanced, english])?.identifier, "enh")
        XCTAssertEqual(KitoVoiceChoice.best(from: [standard, mexican])?.identifier, "std")
        XCTAssertEqual(KitoVoiceChoice.best(from: [english, mexican])?.identifier, "mx")
        XCTAssertNil(KitoVoiceChoice.best(from: [english]))
        XCTAssertNil(KitoVoiceChoice.best(from: []))
        XCTAssertEqual(KitoVoiceChoice.best(from: [C(identifier: "u", language: "es_ES", quality: .standard)])?.identifier, "u")
    }

    // MARK: - Store con voz

    private var directory = FileManager.default.temporaryDirectory.appendingPathComponent("kito-voice-\(UUID().uuidString)")

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    @MainActor
    private func makeStore(
        _ speaker: FakeSpeaker,
        mode: KitoVoiceMode = .soloSiLeHablo,
        voiceOver: Bool = false
    ) -> KitoStore {
        let client = APIClient(
            baseURL: URL(string: "https://test.supabase.co/functions/v1")!,
            session: StubURLProtocol.session(),
            tokenProvider: { "test-access" },
            homeIdProvider: { "7" },
            readCache: ReadCache(directory: directory.appendingPathComponent("cache"))
        )
        return KitoStore(
            api: KitoAPI(client: client),
            historyStore: KitoHistoryStore(directory: directory.appendingPathComponent("kito")),
            userId: 1, homeId: "7", timezone: { "UTC" },
            speaker: speaker, voiceMode: { mode }, isVoiceOverRunning: { voiceOver }
        )
    }

    private func stubReply(_ text: String = "Tienes **dos** tareas a las 09:30.") {
        let json = #"{"texto":"\#(text)"}"#
        StubURLProtocol.reset { _ in StubURLProtocol.Stub(json: json) }
    }

    @MainActor
    func testDictatedMessageGetsASpokenReplyWithCleanText() async {
        stubReply()
        let speaker = FakeSpeaker()
        let store = makeStore(speaker)
        await store.send("¿qué tengo?", origen: .voz)
        XCTAssertEqual(speaker.spoken.map(\.text), ["Tienes dos tareas a las 9 y 30."])
        XCTAssertEqual(speaker.spoken.first?.id, store.messages.last?.id)
        XCTAssertEqual(store.speakingId, store.messages.last?.id)
    }

    @MainActor
    func testTypedMessageGetsNoSpeechInTheDefaultMode() async {
        stubReply()
        let speaker = FakeSpeaker()
        let store = makeStore(speaker)
        await store.send("¿qué tengo?")
        XCTAssertTrue(speaker.spoken.isEmpty)
    }

    @MainActor
    func testAlwaysAndNeverModes() async {
        stubReply()
        let always = FakeSpeaker()
        await makeStore(always, mode: .siempre).send("hola")
        XCTAssertEqual(always.spoken.count, 1)

        let never = FakeSpeaker()
        await makeStore(never, mode: .nunca).send("hola", origen: .voz)
        XCTAssertTrue(never.spoken.isEmpty)
    }

    @MainActor
    func testVoiceOverDisablesAutomaticSpeechButNotTheManualButton() async throws {
        stubReply()
        let speaker = FakeSpeaker()
        let store = makeStore(speaker, mode: .siempre, voiceOver: true)
        await store.send("hola", origen: .voz)
        XCTAssertTrue(speaker.spoken.isEmpty)

        store.toggleSpeech(for: try XCTUnwrap(store.messages.last))
        XCTAssertEqual(speaker.spoken.count, 1)
    }

    @MainActor
    func testClearWhileSendingNeverSpeaksTheLateReply() async throws {
        StubURLProtocol.reset { _ in
            Thread.sleep(forTimeInterval: 0.3)
            return StubURLProtocol.Stub(json: #"{"texto":"tarde"}"#)
        }
        let speaker = FakeSpeaker()
        let store = makeStore(speaker, mode: .siempre)
        let task = Task { await store.send("hola", origen: .voz) }
        while !store.isSending { try await Task.sleep(nanoseconds: 10_000_000) }

        store.clearConversation()
        await task.value

        XCTAssertTrue(speaker.spoken.isEmpty)
    }

    @MainActor
    func testNetworkFailureSpeaksNothing() async {
        StubURLProtocol.reset { _ in StubURLProtocol.Stub(status: 502, json: #"{"error":"x"}"#) }
        let speaker = FakeSpeaker()
        await makeStore(speaker, mode: .siempre).send("hola", origen: .voz)
        XCTAssertTrue(speaker.spoken.isEmpty)
    }

    @MainActor
    func testStartingDictationAndClosingTheChatStopTheVoice() async {
        stubReply()
        let speaker = FakeSpeaker()
        let store = makeStore(speaker, mode: .siempre)
        await store.send("hola")
        XCTAssertNotNil(store.speakingId)

        store.dictationDidStart()
        XCTAssertNil(store.speakingId)
        let stopsAfterDictation = speaker.stops
        XCTAssertGreaterThanOrEqual(stopsAfterDictation, 1)

        store.chatDidClose()
        XCTAssertGreaterThan(speaker.stops, stopsAfterDictation)
    }

    @MainActor
    func testRepliesArrivingWithTheChatClosedAreNotSpoken() async {
        stubReply()
        let speaker = FakeSpeaker()
        let store = makeStore(speaker, mode: .siempre)
        store.chatDidClose()
        await store.send("hola", origen: .voz)
        XCTAssertTrue(speaker.spoken.isEmpty)

        store.chatDidOpen()
        await store.send("otra", origen: .voz)
        XCTAssertEqual(speaker.spoken.count, 1)
    }

    @MainActor
    func testSpeakerButtonTogglesAndSwitchesBetweenReplies() async throws {
        StubURLProtocol.reset { _ in StubURLProtocol.Stub(json: #"{"texto":"Respuesta."}"#) }
        let speaker = FakeSpeaker()
        let store = makeStore(speaker, mode: .nunca)
        await store.send("uno")
        await store.send("dos")
        let first = try XCTUnwrap(store.messages.first { $0.role == .assistant })
        let second = try XCTUnwrap(store.messages.last { $0.role == .assistant })

        store.toggleSpeech(for: first)
        XCTAssertEqual(store.speakingId, first.id)
        store.toggleSpeech(for: second)
        XCTAssertEqual(store.speakingId, second.id)
        XCTAssertEqual(speaker.spoken.count, 2)
        store.toggleSpeech(for: second)
        XCTAssertNil(store.speakingId)
    }

    @MainActor
    func testClearConversationStopsTheVoice() async {
        stubReply()
        let speaker = FakeSpeaker()
        let store = makeStore(speaker, mode: .siempre)
        await store.send("hola")
        store.clearConversation()
        XCTAssertNil(store.speakingId)
    }
}
