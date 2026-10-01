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

/// Copies only the probe's two bounded string values before its callback hops
/// to the main actor. WebKit returns `Any`, so that value must not cross a task
/// boundary unnormalized.
struct RendererProbeSnapshot: Equatable, Sendable {
    let result: WebRuntimeRendererProbeResult
    let readyState: String?
    let visibilityState: String?
    let errorCategory: String?

    init(value: Any?, error: Error?) {
        let probe = value as? [String: Any]
        let candidateReadyState = probe?["ready_state"] as? String
        let candidateVisibilityState = probe?["visibility_state"] as? String
        let isValid = error == nil
            && Self.isSafeReadyState(candidateReadyState)
            && Self.isSafeVisibilityState(candidateVisibilityState)

        result = isValid ? .success : .failed
        readyState = isValid ? candidateReadyState : nil
        visibilityState = isValid ? candidateVisibilityState : nil
        errorCategory = error.map { RuntimeDiagnosticPrivacy.safeErrorCategory($0) }
    }

    private static func isSafeReadyState(_ value: String?) -> Bool {
        guard let value else { return false }
        return ["loading", "interactive", "complete"].contains(value)
    }

    private static func isSafeVisibilityState(_ value: String?) -> Bool {
        guard let value else { return false }
        return ["visible", "hidden", "prerender", "unloaded"].contains(value)
    }
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

enum WebRuntimeUserAction: Equatable, Sendable {
    case reload
    case home

    var diagnosticAction: String {
        switch self {
        case .reload: "reload"
        case .home: "home"
        }
    }

    var diagnosticEvent: String {
        switch self {
        case .reload: "web_runtime.reload.requested"
        case .home: "web_runtime.home.requested"
        }
    }
}

struct WebRuntimeRecoveryTicket: Equatable, Sendable {
    let runtimeGeneration: UInt64
    let navigationGeneration: UInt64
    let userActionGeneration: UInt64
    let recoveryGeneration: UInt64
    let action: WebRuntimeUserAction
}

struct WebRuntimeRecoveryRequest: Equatable {
    let ticket: WebRuntimeRecoveryTicket
    let homeURL: URL?
    let homeURLSchemeWasInferred: Bool
}

struct WebRuntimeUserActionContext: Equatable {
    let generation: UInt64
    let action: WebRuntimeUserAction
    let navigationGenerationBefore: UInt64
    let homeURL: URL?
    let homeURLSchemeWasInferred: Bool
    var navigationGeneration: UInt64?
}

enum WebRuntimeRecoveryClassification: Equatable {
    case rendererResponsiveNavigationStall
    case rendererProbeFailed
    case rendererUnresponsive
    case contentProcessTerminated

    init(probeResult: WebRuntimeRendererProbeResult) {
        switch probeResult {
        case .success: self = .rendererResponsiveNavigationStall
        case .failed: self = .rendererProbeFailed
        case .timeout: self = .rendererUnresponsive
        }
    }

    var isHardRecoveryCandidate: Bool {
        self == .rendererUnresponsive
    }
}

enum WebRuntimeRecoveryNavigationAssociation: Equatable {
    case passive
    case userAction(generation: UInt64)
    case softRecovery(WebRuntimeRecoveryTicket)
    case staleSoftRecovery(WebRuntimeRecoveryTicket)
}

/// Correlates explicit user actions with the navigation they start and one
/// bounded recovery request. Navigation generations remain owned by
/// `WebRuntimeHealthTracker`.
struct WebRuntimeRecoveryTracker {
    private enum SoftRecoveryPhase: Equatable {
        case requested
        case deferred
        case awaitingNavigationStart
        case navigating(UInt64)
    }

    private struct SoftRecoveryState: Equatable {
        let request: WebRuntimeRecoveryRequest
        var phase: SoftRecoveryPhase
    }

    private(set) var runtimeGeneration: UInt64
    private var nextUserActionGeneration: UInt64 = 0
    private var nextRecoveryGeneration: UInt64 = 0
    private var userAction: WebRuntimeUserActionContext?
    private var softRecovery: SoftRecoveryState?

    init(runtimeGeneration: UInt64) {
        self.runtimeGeneration = runtimeGeneration
    }

    mutating func recordUserAction(
        _ action: WebRuntimeUserAction,
        navigationGenerationBefore: UInt64,
        homeURL: URL? = nil,
        homeURLSchemeWasInferred: Bool = false
    ) -> (generation: UInt64, invalidatedRecovery: WebRuntimeRecoveryTicket?) {
        let invalidatedRecovery = softRecovery?.request.ticket
        nextUserActionGeneration &+= 1
        userAction = WebRuntimeUserActionContext(
            generation: nextUserActionGeneration,
            action: action,
            navigationGenerationBefore: navigationGenerationBefore,
            homeURL: homeURL,
            homeURLSchemeWasInferred: homeURLSchemeWasInferred,
            navigationGeneration: nil
        )
        softRecovery = nil
        return (nextUserActionGeneration, invalidatedRecovery)
    }

