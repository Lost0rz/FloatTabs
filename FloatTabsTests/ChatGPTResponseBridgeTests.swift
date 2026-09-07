import WebKit
import XCTest
@testable import FloatTabs

@MainActor
final class ChatGPTResponseBridgeTests: XCTestCase {
    func testPayloadParsingAcceptsStructuredResponseOnly() {
        let payload = ChatGPTResponsePayload.parse([
            "version": 1,
            "kind": "response",
            "requestID": "request-12345678",
            "documentToken": "document-12345678",
            "responseID": "document-12345678:response-1",
            "blocks": [
                ["kind": "paragraph", "text": "Hello", "level": NSNull()],
                ["kind": "heading", "text": "Title", "level": 2],
            ],
        ])

        XCTAssertEqual(payload?.blocks.count, 2)
        XCTAssertEqual(payload?.blocks.first?.kind, .paragraph)
        XCTAssertEqual(payload?.responseID, "document-12345678:response-1")
    }

    func testPayloadParsingRejectsMalformedOrContentlessResponses() {
        XCTAssertNil(ChatGPTResponsePayload.parse([:]))
        XCTAssertNil(ChatGPTResponsePayload.parse([
            "version": 2,
            "kind": "response",
            "requestID": "request-12345678",
            "documentToken": "document-12345678",
            "responseID": "document-12345678:response-1",
            "blocks": [["kind": "paragraph", "text": "Hello"]],
        ]))
        XCTAssertNil(ChatGPTResponsePayload.parse([
            "version": 1,
            "kind": "response",
            "requestID": "request-12345678",
            "documentToken": "document-12345678",
            "responseID": "document-12345678:response-1",
            "blocks": [],
        ]))
        XCTAssertNil(ChatGPTResponsePayload.parse([
            "version": 1,
            "kind": "response",
            "requestID": "request-12345678",
            "documentToken": "document-12345678",
            "responseID": "document-12345678:response-1",
            "blocks": [["kind": "paragraph", "text": "Hello"], ["kind": "unknown", "text": "x"]],
        ]))
    }

    func testEmptyPayloadIsValidWithoutResponseBody() {
        let payload = ChatGPTResponsePayload.parse([
            "version": 1,
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
                "__floatTabsChatGPTResponseRequestLatestV1"
            )
        )
        XCTAssertFalse(ChatGPTResponseExtraction.scriptSource.contains("MutationObserver"))
        XCTAssertFalse(ChatGPTResponseExtraction.scriptSource.contains("characterData"))
        XCTAssertFalse(ChatGPTResponseExtraction.scriptSource.contains("document.body.innerText"))
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
            version: 1,
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
