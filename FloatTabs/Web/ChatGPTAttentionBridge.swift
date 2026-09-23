import Foundation
import WebKit

/// The one shared ChatGPT host-family predicate. `SiteCompatibilityPolicy`
/// (rendering) and attention observation validation both route through this
/// type so the two host lists can never drift.
enum ChatGPTSitePolicy {
    static let chatGPTHost = "chatgpt.com"
    static let legacyChatHost = "chat.openai.com"

    static func isSupportedHost(_ host: String) -> Bool {
        let normalized = host.lowercased()
        return normalized == chatGPTHost
            || normalized.hasSuffix(".\(chatGPTHost)")
            || normalized == legacyChatHost
    }

    static func isSupportedChatGPTURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = url.host else {
            return false
        }
        return isSupportedHost(host)
    }
}

/// Normalized bridge observations. These are sensor facts about the current
/// ChatGPT document, not attention state: `WebAttentionCoordinator` stays the
/// sole authority and is not connected to the bridge until Stage C.
enum ChatGPTAttentionObservation: Equatable, Sendable {
    case generationStarted
    case generationFinished
    case runtimeReset
}

struct ChatGPTAttentionEvent: Equatable, Sendable {
    let observation: ChatGPTAttentionObservation
    let responseIdentity: ChatGPTResponseIdentity?
    let responseRootCount: Int?
    let latestResponseComplete: Bool?
    let completionProducer: UnreadRuntimeDiagnosticCompletionProducer
    let generationEpoch: UInt64?
    let documentToken: String?
    let bridgeInstanceID: UUID?

    init(
        observation: ChatGPTAttentionObservation,
        responseIdentity: ChatGPTResponseIdentity?,
        responseRootCount: Int? = nil,
        latestResponseComplete: Bool? = nil,
        completionProducer: UnreadRuntimeDiagnosticCompletionProducer = .unknown,
        generationEpoch: UInt64? = nil,
        documentToken: String? = nil,
        bridgeInstanceID: UUID? = nil
    ) {
        self.observation = observation
        self.responseIdentity = responseIdentity
        self.responseRootCount = responseRootCount
        self.latestResponseComplete = latestResponseComplete
        self.completionProducer = completionProducer
        self.generationEpoch = generationEpoch
        self.documentToken = documentToken
        self.bridgeInstanceID = bridgeInstanceID
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.observation == rhs.observation
            && lhs.responseIdentity == rhs.responseIdentity
    }
}

/// Minimal bridge payload. Metadata only: prompt text, response text, and any
/// other page content must never appear in this protocol.
struct ChatGPTBridgePayload: Equatable {
    static let currentVersion = 1
    static let baselineKind = "baseline"
    static let stateKind = "state"

    private static let tokenLengthRange = 8...128

    let version: Int
    let kind: String
    /// Opaque per-document identity created by the injected script. Carries no
    /// page content.
    let token: String
    let generating: Bool
    let responseIdentity: ChatGPTResponseIdentity?
    let responseRootCount: Int?
    let latestResponseComplete: Bool?
    let producer: UnreadRuntimeDiagnosticCompletionProducer

    init(
        version: Int,
        kind: String,
        token: String,
        generating: Bool,
        responseIdentity: ChatGPTResponseIdentity? = nil,
        responseRootCount: Int? = nil,
        latestResponseComplete: Bool? = nil,
        producer: UnreadRuntimeDiagnosticCompletionProducer = .unknown
    ) {
        self.version = version
        self.kind = kind
        self.token = token
        self.generating = generating
        self.responseIdentity = responseIdentity
        self.responseRootCount = responseRootCount
        self.latestResponseComplete = latestResponseComplete
        self.producer = producer
    }

    static func parse(_ body: [String: Any]) -> ChatGPTBridgePayload? {
        guard let version = body["version"] as? Int,
              version == currentVersion,
              let kind = body["kind"] as? String,
              kind == baselineKind || kind == stateKind,
              let token = body["token"] as? String,
              tokenLengthRange.contains(token.count),
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
        let responseRootCount: Int?
        if let rawRootCount = body["responseRootCount"] {
            guard let parsedRootCount = rawRootCount as? Int,
                  parsedRootCount >= 0 else {
                return nil
            }
            responseRootCount = parsedRootCount
        } else {
            responseRootCount = nil
        }
        let latestResponseComplete = body["latestResponseComplete"] as? Bool
        let producer: UnreadRuntimeDiagnosticCompletionProducer
        if let rawProducer = body["producer"] as? String {
            producer = UnreadRuntimeDiagnosticCompletionProducer(rawValue: rawProducer) ?? .unknown
        } else {
            producer = .unknown
        }
        return ChatGPTBridgePayload(
            version: version,
            kind: kind,
            token: token,
            generating: generating,
            responseIdentity: responseIdentity,
            responseRootCount: responseRootCount,
            latestResponseComplete: latestResponseComplete,
            producer: producer
        )
    }
}

