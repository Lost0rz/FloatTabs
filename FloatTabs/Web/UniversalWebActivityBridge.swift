import Foundation
import WebKit

/// Shared host classification for universal web activity and Web Notification
/// bridging. ChatGPT hosts are explicitly excluded so `ChatGPTAttentionBridge`
/// remains the single authority for ChatGPT slots.
enum UniversalWebSitePolicy {
    static let knownAIHostSuffixes: [String] = [
        "gemini.google.com",
        "chat.deepseek.com",
        "deepseek.com",
        "claude.ai",
        "perplexity.ai",
        "grok.com",
        "kimi.moonshot.cn",
        "kimi.com",
        "chat.qwen.ai",
        "qwen.ai",
        "tongyi.aliyun.com",
        "doubao.com",
        "yuanbao.tencent.com",
        "chat.mistral.ai",
        "poe.com",
    ]

    static func isSupportedUniversalURL(_ url: URL?) -> Bool {
        guard let url,
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host?.lowercased(),
              !host.isEmpty else {
            return false
        }
        return !ChatGPTSitePolicy.isSupportedHost(host)
    }

    static func isKnownAIHost(_ host: String) -> Bool {
        let normalized = host.lowercased()
        guard !ChatGPTSitePolicy.isSupportedHost(normalized) else { return false }
        return knownAIHostSuffixes.contains { suffix in
            normalized == suffix || normalized.hasSuffix(".\(suffix)")
        }
    }

    static func isGitHubHost(_ host: String) -> Bool {
        let normalized = host.lowercased()
        return normalized == "github.com" || normalized.hasSuffix(".github.com")
    }
}

enum UniversalWebActivityEvent: Equatable, Sendable {
    case generationStarted
    case generationFinished(responseIdentity: ChatGPTResponseIdentity?, previewText: String?)
    case backgroundActivity(
        identity: ChatGPTResponseIdentity?,
        title: String?,
        body: String?,
        isExplicitNotification: Bool
    )
    case activityCleared
    case trustedInteraction
    case runtimeReset
}

/// Low-maintenance semantic activity + W3C `window.Notification` bridge for
/// all non-ChatGPT web apps (Gemini, DeepSeek, Claude, GitHub, X, YouTube,
/// Slack, Gmail, etc.).
@MainActor
final class UniversalWebActivityBridge: NSObject, WKScriptMessageHandler {
    typealias EventHandler = @MainActor (UUID, UniversalWebActivityEvent) -> Void

    static let notificationContentWorld: WKContentWorld = .page
    static let activityContentWorld = WKContentWorld.world(name: "FloatTabsUniversalActivity")
    static let notificationHandlerName = "floatTabsUniversalWebNotification"
    static let activityHandlerName = "floatTabsUniversalActivity"

    private static let maximumTitleLength = 80
    private static let maximumPreviewLength = 240
    private static let maximumTagLength = 96

    let slotID: UUID
    private let onEvent: EventHandler
    private weak var webView: WKWebView?
    private weak var userContentController: WKUserContentController?
    private var currentDocumentToken: String?
    private(set) var isInvalidated = false

    var hasActiveDocumentTokenForTesting: Bool {
        currentDocumentToken != nil
    }

    init(
        slotID: UUID,
        onEvent: @escaping EventHandler
    ) {
        self.slotID = slotID
        self.onEvent = onEvent
        super.init()
    }

    func install(into userContentController: WKUserContentController) {
        guard !isInvalidated else { return }
        userContentController.addUserScript(
            WKUserScript(
                source: Self.notificationScriptSource,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true,
                in: Self.notificationContentWorld
            )
        )
        userContentController.removeScriptMessageHandler(
            forName: Self.notificationHandlerName,
            contentWorld: Self.notificationContentWorld
        )
        userContentController.add(
            self,
            contentWorld: Self.notificationContentWorld,
            name: Self.notificationHandlerName
        )

        userContentController.addUserScript(
            WKUserScript(
                source: Self.activityScriptSource,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true,
                in: Self.activityContentWorld
            )
        )
        userContentController.removeScriptMessageHandler(
            forName: Self.activityHandlerName,
            contentWorld: Self.activityContentWorld
        )
        userContentController.add(
            self,
            contentWorld: Self.activityContentWorld,
            name: Self.activityHandlerName
        )
        self.userContentController = userContentController
    }

