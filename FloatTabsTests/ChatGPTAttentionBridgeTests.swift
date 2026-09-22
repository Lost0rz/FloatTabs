import WebKit
import XCTest
@testable import FloatTabs

/// Collects observations from one detached bridge so tests can drive the
/// exact production acceptance pipeline without a live page.
@MainActor
private final class ChatGPTAttentionBridgeHarness {
    private final class ProbeSequence {
        var values: [Any?]
        private(set) var count = 0

        init(values: [Any?]) {
            self.values = values
        }

        func next() -> Any? {
            count += 1
            guard !values.isEmpty else { return nil }
            return values.removeFirst()
        }
    }

    private final class ObservationLog {
        private(set) var entries: [ChatGPTAttentionObservation] = []

        func record(_ observation: ChatGPTAttentionObservation) {
            entries.append(observation)
        }
    }

    let slotID = UUID()
    let webView = WKWebView()
    let bridge: ChatGPTAttentionBridge
    private let log = ObservationLog()

    var observations: [ChatGPTAttentionObservation] { log.entries }

    init(probeValues: [Any?] = []) {
        // The observation callback must not capture the harness itself before
        // initialization completes; the log reference it captures is enough.
        let log = self.log
        let probes = ProbeSequence(values: probeValues)
        bridge = ChatGPTAttentionBridge(
            slotID: slotID,
            onObservation: { _, observation in
                log.record(observation)
            },
            livenessProbe: { _ in
                probes.next()
            },
            livenessSleeper: { nanoseconds in
                nanoseconds == ChatGPTAttentionBridge.livenessConfirmationDelayNanoseconds
            }
        )
        bridge.attach(to: webView)
        probeCount = { probes.count }
    }

    private(set) var probeCount: () -> Int = { 0 }

    func accept(
        _ generating: Bool,
        token: String,
        host: String = "chatgpt.com",
        originProtocol: String = "https",
        isMainFrame: Bool = true,
        kind: String = ChatGPTBridgePayload.baselineKind,
        messageWebView: WKWebView? = nil
    ) {
        bridge.accept(
            payload: ChatGPTBridgePayload(
                version: ChatGPTBridgePayload.currentVersion,
                kind: kind,
                token: token,
                generating: generating
            ),
            messageWebView: messageWebView ?? webView,
            isMainFrame: isMainFrame,
            originHost: host,
            originProtocol: originProtocol
        )
    }
}

@MainActor
private final class LivenessProbeGate {
    private var queuedValues: [Any?] = []
    private var suspendedContinuations: [CheckedContinuation<Any?, Never>] = []
    private var callWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private(set) var callCount = 0

    func next() async -> Any? {
        callCount += 1
        let readyWaiters = callWaiters.filter { $0.0 <= callCount }
        callWaiters.removeAll { $0.0 <= callCount }
        readyWaiters.forEach { $0.1.resume() }

        if !queuedValues.isEmpty {
            return queuedValues.removeFirst()
        }
        return await withCheckedContinuation { continuation in
            suspendedContinuations.append(continuation)
        }
    }

    func enqueue(_ values: [Any?]) {
        queuedValues.append(contentsOf: values)
    }

    func waitForCall(_ expectedCallCount: Int) async {
        guard callCount < expectedCallCount else { return }
        await withCheckedContinuation { continuation in
            callWaiters.append((expectedCallCount, continuation))
        }
    }

    func resumeSuspended(_ value: Any?) {
        precondition(!suspendedContinuations.isEmpty)
        suspendedContinuations.removeFirst().resume(returning: value)
    }
}

@MainActor
private final class LivenessConfirmationGate {
    private var continuations: [Int: CheckedContinuation<Bool, Never>] = [:]
    private var callWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private(set) var callCount = 0

    var isWaiting: Bool { !continuations.isEmpty }

    func sleep(_ nanoseconds: UInt64) async -> Bool {
        guard nanoseconds == ChatGPTAttentionBridge.livenessConfirmationDelayNanoseconds else {
            return false
        }
        callCount += 1
        let callIndex = callCount
        let readyWaiters = callWaiters.filter { $0.0 <= callCount }
        callWaiters.removeAll { $0.0 <= callCount }
        readyWaiters.forEach { $0.1.resume() }
        return await withCheckedContinuation { continuation in
            continuations[callIndex] = continuation
        }
    }

    func waitForCall(_ expectedCallCount: Int) async {
        guard callCount < expectedCallCount else { return }
        await withCheckedContinuation { continuation in
            callWaiters.append((expectedCallCount, continuation))
        }
    }

    func resume(call callIndex: Int) {
        guard let continuation = continuations.removeValue(forKey: callIndex) else { return }
        continuation.resume(returning: true)
    }

    func resume() {
        guard let callIndex = continuations.keys.min() else { return }
        resume(call: callIndex)
    }
}

@MainActor
final class ChatGPTAttentionBridgeTests: XCTestCase {
    private var tokenA: String!
    private var tokenB: String!

    override func setUp() {
        super.setUp()
        tokenA = UUID().uuidString
        tokenB = UUID().uuidString
    }

    override func tearDown() {
        tokenA = nil
        tokenB = nil
        super.tearDown()
    }

    // MARK: - Shared host policy

    func testChatGPTHostIsAccepted() throws {
        XCTAssertTrue(ChatGPTSitePolicy.isSupportedHost("chatgpt.com"))
        XCTAssertTrue(ChatGPTSitePolicy.isSupportedChatGPTURL(URL(string: "https://chatgpt.com/c/abc")!))
    }

    func testChatGPTSubdomainHostsAreAccepted() throws {
        XCTAssertTrue(ChatGPTSitePolicy.isSupportedHost("www.chatgpt.com"))
        XCTAssertTrue(ChatGPTSitePolicy.isSupportedHost("new.chatgpt.com"))
        XCTAssertTrue(ChatGPTSitePolicy.isSupportedChatGPTURL(URL(string: "https://new.chatgpt.com/")!))
    }

    func testLegacyOpenAIChatHostIsAccepted() throws {
        XCTAssertTrue(ChatGPTSitePolicy.isSupportedHost("chat.openai.com"))
        XCTAssertTrue(ChatGPTSitePolicy.isSupportedChatGPTURL(URL(string: "https://chat.openai.com/c/1")!))
    }

    func testLookalikeAndUnrelatedHostsAreRejected() throws {
        XCTAssertFalse(ChatGPTSitePolicy.isSupportedHost("evilchatgpt.com"))
        XCTAssertFalse(ChatGPTSitePolicy.isSupportedHost("chatgpt.com.evil.example"))
        XCTAssertFalse(ChatGPTSitePolicy.isSupportedHost("notchatgpt.com"))
        XCTAssertFalse(ChatGPTSitePolicy.isSupportedHost("openai.com"))
        XCTAssertFalse(ChatGPTSitePolicy.isSupportedHost("platform.openai.com"))
        XCTAssertFalse(ChatGPTSitePolicy.isSupportedHost(""))
        XCTAssertFalse(ChatGPTSitePolicy.isSupportedChatGPTURL(URL(string: "ftp://chatgpt.com/")!))
        XCTAssertFalse(ChatGPTSitePolicy.isSupportedChatGPTURL(URL(string: "about:blank")!))
    }

