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

struct WebRuntimeNavigationTicket: Equatable, Sendable {
    let runtimeGeneration: UInt64
    let navigationGeneration: UInt64
}

/// Transient diagnostic correlation only. It does not decide whether a
/// navigation is authoritative or alter the WebView's navigation lifecycle.
struct WebRuntimeHealthTracker {
    private(set) var runtimeGeneration: UInt64
    private(set) var latestNavigationGeneration: UInt64 = 0
    private(set) var activeTicket: WebRuntimeNavigationTicket?
    private var committedTicket: WebRuntimeNavigationTicket?
    private var lastStalledNavigationGeneration: UInt64?

    init(runtimeGeneration: UInt64) {
        self.runtimeGeneration = runtimeGeneration
    }

    var latestTicket: WebRuntimeNavigationTicket {
        WebRuntimeNavigationTicket(
            runtimeGeneration: runtimeGeneration,
            navigationGeneration: latestNavigationGeneration
        )
    }

    mutating func provisionalStarted() -> WebRuntimeNavigationTicket {
        latestNavigationGeneration &+= 1
        let ticket = WebRuntimeNavigationTicket(
            runtimeGeneration: runtimeGeneration,
            navigationGeneration: latestNavigationGeneration
        )
        activeTicket = ticket
        committedTicket = nil
        return ticket
    }

    @discardableResult
    mutating func didCommit(_ ticket: WebRuntimeNavigationTicket) -> Bool {
        guard activeTicket == ticket else { return false }
        committedTicket = ticket
        return true
    }

    @discardableResult
    mutating func didFinish(_ ticket: WebRuntimeNavigationTicket) -> Bool {
        guard activeTicket == ticket else { return false }
        activeTicket = nil
        committedTicket = nil
        return true
    }

    @discardableResult
    mutating func didFail(_ ticket: WebRuntimeNavigationTicket) -> Bool {
        guard activeTicket == ticket else { return false }
        activeTicket = nil
        committedTicket = nil
        return true
    }

    func isCommitted(_ ticket: WebRuntimeNavigationTicket) -> Bool {
        activeTicket == ticket && committedTicket == ticket
    }

    @discardableResult
    mutating func markStalled(_ ticket: WebRuntimeNavigationTicket) -> Bool {
        guard ticket.runtimeGeneration == runtimeGeneration,
              activeTicket == ticket,
              lastStalledNavigationGeneration != ticket.navigationGeneration else {
            return false
        }
        lastStalledNavigationGeneration = ticket.navigationGeneration
        return true
    }

    @discardableResult
    mutating func markActionStalled(for navigationGeneration: UInt64) -> Bool {
        guard navigationGeneration == latestNavigationGeneration,
              lastStalledNavigationGeneration != navigationGeneration else {
            return false
        }
        lastStalledNavigationGeneration = navigationGeneration
        return true
    }

    mutating func invalidateCurrentNavigation() {
        activeTicket = nil
        committedTicket = nil
    }

    mutating func replaceRuntime(with generation: UInt64) {
        runtimeGeneration = generation
        latestNavigationGeneration = 0
        activeTicket = nil
        committedTicket = nil
        lastStalledNavigationGeneration = nil
    }
}

enum WebRuntimeRendererProbeResult: Equatable, Sendable {
    case success
    case failed
    case timeout
}

struct RendererProbeTicket: Equatable, Sendable {
    let runtimeGeneration: UInt64
    let navigationGeneration: UInt64
    let probeGeneration: UInt64
}

/// Accepts at most one completion for a runtime/navigation probe ticket.
struct RendererProbeLifecycle {
    private(set) var runtimeGeneration: UInt64
    private var nextProbeGeneration: UInt64 = 0
    private var pendingTicket: RendererProbeTicket?

    init(runtimeGeneration: UInt64) {
        self.runtimeGeneration = runtimeGeneration
    }