    mutating func navigationStarted(
        _ navigation: WebRuntimeNavigationTicket
    ) -> WebRuntimeRecoveryNavigationAssociation {
        guard navigation.runtimeGeneration == runtimeGeneration else {
            return .passive
        }

        if var softRecovery {
            switch softRecovery.phase {
            case .awaitingNavigationStart:
                guard navigation.navigationGeneration
                    > softRecovery.request.ticket.navigationGeneration else {
                    self.softRecovery = nil
                    userAction = nil
                    return .staleSoftRecovery(softRecovery.request.ticket)
                }
                softRecovery.phase = .navigating(navigation.navigationGeneration)
                self.softRecovery = softRecovery
                return .softRecovery(softRecovery.request.ticket)

            case .requested, .deferred, .navigating:
                self.softRecovery = nil
                userAction = nil
                return .staleSoftRecovery(softRecovery.request.ticket)
            }
        }

        guard var userAction else { return .passive }
        guard navigation.navigationGeneration > userAction.navigationGenerationBefore else {
            self.userAction = nil
            return .passive
        }
        if let activeNavigationGeneration = userAction.navigationGeneration,
           activeNavigationGeneration != navigation.navigationGeneration {
            self.userAction = nil
            return .passive
        }

        userAction.navigationGeneration = navigation.navigationGeneration
        self.userAction = userAction
        return .userAction(generation: userAction.generation)
    }

    func userActionContext(
        for navigation: WebRuntimeNavigationTicket
    ) -> WebRuntimeUserActionContext? {
        guard navigation.runtimeGeneration == runtimeGeneration,
              let userAction,
              userAction.navigationGeneration == navigation.navigationGeneration else {
            return nil
        }
        return userAction
    }

    mutating func actionStartTimedOut(
        generation: UInt64
    ) -> WebRuntimeUserActionContext? {
        guard let userAction,
              userAction.generation == generation,
              userAction.navigationGeneration == nil,
              softRecovery == nil else {
            return nil
        }
        self.userAction = nil
        return userAction
    }

    mutating func requestSoftRecovery(
        for navigation: WebRuntimeNavigationTicket,
        classification: WebRuntimeRecoveryClassification
    ) -> WebRuntimeRecoveryRequest? {
        guard classification == .rendererResponsiveNavigationStall,
              navigation.runtimeGeneration == runtimeGeneration,
              let userAction = userActionContext(for: navigation),
              softRecovery == nil else {
            return nil
        }

        nextRecoveryGeneration &+= 1
        let ticket = WebRuntimeRecoveryTicket(
            runtimeGeneration: navigation.runtimeGeneration,
            navigationGeneration: navigation.navigationGeneration,
            userActionGeneration: userAction.generation,
            recoveryGeneration: nextRecoveryGeneration,
            action: userAction.action
        )
        let request = WebRuntimeRecoveryRequest(
            ticket: ticket,
            homeURL: userAction.homeURL,
            homeURLSchemeWasInferred: userAction.homeURLSchemeWasInferred
        )
        softRecovery = SoftRecoveryState(request: request, phase: .requested)
        return request
    }

    mutating func resolveProbeWithoutRecovery(
        for navigation: WebRuntimeNavigationTicket
    ) {
        guard userActionContext(for: navigation) != nil,
              softRecovery == nil else {
            return
        }
        userAction = nil
    }

    func request(for ticket: WebRuntimeRecoveryTicket) -> WebRuntimeRecoveryRequest? {
        guard softRecovery?.request.ticket == ticket else { return nil }
        return softRecovery?.request
    }

    func isCurrent(_ ticket: WebRuntimeRecoveryTicket) -> Bool {
        runtimeGeneration == ticket.runtimeGeneration
            && softRecovery?.request.ticket == ticket
    }

    mutating func deferSoftRecovery(_ ticket: WebRuntimeRecoveryTicket) -> Bool {
        guard var softRecovery,
              softRecovery.request.ticket == ticket,
              softRecovery.phase == .requested else {
            return false
        }
        softRecovery.phase = .deferred
        self.softRecovery = softRecovery
        return true
    }

    mutating func beginSoftRecovery(_ ticket: WebRuntimeRecoveryTicket) -> Bool {
        guard var softRecovery,
              softRecovery.request.ticket == ticket,
              softRecovery.phase == .requested || softRecovery.phase == .deferred else {
            return false
        }
        softRecovery.phase = .awaitingNavigationStart
        self.softRecovery = softRecovery
        return true
    }

    mutating func softRecoveryStartTimedOut(
        _ ticket: WebRuntimeRecoveryTicket
    ) -> Bool {
        guard let softRecovery,
              softRecovery.request.ticket == ticket else {
            return false
        }
        self.softRecovery = nil
        userAction = nil
        return true
    }

    func softRecoveryTicket(
        for navigation: WebRuntimeNavigationTicket
    ) -> WebRuntimeRecoveryTicket? {
        guard let softRecovery,
              case let .navigating(generation) = softRecovery.phase,
              generation == navigation.navigationGeneration,
              navigation.runtimeGeneration == runtimeGeneration else {
            return nil
        }
        return softRecovery.request.ticket
    }

