import WebKit
import XCTest
@testable import FloatTabs

/// Collects observations from one detached bridge so tests can drive the
/// exact production acceptance pipeline without a live page.
@MainActor
private final class ChatGPTAttentionBridgeHarness {
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

    init() {
        // The observation callback must not capture the harness itself before
        // initialization completes; the log reference it captures is enough.
        let log = self.log
        bridge = ChatGPTAttentionBridge(slotID: slotID) { _, observation in
            log.record(observation)
        }
        bridge.attach(to: webView)
    }

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

    func testChatGPTHostIsAccepted() {
        XCTAssertTrue(ChatGPTSitePolicy.isSupportedHost("chatgpt.com"))
        XCTAssertTrue(ChatGPTSitePolicy.isSupportedChatGPTURL(URL(string: "https://chatgpt.com/c/abc")!))
    }

    func testChatGPTSubdomainHostsAreAccepted() {
        XCTAssertTrue(ChatGPTSitePolicy.isSupportedHost("www.chatgpt.com"))
        XCTAssertTrue(ChatGPTSitePolicy.isSupportedHost("new.chatgpt.com"))
        XCTAssertTrue(ChatGPTSitePolicy.isSupportedChatGPTURL(URL(string: "https://new.chatgpt.com/")!))
    }

    func testLegacyOpenAIChatHostIsAccepted() {
        XCTAssertTrue(ChatGPTSitePolicy.isSupportedHost("chat.openai.com"))
        XCTAssertTrue(ChatGPTSitePolicy.isSupportedChatGPTURL(URL(string: "https://chat.openai.com/c/1")!))
    }

    func testLookalikeAndUnrelatedHostsAreRejected() {
        XCTAssertFalse(ChatGPTSitePolicy.isSupportedHost("evilchatgpt.com"))
        XCTAssertFalse(ChatGPTSitePolicy.isSupportedHost("chatgpt.com.evil.example"))
        XCTAssertFalse(ChatGPTSitePolicy.isSupportedHost("notchatgpt.com"))
        XCTAssertFalse(ChatGPTSitePolicy.isSupportedHost("openai.com"))
        XCTAssertFalse(ChatGPTSitePolicy.isSupportedHost("platform.openai.com"))
        XCTAssertFalse(ChatGPTSitePolicy.isSupportedHost(""))
        XCTAssertFalse(ChatGPTSitePolicy.isSupportedChatGPTURL(URL(string: "ftp://chatgpt.com/")!))
        XCTAssertFalse(ChatGPTSitePolicy.isSupportedChatGPTURL(URL(string: "about:blank")!))
    }

