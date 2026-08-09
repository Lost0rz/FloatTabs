import Foundation
import WebKit

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
    private let onURLChange: @MainActor (UUID, URL) -> Void

    init(
        slotID: UUID,
        webView: WKWebView,
        websiteMode: WebsiteMode,
        onURLChange: @escaping @MainActor (UUID, URL) -> Void
    ) {
        self.slotID = slotID
        self.webView = webView
        self.websiteMode = websiteMode
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
        if Self.shouldOpenInCurrentSlot(targetFrame: navigationAction.targetFrame, url: navigationAction.request.url) {
            decisionHandler(.cancel, preferences)
            webView.load(navigationAction.request)
            return
        }
        decisionHandler(.allow, preferences)
    }

    /// Stage 3 compatibility fallback for a new browsing context (`target="_blank"`
    /// or `window.open`). Without an auxiliary WKWebView target, WebKit can deliver
    /// a trusted DOM click while the requested page appears not to open. Until the
    /// full WebNavigationCoordinator policy is implemented, ordinary http/https
    /// requests with no target frame are loaded into the current persistent Slot.
    ///
    /// This fallback does not supersede the canonical V1 navigation policy. The
    /// next compatibility/navigation stage must classify OAuth/login popups,
    /// same-site popups, and ordinary external/research links separately.
    static func shouldOpenInCurrentSlot(targetFrame: WKFrameInfo?, url: URL?) -> Bool {
        guard targetFrame == nil,
              let url,
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return false }
        return true
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