    func attach(to webView: WKWebView) {
        guard !isInvalidated else { return }
        self.webView = webView
    }

    func handleRuntimeReplacement() {
        currentDocumentToken = nil
        guard !isInvalidated else { return }
        onEvent(slotID, .runtimeReset)
    }

    func handleNavigationCommit(committedURL: URL?) {
        handleRuntimeReplacement()
        guard UniversalWebSitePolicy.isSupportedUniversalURL(committedURL) else { return }
        requestCurrentDocumentResync()
    }

    func handleInstantBackActivation(committedURL: URL?) {
        handleRuntimeReplacement()
        guard UniversalWebSitePolicy.isSupportedUniversalURL(committedURL) else { return }
        requestCurrentDocumentResync()
    }

    func requestCurrentDocumentResync() {
        guard !isInvalidated, let webView else { return }
        Task { @MainActor [weak self, weak webView] in
            guard let self, !self.isInvalidated, let webView, self.webView === webView else { return }
            _ = try? await webView.callAsyncJavaScript(
                "return typeof globalThis.__floatTabsUniversalResyncV1 === 'function' ? globalThis.__floatTabsUniversalResyncV1() : false;",
                arguments: [:],
                in: nil,
                contentWorld: Self.activityContentWorld
            )
        }
    }

    func invalidate() {
        guard !isInvalidated else { return }
        isInvalidated = true
        currentDocumentToken = nil
        userContentController?.removeScriptMessageHandler(
            forName: Self.notificationHandlerName,
            contentWorld: Self.notificationContentWorld
        )
        userContentController?.removeScriptMessageHandler(
            forName: Self.activityHandlerName,
            contentWorld: Self.activityContentWorld
        )
        webView = nil
        userContentController = nil
        onEvent(slotID, .runtimeReset)
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        _ = userContentController
        guard !isInvalidated,
              let attachedWebView = webView,
              message.webView === attachedWebView,
              message.frameInfo.isMainFrame else {
            return
        }
        let originURL = Self.validatedOriginURL(
            from: message.frameInfo,
            fallbackWebView: attachedWebView
        )
        guard UniversalWebSitePolicy.isSupportedUniversalURL(originURL),
              let body = message.body as? [String: Any] else {
            return
        }
        _ = acceptMessageBody(
            body,
            handlerName: message.name,
            originURL: originURL
        )
    }

    @discardableResult
    func acceptMessageBody(
        _ body: [String: Any],
        handlerName: String,
        originURL: URL?
    ) -> Bool {
        guard !isInvalidated,
              UniversalWebSitePolicy.isSupportedUniversalURL(originURL) else {
            return false
        }
        switch handlerName {
        case Self.notificationHandlerName:
            return acceptWebNotificationPayload(body, originURL: originURL)
        case Self.activityHandlerName:
            return acceptActivityPayload(body, originURL: originURL)
        default:
            return false
        }
    }

    private func acceptWebNotificationPayload(
        _ body: [String: Any],
        originURL: URL?
    ) -> Bool {
        guard body["kind"] as? String == "web_notification" else { return false }
        let title = Self.boundedText(
            body["title"] as? String,
            limit: Self.maximumTitleLength
        )
        let messageBody = Self.boundedText(
            body["body"] as? String,
            limit: Self.maximumPreviewLength
        )
        let tag = Self.boundedText(
            body["tag"] as? String,
            limit: Self.maximumTagLength
        )
        guard title != nil || messageBody != nil else { return false }

        let host = originURL?.host?.lowercased() ?? "web"
        let seed: String
        if let tag, !tag.isEmpty {
            seed = "notif:\(host):tag:\(tag):\(title ?? ""):\(messageBody ?? "")"
        } else {
            seed = "notif:\(host):\(title ?? ""):\(messageBody ?? ""):\(UUID().uuidString)"
        }
        onEvent(
            slotID,
            .backgroundActivity(
                identity: Self.stableIdentity(for: seed),
                title: title,
                body: messageBody,
                isExplicitNotification: true
            )
        )
        return true
    }