    func testChatGPTAutomaticMobileCompatibilityIdentityIsUnchanged() throws {
        let mobile = WebRenderingProfile.canonicalDefault.settingWebsiteMode(.mobile)

        XCTAssertEqual(
            SiteCompatibilityPolicy.runtimeRendering(
                for: mobile,
                navigationURL: URL(string: "https://chatgpt.com/")!
            ),
            mobile.settingBrowserIdentity(.macosSafari)
        )
        XCTAssertEqual(
            SiteCompatibilityPolicy.runtimeRendering(
                for: mobile,
                navigationURL: URL(string: "https://new.chatgpt.com/")!
            ),
            mobile.settingBrowserIdentity(.macosSafari)
        )
        XCTAssertEqual(
            SiteCompatibilityPolicy.runtimeRendering(
                for: mobile,
                navigationURL: URL(string: "https://chat.openai.com/")!
            ),
            mobile.settingBrowserIdentity(.macosSafari)
        )

        // Unrelated and lookalike hosts keep the user-selected identity.
        XCTAssertEqual(
            SiteCompatibilityPolicy.runtimeRendering(
                for: mobile,
                navigationURL: URL(string: "https://evilchatgpt.com/")!
            ),
            mobile
        )
        // The override remains Automatic+Mobile only.
        XCTAssertEqual(
            SiteCompatibilityPolicy.runtimeRendering(
                for: WebRenderingProfile.canonicalDefault,
                navigationURL: URL(string: "https://chatgpt.com/")!
            ),
            WebRenderingProfile.canonicalDefault
        )
    }

    // MARK: - Installation

    func testInstalledUserScriptInjectsAtDocumentStart() throws {
        let controller = WKUserContentController()
        let harness = ChatGPTAttentionBridgeHarness()

        harness.bridge.install(into: controller)

        XCTAssertEqual(controller.userScripts.count, 1)
        XCTAssertEqual(controller.userScripts.first?.injectionTime, .atDocumentStart)
    }

    func testInstalledUserScriptIsMainFrameOnly() throws {
        let controller = WKUserContentController()
        let harness = ChatGPTAttentionBridgeHarness()

        harness.bridge.install(into: controller)

        XCTAssertEqual(controller.userScripts.first?.isForMainFrameOnly, true)
    }

    func testInstalledUserScriptUsesNamedContentWorld() throws {
        // pageWorld/defaultClientWorld carry no name; a named client world is
        // distinct from both, and one instance is shared by script, handler,
        // and invalidation.
        XCTAssertEqual(
            ChatGPTAttentionBridge.contentWorld.name,
            ChatGPTAttentionBridge.contentWorldName
        )
        XCTAssertFalse(ChatGPTAttentionBridge.contentWorld.name?.isEmpty == true)
    }

    func testInstalledScriptExposesOnlyTheNarrowNamedWorldResyncEntry() throws {
        XCTAssertTrue(
            ChatGPTAttentionBridge.scriptSource.contains(
                "globalThis.__floatTabsAttentionResyncV1"
            )
        )
        XCTAssertEqual(
            ChatGPTAttentionBridge.contentWorld.name,
            ChatGPTAttentionBridge.contentWorldName
        )
    }

    func testInstalledScriptExposesReadOnlyLivenessProbeContract() throws {
        let source = ChatGPTAttentionBridge.scriptSource
        let marker = "globalThis.__floatTabsAttentionProbeV1 = () => {"
        let start = try XCTUnwrap(source.range(of: marker)?.lowerBound)
        let end = try XCTUnwrap(source.range(of: "};", range: start..<source.endIndex)?.upperBound)
        let probe = String(source[start..<end])

        XCTAssertTrue(probe.contains("version: 1"))
        XCTAssertTrue(probe.contains("kind: \"baseline\""))
        XCTAssertTrue(probe.contains("token: TOKEN"))
        XCTAssertTrue(probe.contains("generating: generating"))
        XCTAssertTrue(probe.contains("isGenerating()"))
        XCTAssertFalse(probe.contains("lastSent"))
        XCTAssertFalse(probe.contains("postMessage"))
        XCTAssertFalse(probe.contains("setTimeout"))
        XCTAssertFalse(probe.contains("MutationObserver"))
    }

    func testBridgeConfiguredBeforeInitialLoad() throws {
        var hadBridgeScriptAtFirstLoad = false
        let pool = WebViewPool(
            onURLChange: { _, _ in },
            initialLoad: { webView, _ in
                hadBridgeScriptAtFirstLoad = webView.configuration.userContentController.userScripts
                    .contains { $0.isForMainFrameOnly }
            }
        )

        _ = try pool.webView(for: makeChatGPTProfile())

        // The Factory-owned hidden-scrollbar script is document-start but
        // not main-frame-only, so the flag can only be set by the bridge.
        XCTAssertTrue(hadBridgeScriptAtFirstLoad)
    }

    func testInvalidationKeepsUnrelatedUserScripts() throws {
        let controller = WKUserContentController()
        controller.addUserScript(
            WKUserScript(
                source: "/* unrelated */",
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: false
            )
        )
        let harness = ChatGPTAttentionBridgeHarness()
        harness.bridge.install(into: controller)
        XCTAssertEqual(controller.userScripts.count, 2)

        harness.bridge.invalidate()

        XCTAssertEqual(controller.userScripts.count, 2)
        XCTAssertTrue(controller.userScripts.contains { $0.source == "/* unrelated */" })
    }

    // MARK: - Message validation

    func testPayloadValidationRejectsMalformedBodies() throws {
        XCTAssertNil(ChatGPTBridgePayload.parse([:]))
        XCTAssertNil(ChatGPTBridgePayload.parse([
            "version": 2, "kind": "baseline", "token": "12345678", "generating": true,
        ]))
        XCTAssertNil(ChatGPTBridgePayload.parse([
            "version": 1, "kind": "unexpected", "token": "12345678", "generating": true,
        ]))
        XCTAssertNil(ChatGPTBridgePayload.parse([
            "version": 1, "kind": "baseline", "token": "short", "generating": true,
        ]))
        XCTAssertNil(ChatGPTBridgePayload.parse([
            "version": 1, "kind": "baseline", "token": "12345678", "generating": "yes",
        ]))
        XCTAssertEqual(
            ChatGPTBridgePayload.parse([
                "version": 1, "kind": "state", "token": "12345678", "generating": false,
            ]),
            ChatGPTBridgePayload(
                version: 1, kind: "state", token: "12345678", generating: false
            )
        )
    }

    func testMessageFromOtherWebViewIsRejected() throws {
        let harness = ChatGPTAttentionBridgeHarness()
        let otherWebView = WKWebView()

        harness.accept(true, token: tokenA, messageWebView: otherWebView)
        XCTAssertTrue(harness.observations.isEmpty)

        harness.accept(true, token: tokenA)
        XCTAssertEqual(harness.observations, [.generationStarted])
    }

