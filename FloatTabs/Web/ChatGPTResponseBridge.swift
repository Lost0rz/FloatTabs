import Foundation
import WebKit

@MainActor
protocol ChatGPTResponseExtracting: AnyObject {
    func extractLatest(completion: @escaping @MainActor (ChatGPTResponsePayload?) -> Void)
}

@MainActor
protocol ChatGPTResponseFollowing: AnyObject {
    func scrollToSpeechBlock(
        _ locator: SpeechSourceLocator,
        completion: @escaping @MainActor (Bool) -> Void
    )
}

/// A per-WebView, one-shot ChatGPT response extractor. Unlike the attention
/// bridge, this bridge never observes DOM mutations; it only evaluates the
/// extraction function when explicitly requested.
@MainActor
final class ChatGPTResponseBridge: NSObject, WKScriptMessageHandler, ChatGPTResponseExtracting, ChatGPTResponseFollowing {
    typealias ResultHandler = @MainActor (ChatGPTResponsePayload?) -> Void
    typealias ManualScrollHandler = @MainActor (UUID, String) -> Void

    private struct PendingRequest {
        let webViewIdentity: ObjectIdentifier
        let completion: ResultHandler
    }

    let slotID: UUID
    private let onRuntimeReset: @MainActor (UUID) -> Void
    private let onManualScroll: ManualScrollHandler
    private weak var webView: WKWebView?
    private weak var userContentController: WKUserContentController?
    private var pendingRequests: [String: PendingRequest] = [:]
    private var currentDocumentToken: String?
    private(set) var isInvalidated = false

    init(
        slotID: UUID,
        onRuntimeReset: @escaping @MainActor (UUID) -> Void = { _ in },
        onManualScroll: @escaping ManualScrollHandler = { _, _ in }
    ) {
        self.slotID = slotID
        self.onRuntimeReset = onRuntimeReset
        self.onManualScroll = onManualScroll
        super.init()
    }

    func install(into userContentController: WKUserContentController) {
        guard !isInvalidated else { return }
        userContentController.addUserScript(
            WKUserScript(
                source: ChatGPTResponseExtraction.scriptSource,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true,
                in: ChatGPTResponseExtraction.contentWorld
            )
        )
        userContentController.add(
            self,
            contentWorld: ChatGPTResponseExtraction.contentWorld,
            name: ChatGPTResponseExtraction.messageHandlerName
        )
        self.userContentController = userContentController
    }

    func attach(to webView: WKWebView) {
        guard !isInvalidated else { return }
        self.webView = webView
    }

    func scrollToSpeechBlock(
        _ locator: SpeechSourceLocator,
        completion: @escaping @MainActor (Bool) -> Void = { _ in }
    ) {
        guard !isInvalidated,
              locator.slotID == slotID,
              locator.documentToken == currentDocumentToken,
              let webView else {
            completion(false)
            return
        }

        webView.evaluateJavaScript(
            Self.scrollScript(locator: locator),
            in: nil,
            in: ChatGPTResponseExtraction.contentWorld
        ) { result in
            Task { @MainActor in
                completion((try? result.get() as? Bool) ?? false)
            }
        }
    }

    /// Requests one extraction from the currently attached document. The
    /// result is delivered through the independent script-message channel.
    func extractLatest(completion: @escaping ResultHandler) {
        guard !isInvalidated, let webView else {
            completion(nil)
            return
        }

        let requestID = UUID().uuidString
        pendingRequests[requestID] = PendingRequest(
            webViewIdentity: ObjectIdentifier(webView),
            completion: completion
        )
        webView.evaluateJavaScript(
            Self.requestScript(requestID: requestID),
            in: nil,
            in: ChatGPTResponseExtraction.contentWorld
        ) { [weak self, weak webView] (result: Result<Any, Error>) in
            guard let self,
                  let webView,
                  let pending = self.pendingRequests[requestID],
                  pending.webViewIdentity == ObjectIdentifier(webView) else {
                return
            }
            guard case let .success(value) = result, (value as? Bool) == true else {
                self.pendingRequests.removeValue(forKey: requestID)
                pending.completion(nil)
                return
            }
            // A successful JavaScript invocation is not the response itself;
            // the independent message handler will resolve the pending item.
        }
    }

    func handleRuntimeReplacement() {
        currentDocumentToken = nil
        finishPendingRequests()
        onRuntimeReset(slotID)
    }

    func invalidate() {
        guard !isInvalidated else { return }
        isInvalidated = true
        finishPendingRequests()
        currentDocumentToken = nil
        userContentController?.removeScriptMessageHandler(
            forName: ChatGPTResponseExtraction.messageHandlerName,
            contentWorld: ChatGPTResponseExtraction.contentWorld
        )
        userContentController = nil
        webView = nil
        onRuntimeReset(slotID)
    }

    // MARK: WKScriptMessageHandler

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let attachedWebView = webView,
              message.webView === attachedWebView,
              message.frameInfo.isMainFrame,
              ChatGPTSitePolicy.isSupportedHost(
                message.frameInfo.securityOrigin.host
              ),
              ["http", "https"].contains(
                message.frameInfo.securityOrigin.`protocol`.lowercased()
              ),
              let body = message.body as? [String: Any] else {
            return
        }
        if body["event"] as? String == "manualScroll",
           body["version"] as? Int == ChatGPTResponsePayload.currentVersion,
           let documentToken = body["documentToken"] as? String,
           documentToken == currentDocumentToken {
            onManualScroll(slotID, documentToken)
            return
        }

        guard let payload = ChatGPTResponsePayload.parse(body),
              let pending = pendingRequests.removeValue(forKey: payload.requestID),
              pending.webViewIdentity == ObjectIdentifier(attachedWebView) else {
            return
        }
        currentDocumentToken = payload.documentToken
        pending.completion(
            payload.kind == .response ? payload.assigning(slotID: slotID) : nil
        )
    }

    private func finishPendingRequests() {
        let pending = pendingRequests.values
        pendingRequests.removeAll()
        pending.forEach { $0.completion(nil) }
    }

    private static func requestScript(requestID: String) -> String {
        let encoded: String
        if let data = try? JSONSerialization.data(withJSONObject: [requestID]),
           let json = String(data: data, encoding: .utf8) {
            encoded = String(json.dropFirst().dropLast())
        } else {
            encoded = "\"\""
        }
        return "globalThis.__floatTabsChatGPTResponseRequestLatestV3?.(\(encoded)) === true"
    }

    private static func scrollScript(locator: SpeechSourceLocator) -> String {
        let values = [locator.documentToken, locator.responseID, locator.blockID]
        guard let data = try? JSONSerialization.data(withJSONObject: values),
              let json = String(data: data, encoding: .utf8) else {
            return "false"
        }
        return "globalThis.__floatTabsScrollToSpeechBlockV3?.(\(json.dropFirst().dropLast())) === true"
    }
}
