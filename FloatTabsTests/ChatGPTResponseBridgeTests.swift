import WebKit
import XCTest
@testable import FloatTabs

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
        XCTAssertFalse(ChatGPTResponseExtraction.scriptSource.contains("MutationObserver"))
        XCTAssertFalse(ChatGPTResponseExtraction.scriptSource.contains("characterData"))
        XCTAssertFalse(ChatGPTResponseExtraction.scriptSource.contains("document.body.innerText"))
        XCTAssertTrue(ChatGPTResponseExtraction.scriptSource.contains("scrollIntoView"))
        XCTAssertFalse(ChatGPTResponseExtraction.scriptSource.contains(".focus()"))
        XCTAssertFalse(ChatGPTResponseExtraction.scriptSource.contains("setInterval"))
        XCTAssertFalse(ChatGPTResponseExtraction.scriptSource.contains("setTimeout"))
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
}