    private func acceptActivityPayload(
        _ body: [String: Any],
        originURL: URL?
    ) -> Bool {
        guard let kind = body["kind"] as? String,
              let token = body["token"] as? String,
              (8...128).contains(token.count) else {
            return false
        }

        let host = originURL?.host?.lowercased() ?? "web"

        switch kind {
        case "baseline":
            currentDocumentToken = token
            onEvent(slotID, .runtimeReset)
            return true

        case "generation_started":
            guard token == currentDocumentToken else { return false }
            onEvent(slotID, .generationStarted)
            return true

        case "generation_finished":
            guard token == currentDocumentToken else { return false }
            let preview = Self.boundedText(
                body["preview"] as? String,
                limit: Self.maximumPreviewLength
            )
            let rawIdentity = body["identity"] as? String
            let identity = ChatGPTResponseIdentity.parse(rawIdentity)
                ?? Self.stableIdentity(
                    for: "gen:\(host):\(token):\(preview ?? UUID().uuidString)"
                )
            onEvent(
                slotID,
                .generationFinished(responseIdentity: identity, previewText: preview)
            )
            return true

        case "generation_reset":
            guard token == currentDocumentToken else { return false }
            onEvent(slotID, .runtimeReset)
            return true

        case "badge_activity":
            guard token == currentDocumentToken else { return false }
            let count = body["count"] as? Int ?? 1
            guard count > 0 else { return false }
            let cleanTitle = Self.boundedText(
                body["title"] as? String,
                limit: Self.maximumTitleLength
            )
            let notificationBody: String
            if let cleanTitle, !cleanTitle.isEmpty {
                notificationBody = L10n.tr(
                    "\(cleanTitle) (\(count) unread)",
                    "\(cleanTitle)（\(count) 条未读）"
                )
            } else {
                notificationBody = L10n.tr(
                    "\(count) unread updates",
                    "有 \(count) 条未读消息或动态"
                )
            }
            let identity = Self.stableIdentity(
                for: "badge:\(host):\(token):\(count)"
            )
            onEvent(
                slotID,
                .backgroundActivity(
                    identity: identity,
                    title: nil,
                    body: notificationBody,
                    isExplicitNotification: false
                )
            )
            return true

        case "site_activity":
            guard token == currentDocumentToken else { return false }
            let title = Self.boundedText(
                body["title"] as? String,
                limit: Self.maximumTitleLength
            )
            let preview = Self.boundedText(
                body["preview"] as? String,
                limit: Self.maximumPreviewLength
            )
            let rawIdentity = body["identity"] as? String
            let identity = ChatGPTResponseIdentity.parse(rawIdentity)
                ?? Self.stableIdentity(
                    for: "site:\(host):\(token):\(title ?? ""):\(preview ?? UUID().uuidString)"
                )
            onEvent(
                slotID,
                .backgroundActivity(
                    identity: identity,
                    title: title,
                    body: preview,
                    isExplicitNotification: true
                )
            )
            return true

        case "activity_cleared":
            guard token == currentDocumentToken else { return false }
            onEvent(slotID, .activityCleared)
            return true

        case "trusted_interaction":
            guard token == currentDocumentToken else { return false }
            onEvent(slotID, .trustedInteraction)
            return true

        default:
            return false
        }
    }

    private static func validatedOriginURL(
        from frameInfo: WKFrameInfo,
        fallbackWebView: WKWebView
    ) -> URL? {
        let origin = frameInfo.securityOrigin
        let host = origin.host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let scheme = origin.protocol.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !host.isEmpty, scheme == "http" || scheme == "https" {
            var components = URLComponents()
            components.scheme = scheme
            components.host = host
            if origin.port > 0 {
                components.port = origin.port
            }
            if let url = components.url {
                return url
            }
        }
        return fallbackWebView.url
    }

    static func stableIdentity(for seed: String) -> ChatGPTResponseIdentity? {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in seed.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return ChatGPTResponseIdentity(stableValue: "univ-\(String(hash, radix: 16))")
    }

