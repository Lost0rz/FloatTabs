import Foundation
import WebKit

@MainActor
protocol ChatGPTResponseExtracting: AnyObject {
    func extractLatest(completion: @escaping @MainActor (ChatGPTResponsePayload?) -> Void)
}

@MainActor
protocol ChatGPTResponseStatusSnapshotting: AnyObject {
    func snapshotLatestResponseStatus(
        completion: @escaping @MainActor (ChatGPTResponseStatusSnapshot?) -> Void
    )
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
final class ChatGPTResponseBridge: NSObject, WKScriptMessageHandler, ChatGPTResponseExtracting, ChatGPTResponseFollowing, ChatGPTResponseStatusSnapshotting {
    typealias ResultHandler = @MainActor (ChatGPTResponsePayload?) -> Void
    typealias ManualScrollHandler = @MainActor (UUID, String) -> Void
    typealias TrustedInteractionHandler = @MainActor (UUID, ChatGPTTrustedPageInteractionKind, String) -> Void
    typealias TrustedInteractionEventHandler = @MainActor (UUID, ChatGPTTrustedInteractionEvent) -> Void
    typealias ResponseStatusSnapshotProvider = @MainActor (WKWebView, String) async -> ChatGPTResponseStatusSnapshot?

    private struct PendingRequest {
        let webViewIdentity: ObjectIdentifier
        let completion: ResultHandler
    }

    let slotID: UUID
    let bridgeInstanceID: UUID
    private let onRuntimeReset: @MainActor (UUID) -> Void
    private let onManualScroll: ManualScrollHandler
    private let onTrustedInteraction: TrustedInteractionHandler
    private let onTrustedInteractionEvent: TrustedInteractionEventHandler?
    private let diagnostics: any RuntimeDiagnosticRecording
    private let diagnosticContext: UnreadRuntimeDiagnosticContext
    private weak var webView: WKWebView?
    private weak var userContentController: WKUserContentController?
    private var pendingRequests: [String: PendingRequest] = [:]
    private var currentDocumentToken: String?
    private var responseStatusSnapshotProvider: ResponseStatusSnapshotProvider
#if DEBUG
    private var debugLatestResponseStatusOverride: ChatGPTResponseStatusSnapshot?
#endif
    private(set) var isInvalidated = false

    init(
        slotID: UUID,
        onRuntimeReset: @escaping @MainActor (UUID) -> Void = { _ in },
        onManualScroll: @escaping ManualScrollHandler = { _, _ in },
        onTrustedInteraction: @escaping TrustedInteractionHandler = { _, _, _ in },
        onTrustedInteractionEvent: TrustedInteractionEventHandler? = nil,
        responseStatusSnapshotProvider: ResponseStatusSnapshotProvider? = nil,
        diagnostics: any RuntimeDiagnosticRecording = RuntimeDiagnosticNoopRecorder(),
        bridgeInstanceID: UUID = UUID(),
        diagnosticContext: UnreadRuntimeDiagnosticContext = .shared
    ) {
        self.slotID = slotID
        self.bridgeInstanceID = bridgeInstanceID
        self.onRuntimeReset = onRuntimeReset
        self.onManualScroll = onManualScroll
        self.onTrustedInteraction = onTrustedInteraction
        self.onTrustedInteractionEvent = onTrustedInteractionEvent
        self.diagnostics = diagnostics
        self.diagnosticContext = diagnosticContext
        self.responseStatusSnapshotProvider = responseStatusSnapshotProvider ?? { webView, script in
            await Self.evaluateResponseStatusSnapshot(
                in: webView,
                script: script
            )
        }
        super.init()
        recordBridgeDiagnostic(event: "bridge.created")
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

    /// Reads only the latest response status from the current document. The
    /// result is identity/status metadata, never response content, and is
    /// rejected if the WebView or document changed while WebKit evaluated it.
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
            let snapshot = await provider(
                webView,
                Self.snapshotLatestResponseStatusScript
            )
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

    /// Validates and admits one normalized trusted page interaction. This is
    /// the shared native boundary used by the real script-message route and
    /// by deterministic tests; admission never changes unread state itself.
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
              body["version"] as? Int == ChatGPTResponsePayload.currentVersion,
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
            responseComplete: responseComplete,
            latestResponseIdentity: (body["latestResponseIdentity"] as? String)
                .flatMap { ChatGPTResponseIdentity(rawValue: $0) },
            latestResponseComplete: body["latestResponseComplete"] as? Bool ?? responseComplete,
            responseRootCount: body["responseRootCount"] as? Int ?? 0,
            bridgeInstanceID: bridgeInstanceID
        )
        onTrustedInteractionEvent?(slotID, event)
        onTrustedInteraction(slotID, kind, documentToken)
        return true
    }

#if DEBUG
    /// Test-only delivery of the post-commit document identity. The helper
    /// shares the native validation used by the real script-message route and
    /// deliberately does not invoke extraction.
    @discardableResult
    func debugReceiveDocumentReady(
        documentToken: String,
        version: Int = ChatGPTResponsePayload.currentVersion
    ) -> Bool {
        guard !isInvalidated,
              version == ChatGPTResponsePayload.currentVersion else {
            return false
        }
        return acceptDocumentReady(documentToken)
    }