    func testNonMainFrameMessageIsRejected() throws {
        let harness = ChatGPTAttentionBridgeHarness()

        harness.bridge.accept(
            payload: ChatGPTBridgePayload(
                version: 1, kind: "baseline", token: tokenA, generating: true
            ),
            messageWebView: harness.webView,
            isMainFrame: false,
            originHost: "chatgpt.com",
            originProtocol: "https"
        )

        XCTAssertTrue(harness.observations.isEmpty)
    }

    func testUnsupportedOriginEmitsNothing() throws {
        let harness = ChatGPTAttentionBridgeHarness()

        harness.accept(true, token: tokenA, host: "evilchatgpt.com")
        harness.accept(true, token: tokenA, host: "openai.com")
        harness.accept(true, token: tokenA, host: "chatgpt.com.evil.example")
        harness.accept(true, token: tokenA, host: "chatgpt.com", originProtocol: "about")

        XCTAssertTrue(harness.observations.isEmpty)
    }

    // MARK: - Baseline and transition semantics

    func testIdleBaselineEmitsNoFinish() throws {
        let harness = ChatGPTAttentionBridgeHarness()

        harness.accept(false, token: tokenA)

        XCTAssertTrue(harness.observations.isEmpty)
    }

    func testGeneratingBaselineEmitsOneStart() throws {
        let harness = ChatGPTAttentionBridgeHarness()

        harness.accept(true, token: tokenA)

        XCTAssertEqual(harness.observations, [.generationStarted])
    }

    func testDuplicateGeneratingEmitsNothing() throws {
        let harness = ChatGPTAttentionBridgeHarness()

        harness.accept(true, token: tokenA)
        harness.accept(true, token: tokenA)

        XCTAssertEqual(harness.observations, [.generationStarted])
    }

    func testIdleBaselineDoesNotActivateLivenessWatchdog() throws {
        let harness = ChatGPTAttentionBridgeHarness()

        harness.accept(false, token: tokenA)

        XCTAssertFalse(harness.bridge.debugLivenessWatchdogActive)
        XCTAssertEqual(harness.bridge.debugLivenessWatchdogStartCount, 0)
    }

    func testGeneratingBaselineActivatesOneLivenessWatchdogAndDuplicateStartDoesNotDuplicateIt() throws {
        let harness = ChatGPTAttentionBridgeHarness()

        harness.accept(true, token: tokenA)
        harness.accept(true, token: tokenA, kind: ChatGPTBridgePayload.stateKind)

        XCTAssertTrue(harness.bridge.debugLivenessWatchdogActive)
        XCTAssertEqual(harness.bridge.debugLivenessWatchdogStartCount, 1)
    }

    func testTrueLivenessProbeKeepsGenerationActiveWithoutDuplicateStart() async throws {
        let trueProbe: [String: Any] = [
            "version": 1,
            "kind": "baseline",
            "token": tokenA!,
            "generating": true
        ]
        let harness = ChatGPTAttentionBridgeHarness(probeValues: [trueProbe])

        harness.accept(true, token: tokenA)
        await harness.bridge.debugRunLivenessCycle()

        XCTAssertEqual(harness.observations, [.generationStarted])
        XCTAssertTrue(harness.bridge.debugLivenessWatchdogActive)
        XCTAssertEqual(harness.probeCount(), 1)
    }

    func testFalseFalseLivenessProbeEmitsOneFinishAndStopsWatchdog() async throws {
        let falseProbe: [String: Any] = [
            "version": 1,
            "kind": "baseline",
            "token": tokenA!,
            "generating": false
        ]
        let harness = ChatGPTAttentionBridgeHarness(probeValues: [falseProbe, falseProbe])

        harness.accept(true, token: tokenA)
        await harness.bridge.debugRunLivenessCycle()

        XCTAssertEqual(harness.observations, [.generationStarted, .generationFinished])
        XCTAssertFalse(harness.bridge.debugLivenessWatchdogActive)
        XCTAssertEqual(harness.probeCount(), 2)
    }

    func testFalseThenTrueLivenessProbeDoesNotFinishOrStopWatchdog() async throws {
        let falseProbe: [String: Any] = [
            "version": 1,
            "kind": "baseline",
            "token": tokenA!,
            "generating": false
        ]
        let trueProbe: [String: Any] = [
            "version": 1,
            "kind": "baseline",
            "token": tokenA!,
            "generating": true
        ]
        let harness = ChatGPTAttentionBridgeHarness(probeValues: [falseProbe, trueProbe])

        harness.accept(true, token: tokenA)
        await harness.bridge.debugRunLivenessCycle()

        XCTAssertEqual(harness.observations, [.generationStarted])
        XCTAssertTrue(harness.bridge.debugLivenessWatchdogActive)
        XCTAssertEqual(harness.probeCount(), 2)
    }

    func testNaturalFinishBeforeManualCycleRemainsSingleEmission() async throws {
        let falseProbe: [String: Any] = [
            "version": 1,
            "kind": "baseline",
            "token": tokenA!,
            "generating": false
        ]
        let harness = ChatGPTAttentionBridgeHarness(probeValues: [falseProbe, falseProbe])

        harness.accept(true, token: tokenA)
        harness.accept(false, token: tokenA, kind: ChatGPTBridgePayload.stateKind)
        await harness.bridge.debugRunLivenessCycle()

        XCTAssertEqual(harness.observations, [.generationStarted, .generationFinished])
        XCTAssertFalse(harness.bridge.debugLivenessWatchdogActive)
    }

    func testOldProbeDoesNotBlockNewEpochLivenessCycle() async throws {
        let probes = LivenessProbeGate()
        var observations: [ChatGPTAttentionObservation] = []
        let bridge = ChatGPTAttentionBridge(
            slotID: UUID(),
            onObservation: { _, observation in
                observations.append(observation)
            },
            livenessProbe: { _ in await probes.next() },
            livenessSleeper: { nanoseconds in
                nanoseconds == ChatGPTAttentionBridge.livenessConfirmationDelayNanoseconds
            }
        )
        let webView = WKWebView()
        bridge.attach(to: webView)
        bridge.accept(
            payload: ChatGPTBridgePayload(
                version: 1,
                kind: ChatGPTBridgePayload.baselineKind,
                token: tokenA,
                generating: true
            ),
            messageWebView: webView,
            isMainFrame: true,
            originHost: "chatgpt.com",
            originProtocol: "https"
        )

        let oldCycle = Task { @MainActor in
            await bridge.debugRunLivenessCycle()
        }
        await probes.waitForCall(1)

        bridge.handleRuntimeReplacement()
        bridge.accept(
            payload: ChatGPTBridgePayload(
                version: 1,
                kind: ChatGPTBridgePayload.baselineKind,
                token: tokenB,
                generating: true
            ),
            messageWebView: webView,
            isMainFrame: true,
            originHost: "chatgpt.com",
            originProtocol: "https"
        )
        probes.enqueue([
            ["version": 1, "kind": "baseline", "token": tokenB!, "generating": false],
            ["version": 1, "kind": "baseline", "token": tokenB!, "generating": false]
        ])

        await bridge.debugRunLivenessCycle()
        XCTAssertEqual(
            observations,
            [.generationStarted, .runtimeReset, .generationStarted, .generationFinished]
        )

        probes.resumeSuspended([
            "version": 1,
            "kind": "baseline",
            "token": tokenA!,
            "generating": false
        ])
        await oldCycle.value
        XCTAssertEqual(observations.filter { $0 == .generationFinished }.count, 1)
    }

