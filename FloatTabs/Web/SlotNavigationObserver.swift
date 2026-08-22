import AppKit
import Foundation
import WebKit

@MainActor
final class DownloadCoordinator: NSObject, WKDownloadDelegate {
    private struct PendingDestination {
        let stagingURL: URL
        let finalURL: URL
    }

    private var activeDownloads: [ObjectIdentifier: WKDownload] = [:]
    private var presentingWindows: [ObjectIdentifier: NSWindow] = [:]
    private var pendingDestinations: [ObjectIdentifier: PendingDestination] = [:]
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        super.init()
    }

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

    static func stagingURL(for finalURL: URL, token: UUID = UUID()) -> URL {
        let filename = finalURL.lastPathComponent.isEmpty ? "Download" : finalURL.lastPathComponent
        return finalURL.deletingLastPathComponent().appendingPathComponent(
            ".FloatTabs-\(token.uuidString)-\(filename).download",
            isDirectory: false
        )
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

            guard result == .OK, let finalURL = panel.url else {
                self.cleanup(download)
                completionHandler(nil)
                return
            }

            let id = ObjectIdentifier(download)
            let stagingURL = Self.stagingURL(for: finalURL)
            // WKDownload requires an unused destination. Always download into a
            // same-directory staging file so an existing user file is never
            // deleted before the transfer has actually succeeded.
            if self.fileManager.fileExists(atPath: stagingURL.path) {
                try? self.fileManager.removeItem(at: stagingURL)
            }
            self.pendingDestinations[id] = PendingDestination(
                stagingURL: stagingURL,
                finalURL: finalURL
            )
            completionHandler(stagingURL)
        }

        if let window = presentingWindows[ObjectIdentifier(download)] {
            panel.beginSheetModal(for: window, completionHandler: finish)
        } else {
            finish(panel.runModal())
        }
    }

    func downloadDidFinish(_ download: WKDownload) {
        finalizeSuccessfulDownload(download)
        cleanup(download)
    }

    func download(
        _ download: WKDownload,
        didFailWithError error: Error,
        resumeData: Data?
    ) {
        discardStagingFile(download)
        cleanup(download)
    }

    private func finalizeSuccessfulDownload(_ download: WKDownload) {
        let id = ObjectIdentifier(download)
        guard let destination = pendingDestinations.removeValue(forKey: id) else { return }

        do {
            if fileManager.fileExists(atPath: destination.finalURL.path) {
                _ = try fileManager.replaceItemAt(
                    destination.finalURL,
                    withItemAt: destination.stagingURL,
                    backupItemName: nil,
                    options: []
                )
            } else {
                try fileManager.moveItem(
                    at: destination.stagingURL,
                    to: destination.finalURL
                )
            }
        } catch {
            presentFinalizationFailure(
                stagingURL: destination.stagingURL,
                finalURL: destination.finalURL,
                window: presentingWindows[id]
            )
        }
    }

    private func discardStagingFile(_ download: WKDownload) {
        let id = ObjectIdentifier(download)
        guard let destination = pendingDestinations.removeValue(forKey: id) else { return }
        if fileManager.fileExists(atPath: destination.stagingURL.path) {
            try? fileManager.removeItem(at: destination.stagingURL)
        }
    }

    private func presentFinalizationFailure(
        stagingURL: URL,
        finalURL: URL,
        window: NSWindow?
    ) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Couldn’t Finish Saving Download"
        alert.informativeText = "The existing file was kept. The completed download remains at \(stagingURL.path)."
        alert.addButton(withTitle: "OK")
        if let window, window.attachedSheet == nil {
            alert.beginSheetModal(for: window)
        } else {
            NSSound.beep()
        }
        NSLog(
            "FloatTabs download finalization failed staging=%@ final=%@",
            stagingURL.path,
            finalURL.path
        )
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
    private let onNavigationCommit: @MainActor (UUID) -> Void
    private let onInstantBackRequest: @MainActor (UUID, URL?) -> Void
    private let onInstantBackCancellation: @MainActor (UUID) -> Void
    private let onInstantBackActivation: @MainActor (UUID) -> Void
    private let loadHandler: @MainActor (WKWebView, URL) -> Void

    private struct PendingInstantBack {
        let targetItem: WKBackForwardListItem
        let targetURL: URL?
    }

    /// Set only for a FloatTabs-issued entry whose `https://` scheme was
    /// inferred from a bare user address. Any successful commit or a handled
    /// failure consumes the one-shot permission.
    private var pendingHTTPEntryFallback: URL?

    /// Whether an entry load is currently eligible for the http fallback.
    /// Exposed for tests and diagnostics.
    var isHTTPEntryFallbackPending: Bool {
        pendingHTTPEntryFallback != nil
    }

    /// Whether WebKit has asked us to correlate a possible Instant Back
    /// activation. This marker is transient and is never a committed-URL
    /// authority.
    var isInstantBackActivationPending: Bool {
        pendingInstantBack != nil
    }

    private var pendingInstantBack: PendingInstantBack?

    init(
        slotID: UUID,
        webView: WKWebView,
        websiteMode: WebsiteMode,
        navigationCoordinator: WebNavigationCoordinator = WebNavigationCoordinator(),
        downloadCoordinator: DownloadCoordinator? = nil,
        onURLChange: @escaping @MainActor (UUID, URL) -> Void,
        onContentProcessTermination: @escaping @MainActor (UUID) -> Void = { _ in },
        onNavigationCommit: @escaping @MainActor (UUID) -> Void = { _ in },
        onInstantBackRequest: @escaping @MainActor (UUID, URL?) -> Void = { _, _ in },
        onInstantBackCancellation: @escaping @MainActor (UUID) -> Void = { _ in },
        onInstantBackActivation: @escaping @MainActor (UUID) -> Void = { _ in },
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
        self.onNavigationCommit = onNavigationCommit
        self.onInstantBackRequest = onInstantBackRequest
        self.onInstantBackCancellation = onInstantBackCancellation
        self.onInstantBackActivation = onInstantBackActivation
        self.loadHandler = loadHandler
        super.init()

        observation = webView.observe(\.url, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self, weak webView] in
                guard let self,
                      let webView,
                      self.webView === webView,
                      let url = webView.url,
                      WebAppURL.isSafe(url) else {
                    return
                }
                self.onURLChange(self.slotID, url)
                self.confirmInstantBackActivation(in: webView, observedURL: url)
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
        // If Instant Back falls back to normal loading, ordinary didCommit is
        // authoritative again. A new provisional navigation also invalidates
        // any older correlation marker.
        cancelPendingInstantBack()
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        restoreWebsiteMode(in: webView)
        restoreHiddenScrollerPolicy(in: webView)
        cancelPendingInstantBack()
        // Once an https entry commits, later in-page failures can never inherit
        // the entry-only downgrade permission.
        pendingHTTPEntryFallback = nil
        onNavigationCommit(slotID)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        restoreWebsiteMode(in: webView)
        restoreHiddenScrollerPolicy(in: webView)

        if let url = webView.url, WebAppURL.isSafe(url) {
            confirmInstantBackActivation(in: webView, observedURL: url)
        }

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
        cancelPendingInstantBack()
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

    /// Called by WebKit before a back/forward transition. The request itself
    /// is not evidence that the historical page became current, so Instant
    /// Back only records the target and waits for the existing URL observation
    /// (or didFinish) to verify WebKit's current history item.
    @available(macOS 26.0, *)
    func webView(
        _ webView: WKWebView,
        shouldGoTo backForwardListItem: WKBackForwardListItem,
        willUseInstantBack: Bool,
        completionHandler: @escaping (Bool) -> Void
    ) {
        // A new request supersedes any older pending target before its own
        // transient marker is installed.
        cancelPendingInstantBack()
        if willUseInstantBack {
            pendingInstantBack = PendingInstantBack(
                targetItem: backForwardListItem,
                targetURL: backForwardListItem.url
            )
            onInstantBackRequest(slotID, backForwardListItem.url)
        }

        completionHandler(true)
    }

    /// Deterministic policy gate used by the production correlation path and
    /// by tests on runners that cannot force WebKit's Instant Back runtime.
    /// The current history-item identity remains the authority; URLs only
    /// verify that the observed WebView URL and target item agree.
    static func confirmedInstantBackURL(
        expectedItemID: ObjectIdentifier,
        currentItemID: ObjectIdentifier?,
        expectedURL: URL?,
        currentItemURL: URL?,
        observedURL: URL?
    ) -> URL? {
        guard expectedItemID == currentItemID,
              let expectedURL,
              let currentItemURL,
              let observedURL,
              WebAppURL.isSafe(currentItemURL),
              expectedURL.absoluteString == currentItemURL.absoluteString,
              currentItemURL.absoluteString == observedURL.absoluteString else {
            return nil
        }
        return currentItemURL
    }

    /// Configures one-shot fallback for the next FloatTabs-issued entry load.
    /// `allowed` must represent user-input provenance: true only when FloatTabs
    /// supplied the https scheme. Passing false also clears any stale pending
    /// permission before an explicit HTTPS, HTTP, reload-equivalent, or internal
    /// navigation is started.
    func configureHTTPEntryFallback(for url: URL, allowed: Bool) {
        pendingHTTPEntryFallback = allowed && WebAppURL.httpFallbackCandidate(for: url) != nil
            ? url
            : nil
    }

    /// Pure fallback decision: a connection-level failure of exactly the
    /// pending inferred entry URL yields the http candidate. Certificate-trust
    /// failures, other URLs, and absent pending state never downgrade.
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

    // Internal visibility keeps the deterministic history-item correlation
    // path directly testable on runners that cannot force WebKit's native
    // Instant Back callback sequence.
    func confirmInstantBackActivation(
        in webView: WKWebView,
        observedURL: URL
    ) {
        guard let pendingInstantBack,
              let currentItem = webView.backForwardList.currentItem else {
            return
        }

        guard Self.confirmedInstantBackURL(
            expectedItemID: ObjectIdentifier(pendingInstantBack.targetItem),
            currentItemID: ObjectIdentifier(currentItem),
            expectedURL: pendingInstantBack.targetURL,
            currentItemURL: currentItem.url,
            observedURL: observedURL
        ) != nil else {
            // A URL observation matching another current history item proves
            // that this request was superseded. If the observed URL is only a
            // transient value ahead of WebKit's current item, retain the marker
            // for the next authoritative observation.
            if currentItem.url.absoluteString == observedURL.absoluteString,
               currentItem !== pendingInstantBack.targetItem {
                cancelPendingInstantBack()
            }
            return
        }

        self.pendingInstantBack = nil
        onInstantBackActivation(slotID)
    }

    private func cancelPendingInstantBack() {
        guard pendingInstantBack != nil else { return }
        pendingInstantBack = nil
        onInstantBackCancellation(slotID)
    }
}
