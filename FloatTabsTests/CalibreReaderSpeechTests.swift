import WebKit
import XCTest
@testable import FloatTabs

@MainActor
private final class CalibreTestSpeechService: SpeechSynthesizing {
    private(set) var spokenRequests: [SpeechPlaybackRequest] = []
    private(set) var pauseCount = 0
    private(set) var resumeCount = 0
    private(set) var stopCount = 0
    var finishDuringPause = false

    var onUtteranceStarted: ((UInt64) -> Void)?
    var onUtteranceFinished: ((UInt64) -> Void)?
    var onUtterancePaused: ((UInt64) -> Void)?
    var onUtteranceContinued: ((UInt64) -> Void)?
    var onUtteranceCancelled: ((UInt64) -> Void)?

    func speak(_ request: SpeechPlaybackRequest) {
        spokenRequests.append(request)
    }

    func pause() -> Bool {
        pauseCount += 1
        if finishDuringPause,
           let token = spokenRequests.last?.transportToken {
            onUtteranceFinished?(token)
        }
        return true
    }

    func resume() -> Bool {
        resumeCount += 1
        return true
    }
    func stop() { stopCount += 1 }

    func emitStart() {
        guard let token = spokenRequests.last?.transportToken else { return }
        emitStart(token: token)
    }

    func emitFinish() {
        guard let token = spokenRequests.last?.transportToken else { return }
        emitFinish(token: token)
    }

    func emitStart(token: UInt64) {
        onUtteranceStarted?(token)
    }

    func emitFinish(token: UInt64) {
        onUtteranceFinished?(token)
    }

    func emitPause(token: UInt64) {
        onUtterancePaused?(token)
    }

    func emitContinue(token: UInt64) {
        onUtteranceContinued?(token)
    }

    func emitCancel(token: UInt64) {
        onUtteranceCancelled?(token)
    }
}

@MainActor
private final class CalibreTestReaderBridge: CalibreReaderAccess {
    let slotID: UUID
    var currentDocumentIdentity: CalibreReaderDocumentIdentity?
    var isReaderCandidate = true
    var onRelocation: ((CalibreReaderRelocation) -> Void)?
    var currentPage: CalibreReaderPage
    private(set) var extractionCount = 0
    private(set) var advanceCount = 0
    var deferNextExtraction = false
    var deferAdvanceFailure = false
    private var pendingExtraction: ((Result<CalibreReaderPage, Error>) -> Void)?
    private var pendingAdvanceFailure: (() -> Void)?

    init(slotID: UUID, pages: [CalibreReaderPage]) {
        self.slotID = slotID
        self.currentPage = pages[0]
        self.currentDocumentIdentity = pages[0].identity.document
    }

    func detectCurrentReader(completion: @escaping (Bool) -> Void) {
        completion(isReaderCandidate)
    }

    func extractCurrentReadingUnit(
        completion: @escaping (Result<CalibreReaderPage, Error>) -> Void
    ) {
        extractionCount += 1
        if deferNextExtraction {
            deferNextExtraction = false
            pendingExtraction = completion
        } else {
            completion(.success(currentPage))
        }
    }

    func requestAdvance(
        from identity: CalibreReadingUnitIdentity,
        transitionToken: UInt64,
        completion: @escaping (Bool) -> Void
    ) {
        guard identity == currentPage.identity else {
            completion(false)
            return
        }
        advanceCount += 1
        if deferAdvanceFailure {
            completion(true)
            pendingAdvanceFailure = {
                completion(false)
            }
        } else {
            completion(true)
        }
    }

    func cancelPendingWork() {
        pendingExtraction = nil
        pendingAdvanceFailure = nil
    }

    func resolvePendingExtraction() {
        let extraction = pendingExtraction
        pendingExtraction = nil
        extraction?(.success(currentPage))
    }

    func emitAdvanceFailure() {
        let failure = pendingAdvanceFailure
        pendingAdvanceFailure = nil
        failure?()
    }

    func emitRelocation(
        _ page: CalibreReaderPage,
        token: UInt64? = nil
    ) {
        currentPage = page
        currentDocumentIdentity = page.identity.document
        onRelocation?(
            CalibreReaderRelocation(
                identity: page.identity,
                transitionToken: token
            )
        )
    }
}

@MainActor
private final class CalibreTestWatchdogScheduler: CalibreSpeechWatchdogScheduling {
    final class Task {
        let operation: @MainActor () -> Void
        var isCancelled = false

        init(operation: @escaping @MainActor () -> Void) {
            self.operation = operation
        }
    }

    private(set) var tasks: [Task] = []

    func schedule(
        after delay: TimeInterval,
        operation: @escaping @MainActor () -> Void
    ) -> AnyObject {
        let task = Task(operation: operation)
        tasks.append(task)
        return task
    }

    func cancel(_ task: AnyObject) {
        (task as? Task)?.isCancelled = true
    }

    func fireLatestIgnoringCancellation() {
        tasks.last?.operation()
    }
}

@MainActor
private final class CalibreReaderPageHarness {
    let webView: WKWebView
    let bridge: CalibreReaderBridge
    let url = URL(string: "https://reader.example.test/read/7/epub")!

    init() {
        let bridge = CalibreReaderBridge(slotID: UUID())
        let configuration = WKWebViewConfiguration()
        bridge.install(into: configuration.userContentController)
        let webView = WKWebView(
            frame: CGRect(x: 0, y: 0, width: 800, height: 600),
            configuration: configuration
        )
        bridge.attach(to: webView)
        self.bridge = bridge
        self.webView = webView
    }

    func load(readerInitiallyReady: Bool) {
        let package = readerInitiallyReady ? "{}" : "null"
        let opened = readerInitiallyReady
            ? "Promise.resolve()"
            : "new Promise((resolve) => { window.__resolveCalibreOpened = resolve; })"
        webView.loadHTMLString(
            """
            <!doctype html>
            <html><body><script>
              window.__calibrePageText = 'First page.';
              window.__calibreLocation = {
                start: { cfi: 'a' },
                end: { cfi: 'b' }
              };
              window.__calibreRelocationHandlers = [];
              window.__calibreQueue = {
                length: () => window.__calibreQueueLength || 0,
                running: false,
                paused: false
              };
              window.__calibreSetLocation = (startCFI, endCFI, text) => {
                window.__calibreLocation = {
                  start: { cfi: startCFI },
                  end: { cfi: endCFI }
                };
                document.getElementById('calibre-text').textContent = text;
              };
              window.reader = {
                book: {
                  package: \(package),
                  opened: \(opened),
                  renderer: { document: document }
                },
                rendition: {
                  q: window.__calibreQueue,
                  currentLocation: () => window.__calibreLocation,
                  getContents: () => [{ document: document }],
                  next: () => Promise.resolve(),
                  on: (event, handler) => {
                    if (event === 'relocated') {
                      window.__calibreRelocationHandlers.push(handler);
                    }
                  }
                },
                calibre: {}
              };
              window.ePub = {
                CFI: function() {
                  this.toRange = (doc) => {
                    const node = doc.getElementById('calibre-text').firstChild;
                    const range = doc.createRange();
                    range.setStart(node, 0);
                    range.setEnd(node, node.length);
                    return range;
                  };
                }
              };
              if (!window.__resolveCalibreOpened) {
                window.__resolveCalibreOpened = () => {};
              }
            </script><p id="calibre-text">First page.</p></body></html>
            """,
            baseURL: url
        )
    }

