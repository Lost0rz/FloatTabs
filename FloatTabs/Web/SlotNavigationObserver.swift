import AppKit
import Darwin
import Foundation
import WebKit

struct RendererProbeValues: Equatable, Sendable {
    let readyState: String
    let visibilityState: String
}

typealias RendererJavaScriptEvaluator = @MainActor (
    WKWebView,
    String
) async throws -> RendererProbeValues

enum WebRuntimeLivenessWorld: String, Equatable, Hashable, Sendable {
    case mainPage = "main_page"
    case floatTabsIsolated = "floattabs_isolated"
}

enum WebRuntimeLivenessOutcome: String, Equatable, Sendable {
    case success
    case timeout
    case failed
    case stale
    case suppressed
}

struct WebRuntimeLivenessProbeResult: Equatable, Sendable {
    let outcome: WebRuntimeLivenessOutcome
    let readyState: String?
    let visibilityState: String?
    let latencyMilliseconds: Double

    static func success(
        readyState: String,
        visibilityState: String,
        latencyMilliseconds: Double
    ) -> Self {
        Self(
            outcome: .success,
            readyState: readyState,
            visibilityState: visibilityState,
            latencyMilliseconds: latencyMilliseconds
        )
    }

    static func terminal(
        _ outcome: WebRuntimeLivenessOutcome,
        latencyMilliseconds: Double
    ) -> Self {
        Self(
            outcome: outcome,
            readyState: nil,
            visibilityState: nil,
            latencyMilliseconds: latencyMilliseconds
        )
    }

    var stale: Self {
        .terminal(.stale, latencyMilliseconds: latencyMilliseconds)
    }

    func diagnosticFields(prefix: String) -> [String: RuntimeDiagnosticValue] {
        [
            "\(prefix)_probe_outcome": .string(outcome.rawValue),
            "\(prefix)_probe_latency_ms": .double(min(max(latencyMilliseconds, 0), 5_000)),
            "\(prefix)_document_ready_state": readyState.map(RuntimeDiagnosticValue.string) ?? .null,
            "\(prefix)_document_visibility_state": visibilityState.map(RuntimeDiagnosticValue.string) ?? .null
        ]
    }
}

enum WebRuntimeResponsivenessOutcome: String, Equatable, Sendable {
    case success
    case timeout
    case failed
    case stale
    case suppressed
    case notRun = "not_run"
    case notVisible = "not_visible"
}

enum WebRuntimeFrameCallbackOutcome: String, Equatable, Sendable {
    case sampled
    case notVisible = "not_visible"
    case unavailable
    case measurementWindowElapsed = "measurement_window_elapsed"
}

struct WebRuntimeResponsivenessProbeResult: Equatable, Sendable {
    let outcome: WebRuntimeResponsivenessOutcome
    let probeLatencyMilliseconds: Double
    let eventLoopSchedulingLatencyMilliseconds: Double?
    let frameCallbackOutcome: WebRuntimeFrameCallbackOutcome?
    let frameCallbackLatencyMilliseconds: Double?

    static func success(
        probeLatencyMilliseconds: Double,
        eventLoopSchedulingLatencyMilliseconds: Double,
        frameCallbackOutcome: WebRuntimeFrameCallbackOutcome,
        frameCallbackLatencyMilliseconds: Double?
    ) -> Self {
        Self(
            outcome: .success,
            probeLatencyMilliseconds: probeLatencyMilliseconds,
            eventLoopSchedulingLatencyMilliseconds: eventLoopSchedulingLatencyMilliseconds,
            frameCallbackOutcome: frameCallbackOutcome,
            frameCallbackLatencyMilliseconds: frameCallbackLatencyMilliseconds
        )
    }

    static func terminal(
        _ outcome: WebRuntimeResponsivenessOutcome,
        probeLatencyMilliseconds: Double
    ) -> Self {
        Self(
            outcome: outcome,
            probeLatencyMilliseconds: probeLatencyMilliseconds,
            eventLoopSchedulingLatencyMilliseconds: nil,
            frameCallbackOutcome: nil,
            frameCallbackLatencyMilliseconds: nil
        )
    }

    static func notVisible() -> Self {
        Self(
            outcome: .notVisible,
            probeLatencyMilliseconds: 0,
            eventLoopSchedulingLatencyMilliseconds: nil,
            frameCallbackOutcome: .notVisible,
            frameCallbackLatencyMilliseconds: nil
        )
    }

    static func notRun() -> Self {
        terminal(.notRun, probeLatencyMilliseconds: 0)
    }

    var stale: Self {
        .terminal(.stale, probeLatencyMilliseconds: probeLatencyMilliseconds)
    }

    func diagnosticFields() -> [String: RuntimeDiagnosticValue] {
        [
            "main_world_responsiveness_probe_outcome": .string(outcome.rawValue),
            "main_world_responsiveness_probe_latency_ms": .double(
                Self.bounded(probeLatencyMilliseconds)
            ),
            "main_world_event_loop_schedule_latency_ms": eventLoopSchedulingLatencyMilliseconds
                .map { .double(Self.bounded($0)) } ?? .null,
            "main_world_frame_callback_outcome": frameCallbackOutcome.map {
                .string($0.rawValue)
            } ?? .null,
            "main_world_frame_callback_latency_ms": frameCallbackLatencyMilliseconds
                .map { .double(Self.bounded($0)) } ?? .null
        ]
    }

