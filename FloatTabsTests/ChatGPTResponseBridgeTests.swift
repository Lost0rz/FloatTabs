import WebKit
import XCTest
@testable import FloatTabs

@MainActor
private final class TrustedInteractionAdmissionProbe {
    var count = 0
}
@MainActor
private final class ResponseStatusSnapshotProviderProbe {
    private enum Resolution {
        case snapshot(ChatGPTResponseStatusSnapshot?)
    }

    private var pending: CheckedContinuation<ChatGPTResponseStatusSnapshot?, Never>?
    private var queuedResolution: Resolution?
    private(set) var requestCount = 0
    private(set) var lastScript: String?

    func provide(
        _ webView: WKWebView,
        _ script: String
    ) async -> ChatGPTResponseStatusSnapshot? {
        requestCount += 1
        lastScript = script
        return await withCheckedContinuation { continuation in
            if let queuedResolution {
                self.queuedResolution = nil
                switch queuedResolution {
                case let .snapshot(snapshot):
                    continuation.resume(returning: snapshot)
                }
            } else {
                pending = continuation
            }
        }
    }

    func resolve(_ snapshot: ChatGPTResponseStatusSnapshot?) {
        if let pending {
            self.pending = nil
            pending.resume(returning: snapshot)
        } else {
            queuedResolution = .snapshot(snapshot)
        }
    }
}

@MainActor
final class ChatGPTResponseBridgeTests: XCTestCase {












    func testResponseStatusSnapshotValidatesDocumentIdentityAndCompletionState() throws {
        let identity = try XCTUnwrap(
            ChatGPTResponseIdentity(rawValue: "message:snapshot-latest")
        )
        let snapshot = ChatGPTResponseBridge.parseResponseStatusSnapshot([
            "version": 1,
            "documentToken": "document-snapshot-12345678",
            "responseIdentity": identity.rawValue,
            "generating": false
        ])

        XCTAssertEqual(
            snapshot,
            ChatGPTResponseStatusSnapshot(
                documentToken: "document-snapshot-12345678",
                responseIdentity: identity,
                generating: false
            )
        )
        XCTAssertNil(
            ChatGPTResponseBridge.parseResponseStatusSnapshot([
                "version": 1,
                "documentToken": "document-snapshot-12345678",
                "responseIdentity": "message:bad identity",
                "generating": false
            ])
        )
        XCTAssertNil(
            ChatGPTResponseBridge.parseResponseStatusSnapshot([
                "version": 1,
                "documentToken": "document-snapshot-12345678",
                "responseIdentity": identity.rawValue,
                "generating": "false"
            ])
        )
    }