    private static func boundedText(_ raw: String?, limit: Int) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, limit > 0 else { return nil }
        let collapsed = trimmed.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )
        guard !collapsed.isEmpty else { return nil }
        if collapsed.count <= limit {
            return collapsed
        }
        let clipped = String(collapsed.prefix(limit))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return clipped.isEmpty ? nil : clipped
    }

    // MARK: - Injected Scripts

    private static var chatGPTGateJS: String {
        let mainHost = ChatGPTSitePolicy.chatGPTHost
        let legacyHost = ChatGPTSitePolicy.legacyChatHost
        return """
        const host = (location.hostname || '').toLowerCase();
        if (!host || host === '\(mainHost)' || host.endsWith('.\(mainHost)') || host === '\(legacyHost)') {
          return;
        }
        """
    }

    private static var aiHostsLiteralJS: String {
        let quoted = UniversalWebSitePolicy.knownAIHostSuffixes
            .map { "\"\($0)\"" }
            .joined(separator: ", ")
        return "[\(quoted)]"
    }

    static let notificationScriptSource: String = {
        """
        (() => {
          "use strict";
          if (window.top !== window) { return; }
          if (location.protocol !== 'http:' && location.protocol !== 'https:') { return; }
          \(chatGPTGateJS)
          if (window.__floatTabsNotificationBridgeInstalled) { return; }
          window.__floatTabsNotificationBridgeInstalled = true;

          const postWebNotification = (title, options) => {
            try {
              const handler = window.webkit
                && window.webkit.messageHandlers
                && window.webkit.messageHandlers.\(notificationHandlerName);
              if (!handler) { return; }
              const now = Date.now();
              if (!window.__floatTabsNotifTimes) { window.__floatTabsNotifTimes = []; }
              const recent = window.__floatTabsNotifTimes.filter((t) => now - t < 10000);
              if (recent.length >= 10) { return; }
              if (recent.length > 0 && now - recent[recent.length - 1] < 200) { return; }
              recent.push(now);
              window.__floatTabsNotifTimes = recent;
              const safeTitle = typeof title === 'string' ? title.slice(0, 120) : '';
              const safeBody = options && typeof options.body === 'string'
                ? options.body.slice(0, 300) : '';
              const safeTag = options && typeof options.tag === 'string'
                ? options.tag.slice(0, 96) : '';
              handler.postMessage({
                kind: 'web_notification',
                title: safeTitle,
                body: safeBody,
                tag: safeTag
              });
            } catch (_) {}
          };

          class FloatTabsWebNotification extends EventTarget {
            static get permission() { return 'granted'; }
            static get maxActions() { return 2; }
            static requestPermission(deprecatedCallback) {
              if (typeof deprecatedCallback === 'function') {
                try { deprecatedCallback('granted'); } catch (_) {}
              }
              return Promise.resolve('granted');
            }
            constructor(title, options = {}) {
              super();
              this.title = typeof title === 'string' ? title : String(title || '');
              this.body = options && typeof options.body === 'string' ? options.body : '';
              this.tag = options && typeof options.tag === 'string' ? options.tag : '';
              this.icon = options && typeof options.icon === 'string' ? options.icon : '';
              this.data = options ? options.data : null;
              this.onclick = null;
              this.onshow = null;
              this.onclose = null;
              this.onerror = null;
              postWebNotification(this.title, options || {});
              queueMicrotask(() => {
                const evt = new Event('show');
                if (typeof this.onshow === 'function') {
                  try { this.onshow(evt); } catch (_) {}
                }
                this.dispatchEvent(evt);
              });
            }
            close() {
              const evt = new Event('close');
              if (typeof this.onclose === 'function') {
                try { this.onclose(evt); } catch (_) {}
              }
              this.dispatchEvent(evt);
            }
          }

          try {
            Object.defineProperty(window, 'Notification', {
              configurable: true,
              writable: true,
              value: FloatTabsWebNotification
            });
          } catch (_) {
            window.Notification = FloatTabsWebNotification;
          }

          try {
            if (typeof ServiceWorkerRegistration !== 'undefined'
                && ServiceWorkerRegistration.prototype) {
              ServiceWorkerRegistration.prototype.showNotification = function(title, options) {
                postWebNotification(title, options || {});
                return Promise.resolve();
              };
            }
          } catch (_) {}
        })();
        """
    }()

    static let activityScriptSource: String = {
        """
        (() => {
          "use strict";
          if (window.top !== window) { return; }
          if (location.protocol !== 'http:' && location.protocol !== 'https:') { return; }
          \(chatGPTGateJS)
          if (window.__floatTabsUniversalActivityInstalled) { return; }
          window.__floatTabsUniversalActivityInstalled = true;

          const handler = () => {
            try {
              return window.webkit
                && window.webkit.messageHandlers
                && window.webkit.messageHandlers.\(activityHandlerName);
            } catch (_) {
              return undefined;
            }
          };
          if (!handler()) { return; }

          const AI_HOST_SUFFIXES = \(aiHostsLiteralJS);
          const isAIHost = AI_HOST_SUFFIXES.some(
            (suffix) => host === suffix || host.endsWith('.' + suffix)
          );
          const isGitHubHost = host === 'github.com' || host.endsWith('.github.com');

          const TOKEN = (window.crypto && crypto.randomUUID)
            ? crypto.randomUUID()
            : 'tok-' + Date.now().toString(36) + '-' + Math.random().toString(36).slice(2, 10);

          const post = (payload) => {
            try {
              const target = handler();
              if (target) {
                target.postMessage({ token: TOKEN, ...payload });
              }
            } catch (_) {}
          };

          const stableHash = (value) => {
            let h = 2166136261;
            for (let i = 0; i < value.length; i += 1) {
              h ^= value.charCodeAt(i);
              h = Math.imul(h, 16777619);
            }
            return (h >>> 0).toString(16);
          };

          const isVisible = (element) => {
            if (!element || element.nodeType !== 1 || !element.isConnected || element.hidden) {
              return false;
            }
            if (element.closest('[aria-hidden="true"]')) { return false; }
            const rects = element.getClientRects();
            if (!rects || rects.length === 0) { return false; }
            const style = getComputedStyle(element);
            return style.display !== 'none'
              && style.visibility !== 'hidden'
              && style.visibility !== 'collapse'
              && style.opacity !== '0';
          };

          // --- Shared baseline epoch (guards against firing on page load) ---
          const BASELINE_MS = 1500;
          let baselineReadyAt = Date.now() + BASELINE_MS;
          const resetBaselineWindow = () => {
            baselineReadyAt = Date.now() + BASELINE_MS;
          };

          // --- 1. Generic Title Badge Sensor (X, YouTube, Gmail, Discord, etc.) ---
          let lastBadgeCount = 0;
          const parseTitleBadge = (rawTitle) => {
            if (typeof rawTitle !== 'string') { return null; }
            const m = rawTitle.match(/^\\s*[\\(\\[]\\s*(\\d+)\\s*\\+?\\s*[\\)\\]]\\s*(.*)$/u);
            if (!m) { return null; }
            const count = parseInt(m[1], 10);
            if (!Number.isFinite(count) || count <= 0) { return null; }
            const cleanTitle = (m[2] || '').trim().slice(0, 80);
            return { count, cleanTitle };
          };

          const initialBadge = parseTitleBadge(document.title || '');
          lastBadgeCount = initialBadge ? initialBadge.count : 0;

          const evaluateTitleBadge = () => {
            const parsed = parseTitleBadge(document.title || '');
            const count = parsed ? parsed.count : 0;
            const now = Date.now();
            if (now < baselineReadyAt) {
              lastBadgeCount = count;
              return;
            }
            if (count > lastBadgeCount) {
              lastBadgeCount = count;
              post({
                kind: 'badge_activity',
                count,
                title: parsed ? parsed.cleanTitle : ''
              });
            } else if (count === 0 && lastBadgeCount > 0) {
              lastBadgeCount = 0;
              post({ kind: 'activity_cleared' });
            } else {
              lastBadgeCount = count;
            }
          };

          // --- 2. GitHub Semantic Notification & Live Timeline Sensor ---
          let githubIndicatorWasActive = false;
          let githubTimelineCount = 0;
          const hasGitHubUnreadIndicator = () => {
            if (!isGitHubHost) { return false; }
            const indicator = document.querySelector(
              'a[href="/notifications"].AppHeader-button--hasIndicator,' +
              '[data-target="notification-indicator.link"]:not([hidden]),' +
              'a[href="/notifications"][aria-label*="unread" i],' +
              'a[href="/notifications"][aria-label*="未读"]'
            );
            return Boolean(indicator && isVisible(indicator));
          };
          const currentGitHubTimelineItems = () => {
            if (!isGitHubHost) { return []; }
            return Array.from(document.querySelectorAll(
              '.js-timeline-item, [data-testid="issue-viewer-comments-container"] > div'
            ));
          };
          githubIndicatorWasActive = hasGitHubUnreadIndicator();
          githubTimelineCount = currentGitHubTimelineItems().length;

          const evaluateGitHubActivity = () => {
            if (!isGitHubHost) { return; }
            const now = Date.now();
            const active = hasGitHubUnreadIndicator();
            const items = currentGitHubTimelineItems();
            const count = items.length;
            if (now < baselineReadyAt) {
              githubIndicatorWasActive = active;
              githubTimelineCount = count;
              return;
            }
            if (active && !githubIndicatorWasActive) {
              githubIndicatorWasActive = true;
              post({
                kind: 'site_activity',
                title: document.title || 'GitHub',
                preview: 'New GitHub notification activity.',
                identity: 'message:univ-gh-notif-' + stableHash(location.pathname + ':' + Date.now())
              });
            } else if (!active && githubIndicatorWasActive) {
              githubIndicatorWasActive = false;
              post({ kind: 'activity_cleared' });
            }
            if (count > githubTimelineCount) {
              const backgroundLike = document.visibilityState === 'hidden' || !document.hasFocus();
              githubTimelineCount = count;
              if (backgroundLike) {
                const newest = items[items.length - 1];
                const rawSnippet = newest ? (newest.innerText || newest.textContent || '') : '';
                const snippet = rawSnippet.replace(/\\s+/g, ' ').trim().slice(0, 220);
                post({
                  kind: 'site_activity',
                  title: document.title || 'GitHub',
                  preview: snippet || 'New activity in issue or pull request.',
                  identity: 'message:univ-gh-tl-' + stableHash(location.pathname + ':' + count + ':' + snippet.slice(0, 64))
                });
              }
            } else {
              githubTimelineCount = count;
            }
          };

          // --- 3. Semantic AI Streaming Detector (Gemini, DeepSeek, Claude, etc.) ---
          const STOP_LABEL_RE = /^(stop(\\s+(generating|response|streaming|output|answer))?|cancel generation|停止(生成|回答|输出|响应|流式传输)?|中止(生成|回答)?)$/i;
          const SEND_LABEL_RE = /^(send(\\s+message)?|submit|ask|发送|提交|提问)/i;
          const EXPLICIT_STOP_QUIET_MS = 700;
          const FALLBACK_QUIET_MS = 1600;
          const SUBMIT_ARMED_WINDOW_MS = 5000;
          const SUBMIT_MAX_SILENT_MS = 12000;

          let aiGenerating = false;
          let sawExplicitStopSignal = false;
          let submitArmedUntil = 0;
          let submitBaselineSignature = '';
          let lastContentMutationAt = 0;
          let completionCheckTimer = null;
          let submitSilentTimer = null;
          let lastCompletedSignature = '';

          const isEditableComposer = (el) => {
            if (!el || el.nodeType !== 1) { return false; }
            if (el.matches('textarea, [contenteditable="true"], [role="textbox"]')) {
              return !el.readOnly && !el.disabled;
            }
            const closest = el.closest && el.closest('textarea, [contenteditable="true"], [role="textbox"]');
            return Boolean(closest && !closest.readOnly && !closest.disabled);
          };

          const hasExplicitAIStopSignal = () => {
            const buttons = document.querySelectorAll(
              'button[aria-label], button[title], button[mattooltip], [role="button"][aria-label], [role="button"][title]'
            );
            for (const btn of buttons) {
              if (btn.disabled || btn.getAttribute('aria-disabled') === 'true') { continue; }
              const labels = [
                btn.getAttribute('aria-label') || '',
                btn.getAttribute('title') || '',
                btn.getAttribute('mattooltip') || ''
              ];
              const matchesStop = labels.some((raw) => STOP_LABEL_RE.test(raw.trim().replace(/\\s+/g, ' ')));
              if (matchesStop && isVisible(btn)) {
                return true;
              }
            }
            const busyNode = document.querySelector(
              'main [aria-busy="true"], [role="main"] [aria-busy="true"], model-response[aria-busy="true"]'
            );
            return Boolean(busyNode && isVisible(busyNode));
          };

          const readLastResponseText = () => {
            const scope = document.querySelector('main, [role="main"]') || document.body;
            if (!scope) { return ''; }
            const candidateContainers = scope.querySelectorAll(
              'model-response, [data-message-author-role="assistant"], message-content, article, .markdown, .ds-markdown, [data-testid*="message"]'
            );
            for (let i = candidateContainers.length - 1; i >= 0; i -= 1) {
              const container = candidateContainers[i];
              if (!isVisible(container)) { continue; }
              if (container.closest('form, nav, header, footer')) { continue; }
              if (container.querySelector('textarea, [contenteditable="true"]')) { continue; }
              const clone = container.cloneNode(true);
              clone.querySelectorAll('script, style, noscript, button, [role="button"], nav, header, svg').forEach((n) => n.remove());
              const cleaned = (clone.innerText || clone.textContent || '').replace(/\\s+/g, ' ').trim();
              if (cleaned.length > 0) {
                return cleaned;
              }
            }
            const fallbackClone = scope.cloneNode(true);
            fallbackClone.querySelectorAll('script, style, noscript, textarea, input, [contenteditable="true"], button, [role="button"], nav, header, svg').forEach((n) => n.remove());
            return (fallbackClone.innerText || fallbackClone.textContent || '').replace(/\\s+/g, ' ').trim();
          };

          const mainTextSignature = () => {
            const text = readLastResponseText();
            return text.length + ':' + stableHash(text.slice(-240));
          };

          const clearTimers = () => {
            if (completionCheckTimer) {
              clearTimeout(completionCheckTimer);
              completionCheckTimer = null;
            }
            if (submitSilentTimer) {
              clearTimeout(submitSilentTimer);
              submitSilentTimer = null;
            }
          };

          const scheduleCompletionCheck = () => {
            if (completionCheckTimer) { clearTimeout(completionCheckTimer); }
            const delay = sawExplicitStopSignal ? EXPLICIT_STOP_QUIET_MS : FALLBACK_QUIET_MS;
            completionCheckTimer = setTimeout(() => {
              completionCheckTimer = null;
              if (!aiGenerating) { return; }
              const stopStillPresent = hasExplicitAIStopSignal();
              if (stopStillPresent) {
                sawExplicitStopSignal = true;
                scheduleCompletionCheck();
                return;
              }
              const elapsedQuiet = Date.now() - lastContentMutationAt;
              if (elapsedQuiet < delay) {
                scheduleCompletionCheck();
                return;
              }
              aiGenerating = false;
              sawExplicitStopSignal = false;
              submitArmedUntil = 0;
              clearTimers();
              const responseText = readLastResponseText();
              const preview = responseText.slice(0, 240);
              const sig = responseText.length + ':' + stableHash(preview);
              if (sig === lastCompletedSignature && preview.length === 0) {
                post({ kind: 'generation_reset' });
                return;
              }
              lastCompletedSignature = sig;
              post({
                kind: 'generation_finished',
                preview,
                identity: 'message:univ-ai-' + stableHash(location.pathname + ':' + sig)
              });
            }, delay);
          };

          const startGeneratingIfNeeded = (fromExplicitStop) => {
            if (fromExplicitStop) {
              sawExplicitStopSignal = true;
            }
            if (!aiGenerating) {
              aiGenerating = true;
              lastContentMutationAt = Date.now();
              if (submitSilentTimer) {
                clearTimeout(submitSilentTimer);
                submitSilentTimer = null;
              }
              post({ kind: 'generation_started' });
            }
            scheduleCompletionCheck();
          };

          const armAISubmit = () => {
            if (!isAIHost) { return; }
            submitArmedUntil = Date.now() + SUBMIT_ARMED_WINDOW_MS;
            submitBaselineSignature = mainTextSignature();
            if (submitSilentTimer) { clearTimeout(submitSilentTimer); }
            submitSilentTimer = setTimeout(() => {
              submitSilentTimer = null;
              submitArmedUntil = 0;
              if (aiGenerating && !sawExplicitStopSignal && (Date.now() - lastContentMutationAt) > SUBMIT_MAX_SILENT_MS) {
                aiGenerating = false;
                clearTimers();
                post({ kind: 'generation_reset' });
              }
            }, SUBMIT_MAX_SILENT_MS);
          };

          if (isAIHost) {
            document.addEventListener('keydown', (event) => {
              if (!event.isTrusted || event.isComposing) { return; }
              if (event.key === 'Enter' && !event.shiftKey && !event.altKey && !event.metaKey) {
                if (isEditableComposer(event.target)) {
                  armAISubmit();
                }
              }
            }, true);

            document.addEventListener('click', (event) => {
              if (!event.isTrusted) { return; }
              const btn = event.target && event.target.closest && event.target.closest('button, [role="button"]');
              if (!btn || btn.disabled) { return; }
              if (btn.type === 'submit') {
                armAISubmit();
                return;
              }
              const label = (
                btn.getAttribute('aria-label') ||
                btn.getAttribute('title') ||
                btn.textContent ||
                ''
              ).trim();
              if (SEND_LABEL_RE.test(label)) {
                armAISubmit();
              }
            }, true);
          }

          // --- 4. Trusted Interaction Sensor (clears unread when reading/clicking) ---
          let lastInteractionSentAt = 0;
          const notifyTrustedInteraction = (event) => {
            if (!event || !event.isTrusted) { return; }
            const now = Date.now();
            if (now - lastInteractionSentAt < 1000) { return; }
            lastInteractionSentAt = now;
            post({ kind: 'trusted_interaction' });
          };
          document.addEventListener('pointerdown', notifyTrustedInteraction, { capture: true, passive: true });
          document.addEventListener('wheel', notifyTrustedInteraction, { capture: true, passive: true });

          // --- 5. Observers & Navigation Hooks ---
          let observerTimer = null;
          const handleDOMActivity = () => {
            evaluateTitleBadge();
            if (isGitHubHost) {
              evaluateGitHubActivity();
            }
            const now = Date.now();
            const explicitStop = (isAIHost || now >= baselineReadyAt) && hasExplicitAIStopSignal();
            if (explicitStop) {
              // Require either AI host OR explicit stop + [aria-busy="true"] on non-AI hosts
              const allowExplicit = isAIHost || Boolean(
                document.querySelector('main [aria-busy="true"], [role="main"] [aria-busy="true"]')
              );
              if (allowExplicit) {
                lastContentMutationAt = now;
                startGeneratingIfNeeded(true);
                return;
              }
            }
            if (isAIHost) {
              if (aiGenerating) {
                lastContentMutationAt = now;
                scheduleCompletionCheck();
              } else if (submitArmedUntil > now) {
                const sig = mainTextSignature();
                if (sig !== submitBaselineSignature) {
                  lastContentMutationAt = now;
                  startGeneratingIfNeeded(false);
                }
              }
            }
          };

          const scheduleDOMActivity = () => {
            if (observerTimer) { return; }
            observerTimer = setTimeout(() => {
              observerTimer = null;
              handleDOMActivity();
            }, 250);
          };

          const installObservers = () => {
            const root = document.documentElement || document;
            const mutationObserver = new MutationObserver((mutations) => {
              let relevant = false;
              for (const m of mutations) {
                if (m.target && m.target.nodeName === 'TITLE') {
                  evaluateTitleBadge();
                  continue;
                }
                if (m.target && m.target.closest && m.target.closest('textarea, [contenteditable="true"]')) {
                  continue;
                }
                relevant = true;
              }
              if (relevant) {
                scheduleDOMActivity();
              }
            });
            mutationObserver.observe(root, {
              childList: true,
              subtree: true,
              characterData: true,
              attributes: true,
              attributeFilter: ['aria-label', 'aria-busy', 'disabled', 'aria-disabled', 'hidden', 'class']
            });

            const head = document.head || root;
            const titleEl = document.querySelector('title');
            if (titleEl) {
              new MutationObserver(() => evaluateTitleBadge()).observe(titleEl, {
                childList: true,
                characterData: true,
                subtree: true
              });
            } else if (head) {
              new MutationObserver(() => evaluateTitleBadge()).observe(head, {
                childList: true,
                subtree: true
              });
            }
          };

          let hasAnnouncedBaseline = false;
          const announceBaseline = () => {
            if (hasAnnouncedBaseline) { return; }
            hasAnnouncedBaseline = true;
            post({ kind: 'baseline' });
          };

          globalThis.__floatTabsUniversalResyncV1 = () => {
            resetBaselineWindow();
            aiGenerating = false;
            sawExplicitStopSignal = false;
            clearTimers();
            hasAnnouncedBaseline = true;
            post({ kind: 'baseline' });
            return true;
          };

          if (document.documentElement) {
            installObservers();
          } else {
            document.addEventListener('DOMContentLoaded', installObservers, { once: true });
          }

          // Defer initial baseline until DOMContentLoaded (alongside host-triggered
          // resync on didCommit/Instant Back) so atDocumentStart handshake does not
          // race ahead of WebKit's didCommit token reset.
          if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', announceBaseline, { once: true });
          } else {
            Promise.resolve().then(announceBaseline);
          }

          window.addEventListener('pageshow', (event) => {
            resetBaselineWindow();
            if (event.persisted) {
              aiGenerating = false;
              sawExplicitStopSignal = false;
              clearTimers();
              hasAnnouncedBaseline = true;
              post({ kind: 'baseline' });
            }
          }, { passive: true });
          window.addEventListener('popstate', () => {
            resetBaselineWindow();
          }, { passive: true });
        })();
        """
    }()
}