    func isAwaitingSoftRecoveryNavigationStart(
        after navigation: WebRuntimeNavigationTicket
    ) -> Bool {
        guard navigation.runtimeGeneration == runtimeGeneration,
              let softRecovery,
              softRecovery.phase == .awaitingNavigationStart else {
            return false
        }
        return softRecovery.request.ticket.navigationGeneration == navigation.navigationGeneration
    }

    func hasPendingSoftRecoveryStart(
        after navigation: WebRuntimeNavigationTicket
    ) -> Bool {
        guard navigation.runtimeGeneration == runtimeGeneration,
              let softRecovery,
              softRecovery.request.ticket.navigationGeneration == navigation.navigationGeneration else {
            return false
        }
        switch softRecovery.phase {
        case .requested, .deferred, .awaitingNavigationStart:
            return true
        case .navigating:
            return false
        }
    }

    mutating func didCommit(
        _ navigation: WebRuntimeNavigationTicket
    ) -> WebRuntimeRecoveryTicket? {
        // A commit is progress, not recovery completion. The confirmed incident
        // class is explicitly post-commit: WebKit may commit, remain loading for
        // minutes, and only later finish. Keep the recovery ticket live so a
        // post-commit stall or failure is still attributed to this one bounded
        // recovery attempt.
        guard softRecoveryTicket(for: navigation) != nil else { return nil }
        return nil
    }

    mutating func didFinish(
        _ navigation: WebRuntimeNavigationTicket
    ) -> WebRuntimeRecoveryTicket? {
        if let ticket = softRecoveryTicket(for: navigation) {
            softRecovery = nil
            userAction = nil
            return ticket
        }
        if userActionContext(for: navigation) != nil, softRecovery == nil {
            userAction = nil
        }
        return nil
    }

    mutating func userNavigationFinished(
        _ navigation: WebRuntimeNavigationTicket
    ) -> WebRuntimeRecoveryTicket? {
        guard userActionContext(for: navigation) != nil,
              let softRecovery,
              softRecovery.request.ticket.navigationGeneration == navigation.navigationGeneration,
              softRecovery.phase == .requested || softRecovery.phase == .deferred else {
            return nil
        }
        self.softRecovery = nil
        userAction = nil
        return softRecovery.request.ticket
    }

    mutating func didFail(
        _ navigation: WebRuntimeNavigationTicket
    ) -> WebRuntimeRecoveryTicket? {
        if let softRecovery,
           softRecovery.phase == .awaitingNavigationStart,
           softRecovery.request.ticket.navigationGeneration == navigation.navigationGeneration {
            return nil
        }
        if let ticket = softRecoveryTicket(for: navigation) {
            softRecovery = nil
            userAction = nil
            return ticket
        }
        if userActionContext(for: navigation) != nil, softRecovery == nil {
            userAction = nil
        }
        return nil
    }

    mutating func recoveryNavigationStalled(
        _ navigation: WebRuntimeNavigationTicket
    ) -> WebRuntimeRecoveryTicket? {
        guard let ticket = softRecoveryTicket(for: navigation) else { return nil }
        softRecovery = nil
        userAction = nil
        return ticket
    }

    mutating func invalidate() -> WebRuntimeRecoveryTicket? {
        let invalidated = softRecovery?.request.ticket
        userAction = nil
        softRecovery = nil
        return invalidated
    }