/// Pure per-document baseline/transition reducer. The first observation for a
/// document establishes its baseline — an idle baseline can never synthesize a
/// finish — and duplicate states never re-emit, so noisy injected JS cannot
/// produce duplicate native observations even before the native-side checks.
struct ChatGPTDocumentGenerationTracker {
    private var hasBaseline = false
    private var isGenerating = false

    mutating func observe(_ generating: Bool) -> ChatGPTAttentionObservation? {
        observeEvent(generating, responseIdentity: nil)?.observation
    }

    mutating func observeEvent(
        _ generating: Bool,
        responseIdentity: ChatGPTResponseIdentity?,
        responseRootCount: Int? = nil,
        latestResponseComplete: Bool? = nil,
        producer: UnreadRuntimeDiagnosticCompletionProducer = .unknown
    ) -> ChatGPTAttentionEvent? {
        guard hasBaseline else {
            hasBaseline = true
            isGenerating = generating
            return generating
                ? ChatGPTAttentionEvent(
                    observation: .generationStarted,
                    responseIdentity: nil,
                    responseRootCount: responseRootCount,
                    latestResponseComplete: latestResponseComplete,
                    completionProducer: producer
                )
                : nil
        }
        guard generating != isGenerating else { return nil }
        isGenerating = generating
        return ChatGPTAttentionEvent(
            observation: generating ? .generationStarted : .generationFinished,
            responseIdentity: generating ? nil : responseIdentity,
            responseRootCount: responseRootCount,
            latestResponseComplete: latestResponseComplete,
            completionProducer: producer
        )
    }
}

/// Per-WKWebView ChatGPT generation sensor.
///
/// The bridge owns no business state. It validates incoming script messages,
/// reduces them to the document's generation baseline/transitions, and forwards
/// normalized observations only. Its lifetime follows the WKWebView it was
/// installed on: `WebViewPool` creates it before the WKWebView exists, the
/// Factory invokes `install(into:)` on the pre-creation user content
/// controller, and invalidation removes only this bridge's own message
/// handler so Factory scripts stay intact.
@MainActor
final class ChatGPTAttentionBridge: NSObject, WKScriptMessageHandler {
    static let contentWorldName = "FloatTabsChatGPTAttention"
    static let messageHandlerName = "floatTabsChatGPTAttention"
    static let livenessWatchdogIntervalNanoseconds: UInt64 = 2_000_000_000
    static let livenessConfirmationDelayNanoseconds: UInt64 = 250_000_000
    static let livenessProbeScript = "globalThis.__floatTabsAttentionProbeV1?.()"

    typealias LivenessProbeProvider = @MainActor (WKWebView) async -> Any?
    typealias LivenessSleeper = @MainActor (UInt64) async -> Bool

    private static let productionLivenessSleeper: LivenessSleeper = { nanoseconds in
        guard !Task.isCancelled else { return false }
        do {
            try await Task.sleep(nanoseconds: nanoseconds)
            return !Task.isCancelled
        } catch {
            return false
        }
    }