    func testStaleProbeCannotClearNewCycleOwnerDuringConfirmation() async throws {
        let probes = LivenessProbeGate()
        let confirmation = LivenessConfirmationGate()
        var observations: [ChatGPTAttentionObservation] = []
        let bridge = ChatGPTAttentionBridge(
            slotID: UUID(),
            onObservation: { _, observation in
                observations.append(observation)
            },
            livenessProbe: { _ in await probes.next() },
            livenessSleeper: { nanoseconds in
                await confirmation.sleep(nanoseconds)
            }
        )
        let webView = WKWebView()
        bridge.attach(to: webView)
        bridge.accept(
            payload: ChatGPTBridgePayload(
                version: 1,
                kind: ChatGPTBridgePayload.baselineKind,
                token: tokenA,
                generating: true
            ),
            messageWebView: webView,
            isMainFrame: true,
            originHost: "chatgpt.com",
            originProtocol: "https"
        )

        let oldCycle = Task { @MainActor in
            await bridge.debugRunLivenessCycle()
        }
        await probes.waitForCall(1)
        bridge.handleRuntimeReplacement()
        bridge.accept(
            payload: ChatGPTBridgePayload(
                version: 1,
                kind: ChatGPTBridgePayload.baselineKind,
                token: tokenB,
                generating: true
            ),
            messageWebView: webView,
            isMainFrame: true,
            originHost: "chatgpt.com",
            originProtocol: "https"
        )
        probes.enqueue([
            ["version": 1, "kind": "baseline", "token": tokenB!, "generating": false],
            ["version": 1, "kind": "baseline", "token": tokenB!, "generating": false]
        ])

        let newCycle = Task { @MainActor in
            await bridge.debugRunLivenessCycle()
        }
        for _ in 0..<32 where !confirmation.isWaiting {
            await Task.yield()
        }
        XCTAssertTrue(confirmation.isWaiting)

        probes.resumeSuspended([
            "version": 1,
            "kind": "baseline",
            "token": tokenA!,
            "generating": false
        ])
        confirmation.resume()
        await newCycle.value
        await oldCycle.value

        XCTAssertEqual(observations.filter { $0 == .generationFinished }.count, 1)
        XCTAssertEqual(
            observations,
            [.generationStarted, .runtimeReset, .generationStarted, .generationFinished]
        )
    }

    func testStaleConfirmationFirstThenNewFinish() async throws {
        let probes = LivenessProbeGate()
        let confirmation = LivenessConfirmationGate()
        var observations: [ChatGPTAttentionObservation] = []
        let bridge = ChatGPTAttentionBridge(
            slotID: UUID(),
            onObservation: { _, observation in
                observations.append(observation)
            },
            livenessProbe: { _ in await probes.next() },
            livenessSleeper: { nanoseconds in
                await confirmation.sleep(nanoseconds)
            }
        )
        let webView = WKWebView()
        bridge.attach(to: webView)
        bridge.accept(
            payload: ChatGPTBridgePayload(
                version: 1,
                kind: ChatGPTBridgePayload.baselineKind,
                token: tokenA,
                generating: true
            ),
            messageWebView: webView,
            isMainFrame: true,
            originHost: "chatgpt.com",
            originProtocol: "https"
        )
        probes.enqueue([["version": 1, "kind": "baseline", "token": tokenA!, "generating": false]])

        let oldCycle = Task { @MainActor in
            await bridge.debugRunLivenessCycle()
        }
        await confirmation.waitForCall(1)

        bridge.handleRuntimeReplacement()
        bridge.accept(
            payload: ChatGPTBridgePayload(
                version: 1,
                kind: ChatGPTBridgePayload.baselineKind,
                token: tokenB,
                generating: true
            ),
            messageWebView: webView,
            isMainFrame: true,
            originHost: "chatgpt.com",
            originProtocol: "https"
        )
        probes.enqueue([
            ["version": 1, "kind": "baseline", "token": tokenB!, "generating": false],
            ["version": 1, "kind": "baseline", "token": tokenB!, "generating": false]
        ])

        let newCycle = Task { @MainActor in
            await bridge.debugRunLivenessCycle()
        }
        await confirmation.waitForCall(2)

        confirmation.resume(call: 1)
        await oldCycle.value
        XCTAssertEqual(
            observations,
            [.generationStarted, .runtimeReset, .generationStarted]
        )

        confirmation.resume(call: 2)
        await newCycle.value

        XCTAssertEqual(
            observations,
            [.generationStarted, .runtimeReset, .generationStarted, .generationFinished]
        )
        XCTAssertFalse(bridge.debugLivenessWatchdogActive)
    }

    func testNewFinishFirstThenStaleCallback() async throws {
        let probes = LivenessProbeGate()
        let confirmation = LivenessConfirmationGate()
        let writer = RuntimeDiagnosticInMemoryWriter()
        let diagnostics = RuntimeDiagnostics(mode: .verbose, writer: writer)
        var observations: [ChatGPTAttentionObservation] = []
        let bridge = ChatGPTAttentionBridge(
            slotID: UUID(),
            onObservation: { _, observation in
                observations.append(observation)
            },
            diagnostics: diagnostics,
            livenessProbe: { _ in await probes.next() },
            livenessSleeper: { nanoseconds in
                await confirmation.sleep(nanoseconds)
            }
        )
        let webView = WKWebView()
        bridge.attach(to: webView)
        bridge.accept(
            payload: ChatGPTBridgePayload(
                version: 1,
                kind: ChatGPTBridgePayload.baselineKind,
                token: tokenA,
                generating: true
            ),
            messageWebView: webView,
            isMainFrame: true,
            originHost: "chatgpt.com",
            originProtocol: "https"
        )
        probes.enqueue([["version": 1, "kind": "baseline", "token": tokenA!, "generating": false]])

        let oldCycle = Task { @MainActor in
            await bridge.debugRunLivenessCycle()
        }
        await confirmation.waitForCall(1)

        bridge.handleRuntimeReplacement()
        bridge.accept(
            payload: ChatGPTBridgePayload(
                version: 1,
                kind: ChatGPTBridgePayload.baselineKind,
                token: tokenB,
                generating: true
            ),
            messageWebView: webView,
            isMainFrame: true,
            originHost: "chatgpt.com",
            originProtocol: "https"
        )
        probes.enqueue([
            ["version": 1, "kind": "baseline", "token": tokenB!, "generating": false],
            ["version": 1, "kind": "baseline", "token": tokenB!, "generating": false]
        ])

        let newCycle = Task { @MainActor in
            await bridge.debugRunLivenessCycle()
        }
        await confirmation.waitForCall(2)

        confirmation.resume(call: 2)
        await newCycle.value
        XCTAssertEqual(
            observations,
            [.generationStarted, .runtimeReset, .generationStarted, .generationFinished]
        )
        XCTAssertFalse(bridge.debugLivenessWatchdogActive)

        confirmation.resume(call: 1)
        await oldCycle.value

        XCTAssertEqual(
            observations,
            [.generationStarted, .runtimeReset, .generationStarted, .generationFinished]
        )
        XCTAssertEqual(
            writer.events.filter { $0.event == "attention.liveness_probe.recovered_completion" }.count,
            1
        )
    }