    private static func bounded(_ value: Double) -> Double {
        min(max(value.isFinite ? value : 0, 0), 5_000)
    }
}

typealias WebRuntimeLivenessProbeEvaluator = @MainActor (
    WKWebView,
    WebRuntimeLivenessWorld
) async -> WebRuntimeLivenessProbeResult

typealias WebRuntimeResponsivenessProbeEvaluator = @MainActor (
    WKWebView,
    Bool
) async -> WebRuntimeResponsivenessProbeResult

@MainActor
final class WebRuntimeLivenessRequestBudget {
    static let maximumPendingRequestsPerWorld = 2

    private var pendingRequestIDs: [WebRuntimeLivenessWorld: Set<UUID>] = [:]

    func reserve(_ world: WebRuntimeLivenessWorld) -> UUID? {
        var requestIDs = pendingRequestIDs[world, default: []]
        guard requestIDs.count < Self.maximumPendingRequestsPerWorld else { return nil }
        let requestID = UUID()
        requestIDs.insert(requestID)
        pendingRequestIDs[world] = requestIDs
        return requestID
    }

    func complete(_ requestID: UUID, in world: WebRuntimeLivenessWorld) {
        guard var requestIDs = pendingRequestIDs[world] else { return }
        requestIDs.remove(requestID)
        pendingRequestIDs[world] = requestIDs
    }

    func pendingCount(in world: WebRuntimeLivenessWorld) -> Int {
        pendingRequestIDs[world]?.count ?? 0
    }
}

@MainActor
private final class WebRuntimeProbeGate<Value> {
    private var continuation: CheckedContinuation<Value, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var finished = false

    func install(_ continuation: CheckedContinuation<Value, Never>) {
        self.continuation = continuation
    }

    func installTimeoutTask(_ task: Task<Void, Never>) {
        timeoutTask = task
    }