    mutating func begin(for navigation: WebRuntimeNavigationTicket) -> RendererProbeTicket {
        nextProbeGeneration &+= 1
        let ticket = RendererProbeTicket(
            runtimeGeneration: navigation.runtimeGeneration,
            navigationGeneration: navigation.navigationGeneration,
            probeGeneration: nextProbeGeneration
        )
        pendingTicket = navigation.runtimeGeneration == runtimeGeneration ? ticket : nil
        return ticket
    }

    @discardableResult
    mutating func complete(
        _ ticket: RendererProbeTicket,
        as result: WebRuntimeRendererProbeResult
    ) -> WebRuntimeRendererProbeResult? {
        guard runtimeGeneration == ticket.runtimeGeneration,
              pendingTicket == ticket else {
            return nil
        }
        pendingTicket = nil
        return result
    }

    mutating func timeout(_ ticket: RendererProbeTicket) -> WebRuntimeRendererProbeResult? {
        complete(ticket, as: .timeout)
    }

    mutating func replaceRuntime(with generation: UInt64) {
        runtimeGeneration = generation
        pendingTicket = nil
    }

    mutating func invalidate() {
        pendingTicket = nil
    }
}

enum WebRuntimeUserAction: Equatable {
    case reload
    case home

    var diagnosticEvent: String {
        switch self {
        case .reload: "web_runtime.reload.requested"
        case .home: "web_runtime.home.requested"
        }
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
    static let navigationStallTimeout: TimeInterval = 120
    static let rendererProbeTimeout: TimeInterval = 5
    typealias JavaScriptEvaluationHandler = @MainActor @Sendable (
        WKWebView,
        String,
        @escaping @Sendable (Any?, Error?) -> Void
    ) -> Void

    typealias IncidentDiagnosticContextProvider = @MainActor (
        UUID
    ) -> [String: RuntimeDiagnosticValue]

    private enum WatchdogTarget {
        case navigation(WebRuntimeNavigationTicket)
        case userAction(
            generation: UInt64,
            action: WebRuntimeUserAction,
            navigationGenerationBefore: UInt64
        )
    }

    private weak var webView: WKWebView?
    private var observation: NSKeyValueObservation?
    private let slotID: UUID
    private let websiteMode: WebsiteMode
    private let navigationCoordinator: WebNavigationCoordinator
    private let downloadCoordinator: DownloadCoordinator
    private let onURLChange: @MainActor (UUID, URL) -> Void
    private let onContentProcessTermination: @MainActor (UUID) -> Void
    private let onNavigationCommit: @MainActor (UUID, URL?) -> Void
    private let onNavigationFinish: @MainActor (UUID, URL?) -> Void
    private let onInstantBackRequest: @MainActor (UUID, URL?) -> Void
    private let onInstantBackCancellation: @MainActor (UUID) -> Void
    private let onInstantBackActivation: @MainActor (UUID) -> Void
    private let loadHandler: @MainActor (WKWebView, URL) -> Void
    private let instantBackURLSafetyCheck: (URL) -> Bool
    private let diagnostics: any RuntimeDiagnosticRecording
    private let runtimeGeneration: UInt64
    private let isSlotActive: @MainActor (UUID) -> Bool
    private let incidentDiagnosticContextProvider: IncidentDiagnosticContextProvider
    private let javaScriptEvaluator: JavaScriptEvaluationHandler

    private var healthTracker: WebRuntimeHealthTracker
    private var rendererProbeLifecycle: RendererProbeLifecycle
    private var activeNavigationIdentifier: ObjectIdentifier?
    private var navigationStartUptime: TimeInterval?
    private var lastCommitUptime: TimeInterval?
    private var watchdogGeneration: UInt64 = 0
    private var watchdogWorkItem: DispatchWorkItem?
    private var nextUserActionGeneration: UInt64 = 0
    private var rendererProbeTimeoutWorkItem: DispatchWorkItem?

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
        onNavigationCommit: @escaping @MainActor (UUID, URL?) -> Void = { _, _ in },
        onNavigationFinish: @escaping @MainActor (UUID, URL?) -> Void = { _, _ in },
        onInstantBackRequest: @escaping @MainActor (UUID, URL?) -> Void = { _, _ in },
        onInstantBackCancellation: @escaping @MainActor (UUID) -> Void = { _ in },
        onInstantBackActivation: @escaping @MainActor (UUID) -> Void = { _ in },
        diagnostics: any RuntimeDiagnosticRecording = RuntimeDiagnosticNoopRecorder(),
        instantBackURLSafetyCheck: @escaping (URL) -> Bool = WebAppURL.isSafe,
        loadHandler: @escaping @MainActor (WKWebView, URL) -> Void = { webView, url in
            webView.load(URLRequest(url: url))
        },
        runtimeGeneration: UInt64 = 0,
        isSlotActive: @escaping @MainActor (UUID) -> Bool = { _ in false },
        incidentDiagnosticContextProvider: @escaping IncidentDiagnosticContextProvider = { _ in [:] },
        javaScriptEvaluator: @escaping JavaScriptEvaluationHandler = { webView, script, completion in
            webView.evaluateJavaScript(script, completionHandler: completion)
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
        self.onNavigationFinish = onNavigationFinish
        self.onInstantBackRequest = onInstantBackRequest
        self.onInstantBackCancellation = onInstantBackCancellation
        self.onInstantBackActivation = onInstantBackActivation
        self.diagnostics = diagnostics
        self.instantBackURLSafetyCheck = instantBackURLSafetyCheck
        self.loadHandler = loadHandler
        self.runtimeGeneration = runtimeGeneration
        self.isSlotActive = isSlotActive
        self.incidentDiagnosticContextProvider = incidentDiagnosticContextProvider
        self.javaScriptEvaluator = javaScriptEvaluator
        healthTracker = WebRuntimeHealthTracker(runtimeGeneration: runtimeGeneration)
        rendererProbeLifecycle = RendererProbeLifecycle(runtimeGeneration: runtimeGeneration)
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

    var diagnosticNavigationGeneration: UInt64 {
        healthTracker.latestNavigationGeneration
    }

    /// Called at the existing user-action boundary. This schedules only one
    /// bounded no-progress observation and never changes the requested action.
    func observeUserAction(_ action: WebRuntimeUserAction) {
        guard webView != nil else { return }
        nextUserActionGeneration &+= 1
        scheduleWatchdog(
            target: .userAction(
                generation: nextUserActionGeneration,
                action: action,
                navigationGenerationBefore: healthTracker.latestNavigationGeneration
            ),
            after: Self.navigationStallTimeout
        )
    }

    /// Called before a pooled runtime is released or replaced so no delayed
    /// observation can outlive the WKWebView it describes.
    func invalidate() {
        cancelWatchdog()
        cancelRendererProbeTimeout()
        healthTracker.invalidateCurrentNavigation()
        rendererProbeLifecycle.invalidate()
        if let webView, webView.navigationDelegate === self {
            webView.navigationDelegate = nil
        }
        observation?.invalidate()
        observation = nil
        activeNavigationIdentifier = nil
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
        cancelWatchdog()
        let navigationIdentifier = navigation.map(ObjectIdentifier.init)
        let ticket: WebRuntimeNavigationTicket
        if let navigationIdentifier,
           navigationIdentifier == activeNavigationIdentifier,
           let activeTicket = healthTracker.activeTicket {
            ticket = activeTicket
        } else {
            ticket = healthTracker.provisionalStarted()
            activeNavigationIdentifier = navigationIdentifier
            navigationStartUptime = ProcessInfo.processInfo.systemUptime
            cancelRendererProbeTimeout()
            rendererProbeLifecycle.invalidate()
        }
        diagnostics.record(
            event: "navigation.provisional_started",
            level: .info,
            subsystem: "navigation",
            fields: runtimeFields(for: webView, ticket: ticket)
        )
        scheduleWatchdog(target: .navigation(ticket), after: Self.navigationStallTimeout)
        // If Instant Back falls back to normal loading, ordinary didCommit is
        // authoritative again. A new provisional navigation also invalidates
        // any older correlation marker.
        cancelPendingInstantBack()
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        restoreWebsiteMode(in: webView)
        restoreHiddenScrollerPolicy(in: webView)
        let ticket = currentNavigationTicket(for: navigation)
        if let ticket, healthTracker.didCommit(ticket) {
            cancelWatchdog()
            lastCommitUptime = ProcessInfo.processInfo.systemUptime
            // Commit proves the provisional phase made progress, but it is not
            // a terminal navigation state. Re-arm one bounded diagnostic
            // watchdog so a committed page that never finishes can still be
            // distinguished from a healthy completed load.
            scheduleWatchdog(target: .navigation(ticket), after: Self.navigationStallTimeout)
        }
        cancelPendingInstantBack()
        // Once an https entry commits, later in-page failures can never inherit
        // the entry-only downgrade permission.
        pendingHTTPEntryFallback = nil
        var commitFields = runtimeFields(for: webView, ticket: ticket)
        commitFields["url"] = webView.url.flatMap {
            RuntimeDiagnosticPrivacy.safeURLString($0, mode: .standard)
        }.map(RuntimeDiagnosticValue.string) ?? .null
        diagnostics.record(
            event: "navigation.commit",
            level: .info,
            subsystem: "navigation",
            fields: commitFields
        )
        // At this delegate boundary WebKit's visible URL is the final
        // committed destination for this navigation. Pass it as a narrow,
        // transient commit fact; shared presentation lookup remains history
        // based and must not broaden to generic `webView.url` observation.
        onNavigationCommit(slotID, webView.url)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        restoreWebsiteMode(in: webView)
        restoreHiddenScrollerPolicy(in: webView)

        let ticket = currentNavigationTicket(for: navigation)
        if let ticket, healthTracker.didFinish(ticket) {
            cancelWatchdog()
            activeNavigationIdentifier = nil
            navigationStartUptime = nil
        }

        diagnostics.record(
            event: "navigation.finished",
            level: .info,
            subsystem: "navigation",
            fields: runtimeFields(for: webView, ticket: ticket)
        )
        if diagnostics.capturesDebugEvents {
            recordPageRuntimeProbe(in: webView)
        }

        onNavigationFinish(slotID, webView.url)

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
        let ticket = currentNavigationTicket(for: navigation)
        if let ticket, healthTracker.didFail(ticket) {
            cancelWatchdog()
            activeNavigationIdentifier = nil
            navigationStartUptime = nil
        }
        diagnostics.record(
            event: "navigation.failed",
            level: .warning,
            subsystem: "navigation",
            fields: [
                "slot_id": .string(slotID.uuidString),
                "failure": .string("navigation"),
                "provisional": .bool(false)
            ].merging(runtimeFields(for: webView, ticket: ticket)) { current, _ in current }
                .merging(RuntimeDiagnosticPrivacy.sanitizedErrorCategory(error)) { current, _ in current }
        )
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        restoreHiddenScrollerPolicy(in: webView)
        let ticket = currentNavigationTicket(for: navigation)
        if let ticket, healthTracker.didFail(ticket) {
            cancelWatchdog()
            activeNavigationIdentifier = nil
            navigationStartUptime = nil
        }
        diagnostics.record(
            event: "navigation.failed",
            level: .warning,
            subsystem: "navigation",
            fields: [
                "slot_id": .string(slotID.uuidString),
                "url": failingURLForDiagnostics(error: error, webView: webView),
                "provisional": .bool(true)
            ].merging(runtimeFields(for: webView, ticket: ticket)) { current, _ in current }
                .merging(RuntimeDiagnosticPrivacy.sanitizedErrorCategory(error)) { current, _ in current }
        )
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
            diagnostics.record(
                event: "http_entry_fallback",
                level: .debug,
                subsystem: "navigation",
                fields: ["slot_id": .string(slotID.uuidString)]
            )
            loadHandler(webView, fallback)
        } else {
            pendingHTTPEntryFallback = nil
        }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        let ticket = healthTracker.activeTicket ?? healthTracker.latestTicket
        cancelWatchdog()
        activeNavigationIdentifier = nil
        navigationStartUptime = nil
        diagnostics.record(
            event: "web_content_process_terminated",
            level: .warning,
            subsystem: "navigation",
            fields: runtimeFields(for: webView, ticket: ticket)
        )
        recordIncidentSnapshot(
            in: webView,
            ticket: ticket,
            reason: "content_process_terminated"
        )
        healthTracker.invalidateCurrentNavigation()
        onContentProcessTermination(slotID)
    }

    private func currentNavigationTicket(
        for navigation: WKNavigation!
    ) -> WebRuntimeNavigationTicket? {
        guard let activeTicket = healthTracker.activeTicket else { return nil }
        guard let navigation,
              let activeNavigationIdentifier else {
            return activeTicket
        }
        return ObjectIdentifier(navigation) == activeNavigationIdentifier
            ? activeTicket
            : nil
    }

    private func scheduleWatchdog(target: WatchdogTarget, after delay: TimeInterval) {
        cancelWatchdog()
        watchdogGeneration &+= 1
        let generation = watchdogGeneration
        let workItem = DispatchWorkItem { [weak self, weak webView] in
            Task { @MainActor [weak self, weak webView] in
                guard let self,
                      let webView,
                      self.webView === webView,
                      self.watchdogGeneration == generation else {
                    return
                }
                self.watchdogWorkItem = nil
                self.handleWatchdog(target, in: webView)
            }
        }
        watchdogWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func cancelWatchdog() {
        watchdogGeneration &+= 1
        watchdogWorkItem?.cancel()
        watchdogWorkItem = nil
    }

    private func handleWatchdog(_ target: WatchdogTarget, in webView: WKWebView) {
        switch target {
        case let .navigation(ticket):
            let navigationCommitted = healthTracker.isCommitted(ticket)
            guard healthTracker.markStalled(ticket) else { return }
            recordNavigationStall(
                in: webView,
                ticket: ticket,
                source: "navigation",
                userActionGeneration: nil,
                navigationCommitted: navigationCommitted
            )

        case let .userAction(generation, action, navigationGenerationBefore):
            guard generation == nextUserActionGeneration,
                  healthTracker.markActionStalled(for: navigationGenerationBefore) else {
                return
            }
            let ticket = WebRuntimeNavigationTicket(
                runtimeGeneration: runtimeGeneration,
                navigationGeneration: navigationGenerationBefore
            )
            recordNavigationStall(
                in: webView,
                ticket: ticket,
                source: action == .reload ? "reload" : "home",
                userActionGeneration: generation,
                navigationCommitted: nil
            )
        }
    }

    private func recordNavigationStall(
        in webView: WKWebView,
        ticket: WebRuntimeNavigationTicket,
        source: String,
        userActionGeneration: UInt64?,
        navigationCommitted: Bool?
    ) {
        var fields = runtimeFields(for: webView, ticket: ticket)
        fields["watchdog_source"] = .string(source)
        if let navigationCommitted {
            fields["navigation_committed"] = .bool(navigationCommitted)
        }
        fields["navigation_start_uptime"] = navigationStartUptime.map {
            .double($0)
        } ?? .null
        if let navigationStartUptime {
            fields["navigation_age"] = .double(
                max(0, ProcessInfo.processInfo.systemUptime - navigationStartUptime)
            )
        }
        if let lastCommitUptime {
            fields["last_commit_age"] = .double(
                max(0, ProcessInfo.processInfo.systemUptime - lastCommitUptime)
            )
        }
        if let userActionGeneration {
            fields["user_action_generation"] = .integer(Int64(userActionGeneration))
            fields["navigation_generation_before"] = .integer(
                Int64(ticket.navigationGeneration)
            )
            fields["navigation_started_after_request"] = .bool(false)
        }
        diagnostics.record(
            event: "navigation.stalled",
            level: .warning,
            subsystem: "navigation",
            fields: fields
        )
        recordIncidentSnapshot(in: webView, ticket: ticket, reason: "navigation_stalled")
        startRendererProbe(in: webView, for: ticket)
    }

    private func recordIncidentSnapshot(
        in webView: WKWebView,
        ticket: WebRuntimeNavigationTicket?,
        reason: String
    ) {
        var fields = runtimeFields(for: webView, ticket: ticket)
        let webViewWindow = webView.window
        fields["webview_exists"] = .bool(true)
        fields["is_loading"] = .bool(webView.isLoading)
        fields["estimated_progress"] = .double(webView.estimatedProgress)
        fields["webview_attached_to_superview"] = .bool(webView.superview != nil)
        fields["webview_attached_to_window"] = .bool(webViewWindow != nil)
        fields["webview_hidden"] = .bool(webView.isHidden)
        fields["frame_width"] = .double(Double(webView.frame.width))
        fields["frame_height"] = .double(Double(webView.frame.height))
        fields["bounds_width"] = .double(Double(webView.bounds.width))
        fields["bounds_height"] = .double(Double(webView.bounds.height))
        fields["webview_window_visible"] = .bool(webViewWindow?.isVisible ?? false)
        fields["webview_window_key"] = .bool(webViewWindow?.isKeyWindow ?? false)
        fields["fullscreen_state"] = .string(Self.fullscreenStateName(webView.fullscreenState))
        fields["slot_active"] = .bool(isSlotActive(slotID))
        fields["residency_policy"] = .null
        fields["pending_cold_release"] = .null
        fields["pending_warm_release"] = .null

        for (key, value) in incidentDiagnosticContextProvider(slotID) {
            fields[key] = value
        }
        diagnostics.record(
            event: "web_runtime.incident_snapshot",
            level: .warning,
            subsystem: "web",
            fields: fields.merging(["incident_reason": .string(reason)]) { current, _ in current }
        )
    }

    func startRendererProbe(
        in webView: WKWebView,
        for navigation: WebRuntimeNavigationTicket
    ) {
        cancelRendererProbeTimeout()
        let ticket = rendererProbeLifecycle.begin(for: navigation)
        let startedAt = ProcessInfo.processInfo.systemUptime

        let timeoutWorkItem = DispatchWorkItem { [weak self, weak webView] in
            Task { @MainActor [weak self, weak webView] in
                guard let self,
                      let webView,
                      self.webView === webView,
                      let result = self.rendererProbeLifecycle.timeout(ticket) else {
                    return
                }
                self.rendererProbeTimeoutWorkItem = nil
                self.recordRendererProbeResult(
                    result,
                    ticket: ticket,
                    latencyMilliseconds: self.probeLatencyMilliseconds(since: startedAt)
                )
            }
        }
        rendererProbeTimeoutWorkItem = timeoutWorkItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.rendererProbeTimeout,
            execute: timeoutWorkItem
        )

        let script = """
        (() => ({
          ready_state: document.readyState,
          visibility_state: document.visibilityState
        }))()
        """
        javaScriptEvaluator(webView, script) { [weak self, weak webView] value, error in
            Task { @MainActor [weak self, weak webView] in
                guard let self,
                      let webView,
                      self.webView === webView else {
                    return
                }
                let probe = value as? [String: Any]
                let readyState = probe?["ready_state"] as? String
                let visibilityState = probe?["visibility_state"] as? String
                let isValidResult = error == nil
                    && Self.isSafeReadyState(readyState)
                    && Self.isSafeVisibilityState(visibilityState)
                let outcome: WebRuntimeRendererProbeResult = isValidResult ? .success : .failed
                guard let result = self.rendererProbeLifecycle.complete(ticket, as: outcome) else {
                    return
                }
                self.cancelRendererProbeTimeout()
                self.recordRendererProbeResult(
                    result,
                    ticket: ticket,
                    latencyMilliseconds: self.probeLatencyMilliseconds(since: startedAt),
                    readyState: isValidResult ? readyState : nil,
                    visibilityState: isValidResult ? visibilityState : nil,
                    error: error
                )
            }
        }
    }

    private func cancelRendererProbeTimeout() {
        rendererProbeTimeoutWorkItem?.cancel()
        rendererProbeTimeoutWorkItem = nil
    }

    private func probeLatencyMilliseconds(since startedAt: TimeInterval) -> Double {
        max(0, ProcessInfo.processInfo.systemUptime - startedAt) * 1_000
    }

    private func recordRendererProbeResult(
        _ result: WebRuntimeRendererProbeResult,
        ticket: RendererProbeTicket,
        latencyMilliseconds: Double,
        readyState: String? = nil,
        visibilityState: String? = nil,
        error: Error? = nil
    ) {
        let event: String
        let level: RuntimeDiagnosticLevel
        switch result {
        case .success:
            event = "renderer_probe.success"
            level = .info
        case .failed:
            event = "renderer_probe.failed"
            level = .warning
        case .timeout:
            event = "renderer_probe.timeout"
            level = .warning
        }
        var fields: [String: RuntimeDiagnosticValue] = [
            "slot_id": .string(slotID.uuidString),
            "runtime_generation": .integer(Int64(ticket.runtimeGeneration)),
            "navigation_generation": .integer(Int64(ticket.navigationGeneration)),
            "probe_generation": .integer(Int64(ticket.probeGeneration)),
            "latency_ms": .double(latencyMilliseconds)
        ]
        if let readyState { fields["document_ready_state"] = .string(readyState) }
        if let visibilityState { fields["visibility_state"] = .string(visibilityState) }
        if let error {
            fields["error_category"] = .string(RuntimeDiagnosticPrivacy.safeErrorCategory(error))
        }
        diagnostics.record(
            event: event,
            level: level,
            subsystem: "web",
            fields: fields
        )
    }

    private static func isSafeReadyState(_ value: String?) -> Bool {
        guard let value else { return false }
        return ["loading", "interactive", "complete"].contains(value)
    }

    private static func isSafeVisibilityState(_ value: String?) -> Bool {
        guard let value else { return false }
        return ["visible", "hidden", "prerender", "unloaded"].contains(value)
    }

    private static func fullscreenStateName(_ state: WKWebView.FullscreenState) -> String {
        switch state {
        case .notInFullscreen: "not_in_fullscreen"
        case .enteringFullscreen: "entering_fullscreen"
        case .inFullscreen: "in_fullscreen"
        case .exitingFullscreen: "exiting_fullscreen"
        @unknown default: "unknown"
        }
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
            diagnostics.record(
                event: "instant_back.requested",
                level: .debug,
                subsystem: "navigation",
                fields: ["slot_id": .string(slotID.uuidString)]
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
        observedURL: URL?,
        isSafeURL: (URL) -> Bool = WebAppURL.isSafe
    ) -> URL? {
        guard expectedItemID == currentItemID,
              let expectedURL,
              let currentItemURL,
              let observedURL,
              isSafeURL(currentItemURL),
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

    private func recordPageRuntimeProbe(in webView: WKWebView) {
        let script = """
        (() => {
          const video = document.querySelector('video');
          return {
            inner_width: window.innerWidth,
            client_width: document.documentElement?.clientWidth || 0,
            inner_height: window.innerHeight,
            device_pixel_ratio: window.devicePixelRatio || 0,
            user_agent_is_mobile: /iPhone|Android/i.test(navigator.userAgent),
            video_width: video?.videoWidth || 0,
            video_height: video?.videoHeight || 0,
            video_ready_state: video?.readyState || 0,
            video_network_state: video?.networkState || 0,
            video_present: !!video
          };
        })()
        """

        webView.evaluateJavaScript(script) { [weak self, weak webView] value, error in
            Task { @MainActor [weak self, weak webView] in
                guard let self, let webView, webView === self.webView, error == nil,
                      let probe = value as? [String: Any] else {
                    return
                }

                var fields = self.runtimeFields(for: webView)
                Self.copyNumber(probe["inner_width"], to: "page_inner_width", fields: &fields)
                Self.copyNumber(probe["client_width"], to: "page_client_width", fields: &fields)
                Self.copyNumber(probe["inner_height"], to: "page_inner_height", fields: &fields)
                Self.copyNumber(
                    probe["device_pixel_ratio"],
                    to: "page_device_pixel_ratio",
                    fields: &fields
                )
                Self.copyNumber(probe["video_width"], to: "video_width", fields: &fields)
                Self.copyNumber(probe["video_height"], to: "video_height", fields: &fields)
                Self.copyInteger(
                    probe["video_ready_state"],
                    to: "video_ready_state",
                    fields: &fields
                )
                Self.copyInteger(
                    probe["video_network_state"],
                    to: "video_network_state",
                    fields: &fields
                )
                if let value = probe["user_agent_is_mobile"] as? Bool {
                    fields["page_user_agent_is_mobile"] = .bool(value)
                }
                if let value = probe["video_present"] as? Bool {
                    fields["video_present"] = .bool(value)
                }
                self.diagnostics.record(
                    event: "navigation.page_runtime_probe",
                    level: .debug,
                    subsystem: "navigation",
                    fields: fields
                )
            }
        }
    }

    private static func copyNumber(
        _ value: Any?,
        to key: String,
        fields: inout [String: RuntimeDiagnosticValue]
    ) {
        if let value = value as? NSNumber {
            fields[key] = .double(value.doubleValue)
        } else if let value = value as? Double {
            fields[key] = .double(value)
        }
    }

    private static func copyInteger(
        _ value: Any?,
        to key: String,
        fields: inout [String: RuntimeDiagnosticValue]
    ) {
        if let value = value as? NSNumber {
            fields[key] = .integer(value.int64Value)
        } else if let value = value as? Int {
            fields[key] = .integer(Int64(value))
        }
    }

    private func runtimeFields(
        for webView: WKWebView,
        ticket: WebRuntimeNavigationTicket? = nil
    ) -> [String: RuntimeDiagnosticValue] {
        let contentMode: String = switch webView.configuration.defaultWebpagePreferences.preferredContentMode {
        case .desktop: "desktop"
        case .mobile: "mobile"
        case .recommended: "recommended"
        @unknown default: "unknown"
        }
        let websiteMode = (webView as? FloatTabsWebView)?.websiteMode.rawValue
            ?? contentMode
        let customUserAgent = webView.customUserAgent
        return [
            "slot_id": .string(slotID.uuidString),
            "runtime_generation": .integer(Int64(runtimeGeneration)),
            "navigation_generation": ticket.map {
                .integer(Int64($0.navigationGeneration))
            } ?? .null,
            "website_mode": .string(websiteMode),
            "preferred_content_mode": .string(contentMode),
            "custom_user_agent_present": .bool(customUserAgent?.isEmpty == false),
            "custom_user_agent_is_mobile": .bool(
                customUserAgent?.localizedCaseInsensitiveContains("iPhone") == true
                    || customUserAgent?.localizedCaseInsensitiveContains("Android") == true
            ),
            "page_zoom": .double(Double(webView.pageZoom))
        ]
    }

    private func failingURLForDiagnostics(
        error: Error,
        webView: WKWebView
    ) -> RuntimeDiagnosticValue {
        let errorURL = ((error as NSError).userInfo["NSErrorFailingURLStringKey"] as? String)
            .flatMap(URL.init(string:))
        let url = errorURL ?? webView.url
        return url.flatMap {
            RuntimeDiagnosticPrivacy.safeURLString($0, mode: .standard)
        }.map(RuntimeDiagnosticValue.string) ?? .null
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
            observedURL: observedURL,
            isSafeURL: instantBackURLSafetyCheck
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
        diagnostics.record(
            event: "instant_back.activated",
            level: .debug,
            subsystem: "navigation",
            fields: ["slot_id": .string(slotID.uuidString)]
        )
        onInstantBackActivation(slotID)
    }

    private func cancelPendingInstantBack() {
        guard pendingInstantBack != nil else { return }
        pendingInstantBack = nil
        diagnostics.record(
            event: "instant_back.cancelled",
            level: .debug,
            subsystem: "navigation",
            fields: ["slot_id": .string(slotID.uuidString)]
        )
        onInstantBackCancellation(slotID)
    }
}