    func testNaturalFinishWinsWatchdogRaceWithSingleEmission() async throws {
        let probes = LivenessProbeGate()
        let confirmation = LivenessConfirmationGate()
        let writer = RuntimeDiagnosticInMemoryWriter()
        let diagnostics = RuntimeDiagnostics(mode: .verbose, writer: writer)
        var observations: [ChatGPTAttentionObservation] = []
        var completionCallbackCount = 0
        let bridge = ChatGPTAttentionBridge(
            slotID: UUID(),
            onObservation: { _, observation in
                observations.append(observation)
                if observation == .generationFinished {
                    completionCallbackCount += 1
                }
            },
            diagnostics: diagnostics,
            livenessProbe: { _ in await probes.next() },
            livenessSleeper: { nanoseconds in
                await confirmation.sleep(nanoseconds)
            }
        )
        let webView = WKWebView()
        bridge.attach(to: webView)
        bridge.accept(
            payload: ChatGPTBridgePayload(
                version: 1,
                kind: ChatGPTBridgePayload.baselineKind,
                token: tokenA,
                generating: true
            ),
            messageWebView: webView,
            isMainFrame: true,
            originHost: "chatgpt.com",
            originProtocol: "https"
        )
        probes.enqueue([
            ["version": 1, "kind": "baseline", "token": tokenA!, "generating": false],
            ["version": 1, "kind": "baseline", "token": tokenA!, "generating": false]
        ])

        let cycle = Task { @MainActor in
            await bridge.debugRunLivenessCycle()
        }
        for _ in 0..<32 where !confirmation.isWaiting {
            await Task.yield()
        }
        XCTAssertTrue(confirmation.isWaiting)

        bridge.accept(
            payload: ChatGPTBridgePayload(
                version: 1,
                kind: ChatGPTBridgePayload.stateKind,
                token: tokenA,
                generating: false
            ),
            messageWebView: webView,
            isMainFrame: true,
            originHost: "chatgpt.com",
            originProtocol: "https"
        )
        confirmation.resume()
        await cycle.value

        XCTAssertEqual(observations, [.generationStarted, .generationFinished])
        XCTAssertEqual(completionCallbackCount, 1)
        XCTAssertFalse(bridge.debugLivenessWatchdogActive)
        XCTAssertFalse(writer.events.contains { $0.event == "attention.liveness_probe.recovered_completion" })
    }

    func testAttachmentReplacementRejectsStaleProbeBeforeNewDocumentCompletes() async throws {
        let probes = LivenessProbeGate()
        var observations: [ChatGPTAttentionObservation] = []
        let bridge = ChatGPTAttentionBridge(
            slotID: UUID(),
            onObservation: { _, observation in
                observations.append(observation)
            },
            livenessProbe: { _ in await probes.next() },
            livenessSleeper: { nanoseconds in
                nanoseconds == ChatGPTAttentionBridge.livenessConfirmationDelayNanoseconds
            }
        )
        let webViewA = WKWebView()
        let webViewB = WKWebView()
        bridge.attach(to: webViewA)
        bridge.accept(
            payload: ChatGPTBridgePayload(
                version: 1,
                kind: ChatGPTBridgePayload.baselineKind,
                token: tokenA,
                generating: true
            ),
            messageWebView: webViewA,
            isMainFrame: true,
            originHost: "chatgpt.com",
            originProtocol: "https"
        )
        let oldCycle = Task { @MainActor in
            await bridge.debugRunLivenessCycle()
        }
        await probes.waitForCall(1)

        bridge.attach(to: webViewB)
        bridge.accept(
            payload: ChatGPTBridgePayload(
                version: 1,
                kind: ChatGPTBridgePayload.baselineKind,
                token: tokenB,
                generating: true
            ),
            messageWebView: webViewB,
            isMainFrame: true,
            originHost: "chatgpt.com",
            originProtocol: "https"
        )
        probes.enqueue([
            ["version": 1, "kind": "baseline", "token": tokenB!, "generating": false],
            ["version": 1, "kind": "baseline", "token": tokenB!, "generating": false]
        ])
        await bridge.debugRunLivenessCycle()
        probes.resumeSuspended([
            "version": 1,
            "kind": "baseline",
            "token": tokenA!,
            "generating": false
        ])
        await oldCycle.value

        XCTAssertEqual(observations.filter { $0 == .generationFinished }.count, 1)
        XCTAssertEqual(observations.last, .generationFinished)
    }

    func testStaleNavigationProbeRejectedAfterCommittedBoundary() async throws {
        let probes = LivenessProbeGate()
        let writer = RuntimeDiagnosticInMemoryWriter()
        let diagnostics = RuntimeDiagnostics(mode: .verbose, writer: writer)
        var observations: [ChatGPTAttentionObservation] = []
        let bridge = ChatGPTAttentionBridge(
            slotID: UUID(),
            onObservation: { _, observation in
                observations.append(observation)
            },
            diagnostics: diagnostics,
            livenessProbe: { _ in await probes.next() },
            livenessSleeper: { nanoseconds in
                nanoseconds == ChatGPTAttentionBridge.livenessConfirmationDelayNanoseconds
            }
        )
        let webView = WKWebView()
        bridge.attach(to: webView)
        bridge.accept(
            payload: ChatGPTBridgePayload(
                version: 1,
                kind: ChatGPTBridgePayload.baselineKind,
                token: tokenA,
                generating: true
            ),
            messageWebView: webView,
            isMainFrame: true,
            originHost: "chatgpt.com",
            originProtocol: "https"
        )
        let staleCycle = Task { @MainActor in
            await bridge.debugRunLivenessCycle()
        }
        await probes.waitForCall(1)

        bridge.handleRuntimeReplacement(
            committedURL: URL(string: "https://chatgpt.com/new")
        )
        probes.resumeSuspended([
            "version": 1,
            "kind": "baseline",
            "token": tokenA!,
            "generating": false
        ])
        await staleCycle.value

        XCTAssertEqual(observations, [.generationStarted, .runtimeReset])
        XCTAssertFalse(writer.events.contains { $0.event == "attention.liveness_probe.recovered_completion" })
    }

