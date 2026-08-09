import Foundation
import WebKit

enum WebNavigationDisposition: Equatable {
    case allow
    case loadInCurrentSlot
}

/// Owns navigation-policy decisions independently from per-Slot WebView
/// lifecycle observation.
final class WebNavigationCoordinator {
    func disposition(for navigationAction: WKNavigationAction) -> WebNavigationDisposition {
        Self.disposition(
            hasTargetFrame: navigationAction.targetFrame != nil,
            sourceURL: navigationAction.sourceFrame.request.url,
            targetURL: navigationAction.request.url
        )
    }

    /// Stage 4B production policy for new browsing contexts.
    ///
    /// Same-site HTTP(S) links continue in the persistent Slot. Cross-site and
    /// non-web new contexts are allowed through so `WKUIDelegate` can classify
    /// them as temporary popups or external-browser handoffs.
    static func disposition(
        hasTargetFrame: Bool,
        sourceURL: URL?,
        targetURL: URL?
    ) -> WebNavigationDisposition {
        guard !hasTargetFrame,
              let targetURL,
              isWebURL(targetURL) else {
            return .allow
        }

        return isSameSite(sourceURL, targetURL)
            ? .loadInCurrentSlot
            : .allow
    }

    /// Preserves the accepted Stage 3 regression seam while its historical test
    /// still asserts the old all-HTTP(S) current-Slot fallback directly.
    static func stage3FallbackDisposition(
        hasTargetFrame: Bool,
        url: URL?
    ) -> WebNavigationDisposition {
        guard !hasTargetFrame,
              let url,
              isWebURL(url) else {
            return .allow
        }
        return .loadInCurrentSlot
    }

    static func isSameSite(_ first: URL?, _ second: URL?) -> Bool {
        guard let firstHost = normalizedHost(first),
              let secondHost = normalizedHost(second) else {
            return false
        }
        return firstHost == secondHost
    }

    static func isWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    private static func normalizedHost(_ url: URL?) -> String? {
        guard var host = url?.host?.lowercased(), !host.isEmpty else { return nil }
        if host.hasPrefix("www.") {
            host.removeFirst(4)
        }
        return host
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

    /// Historical Stage 3 regression seam. New Stage 4 policy tests should call
    /// `WebNavigationCoordinator` directly; this remains only so the accepted
    /// Stage 3 fixture continues to guard the original Bilibili fix.
    static func shouldOpenInCurrentSlot(targetFrame: WKFrameInfo?, url: URL?) -> Bool {
        WebNavigationCoordinator.stage3FallbackDisposition(
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
