import WebKit
import XCTest
@testable import FloatTabs

@MainActor
private final class CalibreTestSpeechService: SpeechSynthesizing {
    private(set) var spokenRequests: [SpeechPlaybackRequest] = []
    private(set) var stopCount = 0

    var onUtteranceStarted: ((UInt64) -> Void)?
    var onUtteranceFinished: ((UInt64) -> Void)?
    var onUtterancePaused: ((UInt64) -> Void)?
    var onUtteranceContinued: ((UInt64) -> Void)?
    var onUtteranceCancelled: ((UInt64) -> Void)?

    func speak(_ request: SpeechPlaybackRequest) {
        spokenRequests.append(request)
    }

    func pause() -> Bool { true }
    func resume() -> Bool { true }
    func stop() { stopCount += 1 }

    func emitStart() {
        guard let token = spokenRequests.last?.transportToken else { return }
        onUtteranceStarted?(token)
    }

    func emitFinish() {
        guard let token = spokenRequests.last?.transportToken else { return }
        onUtteranceFinished?(token)
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
    var deferAdvanceFailure = false
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
        completion(.success(currentPage))
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
        pendingAdvanceFailure = nil
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
    private(set) var requestCount = 0

    func extractLatest(completion: @escaping @MainActor (ChatGPTResponsePayload?) -> Void) {
        requestCount += 1
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

    func testPauseAtBoundaryResumesOnceIntoAdvance() {
        let doc = document()
        let first = page(document: doc, start: "a", end: "b", text: "Page.")
        let bridge = CalibreTestReaderBridge(slotID: slotID, pages: [first])
        let service = CalibreTestSpeechService()
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