    func testContentProcessBoundaryRejectsStaleProbeWithoutSyntheticFinish() async throws {
        let probes = LivenessProbeGate()
        let writer = RuntimeDiagnosticInMemoryWriter()
        let diagnostics = RuntimeDiagnostics(mode: .verbose, writer: writer)
        var observations: [ChatGPTAttentionObservation] = []
        let bridge = ChatGPTAttentionBridge(
            slotID: UUID(),
            onObservation: { _, observation in
                observations.append(observation)
            },
            diagnostics: diagnostics,
            livenessProbe: { _ in await probes.next() },
            livenessSleeper: { nanoseconds in
                nanoseconds == ChatGPTAttentionBridge.livenessConfirmationDelayNanoseconds
            }
        )
        let webView = WKWebView()
        bridge.attach(to: webView)
        bridge.accept(
            payload: ChatGPTBridgePayload(
                version: 1,
                kind: ChatGPTBridgePayload.baselineKind,
                token: tokenA,
                generating: true
            ),
            messageWebView: webView,
            isMainFrame: true,
            originHost: "chatgpt.com",
            originProtocol: "https"
        )
        let staleCycle = Task { @MainActor in
            await bridge.debugRunLivenessCycle()
        }
        await probes.waitForCall(1)

        bridge.handleRuntimeReplacement()
        probes.resumeSuspended([
            "version": 1,
            "kind": "baseline",
            "token": tokenA!,
            "generating": false
        ])
        await staleCycle.value

        XCTAssertEqual(observations, [.generationStarted, .runtimeReset])
        XCTAssertFalse(writer.events.contains { $0.event == "attention.liveness_probe.recovered_completion" })
    }

    func testProbeFailureIsDebugOnlyAndLeavesWatchdogRecoverable() async throws {
        let writer = RuntimeDiagnosticInMemoryWriter()
        let diagnostics = RuntimeDiagnostics(mode: .verbose, writer: writer)
        let harness = ChatGPTAttentionBridgeHarness()
        let bridge = ChatGPTAttentionBridge(
            slotID: harness.slotID,
            onObservation: { _, _ in },
            diagnostics: diagnostics,
            livenessProbe: { _ in nil },
            livenessSleeper: { nanoseconds in
                nanoseconds == ChatGPTAttentionBridge.livenessConfirmationDelayNanoseconds
            }
        )
        bridge.attach(to: harness.webView)
        bridge.accept(
            payload: ChatGPTBridgePayload(
                version: 1,
                kind: ChatGPTBridgePayload.baselineKind,
                token: tokenA,
                generating: true
            ),
            messageWebView: harness.webView,
            isMainFrame: true,
            originHost: "chatgpt.com",
            originProtocol: "https"
        )

        await bridge.debugRunLivenessCycle()

        let failure = try XCTUnwrap(
            writer.events.last { $0.event == "attention.liveness_probe.failed" }
        )
        XCTAssertEqual(failure.level, .debug)
        XCTAssertTrue(bridge.debugLivenessWatchdogActive)
    }

    func testPendingInstantBackKeepsCurrentDocumentWatchdogAuthoritative() async throws {
        let falseProbe: [String: Any] = [
            "version": 1,
            "kind": "baseline",
            "token": tokenA!,
            "generating": false
        ]
        let harness = ChatGPTAttentionBridgeHarness(probeValues: [falseProbe, falseProbe])

        harness.accept(true, token: tokenA)
        harness.bridge.beginInstantBackHandoff()
        await harness.bridge.debugRunLivenessCycle()

        XCTAssertTrue(harness.bridge.isInstantBackHandoffPending)
        XCTAssertEqual(harness.observations, [.generationStarted, .generationFinished])
    }

    func testRuntimeReplacementAndInvalidationCancelLivenessWatchdog() throws {
        let harness = ChatGPTAttentionBridgeHarness()
        harness.accept(true, token: tokenA)
        harness.bridge.handleRuntimeReplacement()
        XCTAssertFalse(harness.bridge.debugLivenessWatchdogActive)

        harness.accept(true, token: tokenB)
        XCTAssertTrue(harness.bridge.debugLivenessWatchdogActive)
        harness.bridge.invalidate()
        XCTAssertFalse(harness.bridge.debugLivenessWatchdogActive)
    }

    func testRecoveredVisibleCompletionUsesExistingAttentionRouterAsIdle() async throws {
        let coordinator = WebAttentionCoordinator()
        let slotID = UUID()
        let router = WebAttentionObservationRouter(
            attentionCoordinator: coordinator,
            isUserVisible: { _ in true }
        )
        let probes = [
            [
                "version": 1,
                "kind": "baseline",
                "token": tokenA!,
                "generating": false
            ],
            [
                "version": 1,
                "kind": "baseline",
                "token": tokenA!,
                "generating": false
            ]
        ]
        var remaining = probes
        var completionCallbackCount = 0
        let bridge = ChatGPTAttentionBridge(
            slotID: slotID,
            onObservation: { _, observation in
                router.handle(observation, for: slotID)
                if observation == .generationFinished {
                    completionCallbackCount += 1
                }
            },
            livenessProbe: { _ in
                guard !remaining.isEmpty else { return nil }
                return remaining.removeFirst()
            },
            livenessSleeper: { nanoseconds in
                nanoseconds == ChatGPTAttentionBridge.livenessConfirmationDelayNanoseconds
            }
        )
        let webView = WKWebView()
        bridge.attach(to: webView)
        bridge.accept(
            payload: ChatGPTBridgePayload(
                version: 1,
                kind: ChatGPTBridgePayload.baselineKind,
                token: tokenA,
                generating: true
            ),
            messageWebView: webView,
            isMainFrame: true,
            originHost: "chatgpt.com",
            originProtocol: "https"
        )

        await bridge.debugRunLivenessCycle()

        XCTAssertEqual(coordinator.state(for: slotID), .idle)
        XCTAssertTrue(coordinator.readySlotIDs.isEmpty)
        XCTAssertEqual(completionCallbackCount, 1)
    }

    func testGeneratingToIdleEmitsOneFinish() throws {
        let harness = ChatGPTAttentionBridgeHarness()

        harness.accept(true, token: tokenA)
        harness.accept(false, token: tokenA)

        XCTAssertEqual(harness.observations, [.generationStarted, .generationFinished])
    }

    func testDuplicateIdleEmitsNothing() throws {
        let harness = ChatGPTAttentionBridgeHarness()

        harness.accept(true, token: tokenA)
        harness.accept(false, token: tokenA)
        harness.accept(false, token: tokenA)

        XCTAssertEqual(harness.observations, [.generationStarted, .generationFinished])
    }

    func testTrackerDirectlyMatchesBridgeSemantics() throws {
        var tracker = ChatGPTDocumentGenerationTracker()
        XCTAssertNil(tracker.observe(false))
        XCTAssertNil(tracker.observe(false))
        XCTAssertEqual(tracker.observe(true), .generationStarted)
        XCTAssertNil(tracker.observe(true))
        XCTAssertEqual(tracker.observe(false), .generationFinished)
        XCTAssertNil(tracker.observe(false))
    }

    // MARK: - Navigation lifecycle

    func testProvisionalStartDoesNotResetCurrentDocumentObservations() throws {
        let harness = ChatGPTAttentionBridgeHarness()
        harness.accept(true, token: tokenA)
        harness.accept(false, token: tokenA)

        XCTAssertEqual(
            harness.observations,
            [.generationStarted, .generationFinished]
        )
    }

