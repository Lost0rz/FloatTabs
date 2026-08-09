import Foundation
import WebKit

enum WebNavigationDisposition: Equatable {
    case allow
    case loadInCurrentSlot
}

/// Owns navigation-policy decisions independently from per-Slot WebView
/// lifecycle observation. Stage 4A intentionally preserves the accepted Stage 3
/// behavior while establishing the decision boundary that later popup/OAuth and
/// external-browser routing will extend.
final class WebNavigationCoordinator {
    func disposition(for navigationAction: WKNavigationAction) -> WebNavigationDisposition {
        Self.disposition(
            hasTargetFrame: navigationAction.targetFrame != nil,
            url: navigationAction.request.url
        )
    }

    static func disposition(
        hasTargetFrame: Bool,
        url: URL?
    ) -> WebNavigationDisposition {
        guard !hasTargetFrame,
              let url,
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return .allow
        }

        // Stage 4A is an ownership refactor, not a behavior change. Keep the
        // accepted Stage 3 current-slot fallback until Stage 4B can distinguish
        // same-site links, OAuth/login popups, and ordinary external links.
        return .loadInCurrentSlot
    }
}

/// Owns the per-Slot navigation lifecycle that must survive reloads and redirects.
///
/// On macOS, Website Mode is implemented by FloatTabsWebView's WebKit layout
/// strategy plus the independently selected browser identity. We deliberately do
/// not mutate WKWebpagePreferences.preferredContentMode here: WebKit exposes that
/// desktop-class browsing API for iOS, not as the macOS layout mechanism.
@MainActor
final class SlotNavigationObserver: NSObject, WKNavigationDelegate {
    private weak var webView: WKWebView?
    private var observation: NSKeyValueObservation?
    private let slotID: UUID
    private let websiteMode: WebsiteMode
    private let navigationCoordinator: WebNavigationCoordinator
    private let onURLChange: @MainActor (UUID, URL) -> Void

    init(
        slotID: UUID,
        webView: WKWebView,
        websiteMode: WebsiteMode,
        navigationCoordinator: WebNavigationCoordinator = WebNavigationCoordinator(),
        onURLChange: @escaping @MainActor (UUID, URL) -> Void
    ) {
        self.slotID = slotID
        self.webView = webView
        self.websiteMode = websiteMode
        self.navigationCoordinator = navigationCoordinator
        self.onURLChange = onURLChange
        super.init()

        observation = webView.observe(\.url, options: [.new]) { observedWebView, _ in
            guard let url = observedWebView.url, WebAppURL.isSafe(url) else {
                return
            }

            Task { @MainActor in
                onURLChange(slotID, url)
            }
        }

        webView.navigationDelegate = self
    }

    deinit {
        observation?.invalidate()
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        preferences: WKWebpagePreferences,
        decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void
    ) {
        restoreWebsiteMode(in: webView)

        switch navigationCoordinator.disposition(for: navigationAction) {
        case .allow:
            decisionHandler(.allow, preferences)

        case .loadInCurrentSlot:
            decisionHandler(.cancel, preferences)
            webView.load(navigationAction.request)
        }
    }

    /// Stage 3 regression seam retained while its existing test is migrated to
    /// the Stage 4 coordinator. Policy ownership now lives in
    /// `WebNavigationCoordinator`; this method contains no independent rules.
    static func shouldOpenInCurrentSlot(targetFrame: WKFrameInfo?, url: URL?) -> Bool {
        WebNavigationCoordinator.disposition(
            hasTargetFrame: targetFrame != nil,
            url: url
        ) == .loadInCurrentSlot
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        restoreWebsiteMode(in: webView)
        restoreTransientScrollerPolicy(in: webView)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        restoreWebsiteMode(in: webView)
        restoreTransientScrollerPolicy(in: webView)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        restoreWebsiteMode(in: webView)
        restoreTransientScrollerPolicy(in: webView)

        DispatchQueue.main.async { [weak webView] in
            guard let webView else { return }
            WebViewFactory.configureHiddenScrollers(in: webView)
        }
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        restoreTransientScrollerPolicy(in: webView)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        restoreTransientScrollerPolicy(in: webView)
    }

    private func restoreWebsiteMode(in webView: WKWebView) {
        (webView as? FloatTabsWebView)?.setWebsiteMode(websiteMode)
    }

    private func restoreTransientScrollerPolicy(in webView: WKWebView) {
        WebViewFactory.configureHiddenScrollers(in: webView)
    }
}
