import Foundation
import WebKit

/// Owns the per-Slot navigation lifecycle that must survive reloads and redirects.
/// Website Mode is reasserted for every main navigation while the exact browser
/// identity is supplied independently through `customUserAgent`.
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

    static func applyWebsiteMode(
        _ websiteMode: WebsiteMode,
        to preferences: WKWebpagePreferences
    ) {
        preferences.preferredContentMode = WebViewFactory.preferredContentMode(for: websiteMode)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        preferences: WKWebpagePreferences,
        decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void
    ) {
        Self.applyWebsiteMode(websiteMode, to: preferences)
        decisionHandler(.allow, preferences)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        restoreTransientScrollerPolicy(in: webView)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        restoreTransientScrollerPolicy(in: webView)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
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

    private func restoreTransientScrollerPolicy(in webView: WKWebView) {
        WebViewFactory.configureHiddenScrollers(in: webView)
    }
}