    func testProvisionalFailureRequiresNoReplayOrRuntimeReset() throws {
        let harness = ChatGPTAttentionBridgeHarness()
        harness.accept(true, token: tokenA)
        harness.accept(false, token: tokenA)

        XCTAssertEqual(harness.observations, [.generationStarted, .generationFinished])
        XCTAssertFalse(harness.observations.contains(.runtimeReset))
    }

    func testCommittedReplacementEmitsRuntimeResetAndClearsEpoch() throws {
        let harness = ChatGPTAttentionBridgeHarness()
        harness.accept(true, token: tokenA)

        harness.bridge.handleRuntimeReplacement()

        XCTAssertEqual(harness.observations.last, .runtimeReset)
    }

    func testUnsupportedCurrentDocumentClosesAdmissionUntilSupportedCommitResync() throws {
        let harness = ChatGPTAttentionBridgeHarness()
        let unsupportedURL = URL(string: "https://example.com/document")!
        let supportedURL = URL(string: "https://chatgpt.com/c/fresh")!

        harness.accept(true, token: tokenA)
        harness.bridge.handleRuntimeReplacement(committedURL: unsupportedURL)
        XCTAssertEqual(harness.observations, [.generationStarted, .runtimeReset])

        // Neither a late baseline nor a late state from the old ChatGPT
        // runtime can reopen attention while the current document is
        // unsupported.
        harness.accept(false, token: tokenB)
        harness.accept(false, token: tokenA, kind: ChatGPTBridgePayload.stateKind)
        XCTAssertEqual(harness.observations, [.generationStarted, .runtimeReset])

        // A supported ordinary commit now enters the same authorization
        // barrier used by confirmed Instant Back. The detached harness cannot
        // return a named-world resync result, so neither the old document's
        // queued baseline nor the replacement document's natural baseline may
        // claim the epoch by racing the direct current-document read.
        harness.bridge.handleRuntimeReplacement(committedURL: supportedURL)
        harness.accept(true, token: tokenA)
        harness.accept(true, token: tokenB)
        XCTAssertEqual(harness.observations, [.generationStarted, .runtimeReset])
    }

    func testStaleOldDocumentMessageIsRejectedAfterUnknownCommitBoundary() throws {
        let harness = ChatGPTAttentionBridgeHarness()
        harness.accept(true, token: tokenA)
        harness.bridge.handleRuntimeReplacement()
        let observationsAfterReset = harness.observations.count

        // A late in-flight state message from the superseded document cannot
        // re-baseline the replacement epoch when no committed URL is available.
        harness.accept(false, token: tokenA, kind: ChatGPTBridgePayload.stateKind)
        XCTAssertEqual(harness.observations.count, observationsAfterReset)

        // Unknown/runtime-recovery boundaries retain natural-baseline recovery.
        harness.accept(true, token: tokenB)
        XCTAssertEqual(harness.observations.last, .generationStarted)
    }

    func testRestoredDocumentReestablishesBaselineWithSameToken() throws {
        // BFCache/history restore re-reports with the original token; after a
        // committed replacement that token becomes a fresh baseline again.
        let harness = ChatGPTAttentionBridgeHarness()
        harness.accept(false, token: tokenA)
        harness.bridge.handleRuntimeReplacement()

        harness.accept(true, token: tokenA)

        XCTAssertEqual(harness.observations, [.runtimeReset, .generationStarted])

        // The re-established epoch de-duplicates like any other document.
        harness.accept(true, token: tokenA)
        XCTAssertEqual(harness.observations, [.runtimeReset, .generationStarted])
    }

    func testCurrentDocumentStateContinuesDuringPendingInstantBack() throws {
        let harness = ChatGPTAttentionBridgeHarness()
        harness.accept(true, token: tokenB)
        harness.bridge.beginInstantBackHandoff()

        // The current document remains authoritative until confirmation. Its
        // own completion must not be frozen or buffered by the pending request.
        harness.accept(false, token: tokenB, kind: ChatGPTBridgePayload.stateKind)

        XCTAssertTrue(harness.bridge.isInstantBackHandoffPending)
        XCTAssertEqual(harness.observations, [.generationStarted, .generationFinished])
    }

    func testPreconfirmDifferentTokenBaselineIsRejectedUntilResync() throws {
        let harness = ChatGPTAttentionBridgeHarness()
        harness.accept(false, token: tokenB)
        harness.bridge.beginInstantBackHandoff()

        // A different-token baseline before current-history confirmation is
        // not a candidate epoch and is never replayed by native code.
        harness.accept(true, token: tokenA)
        XCTAssertEqual(harness.observations, [])

        harness.bridge.confirmInstantBackHandoff()
        XCTAssertEqual(harness.observations, [.runtimeReset])

        // Without a known supported target, the generic handoff test seam
        // retains natural-baseline recovery after its reset boundary.
        harness.accept(true, token: tokenA)
        XCTAssertEqual(
            harness.observations,
            [.runtimeReset, .generationStarted]
        )
    }

    func testSameURLStaleHistoricalBaselineIsRejectedBeforeConfirmation() throws {
        let harness = ChatGPTAttentionBridgeHarness()
        // A1 and A2 intentionally share a URL; token identity must still keep
        // the stale A1 baseline from becoming the current epoch.
        harness.accept(false, token: "instant-back-current-b")
        harness.bridge.beginInstantBackHandoff(
            targetURL: URL(string: "https://chatgpt.com/c/123")!
        )
        harness.accept(true, token: "instant-back-a1")
        harness.bridge.confirmInstantBackHandoff()
        XCTAssertEqual(harness.observations, [.runtimeReset])

        // The direct resync is unavailable on this detached harness, so the
        // identity barrier remains closed rather than accepting A2 by token
        // guesswork.
        harness.accept(true, token: "instant-back-a2")
        XCTAssertEqual(harness.observations, [.runtimeReset])
    }

    func testCancelledInstantBackCannotRebaselineOldRuntime() throws {
        let harness = ChatGPTAttentionBridgeHarness()
        harness.accept(true, token: tokenB)
        harness.bridge.beginInstantBackHandoff()
        harness.accept(false, token: tokenA)
        harness.bridge.cancelInstantBackHandoff()

        XCTAssertFalse(harness.bridge.isInstantBackHandoffPending)
        harness.accept(false, token: tokenA)
        XCTAssertEqual(harness.observations, [.generationStarted])
    }

    func testReleaseClearsPendingInstantBackHandoff() throws {
        let harness = ChatGPTAttentionBridgeHarness()
        harness.accept(false, token: tokenB)
        harness.bridge.beginInstantBackHandoff()

        harness.bridge.invalidate()

        XCTAssertFalse(harness.bridge.isInstantBackHandoffPending)
        XCTAssertTrue(harness.bridge.isInvalidated)
    }

    // MARK: - WebContent termination