    private static let productionLivenessProbe: LivenessProbeProvider = { webView in
        await withCheckedContinuation { continuation in
            webView.evaluateJavaScript(
                ChatGPTAttentionBridge.livenessProbeScript,
                in: nil,
                in: ChatGPTAttentionBridge.contentWorld
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

    /// The single shared world instance used for both the injected script and
    /// the message handler. One instance is required: worlds with equal names
    /// are still distinct objects.
    static let contentWorld = WKContentWorld.world(name: contentWorldName)

    /// Test/diagnostic seam: the exact script injected into supported
    /// documents, generated by `makeScriptSource()` from Swift-owned
    /// constants.
    static let scriptSource = makeScriptSource()

    /// The injected script's early host gate, generated from the same
    /// `ChatGPTSitePolicy` constants used by native message validation and
    /// `SiteCompatibilityPolicy`. The script must never carry an
    /// independently maintained host list.
    static func hostGateExpression() -> String {
        let mainHost = ChatGPTSitePolicy.chatGPTHost
        return "host === \"\(mainHost)\""
            + " || host.endsWith(\".\(mainHost)\")"
            + " || host === \"\(ChatGPTSitePolicy.legacyChatHost)\""
    }

    private static func makeScriptSource() -> String {
        let hostGate = hostGateExpression()
        return """
        (() => {
          "use strict";
          if (window.top !== window) { return; }
          const supportedHost = (host) => \(hostGate);
          if (!supportedHost(location.hostname)) { return; }
          const handler = () => {
            try {
              return window.webkit &&
                window.webkit.messageHandlers &&
                window.webkit.messageHandlers["floatTabsChatGPTAttention"];
            } catch (_) {
              return undefined;
            }
          };
          if (!handler()) { return; }

          const COALESCE_MS = 250;
          const TOKEN = (window.crypto && crypto.randomUUID)
            ? crypto.randomUUID()
            : "tok-" + Date.now().toString(36) + "-" +
              Math.random().toString(36).slice(2, 10);

          let lastSent = null;
          let timer = null;
          let lastCheck = 0;
          let observer = null;

          const post = (generating) => {
            const target = handler();
            if (!target) { return; }
            const latestRoot = latestAssistantResponseRoot();
            target.postMessage({
              version: 1,
              kind: lastSent === null ? "baseline" : "state",
              token: TOKEN,
              generating: generating,
              responseIdentity: generating
                ? null
                : canonicalResponseIdentityFor(latestRoot),
              responseRootCount: assistantResponseRoots().length,
              latestResponseComplete: Boolean(latestRoot) && !generating,
              producer: "mutation_observer"
            });
          };

          // A control counts only while it is actually presented: connected,
          // laying out at least one client rect, and not hidden through the
          // computed box model. Opacity and transforms are deliberately not
          // consulted — transient animations must not create false negatives.
          const isRendered = (element) => {
            if (!element.isConnected) { return false; }
            if (element.getClientRects().length === 0) { return false; }
            const style = window.getComputedStyle(element);
            if (style.display === "none") { return false; }
            const visibility = style.visibility;
            if (visibility === "hidden" || visibility === "collapse") {
              return false;
            }
            return true;
          };

          \(ChatGPTResponseIdentity.sharedDOMHelperSource)

          const evaluate = () => {
            const generating = isGenerating();
            if (generating === lastSent) { return; }
            post(generating);
            lastSent = generating;
          };

          // Trailing coalescing: a burst of DOM mutations collapses into at most
          // one state read per window, while a sustained mutation stream (streamed
          // tokens) still gets periodic reads instead of postponing forever.
          const schedule = () => {
            if (timer !== null) { return; }
            const wait = Math.max(0, COALESCE_MS - (Date.now() - lastCheck));
            timer = setTimeout(() => {
              timer = null;
              lastCheck = Date.now();
              evaluate();
            }, wait);
          };

          const startObserving = () => {
            if (observer || !document.documentElement) { return; }
            observer = new MutationObserver(schedule);
            // Render-state transitions can arrive through attributes alone —
            // a control hidden or revealed by class/style/hidden mutations
            // without any node insertion or removal must still re-evaluate.
            // characterData is intentionally excluded: token streaming must
            // not add observation pressure.
            observer.observe(document.documentElement, {
              childList: true,
              subtree: true,
              attributes: true,
              attributeFilter: [
                "data-testid",
                "class",
                "style",
                "hidden",
                "aria-hidden"
              ]
            });
          };

          if (document.documentElement) {
            startObserving();
          } else {
            const boot = new MutationObserver(() => {
              if (document.documentElement) {
                boot.disconnect();
                startObserving();
              }
            });
            boot.observe(document, { childList: true });
          }

          document.addEventListener("DOMContentLoaded", schedule, { once: true });

          globalThis.__floatTabsAttentionProbeV1 = () => {
            const generating = isGenerating();
            return {
              version: 1,
              kind: "baseline",
              token: TOKEN,
              generating: generating,
              responseIdentity: canonicalResponseIdentityFor(
                latestAssistantResponseRoot()
              ),
              responseRootCount: assistantResponseRoots().length,
              latestResponseComplete: Boolean(latestAssistantResponseRoot()) && !generating,
              producer: "liveness_probe"
            };
          };

          // BFCache/history restoration does not rerun document-start injection.
          // A restored document re-reports its current state; the native side
          // also exposes a narrow same-world resync entry for the confirmed
          // current history item.
          window.addEventListener("pageshow", () => {
            lastSent = null;
            schedule();
          });

          globalThis.__floatTabsAttentionResyncV1 = () => {
            const generating = isGenerating();
            // The explicit resync returns the identity-bearing baseline to
            // native code directly. Keep the detector coalescer aligned so a
            // queued pageshow/mutation evaluation cannot create duplicate
            // native traffic for this same state.
            lastSent = generating;
            return {
              version: 1,
              kind: "baseline",
              token: TOKEN,
              generating: generating,
              responseIdentity: canonicalResponseIdentityFor(
                latestAssistantResponseRoot()
              ),
              responseRootCount: assistantResponseRoots().length,
              latestResponseComplete: Boolean(latestAssistantResponseRoot()) && !generating,
              producer: "resync"
            };
          };
        })();
        """
    }

    private struct DocumentSession {
        let token: String
        let epoch: UInt64
        var tracker = ChatGPTDocumentGenerationTracker()
    }

    private enum DocumentAdmission {
        case awaitingSupportedBaseline
        case activeSupportedDocument
        case unsupportedCurrentDocument
        case awaitingAuthorizedResync
    }

    /// A single in-flight Instant Back transition carries only the target's
    /// support classification and whether it should receive a fresh
    /// current-document resync. Attention state and document history never
    /// enter this marker.
    private struct PendingInstantBackHandoff {
        let shouldResyncCurrentDocument: Bool
        let targetIsKnownUnsupported: Bool
    }

    private struct PendingCurrentDocumentResync {
        let generation: UInt64
        let attempt: Int
        let webViewIdentity: ObjectIdentifier
    }

    private static let resyncAttemptLimit = 2

    let slotID: UUID
    let bridgeInstanceID: UUID
    private let onObservation: @MainActor (UUID, ChatGPTAttentionObservation) -> Void
    private let onAttentionEvent: (@MainActor (UUID, ChatGPTAttentionEvent) -> Void)?
    private let diagnostics: any RuntimeDiagnosticRecording
    private let diagnosticContext: UnreadRuntimeDiagnosticContext
    private let livenessProbe: LivenessProbeProvider
    private let livenessSleeper: LivenessSleeper
    private weak var webView: WKWebView?
    private weak var userContentController: WKUserContentController?
    private var document: DocumentSession?
    /// The one runtime-only admission state. The current committed document,
    /// not a requested/provisional/persisted URL, controls whether a ChatGPT
    /// epoch may exist.
    private var documentAdmission = DocumentAdmission.awaitingSupportedBaseline
    private var pendingInstantBackHandoff: PendingInstantBackHandoff?
    private var pendingCurrentDocumentResync: PendingCurrentDocumentResync?
    private var nextResyncGeneration: UInt64 = 0
    private var nextDocumentEpoch: UInt64 = 0
    private var livenessWatchdogTask: Task<Void, Never>?
    private var livenessWatchdogGeneration: UInt64 = 0
    private var livenessGeneration: UInt64 = 0
    private var livenessCycleOwnerGeneration: UInt64?
    private var livenessIdleCandidateOwnerGeneration: UInt64?
    private var nextGenerationEpoch: UInt64 = 0
    private var currentGenerationEpoch: UInt64?
#if DEBUG
    private(set) var debugLivenessWatchdogStartCount = 0
#endif
    private(set) var isInvalidated = false

    /// Whether a transient Instant Back baseline handoff is awaiting either
    /// cancellation or authoritative current-history confirmation.
    var isInstantBackHandoffPending: Bool {
        pendingInstantBackHandoff != nil
    }

    init(
        slotID: UUID,
        onObservation: @escaping @MainActor (UUID, ChatGPTAttentionObservation) -> Void,
        diagnostics: any RuntimeDiagnosticRecording = RuntimeDiagnosticNoopRecorder(),
        livenessProbe: LivenessProbeProvider? = nil,
        livenessSleeper: LivenessSleeper? = nil,
        onAttentionEvent: (@MainActor (UUID, ChatGPTAttentionEvent) -> Void)? = nil,
        bridgeInstanceID: UUID = UUID(),
        diagnosticContext: UnreadRuntimeDiagnosticContext = .shared
    ) {
        self.slotID = slotID
        self.bridgeInstanceID = bridgeInstanceID
        self.onObservation = onObservation
        self.onAttentionEvent = onAttentionEvent
        self.diagnostics = diagnostics
        self.diagnosticContext = diagnosticContext
        self.livenessProbe = livenessProbe ?? Self.productionLivenessProbe
        self.livenessSleeper = livenessSleeper ?? Self.productionLivenessSleeper
        super.init()
        recordBridgeDiagnostic(event: "bridge.created")
    }

    // MARK: Installation

    /// Adds the document-start main-frame script and the same-world message
    /// handler. Must run on the Factory-owned `WKUserContentController` before
    /// the WKWebView is constructed so `.atDocumentStart` is reliable for the
    /// first load.
    func install(into userContentController: WKUserContentController) {
        guard !isInvalidated else { return }
        userContentController.addUserScript(
            WKUserScript(
                source: Self.scriptSource,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true,
                in: Self.contentWorld
            )
        )
        userContentController.add(
            self,
            contentWorld: Self.contentWorld,
            name: Self.messageHandlerName
        )
        self.userContentController = userContentController
    }

    func attach(to webView: WKWebView) {
        guard !isInvalidated else { return }
        if let previousWebView = self.webView,
           previousWebView !== webView {
            handleRuntimeReplacement()
        }
        self.webView = webView
    }

    // MARK: WKScriptMessageHandler

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let body = message.body as? [String: Any],
              let payload = ChatGPTBridgePayload.parse(body) else {
            return
        }
        accept(
            payload: payload,
            messageWebView: message.webView,
            isMainFrame: message.frameInfo.isMainFrame,
            originHost: message.frameInfo.securityOrigin.host,
            originProtocol: message.frameInfo.securityOrigin.`protocol`
        )
    }

    /// Validation pipeline and acceptance, split from the message-handler
    /// entry point so tests exercise the exact production semantics. Every
    /// check below must pass independently; origin comes from the message's
    /// own security origin, never from `webView.url`, because stale
    /// old-document messages race navigation.
    func accept(
        payload: ChatGPTBridgePayload,
        messageWebView: WKWebView?,
        isMainFrame: Bool,
        originHost: String?,
        originProtocol: String?
    ) {
        guard !isInvalidated,
              let attachedWebView = webView,
              messageWebView === attachedWebView,
              isMainFrame,
              let host = originHost?.lowercased(), !host.isEmpty,
              let protocolScheme = originProtocol?.lowercased(),
              protocolScheme == "https" || protocolScheme == "http",
              ChatGPTSitePolicy.isSupportedHost(host) else {
            return
        }

        switch documentAdmission {
        case .unsupportedCurrentDocument, .awaitingAuthorizedResync:
            // After a confirmed current-document boundary, only the direct
            // result from the actual current WebView may open the fresh epoch.
            // Unsupported documents stay closed until a later supported commit.
            // Natural or stale script messages are silent in both states.
            return
        case .awaitingSupportedBaseline, .activeSupportedDocument:
            break
        }

        if pendingInstantBackHandoff != nil {
            // The current accepted document remains authoritative until the
            // history item is confirmed. Its normal state stream must not be
            // frozen or buffered; a different-token baseline is rejected until
            // confirmation and the explicit current-document resync.
            guard document?.token == payload.token else {
                return
            }
            observeGeneration(
                payload.generating,
                responseIdentity: payload.responseIdentity,
                responseRootCount: payload.responseRootCount,
                latestResponseComplete: payload.latestResponseComplete,
                producer: payload.producer
            )
            return
        }

        switch documentAdmission {
        case .awaitingSupportedBaseline:
            // This path is reserved for boundaries that cannot identify a
            // committed document (initial/test seams and runtime recovery).
            // Ordinary supported didCommit uses authorized current-document
            // resync instead, so a stale baseline cannot claim the new epoch.
            guard payload.kind == ChatGPTBridgePayload.baselineKind else { return }
            document = makeDocumentSession(token: payload.token)
            documentAdmission = .activeSupportedDocument
        case .activeSupportedDocument:
            guard document?.token == payload.token else { return }
        case .unsupportedCurrentDocument, .awaitingAuthorizedResync:
            return
        }
        observeGeneration(
            payload.generating,
            responseIdentity: payload.responseIdentity,
            responseRootCount: payload.responseRootCount,
            latestResponseComplete: payload.latestResponseComplete,
            producer: payload.producer
        )
    }

    private func makeDocumentSession(token: String) -> DocumentSession {
        nextDocumentEpoch &+= 1
        recordBridgeDiagnostic(
            event: "bridge.document_ready",
            documentToken: token,
            fields: [
                "document_epoch": .integer(Int64(nextDocumentEpoch))
            ]
        )
        return DocumentSession(token: token, epoch: nextDocumentEpoch)
    }

    // MARK: Navigation / runtime lifecycle

    /// Begins the one bounded bridge handoff for a WebKit Instant Back
    /// request. The request itself is not authority: until the navigation
    /// observer confirms the requested current history item, the old accepted
    /// document remains the only Attention epoch.
    func beginInstantBackHandoff(targetURL: URL? = nil) {
        guard !isInvalidated else {
            pendingInstantBackHandoff = nil
            return
        }
        pendingInstantBackHandoff = PendingInstantBackHandoff(
            shouldResyncCurrentDocument: targetURL.map {
                ChatGPTSitePolicy.isSupportedChatGPTURL($0)
            } ?? false,
            targetIsKnownUnsupported: targetURL.map {
                !ChatGPTSitePolicy.isSupportedChatGPTURL($0)
            } ?? false
        )
    }

    /// Cancels a pending handoff when Instant Back falls back to ordinary
    /// loading, fails, or another navigation supersedes it. The old document
    /// epoch remains untouched until the ordinary didCommit boundary.
    func cancelInstantBackHandoff() {
        pendingInstantBackHandoff = nil
    }

    /// Confirms the handoff only after SlotNavigationObserver has established
    /// that the requested WKBackForwardList item is the current item. Reset the
    /// old runtime first, then ask the actual current document to emit a fresh
    /// baseline when the confirmed target supports ChatGPT attention.
    func confirmInstantBackHandoff() {
        guard let handoff = pendingInstantBackHandoff else { return }
        pendingInstantBackHandoff = nil
        handleRuntimeReplacement()

        if handoff.targetIsKnownUnsupported {
            documentAdmission = .unsupportedCurrentDocument
            return
        }

        guard handoff.shouldResyncCurrentDocument else { return }
        requestCurrentDocumentResync()
    }

    /// The runtime was authoritatively replaced without a committed URL — for
    /// example, the WebContent process terminated. Forward one reset boundary,
    /// clear the old document epoch, and wait for the recovered document's
    /// natural baseline. Ordinary didCommit uses the URL-aware overload below.
    func handleRuntimeReplacement() {
        resetRuntime(admission: .awaitingSupportedBaseline)
    }

    /// The ordinary didCommit boundary supplies the actual committed/current
    /// WebKit URL before any presentation callback or persisted URL can be
    /// consulted. A supported commit closes natural baseline admission first,
    /// then asks the actual current WKWebView for its token-bearing baseline;
    /// this prevents an in-flight same-origin baseline from the replaced
    /// document from claiming the new epoch. A nil URL remains an unknown/test
    /// seam and therefore preserves natural-baseline recovery semantics.
    func handleRuntimeReplacement(committedURL: URL?) {
        guard let committedURL else {
            resetRuntime(admission: .awaitingSupportedBaseline)
            return
        }

        guard ChatGPTSitePolicy.isSupportedChatGPTURL(committedURL) else {
            resetRuntime(admission: .unsupportedCurrentDocument)
            return
        }

        resetRuntime(admission: .awaitingAuthorizedResync)
        requestCurrentDocumentResync()
    }

    private func resetRuntime(admission: DocumentAdmission) {
        stopLivenessWatchdog()
        invalidatePendingCurrentDocumentResync()
        pendingInstantBackHandoff = nil
        let hadActiveDocument = document != nil
        if hadActiveDocument {
            recordBridgeDiagnostic(
                event: "bridge.document_changed",
                documentToken: document?.token,
                fields: [
                    "document_epoch": .integer(Int64(document?.epoch ?? 0))
                ]
            )
        }
        document = nil
        documentAdmission = admission
        currentGenerationEpoch = nil
        if hadActiveDocument {
            emit(ChatGPTAttentionEvent(observation: .runtimeReset, responseIdentity: nil))
        }
    }

    /// Permanently detaches the bridge from its WKWebView. Removes only this
    /// bridge's own message handler — Factory scripts and any unrelated user
    /// scripts stay untouched — drops the document epoch, and rejects every
    /// later callback. Forwards one reset boundary if a document was active.
    func invalidate() {
        guard !isInvalidated else { return }
        isInvalidated = true
        stopLivenessWatchdog()
        invalidatePendingCurrentDocumentResync()
        pendingInstantBackHandoff = nil
        let hadActiveDocument = document != nil
        if hadActiveDocument {
            recordBridgeDiagnostic(
                event: "bridge.destroyed",
                documentToken: document?.token,
                fields: [
                    "document_epoch": .integer(Int64(document?.epoch ?? 0))
                ]
            )
        }
        document = nil
        documentAdmission = .unsupportedCurrentDocument
        currentGenerationEpoch = nil
        userContentController?.removeScriptMessageHandler(
            forName: Self.messageHandlerName,
            contentWorld: Self.contentWorld
        )
        userContentController = nil
        webView = nil
        if hadActiveDocument {
            emit(ChatGPTAttentionEvent(observation: .runtimeReset, responseIdentity: nil))
        }
    }

    private func observeGeneration(
        _ generating: Bool,
        responseIdentity: ChatGPTResponseIdentity? = nil,
        responseRootCount: Int? = nil,
        latestResponseComplete: Bool? = nil,
        producer: UnreadRuntimeDiagnosticCompletionProducer = .unknown
    ) -> ChatGPTAttentionObservation? {
        guard let event = document?.tracker.observeEvent(
            generating,
            responseIdentity: responseIdentity,
            responseRootCount: responseRootCount,
            latestResponseComplete: latestResponseComplete,
            producer: producer
        ) else { return nil }
        emit(event)
        return event.observation
    }

    private func emit(_ event: ChatGPTAttentionEvent) {
        let observation = event.observation
        var diagnosticEvent = event
        switch observation {
        case .generationStarted:
            nextGenerationEpoch &+= 1
            currentGenerationEpoch = nextGenerationEpoch
            livenessGeneration &+= 1
            startLivenessWatchdog()
        case .generationFinished, .runtimeReset:
            stopLivenessWatchdog()
        }
        diagnosticEvent = ChatGPTAttentionEvent(
            observation: event.observation,
            responseIdentity: event.responseIdentity,
            responseRootCount: event.responseRootCount,
            latestResponseComplete: event.latestResponseComplete,
            completionProducer: event.completionProducer,
            generationEpoch: currentGenerationEpoch,
            documentToken: document?.token,
            bridgeInstanceID: bridgeInstanceID
        )
        if observation == .runtimeReset {
            currentGenerationEpoch = nil
        }
        if let onAttentionEvent {
            onAttentionEvent(slotID, diagnosticEvent)
        } else {
            onObservation(slotID, observation)
        }
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
            event: event,
            level: .info,
            subsystem: "unread",
            fields: diagnosticContext.fields(enriched)
        )
    }

    private func startLivenessWatchdog() {
        guard !isInvalidated, livenessWatchdogTask == nil, documentAdmission == .activeSupportedDocument, let document, let webView else { return }
        livenessWatchdogGeneration &+= 1
        let watchdogGeneration = livenessWatchdogGeneration
        let documentEpoch = document.epoch
        let token = document.token
        let webViewIdentity = ObjectIdentifier(webView)
#if DEBUG
        debugLivenessWatchdogStartCount += 1
#endif
        diagnostics.record(event: "attention.liveness_watchdog.started", level: .info, subsystem: "attention", fields: [
            "slot_id": .string(slotID.uuidString),
            "watchdog_interval_ms": .integer(2_000)
        ])
        livenessWatchdogTask = Task { [weak self, weak webView] in
            guard let self, let webView else { return }
            while !Task.isCancelled {
                guard await self.livenessSleeper(Self.livenessWatchdogIntervalNanoseconds) else { return }
                guard !Task.isCancelled else { return }
                await self.performLivenessCycle(watchdogGeneration: watchdogGeneration, documentEpoch: documentEpoch, webView: webView, webViewIdentity: webViewIdentity, token: token)
            }
        }
    }

    private func stopLivenessWatchdog() {
        let wasActive = livenessWatchdogTask != nil
        let stoppedGeneration = livenessWatchdogGeneration
        if livenessCycleOwnerGeneration == stoppedGeneration {
            livenessCycleOwnerGeneration = nil
        }
        livenessWatchdogGeneration &+= 1
        livenessWatchdogTask?.cancel()
        livenessWatchdogTask = nil
        clearLivenessIdleCandidate(ownedBy: stoppedGeneration)
        if wasActive {
            diagnostics.record(event: "attention.liveness_watchdog.stopped", level: .info, subsystem: "attention", fields: ["slot_id": .string(slotID.uuidString)])
        }
    }

    private func clearLivenessIdleCandidate(ownedBy watchdogGeneration: UInt64) {
        guard livenessIdleCandidateOwnerGeneration == watchdogGeneration else { return }
        livenessIdleCandidateOwnerGeneration = nil
    }

    private func isCurrentLivenessContext(watchdogGeneration: UInt64, documentEpoch: UInt64, webView: WKWebView, webViewIdentity: ObjectIdentifier, token: String) -> Bool {
        guard !isInvalidated, documentAdmission == .activeSupportedDocument, livenessWatchdogTask != nil, livenessWatchdogGeneration == watchdogGeneration, let attachedWebView = self.webView, attachedWebView === webView, ObjectIdentifier(attachedWebView) == webViewIdentity, let document, document.epoch == documentEpoch, document.token == token else { return false }
        return true
    }

    private func parseLivenessProbe(_ value: Any?) -> ChatGPTBridgePayload? {
        guard let body = value as? [String: Any], let payload = ChatGPTBridgePayload.parse(body), payload.kind == ChatGPTBridgePayload.baselineKind else { return nil }
        return payload
    }

    private func recordLivenessProbeFailure() {
        diagnostics.record(event: "attention.liveness_probe.failed", level: .debug, subsystem: "attention", fields: ["slot_id": .string(slotID.uuidString)])
    }

    private func performLivenessCycle(watchdogGeneration: UInt64, documentEpoch: UInt64, webView: WKWebView, webViewIdentity: ObjectIdentifier, token: String) async {
        guard livenessCycleOwnerGeneration == nil, isCurrentLivenessContext(watchdogGeneration: watchdogGeneration, documentEpoch: documentEpoch, webView: webView, webViewIdentity: webViewIdentity, token: token) else { return }
        livenessCycleOwnerGeneration = watchdogGeneration
        defer {
            if livenessCycleOwnerGeneration == watchdogGeneration {
                livenessCycleOwnerGeneration = nil
            }
        }
        let generation = livenessGeneration
        guard let firstValue = await livenessProbe(webView), let firstProbe = parseLivenessProbe(firstValue), isCurrentLivenessContext(watchdogGeneration: watchdogGeneration, documentEpoch: documentEpoch, webView: webView, webViewIdentity: webViewIdentity, token: token), firstProbe.token == token else {
            if isCurrentLivenessContext(watchdogGeneration: watchdogGeneration, documentEpoch: documentEpoch, webView: webView, webViewIdentity: webViewIdentity, token: token) { recordLivenessProbeFailure() }
            return
        }
        if firstProbe.generating {
            clearLivenessIdleCandidate(ownedBy: watchdogGeneration)
            return
        }
        livenessIdleCandidateOwnerGeneration = watchdogGeneration
        guard await livenessSleeper(Self.livenessConfirmationDelayNanoseconds), livenessIdleCandidateOwnerGeneration == watchdogGeneration, livenessGeneration == generation, isCurrentLivenessContext(watchdogGeneration: watchdogGeneration, documentEpoch: documentEpoch, webView: webView, webViewIdentity: webViewIdentity, token: token) else {
            clearLivenessIdleCandidate(ownedBy: watchdogGeneration)
            return
        }
        guard let secondValue = await livenessProbe(webView), let secondProbe = parseLivenessProbe(secondValue), secondProbe.token == token, isCurrentLivenessContext(watchdogGeneration: watchdogGeneration, documentEpoch: documentEpoch, webView: webView, webViewIdentity: webViewIdentity, token: token) else {
            if isCurrentLivenessContext(watchdogGeneration: watchdogGeneration, documentEpoch: documentEpoch, webView: webView, webViewIdentity: webViewIdentity, token: token) { recordLivenessProbeFailure() }
            clearLivenessIdleCandidate(ownedBy: watchdogGeneration)
            return
        }
        guard !secondProbe.generating, livenessGeneration == generation else {
            clearLivenessIdleCandidate(ownedBy: watchdogGeneration)
            return
        }
        clearLivenessIdleCandidate(ownedBy: watchdogGeneration)
        guard observeGeneration(
            false,
            responseIdentity: secondProbe.responseIdentity,
            responseRootCount: secondProbe.responseRootCount,
            latestResponseComplete: secondProbe.latestResponseComplete,
            producer: .livenessProbe
        ) == .generationFinished else { return }
        diagnostics.record(event: "attention.liveness_probe.recovered_completion", level: .info, subsystem: "attention", fields: [
            "slot_id": .string(slotID.uuidString),
            "confirmation_count": .integer(2),
            "watchdog_interval_ms": .integer(2_000),
            "confirmation_delay_ms": .integer(250)
        ])
    }

#if DEBUG
    var debugLivenessWatchdogActive: Bool { livenessWatchdogTask != nil }

    func debugRunLivenessCycle() async {
        guard let document, let webView, livenessWatchdogTask != nil else { return }
        await performLivenessCycle(watchdogGeneration: livenessWatchdogGeneration, documentEpoch: document.epoch, webView: webView, webViewIdentity: ObjectIdentifier(webView), token: document.token)
    }
#endif

    private func requestCurrentDocumentResync() {
        documentAdmission = .awaitingAuthorizedResync
        guard !isInvalidated,
              let webView,
              self.webView === webView else {
            return
        }

        nextResyncGeneration &+= 1
        let generation = nextResyncGeneration
        let pending = PendingCurrentDocumentResync(
            generation: generation,
            attempt: 1,
            webViewIdentity: ObjectIdentifier(webView)
        )
        pendingCurrentDocumentResync = pending
        evaluateCurrentDocumentResync(
            in: webView,
            generation: generation,
            attempt: pending.attempt
        )
    }

    private func evaluateCurrentDocumentResync(
        in webView: WKWebView,
        generation: UInt64,
        attempt: Int
    ) {
        webView.evaluateJavaScript(
            "globalThis.__floatTabsAttentionResyncV1?.()",
            in: nil,
            in: Self.contentWorld
        ) { [weak self, weak webView] (result: Result<Any, Error>) in
            guard let self,
                  let webView,
                  !self.isInvalidated,
                  self.webView === webView,
                  let pending = self.pendingCurrentDocumentResync,
                  pending.generation == generation,
                  pending.attempt == attempt,
                  pending.webViewIdentity == ObjectIdentifier(webView) else {
                return
            }

            if case let .success(value) = result,
               let body = value as? [String: Any],
               let payload = ChatGPTBridgePayload.parse(body),
               payload.kind == ChatGPTBridgePayload.baselineKind {
                self.pendingCurrentDocumentResync = nil
                self.acceptAuthorizedCurrentDocumentBaseline(payload)
                return
            }

            guard attempt < Self.resyncAttemptLimit else {
                // Keep the authorization barrier closed after bounded failure.
                // A later ordinary runtime replacement owns recovery; no
                // arbitrary baseline may reopen this epoch.
                self.pendingCurrentDocumentResync = nil
                return
            }

            let retry = PendingCurrentDocumentResync(
                generation: generation,
                attempt: attempt + 1,
                webViewIdentity: ObjectIdentifier(webView)
            )
            self.pendingCurrentDocumentResync = retry
            self.evaluateCurrentDocumentResync(
                in: webView,
                generation: generation,
                attempt: retry.attempt
            )
        }
    }

    private func acceptAuthorizedCurrentDocumentBaseline(
        _ payload: ChatGPTBridgePayload
    ) {
        guard payload.kind == ChatGPTBridgePayload.baselineKind else { return }
        document = makeDocumentSession(token: payload.token)
        documentAdmission = .activeSupportedDocument
        observeGeneration(
            payload.generating,
            responseIdentity: payload.responseIdentity,
            responseRootCount: payload.responseRootCount,
            latestResponseComplete: payload.latestResponseComplete,
            producer: .resync
        )
    }

    private func invalidatePendingCurrentDocumentResync() {
        nextResyncGeneration &+= 1
        pendingCurrentDocumentResync = nil
    }
}
