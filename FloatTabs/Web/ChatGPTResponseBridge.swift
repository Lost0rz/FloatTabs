import Foundation
import WebKit

@MainActor
protocol ChatGPTResponseStatusSnapshotting: AnyObject {
    func snapshotLatestResponseStatus(
        completion: @escaping @MainActor (ChatGPTResponseStatusSnapshot?) -> Void
    )
}

/// Per-WebView bridge for response identity, status and trusted page input.
/// Response body extraction and follow behavior are deliberately not owned here.
@MainActor
final class ChatGPTResponseBridge: NSObject, WKScriptMessageHandler, ChatGPTResponseStatusSnapshotting {
    typealias TrustedInteractionHandler = @MainActor (UUID, ChatGPTTrustedPageInteractionKind, String) -> Void
    typealias TrustedInteractionEventHandler = @MainActor (UUID, ChatGPTTrustedInteractionEvent) -> Void
    typealias ResponseStatusSnapshotProvider = @MainActor (WKWebView, String) async -> ChatGPTResponseStatusSnapshot?

    let slotID: UUID
    private let onTrustedInteraction: TrustedInteractionHandler
    private let onTrustedInteractionEvent: TrustedInteractionEventHandler?
    private weak var webView: WKWebView?
    private weak var userContentController: WKUserContentController?
    private var currentDocumentToken: String?
    private var responseStatusSnapshotProvider: ResponseStatusSnapshotProvider
#if DEBUG
    private var debugLatestResponseStatusOverride: ChatGPTResponseStatusSnapshot?
#endif
    private(set) var isInvalidated = false

    /// Whether this bridge currently recognizes a document-ready handshake.
    /// The opaque document token itself is never exposed to diagnostics.
    var diagnosticCurrentDocumentReady: Bool {
        !isInvalidated && currentDocumentToken != nil
    }

