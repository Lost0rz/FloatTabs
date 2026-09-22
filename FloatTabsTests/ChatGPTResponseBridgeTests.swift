import WebKit
import XCTest
@testable import FloatTabs

@MainActor
private final class TrustedInteractionAdmissionProbe {
    var count = 0
}

@MainActor
final class ChatGPTResponseBridgeTests: XCTestCase {
    func testPayloadParsingAcceptsStructuredResponseOnly() {
        let payload = ChatGPTResponsePayload.parse([
            "version": ChatGPTResponsePayload.currentVersion,
            "kind": "response",
            "requestID": "request-12345678",
            "documentToken": "document-12345678",
            "responseID": "document-12345678:response-1",
            "blocks": [
                [
                    "kind": "paragraph",
                    "text": "Hello",
                    "level": NSNull(),
                    "sourceLocator": [
                        "documentToken": "document-12345678",
                        "responseID": "document-12345678:response-1",
                        "blockID": "document-12345678:response-1:block-0",
                    ],
                ],
                [
                    "kind": "heading",
                    "text": "Title",
                    "level": 2,
                    "sourceLocator": [
                        "documentToken": "document-12345678",
                        "responseID": "document-12345678:response-1",
                        "blockID": "document-12345678:response-1:block-1",
                    ],
                ],
            ],
        ])

        XCTAssertEqual(payload?.blocks.count, 2)
        XCTAssertEqual(payload?.blocks.first?.kind, .paragraph)
        XCTAssertEqual(payload?.responseID, "document-12345678:response-1")
        XCTAssertEqual(
            payload?.blocks.first?.sourceLocator?.blockID,
            "document-12345678:response-1:block-0"
        )
    }

    func testPayloadParsingRejectsMalformedOrContentlessResponses() {
        XCTAssertNil(ChatGPTResponsePayload.parse([:]))
        XCTAssertNil(ChatGPTResponsePayload.parse([
            "version": ChatGPTResponsePayload.currentVersion + 1,
            "kind": "response",
            "requestID": "request-12345678",
            "documentToken": "document-12345678",
            "responseID": "document-12345678:response-1",
            "blocks": [[
                "kind": "paragraph",
                "text": "Hello",
                "sourceLocator": [
                    "documentToken": "document-12345678",
                    "responseID": "document-12345678:response-1",
                    "blockID": "document-12345678:response-1:block-0",
                ],
            ]],
        ]))
        XCTAssertNil(ChatGPTResponsePayload.parse([
            "version": ChatGPTResponsePayload.currentVersion,
            "kind": "response",
            "requestID": "request-12345678",
            "documentToken": "document-12345678",
            "responseID": "document-12345678:response-1",
            "blocks": [],
        ]))
        XCTAssertNil(ChatGPTResponsePayload.parse([
            "version": ChatGPTResponsePayload.currentVersion,
            "kind": "response",
            "requestID": "request-12345678",
            "documentToken": "document-12345678",
            "responseID": "document-12345678:response-1",
            "blocks": [
                [
                    "kind": "paragraph",
                    "text": "Hello",
                    "sourceLocator": [
                        "documentToken": "document-12345678",
                        "responseID": "document-12345678:response-1",
                        "blockID": "document-12345678:response-1:block-0",
                    ],
                ],
                ["kind": "unknown", "text": "x"],
            ],
        ]))
        XCTAssertNil(ChatGPTResponsePayload.parse([
            "version": ChatGPTResponsePayload.currentVersion,
            "kind": "response",
            "requestID": "request-12345678",
            "documentToken": "document-12345678",
            "responseID": "document-12345678:response-1",
            "blocks": [[
                "kind": "paragraph",
                "text": "Hello",
            ]],
        ]))
        XCTAssertNil(ChatGPTResponsePayload.parse([
            "version": ChatGPTResponsePayload.currentVersion,
            "kind": "response",
            "requestID": "request-12345678",
            "documentToken": "document-12345678",
            "responseID": "document-12345678:response-1",
            "blocks": [[
                "kind": "paragraph",
                "text": "Hello",
                "sourceLocator": [
                    "documentToken": "document-12345678",
                    "responseID": "document-12345678:other-response",
                    "blockID": "document-12345678:response-1:block-0",
                ],
            ]],
        ]))
    }

    func testEmptyPayloadIsValidWithoutResponseBody() {
        let payload = ChatGPTResponsePayload.parse([
            "version": ChatGPTResponsePayload.currentVersion,
            "kind": "empty",
            "requestID": "request-12345678",
            "documentToken": "document-12345678",
            "responseID": NSNull(),
            "blocks": [],
        ])

        XCTAssertEqual(payload?.kind, .empty)
        XCTAssertNil(payload?.responseID)
        XCTAssertTrue(payload?.blocks.isEmpty == true)
    }

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

