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
}