    func testAsyncResponseStatusProviderIsProductionSharedAndRespectsBridgeIdentity() async throws {
        let probe = ResponseStatusSnapshotProviderProbe()
        let bridge = ChatGPTResponseBridge(
            slotID: UUID(),
            responseStatusSnapshotProvider: { webView, script in
                await probe.provide(webView, script)
            }
        )
        let webView = WKWebView(
            frame: .zero,
            configuration: WKWebViewConfiguration()
        )
        bridge.attach(to: webView)
        let documentToken = "async-status-document"
        let identity = try XCTUnwrap(
            ChatGPTResponseIdentity(rawValue: "message:async-status")
        )
        XCTAssertTrue(bridge.debugReceiveDocumentReady(documentToken: documentToken))

        var result: ChatGPTResponseStatusSnapshot?
        bridge.snapshotLatestResponseStatus { result = $0 }
        for _ in 0..<1_000 where probe.requestCount < 1 {
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertEqual(probe.requestCount, 1)
        XCTAssertEqual(
            probe.lastScript,
            "globalThis.__floatTabsChatGPTResponseIdentitySnapshotV1?.()"
        )

        probe.resolve(
            ChatGPTResponseStatusSnapshot(
                documentToken: documentToken,
                responseIdentity: identity,
                generating: false
            )
        )
        for _ in 0..<1_000 where result == nil {
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertEqual(
            result,
            ChatGPTResponseStatusSnapshot(
                documentToken: documentToken,
                responseIdentity: identity,
                generating: false
            )
        )

        result = ChatGPTResponseStatusSnapshot(
            documentToken: documentToken,
            responseIdentity: identity,
            generating: false
        )
        bridge.snapshotLatestResponseStatus { result = $0 }
        for _ in 0..<1_000 where probe.requestCount < 2 {
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertEqual(probe.requestCount, 2)
        bridge.handleRuntimeReplacement()
        probe.resolve(nil)
        for _ in 0..<1_000 where result != nil {
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertNil(result)
    }

    func testBridgeUsesIndependentNamedWorldAndNoPersistentMutationObserver() {
        XCTAssertEqual(
            ChatGPTResponseExtraction.contentWorld.name,
            ChatGPTResponseExtraction.contentWorldName
        )
        XCTAssertTrue(ChatGPTResponseExtraction.scriptSource.contains("isEditableTarget"))
        XCTAssertTrue(ChatGPTResponseExtraction.scriptSource.contains("plaintext-only"))
        XCTAssertTrue(ChatGPTResponseExtraction.scriptSource.contains("event.key === 'Home'"))
        XCTAssertTrue(ChatGPTResponseExtraction.scriptSource.contains("event.key === 'End'"))
        XCTAssertTrue(
            ChatGPTResponseExtraction.scriptSource.contains(
                "if (event.isTrusted) postManualScroll();"
            )
        )
        XCTAssertTrue(ChatGPTResponseExtraction.scriptSource.contains("DOMContentLoaded"))
        XCTAssertTrue(ChatGPTResponseExtraction.scriptSource.contains("event: \"documentReady\""))
        XCTAssertTrue(
            ChatGPTResponseExtraction.scriptSource.contains(
                "if (!event.isTrusted) return;"
            )
        )
        XCTAssertFalse(ChatGPTResponseExtraction.scriptSource.contains("mousemove"))
        XCTAssertFalse(ChatGPTResponseExtraction.scriptSource.contains("MutationObserver"))
        XCTAssertFalse(ChatGPTResponseExtraction.scriptSource.contains("characterData"))
        XCTAssertFalse(ChatGPTResponseExtraction.scriptSource.contains("document.body.innerText"))
        XCTAssertFalse(ChatGPTResponseExtraction.scriptSource.contains("scrollIntoView"))
        XCTAssertFalse(ChatGPTResponseExtraction.scriptSource.contains(".focus()"))
        XCTAssertFalse(ChatGPTResponseExtraction.scriptSource.contains("setInterval"))
        XCTAssertFalse(ChatGPTResponseExtraction.scriptSource.contains("setTimeout"))
        XCTAssertTrue(
            ChatGPTResponseExtraction.scriptSource.contains(
                "__floatTabsChatGPTResponseIdentitySnapshotV1"
            )
        )
        XCTAssertTrue(ChatGPTResponseExtraction.scriptSource.contains("event: \"trustedInteraction\""))
    }

    func testResponseIdentityPolicyRemainsShared() throws {
        let source = ChatGPTResponseExtraction.scriptSource
        XCTAssertTrue(source.contains("RESPONSE_STABLE_ATTRIBUTE_NAMES"))
        XCTAssertTrue(source.contains("data-message-id"))
        XCTAssertTrue(source.contains("data-message-uuid"))
        XCTAssertTrue(source.contains("canonicalResponseIdentityFor"))
        XCTAssertTrue(source.contains("latestResponseIdentity"))
        XCTAssertTrue(source.contains("latestResponseComplete"))
        XCTAssertFalse(source.contains("responseIDFor"))
        let identity = try XCTUnwrap(
            ChatGPTResponseIdentity(stableValue: "stable-identity-id")
        )
        XCTAssertEqual(identity.rawValue, "message:stable-identity-id")
    }

    func testDocumentReadyEstablishesLiveIdentityAndTrustedManualScroll() {
        let slotID = UUID()
        var manualScrollEvents: [ChatGPTTrustedInteractionEvent] = []
        let bridge = ChatGPTResponseBridge(
            slotID: slotID,
            onTrustedInteractionEvent: { _, event in manualScrollEvents.append(event) }
        )

        XCTAssertTrue(
            bridge.debugReceiveDocumentReady(
                documentToken: "document-ready-12345678"
            )
        )
        XCTAssertTrue(
            bridge.debugInvokeTrustedManualScroll(
                documentToken: "document-ready-12345678"
            )
        )
        XCTAssertEqual(manualScrollEvents.map(\.kind), [.manualScroll])
        XCTAssertEqual(manualScrollEvents.first?.documentToken, "document-ready-12345678")
    }

    func testDocumentReadyRejectsInvalidTokenAndWrongVersion() {
        let bridge = ChatGPTResponseBridge(slotID: UUID())

        XCTAssertFalse(
            bridge.debugReceiveDocumentReady(documentToken: "short")
        )
        XCTAssertFalse(
            bridge.debugReceiveDocumentReady(
                documentToken: "document-ready-12345678",
                version: ChatGPTResponseProtocol.currentVersion + 1
            )
        )
        XCTAssertFalse(
            bridge.debugInvokeTrustedManualScroll(
                documentToken: "document-ready-12345678"
            )
        )
    }

    func testDocumentReadyReplacesLiveIdentityAndRuntimeResetRejectsOldToken() {
        var manualScrollTokens: [String] = []
        let bridge = ChatGPTResponseBridge(
            slotID: UUID(),
            onTrustedInteractionEvent: { _, event in
                if event.kind == .manualScroll {
                    manualScrollTokens.append(event.documentToken)
                }
            }
        )

        XCTAssertTrue(
            bridge.debugReceiveDocumentReady(documentToken: "document-a-12345678")
        )
        bridge.handleRuntimeReplacement()
        XCTAssertFalse(
            bridge.debugInvokeTrustedManualScroll(documentToken: "document-a-12345678")
        )

        XCTAssertTrue(
            bridge.debugReceiveDocumentReady(documentToken: "document-b-12345678")
        )
        XCTAssertFalse(
            bridge.debugInvokeTrustedManualScroll(documentToken: "document-a-12345678")
        )
        XCTAssertTrue(
            bridge.debugInvokeTrustedManualScroll(documentToken: "document-b-12345678")
        )
        XCTAssertEqual(manualScrollTokens, ["document-b-12345678"])
    }

    func testDebugTrustedInteractionForwardsOnlyCurrentDocumentAndFixedKind() {
        let slotID = UUID()
        var interactions: [(UUID, ChatGPTTrustedPageInteractionKind, String)] = []
        let bridge = ChatGPTResponseBridge(
            slotID: slotID,
            onTrustedInteraction: { slotID, kind, documentToken in
                interactions.append((slotID, kind, documentToken))
            }
        )

        XCTAssertTrue(
            bridge.debugReceiveDocumentReady(
                documentToken: "trusted-interaction-document"
            )
        )
        XCTAssertTrue(
            bridge.debugInvokeTrustedInteraction(
                kind: .assistantPointer,
                documentToken: "trusted-interaction-document"
            )
        )
        XCTAssertTrue(
            bridge.debugInvokeTrustedInteraction(
                kind: .manualScroll,
                documentToken: "trusted-interaction-document"
            )
        )
        XCTAssertFalse(
            bridge.debugInvokeTrustedInteraction(
                kind: .assistantPointer,
                documentToken: "old-interaction-document"
            )
        )

        XCTAssertEqual(interactions.count, 2)
        XCTAssertEqual(interactions[0].0, slotID)
        XCTAssertEqual(interactions[0].1, .assistantPointer)
        XCTAssertEqual(interactions[0].2, "trusted-interaction-document")
        XCTAssertEqual(interactions[1].1, .manualScroll)
    }

    func testTrustedInteractionEventCarriesIdentityAndCompletionAtomically() throws {
        let slotID = UUID()
        let identity = try XCTUnwrap(
            ChatGPTResponseIdentity(rawValue: "message:pointer-response")
        )
        var events: [ChatGPTTrustedInteractionEvent] = []
        let bridge = ChatGPTResponseBridge(
            slotID: slotID,
            onTrustedInteractionEvent: { _, event in
                events.append(event)
            }
        )
        let webView = WKWebView(
            frame: .zero,
            configuration: WKWebViewConfiguration()
        )
        bridge.attach(to: webView)
        let token = "trusted-event-document"
        XCTAssertTrue(bridge.debugReceiveDocumentReady(documentToken: token))

        XCTAssertTrue(
            bridge.acceptTrustedInteraction(
                body: [
                    "version": ChatGPTResponseProtocol.currentVersion,
                    "event": "trustedInteraction",
                    "documentToken": token,
                    "interactionKind": "assistantPointer",
                    "responseIdentity": identity.rawValue,
                    "responseComplete": true
                ],
                messageWebView: webView,
                isMainFrame: true,
                originHost: "chatgpt.com",
                originProtocol: "https"
            )
        )
        XCTAssertEqual(
            events,
            [
                ChatGPTTrustedInteractionEvent(
                    kind: .assistantPointer,
                    documentToken: token,
                    responseIdentity: identity,
                    responseComplete: true
                )
            ]
        )
    }

    func testTrustedInteractionRejectsMalformedIdentityAndCompletionFlag() throws {
        let bridge = ChatGPTResponseBridge(slotID: UUID())
        let webView = WKWebView(
            frame: .zero,
            configuration: WKWebViewConfiguration()
        )
        bridge.attach(to: webView)
        let token = "trusted-event-validation"
        XCTAssertTrue(bridge.debugReceiveDocumentReady(documentToken: token))

        let base: [String: Any] = [
            "version": ChatGPTResponseProtocol.currentVersion,
            "event": "trustedInteraction",
            "documentToken": token,
            "interactionKind": "assistantPointer"
        ]
        XCTAssertFalse(
            bridge.acceptTrustedInteraction(
                body: base.merging([
                    "responseIdentity": "not-canonical"
                ]) { _, new in new },
                messageWebView: webView,
                isMainFrame: true,
                originHost: "chatgpt.com",
                originProtocol: "https"
            )
        )
        XCTAssertFalse(
            bridge.acceptTrustedInteraction(
                body: base.merging([
                    "responseComplete": "true"
                ]) { _, new in new },
                messageWebView: webView,
                isMainFrame: true,
                originHost: "chatgpt.com",
                originProtocol: "https"
            )
        )
    }

    func testPoolForwardsTrustedInteractionWithoutRetainingIt() throws {
        let slotID = UUID()
        let profile = WebAppProfile(
            id: slotID,
            order: 0,
            name: "ChatGPT",
            homeURL: URL(string: "https://chatgpt.com/")!
        )
        var interactions: [(UUID, ChatGPTTrustedPageInteractionKind, String)] = []
        let pool = WebViewPool(onURLChange: { _, _ in })
        pool.onTrustedInteraction = { slotID, kind, documentToken in
            interactions.append((slotID, kind, documentToken))
        }

        _ = try pool.webView(for: profile)
        let bridge = try XCTUnwrap(pool.responseBridge(for: slotID))
        XCTAssertTrue(
            bridge.debugReceiveDocumentReady(documentToken: "pool-interaction-document")
        )
        XCTAssertTrue(
            bridge.debugInvokeTrustedInteraction(
                kind: .assistantPointer,
                documentToken: "pool-interaction-document"
            )
        )

        XCTAssertEqual(interactions.count, 1)
        XCTAssertEqual(interactions.first?.0, slotID)
        XCTAssertEqual(interactions.first?.1, .assistantPointer)
        XCTAssertEqual(interactions.first?.2, "pool-interaction-document")
    }

    func testTrustedAssistantPointerProtocolUsesFixedContentFreeContract() {
        XCTAssertEqual(
            ChatGPTTrustedPageInteractionKind.assistantPointer.rawValue,
            "assistantPointer"
        )
        let source = ChatGPTResponseExtraction.scriptSource
        XCTAssertTrue(source.contains("event: \"trustedInteraction\""))
        XCTAssertTrue(source.contains("interactionKind: \"assistantPointer\""))
        XCTAssertTrue(source.contains("pointerdown"))
        XCTAssertTrue(source.contains("event.isTrusted"))
        XCTAssertTrue(source.contains("data-message-author-role=\"assistant\""))
        XCTAssertTrue(source.contains("data-message-role=\"assistant\""))
        XCTAssertTrue(source.contains("[data-testid*=\"conversation-turn\"]"))
        XCTAssertTrue(source.contains("[data-turn=\"assistant\"]"))
        XCTAssertTrue(source.contains("[data-content-search-unit-key]"))
        XCTAssertTrue(source.contains("[data-conversation-role=\"assistant\"]"))
        XCTAssertFalse(source.contains("article[data-testid*=\"conversation-turn\"]"))
        XCTAssertFalse(source.contains("buttonText"))
        XCTAssertFalse(source.contains("ariaLabel"))
        XCTAssertFalse(source.contains("responseContent"))
        XCTAssertFalse(source.contains("domPath"))
        XCTAssertFalse(source.contains("clipboard"))
        XCTAssertFalse(source.contains("selectionText"))
    }

    func testTrustedInteractionAdmissionAcceptsValidEnvelope() {
        let fixture = makeTrustedInteractionAdmissionFixture()

        XCTAssertTrue(
            fixture.bridge.acceptTrustedInteraction(
                body: trustedInteractionBody(),
                messageWebView: fixture.attachedWebView,
                isMainFrame: true,
                originHost: "chatgpt.com",
                originProtocol: "HTTPS"
            )
        )
        XCTAssertEqual(fixture.probe.count, 1)
    }

    func testTrustedInteractionAdmissionRejectsWrongWebView() {
        let fixture = makeTrustedInteractionAdmissionFixture()

        XCTAssertFalse(
            fixture.bridge.acceptTrustedInteraction(
                body: trustedInteractionBody(),
                messageWebView: fixture.otherWebView,
                isMainFrame: true,
                originHost: "chatgpt.com",
                originProtocol: "https"
            )
        )
        XCTAssertEqual(fixture.probe.count, 0)
    }

    func testTrustedInteractionAdmissionRejectsNonMainFrame() {
        let fixture = makeTrustedInteractionAdmissionFixture()

        XCTAssertFalse(
            fixture.bridge.acceptTrustedInteraction(
                body: trustedInteractionBody(),
                messageWebView: fixture.attachedWebView,
                isMainFrame: false,
                originHost: "chatgpt.com",
                originProtocol: "https"
            )
        )
        XCTAssertEqual(fixture.probe.count, 0)
    }

    func testTrustedInteractionAdmissionRejectsUnsupportedHost() {
        let fixture = makeTrustedInteractionAdmissionFixture()

        XCTAssertFalse(
            fixture.bridge.acceptTrustedInteraction(
                body: trustedInteractionBody(),
                messageWebView: fixture.attachedWebView,
                isMainFrame: true,
                originHost: "example.com",
                originProtocol: "https"
            )
        )
        XCTAssertEqual(fixture.probe.count, 0)
    }

    func testTrustedInteractionAdmissionRejectsInvalidProtocol() {
        let fixture = makeTrustedInteractionAdmissionFixture()

        XCTAssertFalse(
            fixture.bridge.acceptTrustedInteraction(
                body: trustedInteractionBody(),
                messageWebView: fixture.attachedWebView,
                isMainFrame: true,
                originHost: "chatgpt.com",
                originProtocol: "file"
            )
        )
        XCTAssertEqual(fixture.probe.count, 0)
    }

    func testTrustedInteractionAdmissionRejectsWrongVersion() {
        let fixture = makeTrustedInteractionAdmissionFixture()

        XCTAssertFalse(
            fixture.bridge.acceptTrustedInteraction(
                body: trustedInteractionBody(
                    version: ChatGPTResponseProtocol.currentVersion + 1
                ),
                messageWebView: fixture.attachedWebView,
                isMainFrame: true,
                originHost: "chatgpt.com",
                originProtocol: "https"
            )
        )
        XCTAssertEqual(fixture.probe.count, 0)
    }

    func testTrustedInteractionAdmissionRejectsInvalidKind() {
        let fixture = makeTrustedInteractionAdmissionFixture()

        XCTAssertFalse(
            fixture.bridge.acceptTrustedInteraction(
                body: trustedInteractionBody(kind: "assistantClick"),
                messageWebView: fixture.attachedWebView,
                isMainFrame: true,
                originHost: "chatgpt.com",
                originProtocol: "https"
            )
        )
        XCTAssertEqual(fixture.probe.count, 0)
    }

    func testTrustedInteractionAdmissionRejectsStaleDocumentToken() {
        let fixture = makeTrustedInteractionAdmissionFixture()

        XCTAssertFalse(
            fixture.bridge.acceptTrustedInteraction(
                body: trustedInteractionBody(token: "stale-document-12345678"),
                messageWebView: fixture.attachedWebView,
                isMainFrame: true,
                originHost: "chatgpt.com",
                originProtocol: "https"
            )
        )
        XCTAssertEqual(fixture.probe.count, 0)
    }

    private func makeTrustedInteractionAdmissionFixture() -> (
        bridge: ChatGPTResponseBridge,
        attachedWebView: WKWebView,
        otherWebView: WKWebView,
        probe: TrustedInteractionAdmissionProbe
    ) {
        let probe = TrustedInteractionAdmissionProbe()
        let bridge = ChatGPTResponseBridge(
            slotID: UUID(),
            onTrustedInteraction: { _, _, _ in
                probe.count += 1
            }
        )
        let attachedWebView = WKWebView(
            frame: .zero,
            configuration: WKWebViewConfiguration()
        )
        let otherWebView = WKWebView(
            frame: .zero,
            configuration: WKWebViewConfiguration()
        )
        bridge.attach(to: attachedWebView)
        XCTAssertTrue(
            bridge.debugReceiveDocumentReady(
                documentToken: "trusted-admission-document-12345678"
            )
        )
        return (bridge, attachedWebView, otherWebView, probe)
    }

    private func trustedInteractionBody(
        version: Int = ChatGPTResponseProtocol.currentVersion,
        token: String = "trusted-admission-document-12345678",
        kind: String = "assistantPointer"
    ) -> [String: Any] {
        [
            "version": version,
            "event": "trustedInteraction",
            "documentToken": token,
            "interactionKind": kind,
        ]
    }
}

// MARK: - One-shot assistant response preview snapshot

@MainActor
private final class ResponsePreviewSnapshotProviderProbe {
    private enum Resolution {
        case snapshot(ChatGPTResponsePreviewSnapshot?)
    }

    private var pending: (@MainActor (ChatGPTResponsePreviewSnapshot?) -> Void)?
    private var queued: Resolution?
    private(set) var requestCount = 0
    private(set) var lastScript: String?

    func provide(
        _ webView: WKWebView,
        _ script: String,
        completion: @escaping @MainActor (ChatGPTResponsePreviewSnapshot?) -> Void
    ) {
        requestCount += 1
        lastScript = script
        if let queued {
            self.queued = nil
            switch queued {
            case let .snapshot(snapshot):
                completion(snapshot)
            }
        } else {
            pending = completion
        }
    }

    func resolve(_ snapshot: ChatGPTResponsePreviewSnapshot?) {
        if let pending {
            self.pending = nil
            pending(snapshot)
        } else {
            queued = .snapshot(snapshot)
        }
    }
}

extension ChatGPTResponseBridgeTests {
    private func makePreviewBridge(
        probe: ResponsePreviewSnapshotProviderProbe,
        timeoutNanoseconds: UInt64 = 1_000_000_000
    ) -> (bridge: ChatGPTResponseBridge, webView: WKWebView) {
        let bridge = ChatGPTResponseBridge(
            slotID: UUID(),
            responsePreviewSnapshotProvider: { webView, script, completion in
                probe.provide(webView, script, completion: completion)
            },
            previewSnapshotTimeoutNanoseconds: timeoutNanoseconds
        )
        let webView = WKWebView(
            frame: .zero,
            configuration: WKWebViewConfiguration()
        )
        bridge.attach(to: webView)
        return (bridge, webView)
    }

    /// N1 parse contract: valid completed previews parse; generating,
    /// malformed and mismatched payloads never admit.
    func testPreviewSnapshotParsingAdmitsOnlyCompletedBoundedResults() {
        let token = "preview-document-token-12345678"
        let valid = ChatGPTResponseBridge.parseResponsePreviewSnapshot([
            "version": 1,
            "documentToken": token,
            "generating": false,
            "preview": "Bounded assistant preview."
        ])
        XCTAssertEqual(
            valid,
            ChatGPTResponsePreviewSnapshot(
                documentToken: token,
                generating: false,
                previewText: "Bounded assistant preview."
            )
        )
        XCTAssertNil(
            ChatGPTResponseBridge.parseResponsePreviewSnapshot([
                "version": 1,
                "documentToken": token,
                "generating": true,
                "preview": "Streaming text is not a completed preview."
            ])
        )
        XCTAssertNil(
            ChatGPTResponseBridge.parseResponsePreviewSnapshot([
                "version": 2,
                "documentToken": token,
                "generating": false,
                "preview": "text"
            ])
        )
        XCTAssertNil(
            ChatGPTResponseBridge.parseResponsePreviewSnapshot([
                "version": 1,
                "documentToken": "short",
                "generating": false,
                "preview": "text"
            ])
        )
        XCTAssertNil(
            ChatGPTResponseBridge.parseResponsePreviewSnapshot([
                "version": 1,
                "documentToken": token,
                "generating": false,
                "preview": 42
            ])
        )
        let noPreview = ChatGPTResponseBridge.parseResponsePreviewSnapshot([
            "version": 1,
            "documentToken": token,
            "generating": false,
            "preview": NSNull()
        ])
        XCTAssertEqual(
            noPreview,
            ChatGPTResponsePreviewSnapshot(
                documentToken: token,
                generating: false,
                previewText: nil
            )
        )
    }

    func testPreviewProviderSuccessBeforeTimeoutAdmitsCurrentDocumentSnapshot() async throws {
        let probe = ResponsePreviewSnapshotProviderProbe()
        let (bridge, retainedWebView) = makePreviewBridge(
            probe: probe,
            timeoutNanoseconds: 300_000_000
        )
        XCTAssertNotNil(retainedWebView)
        let token = "preview-success-doc-12345678"
        XCTAssertTrue(bridge.debugReceiveDocumentReady(documentToken: token))

        var completed: ChatGPTResponsePreviewSnapshot?
        var completionCount = 0
        bridge.previewLatestAssistantResponse { snapshot in
            completed = snapshot
            completionCount += 1
        }
        for _ in 0..<100 where probe.requestCount == 0 {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        probe.resolve(
            ChatGPTResponsePreviewSnapshot(
                documentToken: token,
                generating: false,
                previewText: "current assistant preview"
            )
        )

        XCTAssertEqual(completed?.previewText, "current assistant preview")
        XCTAssertEqual(completionCount, 1)
        try await Task.sleep(nanoseconds: 350_000_000)
        XCTAssertEqual(completionCount, 1, "provider success cancels its timeout")
    }

    /// A navigation replacement settles a pending preview once with nil;
    /// the provider's late result is ignored.
    func testPreviewSnapshotInvalidatedByDocumentReplacementMidFlight() async throws {
        let probe = ResponsePreviewSnapshotProviderProbe()
        let (bridge, retainedWebView) = makePreviewBridge(
            probe: probe,
            timeoutNanoseconds: 300_000_000
        )
        XCTAssertNotNil(retainedWebView)
        XCTAssertTrue(
            bridge.debugReceiveDocumentReady(documentToken: "preview-original-doc-1234567")
        )

        var completed: ChatGPTResponsePreviewSnapshot?
        var completionCount = 0
        bridge.previewLatestAssistantResponse { snapshot in
            completed = snapshot
            completionCount += 1
        }
        for _ in 0..<100 where probe.requestCount == 0 {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(probe.requestCount, 1)

        // Navigation replacement lands while the provider is still in flight.
        XCTAssertTrue(
            bridge.debugReceiveDocumentReady(documentToken: "preview-replaced-doc-1234567")
        )
        XCTAssertNil(completed)
        XCTAssertEqual(completionCount, 1)
        probe.resolve(
            ChatGPTResponsePreviewSnapshot(
                documentToken: "preview-original-doc-1234567",
                generating: false,
                previewText: "stale response text"
            )
        )
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertNil(completed, "stale-document preview must not be admitted")
        XCTAssertEqual(completionCount, 1, "late provider result must not callback twice")
    }

    func testPreviewRuntimeReplacementCompletesPendingRequestExactlyOnceWithNil() async throws {
        let probe = ResponsePreviewSnapshotProviderProbe()
        let (bridge, retainedWebView) = makePreviewBridge(
            probe: probe,
            timeoutNanoseconds: 300_000_000
        )
        XCTAssertNotNil(retainedWebView)
        XCTAssertTrue(
            bridge.debugReceiveDocumentReady(documentToken: "preview-runtime-doc-1234567")
        )

        var completed: ChatGPTResponsePreviewSnapshot?
        var completionCount = 0
        bridge.previewLatestAssistantResponse { snapshot in
            completed = snapshot
            completionCount += 1
        }
        for _ in 0..<100 where probe.requestCount == 0 {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(probe.requestCount, 1)

        bridge.handleRuntimeReplacement()
        XCTAssertNil(completed)
        XCTAssertEqual(completionCount, 1)
        probe.resolve(
            ChatGPTResponsePreviewSnapshot(
                documentToken: "preview-runtime-doc-1234567",
                generating: false,
                previewText: "late runtime preview"
            )
        )
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertNil(completed)
        XCTAssertEqual(completionCount, 1)
    }

    func testPreviewProviderTimeoutCompletesExactlyOnceWithNilAndIgnoresLateResult() async throws {
        let probe = ResponsePreviewSnapshotProviderProbe()
        let (bridge, retainedWebView) = makePreviewBridge(
            probe: probe,
            timeoutNanoseconds: 100_000_000
        )
        XCTAssertNotNil(retainedWebView)
        XCTAssertTrue(
            bridge.debugReceiveDocumentReady(documentToken: "preview-timeout-doc-123456")
        )

        var completed: ChatGPTResponsePreviewSnapshot?
        var completionCount = 0
        bridge.previewLatestAssistantResponse { snapshot in
            completed = snapshot
            completionCount += 1
        }
        for _ in 0..<100 where probe.requestCount == 0 {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(probe.requestCount, 1)
        for _ in 0..<100 where completionCount == 0 {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertNil(completed)
        XCTAssertEqual(completionCount, 1, "timeout must settle the one-shot request once")
        probe.resolve(
            ChatGPTResponsePreviewSnapshot(
                documentToken: "preview-timeout-doc-123456",
                generating: false,
                previewText: "late preview after timeout"
            )
        )
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertNil(completed)
        XCTAssertEqual(completionCount, 1, "late provider result must be ignored")
    }

    func testPreviewProviderNilCompletesExactlyOnceBeforeTimeout() async throws {
        let probe = ResponsePreviewSnapshotProviderProbe()
        let (bridge, retainedWebView) = makePreviewBridge(
            probe: probe,
            timeoutNanoseconds: 300_000_000
        )
        XCTAssertNotNil(retainedWebView)
        XCTAssertTrue(
            bridge.debugReceiveDocumentReady(documentToken: "preview-nil-doc-12345678")
        )

        var completionCount = 0
        var completed: ChatGPTResponsePreviewSnapshot?
        bridge.previewLatestAssistantResponse { snapshot in
            completed = snapshot
            completionCount += 1
        }
        for _ in 0..<100 where probe.requestCount == 0 {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        probe.resolve(nil)
        for _ in 0..<100 where completionCount == 0 {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertNil(completed)
        XCTAssertEqual(completionCount, 1)
        try await Task.sleep(nanoseconds: 350_000_000)
        XCTAssertEqual(completionCount, 1, "provider nil and timeout must arbitrate once")
    }

    /// N1-6: an invalidated or document-less bridge admits no preview.
    func testPreviewSnapshotRequiresValidCurrentDocument() async {
        let probe = ResponsePreviewSnapshotProviderProbe()
        let (bridge, retainedWebView) = makePreviewBridge(probe: probe)
        XCTAssertNotNil(retainedWebView)

        var noDocumentResult: ChatGPTResponsePreviewSnapshot?
        bridge.previewLatestAssistantResponse { snapshot in
            noDocumentResult = snapshot
        }
        XCTAssertNil(noDocumentResult)
        XCTAssertEqual(probe.requestCount, 0)

        bridge.invalidate()
        XCTAssertTrue(
            bridge.debugReceiveDocumentReady(documentToken: "preview-never-doc-12345678")
                == false
        )
        var invalidatedResult: ChatGPTResponsePreviewSnapshot?
        bridge.previewLatestAssistantResponse { snapshot in
            invalidatedResult = snapshot
        }
        XCTAssertNil(invalidatedResult)
        XCTAssertEqual(probe.requestCount, 0)
    }

    /// The preview projection uses its own one-shot script and never touches
    /// the status snapshot script.
    func testPreviewUsesDedicatedScriptSeparateFromStatusSnapshot() async throws {
        let probe = ResponsePreviewSnapshotProviderProbe()
        let (bridge, retainedWebView) = makePreviewBridge(probe: probe)
        XCTAssertNotNil(retainedWebView)
        XCTAssertTrue(
            bridge.debugReceiveDocumentReady(documentToken: "preview-script-doc-12345678")
        )

        bridge.previewLatestAssistantResponse { _ in }
        for _ in 0..<100 where probe.requestCount == 0 {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(
            probe.lastScript,
            "globalThis.__floatTabsChatGPTResponsePreviewV1?.()"
        )
    }
}