    func run(_ javascript: String) async -> Any? {
        await withCheckedContinuation { continuation in
            webView.evaluateJavaScript(
                javascript,
                in: nil,
                in: CalibreReaderBridge.contentWorld
            ) { result in
                switch result {
                case let .success(value):
                    continuation.resume(returning: value)
                case .failure:
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    func waitFor(
        _ condition: @escaping @MainActor () -> Bool,
        timeout: TimeInterval = 5
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return condition()
    }

    func waitForPageFlag(
        _ javascript: String,
        timeout: TimeInterval = 5
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await (run(javascript) as? Bool) == true { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return (await run(javascript) as? Bool) == true
    }

    func setQueueBusy(_ busy: Bool) async {
        _ = await run("window.__calibreQueueLength = \(busy ? 1 : 0); window.__calibreQueue.running = \(busy ? "true" : "false"); true")
    }

    func emitRenditionRelocation(
        _ page: CalibreReaderPage
    ) async {
        let start = jsonString(page.identity.startCFI)
        let end = jsonString(page.identity.endCFI)
        let text = jsonString(page.text)
        _ = await run(
            """
            (() => {
                window.__calibreSetLocation(\(start), \(end), \(text));
                window.__calibreRelocationHandlers.forEach((handler) => handler(window.__calibreLocation));
                return true;
            })()
            """
        )
    }

    func emitGenericRelocation(
        _ page: CalibreReaderPage,
        generation: UInt64 = 1
    ) async {
        let start = jsonString(page.identity.startCFI)
        let end = jsonString(page.identity.endCFI)
        let text = jsonString(page.text)
        let handler = jsonString(CalibreReaderBridge.messageHandlerName)
        _ = await run(
            """
            (() => {
                window.__calibreSetLocation(\(start), \(end), \(text));
                const handler = window.webkit.messageHandlers[\(handler)];
                handler.postMessage({
                    event: 'relocated',
                    generation: \(generation),
                    startCFI: \(start),
                    endCFI: \(end)
                });
                return true;
            })()
            """
        )
    }

    func postSourceAck(
        generation: UInt64,
        transitionToken: UInt64,
        fromStartCFI: String,
        fromEndCFI: String,
        startCFI: String,
        endCFI: String
    ) async {
        let handler = jsonString(CalibreReaderBridge.messageHandlerName)
        let fromStart = jsonString(fromStartCFI)
        let fromEnd = jsonString(fromEndCFI)
        let start = jsonString(startCFI)
        let end = jsonString(endCFI)
        _ = await run(
            """
            window.webkit.messageHandlers[\(handler)].postMessage({
                event: 'sourceAdvanceRelocated',
                generation: \(generation),
                transitionToken: \(transitionToken),
                fromStartCFI: \(fromStart),
                fromEndCFI: \(fromEnd),
                startCFI: \(start),
                endCFI: \(end)
            }); true
            """
        )
    }

    private func jsonString(_ value: String) -> String {
        let data = try! JSONEncoder().encode(value)
        return String(data: data, encoding: .utf8)!
    }
}

@MainActor
private final class CalibreStubSpeechSource: SpeechSourceAdapter {
    let kind: SpeechSourceKind = .chatGPT
    let slotID: UUID
    var readCount = 0
    var globalStopCount = 0
    var presentation: SpeechSourcePresentation {
        SpeechSourcePresentation(
            sourceKind: kind,
            activeSlotID: slotID,
            autoSpeakSlotIDs: [],
            activeSlotAutoSpeakEnabled: false,
            currentSpeakingSlotID: nil,
            playbackState: .idle,
            activeSlotSupportsSpeech: true
        )
    }

    init(slotID: UUID) { self.slotID = slotID }
    func supportsSpeech(slotID: UUID) -> Bool { slotID == self.slotID }
    func isAutoSpeakArmed(slotID: UUID) -> Bool { false }
    func readLatest(slotID: UUID) -> Bool { readCount += 1; return true }
    func replayLatest(slotID: UUID) -> Bool { true }
    func pause(slotID: UUID) -> Bool { false }
    func resume(slotID: UUID) -> Bool { false }
    func stop(slotID: UUID) -> Bool { false }
    func stopCurrentPlayback() -> Bool { globalStopCount += 1; return true }
    func toggleAutoSpeak(slotID: UUID) -> Bool { false }
    func playPreview(_ requests: [SpeechUtteranceRequest]) {}
}

@MainActor
private final class CalibreTestResponseBridge: ChatGPTResponseExtracting {
    private var completions: [@MainActor (ChatGPTResponsePayload?) -> Void] = []

    var requestCount: Int { completions.count }

    func extractLatest(completion: @escaping @MainActor (ChatGPTResponsePayload?) -> Void) {
        completions.append(completion)
    }

    func resolve(_ payload: ChatGPTResponsePayload?) {
        guard !completions.isEmpty else { return }
        completions.removeFirst()(payload)
    }
}

@MainActor
final class CalibreReaderSpeechTests: XCTestCase {
    private let slotID = UUID()

    private func document(generation: UInt64 = 1) -> CalibreReaderDocumentIdentity {
        let url = URL(string: "https://reader.example.test/read/7/epub")!
        return CalibreReaderDocumentIdentity(
            slotID: slotID,
            documentGeneration: generation,
            committedURL: url,
            origin: URL(string: "https://reader.example.test")!,
            readerKind: .epub
        )
    }

    private func page(
        document: CalibreReaderDocumentIdentity,
        start: String,
        end: String,
        text: String,
        atEnd: Bool = false
    ) -> CalibreReaderPage {
        CalibreReaderPage(
            identity: CalibreReadingUnitIdentity(
                document: document,
                startCFI: start,
                endCFI: end
            ),
            text: text,
            isAtEnd: atEnd
        )
    }

    private func makeCoordinator(
        bridge: CalibreReaderAccess,
        service: CalibreTestSpeechService,
        watchdogScheduler: CalibreSpeechWatchdogScheduling? = nil
    ) -> (CalibreSpeechCoordinator, SpeechPlaybackSessionController) {
        let session = SpeechPlaybackSessionController(speechService: service)
        let coordinator: CalibreSpeechCoordinator
        if let watchdogScheduler {
            coordinator = CalibreSpeechCoordinator(
                playbackSession: session,
                bridgeProvider: { id in id == bridge.slotID ? bridge : nil },
                watchdogScheduler: watchdogScheduler
            )
        } else {
            coordinator = CalibreSpeechCoordinator(
                playbackSession: session,
                bridgeProvider: { id in id == bridge.slotID ? bridge : nil }
            )
        }
        _ = CalibreSpeechSourceAdapter(
            coordinator: coordinator,
            playbackSession: session,
            activeSlotIDProvider: { bridge.slotID }
        )
        return (coordinator, session)
    }

    func testRouteMatcherAcceptsOnlyEPUBAndKEPUBReaderTail() {
        XCTAssertEqual(
            CalibreReaderRouteMatcher.readerKind(
                for: URL(string: "https://host.test/prefix/read/42/epub?x=1")
            ),
            .epub
        )
        XCTAssertEqual(
            CalibreReaderRouteMatcher.readerKind(
                for: URL(string: "http://host.test/read/42/kepub")
            ),
            .kepub
        )
        XCTAssertNil(CalibreReaderRouteMatcher.readerKind(
            for: URL(string: "https://host.test/read/42/pdf")
        ))
        XCTAssertNil(CalibreReaderRouteMatcher.readerKind(
            for: URL(string: "https://host.test/read/42/epub/extra")
        ))
        XCTAssertNil(CalibreReaderRouteMatcher.readerKind(
            for: URL(string: "https://host.test/read/no-id/epub")
        ))
    }

    func testCommittedOriginContainsOnlySchemeHostAndPort() {
        XCTAssertEqual(
            CalibreReaderRouteMatcher.committedOrigin(
                for: URL(string: "HTTPS://Reader.Example:8443/read/1/epub?q=1")!
            ),
            URL(string: "https://reader.example:8443")
        )
    }

    func testCalibreTextNormalizationPreservesBookContentAndLineBreaks() {
        XCTAssertEqual(
            CalibreReaderTextNormalizer.normalize(
                "  First\u{00AD} line  \r\n\tSecond\u{200B} line.  "
            ),
            "First line\nSecond line."
        )
    }

    func testReaderCandidateMustBeRuntimeBackedBeforeAcquiringLease() {
        let doc = document()
        let first = page(document: doc, start: "a", end: "b", text: "Page.")
        let bridge = CalibreTestReaderBridge(slotID: slotID, pages: [first])
        bridge.isReaderCandidate = false
        let service = CalibreTestSpeechService()
        let (coordinator, session) = makeCoordinator(bridge: bridge, service: service)

        XCTAssertFalse(coordinator.readCurrentPage(slotID: slotID))
        XCTAssertNil(session.activeSourceSessionKind)
        XCTAssertEqual(coordinator.state, .idle)
    }

    func testCalibrePresentationUsesPageSemanticsAndDisablesAutoSpeak() {
        let doc = document()
        let first = page(document: doc, start: "a", end: "b", text: "Page.")
        let bridge = CalibreTestReaderBridge(slotID: slotID, pages: [first])
        let service = CalibreTestSpeechService()
        let session = SpeechPlaybackSessionController(speechService: service)
        let coordinator = CalibreSpeechCoordinator(
            playbackSession: session,
            bridgeProvider: { id in id == self.slotID ? bridge : nil }
        )
        let adapter = CalibreSpeechSourceAdapter(
            coordinator: coordinator,
            playbackSession: session,
            activeSlotIDProvider: { self.slotID }
        )

        XCTAssertEqual(adapter.presentation.capabilities, .calibreReader)
        XCTAssertTrue(adapter.presentation.activeSlotSupportsSpeech)
        XCTAssertFalse(adapter.presentation.capabilities.canAutoSpeak)
        XCTAssertEqual(adapter.presentation.labels.read, "Read From Current Page")
        XCTAssertEqual(adapter.presentation.labels.replay, "Replay Current Page")
    }

    func testSourceLeaseIsIndependentFromTransportAndRejectsForeignOwner() {
        let service = CalibreTestSpeechService()
        let session = SpeechPlaybackSessionController(speechService: service)
        let owner = UUID()
        let other = UUID()
        let token = session.acquireSourceSession(
            sourceKind: .calibreReader,
            slotID: owner
        )

        XCTAssertNotNil(token)
        XCTAssertEqual(
            session.acquireSourceSession(sourceKind: .calibreReader, slotID: owner),
            token
        )
        XCTAssertNil(session.acquireSourceSession(sourceKind: .chatGPT, slotID: other))
        XCTAssertEqual(session.playbackState, .idle)
        session.releaseSourceSession(sourceKind: .calibreReader, token: token)
        XCTAssertNil(session.activeSourceSessionKind)
    }

    func testPauseWhenInactiveSuspendsAtBoundaryWithoutAutoAdvancing() {
        let doc = document()
        let first = page(
            document: doc,
            start: "a",
            end: "b",
            text: "English sentence. 中文句子。"
        )
        let second = page(document: doc, start: "c", end: "d", text: "Next page.")
        let bridge = CalibreTestReaderBridge(slotID: slotID, pages: [first, second])
        let service = CalibreTestSpeechService()
        let (coordinator, session) = makeCoordinator(bridge: bridge, service: service)
        let firstToken = try! XCTUnwrap({
            XCTAssertTrue(coordinator.readCurrentPage(slotID: slotID))
            return service.spokenRequests.first?.transportToken
        }())

        service.emitStart(token: firstToken)
        coordinator.handleBackgroundMediaPolicyChange(
            slotID: slotID,
            policy: .pauseWhenInactive,
            isInactive: true
        )
        XCTAssertEqual(coordinator.state, .suspended)
        XCTAssertFalse(coordinator.isSpeechRuntimeProtectionActive)
        XCTAssertFalse(coordinator.hasActiveSourceSession)
        XCTAssertNil(session.activeSourceSessionKind)
        XCTAssertEqual(service.pauseCount, 1)

        // The accepted pause transaction may settle through a finish callback;
        // it must remain source-suspended at the boundary.
        service.emitFinish(token: firstToken)
        XCTAssertEqual(coordinator.state, .suspended)
        XCTAssertEqual(service.spokenRequests.count, 1)
        XCTAssertEqual(bridge.advanceCount, 0)
        XCTAssertNil(session.activeSourceSessionKind)

        XCTAssertTrue(coordinator.resume(slotID: slotID))
        XCTAssertEqual(service.resumeCount, 0)
        XCTAssertEqual(service.spokenRequests.count, 2)
        XCTAssertEqual(coordinator.state, .speakingUnit)
        XCTAssertEqual(bridge.advanceCount, 0)
    }

    func testPauseWhenInactiveSuspendsAcceptedRelocationBeforeNextPageSpeech() {
        let doc = document()
        let first = page(document: doc, start: "a", end: "b", text: "First page.")
        let second = page(document: doc, start: "c", end: "d", text: "Second page.")
        let bridge = CalibreTestReaderBridge(slotID: slotID, pages: [first, second])
        let service = CalibreTestSpeechService()
        let (coordinator, _) = makeCoordinator(bridge: bridge, service: service)

        XCTAssertTrue(coordinator.readCurrentPage(slotID: slotID))
        service.emitStart()
        service.emitFinish()
        XCTAssertEqual(coordinator.state, .awaitingRelocation)
        XCTAssertEqual(service.spokenRequests.count, 1)

        coordinator.handleBackgroundMediaPolicyChange(
            slotID: slotID,
            policy: .pauseWhenInactive,
            isInactive: true
        )
        XCTAssertEqual(coordinator.state, .suspended)
        XCTAssertFalse(coordinator.isSpeechRuntimeProtectionActive)

        bridge.emitRelocation(second, token: 1)
        XCTAssertEqual(coordinator.state, .suspended)
        XCTAssertEqual(service.spokenRequests.count, 1)
        XCTAssertEqual(bridge.currentPage.identity, second.identity)

        // Resume is the only admission point after the inactive suspension.
        XCTAssertTrue(coordinator.resume(slotID: slotID))
        XCTAssertEqual(service.spokenRequests.count, 2)
        XCTAssertEqual(service.spokenRequests.last?.text, "Second page.")
    }

    func testAllowBackgroundAudioDoesNotAutoResumeASuspendedCalibreSource() {
        let doc = document()
        let first = page(document: doc, start: "a", end: "b", text: "First page.")
        let bridge = CalibreTestReaderBridge(slotID: slotID, pages: [first])
        let service = CalibreTestSpeechService()
        let (coordinator, _) = makeCoordinator(bridge: bridge, service: service)

        XCTAssertTrue(coordinator.readCurrentPage(slotID: slotID))
        let token = try! XCTUnwrap(service.spokenRequests.first?.transportToken)
        service.emitStart(token: token)
        coordinator.handleBackgroundMediaPolicyChange(
            slotID: slotID,
            policy: .pauseWhenInactive,
            isInactive: true
        )
        service.emitFinish(token: token)

        coordinator.handleBackgroundMediaPolicyChange(
            slotID: slotID,
            policy: .allowBackgroundAudio,
            isInactive: true
        )
        XCTAssertEqual(coordinator.state, .suspended)
        XCTAssertEqual(service.spokenRequests.count, 1)
        XCTAssertFalse(coordinator.isSpeechRuntimeProtectionActive)
    }

    func testManualPausedBoundaryDoesNotProtectInactiveWebViewRuntime() {
        let doc = document()
        let first = page(document: doc, start: "a", end: "b", text: "First page.")
        let bridge = CalibreTestReaderBridge(slotID: slotID, pages: [first])
        let service = CalibreTestSpeechService()
        let (coordinator, _) = makeCoordinator(bridge: bridge, service: service)

        XCTAssertTrue(coordinator.readCurrentPage(slotID: slotID))
        service.emitStart()
        XCTAssertTrue(coordinator.pause(slotID: slotID))
        service.emitFinish()

        XCTAssertEqual(coordinator.state, .speakingUnit)
        XCTAssertFalse(coordinator.hasActiveSourceSession)
        XCTAssertTrue(coordinator.hasResumableState(slotID: slotID))
        XCTAssertFalse(coordinator.isSpeechRuntimeProtectionActive)
    }

    func testManualPauseWithAllowBackgroundAudioStopsProtectingRuntime() {
        let doc = document()
        let first = page(
            document: doc,
            start: "a",
            end: "b",
            text: "English sentence. 中文句子。"
        )
        let bridge = CalibreTestReaderBridge(slotID: slotID, pages: [first])
        let service = CalibreTestSpeechService()
        let (coordinator, session) = makeCoordinator(bridge: bridge, service: service)

        XCTAssertTrue(coordinator.readCurrentPage(slotID: slotID))
        let token = try! XCTUnwrap(service.spokenRequests.first?.transportToken)
        service.emitStart(token: token)
        XCTAssertTrue(coordinator.pause(slotID: slotID))
        service.emitPause(token: token)

        XCTAssertEqual(session.playbackState, .idle)
        XCTAssertEqual(coordinator.state, .speakingUnit)
        XCTAssertFalse(coordinator.hasActiveSourceSession)
        XCTAssertNil(session.activeContext)
        XCTAssertTrue(coordinator.hasResumableState(slotID: slotID))
        XCTAssertFalse(coordinator.isSpeechRuntimeProtectionActive)

        XCTAssertTrue(coordinator.resume(slotID: slotID))
        XCTAssertEqual(service.spokenRequests.count, 2)
        XCTAssertEqual(service.spokenRequests[1].text, service.spokenRequests[0].text)
        XCTAssertEqual(session.activeSourceSessionKind, .calibreReader)

        coordinator.prepareForRuntimeRelease(slotID: slotID)
        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertNil(session.activeSourceSessionKind)
        XCTAssertNil(bridge.onRelocation)
        XCTAssertGreaterThan(service.stopCount, 0)
    }

    func testManualPauseAtSegmentBoundaryYieldsAuthorityAndResumesNextSegment() {
        let doc = document()
        let first = page(
            document: doc,
            start: "a",
            end: "b",
            text: "English sentence. 中文句子。"
        )
        let bridge = CalibreTestReaderBridge(slotID: slotID, pages: [first])
        let service = CalibreTestSpeechService()
        service.finishDuringPause = true
        let (coordinator, session) = makeCoordinator(bridge: bridge, service: service)
        let requests = SpeechLanguageRouter.utteranceRequests(for: first.text)
        XCTAssertGreaterThanOrEqual(requests.count, 2)

        XCTAssertTrue(coordinator.readCurrentPage(slotID: slotID))
        service.emitStart()
        XCTAssertTrue(coordinator.pause(slotID: slotID))

        XCTAssertEqual(coordinator.state, .pausedAtBoundary)
        XCTAssertFalse(coordinator.hasActiveSourceSession)
        XCTAssertNil(session.activeContext)
        XCTAssertTrue(coordinator.hasResumableState(slotID: slotID))
        XCTAssertFalse(coordinator.isSpeechRuntimeProtectionActive)

        XCTAssertTrue(coordinator.resume(slotID: slotID))
        XCTAssertEqual(service.spokenRequests.count, 2)
        XCTAssertEqual(service.spokenRequests[1].text, requests[1].text)
        XCTAssertEqual(session.activeSourceSessionKind, .calibreReader)
        XCTAssertEqual(coordinator.state, .speakingUnit)
    }

    func testManualCalibrePauseYieldsToChatGPTAutoSpeakUnderBothBackgroundPolicies() {
        for policy in [BackgroundMediaPolicy.allowBackgroundAudio,
                       .pauseWhenInactive] {
            let doc = document()
            let first = page(
                document: doc,
                start: "a",
                end: "b",
                text: "Calibre sentence. 中文句子。"
            )
            let bridge = CalibreTestReaderBridge(slotID: slotID, pages: [first])
            let service = CalibreTestSpeechService()
            let session = SpeechPlaybackSessionController(speechService: service)
            let calibreCoordinator = CalibreSpeechCoordinator(
                playbackSession: session,
                bridgeProvider: { id in id == self.slotID ? bridge : nil }
            )
            let chatSlot = UUID()
            var activeSlot = slotID
            _ = CalibreSpeechSourceAdapter(
                coordinator: calibreCoordinator,
                playbackSession: session,
                activeSlotIDProvider: { activeSlot }
            )
            let responseBridge = CalibreTestResponseBridge()
            let chatWebView = WKWebView(frame: .zero)
            let chatCoordinator = AssistantSpeechCoordinator(
                playbackSession: session,
                webViewProvider: { _ in chatWebView },
                responseBridgeProvider: { _ in responseBridge },
                automaticSpeechSuppressed: { _ in
                    session.activeSourceSessionKind != nil
                }
            )
            _ = ChatGPTSpeechSourceAdapter(
                coordinator: chatCoordinator,
                playbackSession: session,
                activeSlotIDProvider: { activeSlot },
                supportsSpeechQuery: { $0 == chatSlot }
            )

            chatCoordinator.toggleAutoSpeak(for: chatSlot)
            XCTAssertTrue(calibreCoordinator.readCurrentPage(slotID: slotID))
            service.emitStart()
            XCTAssertTrue(calibreCoordinator.pause(slotID: slotID))
            if policy == .pauseWhenInactive {
                calibreCoordinator.handleBackgroundMediaPolicyChange(
                    slotID: slotID,
                    policy: policy,
                    isInactive: true
                )
            }

            XCTAssertNil(session.activeSourceSessionKind)
            XCTAssertFalse(calibreCoordinator.isSpeechRuntimeProtectionActive)
            XCTAssertTrue(calibreCoordinator.hasResumableState(slotID: slotID))

            activeSlot = chatSlot
            chatCoordinator.handle(.generationFinished, for: chatSlot)
            responseBridge.resolve(
                ChatGPTResponsePayload(
                    version: ChatGPTResponsePayload.currentVersion,
                    kind: .response,
                    requestID: "request-chat-12345678",
                    documentToken: "document-chat-12345678",
                    responseID: "document-chat-12345678:response-chat",
                    blocks: [SpeechContentBlock(
                        kind: .paragraph,
                        text: "ChatGPT automatic response.",
                        level: nil
                    )]
                )
            )

            XCTAssertEqual(service.spokenRequests.count, 2)
            XCTAssertEqual(service.spokenRequests.last?.text, "ChatGPT automatic response.")
            XCTAssertEqual(session.activeContext?.sourceKind, .chatGPT)
            XCTAssertEqual(session.activeContext?.slotID, chatSlot)
            XCTAssertEqual(session.playbackState, .starting)
        }
    }

    func testScopedStopClearsYieldedCalibreStateWithoutStoppingForeignChatGPT() {
        let doc = document()
        let first = page(document: doc, start: "a", end: "b", text: "Calibre page.")
        let bridge = CalibreTestReaderBridge(slotID: slotID, pages: [first])
        let service = CalibreTestSpeechService()
        let session = SpeechPlaybackSessionController(speechService: service)
        let calibreCoordinator = CalibreSpeechCoordinator(
            playbackSession: session,
            bridgeProvider: { id in id == self.slotID ? bridge : nil }
        )
        let chatSlot = UUID()
        let calibreSource = CalibreSpeechSourceAdapter(
            coordinator: calibreCoordinator,
            playbackSession: session,
            activeSlotIDProvider: { self.slotID }
        )
        let foreignSource = CalibreStubSpeechSource(slotID: chatSlot)
        var activeSlot = slotID
        let router = SpeechCommandRouter(
            sources: [calibreSource, foreignSource],
            playbackSession: session,
            activeSlotIDProvider: { activeSlot }
        )

        XCTAssertTrue(calibreCoordinator.readCurrentPage(slotID: slotID))
        service.emitStart()
        XCTAssertTrue(calibreCoordinator.pause(slotID: slotID))
        XCTAssertNil(session.activeContext)
        XCTAssertNil(session.activeSourceSessionKind)

        let foreignContext = SpeechPlaybackContext(
            sourceKind: .chatGPT,
            slotID: chatSlot,
            sourceSequence: 1,
            origin: .automatic
        )
        XCTAssertTrue(session.speak(
            context: foreignContext,
            text: "ChatGPT speech.",
            languageRole: .english
        ))
        service.emitStart(token: session.activeTransportToken!)
        activeSlot = slotID

        XCTAssertEqual(
            router.stopForActiveSlot(),
            .stopped(sourceKind: .calibreReader, slotID: slotID)
        )
        XCTAssertEqual(calibreCoordinator.state, .idle)
        XCTAssertEqual(session.activeContext, foreignContext)
        XCTAssertEqual(session.playbackState, .speaking)
        XCTAssertEqual(foreignSource.globalStopCount, 0)
    }

    func testRouterResumeContinuesSuspendedCalibreFromSafeSegmentBoundary() {
        let doc = document()
        let first = page(
            document: doc,
            start: "a",
            end: "b",
            text: "English sentence. 中文句子。"
        )
        let bridge = CalibreTestReaderBridge(slotID: slotID, pages: [first])
        let service = CalibreTestSpeechService()
        let (coordinator, session) = makeCoordinator(bridge: bridge, service: service)
        let source = CalibreSpeechSourceAdapter(
            coordinator: coordinator,
            playbackSession: session,
            activeSlotIDProvider: { self.slotID }
        )
        let router = SpeechCommandRouter(
            sources: [source],
            playbackSession: session,
            activeSlotIDProvider: { self.slotID }
        )

        XCTAssertTrue(coordinator.readCurrentPage(slotID: slotID))
        let firstToken = try! XCTUnwrap(service.spokenRequests.first?.transportToken)
        service.emitStart(token: firstToken)
        coordinator.handleBackgroundMediaPolicyChange(
            slotID: slotID,
            policy: .pauseWhenInactive,
            isInactive: true
        )

        XCTAssertEqual(coordinator.state, .suspended)
        XCTAssertNil(session.activeContext)
        XCTAssertNil(session.activeSourceSessionKind)
        XCTAssertEqual(source.presentation.resumableSlotID, slotID)
        XCTAssertEqual(source.presentation.playbackState, .paused)
        XCTAssertEqual(source.presentation.railPresentation.resumableSlotID, slotID)

        let extractionCount = bridge.extractionCount
        XCTAssertEqual(
            router.readPauseResumeForActiveSlot(),
            .resumed(sourceKind: .calibreReader, slotID: slotID)
        )
        XCTAssertEqual(bridge.extractionCount, extractionCount)
        XCTAssertEqual(service.spokenRequests.count, 2)
        XCTAssertEqual(service.spokenRequests[1].text, service.spokenRequests[0].text)
        XCTAssertEqual(session.activeSourceSessionKind, .calibreReader)
    }

    func testRouterResumeAfterSuspendedRelocationUsesExistingReadingTransaction() {
        let doc = document()
        let first = page(document: doc, start: "a", end: "b", text: "First page.")
        let second = page(document: doc, start: "c", end: "d", text: "Second page.")
        let bridge = CalibreTestReaderBridge(slotID: slotID, pages: [first, second])
        let service = CalibreTestSpeechService()
        let (coordinator, session) = makeCoordinator(bridge: bridge, service: service)
        let source = CalibreSpeechSourceAdapter(
            coordinator: coordinator,
            playbackSession: session,
            activeSlotIDProvider: { self.slotID }
        )
        let router = SpeechCommandRouter(
            sources: [source],
            playbackSession: session,
            activeSlotIDProvider: { self.slotID }
        )

        XCTAssertTrue(coordinator.readCurrentPage(slotID: slotID))
        service.emitStart()
        service.emitFinish()
        XCTAssertEqual(coordinator.state, .awaitingRelocation)
        XCTAssertEqual(bridge.advanceCount, 1)

        coordinator.handleBackgroundMediaPolicyChange(
            slotID: slotID,
            policy: .pauseWhenInactive,
            isInactive: true
        )
        bridge.emitRelocation(second, token: 1)

        XCTAssertEqual(coordinator.state, .suspended)
        XCTAssertNil(session.activeSourceSessionKind)
        XCTAssertEqual(service.spokenRequests.count, 1)
        XCTAssertEqual(bridge.advanceCount, 1)

        XCTAssertEqual(
            router.readPauseResumeForActiveSlot(),
            .resumed(sourceKind: .calibreReader, slotID: slotID)
        )
        XCTAssertEqual(service.spokenRequests.last?.text, "Second page.")
        XCTAssertEqual(bridge.advanceCount, 1)
        XCTAssertEqual(bridge.extractionCount, 3)
    }

    func testRouterResumeContinuesSuspendedExtractionWithoutFreshRead() {
        let doc = document()
        let first = page(document: doc, start: "a", end: "b", text: "First page.")
        let bridge = CalibreTestReaderBridge(slotID: slotID, pages: [first])
        bridge.deferNextExtraction = true
        let service = CalibreTestSpeechService()
        let (coordinator, session) = makeCoordinator(bridge: bridge, service: service)
        let source = CalibreSpeechSourceAdapter(
            coordinator: coordinator,
            playbackSession: session,
            activeSlotIDProvider: { self.slotID }
        )
        let router = SpeechCommandRouter(
            sources: [source],
            playbackSession: session,
            activeSlotIDProvider: { self.slotID }
        )

        XCTAssertTrue(coordinator.readCurrentPage(slotID: slotID))
        XCTAssertEqual(coordinator.state, .extracting)
        coordinator.handleBackgroundMediaPolicyChange(
            slotID: slotID,
            policy: .pauseWhenInactive,
            isInactive: true
        )
        bridge.resolvePendingExtraction()

        XCTAssertEqual(coordinator.state, .suspended)
        XCTAssertEqual(service.spokenRequests.count, 0)
        XCTAssertNil(session.activeSourceSessionKind)

        XCTAssertEqual(
            router.readPauseResumeForActiveSlot(),
            .resumed(sourceKind: .calibreReader, slotID: slotID)
        )
        XCTAssertEqual(bridge.extractionCount, 1)
        XCTAssertEqual(service.spokenRequests.count, 1)
        XCTAssertEqual(service.spokenRequests.first?.text, "First page.")
    }

    func testSuspendedCalibreYieldsAuthorityToChatGPTAndExplicitResumeReacquiresIt() {
        let doc = document()
        let first = page(
            document: doc,
            start: "a",
            end: "b",
            text: "Calibre first sentence. 中文句子。"
        )
        let bridge = CalibreTestReaderBridge(slotID: slotID, pages: [first])
        let service = CalibreTestSpeechService()
        let session = SpeechPlaybackSessionController(speechService: service)
        let calibreCoordinator = CalibreSpeechCoordinator(
            playbackSession: session,
            bridgeProvider: { id in id == self.slotID ? bridge : nil }
        )
        let chatSlot = UUID()
        var activeSlot = slotID
        let calibreSource = CalibreSpeechSourceAdapter(
            coordinator: calibreCoordinator,
            playbackSession: session,
            activeSlotIDProvider: { activeSlot }
        )
        let responseBridge = CalibreTestResponseBridge()
        let chatWebView = WKWebView(frame: .zero)
        let chatCoordinator = AssistantSpeechCoordinator(
            playbackSession: session,
            webViewProvider: { _ in chatWebView },
            responseBridgeProvider: { _ in responseBridge },
            automaticSpeechSuppressed: { _ in
                session.activeSourceSessionKind != nil
            }
        )
        let chatSource = ChatGPTSpeechSourceAdapter(
            coordinator: chatCoordinator,
            playbackSession: session,
            activeSlotIDProvider: { activeSlot },
            supportsSpeechQuery: { $0 == chatSlot }
        )
        let router = SpeechCommandRouter(
            sources: [calibreSource, chatSource],
            playbackSession: session,
            activeSlotIDProvider: { activeSlot }
        )

        chatCoordinator.toggleAutoSpeak(for: chatSlot)
        XCTAssertTrue(calibreCoordinator.readCurrentPage(slotID: slotID))
        service.emitStart()
        calibreCoordinator.handleBackgroundMediaPolicyChange(
            slotID: slotID,
            policy: .pauseWhenInactive,
            isInactive: true
        )

        XCTAssertNil(session.activeSourceSessionKind)
        XCTAssertEqual(session.playbackState, .idle)

        activeSlot = chatSlot
        chatCoordinator.handle(.generationFinished, for: chatSlot)
        responseBridge.resolve(
            ChatGPTResponsePayload(
                version: ChatGPTResponsePayload.currentVersion,
                kind: .response,
                requestID: "request-chat-12345678",
                documentToken: "document-chat-12345678",
                responseID: "document-chat-12345678:response-chat",
                blocks: [SpeechContentBlock(
                    kind: .paragraph,
                    text: "ChatGPT automatic response.",
                    level: nil
                )]
            )
        )
        XCTAssertEqual(service.spokenRequests.last?.text, "ChatGPT automatic response.")
        XCTAssertEqual(session.activeContext?.sourceKind, .chatGPT)

        activeSlot = slotID
        XCTAssertEqual(
            router.readPauseResumeForActiveSlot(),
            .resumed(sourceKind: .calibreReader, slotID: slotID)
        )
        XCTAssertEqual(session.activeContext?.sourceKind, .calibreReader)
        XCTAssertEqual(service.spokenRequests.last?.text, "Calibre first sentence.")
        XCTAssertEqual(service.spokenRequests.filter {
            $0.text == "Calibre first sentence."
        }.count, 2)
    }

    func testSuspendedCalibreReacquiresAfterChatGPTFinishes() {
        let doc = document()
        let first = page(
            document: doc,
            start: "a",
            end: "b",
            text: "Calibre first sentence. 中文句子。"
        )
        let bridge = CalibreTestReaderBridge(slotID: slotID, pages: [first])
        let service = CalibreTestSpeechService()
        let session = SpeechPlaybackSessionController(speechService: service)
        let calibreCoordinator = CalibreSpeechCoordinator(
            playbackSession: session,
            bridgeProvider: { id in id == self.slotID ? bridge : nil }
        )
        let chatSlot = UUID()
        var activeSlot = slotID
        let calibreSource = CalibreSpeechSourceAdapter(
            coordinator: calibreCoordinator,
            playbackSession: session,
            activeSlotIDProvider: { activeSlot }
        )
        let responseBridge = CalibreTestResponseBridge()
        let chatWebView = WKWebView(frame: .zero)
        let chatCoordinator = AssistantSpeechCoordinator(
            playbackSession: session,
            webViewProvider: { _ in chatWebView },
            responseBridgeProvider: { _ in responseBridge },
            automaticSpeechSuppressed: { _ in
                session.activeSourceSessionKind != nil
            }
        )
        let chatSource = ChatGPTSpeechSourceAdapter(
            coordinator: chatCoordinator,
            playbackSession: session,
            activeSlotIDProvider: { activeSlot },
            supportsSpeechQuery: { $0 == chatSlot }
        )
        let router = SpeechCommandRouter(
            sources: [calibreSource, chatSource],
            playbackSession: session,
            activeSlotIDProvider: { activeSlot }
        )

        chatCoordinator.toggleAutoSpeak(for: chatSlot)
        XCTAssertTrue(calibreCoordinator.readCurrentPage(slotID: slotID))
        service.emitStart()
        calibreCoordinator.handleBackgroundMediaPolicyChange(
            slotID: slotID,
            policy: .pauseWhenInactive,
            isInactive: true
        )
        XCTAssertNil(session.activeSourceSessionKind)

        activeSlot = chatSlot
        chatCoordinator.handle(.generationFinished, for: chatSlot)
        responseBridge.resolve(
            ChatGPTResponsePayload(
                version: ChatGPTResponsePayload.currentVersion,
                kind: .response,
                requestID: "request-chat-finished-12345678",
                documentToken: "document-chat-finished-12345678",
                responseID: "document-chat-finished-12345678:response-chat",
                blocks: [SpeechContentBlock(
                    kind: .paragraph,
                    text: "ChatGPT response.",
                    level: nil
                )]
            )
        )
        let chatToken = try! XCTUnwrap(service.spokenRequests.last?.transportToken)
        service.emitStart(token: chatToken)
        XCTAssertEqual(session.activeContext?.sourceKind, .chatGPT)
        service.emitFinish(token: chatToken)

        XCTAssertNil(session.activeContext)
        XCTAssertNil(session.activeSourceSessionKind)
        XCTAssertEqual(session.playbackState, .idle)

        activeSlot = slotID
        XCTAssertEqual(
            router.readPauseResumeForActiveSlot(),
            .resumed(sourceKind: .calibreReader, slotID: slotID)
        )
        XCTAssertEqual(session.activeContext?.sourceKind, .calibreReader)
        XCTAssertEqual(session.activeContext?.slotID, slotID)
        XCTAssertEqual(service.spokenRequests.last?.text, "Calibre first sentence.")
    }

    func testPinnedBridgeScriptsUseRuntimeCFIAndRelocationWithoutWholeDocumentText() {
        let source = CalibreReaderBridge.currentReadingUnitScript
            + CalibreReaderBridge.runtimeDetectionScript
            + CalibreReaderBridge.advanceScript(startCFI: "a", endCFI: "b")
            + CalibreReaderBridge.relocationObserverScript(generation: 1)
        XCTAssertTrue(source.contains("currentLocation"))
        XCTAssertTrue(source.contains("ePub.CFI"))
        XCTAssertTrue(source.contains("rendition.next()"))
        XCTAssertTrue(source.contains("relocated"))
        XCTAssertTrue(source.contains("sourceAdvanceRelocated"))
        XCTAssertTrue(source.contains("__floatTabsCalibreReaderAdvanceTransaction"))
        XCTAssertTrue(source.contains("queueBusy"))
        XCTAssertTrue(source.contains("generation"))
        XCTAssertTrue(source.contains("startCFI"))
        XCTAssertTrue(source.contains("endCFI"))
        XCTAssertFalse(source.contains("document.body.innerText"))
        XCTAssertFalse(source.contains("document.body.textContent"))
        XCTAssertFalse(source.contains("spine"))
    }

    func testReaderReadinessUsesBookOpenedPromiseAndGenerationScopedObserver() {
        let detection = CalibreReaderBridge.runtimeDetectionScript
        let observer = CalibreReaderBridge.readerReadinessObserverScript(generation: 7)

        XCTAssertTrue(detection.contains("book.opened"))
        XCTAssertTrue(detection.contains("readinessPending"))
        XCTAssertTrue(observer.contains("opened.then"))
        XCTAssertTrue(observer.contains("event: 'readerReady'"))
        XCTAssertTrue(observer.contains("generation: 7"))
        XCTAssertTrue(observer.contains("__floatTabsCalibreReaderReadinessGeneration"))
        XCTAssertTrue(observer.contains("() => {}"))
    }

    func testAsyncReaderReadinessAfterDidFinishPromotesCandidate() async {
        let page = CalibreReaderPageHarness()
        page.bridge.handleNavigationCommit(page.url)
        page.load(readerInitiallyReady: false)

        let loaded = await page.waitFor { !page.webView.isLoading }
        XCTAssertTrue(loaded)
        page.bridge.handleNavigationFinish(page.url)
        XCTAssertFalse(page.bridge.isReaderCandidate)

        let resolverType = await page.run("typeof window.__resolveCalibreOpened") as? String
        XCTAssertEqual(resolverType, "function")
        let observerGeneration = await page.run(
            "window.__floatTabsCalibreReaderReadinessGeneration || null"
        ) as? NSNumber
        XCTAssertEqual(observerGeneration?.uint64Value, 1)
        _ = await page.run("window.reader.book.package = {}; window.__resolveCalibreOpened(); true")
        let detected = await page.run(CalibreReaderBridge.runtimeDetectionScript) as? [String: Any]
        XCTAssertEqual(detected?["valid"] as? Bool, true)

        let ready = await page.waitFor { page.bridge.isReaderCandidate }
        XCTAssertTrue(ready)
    }

    func testAlreadyReadyReaderStillPromotesImmediatelyAfterDidFinish() async {
        let page = CalibreReaderPageHarness()
        page.bridge.handleNavigationCommit(page.url)
        page.load(readerInitiallyReady: true)

        let loaded = await page.waitFor { !page.webView.isLoading }
        XCTAssertTrue(loaded)
        page.bridge.handleNavigationFinish(page.url)

        let ready = await page.waitFor { page.bridge.isReaderCandidate }
        XCTAssertTrue(ready)
    }

    func testReaderReadyAndAdvanceFailureMessagesRequireWebViewFrameAndOrigin() {
        let attachedWebView = WKWebView(frame: .zero)
        let otherWebView = WKWebView(frame: .zero)
        let origin = URL(string: "https://reader.example.test")!

        XCTAssertTrue(
            CalibreReaderBridge.pageMessagePassesSecurityContract(
                messageWebView: attachedWebView,
                attachedWebView: attachedWebView,
                isMainFrame: true,
                originScheme: "https",
                originHost: "reader.example.test",
                originPort: 443,
                documentOrigin: origin
            )
        )
        XCTAssertFalse(
            CalibreReaderBridge.pageMessagePassesSecurityContract(
                messageWebView: otherWebView,
                attachedWebView: attachedWebView,
                isMainFrame: true,
                originScheme: "https",
                originHost: "reader.example.test",
                originPort: 443,
                documentOrigin: origin
            )
        )
        XCTAssertFalse(
            CalibreReaderBridge.pageMessagePassesSecurityContract(
                messageWebView: attachedWebView,
                attachedWebView: attachedWebView,
                isMainFrame: false,
                originScheme: "https",
                originHost: "reader.example.test",
                originPort: 443,
                documentOrigin: origin
            )
        )
        XCTAssertFalse(
            CalibreReaderBridge.pageMessagePassesSecurityContract(
                messageWebView: attachedWebView,
                attachedWebView: attachedWebView,
                isMainFrame: true,
                originScheme: "https",
                originHost: "other.example.test",
                originPort: 443,
                documentOrigin: origin
            )
        )
    }

    func testAdvanceScriptObservesAsyncRejectionWithBoundTransitionIdentity() {
        let script = CalibreReaderBridge.advanceScript(
            startCFI: "a",
            endCFI: "b",
            generation: 4,
            transitionToken: 9
        )

        XCTAssertTrue(script.contains("result.then"))
        XCTAssertTrue(script.contains("event: 'advanceFailed'"))
        XCTAssertTrue(script.contains("generation: 4"))
        XCTAssertTrue(script.contains("transitionToken: 9"))
        XCTAssertTrue(script.contains("rendition.next()"))
        XCTAssertTrue(script.contains("rendition.q"))
        XCTAssertTrue(script.contains("queue.length()"))
        XCTAssertTrue(script.contains("fromStartCFI"))
        XCTAssertTrue(script.contains("fromEndCFI"))
        XCTAssertTrue(
            CalibreReaderBridge.clearAdvanceTransactionScript(
                generation: 4,
                transitionToken: 9
            ).contains("transitionToken === (9)")
        )
    }

    private func makeReadyPageHarness() async -> (
        harness: CalibreReaderPageHarness,
        document: CalibreReaderDocumentIdentity
    ) {
        let harness = CalibreReaderPageHarness()
        harness.bridge.handleNavigationCommit(harness.url)
        harness.load(readerInitiallyReady: true)
        let loaded = await harness.waitFor { !harness.webView.isLoading }
        XCTAssertTrue(loaded)
        harness.bridge.handleNavigationFinish(harness.url)
        let ready = await harness.waitFor { harness.bridge.isReaderCandidate }
        XCTAssertTrue(ready)
        let observerReady = await harness.waitForPageFlag(
            "window.__floatTabsCalibreRelocationGeneration === 1"
        )
        XCTAssertTrue(observerReady)
        return (harness, try! XCTUnwrap(harness.bridge.currentDocumentIdentity))
    }

    func testRealBridgeGenericRelocationNeverReceivesPendingSourceToken() async {
        let (harness, document) = await makeReadyPageHarness()
        let second = page(document: document, start: "c", end: "d", text: "Manual page.")
        let scheduler = CalibreTestWatchdogScheduler()
        let service = CalibreTestSpeechService()
        let (coordinator, session) = makeCoordinator(
            bridge: harness.bridge,
            service: service,
            watchdogScheduler: scheduler
        )

        XCTAssertTrue(coordinator.readCurrentPage(slotID: harness.bridge.slotID))
        let firstSpeech = await harness.waitFor { service.spokenRequests.count == 1 }
        XCTAssertTrue(firstSpeech)
        service.emitStart()
        service.emitFinish()
        let awaitingRelocation = await harness.waitFor {
            coordinator.state == .awaitingRelocation
        }
        XCTAssertTrue(awaitingRelocation)

        await harness.emitGenericRelocation(second)

        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertNil(session.activeSourceSessionKind)
        XCTAssertFalse(coordinator.isSpeechProtectionActive)
        XCTAssertEqual(service.spokenRequests.count, 1)
        XCTAssertEqual(scheduler.tasks.count, 1)
    }

    func testRealBridgeSourceTransactionOwnsRelocationAndContinuesSpeech() async {
        let (harness, document) = await makeReadyPageHarness()
        let second = page(document: document, start: "c", end: "d", text: "Second page.")
        let scheduler = CalibreTestWatchdogScheduler()
        let service = CalibreTestSpeechService()
        let (coordinator, session) = makeCoordinator(
            bridge: harness.bridge,
            service: service,
            watchdogScheduler: scheduler
        )

        XCTAssertTrue(coordinator.readCurrentPage(slotID: harness.bridge.slotID))
        let firstSpeech = await harness.waitFor { service.spokenRequests.count == 1 }
        XCTAssertTrue(firstSpeech)
        service.emitStart()
        service.emitFinish()
        let awaitingRelocation = await harness.waitFor {
            coordinator.state == .awaitingRelocation
        }
        XCTAssertTrue(awaitingRelocation)

        await harness.emitRenditionRelocation(second)
        let continued = await harness.waitFor { coordinator.state == .speakingUnit }
        XCTAssertTrue(continued)

        XCTAssertEqual(service.spokenRequests.count, 2)
        XCTAssertEqual(coordinator.state, .speakingUnit)
        XCTAssertEqual(session.activeSourceSessionKind, .calibreReader)
        XCTAssertTrue(scheduler.tasks.first?.isCancelled == true)
    }

    func testRealBridgeStaleSourceAckCannotTouchCurrentSession() async {
        let (harness, document) = await makeReadyPageHarness()
        let first = page(document: document, start: "a", end: "b", text: "First page.")
        let service = CalibreTestSpeechService()
        let (coordinator, session) = makeCoordinator(
            bridge: harness.bridge,
            service: service
        )

        XCTAssertTrue(coordinator.readCurrentPage(slotID: harness.bridge.slotID))
        let firstSpeech = await harness.waitFor { service.spokenRequests.count == 1 }
        XCTAssertTrue(firstSpeech)
        XCTAssertEqual(coordinator.state, .speakingUnit)
        await harness.postSourceAck(
            generation: 0,
            transitionToken: 999,
            fromStartCFI: first.identity.startCFI,
            fromEndCFI: first.identity.endCFI,
            startCFI: "c",
            endCFI: "d"
        )

        XCTAssertEqual(coordinator.state, .speakingUnit)
        XCTAssertEqual(service.spokenRequests.count, 1)
        XCTAssertEqual(session.activeSourceSessionKind, .calibreReader)
    }

    func testRealBridgeLaterGenericRelocationTerminatesAfterOwnedAck() async {
        let (harness, document) = await makeReadyPageHarness()
        let second = page(document: document, start: "c", end: "d", text: "Second page.")
        let third = page(document: document, start: "e", end: "f", text: "Manual page.")
        let service = CalibreTestSpeechService()
        let (coordinator, session) = makeCoordinator(
            bridge: harness.bridge,
            service: service
        )

        XCTAssertTrue(coordinator.readCurrentPage(slotID: harness.bridge.slotID))
        let firstSpeech = await harness.waitFor { service.spokenRequests.count == 1 }
        XCTAssertTrue(firstSpeech)
        service.emitStart()
        service.emitFinish()
        let awaitingRelocation = await harness.waitFor {
            coordinator.state == .awaitingRelocation
        }
        XCTAssertTrue(awaitingRelocation)
        await harness.emitRenditionRelocation(second)
        let continued = await harness.waitFor { coordinator.state == .speakingUnit }
        XCTAssertTrue(continued)
        XCTAssertEqual(service.spokenRequests.count, 2)

        await harness.emitGenericRelocation(third)

        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertNil(session.activeSourceSessionKind)
        XCTAssertFalse(coordinator.isSpeechProtectionActive)
        XCTAssertEqual(service.spokenRequests.count, 2)
    }

    func testRealBridgePreexistingQueueWorkFailsClosedWithoutSourceAck() async {
        let (harness, _) = await makeReadyPageHarness()
        let service = CalibreTestSpeechService()
        let (coordinator, session) = makeCoordinator(
            bridge: harness.bridge,
            service: service
        )

        XCTAssertTrue(coordinator.readCurrentPage(slotID: harness.bridge.slotID))
        let firstSpeech = await harness.waitFor { service.spokenRequests.count == 1 }
        XCTAssertTrue(firstSpeech)
        service.emitStart()
        await harness.setQueueBusy(true)
        service.emitFinish()

        let stopped = await harness.waitFor { coordinator.state == .idle }
        XCTAssertTrue(stopped)
        XCTAssertNil(session.activeSourceSessionKind)
        XCTAssertFalse(coordinator.isSpeechProtectionActive)
        XCTAssertEqual(service.spokenRequests.count, 1)
        let transactionCleared = await harness.run(
            "window.__floatTabsCalibreReaderAdvanceTransaction == null"
        ) as? Bool
        XCTAssertEqual(transactionCleared, true)
    }

    func testReadHoldsSourceLeaseAcrossTransportIdleAndAdvancesOnlyAfterChangedRelocation() {
        let doc = document()
        let first = page(document: doc, start: "a", end: "b", text: "First page.")
        let second = page(document: doc, start: "c", end: "d", text: "Second page.")
        let bridge = CalibreTestReaderBridge(slotID: slotID, pages: [first, second])
        let service = CalibreTestSpeechService()
        let (coordinator, session) = makeCoordinator(bridge: bridge, service: service)

        XCTAssertTrue(coordinator.readCurrentPage(slotID: slotID))
        XCTAssertEqual(session.activeSourceSessionKind, .calibreReader)
        service.emitStart()
        service.emitFinish()

        XCTAssertEqual(coordinator.state, .awaitingRelocation)
        XCTAssertEqual(session.playbackState, .idle)
        XCTAssertEqual(bridge.advanceCount, 1)
        XCTAssertEqual(service.spokenRequests.count, 1)
        XCTAssertEqual(session.activeSourceSessionKind, .calibreReader)

        bridge.emitRelocation(first, token: 1)
        XCTAssertEqual(coordinator.state, .awaitingRelocation)
        bridge.emitRelocation(second, token: 1)
        XCTAssertEqual(coordinator.state, .speakingUnit)
        XCTAssertEqual(service.spokenRequests.count, 2)
        XCTAssertEqual(session.activeSourceSessionKind, .calibreReader)
    }

    func testAsyncAdvanceFailureStopsAndReleasesLeaseAndProtection() {
        let doc = document()
        let first = page(document: doc, start: "a", end: "b", text: "First page.")
        let bridge = CalibreTestReaderBridge(slotID: slotID, pages: [first])
        bridge.deferAdvanceFailure = true
        let service = CalibreTestSpeechService()
        let (coordinator, session) = makeCoordinator(bridge: bridge, service: service)

        XCTAssertTrue(coordinator.readCurrentPage(slotID: slotID))
        service.emitStart()
        service.emitFinish()
        XCTAssertEqual(coordinator.state, .awaitingRelocation)
        XCTAssertNotNil(session.activeSourceSessionKind)

        bridge.emitAdvanceFailure()

        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertNil(session.activeSourceSessionKind)
        XCTAssertFalse(coordinator.isSpeechProtectionActive)
        XCTAssertEqual(bridge.extractionCount, 2)
    }

    func testRelocationWatchdogFailsClosedWithoutChangedRelocation() {
        let doc = document()
        let first = page(document: doc, start: "a", end: "b", text: "First page.")
        let bridge = CalibreTestReaderBridge(slotID: slotID, pages: [first])
        let scheduler = CalibreTestWatchdogScheduler()
        let service = CalibreTestSpeechService()
        let (coordinator, session) = makeCoordinator(
            bridge: bridge,
            service: service,
            watchdogScheduler: scheduler
        )

        XCTAssertTrue(coordinator.readCurrentPage(slotID: slotID))
        service.emitStart()
        service.emitFinish()
        XCTAssertEqual(coordinator.state, .awaitingRelocation)
        XCTAssertEqual(scheduler.tasks.count, 1)

        scheduler.fireLatestIgnoringCancellation()

        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertNil(session.activeSourceSessionKind)
        XCTAssertFalse(coordinator.isSpeechProtectionActive)
        XCTAssertEqual(bridge.extractionCount, 2)
    }

    func testSuccessfulRelocationCancelsWatchdogAndOldCallbackIsInert() {
        let doc = document()
        let first = page(document: doc, start: "a", end: "b", text: "First page.")
        let second = page(document: doc, start: "c", end: "d", text: "Second page.")
        let bridge = CalibreTestReaderBridge(slotID: slotID, pages: [first, second])
        let scheduler = CalibreTestWatchdogScheduler()
        let service = CalibreTestSpeechService()
        let (coordinator, session) = makeCoordinator(
            bridge: bridge,
            service: service,
            watchdogScheduler: scheduler
        )

        XCTAssertTrue(coordinator.readCurrentPage(slotID: slotID))
        service.emitStart()
        service.emitFinish()
        bridge.emitRelocation(second, token: 1)
        XCTAssertEqual(coordinator.state, .speakingUnit)
        XCTAssertEqual(service.spokenRequests.count, 2)
        XCTAssertTrue(scheduler.tasks.first?.isCancelled == true)

        scheduler.fireLatestIgnoringCancellation()

        XCTAssertEqual(coordinator.state, .speakingUnit)
        XCTAssertEqual(service.spokenRequests.count, 2)
        XCTAssertEqual(session.activeSourceSessionKind, .calibreReader)
    }

    func testSameCFIRelocationDoesNotCompleteTransitionAndWatchdogReleases() {
        let doc = document()
        let first = page(document: doc, start: "a", end: "b", text: "First page.")
        let bridge = CalibreTestReaderBridge(slotID: slotID, pages: [first])
        let scheduler = CalibreTestWatchdogScheduler()
        let service = CalibreTestSpeechService()
        let (coordinator, session) = makeCoordinator(
            bridge: bridge,
            service: service,
            watchdogScheduler: scheduler
        )

        XCTAssertTrue(coordinator.readCurrentPage(slotID: slotID))
        service.emitStart()
        service.emitFinish()
        bridge.emitRelocation(first, token: 1)

        XCTAssertEqual(coordinator.state, .awaitingRelocation)
        XCTAssertNotNil(session.activeSourceSessionKind)
        scheduler.fireLatestIgnoringCancellation()

        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertNil(session.activeSourceSessionKind)
        XCTAssertFalse(coordinator.isSpeechProtectionActive)
    }

    func testNavigationWhileAwaitingRelocationInvalidatesOldWatchdogAndFailure() {
        let doc = document()
        let first = page(document: doc, start: "a", end: "b", text: "First page.")
        let bridge = CalibreTestReaderBridge(slotID: slotID, pages: [first])
        let scheduler = CalibreTestWatchdogScheduler()
        let service = CalibreTestSpeechService()
        let (coordinator, session) = makeCoordinator(
            bridge: bridge,
            service: service,
            watchdogScheduler: scheduler
        )

        XCTAssertTrue(coordinator.readCurrentPage(slotID: slotID))
        service.emitStart()
        service.emitFinish()
        XCTAssertEqual(coordinator.state, .awaitingRelocation)

        coordinator.resetRuntime(slotID: slotID)
        bridge.emitAdvanceFailure()
        scheduler.fireLatestIgnoringCancellation()

        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertNil(session.activeSourceSessionKind)
        XCTAssertFalse(coordinator.isSpeechProtectionActive)
    }

    func testExplicitStopWhileAwaitingRelocationRemainsFinalAfterWatchdog() {
        let doc = document()
        let first = page(document: doc, start: "a", end: "b", text: "First page.")
        let bridge = CalibreTestReaderBridge(slotID: slotID, pages: [first])
        let scheduler = CalibreTestWatchdogScheduler()
        let service = CalibreTestSpeechService()
        let (coordinator, session) = makeCoordinator(
            bridge: bridge,
            service: service,
            watchdogScheduler: scheduler
        )

        XCTAssertTrue(coordinator.readCurrentPage(slotID: slotID))
        service.emitStart()
        service.emitFinish()
        XCTAssertEqual(coordinator.state, .awaitingRelocation)

        coordinator.stop()
        scheduler.fireLatestIgnoringCancellation()

        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertNil(session.activeSourceSessionKind)
        XCTAssertFalse(coordinator.isSpeechProtectionActive)
    }

    func testExternalRelocationTerminatesContinuousSessionWithoutIssuingAdvance() {
        let doc = document()
        let first = page(document: doc, start: "a", end: "b", text: "First page.")
        let second = page(document: doc, start: "c", end: "d", text: "Manual page.")
        let bridge = CalibreTestReaderBridge(slotID: slotID, pages: [first, second])
        let service = CalibreTestSpeechService()
        let (coordinator, session) = makeCoordinator(bridge: bridge, service: service)

        XCTAssertTrue(coordinator.readCurrentPage(slotID: slotID))
        service.emitStart()
        bridge.emitRelocation(
            second,
            token: nil
        )

        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertNil(session.activeSourceSessionKind)
        XCTAssertEqual(bridge.advanceCount, 0)
        XCTAssertEqual(service.stopCount, 1)
    }

    func testExternalRelocationDuringAdvanceWaitTerminatesSession() {
        let doc = document()
        let first = page(document: doc, start: "a", end: "b", text: "First page.")
        let second = page(document: doc, start: "c", end: "d", text: "Manual page.")
        let bridge = CalibreTestReaderBridge(slotID: slotID, pages: [first, second])
        let service = CalibreTestSpeechService()
        let (coordinator, session) = makeCoordinator(bridge: bridge, service: service)

        XCTAssertTrue(coordinator.readCurrentPage(slotID: slotID))
        service.emitStart()
        service.emitFinish()
        XCTAssertEqual(coordinator.state, .awaitingRelocation)

        bridge.emitRelocation(
            second,
            token: nil
        )

        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertNil(session.activeSourceSessionKind)
        XCTAssertEqual(service.spokenRequests.count, 1)
    }

    func testDuplicateRelocationDoesNotDuplicateNextPageSpeech() {
        let doc = document()
        let first = page(document: doc, start: "a", end: "b", text: "First page.")
        let second = page(document: doc, start: "c", end: "d", text: "Second page.")
        let bridge = CalibreTestReaderBridge(slotID: slotID, pages: [first, second])
        let service = CalibreTestSpeechService()
        let (coordinator, _) = makeCoordinator(bridge: bridge, service: service)

        XCTAssertTrue(coordinator.readCurrentPage(slotID: slotID))
        service.emitStart()
        service.emitFinish()
        bridge.emitRelocation(second, token: 1)
        XCTAssertEqual(service.spokenRequests.count, 2)

        bridge.emitRelocation(second, token: nil)
        XCTAssertEqual(coordinator.state, .speakingUnit)
        XCTAssertEqual(service.spokenRequests.count, 2)
    }

    func testEndOfBookReleasesLeaseAndSpeechProtection() {
        let doc = document()
        let last = page(document: doc, start: "a", end: "b", text: "Last page.", atEnd: true)
        let bridge = CalibreTestReaderBridge(slotID: slotID, pages: [last])
        let service = CalibreTestSpeechService()
        let (coordinator, session) = makeCoordinator(bridge: bridge, service: service)

        XCTAssertTrue(coordinator.readCurrentPage(slotID: slotID))
        service.emitStart()
        service.emitFinish()

        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertNil(session.activeSourceSessionKind)
        XCTAssertFalse(coordinator.isSpeechProtectionActive)
    }

    func testBridgeErrorOrDocumentReplacementReleasesLease() {
        let doc = document()
        let first = page(document: doc, start: "a", end: "b", text: "Page.")
        let bridge = CalibreTestReaderBridge(slotID: slotID, pages: [first])
        let service = CalibreTestSpeechService()
        let (coordinator, session) = makeCoordinator(bridge: bridge, service: service)

        XCTAssertTrue(coordinator.readCurrentPage(slotID: slotID))
        bridge.isReaderCandidate = false
        coordinator.resetRuntime(slotID: slotID)

        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertNil(session.activeSourceSessionKind)
        XCTAssertEqual(service.stopCount, 1)
    }

    func testGlobalStopClearsCalibreLeaseAndMakesLateRelocationInert() {
        let doc = document()
        let first = page(document: doc, start: "a", end: "b", text: "Page.")
        let second = page(document: doc, start: "c", end: "d", text: "Next.")
        let bridge = CalibreTestReaderBridge(slotID: slotID, pages: [first, second])
        let service = CalibreTestSpeechService()
        let (coordinator, session) = makeCoordinator(bridge: bridge, service: service)
        let source = CalibreSpeechSourceAdapter(
            coordinator: coordinator,
            playbackSession: session,
            activeSlotIDProvider: { self.slotID }
        )
        let router = SpeechCommandRouter(
            sources: [source],
            playbackSession: session,
            activeSlotIDProvider: { self.slotID }
        )

        XCTAssertTrue(coordinator.readCurrentPage(slotID: slotID))
        service.emitStart()
        XCTAssertEqual(
            router.stopCurrentPlayback(),
            .stopped(sourceKind: .calibreReader, slotID: slotID)
        )
        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertNil(session.activeSourceSessionKind)
        let spokenCount = service.spokenRequests.count
        bridge.emitRelocation(second, token: 1)
        XCTAssertEqual(service.spokenRequests.count, spokenCount)

        XCTAssertEqual(router.stopCurrentPlayback(), .noOp)
    }

    func testPreviewPreemptsCalibreSessionBeforeStartingChatGPTPreview() {
        let doc = document()
        let first = page(document: doc, start: "a", end: "b", text: "Page.")
        let bridge = CalibreTestReaderBridge(slotID: slotID, pages: [first])
        let service = CalibreTestSpeechService()
        let session = SpeechPlaybackSessionController(speechService: service)
        let calibreCoordinator = CalibreSpeechCoordinator(
            playbackSession: session,
            bridgeProvider: { id in id == self.slotID ? bridge : nil }
        )
        let calibreSource = CalibreSpeechSourceAdapter(
            coordinator: calibreCoordinator,
            playbackSession: session,
            activeSlotIDProvider: { self.slotID }
        )
        let responseBridge = CalibreTestResponseBridge()
        let chatGPTCoordinator = AssistantSpeechCoordinator(
            playbackSession: session,
            webViewProvider: { _ in WKWebView(frame: .zero) },
            responseBridgeProvider: { _ in responseBridge }
        )
        let chatGPTSource = ChatGPTSpeechSourceAdapter(
            coordinator: chatGPTCoordinator,
            playbackSession: session
        )
        let router = SpeechCommandRouter(
            sources: [calibreSource, chatGPTSource],
            playbackSession: session,
            activeSlotIDProvider: { self.slotID }
        )

        XCTAssertTrue(calibreCoordinator.readCurrentPage(slotID: slotID))
        XCTAssertNotNil(session.activeSourceSessionKind)
        router.playPreview(SpeechLanguageRouter.utteranceRequests(for: "Preview."))

        XCTAssertNil(session.activeSourceSessionKind)
        XCTAssertEqual(calibreCoordinator.state, .idle)
        XCTAssertEqual(service.spokenRequests.last?.text, "Preview.")
        XCTAssertGreaterThan(service.stopCount, 0)
    }

    func testDocumentNavigationCreatesNewGenerationAndDropsReaderCandidate() {
        let bridge = CalibreReaderBridge(slotID: slotID)
        let webView = WKWebView(frame: .zero)
        bridge.attach(to: webView)
        let url = URL(string: "https://reader.example.test/read/7/epub")!

        bridge.handleNavigationCommit(url)
        let firstGeneration = bridge.currentDocumentIdentity?.documentGeneration
        XCTAssertNotNil(firstGeneration)
        XCTAssertFalse(bridge.isReaderCandidate)

        bridge.handleNavigationCommit(url)
        XCTAssertEqual(
            bridge.currentDocumentIdentity?.documentGeneration,
            (firstGeneration ?? 0) + 1
        )
        XCTAssertFalse(bridge.isReaderCandidate)
    }

    func testSingleSegmentBoundaryResumeUsesNormalCompletionAuthority() {
        let doc = document()
        let first = page(document: doc, start: "a", end: "b", text: "Page.")
        let bridge = CalibreTestReaderBridge(slotID: slotID, pages: [first])
        let service = CalibreTestSpeechService()
        service.finishDuringPause = true
        let (coordinator, _) = makeCoordinator(bridge: bridge, service: service)

        XCTAssertTrue(coordinator.readCurrentPage(slotID: slotID))
        service.emitStart()
        XCTAssertTrue(coordinator.pause(slotID: slotID))
        service.emitFinish()
        XCTAssertEqual(coordinator.state, .pausedAtBoundary)
        XCTAssertEqual(bridge.advanceCount, 0)

        XCTAssertTrue(coordinator.resume(slotID: slotID))
        XCTAssertEqual(coordinator.state, .awaitingRelocation)
        XCTAssertEqual(bridge.advanceCount, 1)
        XCTAssertEqual(bridge.extractionCount, 2)
    }

    func testMultiSegmentBoundaryResumeContinuesSameReadingUnitWithoutAdvance() {
        let doc = document()
        let first = page(
            document: doc,
            start: "a",
            end: "b",
            text: "English sentence. 中文句子。"
        )
        let bridge = CalibreTestReaderBridge(slotID: slotID, pages: [first])
        let service = CalibreTestSpeechService()
        service.finishDuringPause = true
        let (coordinator, session) = makeCoordinator(bridge: bridge, service: service)
        let requests = SpeechLanguageRouter.utteranceRequests(for: first.text)
        XCTAssertGreaterThanOrEqual(requests.count, 2)

        XCTAssertTrue(coordinator.readCurrentPage(slotID: slotID))
        XCTAssertEqual(service.spokenRequests.count, 1)
        service.emitStart()
        let sourceSequence = try! XCTUnwrap(session.activeContext?.sourceSequence)
        let firstToken = try! XCTUnwrap(service.spokenRequests.first?.transportToken)

        XCTAssertTrue(coordinator.pause(slotID: slotID))
        service.emitFinish(token: firstToken)
        XCTAssertEqual(coordinator.state, .pausedAtBoundary)
        XCTAssertEqual(bridge.advanceCount, 0)

        XCTAssertTrue(coordinator.resume(slotID: slotID))
        XCTAssertEqual(service.spokenRequests.count, 2)
        XCTAssertEqual(service.spokenRequests[1].text, requests[1].text)
        XCTAssertEqual(bridge.currentPage.identity, first.identity)
        XCTAssertEqual(bridge.advanceCount, 0)
        XCTAssertEqual(session.activeContext?.sourceSequence, sourceSequence)
        XCTAssertEqual(session.activeSourceSessionKind, .calibreReader)
        XCTAssertEqual(session.activeSourceSessionSlotID, slotID)
        XCTAssertEqual(coordinator.state, .speakingUnit)
    }

    func testMultiSegmentBoundaryResumeFinishesRemainingSegmentBeforeNormalAdvance() {
        let doc = document()
        let first = page(
            document: doc,
            start: "a",
            end: "b",
            text: "English sentence. 中文句子。"
        )
        let second = page(document: doc, start: "c", end: "d", text: "Next page.")
        let bridge = CalibreTestReaderBridge(slotID: slotID, pages: [first, second])
        let service = CalibreTestSpeechService()
        service.finishDuringPause = true
        let (coordinator, session) = makeCoordinator(bridge: bridge, service: service)
        XCTAssertGreaterThanOrEqual(
            SpeechLanguageRouter.utteranceRequests(for: first.text).count,
            2
        )

        XCTAssertTrue(coordinator.readCurrentPage(slotID: slotID))
        service.emitStart()
        let firstToken = try! XCTUnwrap(service.spokenRequests.first?.transportToken)
        let sourceSequence = try! XCTUnwrap(session.activeContext?.sourceSequence)
        XCTAssertTrue(coordinator.pause(slotID: slotID))
        service.emitFinish(token: firstToken)

        XCTAssertTrue(coordinator.resume(slotID: slotID))
        XCTAssertEqual(bridge.advanceCount, 0)
        XCTAssertEqual(session.activeContext?.sourceSequence, sourceSequence)
        let secondToken = try! XCTUnwrap(service.spokenRequests.last?.transportToken)
        service.emitStart(token: secondToken)
        service.emitFinish(token: secondToken)

        XCTAssertEqual(session.activeContext?.sourceSequence, nil)
        XCTAssertEqual(coordinator.state, .awaitingRelocation)
        XCTAssertEqual(bridge.advanceCount, 1)
        XCTAssertEqual(bridge.currentPage.identity, first.identity)
        XCTAssertNotEqual(firstToken, secondToken)
    }

    func testBoundaryResumeAtEOFCompletesWithoutAdvanceOrResidue() {
        let doc = document()
        let last = page(
            document: doc,
            start: "a",
            end: "b",
            text: "Final page.",
            atEnd: true
        )
        let bridge = CalibreTestReaderBridge(slotID: slotID, pages: [last])
        let scheduler = CalibreTestWatchdogScheduler()
        let service = CalibreTestSpeechService()
        service.finishDuringPause = true
        let (coordinator, session) = makeCoordinator(
            bridge: bridge,
            service: service,
            watchdogScheduler: scheduler
        )

        XCTAssertTrue(coordinator.readCurrentPage(slotID: slotID))
        service.emitStart()
        XCTAssertTrue(coordinator.pause(slotID: slotID))
        service.emitFinish()
        XCTAssertEqual(coordinator.state, .pausedAtBoundary)

        XCTAssertTrue(coordinator.resume(slotID: slotID))
        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertEqual(session.playbackState, .idle)
        XCTAssertNil(session.activeSourceSessionKind)
        XCTAssertFalse(coordinator.isSpeechProtectionActive)
        XCTAssertEqual(bridge.advanceCount, 0)
        XCTAssertTrue(scheduler.tasks.isEmpty)
    }

    func testBoundaryResumeRejectsEveryStaleTransportCallback() {
        let doc = document()
        let first = page(
            document: doc,
            start: "a",
            end: "b",
            text: "English sentence. 中文句子。"
        )
        let bridge = CalibreTestReaderBridge(slotID: slotID, pages: [first])
        let service = CalibreTestSpeechService()
        service.finishDuringPause = true
        let (coordinator, session) = makeCoordinator(bridge: bridge, service: service)

        XCTAssertTrue(coordinator.readCurrentPage(slotID: slotID))
        service.emitStart()
        let oldToken = try! XCTUnwrap(service.spokenRequests.first?.transportToken)
        XCTAssertTrue(coordinator.pause(slotID: slotID))
        service.emitFinish(token: oldToken)
        XCTAssertTrue(coordinator.resume(slotID: slotID))
        let newToken = try! XCTUnwrap(service.spokenRequests.last?.transportToken)
        XCTAssertNotEqual(oldToken, newToken)

        service.emitStart(token: oldToken)
        service.emitPause(token: oldToken)
        service.emitContinue(token: oldToken)
        service.emitFinish(token: oldToken)
        service.emitCancel(token: oldToken)

        XCTAssertEqual(service.spokenRequests.count, 2)
        XCTAssertEqual(session.playbackState, .starting)
        XCTAssertEqual(session.activeTransportToken, newToken)
        XCTAssertEqual(coordinator.state, .speakingUnit)
        XCTAssertEqual(bridge.advanceCount, 0)

        service.emitStart(token: newToken)
        XCTAssertEqual(session.playbackState, .speaking)
        XCTAssertEqual(coordinator.state, .speakingUnit)
    }

    func testStopWhilePausedAtBoundaryPreventsRemainingSpeechAndAdvance() {
        let doc = document()
        let first = page(
            document: doc,
            start: "a",
            end: "b",
            text: "English sentence. 中文句子。"
        )
        let second = page(document: doc, start: "c", end: "d", text: "Next page.")
        let bridge = CalibreTestReaderBridge(slotID: slotID, pages: [first, second])
        let service = CalibreTestSpeechService()
        service.finishDuringPause = true
        let (coordinator, session) = makeCoordinator(bridge: bridge, service: service)

        XCTAssertTrue(coordinator.readCurrentPage(slotID: slotID))
        service.emitStart()
        let oldToken = try! XCTUnwrap(service.spokenRequests.first?.transportToken)
        XCTAssertTrue(coordinator.pause(slotID: slotID))
        service.emitFinish(token: oldToken)
        XCTAssertEqual(coordinator.state, .pausedAtBoundary)

        coordinator.stop()
        service.emitStart(token: oldToken)
        service.emitFinish(token: oldToken)
        service.emitCancel(token: oldToken)

        XCTAssertFalse(coordinator.resume(slotID: slotID))
        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertEqual(service.spokenRequests.count, 1)
        XCTAssertEqual(bridge.advanceCount, 0)
        XCTAssertNil(session.activeSourceSessionKind)
        XCTAssertFalse(coordinator.isSpeechProtectionActive)
    }

    func testRuntimeResetWhilePausedAtBoundaryPreventsDelayedContinuation() {
        let doc = document()
        let first = page(
            document: doc,
            start: "a",
            end: "b",
            text: "English sentence. 中文句子。"
        )
        let bridge = CalibreTestReaderBridge(slotID: slotID, pages: [first])
        let service = CalibreTestSpeechService()
        service.finishDuringPause = true
        let (coordinator, session) = makeCoordinator(bridge: bridge, service: service)

        XCTAssertTrue(coordinator.readCurrentPage(slotID: slotID))
        service.emitStart()
        let oldToken = try! XCTUnwrap(service.spokenRequests.first?.transportToken)
        XCTAssertTrue(coordinator.pause(slotID: slotID))
        service.emitFinish(token: oldToken)

        coordinator.resetRuntime(slotID: slotID)
        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertNil(session.activeSourceSessionKind)
        XCTAssertFalse(coordinator.isSpeechProtectionActive)

        service.emitStart(token: oldToken)
        service.emitFinish(token: oldToken)
        XCTAssertFalse(coordinator.resume(slotID: slotID))
        XCTAssertEqual(service.spokenRequests.count, 1)
        XCTAssertEqual(bridge.advanceCount, 0)
    }

    func testExternalRelocationWhilePausedAtBoundaryInvalidatesRemainingSegments() {
        let doc = document()
        let first = page(
            document: doc,
            start: "a",
            end: "b",
            text: "English sentence. 中文句子。"
        )
        let second = page(document: doc, start: "c", end: "d", text: "Manual page.")
        let bridge = CalibreTestReaderBridge(slotID: slotID, pages: [first, second])
        let service = CalibreTestSpeechService()
        service.finishDuringPause = true
        let (coordinator, session) = makeCoordinator(bridge: bridge, service: service)

        XCTAssertTrue(coordinator.readCurrentPage(slotID: slotID))
        service.emitStart()
        let oldToken = try! XCTUnwrap(service.spokenRequests.first?.transportToken)
        XCTAssertTrue(coordinator.pause(slotID: slotID))
        service.emitFinish(token: oldToken)
        XCTAssertEqual(coordinator.state, .pausedAtBoundary)

        bridge.emitRelocation(second, token: nil)
        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertEqual(service.spokenRequests.count, 1)
        XCTAssertEqual(bridge.advanceCount, 0)
        XCTAssertNil(session.activeSourceSessionKind)
        XCTAssertFalse(coordinator.isSpeechProtectionActive)
    }

    func testManualCrossSourceReadStopsCalibreBeforeChatGPTAdmission() {
        let doc = document()
        let first = page(document: doc, start: "a", end: "b", text: "Page.")
        let bridge = CalibreTestReaderBridge(slotID: slotID, pages: [first])
        let service = CalibreTestSpeechService()
        let (coordinator, session) = makeCoordinator(bridge: bridge, service: service)
        let chatSlot = UUID()
        let chatSource = CalibreStubSpeechSource(slotID: chatSlot)
        let calibreSource = CalibreSpeechSourceAdapter(
            coordinator: coordinator,
            playbackSession: session,
            activeSlotIDProvider: { chatSlot }
        )
        var activeSlot = slotID
        let router = SpeechCommandRouter(
            sources: [chatSource, calibreSource],
            playbackSession: session,
            activeSlotIDProvider: { activeSlot }
        )

        XCTAssertTrue(coordinator.readCurrentPage(slotID: slotID))
        service.emitStart()
        activeSlot = chatSlot
        XCTAssertEqual(
            router.readLatestForActiveSlot(),
            .manualReadAccepted(sourceKind: .chatGPT, slotID: chatSlot)
        )
        XCTAssertNil(session.activeSourceSessionKind)
        XCTAssertEqual(chatSource.readCount, 1)
    }

    func testChatGPTAutoSpeakIsSuppressedBeforeAutomaticBridgeAdmission() {
        let service = CalibreTestSpeechService()
        let session = SpeechPlaybackSessionController(speechService: service)
        let bridge = CalibreTestResponseBridge()
        let webView = WKWebView(frame: .zero)
        let coordinator = AssistantSpeechCoordinator(
            playbackSession: session,
            webViewProvider: { _ in webView },
            responseBridgeProvider: { _ in bridge },
            activeSlotIDProvider: { self.slotID },
            automaticSpeechSuppressed: { _ in true }
        )

        _ = ChatGPTSpeechSourceAdapter(
            coordinator: coordinator,
            playbackSession: session
        )
        coordinator.toggleAutoSpeak(for: slotID)
        _ = session.acquireSourceSession(
            sourceKind: .calibreReader,
            slotID: slotID
        )
        coordinator.handle(.generationFinished, for: slotID)

        XCTAssertEqual(bridge.requestCount, 0)
    }
}