    init(
        slotID: UUID,
        onTrustedInteraction: @escaping TrustedInteractionHandler = { _, _, _ in },
        onTrustedInteractionEvent: TrustedInteractionEventHandler? = nil,
        responseStatusSnapshotProvider: ResponseStatusSnapshotProvider? = nil
    ) {
        self.slotID = slotID
        self.onTrustedInteraction = onTrustedInteraction
        self.onTrustedInteractionEvent = onTrustedInteractionEvent
        self.responseStatusSnapshotProvider = responseStatusSnapshotProvider ?? { webView, script in
            await Self.evaluateResponseStatusSnapshot(in: webView, script: script)
        }
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

    /// Reads only latest response identity/status metadata from the current
    /// document. No response body is requested.
    func snapshotLatestResponseStatus(
        completion: @escaping @MainActor (ChatGPTResponseStatusSnapshot?) -> Void
    ) {
        guard !isInvalidated,
              let webView,
              let documentToken = currentDocumentToken else {
            completion(nil)
            return
        }
#if DEBUG
        if let debugLatestResponseStatusOverride {
            completion(
                debugLatestResponseStatusOverride.documentToken == documentToken
                    ? debugLatestResponseStatusOverride
                    : nil
            )
            return
        }
#endif
        let webViewIdentity = ObjectIdentifier(webView)
        let provider = responseStatusSnapshotProvider
        Task { @MainActor [weak self, weak webView] in
            guard let webView else {
                completion(nil)
                return
            }
            let snapshot = await provider(webView, Self.snapshotLatestResponseStatusScript)
            guard let self,
                  !self.isInvalidated,
                  self.webView === webView,
                  ObjectIdentifier(webView) == webViewIdentity,
                  self.currentDocumentToken == documentToken,
                  let snapshot,
                  snapshot.documentToken == documentToken else {
                completion(nil)
                return
            }
            completion(snapshot)
        }
    }

    /// Validates and admits one normalized trusted page interaction. Admission
    /// never changes unread state itself; PanelController remains the owner.
    @discardableResult
    func acceptTrustedInteraction(
        body: [String: Any],
        messageWebView: WKWebView?,
        isMainFrame: Bool,
        originHost: String?,
        originProtocol: String?
    ) -> Bool {
        guard !isInvalidated,
              let attachedWebView = webView,
              messageWebView === attachedWebView,
              isMainFrame,
              let originHost,
              ChatGPTSitePolicy.isSupportedHost(originHost),
              let originProtocol,
              ["http", "https"].contains(originProtocol.lowercased()),
              body["event"] as? String == "trustedInteraction",
              body["version"] as? Int == ChatGPTResponseProtocol.currentVersion,
              let documentToken = body["documentToken"] as? String,
              documentToken == currentDocumentToken,
              let rawKind = body["interactionKind"] as? String,
              let kind = ChatGPTTrustedPageInteractionKind(rawValue: rawKind) else {
            return false
        }

        let responseIdentity: ChatGPTResponseIdentity?
        if let rawIdentity = body["responseIdentity"] as? String {
            guard let parsedIdentity = ChatGPTResponseIdentity(rawValue: rawIdentity) else {
                return false
            }
            responseIdentity = parsedIdentity
        } else if body["responseIdentity"] == nil || body["responseIdentity"] is NSNull {
            responseIdentity = nil
        } else {
            return false
        }

        let responseComplete: Bool
        if let rawResponseComplete = body["responseComplete"] {
            guard let parsedResponseComplete = rawResponseComplete as? Bool else {
                return false
            }
            responseComplete = parsedResponseComplete
        } else {
            responseComplete = false
        }

        let event = ChatGPTTrustedInteractionEvent(
            kind: kind,
            documentToken: documentToken,
            responseIdentity: responseIdentity,
            responseComplete: responseComplete
        )
        onTrustedInteractionEvent?(slotID, event)
        onTrustedInteraction(slotID, kind, documentToken)
        return true
    }

#if DEBUG
    /// Test-only delivery of the post-commit document identity. This models
    /// the native validation used by the real script-message route.
    @discardableResult
    func debugReceiveDocumentReady(
        documentToken: String,
        version: Int = ChatGPTResponseProtocol.currentVersion
    ) -> Bool {
        guard !isInvalidated,
              version == ChatGPTResponseProtocol.currentVersion else {
            return false
        }
        return acceptDocumentReady(documentToken)
    }

    /// Test-only forwarding for trusted manual-scroll evidence. Manual scroll
    /// remains an Unread interaction event; there is no callback.
    @discardableResult
    func debugInvokeTrustedManualScroll(documentToken: String) -> Bool {
        debugInvokeTrustedManualScroll(
            documentToken: documentToken,
            latestResponseIdentity: nil,
            latestResponseComplete: false
        )
    }

    @discardableResult
    func debugInvokeTrustedManualScroll(
        documentToken: String,
        latestResponseIdentity: ChatGPTResponseIdentity?,
        latestResponseComplete: Bool
    ) -> Bool {
        guard !isInvalidated, documentToken == currentDocumentToken else {
            return false
        }
        onTrustedInteractionEvent?(
            slotID,
            ChatGPTTrustedInteractionEvent(
                kind: .manualScroll,
                documentToken: documentToken,
                responseIdentity: latestResponseIdentity,
                responseComplete: latestResponseComplete
            )
        )
        return true
    }

    /// Test-only forwarding for a trust-admitted normalized interaction.
    @discardableResult
    func debugInvokeTrustedInteraction(
        kind: ChatGPTTrustedPageInteractionKind,
        documentToken: String,
        responseIdentity: ChatGPTResponseIdentity? = nil,
        responseComplete: Bool = false
    ) -> Bool {
        guard !isInvalidated, documentToken == currentDocumentToken else {
            return false
        }
        onTrustedInteraction(slotID, kind, documentToken)
        onTrustedInteractionEvent?(
            slotID,
            ChatGPTTrustedInteractionEvent(
                kind: kind,
                documentToken: documentToken,
                responseIdentity: responseIdentity,
                responseComplete: responseComplete
            )
        )
        return true
    }

    func debugSetLatestResponseStatusOverride(
        _ snapshot: ChatGPTResponseStatusSnapshot?
    ) {
        debugLatestResponseStatusOverride = snapshot
    }

    func debugSetResponseStatusSnapshotProvider(
        _ provider: @escaping ResponseStatusSnapshotProvider
    ) {
        responseStatusSnapshotProvider = provider
    }
#endif

    /// A navigation/runtime replacement invalidates the document identity but
    /// keeps the bridge installed for the replacement document.
    func handleRuntimeReplacement() {
        currentDocumentToken = nil
    }

    func invalidate() {
        guard !isInvalidated else { return }
        isInvalidated = true
        currentDocumentToken = nil
        userContentController?.removeScriptMessageHandler(
            forName: ChatGPTResponseExtraction.messageHandlerName,
            contentWorld: ChatGPTResponseExtraction.contentWorld
        )
        userContentController = nil
        webView = nil
    }

    // MARK: WKScriptMessageHandler

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let attachedWebView = webView,
              message.webView === attachedWebView,
              message.frameInfo.isMainFrame,
              ChatGPTSitePolicy.isSupportedHost(message.frameInfo.securityOrigin.host),
              ["http", "https"].contains(
                  message.frameInfo.securityOrigin.`protocol`.lowercased()
              ),
              let body = message.body as? [String: Any] else {
            return
        }

        if body["event"] as? String == "documentReady" {
            guard body["version"] as? Int == ChatGPTResponseProtocol.currentVersion,
                  let documentToken = body["documentToken"] as? String,
                  acceptDocumentReady(documentToken) else {
                return
            }
            return
        }

        if body["event"] as? String == "manualScroll",
           body["version"] as? Int == ChatGPTResponseProtocol.currentVersion,
           let documentToken = body["documentToken"] as? String,
           documentToken == currentDocumentToken {
            let responseIdentity: ChatGPTResponseIdentity?
            if let rawIdentity = body["latestResponseIdentity"] as? String {
                guard let parsedIdentity = ChatGPTResponseIdentity(rawValue: rawIdentity) else {
                    return
                }
                responseIdentity = parsedIdentity
            } else if body["latestResponseIdentity"] == nil
                        || body["latestResponseIdentity"] is NSNull {
                responseIdentity = nil
            } else {
                return
            }

            let responseComplete: Bool
            if let rawResponseComplete = body["latestResponseComplete"] {
                guard let parsedResponseComplete = rawResponseComplete as? Bool else {
                    return
                }
                responseComplete = parsedResponseComplete
            } else {
                responseComplete = false
            }
            onTrustedInteractionEvent?(
                slotID,
                ChatGPTTrustedInteractionEvent(
                    kind: .manualScroll,
                    documentToken: documentToken,
                    responseIdentity: responseIdentity,
                    responseComplete: responseComplete
                )
            )
            return
        }

        if body["event"] as? String == "trustedInteraction" {
            _ = acceptTrustedInteraction(
                body: body,
                messageWebView: message.webView,
                isMainFrame: message.frameInfo.isMainFrame,
                originHost: message.frameInfo.securityOrigin.host,
                originProtocol: message.frameInfo.securityOrigin.`protocol`
            )
        }
    }

