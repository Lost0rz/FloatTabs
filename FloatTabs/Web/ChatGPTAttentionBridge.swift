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
    /// The current document URL is navigation metadata used only to correlate
    /// a transient Instant Back baseline with the confirmed history target.
    /// It is not persisted or used as Attention state.
    let documentURL: URL?

    init(
        version: Int,
        kind: String,
        token: String,
        generating: Bool,
        documentURL: URL? = nil
    ) {
        self.version = version
        self.kind = kind
        self.token = token
        self.generating = generating
        self.documentURL = documentURL
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
        let documentURL = (body["documentURL"] as? String).flatMap(URL.init(string:))
        return ChatGPTBridgePayload(
            version: version,
            kind: kind,
            token: token,
            generating: generating,
            documentURL: documentURL
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
        guard hasBaseline else {
            hasBaseline = true
            isGenerating = generating
            return generating ? .generationStarted : nil
        }
        guard generating != isGenerating else { return nil }
        isGenerating = generating
        return generating ? .generationStarted : .generationFinished
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

          const STOP_SELECTORS = [
            '[data-testid="stop-button"]',
            '[data-testid="fruitjuice-stop-button"]'
          ];
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
            target.postMessage({
              version: 1,
              kind: lastSent === null ? "baseline" : "state",
              token: TOKEN,
              documentURL: location.href,
              generating: generating
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

          // Every element matching an exact selector is inspected: a hidden
          // or stale first match must never mask a later legitimate control.
          const isGenerating = () => {
            for (const selector of STOP_SELECTORS) {
              const elements = document.querySelectorAll(selector);
              for (const element of elements) {
                if (isRendered(element)) { return true; }
              }
            }
            return false;
          };

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

          // BFCache/history restoration does not rerun document-start injection.
          // A restored document re-reports its current state so the native side
          // can re-establish a baseline from the still-current token.
          window.addEventListener("pageshow", () => {
            lastSent = null;
            schedule();
          });
        })();
        """
    }

    private struct DocumentSession {
        let token: String
        var tracker = ChatGPTDocumentGenerationTracker()
    }

    /// A single in-flight Instant Back transition may briefly deliver the
    /// restored document's baseline before native history confirmation. The
    /// candidate is deliberately not an Attention state or document history;
    /// it is only a deferred baseline payload for this one handoff.
    private struct PendingInstantBackHandoff {
        var candidate: ChatGPTBridgePayload?
    }

    let slotID: UUID
    private let onObservation: @MainActor (UUID, ChatGPTAttentionObservation) -> Void
    private weak var webView: WKWebView?
    private weak var userContentController: WKUserContentController?
    private var document: DocumentSession?
    /// True until a document's own `baseline` report is accepted — including
    /// from bridge creation, so the very first load can establish its epoch.
    private var isAwaitingNewDocumentBaseline = true
    private var pendingInstantBackHandoff: PendingInstantBackHandoff?
    private var pendingInstantBackTargetURL: URL?
    private(set) var isInvalidated = false

    /// Whether a transient Instant Back baseline handoff is awaiting either
    /// cancellation or authoritative current-history confirmation.
    var isInstantBackHandoffPending: Bool {
        pendingInstantBackHandoff != nil
    }

    init(
        slotID: UUID,
        onObservation: @escaping @MainActor (UUID, ChatGPTAttentionObservation) -> Void
    ) {
        self.slotID = slotID
        self.onObservation = onObservation
        super.init()
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

        if pendingInstantBackHandoff != nil {
            // During the handoff, only a new document's own baseline may be
            // a candidate. Existing-document state messages, including late
            // messages from the document that is leaving, are ignored until
            // the navigation boundary is confirmed or cancelled.
            guard payload.kind == ChatGPTBridgePayload.baselineKind,
                  document?.token != payload.token,
                  instantBackCandidateMatchesTarget(payload) else {
                return
            }
            pendingInstantBackHandoff?.candidate = payload
            return
        }

        if isAwaitingNewDocumentBaseline {
            // Only a document's own baseline report may open an epoch: the
            // document-start script's first message and a pageshow re-report
            // both carry the baseline kind, while a late `state` message from
            // a superseded document must never re-baseline.
            guard payload.kind == ChatGPTBridgePayload.baselineKind else { return }
            document = DocumentSession(token: payload.token)
            isAwaitingNewDocumentBaseline = false
        } else if document?.token != payload.token {
            return
        }
        guard let observation = document?.tracker.observe(payload.generating) else {
            return
        }
        emit(observation)
    }

    // MARK: Navigation / runtime lifecycle

    /// Begins the one bounded bridge handoff for a WebKit Instant Back
    /// request. The request itself is not authority: until the navigation
    /// observer confirms the requested current history item, a new baseline is
    /// held without mutating the Attention observation stream.
    func beginInstantBackHandoff(targetURL: URL? = nil) {
        guard !isInvalidated else {
            pendingInstantBackHandoff = nil
            pendingInstantBackTargetURL = nil
            return
        }
        if let targetURL,
           !ChatGPTSitePolicy.isSupportedChatGPTURL(targetURL) {
            pendingInstantBackHandoff = nil
            pendingInstantBackTargetURL = nil
            return
        }
        pendingInstantBackHandoff = PendingInstantBackHandoff()
        pendingInstantBackTargetURL = targetURL
    }

    /// Cancels a pending handoff when Instant Back falls back to ordinary
    /// loading, fails, or another navigation supersedes it. The old document
    /// epoch remains untouched until the ordinary didCommit boundary.
    func cancelInstantBackHandoff() {
        pendingInstantBackHandoff = nil
        pendingInstantBackTargetURL = nil
    }

    /// Confirms the handoff only after SlotNavigationObserver has established
    /// that the requested WKBackForwardList item is the current item. Reset the
    /// old runtime first, then replay the one held baseline (if any) as a fresh
    /// current-document epoch.
    func confirmInstantBackHandoff() {
        guard let handoff = pendingInstantBackHandoff else { return }
        pendingInstantBackHandoff = nil
        pendingInstantBackTargetURL = nil
        handleRuntimeReplacement()

        guard let candidate = handoff.candidate else { return }
        acceptFreshBaseline(candidate)
    }

    /// The runtime was authoritatively replaced — a new top-level document
    /// committed or the WebContent process terminated. Forward one reset
    /// boundary for the old runtime, clear the accepted document epoch, and
    /// wait for the new document's baseline. The installation itself stays
    /// usable for the recovered/replacement document.
    func handleRuntimeReplacement() {
        pendingInstantBackHandoff = nil
        pendingInstantBackTargetURL = nil
        let hadActiveDocument = document != nil
        document = nil
        isAwaitingNewDocumentBaseline = true
        if hadActiveDocument {
            emit(.runtimeReset)
        }
    }

    /// Permanently detaches the bridge from its WKWebView. Removes only this
    /// bridge's own message handler — Factory scripts and any unrelated user
    /// scripts stay untouched — drops the document epoch, and rejects every
    /// later callback. Forwards one reset boundary if a document was active.
    func invalidate() {
        guard !isInvalidated else { return }
        isInvalidated = true
        pendingInstantBackHandoff = nil
        pendingInstantBackTargetURL = nil
        let hadActiveDocument = document != nil
        document = nil
        isAwaitingNewDocumentBaseline = false
        userContentController?.removeScriptMessageHandler(
            forName: Self.messageHandlerName,
            contentWorld: Self.contentWorld
        )
        userContentController = nil
        webView = nil
        if hadActiveDocument {
            emit(.runtimeReset)
        }
    }

    private func emit(_ observation: ChatGPTAttentionObservation) {
        onObservation(slotID, observation)
    }

    private func acceptFreshBaseline(_ payload: ChatGPTBridgePayload) {
        guard payload.kind == ChatGPTBridgePayload.baselineKind else { return }
        document = DocumentSession(token: payload.token)
        isAwaitingNewDocumentBaseline = false
        if let observation = document?.tracker.observe(payload.generating) {
            emit(observation)
        }
    }

    private func instantBackCandidateMatchesTarget(
        _ payload: ChatGPTBridgePayload
    ) -> Bool {
        guard let targetURL = pendingInstantBackTargetURL else { return true }
        guard let documentURL = payload.documentURL else { return false }
        return documentURL.absoluteString == targetURL.absoluteString
    }
}