    mutating func replaceRuntime(with generation: UInt64) -> WebRuntimeRecoveryTicket? {
        let invalidated = invalidate()
        runtimeGeneration = generation
        nextUserActionGeneration = 0
        nextRecoveryGeneration = 0
        return invalidated
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
    typealias DiagnosticHealthSnapshotHandler = @MainActor (
        UUID,
        WKWebView,
        String,
        UInt64?
    ) -> Void

    private enum WatchdogTarget {
        case navigation(WebRuntimeNavigationTicket)
        case userAction(
            generation: UInt64,
            action: WebRuntimeUserAction,
            navigationGenerationBefore: UInt64
        )
        case softRecoveryStart(WebRuntimeRecoveryTicket)
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
    private let networkPathGenerationProvider: @MainActor () -> UInt64?
    private let incidentDiagnosticContextProvider: IncidentDiagnosticContextProvider
    private let onDiagnosticHealthSnapshot: DiagnosticHealthSnapshotHandler
    private let javaScriptEvaluator: JavaScriptEvaluationHandler
    private let onSoftRecoveryRequested: @MainActor (WebRuntimeRecoveryRequest) -> Void
    private let onSoftRecoveryInvalidated: @MainActor (WebRuntimeRecoveryTicket) -> Void

    private var healthTracker: WebRuntimeHealthTracker
    private var rendererProbeLifecycle: RendererProbeLifecycle
    private var recoveryTracker: WebRuntimeRecoveryTracker
    private var activeNavigationIdentifier: ObjectIdentifier?
    private var softRecoverySourceNavigationIdentifier: ObjectIdentifier?
    private var softRecoverySourceTicket: WebRuntimeRecoveryTicket?
    private var softRecoveryReplacementDidStart = false
    private var navigationStartUptime: TimeInterval?
    private var lastCommitUptime: TimeInterval?
    private var watchdogGeneration: UInt64 = 0
    private var watchdogWorkItem: DispatchWorkItem?
    private var nextUserActionGeneration: UInt64 = 0
    private var nextNavigationTrigger: WebNavigationTrigger?
    private var currentNavigationTrigger: WebNavigationTrigger = .unknown
    private var currentTriggerNavigationGeneration: UInt64?
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
        networkPathGenerationProvider: @escaping @MainActor () -> UInt64? = { nil },
        incidentDiagnosticContextProvider: @escaping IncidentDiagnosticContextProvider = { _ in [:] },
        onDiagnosticHealthSnapshot: @escaping DiagnosticHealthSnapshotHandler = { _, _, _, _ in },
        onSoftRecoveryRequested: @escaping @MainActor (WebRuntimeRecoveryRequest) -> Void = { _ in },
        onSoftRecoveryInvalidated: @escaping @MainActor (WebRuntimeRecoveryTicket) -> Void = { _ in },
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
        self.networkPathGenerationProvider = networkPathGenerationProvider
        self.incidentDiagnosticContextProvider = incidentDiagnosticContextProvider
        self.onDiagnosticHealthSnapshot = onDiagnosticHealthSnapshot
        self.onSoftRecoveryRequested = onSoftRecoveryRequested
        self.onSoftRecoveryInvalidated = onSoftRecoveryInvalidated
        self.javaScriptEvaluator = javaScriptEvaluator
        healthTracker = WebRuntimeHealthTracker(runtimeGeneration: runtimeGeneration)
        rendererProbeLifecycle = RendererProbeLifecycle(runtimeGeneration: runtimeGeneration)
        recoveryTracker = WebRuntimeRecoveryTracker(runtimeGeneration: runtimeGeneration)
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

    func setNextNavigationTrigger(_ trigger: WebNavigationTrigger) {
        nextNavigationTrigger = trigger
    }

    /// Called at the existing user-action boundary. This schedules only one
    /// bounded no-progress observation and never changes the requested action.
    func observeUserAction(
        _ action: WebRuntimeUserAction,
        homeURL: URL? = nil,
        homeURLSchemeWasInferred: Bool = false
    ) {
        guard webView != nil else { return }
        cancelWatchdog()
        cancelRendererProbeTimeout()
        rendererProbeLifecycle.invalidate()
        let actionContext = recoveryTracker.recordUserAction(
            action,
            navigationGenerationBefore: healthTracker.latestNavigationGeneration,
            homeURL: homeURL,
            homeURLSchemeWasInferred: homeURLSchemeWasInferred
        )
        clearSoftRecoverySourceNavigation(force: true)
        if let previousRecovery = actionContext.invalidatedRecovery {
            recordRecoveryEvent(
                "soft_stale",
                ticket: previousRecovery,
                reason: "new_user_action"
            )
            onSoftRecoveryInvalidated(previousRecovery)
        }
        nextUserActionGeneration = actionContext.generation
        scheduleWatchdog(
            target: .userAction(
                generation: actionContext.generation,
                action: action,
                navigationGenerationBefore: healthTracker.latestNavigationGeneration
            ),
            after: Self.navigationStallTimeout
        )
    }

    func isCurrentSoftRecovery(_ ticket: WebRuntimeRecoveryTicket) -> Bool {
        recoveryTracker.isCurrent(ticket)
    }

    func softRecoveryRequest(
        for ticket: WebRuntimeRecoveryTicket
    ) -> WebRuntimeRecoveryRequest? {
        recoveryTracker.request(for: ticket)
    }

    @discardableResult
    func deferSoftRecovery(_ ticket: WebRuntimeRecoveryTicket, reason: String) -> Bool {
        guard recoveryTracker.deferSoftRecovery(ticket) else { return false }
        recordRecoveryEvent("soft_deferred", ticket: ticket, reason: reason)
        scheduleWatchdog(
            target: .softRecoveryStart(ticket),
            after: Self.navigationStallTimeout
        )
        return true
    }

    @discardableResult
    func beginSoftRecovery(_ ticket: WebRuntimeRecoveryTicket) -> Bool {
        guard recoveryTracker.beginSoftRecovery(ticket) else { return false }
        softRecoverySourceNavigationIdentifier = activeNavigationIdentifier
        softRecoverySourceTicket = ticket
        softRecoveryReplacementDidStart = false
        cancelWatchdog()
        recordRecoveryEvent(
            "soft_started",
            ticket: ticket,
            reason: "user_action_stalled_renderer_responsive"
        )
        scheduleWatchdog(
            target: .softRecoveryStart(ticket),
            after: Self.navigationStallTimeout
        )
        return true
    }

    func failSoftRecovery(_ ticket: WebRuntimeRecoveryTicket, reason: String) {
        guard recoveryTracker.isCurrent(ticket) else { return }
        cancelWatchdog()
        _ = recoveryTracker.invalidate()
        clearSoftRecoverySourceNavigation()
        recordRecoveryEvent("soft_failed", ticket: ticket, reason: reason)
        onSoftRecoveryInvalidated(ticket)
    }

    func invalidateSoftRecovery(_ ticket: WebRuntimeRecoveryTicket, reason: String) {
        guard recoveryTracker.isCurrent(ticket) else { return }
        cancelWatchdog()
        _ = recoveryTracker.invalidate()
        clearSoftRecoverySourceNavigation()
        recordRecoveryEvent("soft_stale", ticket: ticket, reason: reason)
        onSoftRecoveryInvalidated(ticket)
    }

    /// Called before a pooled runtime is released or replaced so no delayed
    /// observation can outlive the WKWebView it describes.
    func invalidate(recoveryReason: String = "runtime_released") {
        cancelWatchdog()
        cancelRendererProbeTimeout()
        clearSoftRecoverySourceNavigation(force: true)
        if let invalidatedRecovery = recoveryTracker.invalidate() {
            recordRecoveryEvent(
                "soft_stale",
                ticket: invalidatedRecovery,
                reason: recoveryReason
            )
            onSoftRecoveryInvalidated(invalidatedRecovery)
        }
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
            let association = recoveryTracker.navigationStarted(ticket)
            switch association {
            case .passive:
                currentNavigationTrigger = nextNavigationTrigger ?? .normalNavigation
            case let .userAction(generation):
                let action = recoveryTracker.userActionContext(for: ticket)?.action
                currentNavigationTrigger = action.map(Self.navigationTrigger(for:))
                    ?? nextNavigationTrigger
                    ?? .unknown
                _ = generation
            case .softRecovery:
                currentNavigationTrigger = .softRecovery
                softRecoveryReplacementDidStart = true
                cancelWatchdog()
                // The start watchdog is replaced by the normal bounded
                // navigation watchdog below.
            case let .staleSoftRecovery(recoveryTicket):
                currentNavigationTrigger = .softRecovery
                clearSoftRecoverySourceNavigation()
                recordRecoveryEvent(
                    "soft_stale",
                    ticket: recoveryTicket,
                    reason: "new_navigation"
                )
                onSoftRecoveryInvalidated(recoveryTicket)
            }
            currentTriggerNavigationGeneration = ticket.navigationGeneration
            nextNavigationTrigger = nil
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
        let isCurrentNavigationCallback = ticket != nil
        let isRecoverySourceCallback = !isCurrentNavigationCallback
            && isCurrentSoftRecoverySourceNavigation(navigation)
        let mayProjectNavigationState = isCurrentNavigationCallback && !isRecoverySourceCallback
        let preservesRecoveryStartWatchdog = ticket.map {
            recoveryTracker.hasPendingSoftRecoveryStart(after: $0)
        } ?? false
        if let ticket, healthTracker.didCommit(ticket) {
            if !preservesRecoveryStartWatchdog {
                cancelWatchdog()
            }
            cancelRendererProbeTimeout()
            rendererProbeLifecycle.invalidate()
            lastCommitUptime = ProcessInfo.processInfo.systemUptime
            // Commit proves the provisional phase made progress, but it is not
            // a terminal navigation state. Re-arm one bounded diagnostic
            // watchdog so a committed page that never finishes can still be
            // distinguished from a healthy completed load. If soft recovery
            // has already begun, however, a late commit from the original
            // stalled navigation must not replace the recovery-start watchdog.
            if !preservesRecoveryStartWatchdog {
                scheduleWatchdog(target: .navigation(ticket), after: Self.navigationStallTimeout)
            }
        }
        if let ticket {
            _ = recoveryTracker.didCommit(ticket)
        }
        if mayProjectNavigationState {
            cancelPendingInstantBack()
            // Once an https entry commits, later in-page failures can never inherit
            // the entry-only downgrade permission. A late commit from the original
            // stalled navigation during soft-recovery startup must not clear the
            // fallback provenance just configured for the replacement Home load.
            if !preservesRecoveryStartWatchdog {
                pendingHTTPEntryFallback = nil
            }
        }
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
        // committed destination for the current navigation. A late callback
        // from the original recovery-source navigation is stale once the
        // replacement has begun and must not reset bridges or project a
        // committed URL for the replacement document.
        if mayProjectNavigationState {
            onNavigationCommit(slotID, webView.url)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        restoreWebsiteMode(in: webView)
        restoreHiddenScrollerPolicy(in: webView)

        let ticket = currentNavigationTicket(for: navigation)
        let isCurrentNavigationCallback = ticket != nil
        let isRecoverySourceCallback = !isCurrentNavigationCallback
            && isCurrentSoftRecoverySourceNavigation(navigation)
        let mayProjectNavigationState = isCurrentNavigationCallback && !isRecoverySourceCallback
        let preservesRecoveryStartWatchdog = ticket.map {
            recoveryTracker.isAwaitingSoftRecoveryNavigationStart(after: $0)
        } ?? false
        if let ticket, healthTracker.didFinish(ticket) {
            if !preservesRecoveryStartWatchdog {
                cancelWatchdog()
            }
            cancelRendererProbeTimeout()
            rendererProbeLifecycle.invalidate()
            activeNavigationIdentifier = nil
            navigationStartUptime = nil
        }
        if let ticket,
           let supersededRecovery = recoveryTracker.userNavigationFinished(ticket) {
            clearSoftRecoverySourceNavigation()
            recordRecoveryEvent(
                "soft_stale",
                ticket: supersededRecovery,
                reason: "user_navigation_finished_before_recovery"
            )
            onSoftRecoveryInvalidated(supersededRecovery)
        }
        if let ticket,
           let completedRecovery = recoveryTracker.didFinish(ticket) {
            clearSoftRecoverySourceNavigation()
            recordRecoveryEvent(
                "soft_completed",
                ticket: completedRecovery,
                reason: "navigation_finished"
            )
        }

        diagnostics.record(
            event: "navigation.finished",
            level: .info,
            subsystem: "navigation",
            fields: runtimeFields(for: webView, ticket: ticket)
        )
        onDiagnosticHealthSnapshot(
            slotID,
            webView,
            "navigation_finish",
            ticket?.navigationGeneration
        )
        if diagnostics.capturesDebugEvents && mayProjectNavigationState {
            recordPageRuntimeProbe(in: webView)
        }

        if mayProjectNavigationState {
            onNavigationFinish(slotID, webView.url)

            if let url = webView.url, WebAppURL.isSafe(url) {
                confirmInstantBackActivation(in: webView, observedURL: url)
            }
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
        let preservesRecoveryStartWatchdog = ticket.map {
            recoveryTracker.hasPendingSoftRecoveryStart(after: $0)
        } ?? false
        if let ticket, healthTracker.didFail(ticket) {
            // stopLoading() is the first step of soft recovery and may fail the
            // original stalled navigation before reloadFromOrigin()/Home starts
            // its replacement navigation. That expected old-navigation failure
            // must not cancel the bounded recovery-start watchdog.
            if !preservesRecoveryStartWatchdog {
                cancelWatchdog()
            }
            cancelRendererProbeTimeout()
            rendererProbeLifecycle.invalidate()
            activeNavigationIdentifier = nil
            navigationStartUptime = nil
        }
        if let ticket,
           let failedRecovery = recoveryTracker.didFail(ticket) {
            clearSoftRecoverySourceNavigation()
            recordRecoveryEvent(
                "soft_failed",
                ticket: failedRecovery,
                reason: "navigation_failed"
            )
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
        onDiagnosticHealthSnapshot(
            slotID,
            webView,
            "navigation_failure",
            ticket?.navigationGeneration
        )
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        restoreHiddenScrollerPolicy(in: webView)
        let ticket = currentNavigationTicket(for: navigation)
        let isCurrentNavigationCallback = ticket != nil
        let isRecoverySourceCallback = !isCurrentNavigationCallback
            && isCurrentSoftRecoverySourceNavigation(navigation)
        let mayProjectNavigationState = isCurrentNavigationCallback && !isRecoverySourceCallback
        let preservesRecoveryStartWatchdog = ticket.map {
            recoveryTracker.hasPendingSoftRecoveryStart(after: $0)
        } ?? false
        if let ticket, healthTracker.didFail(ticket) {
            // stopLoading() is the first step of soft recovery and may fail the
            // original stalled navigation before reloadFromOrigin()/Home starts
            // its replacement navigation. That expected old-navigation failure
            // must not cancel the bounded recovery-start watchdog.
            if !preservesRecoveryStartWatchdog {
                cancelWatchdog()
            }
            cancelRendererProbeTimeout()
            rendererProbeLifecycle.invalidate()
            activeNavigationIdentifier = nil
            navigationStartUptime = nil
        }
        if let ticket,
           let failedRecovery = recoveryTracker.didFail(ticket) {
            clearSoftRecoverySourceNavigation()
            recordRecoveryEvent(
                "soft_failed",
                ticket: failedRecovery,
                reason: "navigation_failed"
            )
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
        onDiagnosticHealthSnapshot(
            slotID,
            webView,
            "navigation_failure",
            ticket?.navigationGeneration
        )
        if mayProjectNavigationState {
            cancelPendingInstantBack()
        }
        // The replacement Home load may already have installed fresh inferred-
        // scheme fallback provenance while WebKit is still delivering a late
        // failure for the original stopped navigation. Do not let that stale
        // callback consume or clear the replacement navigation's permission.
        if isCurrentNavigationCallback,
           !preservesRecoveryStartWatchdog,
           !isRecoverySourceCallback {
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
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        let ticket = healthTracker.activeTicket ?? healthTracker.latestTicket
        cancelWatchdog()
        cancelRendererProbeTimeout()
        rendererProbeLifecycle.invalidate()
        clearSoftRecoverySourceNavigation(force: true)
        if let invalidatedRecovery = recoveryTracker.invalidate() {
            recordRecoveryEvent(
                "soft_stale",
                ticket: invalidatedRecovery,
                reason: "content_process_terminated"
            )
            onSoftRecoveryInvalidated(invalidatedRecovery)
        }
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

    private func isCurrentSoftRecoverySourceNavigation(_ navigation: WKNavigation!) -> Bool {
        guard let navigation else {
            return false
        }
        let navigationIdentifier = ObjectIdentifier(navigation)
        if navigationIdentifier == activeNavigationIdentifier {
            return false
        }
        guard let sourceNavigationIdentifier = softRecoverySourceNavigationIdentifier,
              navigationIdentifier == sourceNavigationIdentifier else { return false }
        return softRecoveryReplacementDidStart
            || softRecoverySourceTicket.map(recoveryTracker.isCurrent) == true
    }

    private func clearSoftRecoverySourceNavigation(force: Bool = false) {
        guard force || !softRecoveryReplacementDidStart else { return }
        softRecoverySourceNavigationIdentifier = nil
        softRecoverySourceTicket = nil
        softRecoveryReplacementDidStart = false
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
            if let recoveryTicket = recoveryTracker.recoveryNavigationStalled(ticket) {
                clearSoftRecoverySourceNavigation()
                recordRecoveryEvent(
                    "soft_failed",
                    ticket: recoveryTicket,
                    reason: "recovery_navigation_stalled"
                )
                recordNavigationStall(
                    in: webView,
                    ticket: ticket,
                    source: "soft_recovery",
                    userActionContext: nil,
                    navigationCommitted: navigationCommitted,
                    recoveryTicket: recoveryTicket,
                    shouldProbeRenderer: false
                )
                onSoftRecoveryInvalidated(recoveryTicket)
                return
            }
            recordNavigationStall(
                in: webView,
                ticket: ticket,
                source: "navigation",
                userActionContext: recoveryTracker.userActionContext(for: ticket),
                navigationCommitted: navigationCommitted
            )

        case let .userAction(generation, _, navigationGenerationBefore):
            guard generation == nextUserActionGeneration,
                  let actionContext = recoveryTracker.actionStartTimedOut(generation: generation) else {
                return
            }
            diagnostics.record(
                event: "web_runtime.user_action.no_navigation",
                level: .warning,
                subsystem: "web",
                fields: [
                    "slot_id": .string(slotID.uuidString),
                    "runtime_generation": .integer(Int64(runtimeGeneration)),
                    "navigation_generation": .integer(Int64(navigationGenerationBefore)),
                    "navigation_generation_before": .integer(Int64(actionContext.navigationGenerationBefore)),
                    "user_action_generation": .integer(Int64(actionContext.generation)),
                    "action": .string(actionContext.action.diagnosticAction),
                    "is_loading": .bool(webView.isLoading)
                ]
            )

        case let .softRecoveryStart(ticket):
            guard recoveryTracker.softRecoveryStartTimedOut(ticket) else { return }
            clearSoftRecoverySourceNavigation()
            recordRecoveryEvent(
                "soft_failed",
                ticket: ticket,
                reason: "recovery_navigation_start_timeout"
            )
            onSoftRecoveryInvalidated(ticket)
        }
    }

    private func recordNavigationStall(
        in webView: WKWebView,
        ticket: WebRuntimeNavigationTicket,
        source: String,
        userActionContext: WebRuntimeUserActionContext?,
        navigationCommitted: Bool?,
        recoveryTicket: WebRuntimeRecoveryTicket? = nil,
        shouldProbeRenderer: Bool = true
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
        if let userActionContext {
            fields["user_action_generation"] = .integer(Int64(userActionContext.generation))
            fields["action"] = .string(userActionContext.action.diagnosticAction)
            fields["navigation_generation_before"] = .integer(
                Int64(userActionContext.navigationGenerationBefore)
            )
            fields["navigation_started_after_request"] = .bool(true)
        }
        if let recoveryTicket {
            fields["user_action_generation"] = .integer(Int64(recoveryTicket.userActionGeneration))
            fields["recovery_generation"] = .integer(Int64(recoveryTicket.recoveryGeneration))
            fields["action"] = .string(recoveryTicket.action.diagnosticAction)
        }
        diagnostics.record(
            event: "navigation.stalled",
            level: .warning,
            subsystem: "navigation",
            fields: fields
        )
        onDiagnosticHealthSnapshot(
            slotID,
            webView,
            "navigation_stall",
            ticket.navigationGeneration
        )
        recordIncidentSnapshot(in: webView, ticket: ticket, reason: "navigation_stalled")
        if shouldProbeRenderer {
            startRendererProbe(in: webView, for: ticket)
        }
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
            let snapshot = RendererProbeSnapshot(value: value, error: error)
            Task { @MainActor [weak self, weak webView] in
                guard let self,
                      let webView,
                      self.webView === webView else {
                    return
                }
                guard let result = self.rendererProbeLifecycle.complete(
                    ticket,
                    as: snapshot.result
                ) else {
                    return
                }
                self.cancelRendererProbeTimeout()
                self.recordRendererProbeResult(
                    result,
                    ticket: ticket,
                    latencyMilliseconds: self.probeLatencyMilliseconds(since: startedAt),
                    readyState: snapshot.readyState,
                    visibilityState: snapshot.visibilityState,
                    errorCategory: snapshot.errorCategory
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
        errorCategory: String? = nil
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
        if let errorCategory {
            fields["error_category"] = .string(errorCategory)
        }
        diagnostics.record(
            event: event,
            level: level,
            subsystem: "web",
            fields: fields
        )
        handleRecoveryProbeResult(
            result,
            for: WebRuntimeNavigationTicket(
                runtimeGeneration: ticket.runtimeGeneration,
                navigationGeneration: ticket.navigationGeneration
            )
        )
    }

    private func handleRecoveryProbeResult(
        _ result: WebRuntimeRendererProbeResult,
        for navigation: WebRuntimeNavigationTicket
    ) {
        guard let actionContext = recoveryTracker.userActionContext(for: navigation) else {
            return
        }

        let classification = WebRuntimeRecoveryClassification(probeResult: result)
        switch classification {
        case .rendererResponsiveNavigationStall:
            guard let request = recoveryTracker.requestSoftRecovery(
                for: navigation,
                classification: classification
            ) else {
                return
            }
            recordRecoveryEvent(
                "soft_requested",
                ticket: request.ticket,
                reason: "user_action_stalled_renderer_responsive"
            )
            scheduleWatchdog(
                target: .softRecoveryStart(request.ticket),
                after: Self.navigationStallTimeout
            )
            onSoftRecoveryRequested(request)

        case .rendererProbeFailed:
            recoveryTracker.resolveProbeWithoutRecovery(for: navigation)
            diagnostics.record(
                event: "web_runtime.recovery.soft_failed",
                level: .warning,
                subsystem: "web",
                fields: [
                    "slot_id": .string(slotID.uuidString),
                    "runtime_generation": .integer(Int64(navigation.runtimeGeneration)),
                    "navigation_generation": .integer(Int64(navigation.navigationGeneration)),
                    "user_action_generation": .integer(Int64(actionContext.generation)),
                    "recovery_generation": .null,
                    "action": .string(actionContext.action.diagnosticAction),
                    "reason": .string("renderer_probe_failed")
                ]
            )

        case .rendererUnresponsive:
            recoveryTracker.resolveProbeWithoutRecovery(for: navigation)
            diagnostics.record(
                event: "web_runtime.recovery.hard_deferred",
                level: .warning,
                subsystem: "web",
                fields: [
                    "slot_id": .string(slotID.uuidString),
                    "runtime_generation": .integer(Int64(navigation.runtimeGeneration)),
                    "navigation_generation": .integer(Int64(navigation.navigationGeneration)),
                    "user_action_generation": .integer(Int64(actionContext.generation)),
                    "recovery_generation": .null,
                    "action": .string(actionContext.action.diagnosticAction),
                    "reason": .string("renderer_probe_timeout_existing_rebuild_owner_required")
                ]
            )

        case .contentProcessTerminated:
            break
        }
    }

    private func recordRecoveryEvent(
        _ suffix: String,
        ticket: WebRuntimeRecoveryTicket,
        reason: String
    ) {
        let level: RuntimeDiagnosticLevel = switch suffix {
        case "soft_requested": .notice
        case "soft_started", "soft_completed": .info
        default: .warning
        }
        diagnostics.record(
            event: "web_runtime.recovery.\(suffix)",
            level: level,
            subsystem: "web",
            fields: [
                "slot_id": .string(slotID.uuidString),
                "runtime_generation": .integer(Int64(ticket.runtimeGeneration)),
                "navigation_generation": .integer(Int64(ticket.navigationGeneration)),
                "user_action_generation": .integer(Int64(ticket.userActionGeneration)),
                "recovery_generation": .integer(Int64(ticket.recoveryGeneration)),
                "action": .string(ticket.action.diagnosticAction),
                "reason": .string(reason)
            ]
        )
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
        var fields: [String: RuntimeDiagnosticValue] = [
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
        let trigger = ticket.flatMap { currentTriggerNavigationGeneration == $0.navigationGeneration
            ? currentNavigationTrigger
            : nil
        } ?? .unknown
        fields["navigation_trigger"] = .string(trigger.rawValue)
        fields["network_generation"] = networkPathGenerationProvider().map {
            .integer(Int64($0))
        } ?? .null
        return fields
    }

    private static func navigationTrigger(
        for action: WebRuntimeUserAction
    ) -> WebNavigationTrigger {
        switch action {
        case .reload: .userReload
        case .home: .userHome
        }
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