    func finish(_ result: Value) {
        guard !finished else { return }
        finished = true
        timeoutTask?.cancel()
        timeoutTask = nil
        let continuation = self.continuation
        self.continuation = nil
        continuation?.resume(returning: result)
    }
}

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
    private enum DiagnosticNavigationPhase: String {
        case provisional
        case postCommit = "post_commit"
        case finished
        case failed
        case terminated
    }

    private struct DiagnosticNavigationTicket {
        let navigationID: ObjectIdentifier
        let generation: UInt64
        var phase: DiagnosticNavigationPhase
        var didEmitStall: Bool
    }

    private weak var webView: WKWebView?
    private var observation: NSKeyValueObservation?
    private let slotID: UUID
    private let runtimeDiagnosticIdentity: WebRuntimeDiagnosticIdentity?
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
    private let navigationStallTimeout: TimeInterval
    private let rendererProbeTimeout: TimeInterval
    private let rendererJavaScriptEvaluator: RendererJavaScriptEvaluator?
    private let livenessProbeEvaluator: WebRuntimeLivenessProbeEvaluator
    private let responsivenessProbeEvaluator: WebRuntimeResponsivenessProbeEvaluator
    private let livenessProbeIntervalNanoseconds: UInt64
    private var nextNavigationGeneration: UInt64 = 0
    private var currentNavigationTicket: DiagnosticNavigationTicket?
    /// Public WebKit does not expose a stable child-process identifier. This
    /// epoch advances only when FloatTabs observes the documented termination
    /// callback; it is correlation evidence, not proof of every process swap.
    private var observedContentProcessEpoch: UInt64 = 1
    private var observedContentProcessTerminationCount: UInt64 = 0
    private var navigationStallTask: Task<Void, Never>?
    private var pendingRendererProbeID: UUID?
    private var rendererProbeTimeoutTask: Task<Void, Never>?
    private var rendererProbeStartedAt: TimeInterval?
    private var rendererProbeTrigger: String?
    private var rendererProbeIncidentID: UUID?
    private var rendererProbeCompletion: (@MainActor (String) -> Void)?
    private var livenessObservationTask: Task<Void, Never>?
    private var livenessContextGeneration: UInt64 = 1
    private var consecutivePostFinishDualTimeouts = 0

    static let defaultCrossWorldLivenessInterval: TimeInterval = 30
    static let defaultCrossWorldLivenessTimeout: TimeInterval = 5
    static let postFinishStallConfirmationCount = 2

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
        runtimeDiagnosticIdentity: WebRuntimeDiagnosticIdentity? = nil,
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
        navigationStallTimeout: TimeInterval = 120,
        rendererProbeTimeout: TimeInterval = 5,
        rendererJavaScriptEvaluator: RendererJavaScriptEvaluator? = nil,
        crossWorldLivenessInterval: TimeInterval = SlotNavigationObserver.defaultCrossWorldLivenessInterval,
        crossWorldLivenessTimeout: TimeInterval = SlotNavigationObserver.defaultCrossWorldLivenessTimeout,
        livenessProbeEvaluator: WebRuntimeLivenessProbeEvaluator? = nil,
        responsivenessProbeEvaluator: WebRuntimeResponsivenessProbeEvaluator? = nil,
        instantBackURLSafetyCheck: @escaping (URL) -> Bool = WebAppURL.isSafe,
        loadHandler: @escaping @MainActor (WKWebView, URL) -> Void = { webView, url in
            webView.load(URLRequest(url: url))
        }
    ) {
        self.slotID = slotID
        self.webView = webView
        self.runtimeDiagnosticIdentity = runtimeDiagnosticIdentity
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
        self.navigationStallTimeout = max(0, navigationStallTimeout)
        self.rendererProbeTimeout = max(0, rendererProbeTimeout)
        self.rendererJavaScriptEvaluator = rendererJavaScriptEvaluator
        let normalizedLivenessInterval = min(max(crossWorldLivenessInterval, 1), 300)
        let normalizedLivenessTimeout = min(max(crossWorldLivenessTimeout, 0.1), 5)
        livenessProbeIntervalNanoseconds = UInt64(normalizedLivenessInterval * 1_000_000_000)
        let livenessProbeRequestBudget = WebRuntimeLivenessRequestBudget()
        self.responsivenessProbeEvaluator = responsivenessProbeEvaluator ?? { webView, shouldMeasureFrame in
            await Self.productionResponsivenessProbe(
                webView: webView,
                shouldMeasureFrame: shouldMeasureFrame,
                timeout: normalizedLivenessTimeout,
                requestBudget: livenessProbeRequestBudget
            )
        }
        self.livenessProbeEvaluator = livenessProbeEvaluator ?? { webView, world in
            await Self.productionLivenessProbe(
                webView: webView,
                world: world,
                timeout: normalizedLivenessTimeout,
                requestBudget: livenessProbeRequestBudget
            )
        }
        self.instantBackURLSafetyCheck = instantBackURLSafetyCheck
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
        startCrossWorldLivenessObservation(for: webView)
    }

    deinit {
        observation?.invalidate()
        livenessObservationTask?.cancel()
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
        let ticket = navigation.map(beginDiagnosticNavigation)
        let callbackFields = ticket.map(navigationFields(for:)) ?? staleNavigationFields
        diagnostics.record(
            event: "navigation.provisional_started",
            level: .debug,
            subsystem: "navigation",
            fields: runtimeFields(for: webView).merging(callbackFields) { _, new in new }
        )
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
        let ticket = navigation.flatMap(commitDiagnosticNavigation)
        var commitFields = runtimeFields(for: webView).merging(
            ticket.map(navigationFields(for:)) ?? staleNavigationFields
        ) { _, new in new }
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

        let ticket = navigation.flatMap { completeDiagnosticNavigation($0, phase: .finished) }

        diagnostics.record(
            event: "navigation.finished",
            level: .debug,
            subsystem: "navigation",
            fields: runtimeFields(for: webView).merging(
                ticket.map(navigationFields(for:)) ?? staleNavigationFields
            ) { _, new in new }
        )

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
        let ticket = navigation.flatMap { completeDiagnosticNavigation($0, phase: .failed) }
        diagnostics.record(
            event: "navigation.failed",
            level: .warning,
            subsystem: "navigation",
            fields: runtimeFields(for: webView).merging([
                "slot_id": .string(slotID.uuidString),
                "failure": .string("navigation"),
                "provisional": .bool(false)
            ]) { _, new in new }
                .merging(RuntimeDiagnosticPrivacy.sanitizedErrorCategory(error)) { current, _ in current }
                .merging(ticket.map(navigationFields(for:)) ?? staleNavigationFields) { _, new in new }
        )
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        restoreHiddenScrollerPolicy(in: webView)
        let ticket = navigation.flatMap { completeDiagnosticNavigation($0, phase: .failed) }
        diagnostics.record(
            event: "navigation.failed",
            level: .warning,
            subsystem: "navigation",
            fields: runtimeFields(for: webView).merging([
                "slot_id": .string(slotID.uuidString),
                "url": failingURLForDiagnostics(error: error, webView: webView),
                "provisional": .bool(true)
            ]) { _, new in new }
                .merging(RuntimeDiagnosticPrivacy.sanitizedErrorCategory(error)) { current, _ in current }
                .merging(ticket.map(navigationFields(for:)) ?? staleNavigationFields) { _, new in new }
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
        advanceObservedContentProcessEpoch()
        consecutivePostFinishDualTimeouts = 0
        invalidateDiagnosticNavigation(phase: .terminated)
        diagnostics.record(
            event: "web_content_process_terminated",
            level: .warning,
            subsystem: "navigation",
            fields: runtimeFields(for: webView)
        )
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

    func invalidateDiagnosticNavigation() {
        livenessObservationTask?.cancel()
        livenessObservationTask = nil
        if livenessContextGeneration < UInt64.max {
            livenessContextGeneration += 1
        }
        consecutivePostFinishDualTimeouts = 0
        invalidateDiagnosticNavigation(phase: nil)
    }

    var currentNavigationDiagnosticFields: [String: RuntimeDiagnosticValue] {
        guard let currentNavigationTicket else { return [:] }
        return navigationFields(for: currentNavigationTicket)
    }

    var currentDiagnosticNavigationGeneration: UInt64? {
        currentNavigationTicket?.generation
    }

    var currentContentProcessDiagnosticFields: [String: RuntimeDiagnosticValue] {
        [
            "observed_web_process_epoch": Self.diagnosticInteger(observedContentProcessEpoch),
            "observed_web_process_termination_count": Self.diagnosticInteger(
                observedContentProcessTerminationCount
            )
        ]
    }

    var currentRuntimeCorrelationFields: [String: RuntimeDiagnosticValue] {
        var fields: [String: RuntimeDiagnosticValue] = [
            "slot_id": .string(slotID.uuidString)
        ]
        fields.merge(runtimeDiagnosticIdentity?.fields ?? [:]) { current, _ in current }
        let navigationFields = currentNavigationDiagnosticFields
        fields.merge(navigationFields.isEmpty ? [
            "navigation_generation": RuntimeDiagnosticValue.null,
            "navigation_phase": .string("none"),
            "navigation_callback_stale": .bool(false)
        ] : navigationFields) { current, _ in current }
        fields.merge(currentContentProcessDiagnosticFields) { current, _ in current }
        return fields
    }

    /// Captures one bounded main-page-world + FloatTabs-isolated-world sample.
    /// This is evidence only: it never reloads, rebuilds, releases, or mutates
    /// persistent site/profile data.
    func captureCrossWorldLivenessOnce() async {
        guard let webView,
              let url = webView.url,
              ChatGPTSitePolicy.isSupportedChatGPTURL(url) else {
            return
        }

        let expectedContextGeneration = livenessContextGeneration
        let expectedNavigationGeneration = currentNavigationTicket?.generation
        let expectedNavigationPhase = currentNavigationTicket?.phase
        let startedAt = ProcessInfo.processInfo.systemUptime

        async let mainRaw = livenessProbeEvaluator(webView, .mainPage)
        async let isolatedRaw = livenessProbeEvaluator(webView, .floatTabsIsolated)
        let (mainCaptured, isolatedCaptured) = await (mainRaw, isolatedRaw)

        let contextAfterLiveness = self.webView === webView
            && livenessContextGeneration == expectedContextGeneration
            && currentNavigationTicket?.generation == expectedNavigationGeneration
            && currentNavigationTicket?.phase == expectedNavigationPhase
        let responsivenessCaptured: WebRuntimeResponsivenessProbeResult
        if !contextAfterLiveness {
            responsivenessCaptured = .terminal(.stale, probeLatencyMilliseconds: 0)
        } else if mainCaptured.outcome != .success {
            responsivenessCaptured = .notRun()
        } else {
            let pageVisible = mainCaptured.visibilityState == "visible"
            let nativeVisible = !webView.isHidden && webView.window?.isVisible == true
            if pageVisible && nativeVisible {
                responsivenessCaptured = await responsivenessProbeEvaluator(
                    webView,
                    true
                )
            } else {
                responsivenessCaptured = .notVisible()
            }
        }

        let runtimeContextCurrent = self.webView === webView
            && livenessContextGeneration == expectedContextGeneration
            && currentNavigationTicket?.generation == expectedNavigationGeneration
            && currentNavigationTicket?.phase == expectedNavigationPhase
        let main = runtimeContextCurrent ? mainCaptured : mainCaptured.stale
        let isolated = runtimeContextCurrent ? isolatedCaptured : isolatedCaptured.stale
        let responsiveness = runtimeContextCurrent
            ? responsivenessCaptured
            : responsivenessCaptured.stale
        let navigationFinished = currentNavigationTicket?.phase == .finished
        let nativeFinishedFacts = !webView.isLoading && webView.estimatedProgress >= 0.999
        let postFinishBoundary = runtimeContextCurrent && navigationFinished && nativeFinishedFacts
        let dualTimeout = main.outcome == .timeout && isolated.outcome == .timeout

        if postFinishBoundary && dualTimeout {
            consecutivePostFinishDualTimeouts += 1
        } else {
            consecutivePostFinishDualTimeouts = 0
        }

        var fields = runtimeFields(for: webView)
        fields.merge(main.diagnosticFields(prefix: "main_world")) { _, new in new }
        fields.merge(isolated.diagnosticFields(prefix: "isolated_world")) { _, new in new }
        fields.merge(responsiveness.diagnosticFields()) { _, new in new }
        fields.merge([
            "runtime_context_current": .bool(runtimeContextCurrent),
            "navigation_finished": .bool(navigationFinished),
            "native_finished_facts": .bool(nativeFinishedFacts),
            "is_loading": .bool(webView.isLoading),
            "estimated_progress": .double(webView.estimatedProgress),
            "webview_hidden": .bool(webView.isHidden),
            "webview_window_visible": .bool(webView.window?.isVisible == true),
            "post_finish_dual_timeout_count": .integer(Int64(consecutivePostFinishDualTimeouts)),
            "probe_cycle_latency_ms": .double(
                min(max(ProcessInfo.processInfo.systemUptime - startedAt, 0) * 1_000, 10_000)
            ),
            "system_physical_memory_bytes": Self.diagnosticInteger(ProcessInfo.processInfo.physicalMemory),
            "web_process_resource_attribution": .string("unavailable_public_api")
        ]) { _, new in new }
        if let residentSize = Self.currentProcessResidentSizeBytes() {
            fields["host_resident_size_bytes"] = Self.diagnosticInteger(residentSize)
        } else {
            fields["host_resident_size_bytes"] = .null
        }

        diagnostics.record(
            event: "web_runtime.cross_world_liveness",
            level: dualTimeout ? .warning : .notice,
            subsystem: "web",
            fields: fields
        )

        guard postFinishBoundary, dualTimeout else { return }
        var stallFields = fields
        stallFields["stall_class"] = .string("POST_FINISH_RUNTIME_STALL")
        stallFields["stall_confirmation_state"] = .string(
            consecutivePostFinishDualTimeouts >= Self.postFinishStallConfirmationCount
                ? "confirmed"
                : "candidate"
        )
        diagnostics.record(
            event: consecutivePostFinishDualTimeouts >= Self.postFinishStallConfirmationCount
                ? "web_runtime.post_finish_stall_detected"
                : "web_runtime.post_finish_stall_candidate",
            level: .warning,
            subsystem: "web",
            fields: stallFields
        )
    }

    private var staleNavigationFields: [String: RuntimeDiagnosticValue] {
        [
            "navigation_generation": .null,
            "navigation_phase": .null,
            "navigation_callback_stale": .bool(true)
        ]
    }

    private func navigationFields(
        for ticket: DiagnosticNavigationTicket
    ) -> [String: RuntimeDiagnosticValue] {
        [
            "navigation_generation": .integer(Int64(ticket.generation)),
            "navigation_phase": .string(ticket.phase.rawValue),
            "navigation_callback_stale": .bool(false)
        ]
    }

    private func beginDiagnosticNavigation(
        _ navigation: WKNavigation
    ) -> DiagnosticNavigationTicket {
        let navigationID = ObjectIdentifier(navigation)
        if let currentNavigationTicket,
           currentNavigationTicket.navigationID == navigationID {
            return currentNavigationTicket
        }

        invalidateDiagnosticNavigation(phase: nil)
        consecutivePostFinishDualTimeouts = 0
        precondition(nextNavigationGeneration < UInt64.max, "Navigation diagnostic generation exhausted")
        nextNavigationGeneration += 1
        let ticket = DiagnosticNavigationTicket(
            navigationID: navigationID,
            generation: nextNavigationGeneration,
            phase: .provisional,
            didEmitStall: false
        )
        currentNavigationTicket = ticket
        scheduleStallWatchdog(for: ticket)
        return ticket
    }

    private func commitDiagnosticNavigation(
        _ navigation: WKNavigation
    ) -> DiagnosticNavigationTicket? {
        guard var ticket = matchingActiveTicket(for: navigation) else { return nil }
        if ticket.phase == .provisional {
            ticket.phase = .postCommit
            currentNavigationTicket = ticket
            scheduleStallWatchdog(for: ticket)
        }
        return ticket
    }

    private func completeDiagnosticNavigation(
        _ navigation: WKNavigation,
        phase: DiagnosticNavigationPhase
    ) -> DiagnosticNavigationTicket? {
        guard var ticket = matchingActiveTicket(for: navigation) else { return nil }
        ticket.phase = phase
        currentNavigationTicket = ticket
        cancelNavigationStallWatchdog()
        invalidateRendererProbe()
        return ticket
    }

    private func matchingActiveTicket(
        for navigation: WKNavigation
    ) -> DiagnosticNavigationTicket? {
        guard let ticket = currentNavigationTicket,
              ticket.navigationID == ObjectIdentifier(navigation),
              ticket.phase != .finished,
              ticket.phase != .failed,
              ticket.phase != .terminated else {
            return nil
        }
        return ticket
    }

    private func invalidateDiagnosticNavigation(phase: DiagnosticNavigationPhase?) {
        cancelNavigationStallWatchdog()
        invalidateRendererProbe()
        guard var ticket = currentNavigationTicket else { return }
        if let phase {
            ticket.phase = phase
            currentNavigationTicket = ticket
        } else {
            currentNavigationTicket = nil
        }
    }

    private func scheduleStallWatchdog(for ticket: DiagnosticNavigationTicket) {
        cancelNavigationStallWatchdog()
        let delay = UInt64(navigationStallTimeout * 1_000_000_000)
        navigationStallTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: delay)
            } catch {
                return
            }
            self?.fireDiagnosticStallWatchdog(
                navigationID: ticket.navigationID,
                generation: ticket.generation,
                phase: ticket.phase.rawValue
            )
        }
    }

    func fireDiagnosticStallWatchdog(
        navigationID: ObjectIdentifier,
        generation: UInt64,
        phase: String
    ) {
        guard let webView = self.webView,
              var current = currentNavigationTicket,
              current.navigationID == navigationID,
              current.generation == generation,
              current.phase.rawValue == phase,
              !current.didEmitStall else {
            return
        }

        current.didEmitStall = true
        currentNavigationTicket = current
        navigationStallTask = nil
        var fields = runtimeFields(for: webView)
        fields.merge(navigationFields(for: current)) { _, new in new }
        fields["stall_class"] = .string(
            current.phase == .provisional
                ? "PRE_COMMIT_NAVIGATION_STALL"
                : "POST_COMMIT_NAVIGATION_STALL"
        )
        fields["is_loading"] = .bool(webView.isLoading)
        fields["estimated_progress"] = .double(webView.estimatedProgress)
        fields["origin"] = webView.url.flatMap {
            RuntimeDiagnosticPrivacy.safeURLString($0, mode: .standard)
        }.map(RuntimeDiagnosticValue.string) ?? .null
        diagnostics.record(
            event: "navigation.stall_detected",
            level: .warning,
            subsystem: "navigation",
            fields: fields
        )
        startRendererProbe(trigger: "stall", incidentID: nil, completion: nil)
    }

    func captureBoundedRendererProbe(
        incidentID: UUID,
        completion: @escaping @MainActor (String) -> Void
    ) {
        startRendererProbe(
            trigger: "qa_incident_capture",
            incidentID: incidentID,
            completion: completion
        )
    }

    private static let rendererProbeScript =
        "(() => ({ ready_state: document.readyState, visibility_state: document.visibilityState }))()"

    private func startRendererProbe(
        trigger: String,
        incidentID: UUID?,
        completion: (@MainActor (String) -> Void)?
    ) {
        guard let webView else {
            completion?("failed")
            return
        }

        invalidateRendererProbe()
        let probeID = UUID()
        let expectedNavigationGeneration = currentNavigationTicket?.generation
        let expectedRuntimeIdentity = runtimeDiagnosticIdentity
        let startedAt = ProcessInfo.processInfo.systemUptime
        pendingRendererProbeID = probeID
        rendererProbeStartedAt = startedAt
        rendererProbeTrigger = trigger
        rendererProbeIncidentID = incidentID
        rendererProbeCompletion = completion

        let timeout = UInt64(rendererProbeTimeout * 1_000_000_000)
        rendererProbeTimeoutTask = Task { @MainActor [weak self, weak webView] in
            do {
                try await Task.sleep(nanoseconds: timeout)
            } catch {
                return
            }
            guard let self, let webView else { return }
            self.finishRendererProbe(
                id: probeID,
                webView: webView,
                expectedRuntimeIdentity: expectedRuntimeIdentity,
                expectedNavigationGeneration: expectedNavigationGeneration,
                outcome: .timeout
            )
        }

        Task { @MainActor [weak self, weak webView] in
            guard let self, let webView else { return }
            do {
                let values: RendererProbeValues
                if let evaluator = self.rendererJavaScriptEvaluator {
                    values = try await evaluator(webView, Self.rendererProbeScript)
                } else {
                    let result = try await webView.evaluateJavaScript(Self.rendererProbeScript)
                    guard let fields = result as? [String: Any],
                          let readyState = fields["ready_state"] as? String,
                          let visibilityState = fields["visibility_state"] as? String else {
                        self.finishRendererProbe(
                            id: probeID,
                            webView: webView,
                            expectedRuntimeIdentity: expectedRuntimeIdentity,
                            expectedNavigationGeneration: expectedNavigationGeneration,
                            outcome: .failed
                        )
                        return
                    }
                    values = RendererProbeValues(
                        readyState: readyState,
                        visibilityState: visibilityState
                    )
                }

                guard Self.isAllowed(values) else {
                    self.finishRendererProbe(
                        id: probeID,
                        webView: webView,
                        expectedRuntimeIdentity: expectedRuntimeIdentity,
                        expectedNavigationGeneration: expectedNavigationGeneration,
                        outcome: .failed
                    )
                    return
                }
                self.finishRendererProbe(
                    id: probeID,
                    webView: webView,
                    expectedRuntimeIdentity: expectedRuntimeIdentity,
                    expectedNavigationGeneration: expectedNavigationGeneration,
                    outcome: .success(values)
                )
            } catch {
                self.finishRendererProbe(
                    id: probeID,
                    webView: webView,
                    expectedRuntimeIdentity: expectedRuntimeIdentity,
                    expectedNavigationGeneration: expectedNavigationGeneration,
                    outcome: .failed
                )
            }
        }
    }

    private enum RendererProbeOutcome {
        case success(RendererProbeValues)
        case failed
        case timeout

        var result: String {
            switch self {
            case .success: "success"
            case .failed: "failed"
            case .timeout: "timeout"
            }
        }
    }

    private static func isAllowed(_ values: RendererProbeValues) -> Bool {
        ["loading", "interactive", "complete"].contains(values.readyState)
            && ["visible", "hidden", "prerender", "unloaded"].contains(values.visibilityState)
    }

    private func finishRendererProbe(
        id: UUID,
        webView: WKWebView,
        expectedRuntimeIdentity: WebRuntimeDiagnosticIdentity?,
        expectedNavigationGeneration: UInt64?,
        outcome: RendererProbeOutcome
    ) {
        guard pendingRendererProbeID == id else { return }
        guard self.webView === webView,
              runtimeDiagnosticIdentity == expectedRuntimeIdentity,
              currentNavigationTicket?.generation == expectedNavigationGeneration else {
            invalidateRendererProbe()
            return
        }

        rendererProbeTimeoutTask?.cancel()
        rendererProbeTimeoutTask = nil
        pendingRendererProbeID = nil
        let completion = rendererProbeCompletion
        rendererProbeCompletion = nil

        var fields = runtimeFields(for: webView)
        fields["probe_trigger"] = .string(rendererProbeTrigger ?? "unknown")
        fields["probe_result"] = .string(outcome.result)
        let startedAt = rendererProbeStartedAt ?? ProcessInfo.processInfo.systemUptime
        fields["probe_latency_ms"] = .double(
            max(0, ProcessInfo.processInfo.systemUptime - startedAt) * 1_000
        )
        if let rendererProbeIncidentID {
            fields["incident_id"] = .string(rendererProbeIncidentID.uuidString)
        }
        if case let .success(values) = outcome {
            fields["document_ready_state"] = .string(values.readyState)
            fields["document_visibility_state"] = .string(values.visibilityState)
        }
        diagnostics.record(
            event: "navigation.renderer_probe",
            level: .notice,
            subsystem: "navigation",
            fields: fields
        )
        rendererProbeStartedAt = nil
        rendererProbeTrigger = nil
        rendererProbeIncidentID = nil
        completion?(outcome.result)
    }

    private func invalidateRendererProbe() {
        rendererProbeTimeoutTask?.cancel()
        rendererProbeTimeoutTask = nil
        pendingRendererProbeID = nil
        rendererProbeStartedAt = nil
        rendererProbeTrigger = nil
        rendererProbeIncidentID = nil
        let completion = rendererProbeCompletion
        rendererProbeCompletion = nil
        completion?("discarded")
    }

    private func cancelNavigationStallWatchdog() {
        navigationStallTask?.cancel()
        navigationStallTask = nil
    }

    private func startCrossWorldLivenessObservation(for webView: WKWebView) {
        livenessObservationTask?.cancel()
        livenessObservationTask = Task { @MainActor [weak self, weak webView] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: self?.livenessProbeIntervalNanoseconds ?? 0)
                } catch {
                    return
                }
                guard let self, let webView, self.webView === webView else { return }
                await self.captureCrossWorldLivenessOnce()
            }
        }
    }

    private static let runtimeLivenessProbeScript = """
    (() => ({
      ready_state: ["loading", "interactive", "complete"].includes(document.readyState)
        ? document.readyState : "other",
      visibility_state: ["visible", "hidden", "prerender", "unloaded"].includes(document.visibilityState)
        ? document.visibilityState : "other"
    }))()
    """

    /// Maximum wait for one frame callback; this is a measurement bound, not a degraded threshold.
    private static let frameCallbackMeasurementWindowMilliseconds = 4_000

    private static let runtimeResponsivenessProbeScript = """
    const eventLoopStartedAt = performance.now();
    await new Promise(resolve => setTimeout(resolve, 0));
    const eventLoopScheduleLatency = performance.now() - eventLoopStartedAt;

    let frameCallbackOutcome = "not_visible";
    let frameCallbackLatency = null;
    if (shouldMeasureFrame && document.visibilityState === "visible") {
      if (typeof requestAnimationFrame !== "function") {
        frameCallbackOutcome = "unavailable";
      } else {
        const frameStartedAt = performance.now();
        const frameResult = await new Promise(resolve => {
          let completed = false;
          let frameRequestID = null;
          const measurementTimerID = setTimeout(() => {
            if (completed) return;
            completed = true;
            if (frameRequestID !== null) cancelAnimationFrame(frameRequestID);
            resolve({ outcome: "measurement_window_elapsed", latency: null });
          }, \(frameCallbackMeasurementWindowMilliseconds));

          frameRequestID = requestAnimationFrame(() => {
            if (completed) return;
            completed = true;
            clearTimeout(measurementTimerID);
            resolve({
              outcome: "sampled",
              latency: performance.now() - frameStartedAt
            });
          });
        });
        frameCallbackOutcome = frameResult.outcome;
        frameCallbackLatency = frameResult.latency;
      }
    }

    return {
      event_loop_schedule_latency_ms: eventLoopScheduleLatency,
      frame_callback_outcome: frameCallbackOutcome,
      frame_callback_latency_ms: frameCallbackLatency
    };
    """

    private static func productionLivenessProbe(
        webView: WKWebView,
        world: WebRuntimeLivenessWorld,
        timeout: TimeInterval,
        requestBudget: WebRuntimeLivenessRequestBudget
    ) async -> WebRuntimeLivenessProbeResult {
        let startedAt = ProcessInfo.processInfo.systemUptime
        guard let requestID = requestBudget.reserve(world) else {
            return .terminal(
                .suppressed,
                latencyMilliseconds: min(
                    max(ProcessInfo.processInfo.systemUptime - startedAt, 0) * 1_000,
                    5_000
                )
            )
        }
        let gate = WebRuntimeProbeGate<WebRuntimeLivenessProbeResult>()
        return await withCheckedContinuation { continuation in
            gate.install(continuation)
            let timeoutTask = Task { @MainActor [weak gate] in
                do {
                    try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                } catch {
                    return
                }
                gate?.finish(.terminal(.timeout, latencyMilliseconds: timeout * 1_000))
            }
            gate.installTimeoutTask(timeoutTask)

            let finishValue: @MainActor (Any?, Error?) -> Void = { value, error in
                requestBudget.complete(requestID, in: world)
                let latency = min(
                    max(ProcessInfo.processInfo.systemUptime - startedAt, 0) * 1_000,
                    5_000
                )
                guard error == nil,
                      let fields = value as? [String: Any],
                      let readyState = fields["ready_state"] as? String,
                      let visibilityState = fields["visibility_state"] as? String,
                      ["loading", "interactive", "complete", "other"].contains(readyState),
                      ["visible", "hidden", "prerender", "unloaded", "other"].contains(visibilityState) else {
                    gate.finish(.terminal(.failed, latencyMilliseconds: latency))
                    return
                }
                gate.finish(
                    .success(
                        readyState: readyState,
                        visibilityState: visibilityState,
                        latencyMilliseconds: latency
                    )
                )
            }

            switch world {
            case .mainPage:
                webView.evaluateJavaScript(Self.runtimeLivenessProbeScript) { value, error in
                    finishValue(value, error)
                }
            case .floatTabsIsolated:
                webView.evaluateJavaScript(
                    Self.runtimeLivenessProbeScript,
                    in: nil,
                    in: ChatGPTAttentionBridge.contentWorld
                ) { result in
                    switch result {
                    case let .success(value):
                        finishValue(value, nil)
                    case let .failure(error):
                        finishValue(nil, error)
                    }
                }
            }
        }
    }

    static func productionResponsivenessProbe(
        webView: WKWebView,
        shouldMeasureFrame: Bool,
        timeout: TimeInterval,
        requestBudget: WebRuntimeLivenessRequestBudget
    ) async -> WebRuntimeResponsivenessProbeResult {
        let startedAt = ProcessInfo.processInfo.systemUptime
        guard let requestID = requestBudget.reserve(.mainPage) else {
            return .terminal(
                .suppressed,
                probeLatencyMilliseconds: min(
                    max(ProcessInfo.processInfo.systemUptime - startedAt, 0) * 1_000,
                    5_000
                )
            )
        }
        let gate = WebRuntimeProbeGate<WebRuntimeResponsivenessProbeResult>()
        return await withCheckedContinuation { continuation in
            gate.install(continuation)
            let timeoutTask = Task { @MainActor [weak gate] in
                do {
                    try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                } catch {
                    return
                }
                gate?.finish(
                    .terminal(.timeout, probeLatencyMilliseconds: timeout * 1_000)
                )
            }
            gate.installTimeoutTask(timeoutTask)

            webView.callAsyncJavaScript(
                Self.runtimeResponsivenessProbeScript,
                arguments: ["shouldMeasureFrame": shouldMeasureFrame],
                in: nil,
                in: .page,
                completionHandler: { result in
                    requestBudget.complete(requestID, in: .mainPage)
                    let latency = min(
                        max(ProcessInfo.processInfo.systemUptime - startedAt, 0) * 1_000,
                        5_000
                    )
                    guard case let .success(value) = result,
                          let fields = value as? [String: Any],
                          let eventLoopLatency = fields["event_loop_schedule_latency_ms"] as? NSNumber,
                          eventLoopLatency.doubleValue.isFinite,
                          eventLoopLatency.doubleValue >= 0,
                          let rawFrameOutcome = fields["frame_callback_outcome"] as? String,
                          let frameOutcome = WebRuntimeFrameCallbackOutcome(rawValue: rawFrameOutcome) else {
                        gate.finish(
                            .terminal(.failed, probeLatencyMilliseconds: latency)
                        )
                        return
                    }

                    let frameLatency = fields["frame_callback_latency_ms"] as? NSNumber
                    guard (frameOutcome == .sampled && frameLatency != nil)
                        || (frameOutcome != .sampled && frameLatency == nil),
                        frameLatency?.doubleValue.isFinite != false,
                        (frameLatency?.doubleValue ?? 0) >= 0 else {
                        gate.finish(
                            .terminal(.failed, probeLatencyMilliseconds: latency)
                        )
                        return
                    }

                    gate.finish(
                        .success(
                            probeLatencyMilliseconds: latency,
                            eventLoopSchedulingLatencyMilliseconds: eventLoopLatency.doubleValue,
                            frameCallbackOutcome: frameOutcome,
                            frameCallbackLatencyMilliseconds: frameLatency?.doubleValue
                        )
                    )
                }
            )
        }
    }

    private static func currentProcessResidentSizeBytes() -> UInt64? {
        var info = mach_task_basic_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    rebound,
                    &count
                )
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return UInt64(info.resident_size)
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

    private func runtimeFields(for webView: WKWebView) -> [String: RuntimeDiagnosticValue] {
        let contentMode: String = switch webView.configuration.defaultWebpagePreferences.preferredContentMode {
        case .desktop: "desktop"
        case .mobile: "mobile"
        case .recommended: "recommended"
        @unknown default: "unknown"
        }
        let websiteMode = (webView as? FloatTabsWebView)?.websiteMode.rawValue
            ?? contentMode
        let customUserAgent = webView.customUserAgent
        var fields = diagnostics.environmentFields()
        fields.merge([
            "slot_id": .string(slotID.uuidString),
            "website_mode": .string(websiteMode),
            "preferred_content_mode": .string(contentMode),
            "custom_user_agent_present": .bool(customUserAgent?.isEmpty == false),
            "custom_user_agent_is_mobile": .bool(
                customUserAgent?.localizedCaseInsensitiveContains("iPhone") == true
                    || customUserAgent?.localizedCaseInsensitiveContains("Android") == true
            ),
            "frame_width": .double(Double(webView.frame.width)),
            "frame_height": .double(Double(webView.frame.height)),
            "bounds_width": .double(Double(webView.bounds.width)),
            "bounds_height": .double(Double(webView.bounds.height)),
            "page_zoom": .double(Double(webView.pageZoom))
        ]) { _, new in new }
        fields.merge(runtimeDiagnosticIdentity?.fields ?? [:]) { current, _ in current }
        fields.merge(currentContentProcessDiagnosticFields) { current, _ in current }
        let navigationFields = currentNavigationDiagnosticFields
        fields.merge(navigationFields.isEmpty ? [
            "navigation_generation": RuntimeDiagnosticValue.null,
            "navigation_phase": .string("none"),
            "navigation_callback_stale": .bool(false)
        ] : navigationFields) { current, _ in current }
        return fields
    }

    private func advanceObservedContentProcessEpoch() {
        if observedContentProcessTerminationCount < UInt64.max {
            observedContentProcessTerminationCount += 1
        }
        if observedContentProcessEpoch < UInt64.max {
            observedContentProcessEpoch += 1
        }
    }

    private static func diagnosticInteger(_ value: UInt64) -> RuntimeDiagnosticValue {
        .integer(value > UInt64(Int64.max) ? Int64.max : Int64(value))
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