    @discardableResult
    private func acceptDocumentReady(_ documentToken: String) -> Bool {
        guard ChatGPTResponseProtocol.isOpaqueIdentifier(documentToken) else {
            return false
        }
        currentDocumentToken = documentToken
        return true
    }

    private static let snapshotLatestResponseStatusScript =
        "globalThis.__floatTabsChatGPTResponseIdentitySnapshotV1?.()"

    static func parseResponseStatusSnapshot(_ value: Any) -> ChatGPTResponseStatusSnapshot? {
        guard let body = value as? [String: Any],
              body["version"] as? Int == 1,
              let documentToken = body["documentToken"] as? String,
              ChatGPTResponseProtocol.isOpaqueIdentifier(documentToken),
              let generating = body["generating"] as? Bool else {
            return nil
        }
        let responseIdentity: ChatGPTResponseIdentity?
        if let rawIdentity = body["responseIdentity"] as? String {
            guard let parsedIdentity = ChatGPTResponseIdentity(rawValue: rawIdentity) else {
                return nil
            }
            responseIdentity = parsedIdentity
        } else if body["responseIdentity"] == nil || body["responseIdentity"] is NSNull {
            responseIdentity = nil
        } else {
            return nil
        }
        return ChatGPTResponseStatusSnapshot(
            documentToken: documentToken,
            responseIdentity: responseIdentity,
            generating: generating
        )
    }

    private static func evaluateResponseStatusSnapshot(
        in webView: WKWebView,
        script: String
    ) async -> ChatGPTResponseStatusSnapshot? {
        await withCheckedContinuation { continuation in
            webView.evaluateJavaScript(
                script,
                in: nil,
                in: ChatGPTResponseExtraction.contentWorld
            ) { result in
                guard case let .success(value) = result else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: parseResponseStatusSnapshot(value))
            }
        }
    }
}