    func testChatGPTAutomaticMobileCompatibilityIdentityIsUnchanged() {
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

    func testInstalledUserScriptInjectsAtDocumentStart() {
        let controller = WKUserContentController()
        let harness = ChatGPTAttentionBridgeHarness()

        harness.bridge.install(into: controller)

        XCTAssertEqual(controller.userScripts.count, 1)
        XCTAssertEqual(controller.userScripts.first?.injectionTime, .atDocumentStart)
    }

    func testInstalledUserScriptIsMainFrameOnly() {
        let controller = WKUserContentController()
        let harness = ChatGPTAttentionBridgeHarness()

        harness.bridge.install(into: controller)

        XCTAssertEqual(controller.userScripts.first?.isForMainFrameOnly, true)
    }

    func testInstalledUserScriptUsesNamedContentWorld() {
        // pageWorld/defaultClientWorld carry no name; a named client world is
        // distinct from both, and one instance is shared by script, handler,
        // and invalidation.
        XCTAssertEqual(
            ChatGPTAttentionBridge.contentWorld.name,
            ChatGPTAttentionBridge.contentWorldName
        )
        XCTAssertFalse(ChatGPTAttentionBridge.contentWorld.name?.isEmpty == true)
    }

    func testInstalledScriptExposesOnlyTheNarrowNamedWorldResyncEntry() {
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

    func testBridgeConfiguredBeforeInitialLoad() {
        var hadBridgeScriptAtFirstLoad = false
        let pool = WebViewPool(
            onURLChange: { _, _ in },
            initialLoad: { webView, _ in
                hadBridgeScriptAtFirstLoad = webView.configuration.userContentController.userScripts
                    .contains { $0.isForMainFrameOnly }
            }
        )

        _ = pool.webView(for: makeChatGPTProfile())

        // The Factory-owned hidden-scrollbar script is document-start but
        // not main-frame-only, so the flag can only be set by the bridge.
        XCTAssertTrue(hadBridgeScriptAtFirstLoad)
    }

    func testInvalidationKeepsUnrelatedUserScripts() {
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

    func testPayloadValidationRejectsMalformedBodies() {
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

    func testMessageFromOtherWebViewIsRejected() {
        let harness = ChatGPTAttentionBridgeHarness()
        let otherWebView = WKWebView()

        harness.accept(true, token: tokenA, messageWebView: otherWebView)
        XCTAssertTrue(harness.observations.isEmpty)

        harness.accept(true, token: tokenA)
        XCTAssertEqual(harness.observations, [.generationStarted])
    }

    func testNonMainFrameMessageIsRejected() {
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

    func testUnsupportedOriginEmitsNothing() {
        let harness = ChatGPTAttentionBridgeHarness()

        harness.accept(true, token: tokenA, host: "evilchatgpt.com")
        harness.accept(true, token: tokenA, host: "openai.com")
        harness.accept(true, token: tokenA, host: "chatgpt.com.evil.example")
        harness.accept(true, token: tokenA, host: "chatgpt.com", originProtocol: "about")

        XCTAssertTrue(harness.observations.isEmpty)
    }

    // MARK: - Baseline and transition semantics

    func testIdleBaselineEmitsNoFinish() {
        let harness = ChatGPTAttentionBridgeHarness()

        harness.accept(false, token: tokenA)

        XCTAssertTrue(harness.observations.isEmpty)
    }

    func testGeneratingBaselineEmitsOneStart() {
        let harness = ChatGPTAttentionBridgeHarness()

        harness.accept(true, token: tokenA)

        XCTAssertEqual(harness.observations, [.generationStarted])
    }

    func testDuplicateGeneratingEmitsNothing() {
        let harness = ChatGPTAttentionBridgeHarness()

        harness.accept(true, token: tokenA)
        harness.accept(true, token: tokenA)

        XCTAssertEqual(harness.observations, [.generationStarted])
    }

    func testGeneratingToIdleEmitsOneFinish() {
        let harness = ChatGPTAttentionBridgeHarness()

        harness.accept(true, token: tokenA)
        harness.accept(false, token: tokenA)

        XCTAssertEqual(harness.observations, [.generationStarted, .generationFinished])
    }

    func testDuplicateIdleEmitsNothing() {
        let harness = ChatGPTAttentionBridgeHarness()

        harness.accept(true, token: tokenA)
        harness.accept(false, token: tokenA)
        harness.accept(false, token: tokenA)

        XCTAssertEqual(harness.observations, [.generationStarted, .generationFinished])
    }

    func testTrackerDirectlyMatchesBridgeSemantics() {
        var tracker = ChatGPTDocumentGenerationTracker()
        XCTAssertNil(tracker.observe(false))
        XCTAssertNil(tracker.observe(false))
        XCTAssertEqual(tracker.observe(true), .generationStarted)
        XCTAssertNil(tracker.observe(true))
        XCTAssertEqual(tracker.observe(false), .generationFinished)
        XCTAssertNil(tracker.observe(false))
    }

    // MARK: - Navigation lifecycle

    func testProvisionalStartDoesNotResetCurrentDocumentObservations() {
        let harness = ChatGPTAttentionBridgeHarness()
        harness.accept(true, token: tokenA)
        harness.accept(false, token: tokenA)

        XCTAssertEqual(
            harness.observations,
            [.generationStarted, .generationFinished]
        )
    }

    func testProvisionalFailureRequiresNoReplayOrRuntimeReset() {
        let harness = ChatGPTAttentionBridgeHarness()
        harness.accept(true, token: tokenA)
        harness.accept(false, token: tokenA)

        XCTAssertEqual(harness.observations, [.generationStarted, .generationFinished])
        XCTAssertFalse(harness.observations.contains(.runtimeReset))
    }

    func testCommittedReplacementEmitsRuntimeResetAndClearsEpoch() {
        let harness = ChatGPTAttentionBridgeHarness()
        harness.accept(true, token: tokenA)

        harness.bridge.handleRuntimeReplacement()

        XCTAssertEqual(harness.observations.last, .runtimeReset)
    }

    func testUnsupportedCurrentDocumentClosesAdmissionUntilSupportedReplacement() {
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

        harness.bridge.handleRuntimeReplacement(committedURL: supportedURL)
        harness.accept(false, token: tokenB)
        XCTAssertEqual(
            harness.observations,
            [.generationStarted, .runtimeReset]
        )
        harness.accept(true, token: tokenB, kind: ChatGPTBridgePayload.stateKind)
        XCTAssertEqual(
            harness.observations,
            [.generationStarted, .runtimeReset, .generationStarted]
        )
    }

    func testStaleOldDocumentMessageIsRejectedAfterCommit() {
        let harness = ChatGPTAttentionBridgeHarness()
        harness.accept(true, token: tokenA)
        harness.bridge.handleRuntimeReplacement()
        let observationsAfterReset = harness.observations.count

        // A late in-flight state message from the superseded document cannot
        // re-baseline the replacement epoch.
        harness.accept(false, token: tokenA, kind: ChatGPTBridgePayload.stateKind)
        XCTAssertEqual(harness.observations.count, observationsAfterReset)

        // The replacement document establishes its own baseline token.
        harness.accept(true, token: tokenB)
        XCTAssertEqual(harness.observations.last, .generationStarted)
    }

    func testRestoredDocumentReestablishesBaselineWithSameToken() {
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

    func testCurrentDocumentStateContinuesDuringPendingInstantBack() {
        let harness = ChatGPTAttentionBridgeHarness()
        harness.accept(true, token: tokenB)
        harness.bridge.beginInstantBackHandoff()

        // The current document remains authoritative until confirmation. Its
        // own completion must not be frozen or buffered by the pending request.
        harness.accept(false, token: tokenB, kind: ChatGPTBridgePayload.stateKind)

        XCTAssertTrue(harness.bridge.isInstantBackHandoffPending)
        XCTAssertEqual(harness.observations, [.generationStarted, .generationFinished])
    }

    func testPreconfirmDifferentTokenBaselineIsRejectedUntilResync() {
        let harness = ChatGPTAttentionBridgeHarness()
        harness.accept(false, token: tokenB)
        harness.bridge.beginInstantBackHandoff()

        // A different-token baseline before current-history confirmation is
        // not a candidate epoch and is never replayed by native code.
        harness.accept(true, token: tokenA)
        XCTAssertEqual(harness.observations, [])

        harness.bridge.confirmInstantBackHandoff()
        XCTAssertEqual(harness.observations, [.runtimeReset])

        // The actual current document's natural/explicit resync baseline now
        // opens the fresh epoch.
        harness.accept(true, token: tokenA)
        XCTAssertEqual(
            harness.observations,
            [.runtimeReset, .generationStarted]
        )
    }

    func testSameURLStaleHistoricalBaselineIsRejectedBeforeConfirmation() {
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
        // guesswork. The real named-world test covers the authorized result.
        harness.accept(true, token: "instant-back-a2")
        XCTAssertEqual(harness.observations, [.runtimeReset])
    }

    func testCancelledInstantBackCannotRebaselineOldRuntime() {
        let harness = ChatGPTAttentionBridgeHarness()
        harness.accept(true, token: tokenB)
        harness.bridge.beginInstantBackHandoff()
        harness.accept(false, token: tokenA)
        harness.bridge.cancelInstantBackHandoff()

        XCTAssertFalse(harness.bridge.isInstantBackHandoffPending)
        harness.accept(false, token: tokenA)
        XCTAssertEqual(harness.observations, [.generationStarted])
    }

    func testReleaseClearsPendingInstantBackHandoff() {
        let harness = ChatGPTAttentionBridgeHarness()
        harness.accept(false, token: tokenB)
        harness.bridge.beginInstantBackHandoff()

        harness.bridge.invalidate()

        XCTAssertFalse(harness.bridge.isInstantBackHandoffPending)
        XCTAssertTrue(harness.bridge.isInvalidated)
    }

    // MARK: - WebContent termination

    func testWebContentTerminationEmitsResetBeforeRecoveryReload() {
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
        _ = pool.webView(for: profile)
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

    func testReleaseInvalidatesBridgeAndForwardsResetBoundary() {
        var observations: [ChatGPTAttentionObservation] = []
        let pool = WebViewPool(onURLChange: { _, _ in })
        pool.onAttentionObservation = { _, observation in
            observations.append(observation)
        }
        let profile = makeChatGPTProfile()
        let webView = pool.webView(for: profile)
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

    func testStaleCallbackAfterInvalidationIsIgnored() {
        let harness = ChatGPTAttentionBridgeHarness()
        harness.accept(true, token: tokenA)
        harness.bridge.invalidate()
        let countAfterInvalidation = harness.observations.count

        harness.accept(true, token: tokenA)
        harness.accept(false, token: tokenA)
        harness.bridge.handleRuntimeReplacement()

        XCTAssertEqual(harness.observations.count, countAfterInvalidation)
    }

    func testRenderingRebuildInvalidatesOldBridgeAndCreatesNewBridge() {
        var residentSetChangeCount = 0
        let pool = WebViewPool(onURLChange: { _, _ in })
        pool.onResidentSetChange = { residentSetChangeCount += 1 }
        var profile = makeChatGPTProfile()
        _ = pool.webView(for: profile)
        let oldBridge = pool.attentionBridge(for: profile.id)!

        profile.renderingProfile = profile.renderingProfile.settingBrowserIdentity(.windowsChrome)
        _ = pool.webView(for: profile)
        let newBridge = pool.attentionBridge(for: profile.id)!

        XCTAssertFalse(oldBridge === newBridge)
        XCTAssertTrue(oldBridge.isInvalidated)
        XCTAssertFalse(newBridge.isInvalidated)
        // Rebuilding a resident Slot must not fake a resident-set transition.
        XCTAssertEqual(residentSetChangeCount, 1)
    }

    func testRemovingOneSlotLeavesTheOtherBridgeIntact() {
        let pool = WebViewPool(onURLChange: { _, _ in })
        let chatGPTProfile = makeChatGPTProfile()
        let otherProfile = WebAppProfile(
            order: 1,
            name: "Docs",
            homeURL: URL(string: "https://chatgpt.com/")!
        )
        _ = pool.webView(for: chatGPTProfile)
        let otherWebView = pool.webView(for: otherProfile)
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

    func testPoolForwardsNormalizedObservationsThroughTransientSeam() {
        var received: [(UUID, ChatGPTAttentionObservation)] = []
        let pool = WebViewPool(onURLChange: { _, _ in })
        pool.onAttentionObservation = { slotID, observation in
            received.append((slotID, observation))
        }
        let profile = makeChatGPTProfile()
        let webView = pool.webView(for: profile)

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

    func testObserverKeepsHTTPFallbackIndependentOfAttentionLifecycle() {
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