    func testBridgeUsesIndependentNamedWorldAndNoPersistentMutationObserver() {
        XCTAssertEqual(
            ChatGPTResponseExtraction.contentWorld.name,
            ChatGPTResponseExtraction.contentWorldName
        )
        XCTAssertTrue(
            ChatGPTResponseExtraction.scriptSource.contains(
                "__floatTabsChatGPTResponseRequestLatestV3"
            )
        )
        XCTAssertTrue(
            ChatGPTResponseExtraction.scriptSource.contains(
                "__floatTabsScrollToSpeechBlockV3"
            )
        )
        XCTAssertTrue(ChatGPTResponseExtraction.scriptSource.contains("responseLocatorKeys"))
        XCTAssertTrue(ChatGPTResponseExtraction.scriptSource.contains("MAX_RESPONSE_GROUPS"))
        XCTAssertFalse(ChatGPTResponseExtraction.scriptSource.contains("locatorRegistry.clear()"))
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
        XCTAssertTrue(ChatGPTResponseExtraction.scriptSource.contains("scrollIntoView"))
        XCTAssertFalse(ChatGPTResponseExtraction.scriptSource.contains(".focus()"))
        XCTAssertFalse(ChatGPTResponseExtraction.scriptSource.contains("setInterval"))
        XCTAssertFalse(ChatGPTResponseExtraction.scriptSource.contains("setTimeout"))
    }

    func testResponseIdentityPolicyIsSharedWithSpeechExtractionWithoutChangingSpeechIDs() throws {
        let source = ChatGPTResponseExtraction.scriptSource
        XCTAssertTrue(source.contains("RESPONSE_STABLE_ATTRIBUTE_NAMES"))
        XCTAssertTrue(source.contains("data-message-id"))
        XCTAssertTrue(source.contains("data-message-uuid"))
        XCTAssertTrue(source.contains("canonicalResponseIdentityFor"))
        XCTAssertTrue(source.contains("latestResponseIdentity"))
        XCTAssertTrue(source.contains("latestResponseComplete"))
        XCTAssertTrue(source.contains("responseIDFor"))
        let identity = try XCTUnwrap(
            ChatGPTResponseIdentity(stableValue: "speech-independent-id")
        )
        XCTAssertEqual(identity.rawValue, "message:speech-independent-id")
    }

    func testBridgeLifecycleResetRejectsOldPendingCallback() {
        let slotID = UUID()
        var resetSlotID: UUID?
        let bridge = ChatGPTResponseBridge(slotID: slotID) { resetSlotID = $0 }
        let controller = WKUserContentController()
        bridge.install(into: controller)
        let webView = WKWebView(
            frame: .zero,
            configuration: WKWebViewConfiguration()
        )
        bridge.attach(to: webView)

        var callbackResult: ChatGPTResponsePayload? = ChatGPTResponsePayload(
            version: ChatGPTResponsePayload.currentVersion,
            kind: .empty,
            requestID: "request-12345678",
            documentToken: "document-12345678",
            responseID: nil,
            blocks: []
        )
        bridge.extractLatest { callbackResult = $0 }
        bridge.handleRuntimeReplacement()

        XCTAssertEqual(resetSlotID, slotID)
        XCTAssertNil(callbackResult)
    }

    func testDocumentReadyEstablishesLiveIdentityWithoutExtraction() {
        let slotID = UUID()
        var manualScrollCount = 0
        let bridge = ChatGPTResponseBridge(
            slotID: slotID,
            onManualScroll: { _, _ in manualScrollCount += 1 }
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
        XCTAssertEqual(manualScrollCount, 1)
    }

    func testDocumentReadyRejectsInvalidTokenAndWrongVersion() {
        let bridge = ChatGPTResponseBridge(slotID: UUID())

        XCTAssertFalse(
            bridge.debugReceiveDocumentReady(documentToken: "short")
        )
        XCTAssertFalse(
            bridge.debugReceiveDocumentReady(
                documentToken: "document-ready-12345678",
                version: ChatGPTResponsePayload.currentVersion + 1
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
            onManualScroll: { _, token in manualScrollTokens.append(token) }
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
                    "version": ChatGPTResponsePayload.currentVersion,
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
            "version": ChatGPTResponsePayload.currentVersion,
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
        XCTAssertTrue(source.contains("article[data-testid*=\"conversation-turn\"]"))
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
                    version: ChatGPTResponsePayload.currentVersion + 1
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
        version: Int = ChatGPTResponsePayload.currentVersion,
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