    func testWebContentTerminationEmitsResetBeforeRecoveryReload() throws {
        var timeline: [String] = []
        let pool = WebViewPool(
            onURLChange: { _, _ in },
            initialLoad: { _, _ in timeline.append("load") },
            isSlotActive: { _ in true }
        )
        pool.onAttentionObservation = { _, observation in
            if case .runtimeReset = observation {
                timeline.append("reset")
            }
        }
        let profile = makeChatGPTProfile()
        _ = try pool.webView(for: profile)
        let bridge = pool.attentionBridge(for: profile.id)!
        bridge.accept(
            payload: ChatGPTBridgePayload(
                version: 1, kind: "baseline", token: tokenA, generating: true
            ),
            messageWebView: pool.existingWebView(for: profile.id),
            isMainFrame: true,
            originHost: "chatgpt.com",
            originProtocol: "https"
        )
        let boundary = timeline.count

        pool.handleContentProcessTermination(slotID: profile.id)

        XCTAssertEqual(Array(timeline[boundary...]), ["reset", "load"])
    }

    // MARK: - Release / rebuild / remove

    func testReleaseInvalidatesBridgeAndForwardsResetBoundary() throws {
        var observations: [ChatGPTAttentionObservation] = []
        let pool = WebViewPool(onURLChange: { _, _ in })
        pool.onAttentionObservation = { _, observation in
            observations.append(observation)
        }
        let profile = makeChatGPTProfile()
        let webView = try pool.webView(for: profile)
        let bridge = pool.attentionBridge(for: profile.id)!
        bridge.accept(
            payload: ChatGPTBridgePayload(
                version: 1, kind: "baseline", token: tokenA, generating: true
            ),
            messageWebView: webView,
            isMainFrame: true,
            originHost: "chatgpt.com",
            originProtocol: "https"
        )

        pool.release(slotID: profile.id)

        XCTAssertTrue(bridge.isInvalidated)
        XCTAssertNil(pool.attentionBridge(for: profile.id))
        XCTAssertEqual(observations.last, .runtimeReset)
    }

    func testStaleCallbackAfterInvalidationIsIgnored() throws {
        let harness = ChatGPTAttentionBridgeHarness()
        harness.accept(true, token: tokenA)
        harness.bridge.invalidate()
        let countAfterInvalidation = harness.observations.count

        harness.accept(true, token: tokenA)
        harness.accept(false, token: tokenA)
        harness.bridge.handleRuntimeReplacement()

        XCTAssertEqual(harness.observations.count, countAfterInvalidation)
    }

    func testRenderingRebuildInvalidatesOldBridgeAndCreatesNewBridge() throws {
        var residentSetChangeCount = 0
        let pool = WebViewPool(onURLChange: { _, _ in })
        pool.onResidentSetChange = { residentSetChangeCount += 1 }
        var profile = makeChatGPTProfile()
        _ = try pool.webView(for: profile)
        let oldBridge = pool.attentionBridge(for: profile.id)!

        profile.renderingProfile = profile.renderingProfile.settingBrowserIdentity(.windowsChrome)
        _ = try pool.webView(for: profile)
        let newBridge = pool.attentionBridge(for: profile.id)!

        XCTAssertFalse(oldBridge === newBridge)
        XCTAssertTrue(oldBridge.isInvalidated)
        XCTAssertFalse(newBridge.isInvalidated)
        // Rebuilding a resident Slot must not fake a resident-set transition.
        XCTAssertEqual(residentSetChangeCount, 1)
    }

    func testRemovingOneSlotLeavesTheOtherBridgeIntact() throws {
        let pool = WebViewPool(onURLChange: { _, _ in })
        let chatGPTProfile = makeChatGPTProfile()
        let otherProfile = WebAppProfile(
            order: 1,
            name: "Docs",
            homeURL: URL(string: "https://chatgpt.com/")!
        )
        _ = try pool.webView(for: chatGPTProfile)
        let otherWebView = try pool.webView(for: otherProfile)
        let chatGPTBridge = pool.attentionBridge(for: chatGPTProfile.id)!
        let otherBridge = pool.attentionBridge(for: otherProfile.id)!

        pool.release(slotID: chatGPTProfile.id)

        XCTAssertTrue(chatGPTBridge.isInvalidated)
        XCTAssertNil(pool.attentionBridge(for: chatGPTProfile.id))
        XCTAssertFalse(otherBridge.isInvalidated)
        XCTAssertTrue(pool.attentionBridge(for: otherProfile.id) === otherBridge)

        // The surviving bridge still processes its own document.
        otherBridge.accept(
            payload: ChatGPTBridgePayload(
                version: 1, kind: "baseline", token: tokenB, generating: true
            ),
            messageWebView: otherWebView,
            isMainFrame: true,
            originHost: "chatgpt.com",
            originProtocol: "https"
        )
    }

    func testPoolForwardsNormalizedObservationsThroughTransientSeam() throws {
        var received: [(UUID, ChatGPTAttentionObservation)] = []
        let pool = WebViewPool(onURLChange: { _, _ in })
        pool.onAttentionObservation = { slotID, observation in
            received.append((slotID, observation))
        }
        let profile = makeChatGPTProfile()
        let webView = try pool.webView(for: profile)

        pool.attentionBridge(for: profile.id)?.accept(
            payload: ChatGPTBridgePayload(
                version: 1, kind: "baseline", token: tokenA, generating: true
            ),
            messageWebView: webView,
            isMainFrame: true,
            originHost: "chatgpt.com",
            originProtocol: "https"
        )

        XCTAssertEqual(received.count, 1)
        XCTAssertEqual(received.first?.0, profile.id)
        XCTAssertEqual(received.first?.1, .generationStarted)
    }

    // MARK: - SlotNavigationObserver forwarding (HTTP fallback interaction)

    func testObserverKeepsHTTPFallbackIndependentOfAttentionLifecycle() throws {
        var events: [String] = []
        let webView = WKWebView()
        let entryURL = URL(string: "https://chat.example.com:8443/")!
        let observer = SlotNavigationObserver(
            slotID: UUID(),
            webView: webView,
            websiteMode: .desktop,
            onURLChange: { _, _ in },
            onNavigationCommit: { _, _ in
                events.append("commit")
            },
            loadHandler: { _, url in
                events.append("fallback:\(url.scheme ?? "")")
            }
        )
        observer.configureHTTPEntryFallback(for: entryURL, allowed: true)

        observer.webView(webView, didStartProvisionalNavigation: nil)
        XCTAssertTrue(events.isEmpty)

        let failure = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorCannotConnectToHost,
            userInfo: ["NSErrorFailingURLStringKey": entryURL.absoluteString]
        )
        observer.webView(
            webView,
            didFailProvisionalNavigation: nil,
            withError: failure
        )
        XCTAssertEqual(events, ["fallback:http"])

        // The fallback request receives its own provisional boundary normally.
        observer.webView(webView, didStartProvisionalNavigation: nil)
        observer.webView(webView, didCommit: nil)
        XCTAssertEqual(events, [
            "fallback:http", "commit",
        ])
    }

    // MARK: - Helpers

    private func makeChatGPTProfile() -> WebAppProfile {
        WebAppProfile(
            order: 0,
            name: "ChatGPT",
            homeURL: URL(string: "https://chatgpt.com/")!
        )
    }
}