    /// Test-only response delivery for a pending extraction. This preserves
    /// the bridge's normal completion path while avoiding a real WebKit page
    /// and network response in deterministic speech state tests.
    @discardableResult
    func debugResolveFirstPendingRequest(
        with payload: ChatGPTResponsePayload
    ) -> Bool {
        guard let requestID = pendingRequests.keys.first,
              let pending = pendingRequests.removeValue(forKey: requestID) else {
            return false
        }
        guard payload.documentToken == currentDocumentToken else {
            pending.completion(nil)
            return true
        }
        pending.completion(
            payload.kind == .response
                ? payload.assigning(slotID: slotID)
                : nil
        )
        return true
    }

    /// Test-only forwarding for a manual-scroll event after the production
    /// content-world trust/document checks have been modeled deterministically.
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
        onManualScroll(slotID, documentToken)
        onTrustedInteractionEvent?(
            slotID,
            ChatGPTTrustedInteractionEvent(
                kind: .manualScroll,
                documentToken: documentToken,
                responseIdentity: latestResponseIdentity,
                responseComplete: latestResponseComplete,
                latestResponseIdentity: latestResponseIdentity,
                latestResponseComplete: latestResponseComplete,
                bridgeInstanceID: bridgeInstanceID
            )
        )
        return true
    }

    /// Test-only forwarding for a trust-admitted normalized interaction. The
    /// helper models only the post-content-world event and still validates the
    /// live document identity used by the production route.
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
                responseComplete: responseComplete,
                latestResponseIdentity: responseIdentity,
                latestResponseComplete: responseComplete,
                bridgeInstanceID: bridgeInstanceID
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

    func handleRuntimeReplacement() {
        recordBridgeDiagnostic(
            event: "bridge.document_changed",
            documentToken: currentDocumentToken
        )
        currentDocumentToken = nil
        finishPendingRequests()
        onRuntimeReset(slotID)
    }

    func invalidate() {
        guard !isInvalidated else { return }
        recordBridgeDiagnostic(
            event: "bridge.destroyed",
            documentToken: currentDocumentToken
        )
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
        if body["event"] as? String == "documentReady" {
            guard body["version"] as? Int == ChatGPTResponsePayload.currentVersion,
                  let documentToken = body["documentToken"] as? String,
                  acceptDocumentReady(documentToken) else {
                return
            }
            return
        }
        if body["event"] as? String == "manualScroll",
           body["version"] as? Int == ChatGPTResponsePayload.currentVersion,
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
            let event = ChatGPTTrustedInteractionEvent(
                kind: .manualScroll,
                documentToken: documentToken,
                responseIdentity: responseIdentity,
                responseComplete: responseComplete,
                latestResponseIdentity: responseIdentity,
                latestResponseComplete: responseComplete,
                responseRootCount: body["responseRootCount"] as? Int ?? 0,
                bridgeInstanceID: bridgeInstanceID
            )
            onManualScroll(slotID, documentToken)
            onTrustedInteractionEvent?(slotID, event)
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
            return
        }

        guard let payload = ChatGPTResponsePayload.parse(body),
              let pending = pendingRequests.removeValue(forKey: payload.requestID),
              pending.webViewIdentity == ObjectIdentifier(attachedWebView) else {
            return
        }
        guard payload.documentToken == currentDocumentToken else {
            pending.completion(nil)
            return
        }
        pending.completion(
            payload.kind == .response ? payload.assigning(slotID: slotID) : nil
        )
    }

    @discardableResult
    private func acceptDocumentReady(_ documentToken: String) -> Bool {
        guard ChatGPTResponsePayload.isOpaqueIdentifier(documentToken) else {
            return false
        }
        currentDocumentToken = documentToken
        recordBridgeDiagnostic(
            event: "bridge.document_ready",
            documentToken: documentToken
        )
        return true
    }

    private func recordBridgeDiagnostic(
        event: String,
        documentToken: String? = nil,
        fields: [String: RuntimeDiagnosticValue] = [:]
    ) {
        var enriched = fields
        enriched["slot_id"] = .string(slotID.uuidString)
        enriched["bridge_instance_id"] = .string(bridgeInstanceID.uuidString)
        enriched["document_token_tag"] = diagnosticContext.documentTokenTag(documentToken)
        diagnostics.record(
            event: "unread.\(event)",
            level: .info,
            subsystem: "unread",
            fields: diagnosticContext.fields(enriched)
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

    private static let snapshotLatestResponseStatusScript =
        "globalThis.__floatTabsChatGPTResponseIdentitySnapshotV1?.()"

    static func parseResponseStatusSnapshot(_ value: Any) -> ChatGPTResponseStatusSnapshot? {
        guard let body = value as? [String: Any],
              body["version"] as? Int == 1,
              let documentToken = body["documentToken"] as? String,
              ChatGPTResponsePayload.isOpaqueIdentifier(documentToken),
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
            generating: generating,
            responseRootCount: body["responseRootCount"] as? Int ?? 0,
            responseComplete: body["responseComplete"] as? Bool
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
                continuation.resume(
                    returning: parseResponseStatusSnapshot(value)
                )
            }
        }
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
