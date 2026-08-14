import AppKit
import Foundation
import WebKit

@MainActor
final class DownloadCoordinator: NSObject, WKDownloadDelegate {
    private var activeDownloads: [ObjectIdentifier: WKDownload] = [:]
    private var presentingWindows: [ObjectIdentifier: NSWindow] = [:]

    static func actionPolicy(
        shouldPerformDownload: Bool
    ) -> WKNavigationActionPolicy {
        shouldPerformDownload ? .download : .allow
    }

    static func responsePolicy(
        canShowMIMEType: Bool
    ) -> WKNavigationResponsePolicy {
        canShowMIMEType ? .allow : .download
    }

    static func responsePolicy(
        response: URLResponse,
        canShowMIMEType: Bool
    ) -> WKNavigationResponsePolicy {
        if contentDispositionRequestsDownload(response) {
            return .download
        }
        return responsePolicy(canShowMIMEType: canShowMIMEType)
    }

    static func contentDispositionRequestsDownload(_ response: URLResponse) -> Bool {
        guard let httpResponse = response as? HTTPURLResponse,
              let value = httpResponse.value(forHTTPHeaderField: "Content-Disposition") else {
            return false
        }

        let disposition = value
            .split(separator: ";", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        return disposition == "attachment"
    }

    static func safeSuggestedFilename(_ suggestedFilename: String) -> String {
        guard !suggestedFilename.isEmpty else {
            return "Download"
        }

        let candidate = URL(fileURLWithPath: suggestedFilename).lastPathComponent
        return candidate.isEmpty ? "Download" : candidate
    }

    func attach(_ download: WKDownload, presentingWindow: NSWindow?) {
        let id = ObjectIdentifier(download)
        activeDownloads[id] = download
        if let presentingWindow {
            presentingWindows[id] = presentingWindow
        }
        download.delegate = self
    }

    func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String,
        completionHandler: @escaping @MainActor @Sendable (URL?) -> Void
    ) {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = Self.safeSuggestedFilename(suggestedFilename)

        let finish: (NSApplication.ModalResponse) -> Void = { [weak self] result in
            guard let self else {
                completionHandler(nil)
                return
            }

            guard result == .OK, let destination = panel.url else {
                self.cleanup(download)
                completionHandler(nil)
                return
            }

            if FileManager.default.fileExists(atPath: destination.path) {
                do {
                    try FileManager.default.removeItem(at: destination)
                } catch {
                    self.cleanup(download)
                    completionHandler(nil)
                    return
                }
            }

            completionHandler(destination)
        }

        if let window = presentingWindows[ObjectIdentifier(download)] {
            panel.beginSheetModal(for: window, completionHandler: finish)
        } else {
            finish(panel.runModal())
        }
    }

    func downloadDidFinish(_ download: WKDownload) {
        cleanup(download)
    }

    func download(
        _ download: WKDownload,
        didFailWithError error: Error,
        resumeData: Data?
    ) {
        cleanup(download)
    }

    private func cleanup(_ download: WKDownload) {
        let id = ObjectIdentifier(download)
        activeDownloads.removeValue(forKey: id)
        presentingWindows.removeValue(forKey: id)
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
    private let downloadCoordinator: DownloadCoordinator
    private let onURLChange: @MainActor (UUID, URL) -> Void
    private let onContentProcessTermination: @MainActor (UUID) -> Void
    private let loadHandler: @MainActor (WKWebView, URL) -> Void

    /// Set when FloatTabs itself issued the entry load for an https URL that
    /// is eligible for the one-shot http:// fallback (see
    /// `allowHTTPEntryFallback`). Any successful commit or a handled failure
    /// consumes it.
    private var pendingHTTPEntryFallback: URL?

    /// Whether an entry load is currently eligible for the http fallback.
    /// Exposed for tests and diagnostics.
    var isHTTPEntryFallbackPending: Bool {
        pendingHTTPEntryFallback != nil
    }

    init(
        slotID: UUID,
        webView: WKWebView,
        websiteMode: WebsiteMode,
        navigationCoordinator: WebNavigationCoordinator = WebNavigationCoordinator(),
        downloadCoordinator: DownloadCoordinator? = nil,
        onURLChange: @escaping @MainActor (UUID, URL) -> Void,
        onContentProcessTermination: @escaping @MainActor (UUID) -> Void = { _ in },
        loadHandler: @escaping @MainActor (WKWebView, URL) -> Void = { webView, url in
            webView.load(URLRequest(url: url))
        }
    ) {
        self.slotID = slotID
        self.webView = webView
        self.websiteMode = websiteMode
        self.navigationCoordinator = navigationCoordinator
        self.downloadCoordinator = downloadCoordinator ?? DownloadCoordinator()
        self.onURLChange = onURLChange
        self.onContentProcessTermination = onContentProcessTermination
        self.loadHandler = loadHandler
        super.init()

        observation = webView.observe(\.url, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self,
                      let url = self.webView?.url,
                      WebAppURL.isSafe(url) else {
                    return
                }
                self.onURLChange(self.slotID, url)
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
        decisionHandler: @escaping @MainActor @Sendable (
            WKNavigationActionPolicy,
            WKWebpagePreferences
        ) -> Void
    ) {
        restoreWebsiteMode(in: webView)

        if navigationAction.shouldPerformDownload {
            decisionHandler(.download, preferences)
            return
        }

        switch navigationCoordinator.disposition(for: navigationAction) {
        case .allow:
            decisionHandler(.allow, preferences)

        case .loadInCurrentSlot:
            decisionHandler(.cancel, preferences)
            webView.load(navigationAction.request)
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void
    ) {
        decisionHandler(
            DownloadCoordinator.responsePolicy(
                response: navigationResponse.response,
                canShowMIMEType: navigationResponse.canShowMIMEType
            )
        )
    }

    func webView(
        _ webView: WKWebView,
        navigationAction: WKNavigationAction,
        didBecome download: WKDownload
    ) {
        downloadCoordinator.attach(download, presentingWindow: webView.window)
    }

    func webView(
        _ webView: WKWebView,
        navigationResponse: WKNavigationResponse,
        didBecome download: WKDownload
    ) {
        downloadCoordinator.attach(download, presentingWindow: webView.window)
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
        restoreHiddenScrollerPolicy(in: webView)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        restoreWebsiteMode(in: webView)
        restoreHiddenScrollerPolicy(in: webView)
        // The https entry committed successfully; the http fallback loses its
        // eligibility so later in-page failures can never downgrade.
        pendingHTTPEntryFallback = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        restoreWebsiteMode(in: webView)
        restoreHiddenScrollerPolicy(in: webView)

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
        restoreHiddenScrollerPolicy(in: webView)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        restoreHiddenScrollerPolicy(in: webView)

        let failingURL = ((error as NSError).userInfo["NSErrorFailingURLStringKey"] as? String)
            .flatMap { URL(string: $0) }
            ?? webView.url
        if let fallback = Self.httpFallbackURL(
            pending: pendingHTTPEntryFallback,
            failingURL: failingURL,
            error: error
        ) {
            pendingHTTPEntryFallback = nil
            loadHandler(webView, fallback)
        } else {
            pendingHTTPEntryFallback = nil
        }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        onContentProcessTermination(slotID)
    }

    /// Marks the next load as a FloatTabs entry (address bar, Web App first
    /// load, Return to Home) eligible for the one-shot https → http fallback.
    /// Ineligible URLs (default-port https, explicit http) store nothing.
    func allowHTTPEntryFallback(for url: URL) {
        pendingHTTPEntryFallback = WebAppURL.httpFallbackCandidate(for: url) != nil ? url : nil
    }

    /// Pure fallback decision: a connection-level failure of exactly the
    /// pending entry URL yields the http candidate. Certificate-trust
    /// failures, other domains, mismatched URLs, and absent pending state
    /// never downgrade.
    static func httpFallbackURL(pending: URL?, failingURL: URL?, error: Error) -> URL? {
        guard let pending,
              let failingURL,
              failingURL == pending || failingURL.absoluteString == pending.absoluteString else {
            return nil
        }

        let nsError = error as NSError
        let connectionLevelFailureCodes: Set<Int> = [
            NSURLErrorTimedOut,
            NSURLErrorCannotFindHost,
            NSURLErrorCannotConnectToHost,
            NSURLErrorNetworkConnectionLost,
            NSURLErrorDNSLookupFailed,
            NSURLErrorSecureConnectionFailed,
        ]
        guard nsError.domain == NSURLErrorDomain,
              connectionLevelFailureCodes.contains(nsError.code) else {
            return nil
        }

        return WebAppURL.httpFallbackCandidate(for: pending)
    }

    private func restoreWebsiteMode(in webView: WKWebView) {
        (webView as? FloatTabsWebView)?.setWebsiteMode(websiteMode)
    }

    private func restoreHiddenScrollerPolicy(in webView: WKWebView) {
        WebViewFactory.configureHiddenScrollers(in: webView)
    }
}
