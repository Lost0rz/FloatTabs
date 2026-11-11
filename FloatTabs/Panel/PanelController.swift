import AppKit
import OSLog
import WebKit

typealias BrowserProfileSwitchConfirmation = @MainActor (WebAppProfile, BrowserProfile?, String) -> Bool

enum PanelPresentationDisplayRelationship: String, Equatable {
    case sameDisplay
    case crossDisplay
    case unknown
}

/// A reload-only favicon refresh intent bound to one resident Runtime and one
/// navigation generation. It cannot survive a Runtime swap, newer navigation,
/// or consumption by the matching navigation finish.
struct ManualFaviconReloadIntent: Equatable {
    enum NavigationStartResult: Equatable {
        case ignored
        case captured
        case invalidated
    }

    private enum Phase: Equatable {
        case waitingForNavigationStart
        case awaitingFinish(UInt64)
        case consumed
    }

    let runtimeIdentity: WebRuntimeDiagnosticIdentity
    let baselineNavigationGeneration: UInt64
    let expiresAt: TimeInterval
    private var phase: Phase = .waitingForNavigationStart

    init(
        runtimeIdentity: WebRuntimeDiagnosticIdentity,
        baselineNavigationGeneration: UInt64,
        requestedAt: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) {
        self.runtimeIdentity = runtimeIdentity
        self.baselineNavigationGeneration = baselineNavigationGeneration
        expiresAt = requestedAt + 15
    }

    var capturedNavigationGeneration: UInt64? {
        guard case let .awaitingFinish(generation) = phase else { return nil }
        return generation
    }

    mutating func recordNavigationStart(
        runtimeIdentity: WebRuntimeDiagnosticIdentity,
        navigationGeneration: UInt64,
        at now: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> NavigationStartResult {
        guard runtimeIdentity == self.runtimeIdentity, now <= expiresAt else { return .invalidated }
        switch phase {
        case .waitingForNavigationStart:
            guard navigationGeneration > baselineNavigationGeneration else { return .ignored }
            phase = .awaitingFinish(navigationGeneration)
            return .captured
        case let .awaitingFinish(capturedGeneration):
            return capturedGeneration == navigationGeneration ? .ignored : .invalidated
        case .consumed:
            return .invalidated
        }
    }

    mutating func consumeNavigationFinish(
        runtimeIdentity: WebRuntimeDiagnosticIdentity,
        navigationGeneration: UInt64
    ) -> Bool {
        guard runtimeIdentity == self.runtimeIdentity,
              phase == .awaitingFinish(navigationGeneration) else {
            return false
        }
        phase = .consumed
        return true
    }

    func matchesNavigationFailure(
        runtimeIdentity: WebRuntimeDiagnosticIdentity,
        navigationGeneration: UInt64?
    ) -> Bool {
        guard runtimeIdentity == self.runtimeIdentity else { return false }
        switch phase {
        case .waitingForNavigationStart:
            guard let navigationGeneration else { return true }
            return navigationGeneration > baselineNavigationGeneration
        case let .awaitingFinish(capturedGeneration):
            return navigationGeneration == capturedGeneration
        case .consumed:
            return false
        }
    }
}

/// Records the Shell's display at presentation start and any observed moves.
struct PanelPresentationDisplayMovement {
    private(set) var initialDisplayID: CGDirectDisplayID?
    private(set) var lastDisplayID: CGDirectDisplayID?
    private(set) var didMoveAcrossDisplays = false

    mutating func begin(on displayID: CGDirectDisplayID?) {
        initialDisplayID = displayID
        lastDisplayID = displayID
        didMoveAcrossDisplays = false
    }

    mutating func observe(displayID: CGDirectDisplayID?) {
        guard let displayID else { return }
        if let lastDisplayID, lastDisplayID != displayID {
            didMoveAcrossDisplays = true
        }
        lastDisplayID = displayID
    }

    mutating func reset() {
        initialDisplayID = nil
        lastDisplayID = nil
        didMoveAcrossDisplays = false
    }

    func relationship(
        to currentDisplayID: CGDirectDisplayID?,
        connectedDisplayIDs: Set<CGDirectDisplayID>
    ) -> PanelPresentationDisplayRelationship {
        guard let initialDisplayID,
              let currentDisplayID,
              connectedDisplayIDs.contains(initialDisplayID),
              connectedDisplayIDs.contains(currentDisplayID) else {
            return .unknown
        }

        guard !didMoveAcrossDisplays, initialDisplayID == currentDisplayID else {
            return .crossDisplay
        }
        return .sameDisplay
    }
}

enum PanelDismissFocusDecisionReason: String, Equatable {
    case sessionLocked
    case floatTabsNotFrontmost
    case sameDisplay
    case previousApplicationUnavailable
    case pinnedCrossDisplay
    case pinnedDisplayUnknown
    case unpinnedCrossDisplay
    case unpinnedDisplayUnknown
}

struct PanelDismissFocusDecision: Equatable {
    let shouldDeactivateApplication: Bool
    let shouldActivatePreviousApplication: Bool
    let reason: PanelDismissFocusDecisionReason

    static func resolve(
        isPinned: Bool,
        floatTabsOwnsForeground: Bool,
        displayRelationship: PanelPresentationDisplayRelationship,
        previousApplicationAvailable: Bool,
        isSessionLocked: Bool = false
    ) -> PanelDismissFocusDecision {
        if isSessionLocked {
            return PanelDismissFocusDecision(
                shouldDeactivateApplication: false,
                shouldActivatePreviousApplication: false,
                reason: .sessionLocked
            )
        }

        guard floatTabsOwnsForeground else {
            return PanelDismissFocusDecision(
                shouldDeactivateApplication: false,
                shouldActivatePreviousApplication: false,
                reason: .floatTabsNotFrontmost
            )
        }

        let shouldActivatePreviousApplication =
            displayRelationship == .sameDisplay && previousApplicationAvailable
        let shouldDeactivateApplication =
            !isPinned || displayRelationship == .sameDisplay
        let reason: PanelDismissFocusDecisionReason
        switch displayRelationship {
        case .sameDisplay:
            reason = previousApplicationAvailable ? .sameDisplay : .previousApplicationUnavailable
        case .crossDisplay:
            reason = isPinned ? .pinnedCrossDisplay : .unpinnedCrossDisplay
        case .unknown:
            reason = isPinned ? .pinnedDisplayUnknown : .unpinnedDisplayUnknown
        }

        return PanelDismissFocusDecision(
            shouldDeactivateApplication: shouldDeactivateApplication,
            shouldActivatePreviousApplication: shouldActivatePreviousApplication,
            reason: reason
        )
    }
}

struct FullscreenVisibilityIntent {
    private(set) var shouldRestoreNormalPresentation = false

    mutating func begin(wasVisible: Bool) {
        shouldRestoreNormalPresentation = wasVisible
    }

    mutating func requestPresentation() {
        shouldRestoreNormalPresentation = true
    }

    mutating func dismissPresentation() {
        shouldRestoreNormalPresentation = false
    }

    mutating func consumeRestore(currentVisibility: Bool) -> Bool {
        let restoredVisibility = currentVisibility || shouldRestoreNormalPresentation
        shouldRestoreNormalPresentation = false
        return restoredVisibility
    }
}

/// The shell is re-presented by more paths than the explicit status-item
/// show: the fullscreen restore re-presents it from inside WebKit's Space
/// teardown. Workspace activation events that macOS delivers while that
/// transition is still settling describe the pre-exit Space's frontmost
/// application rather than a fresh user choice, so a just-restored shell
/// needs the same short auto-hide grace that showFloatTabs arms.
struct WorkspaceAutoHideSuppression: Equatable {
    // A global hotkey can produce the application-activation notification
    // after several run-loop turns. Keep the stale notification from hiding
    // the presentation while its key-window handoff is still settling.
    static let graceInterval: TimeInterval = 1.5

    private(set) var deadline: TimeInterval = -.infinity

    mutating func arm(atUptime uptime: TimeInterval) {
        deadline = uptime + Self.graceInterval
    }

    func suppressesAutoHide(nowUptime uptime: TimeInterval) -> Bool {
        uptime < deadline
    }
}

enum PresentationWebFocusOwner: String, Equatable {
    case standardPresentation = "standard_presentation"
    case externalVoice = "external_voice"
}

enum PresentationNativeFocusTransferAction: Equatable {
    case sourceAlreadyKey
    case issueSourceKeyTransfer
    case waitForSourceKey
    case alreadyConsumed
}

struct PresentationNativeFocusTransferState: Equatable {
    private(set) var transferIssued = false
    private(set) var nativeFocusPending = false

    mutating func beginGeneration() {
        transferIssued = false
        nativeFocusPending = true
    }

    mutating func reset() {
        transferIssued = false
        nativeFocusPending = false
    }

    mutating func action(sourceWindowIsKey: Bool) -> PresentationNativeFocusTransferAction {
        guard nativeFocusPending else { return .alreadyConsumed }
        if sourceWindowIsKey {
            nativeFocusPending = false
            return .sourceAlreadyKey
        }
        guard !transferIssued else { return .waitForSourceKey }
        transferIssued = true
        return .issueSourceKeyTransfer
    }
}

/// Keeps native-window focus decisions pure and owner-specific. The actual
/// AppKit calls remain in the presentation owner; this policy only decides
/// which transition is allowed for the current presentation generation.
enum PresentationNativeFocusPolicy {
    static func isNativeWindowReady(
        owner: PresentationWebFocusOwner,
        applicationActive: Bool,
        shellWindowIsKey: Bool,
        sourceWindowIsKey: Bool,
        sourceSessionLocked: Bool
    ) -> Bool {
        guard applicationActive else { return false }
        if owner == .externalVoice, !sourceSessionLocked {
            return sourceWindowIsKey
        }
        return shellWindowIsKey || sourceWindowIsKey
    }

    static func shouldMakeShellKey(
        owner: PresentationWebFocusOwner,
        presentationAlreadyVisible: Bool,
        sourceWindowIsVisible: Bool,
        sourceWindowIsKey: Bool,
        sourceSessionLocked: Bool
    ) -> Bool {
        guard owner == .externalVoice,
              presentationAlreadyVisible,
              sourceWindowIsVisible,
              sourceWindowIsKey,
              !sourceSessionLocked else {
            return true
        }
        return false
    }

    static func shouldMakeSourceWindowKey(sourceWindowIsKey: Bool) -> Bool {
        !sourceWindowIsKey
    }

    static func shouldMakeSourceWindowMain(
        owner: PresentationWebFocusOwner,
        sourceSessionLocked: Bool
    ) -> Bool {
        owner == .standardPresentation && !sourceSessionLocked
    }

    static func shouldRefocusDuringSettle(owner: PresentationWebFocusOwner) -> Bool {
        owner == .standardPresentation
    }
}

/// The RemoteOrbit bridge sends one semantic scroll command per physical edge.
/// Keep delivery direct and bounded: if the WebView is not present yet, the
/// command is reported as unavailable instead of starting a retry stream that
/// can outlive the user's button press.

@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    private enum ScreenPlacementReason: Equatable {
        case explicitSummon
        case fullscreenCompanion
    }

    private struct PreviousApplicationContext {
        let application: NSRunningApplication
        /// Preserved for diagnostic compatibility only. `NSScreen.main` is
        /// not authoritative for an external application's display and this
        /// value must not drive positioning or focus restoration.
        let displayID: CGDirectDisplayID?
        /// Diagnostics-only observation. This value never participates in
        /// restore, focus, ordering, or any other business decision.
        let windowObservation: RuntimeDiagnosticExternalWindowObservation?
    }

    private struct PendingRestoreObservation {
        let ticket: RuntimeDiagnosticRestoreObservationTicket
        let application: NSRunningApplication
        let capturedWindowObservation: RuntimeDiagnosticExternalWindowObservation?
        let requestedAtUptime: TimeInterval
        var requestAccepted: Bool?
        var observationAttemptCount = 0
    }

    private enum UnreadDiagnosticSource: String {
        case explicitSelection = "explicit_selection"
        case explicitSelectionDeferred = "explicit_selection_deferred"
        case trustedManualScroll = "trusted_manual_scroll"
        case trustedAssistantPointer = "trusted_assistant_pointer"
        case generationStarted = "generation_started"
    }

    private enum UnreadDiagnosticSkipReason: String {
        case visibleCompletion = "visible_completion"
        case invalidCompletion = "invalid_completion"
        case alreadyUnread = "already_unread"
        case alreadyHandledResponse = "already_handled_response"
        case responseIdentityMismatch = "response_identity_mismatch"
        case notActuallyPresented = "not_actually_presented"
        case notActiveSlot = "not_active_slot"
        case presentationNotReady = "presentation_not_ready"
        case stateUnchanged = "state_unchanged"
    }

    private struct UnreadPresentationFacts {
        let presentationVisible: Bool
        let interactionSurfacePresented: Bool
        let webWindowKey: Bool
        let activeSlotMatches: Bool
        let sessionLocked: Bool
        let panelVisible: Bool
    }

    private struct UnreadAcknowledgementAttempt {
        let slotID: UUID
        let source: UnreadDiagnosticSource
        let facts: UnreadPresentationFacts
        let trace: RuntimeDiagnosticTrace
    }

    private let externalCommandLogger = Logger(
        subsystem: "com.lost0rz.FloatTabs",
        category: "ExternalCommand"
    )
    private let panel: FloatingPanel
    private let rootView: PanelRootView
    private let sourceHostController: FullscreenSourceHostController
    private let tabStore: TabStore
    private let webViewPool: WebViewPool
    private let attentionCoordinator: WebAttentionCoordinator
    private let diagnostics: any RuntimeDiagnosticRecording
    private let unreadResponseCoordinator: ChatGPTUnreadResponseCoordinator
    private let webFocusRouter: WebFocusRouter
    private let presentationFocusReadinessProvider: (@MainActor () -> (applicationActive: Bool, windowKey: Bool))?
    private let frameStore: PanelFrameStore
    private let confirmBrowserProfileSwitch: BrowserProfileSwitchConfirmation
    private weak var websiteCacheUsageStore: WebsiteCacheUsageStore?
    private weak var websiteCacheCleanupCoordinator: WebsiteCacheCleanupCoordinator?
    private let addressOverlayView = AddressOverlayView()
    private let statusHUDView = StatusHUDView()
    private var transientUIConstraints: [NSLayoutConstraint] = []
    private lazy var slotLifecycleCoordinator = SlotLifecycleCoordinator(
        webViewPool: webViewPool,
        container: rootView.webPanelContainerView,
        attentionProtectionQuery: { [weak self] slotID in
            self?.attentionCoordinator.isAttentionProtected(slotID) ?? false
        },
        diagnostics: diagnostics
    )

    /// Stage C routing boundary: normalized bridge observations become
    /// coordinator events, with actual visibility resolved only for
    /// completion. The owner gathers the facts; the router stays stateless.
    private lazy var attentionRouter = WebAttentionObservationRouter(
        attentionCoordinator: attentionCoordinator,
        isUserVisible: { [weak self] slotID in
            self?.isAttentionUserVisible(slotID: slotID) ?? false
        }
    )

    private var previousApplicationContext: PreviousApplicationContext?
    private var presentationDisplayMovement = PanelPresentationDisplayMovement()
    private var hideObservationTrace: RuntimeDiagnosticTrace?
    private var hideObservationGeneration: UInt64 = 0
    private var hideObservationSpaceChangeCount = 0
    private var restoreObservationTracker = RuntimeDiagnosticRestoreObservationTracker()
    private var pendingRestoreObservation: PendingRestoreObservation?
    private var restoredFrame: NSRect?
    private var preferredPanelSize: NSSize?
    private var hasPositionedPanel = false
    private var lastSynchronizedActiveID: UUID?
    private var lastSynchronizedActiveProfile: WebAppProfile?
    private let preferencesStore: AppPreferencesStore
    private(set) var isPinned = false
    private var externalMouseMonitor: Any?
    private var requestedVisibility = false
    private var pendingSlotSynchronization = false
    private var suppressTabStoreSynchronization = false
    private var unreadPruneDiagnosticSuppressionIDs: Set<UUID> = []
    private var lastPresentationUptime: TimeInterval = -.infinity
    private var workspaceAutoHideSuppression = WorkspaceAutoHideSuppression()
    private var autoHideIgnoreLastRecordedAt: [String: TimeInterval] = [:]
    private var fullscreenProfile: WebAppProfile?
    private var companionActiveProfile: WebAppProfile?
    private var fullscreenVisibilityIntent = FullscreenVisibilityIntent()
    private var shouldClampAfterFullscreen = false
    private var presentationWebFocusTask: Task<Void, Never>?
    private var presentationFocusTask: Task<Void, Never>?
    private var presentationTrace: RuntimeDiagnosticTrace?
    private var presentationActivationConfirmedGeneration: UInt64?
    /// Presentation focus is an event-driven handshake. A new request makes
    /// every older async callback stale, so a slow WebKit response cannot
    /// refocus a page that is no longer the selected presentation.
    private var presentationFocusGeneration: UInt64 = 0
    private var presentationWebFocusOwner: PresentationWebFocusOwner = .standardPresentation
    private var presentationNativeFocusPending = false
    private var presentationNativeFocusTransferState = PresentationNativeFocusTransferState()
    private var presentationWebFocusPending = false

    /// Phase 6 two-stage materialization request. Identity is independent from
    /// the presentation-focus generation above and lives only here: a pending
    /// request may materialize, attach, activate lifecycle state, focus or
    /// dismiss restoring UI only while the materialization generation, the
    /// active Slot and the exact current Runtime all still match.
    private struct PendingRuntimeMaterialization {
        let generation: UInt64
        let slotID: UUID
        let surface: RuntimePresentationSurface
        var didRecordRestoringSurfaceWindowVisibility = false
    }
    private enum RuntimePresentationSurface: Equatable {
        case standard
        case fullscreenCompanion
    }
    private enum RuntimeReadinessState: String, Equatable {
        case loading
        case ready
        case failed
    }
    private struct RuntimeReadinessRecord {
        let identity: WebRuntimeDiagnosticIdentity
        var state: RuntimeReadinessState
        var navigationGeneration: UInt64?
    }
    private struct FaviconDOMReadRecord: Equatable {
        let identity: WebRuntimeDiagnosticIdentity
        let navigationGeneration: UInt64
        let committedURL: URL
        let isManualReloadRefresh: Bool
    }
    private struct PendingColdUnreadAcknowledgement {
        let slotID: UUID
        let materializationGeneration: UInt64
        let trace: RuntimeDiagnosticTrace
    }
    private var runtimeMaterializationGeneration: UInt64 = 0
    private var pendingRuntimeMaterialization: PendingRuntimeMaterialization?
    /// Immutable runtime identity of the Runtime attached under the current
    /// pending materialization. Correlates the Outcome-A navigation finish to
    /// this exact Runtime before restoring UI may disappear.
    private var pendingRuntimeMaterializationIdentity: WebRuntimeDiagnosticIdentity?
    private var pendingColdUnreadAcknowledgement: PendingColdUnreadAcknowledgement?
    /// Exact Runtime readiness is a PanelController presentation fact. Pool
    /// residency and Slot identity alone never authorize Web content reveal.
    private var runtimeReadinessBySlot: [UUID: RuntimeReadinessRecord] = [:]
    private var faviconDOMReadBySlot: [UUID: FaviconDOMReadRecord] = [:]
    private var manualFaviconReloadIntentsBySlot: [UUID: ManualFaviconReloadIntent] = [:]
#if DEBUG
    private var debugPresentationFactOverrides: [UUID: Bool] = [:]
    private var debugInteractionSurfaceFactOverrides: [UUID: Bool] = [:]
    var debugTargetVisibleFrameOverride: NSRect?
#endif

    var isVisible: Bool {
        requestedVisibility
    }

    /// The status item and global shortcut normally toggle the requested
    /// visibility. During a WebKit fullscreen exit, however, requested state
    /// can briefly be true while the shell is physically ordered out. Treat
    /// that transition as hidden so the next shortcut re-presents the shell
    /// instead of hiding an already invisible window.
    var isPresentationActuallyVisible: Bool {
        panel.isVisible
    }

    static func shouldPresentAfterToggle(shellIsVisible: Bool) -> Bool {
        !shellIsVisible
    }

    func toggleFloatTabs(
        trace: RuntimeDiagnosticTrace? = nil,
        dismissSource: RuntimeDiagnosticDismissSource = .internal
    ) {
        let trace = trace ?? diagnostics.beginTrace(root: "panel.toggle")
        diagnostics.record(
            event: "panel.toggle.received",
            level: .info,
            subsystem: "panel",
            trace: trace
        )
        fullscreenExperimentLog(
            "TOGGLE_REQUEST requested=\(requestedVisibility) "
                + "actual=\(panel.isVisible) "
                + "session=\(sourceHostController.sessionState.rawValue)"
        )
        if Self.shouldPresentAfterToggle(shellIsVisible: panel.isVisible) {
            showFloatTabs(trace: trace)
        } else {
            hideFloatTabs(trace: trace, dismissSource: dismissSource)
        }
    }

    /// Present the shell and make its Web surface interactive. If the shell
    /// is already visible, this explicit presentation path restores focus.
    func presentFloatTabs(trace: RuntimeDiagnosticTrace? = nil) {
        presentFloatTabs(
            trace: trace,
            webFocusOwner: .standardPresentation
        )
    }

    private func presentFloatTabs(
        trace: RuntimeDiagnosticTrace? = nil,
        webFocusOwner: PresentationWebFocusOwner
    ) {
        let trace = trace ?? diagnostics.beginTrace(root: "panel.summon")
        invalidatePendingRestoreObservationForNewPresentation()
        if panel.isVisible {
            let presentationUptime = ProcessInfo.processInfo.systemUptime
            lastPresentationUptime = presentationUptime
            workspaceAutoHideSuppression.arm(atUptime: presentationUptime)
            activateFloatTabs(trace: trace)
            panel.orderFrontRegardless()
            if PresentationNativeFocusPolicy.shouldMakeShellKey(
                owner: webFocusOwner,
                presentationAlreadyVisible: true,
                sourceWindowIsVisible: sourceHostController.window.isVisible,
                sourceWindowIsKey: sourceHostController.window.isKeyWindow,
                sourceSessionLocked: sourceHostController.isSessionLocked
            ) {
                panel.makeKeyAndOrderFront(nil)
            }
            beginPresentationFocusHandshake(
                trace: trace,
                webFocusOwner: webFocusOwner
            )
            diagnostics.record(
                event: "panel.presentation.focus-requested",
                level: .debug,
                subsystem: "panel",
                trace: trace
            )
            return
        }

        showFloatTabs(trace: trace, webFocusOwner: webFocusOwner)
    }

    @discardableResult
    func prepareInputFocusForExternalVoice(
        trace: RuntimeDiagnosticTrace? = nil
    ) async -> ExternalVoiceFocusResult {
        let trace = trace ?? diagnostics.beginTrace(root: "external.voice-focus")
        invalidatePendingRestoreObservationForNewPresentation()
        diagnostics.record(
            event: "external.voice-focus.received",
            level: .info,
            subsystem: "focus",
            trace: trace
        )
        if let prePresentationWebView = selectedPresentationWebView() {
            webFocusRouter.setCurrentWebView(prePresentationWebView)
            _ = await webFocusRouter.captureInputTargetForExternalVoice()
        }

        presentFloatTabs(
            trace: trace,
            webFocusOwner: .externalVoice
        )

        guard requestedVisibility else {
            return .failed("panel-hidden")
        }
        guard let targetTabID = tabStore.activeTabID else {
            return .failed("no-active-tab")
        }
        guard let webView = selectedPresentationWebView() else {
            return .failed("no-active-webview")
        }
        let voiceGeneration = presentationFocusGeneration

        webFocusRouter.setCurrentWebView(webView)

        await Task.yield()
        guard !Task.isCancelled,
              isCurrentPresentationFocusRequest(voiceGeneration),
              presentationWebFocusOwner == .externalVoice,
              tabStore.activeTabID == targetTabID,
              selectedPresentationWebView() === webView else {
            return .failed("presentation-changed")
        }
        guard !webView.isLoading else {
            return .failed("webview-loading")
        }

        let focused = await webFocusRouter.focusInputForPresentation(
            preservingCapturedTarget: true,
            trace: trace
        )
        guard !Task.isCancelled,
              isCurrentPresentationFocusRequest(voiceGeneration),
              presentationWebFocusOwner == .externalVoice,
              tabStore.activeTabID == targetTabID,
              selectedPresentationWebView() === webView else {
            return .failed("presentation-changed")
        }
        settlePresentationWebFocus(
            generation: voiceGeneration,
            owner: .externalVoice,
            trace: trace,
            focused: focused
        )
        return focused ? .ready : .failed("dom-input-unavailable")
    }

    @discardableResult
    func scrollWebView(lines: Int) -> Bool {
        let clampedLines = min(max(lines, -40), 40)
        guard clampedLines != 0,
              let webView = selectedPresentationWebView(),
              let window = webView.window,
              window.isVisible,
              let event = makeExternalScrollEvent(lines: clampedLines, in: webView) else {
            externalCommandLogger.debug(
                "scroll unavailable lines=\(lines, privacy: .public)"
            )
            return false
        }

        webView.scrollWheel(with: event)
        externalCommandLogger.debug(
            "scroll dispatched lines=\(clampedLines, privacy: .public) key=\(window.isKeyWindow, privacy: .public)"
        )
        return true
    }

    func cancelExternalScrollCommands() {
        externalCommandLogger.debug("scroll cancel received")
    }

    private func makeExternalScrollEvent(lines: Int, in webView: WKWebView) -> NSEvent? {
        guard let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 1,
            wheel1: Int32(-lines),
            wheel2: 0,
            wheel3: 0
        ) else {
            return nil
        }

        let pagePoint = webView.convert(
            NSPoint(x: webView.bounds.midX, y: webView.bounds.midY),
            to: nil
        )
        event.location = quartzLocation(for: pagePoint)
        return NSEvent(cgEvent: event)
    }

    private func quartzLocation(for appKitPoint: NSPoint) -> CGPoint {
        guard let screen = NSScreen.screens.first(where: {
            $0.frame.contains(appKitPoint)
        }) ?? NSScreen.main else {
            return CGPoint(x: appKitPoint.x, y: appKitPoint.y)
        }

        let localX = appKitPoint.x - screen.frame.minX
        let localY = appKitPoint.y - screen.frame.minY
        let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
            as? CGDirectDisplayID
        let displayBounds = displayID.map(CGDisplayBounds)
        return CGPoint(
            x: (displayBounds?.minX ?? screen.frame.minX) + localX,
            y: (displayBounds?.minY ?? screen.frame.minY)
                + screen.frame.height
                - localY
        )
    }

    func toggleOrPresentFloatTabs(trace: RuntimeDiagnosticTrace? = nil) {
        let trace = trace ?? diagnostics.beginTrace(root: "panel.summon")
        diagnostics.record(
            event: "panel.summon.received",
            level: .info,
            subsystem: "panel",
            trace: trace
        )
        if Self.shouldHideForGlobalShortcut(shellIsVisible: panel.isVisible) {
            hideFloatTabs(trace: trace, dismissSource: .hotkey)
        } else {
            presentFloatTabs(trace: trace)
        }
    }

    static func shouldHideForGlobalShortcut(shellIsVisible: Bool) -> Bool {
        shellIsVisible
    }

    var onPanelBecameHidden: (() -> Void)?

    var acceptsAppCommands: Bool {
        Self.acceptsAppCommands(
            requestedVisibility: requestedVisibility,
            sourceSessionLocked: sourceHostController.isSessionLocked
        )
    }

    static func acceptsAppCommands(
        requestedVisibility: Bool,
        sourceSessionLocked: Bool
    ) -> Bool {
        requestedVisibility || sourceSessionLocked
    }

    var selectedSlotName: String? {
        tabStore.activeProfile?.name
    }

    var isShowingUnsupportedBrowserProfile: Bool {
        if sourceHostController.isSessionLocked {
            return sourceHostController.companionContainer.isShowingUnsupportedBrowserProfile
        }
        return rootView.webPanelContainerView.isShowingUnsupportedBrowserProfile
    }

    var displayedUnsupportedBrowserProfileName: String? {
        if sourceHostController.isSessionLocked {
            return sourceHostController.companionContainer.displayedUnsupportedBrowserProfileName
        }
        return rootView.webPanelContainerView.displayedUnsupportedBrowserProfileName
    }

    static func unsupportedBrowserProfileName(
        for profile: WebAppProfile,
        error: Error,
        browserProfiles: [BrowserProfile]
    ) -> String? {
        guard profile.browserProfileID != nil,
              let providerError = error as? BrowserProfileDataStoreProviderError,
              providerError == .customProfilesUnsupported else {
            return nil
        }

        guard let browserProfileID = profile.browserProfileID else {
            return nil
        }
        return browserProfiles.first(where: { $0.id == browserProfileID })?.name
            ?? "Selected Profile"
    }

    var selectedSlotFaviconURL: URL? {
        guard let activeProfile = tabStore.activeProfile else { return nil }
        return faviconURL(for: activeProfile)
    }

    var unreadResponseCount: Int {
        unreadResponseCoordinator.unreadSlotIDs.count
    }

    @discardableResult
    func captureStuckTabSnapshot() -> String {
        captureIncidentSnapshot(
            context: RuntimeDiagnosticIncidentContext(
                id: UUID(),
                kind: .manualSnapshot,
                trigger: "manual_stuck_tab_snapshot",
                startedAtUptime: ProcessInfo.processInfo.systemUptime
            )
        )
    }

    @discardableResult
    func captureIncidentSnapshot(
        context: RuntimeDiagnosticIncidentContext,
        slotID requestedSlotID: UUID? = nil
    ) -> String {
        var fields = diagnostics.environmentFields()
        fields.merge(context.fields(phase: .snapshot)) { _, new in new }
        fields.merge(residentAttentionDiagnosticFields()) { _, new in new }
        let snapshotEvent = context.kind == .manualSnapshot
            ? "diagnostics.stuck_tab_snapshot"
            : "diagnostics.incident_snapshot"

        if let requestedSlotID,
           tabStore.profiles.first(where: { $0.id == requestedSlotID }) == nil {
            fields["requested_slot_id"] = .string(requestedSlotID.uuidString)
            fields["capture_availability"] = .string("requested_slot_unavailable")
            fields["capture_stale"] = .bool(true)
            diagnostics.record(
                event: snapshotEvent,
                level: .notice,
                subsystem: "diagnostics",
                fields: fields
            )
            return "Snapshot recorded (requested Slot unavailable/stale)."
        }

        guard let profile = requestedSlotID
            .flatMap({ requestedID in tabStore.profiles.first { $0.id == requestedID } })
            ?? tabStore.activeProfile else {
            fields["capture_availability"] = .string("no_active_slot")
            diagnostics.record(
                event: snapshotEvent,
                level: .notice,
                subsystem: "diagnostics",
                fields: fields
            )
            return "Snapshot recorded (no active Slot)."
        }

        let slotID = profile.id
        fields["slot_id"] = .string(slotID.uuidString)
        fields["active_slot_matches"] = .bool(tabStore.activeTabID == slotID)
        fields["fullscreen_session_state"] = .string(sourceHostController.sessionState.rawValue)
        fields["fullscreen_restore_generation"] = .integer(
            Int64(sourceHostController.diagnosticRestoreGeneration)
        )
        fields["fullscreen_source_window_visible"] = .bool(sourceHostController.window.isVisible)
        fields["fullscreen_source_window_key"] = .bool(sourceHostController.window.isKeyWindow)

        guard let webView = webViewPool.existingWebView(for: slotID) else {
            fields["capture_availability"] = .string("no_resident_active_runtime")
            fields["resident"] = .bool(false)
            fields.merge(slotLifecycleCoordinator.diagnosticSnapshotFields(for: slotID)) {
                current, _ in current
            }
            diagnostics.record(
                event: snapshotEvent,
                level: .notice,
                subsystem: "diagnostics",
                fields: fields
            )
            return "Snapshot recorded (active Slot has no resident WebView)."
        }

        let normalWebView = rootView.webPanelContainerView.currentWebView
        let companionWebView = sourceHostController.companionContainer.currentWebView
        let sourceWebView = sourceHostController.diagnosticObservedWebView
        let matchesNormal = normalWebView === webView
        let matchesCompanion = companionWebView === webView
        let matchesSource = sourceWebView === webView
        let matchesSourceWindow = matchesSource && webView.window === sourceHostController.window
        let matchesFullscreenPrivateWindow = sourceHostController
            .diagnosticIsFullscreenPrivatePresentation(of: webView)
        let expectedContainer: NSView?
        if matchesCompanion {
            expectedContainer = sourceHostController.companionContainer
        } else {
            expectedContainer = rootView.webPanelContainerView
        }
        let hasExpectedAncestry = expectedContainer.map {
            webView.isDescendant(of: $0)
        } ?? false
        let role: String
        if matchesCompanion {
            role = "shell_companion"
        } else if matchesSourceWindow {
            role = "source"
        } else if matchesNormal || webView.window === panel {
            role = "shell"
        } else if matchesFullscreenPrivateWindow {
            role = "fullscreen_private"
        } else {
            role = "none_other"
        }

        fields["capture_availability"] = .string("captured")
        fields["resident"] = .bool(true)
        fields.merge(webViewPool.diagnosticSnapshotFields(for: slotID)) { current, _ in current }
        fields.merge(slotLifecycleCoordinator.diagnosticSnapshotFields(for: slotID)) {
            current, _ in current
        }
        fields["slot_residency_policy"] = .string(profile.residencyPolicy.rawValue)
        fields["pool_webview_present"] = .bool(true)
        fields["pool_matches_normal_presented_webview"] = .bool(matchesNormal)
        fields["pool_matches_companion_webview"] = .bool(matchesCompanion)
        fields["pool_matches_source_webview"] = .bool(matchesSource)
        fields["pool_webview_matches_presented"] = .bool(
            matchesNormal || matchesCompanion || matchesSourceWindow || matchesFullscreenPrivateWindow
        )
        fields["expected_container_host_relationship"] = .bool(
            hasExpectedAncestry || matchesFullscreenPrivateWindow
        )
        fields["webview_descendant_of_expected_container"] = .bool(hasExpectedAncestry)
        fields["webview_role"] = .string(role)
        fields["webview_hidden"] = .bool(webView.isHiddenOrHasHiddenAncestor)
        fields["host_hidden"] = .bool(
            webView.superview?.isHiddenOrHasHiddenAncestor ?? true
        )
        fields["window_visible"] = .bool(webView.window?.isVisible ?? false)
        fields["window_key"] = .bool(webView.window?.isKeyWindow ?? false)
        fields["frame_nonzero"] = .bool(webView.frame.width > 0 && webView.frame.height > 0)
        fields["bounds_nonzero"] = .bool(webView.bounds.width > 0 && webView.bounds.height > 0)
        let origin = webView.url.flatMap {
            RuntimeDiagnosticPrivacy.safeURLString($0, mode: .standard)
        }
        fields["origin"] = origin.map(RuntimeDiagnosticValue.string) ?? .null

        let pageURL = webView.url
        let isSupportedChatGPT = pageURL.map(ChatGPTSitePolicy.isSupportedChatGPTURL) ?? false
        fields["page_class"] = .string(isSupportedChatGPT ? "chatgpt" : "other_or_unknown")
        if isSupportedChatGPT {
            fields.merge(
                webViewPool.attentionBridge(for: slotID)?.diagnosticSnapshotFields ?? [
                    "attention_document_admitted": .bool(false),
                    "chatgpt_document_epoch": .null,
                    "chatgpt_generating": .null,
                    "attention_document_admission": .string("unavailable")
                ]
            ) { current, _ in current }
            if let responseBridge = webViewPool.responseBridge(for: slotID) {
                fields["response_current_document_ready"] = .bool(
                    responseBridge.diagnosticCurrentDocumentReady
                )
            } else {
                fields["response_current_document_ready"] = .null
            }
        }

        diagnostics.record(
            event: snapshotEvent,
            level: .notice,
            subsystem: "diagnostics",
            fields: fields
        )
        if isSupportedChatGPT {
            webViewPool.captureBoundedChatGPTHealthProbe(slotID: slotID) {
                [weak self, fields] result in
                guard let self else { return }
                var healthFields = fields
                healthFields.merge(result.diagnosticFields) { _, new in new }
                self.diagnostics.record(
                    event: "diagnostics.chatgpt_health_probe",
                    level: .notice,
                    subsystem: "diagnostics",
                    fields: healthFields
                )
            }
            webViewPool.captureBoundedChatGPTPageAppDiagnostics(slotID: slotID) {
                [weak self, fields] result in
                guard let self else { return }
                var pageAppFields = fields
                pageAppFields.merge(result.diagnosticFields) { _, new in new }
                self.diagnostics.record(
                    event: "diagnostics.chatgpt_page_app_snapshot",
                    level: .notice,
                    subsystem: "diagnostics",
                    fields: pageAppFields
                )
            }
        }
        webViewPool.captureBoundedRendererProbe(
            slotID: slotID,
            incidentID: context.id,
            completion: { _ in }
        )
        return "Snapshot recorded for active Slot."
    }

    func captureLongTermDiagnosticsCheckpoint(
        shouldRecord: @escaping @MainActor () -> Bool,
        completion: @escaping @MainActor () -> Void
    ) {
        guard shouldRecord() else {
            completion()
            return
        }

        var fields = diagnostics.environmentFields()
        fields.merge([
            "observation_source": .string("long_term_performance"),
            "resident_slot_count": .integer(Int64(webViewPool.count)),
            "panel_visible": .bool(panel.isVisible),
            "source_window_visible": .bool(sourceHostController.window.isVisible),
            "source_window_key": .bool(sourceHostController.window.isKeyWindow),
            "pinned": .bool(isPinned),
            "fullscreen_session_state": .string(sourceHostController.sessionState.rawValue),
            "fullscreen_restore_generation": .integer(
                Int64(sourceHostController.diagnosticRestoreGeneration)
            ),
            "active_slot_id": tabStore.activeTabID.map {
                .string($0.uuidString)
            } ?? .null
        ]) { _, new in new }
        fields.merge(residentAttentionDiagnosticFields()) { _, new in new }

        guard let profile = tabStore.activeProfile else {
            fields["capture_availability"] = .string("no_active_slot")
            fields["resident"] = .bool(false)
            fields["active_slot_matches"] = .bool(false)
            fields["slot_visible"] = .bool(false)
            recordLongTermDiagnosticsCheckpoint(fields, shouldRecord: shouldRecord)
            completion()
            return
        }

        let slotID = profile.id
        fields["slot_id"] = .string(slotID.uuidString)
        fields["active_slot_matches"] = .bool(tabStore.activeTabID == slotID)
        fields["slot_active"] = .bool(true)
        fields["slot_visible"] = .bool(isAttentionUserVisible(slotID: slotID))
        fields["slot_residency_policy"] = .string(profile.residencyPolicy.rawValue)
        let profileURL = profile.currentURL ?? profile.homeURL
        if let safeOrigin = RuntimeDiagnosticPrivacy.safeURLString(profileURL, mode: .standard) {
            fields["origin"] = .string(safeOrigin)
        }

        guard let webView = webViewPool.existingWebView(for: slotID) else {
            fields["capture_availability"] = .string("no_resident_active_runtime")
            fields["resident"] = .bool(false)
            fields["runtime_context_current"] = .bool(false)
            recordLongTermDiagnosticsCheckpoint(fields, shouldRecord: shouldRecord)
            completion()
            return
        }

        fields["capture_availability"] = .string("captured")
        fields["resident"] = .bool(true)
        fields.merge(webViewPool.diagnosticSnapshotFields(for: slotID)) {
            current, _ in current
        }

        let pageURL = webView.url ?? profile.currentURL ?? profile.homeURL
        let isChatGPT = ChatGPTSitePolicy.isSupportedChatGPTURL(pageURL)
        fields["page_class"] = .string(isChatGPT ? "chatgpt" : "other_or_unknown")

        if isChatGPT {
            fields.merge(webViewPool.attentionBridge(for: slotID)?.diagnosticSnapshotFields ?? [
                "attention_document_admitted": .bool(false),
                "chatgpt_document_epoch": .null,
                "chatgpt_generating": .null,
                "attention_document_admission": .string("unavailable")
            ]) { current, _ in current }
            if let responseBridge = webViewPool.responseBridge(for: slotID) {
                fields["response_current_document_ready"] = .bool(
                    responseBridge.diagnosticCurrentDocumentReady
                )
            } else {
                fields["response_current_document_ready"] = .null
            }
        }

        let runtimeIdentity = webViewPool.runtimeDiagnosticIdentity(for: slotID)
        let capturedNavigationGeneration = fields["navigation_generation"]
        let isRuntimeContextCurrent: @MainActor () -> Bool = { [weak self, weak webView] in
            guard let self,
                  let webView,
                  let runtimeIdentity,
                  self.webViewPool.existingWebView(for: slotID) === webView,
                  self.webViewPool.runtimeDiagnosticIdentity(for: slotID) == runtimeIdentity else {
                return false
            }
            return self.webViewPool.diagnosticSnapshotFields(for: slotID)["navigation_generation"]
                == capturedNavigationGeneration
        }

        guard isChatGPT, let runtimeIdentity else {
            fields["runtime_context_current"] = .bool(isRuntimeContextCurrent())
            fields["selected_slot_current"] = .bool(tabStore.activeTabID == slotID)
            if runtimeIdentity == nil {
                fields["capture_availability"] = .string("runtime_identity_unavailable")
            }
            recordLongTermDiagnosticsCheckpoint(fields, shouldRecord: shouldRecord)
            completion()
            return
        }

        webViewPool.captureBoundedChatGPTHealthProbe(slotID: slotID) {
            [weak self, fields] result in
            guard let self else {
                completion()
                return
            }
            guard shouldRecord() else {
                completion()
                return
            }

            var checkpoint = fields
            checkpoint.merge(result.diagnosticFields) { _, new in new }
            let runtimeIsCurrent = isRuntimeContextCurrent()
            let selectedSlotIsCurrent = self.tabStore.activeTabID == slotID
            checkpoint["runtime_context_current"] = .bool(runtimeIsCurrent)
            checkpoint["selected_slot_current"] = .bool(selectedSlotIsCurrent)

            guard runtimeIsCurrent, selectedSlotIsCurrent else {
                checkpoint.merge(Self.staleLongTermPageAppProbeResult(
                    documentEpoch: result.documentEpoch
                ).longTermObservationDiagnosticFields) { _, new in new }
                self.recordLongTermDiagnosticsCheckpoint(checkpoint, shouldRecord: shouldRecord)
                completion()
                return
            }

            self.webViewPool.captureBoundedChatGPTPageAppDiagnostics(slotID: slotID) {
                [weak self] pageAppResult in
                guard let self else {
                    completion()
                    return
                }
                guard shouldRecord() else {
                    completion()
                    return
                }
                checkpoint.merge(pageAppResult.longTermObservationDiagnosticFields) {
                    _, new in new
                }
                checkpoint["runtime_context_current"] = .bool(isRuntimeContextCurrent())
                checkpoint["selected_slot_current"] = .bool(self.tabStore.activeTabID == slotID)
                let workloadBridge = self.webViewPool.attentionBridge(for: slotID)
                let navigationGeneration: UInt64? = {
                    guard case let .integer(value) = fields["navigation_generation"],
                          value >= 0 else { return nil }
                    return UInt64(value)
                }()
                guard runtimeIsCurrent,
                      self.tabStore.activeTabID == slotID,
                      let workloadBridge else {
                    checkpoint["attention_workload_probe_status"] = .string("stale")
                    self.recordLongTermDiagnosticsCheckpoint(checkpoint, shouldRecord: shouldRecord)
                    completion()
                    return
                }
                Task { @MainActor [weak self, weak webView, weak workloadBridge] in
                    guard let self, let webView, let workloadBridge else {
                        completion()
                        return
                    }
                    let workloadFields = await workloadBridge.captureLongTermWorkloadDiagnosticFields(
                        for: webView,
                        runtimeIdentity: runtimeIdentity,
                        navigationGeneration: navigationGeneration,
                        contextIsCurrent: isRuntimeContextCurrent
                    )
                    guard shouldRecord() else {
                        completion()
                        return
                    }
                    checkpoint.merge(workloadFields) { _, new in new }
                    checkpoint["runtime_context_current"] = .bool(isRuntimeContextCurrent())
                    checkpoint["selected_slot_current"] = .bool(self.tabStore.activeTabID == slotID)
                    self.recordLongTermDiagnosticsCheckpoint(checkpoint, shouldRecord: shouldRecord)
                    completion()
                }
            }
        }
    }

    private func recordLongTermDiagnosticsCheckpoint(
        _ fields: [String: RuntimeDiagnosticValue],
        shouldRecord: @MainActor () -> Bool
    ) {
        guard shouldRecord() else { return }
        diagnostics.record(
            event: "diagnostics.performance_checkpoint",
            level: .notice,
            subsystem: "diagnostics",
            fields: fields
        )
    }

    private static func staleLongTermPageAppProbeResult(
        documentEpoch: UInt64?
    ) -> ChatGPTIncidentPageAppProbeResult {
        ChatGPTIncidentPageAppProbeResult(
            outcome: .stale,
            values: nil,
            documentEpoch: documentEpoch,
            latencyMilliseconds: 0,
            captureUptimeMilliseconds: Int64(ProcessInfo.processInfo.systemUptime * 1_000)
        )
    }

    func runtimeDiagnosticSnapshot() -> RuntimeDiagnosticSnapshot {
        let protectedAttentionCount = tabStore.orderedProfiles.reduce(into: 0) { count, profile in
            if attentionCoordinator.isAttentionProtected(profile.id) {
                count += 1
            }
        }
        var fields: [String: RuntimeDiagnosticValue] = [
            "requested_visibility": .bool(requestedVisibility),
            "shell_visible": .bool(panel.isVisible),
            "shell_key": .bool(panel.isKeyWindow),
            "source_visible": .bool(sourceHostController.window.isVisible),
            "source_key": .bool(sourceHostController.window.isKeyWindow),
            "app_active": .bool(NSApp.isActive),
            "shell_screen_id": .string(fullscreenExperimentScreenID(panel.screen)),
            "source_screen_id": .string(fullscreenExperimentScreenID(sourceHostController.window.screen)),
            "source_session_state": .string(sourceHostController.sessionState.rawValue),
            "fullscreen_restore_generation": .integer(Int64(sourceHostController.diagnosticRestoreGeneration)),
            "active_slot_id": tabStore.activeTabID.map { .string($0.uuidString) } ?? .null,
            "resident_slot_count": .integer(Int64(webViewPool.count)),
            "attention_ready_count": .integer(Int64(attentionCoordinator.readySlotIDs.count)),
            "attention_protected_count": .integer(Int64(protectedAttentionCount)),
            "lifecycle_pending_cold_release_count": .integer(Int64(slotLifecycleCoordinator.pendingColdReleaseCount)),
            "lifecycle_pending_warm_release_count": .integer(Int64(slotLifecycleCoordinator.pendingWarmReleaseCount)),
            "lifecycle_hidden_active_grace_pending": .bool(slotLifecycleCoordinator.isHiddenActiveGracePending),
            "focus_target": .string(webFocusRouter.currentTarget.rawValue),
            "focus_site": webFocusRouter.currentWebsiteIdentifier.map { .string($0) } ?? .null,
            "presentation_focus_generation": .integer(Int64(presentationFocusGeneration)),
            "presentation_native_focus_pending": .bool(presentationNativeFocusPending),
            "presentation_web_focus_pending": .bool(presentationWebFocusPending)
        ]
        fields.merge(residentAttentionDiagnosticFields()) { _, new in new }
        fields["pinned"] = .bool(isPinned)
        return RuntimeDiagnosticSnapshot(fields: fields)
    }

    private func residentAttentionDiagnosticFields() -> [String: RuntimeDiagnosticValue] {
        let residentSlotIDs = webViewPool.residentSlotIDs
        let generatingCount = residentSlotIDs.filter {
            attentionCoordinator.state(for: $0) == .generating
        }.count
        let readyCount = residentSlotIDs.filter {
            attentionCoordinator.state(for: $0) == .ready
        }.count
        return [
            "resident_attention_generating_count": .integer(Int64(generatingCount)),
            "resident_attention_ready_count": .integer(Int64(readyCount)),
            "resident_attention_protected_count": .integer(Int64(generatingCount))
        ]
    }

    var unreadResponseSlotIDs: Set<UUID> {
        unreadResponseCoordinator.unreadSlotIDs
    }

    var onSelectedSlotPresentationChange: ((String?, URL?) -> Void)?
    var onAttentionPresentationChange: ((Int, Bool) -> Void)?
    var onChatGPTGenerationCompleted: ((UUID) -> Void)?
    var onChatGPTUnreadCompletionMarked: ((UUID, String?, String?) -> Void)?
    var onOpenGlobalSettings: (() -> Void)?

    init(
        tabStore: TabStore,
        webViewPool: WebViewPool,
        attentionCoordinator: WebAttentionCoordinator = WebAttentionCoordinator(),
        unreadResponseStore: UnreadResponseStore? = nil,
        unreadResponseCoordinator: ChatGPTUnreadResponseCoordinator? = nil,
        frameStore: PanelFrameStore = PanelFrameStore(),
        preferencesStore: AppPreferencesStore? = nil,
        webFocusRouter: WebFocusRouter? = nil,
        confirmBrowserProfileSwitch: @escaping BrowserProfileSwitchConfirmation = PanelController.defaultBrowserProfileSwitchConfirmation,
        diagnostics: any RuntimeDiagnosticRecording = RuntimeDiagnosticNoopRecorder(),
        presentationFocusReadinessProvider: (@MainActor () -> (applicationActive: Bool, windowKey: Bool))? = nil
    ) {
        self.tabStore = tabStore
        self.webViewPool = webViewPool
        self.attentionCoordinator = attentionCoordinator
        self.diagnostics = diagnostics
        self.presentationFocusReadinessProvider = presentationFocusReadinessProvider
        self.unreadResponseCoordinator = unreadResponseCoordinator
            ?? ChatGPTUnreadResponseCoordinator(
                store: unreadResponseStore ?? UnreadResponseStore()
            )
        self.webFocusRouter = webFocusRouter ?? WebFocusRouter(diagnostics: diagnostics)
        self.frameStore = frameStore
        self.confirmBrowserProfileSwitch = confirmBrowserProfileSwitch
        let resolvedPreferencesStore = preferencesStore ?? AppPreferencesStore()
        self.preferencesStore = resolvedPreferencesStore
        let savedFrame = frameStore.loadFrame()
        restoredFrame = savedFrame
        preferredPanelSize = savedFrame?.size

        let initialFrame = NSRect(origin: .zero, size: PanelMetrics.defaultPanelSize)
        panel = FloatingPanel(contentRect: initialFrame)
        rootView = PanelRootView(preferencesStore: resolvedPreferencesStore)
        sourceHostController = FullscreenSourceHostController(
            container: rootView.webPanelContainerView,
            resizeHandle: rootView.resizeHandleView,
            resizeReadout: rootView.resizeReadoutView,
            shellWindow: panel,
            diagnostics: diagnostics
        )

        super.init()

        WebsiteFaviconProvider.shared.setDiagnosticRecorder(diagnostics)

        webViewPool.attentionStateQuery = { [weak attentionCoordinator] slotID in
            attentionCoordinator?.state(for: slotID) ?? .idle
        }

        for slotID in self.unreadResponseCoordinator.unreadSlotIDs {
            recordUnreadDiagnostic(event: "unread.state_restored", fields: [
                "slot_id": .string(slotID.uuidString)
            ])
        }

        panel.delegate = self
        panel.contentView = rootView

        sourceHostController.onSessionLockChange = { [weak self] isLocked in
            self?.handleSourceSessionLockChange(isLocked: isLocked)
        }
        sourceHostController.onSessionStateChange = { [weak self] state in
            self?.handleSourceSessionStateChange(state)
        }
        sourceHostController.onSourceRebuildRequired = { [weak self] in
            self?.rebuildFullscreenSourceAfterRestoreTimeout()
        }
        rootView.webPanelContainerView.onRetryRequested = { [weak self] in
            self?.retryFailedSelectedSlot(in: .standard)
        }
        sourceHostController.companionContainer.onRetryRequested = { [weak self] in
            self?.retryFailedSelectedSlot(in: .fullscreenCompanion)
        }

        rootView.webPanelContainerView.layer?.borderWidth = 0
        rootView.webPanelContainerView.layer?.shadowOpacity = 0
        rootView.webPanelContainerView.layer?.shadowRadius = 0
        rootView.webPanelContainerView.layer?.shadowOffset = .zero

        configureTransientUI()

        rootView.onResizeEnded = { [weak self] in
            self?.handleManualResizeEnded()
        }
        rootView.fullscreenExitPlaceholderView.onExitFullscreen = { [weak self] in
            self?.sourceHostController.requestFullscreenExit()
        }
        configureSlotInteractions()
        configurePreferenceObservers()
        synchronizePreferencePresentation()
        rootView.externalControlZoneView.setPinned(isPinned)
        synchronizePinnedPresentation()
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(workspaceDidActivateApplication(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(workspaceDidChangeActiveSpace(_:)),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange(_:)),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive(_:)),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
        externalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            let eventTimestamp = event.timestamp
            let mouseLocation = NSEvent.mouseLocation
            Task { @MainActor [weak self] in
                self?.handleExternalMouseDown(
                    eventTimestamp: eventTimestamp,
                    mouseLocation: mouseLocation
                )
            }
        }

        webViewPool.onResidentSetChange = { [weak self] in
            self?.synchronizeResidentIndicators()
        }
        webViewPool.onIncidentRequest = { [weak self] slotID, context in
            self?.captureIncidentSnapshot(context: context, slotID: slotID)
        }
        webViewPool.onAttentionEvent = { [weak self] slotID, event in
            self?.handleAttentionEvent(slotID: slotID, event: event)
        }
        webViewPool.onAttentionObservation = { [weak self] slotID, observation in
            self?.handleAttentionEvent(
                slotID: slotID,
                event: ChatGPTAttentionEvent(
                    observation: observation,
                    responseIdentity: nil
                )
            )
        }
        webViewPool.onTrustedInteractionEvent = { [weak self] slotID, event in
            self?.handleTrustedInteraction(slotID: slotID, event: event)
        }
        webViewPool.onCommittedURLChange = { [weak self] slotID, url in
            self?.handleCommittedURLChange(slotID: slotID, url: url)
        }
        webViewPool.onSlotNavigationStart = { [weak self] slotID, identity, navigationGeneration in
            self?.handleSlotNavigationStart(
                slotID: slotID,
                runtimeIdentity: identity,
                navigationGeneration: navigationGeneration
            )
        }
        webViewPool.onSlotNavigationFinish = { [weak self] slotID, identity, navigationGeneration in
            self?.handleSlotNavigationFinish(
                slotID: slotID,
                runtimeIdentity: identity,
                navigationGeneration: navigationGeneration
            )
        }
        webViewPool.onSlotNavigationFailure = { [weak self] slotID, identity, navigationGeneration in
            self?.handleSlotNavigationFailure(
                slotID: slotID,
                runtimeIdentity: identity,
                navigationGeneration: navigationGeneration
            )
        }
        webViewPool.onRuntimeRecoveryStart = { [weak self] slotID, identity in
            self?.handleRuntimeRecoveryStart(slotID: slotID, runtimeIdentity: identity)
        }
        webViewPool.onRuntimeRecoveryUnavailable = { [weak self] slotID, identity in
            self?.handleRuntimeRecoveryUnavailable(slotID: slotID, runtimeIdentity: identity)
        }
        tabStore.onChange = { [weak self] in
            guard let self, !self.suppressTabStoreSynchronization else { return }
            self.synchronizeSlotState()
        }
        synchronizeSlotState()
    }

    deinit {
        presentationFocusTask?.cancel()
        presentationWebFocusTask?.cancel()
        if let externalMouseMonitor {
            NSEvent.removeMonitor(externalMouseMonitor)
        }
        NotificationCenter.default.removeObserver(
            self,
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.removeObserver(
            self,
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.removeObserver(
            self,
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        NotificationCenter.default.removeObserver(
            self,
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NotificationCenter.default.removeObserver(
            self,
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    func prepareForStatusItemPresentation(trace: RuntimeDiagnosticTrace? = nil) {
        guard !requestedVisibility else { return }
        invalidatePendingRestoreObservationForNewPresentation()
        capturePreviousApplication(trace: trace)
        activateFloatTabs(trace: trace)
    }

    func prepareForExplicitActivation() {
        invalidatePendingRestoreObservationForNewPresentation()
    }

    func showFloatTabs(trace: RuntimeDiagnosticTrace? = nil) {
        showFloatTabs(
            trace: trace,
            webFocusOwner: .standardPresentation
        )
    }

    private func showFloatTabs(
        trace: RuntimeDiagnosticTrace? = nil,
        webFocusOwner: PresentationWebFocusOwner
    ) {
        let trace = trace ?? diagnostics.beginTrace(root: "panel.summon")
        presentationDisplayMovement.reset()
        invalidatePendingRestoreObservationForNewPresentation()
        var presentationFields = runtimeDiagnosticSnapshot().fields
        presentationFields["requested_before"] = .bool(requestedVisibility)
        diagnostics.record(
            event: "panel.presentation.begin",
            level: .notice,
            subsystem: "panel",
            trace: trace,
            fields: presentationFields
        )
        let presentationUptime = ProcessInfo.processInfo.systemUptime
        fullscreenExperimentLog(
            "SHOW_REQUEST requestedBefore=\(requestedVisibility) "
                + "session=\(sourceHostController.sessionState.rawValue) "
                + "panelVisible=\(panel.isVisible)"
        )
        lastPresentationUptime = presentationUptime
        workspaceAutoHideSuppression.arm(atUptime: presentationUptime)
        updateRequestedVisibility(true)
        synchronizeAppearance()
        guard !sourceHostController.isSessionLocked else {
            cancelPendingRuntimeMaterialization(reason: "session_locked")
            fullscreenVisibilityIntent.requestPresentation()
            panel.orderOut(nil)
            showFullscreenCompanionIfReady()
            return
        }

        capturePreviousApplication(trace: trace)
        positionPanelForCurrentScreens(
            trace: trace,
            reason: .explicitSummon
        )
        synchronizeFixedViewportAfterPositioning()
        synchronizeSourceHostFrame(display: false)
        slotLifecycleCoordinator.setPanelVisible(true, activeProfile: tabStore.activeProfile)
        synchronizeSlotState()
        panel.orderFrontRegardless()
        activateFloatTabs(trace: trace)
        panel.makeKeyAndOrderFront(nil)
        presentationDisplayMovement.begin(
            on: ScreenPositioning.displayID(forWindowFrame: panel.frame)
        )
        recordRestoringSurfaceWindowVisibilityIfNeeded()
        beginPresentationFocusHandshake(
            trace: trace,
            webFocusOwner: webFocusOwner
        )
        acknowledgeActiveAttentionIfActuallyPresented()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            fullscreenExperimentLog(
                "SHOW shell=\(self.panel.windowNumber) source=\(self.sourceHostController.window.windowNumber) "
                    + "shellScreen=\(fullscreenExperimentScreenID(self.panel.screen)) "
                    + "sourceScreen=\(fullscreenExperimentScreenID(self.sourceHostController.window.screen)) "
                    + "shellKey=\(self.panel.isKeyWindow) "
                    + "sourceKey=\(self.sourceHostController.window.isKeyWindow) "
                    + "sourceVisible=\(self.sourceHostController.window.isVisible)"
            )
        }
    }

    func hideFloatTabs(
        trace: RuntimeDiagnosticTrace? = nil,
        dismissSource: RuntimeDiagnosticDismissSource = .internal
    ) {
        let trace = trace ?? diagnostics.beginTrace(root: "panel.dismiss")
        let wasVisible = requestedVisibility
        let isPinnedBeforeHide = isPinned
        let applicationActiveBeforeHide = NSApp.isActive
        let frontmostApplicationBeforeHide = NSWorkspace.shared.frontmostApplication
        let frontmostProcessIdentifierBeforeHide =
            frontmostApplicationBeforeHide?.processIdentifier
        let ownProcessIdentifier = ProcessInfo.processInfo.processIdentifier
        let shellKeyBeforeHide = panel.isKeyWindow
        let sourceKeyBeforeHide = sourceHostController.window.isKeyWindow
        let previousApplication = previousApplicationContext
        let previousApplicationAvailable = previousApplication.map {
            !$0.application.isTerminated
                && $0.application.processIdentifier != ownProcessIdentifier
        } ?? false
        let connectedDisplayFrames = ScreenPositioning.connectedDisplayFrames()
        let connectedDisplayIDs = Set(connectedDisplayFrames.map { $0.displayID })
        let currentShellDisplayID = ScreenPositioning.displayID(
            forWindowFrame: panel.frame,
            displayFrames: connectedDisplayFrames
        )
        let initialShellDisplayID = presentationDisplayMovement.initialDisplayID
        let displayRelationship = presentationDisplayMovement.relationship(
            to: currentShellDisplayID,
            connectedDisplayIDs: connectedDisplayIDs
        )
        let floatTabsOwnsForeground = applicationActiveBeforeHide
            && frontmostProcessIdentifierBeforeHide == ownProcessIdentifier
        let sessionLockedBeforeHide = sourceHostController.isSessionLocked
        let focusDecision = PanelDismissFocusDecision.resolve(
            isPinned: isPinnedBeforeHide,
            floatTabsOwnsForeground: floatTabsOwnsForeground,
            displayRelationship: displayRelationship,
            previousApplicationAvailable: previousApplicationAvailable,
            isSessionLocked: sessionLockedBeforeHide
        )
        hideObservationGeneration &+= 1
        let observationGeneration = hideObservationGeneration
        hideObservationTrace = trace
        hideObservationSpaceChangeCount = 0
        defer { presentationDisplayMovement.reset() }

        var hideBeginFields = panelHideObservationFields()
        hideBeginFields["application_active_before_hide"] = .bool(applicationActiveBeforeHide)
        hideBeginFields["frontmost_process_identifier_before_hide"] =
            frontmostProcessIdentifierBeforeHide.map { .integer(Int64($0)) } ?? .null
        hideBeginFields["float_tabs_frontmost_before_hide"] = .bool(
            frontmostProcessIdentifierBeforeHide == ownProcessIdentifier
        )
        hideBeginFields["float_tabs_owns_foreground_before_hide"] = .bool(
            floatTabsOwnsForeground
        )
        hideBeginFields["shell_key_before_hide"] = .bool(shellKeyBeforeHide)
        hideBeginFields["source_key_before_hide"] = .bool(sourceKeyBeforeHide)
        hideBeginFields["pinned_before_hide"] = .bool(isPinnedBeforeHide)
        hideBeginFields["initial_shell_display_id"] =
            initialShellDisplayID.map { .integer(Int64($0)) } ?? .null
        hideBeginFields["current_shell_display_id"] =
            currentShellDisplayID.map { .integer(Int64($0)) } ?? .null
        hideBeginFields["display_relationship"] = .string(displayRelationship.rawValue)
        hideBeginFields["explicit_cross_display_move"] = .bool(
            presentationDisplayMovement.didMoveAcrossDisplays
        )
        hideBeginFields["previous_application_available"] = .bool(
            previousApplicationAvailable
        )
        if let frontmostApplicationBeforeHide,
           let bundleIdentifier = RuntimeDiagnosticPrivacy.safeBundleIdentifier(
               frontmostApplicationBeforeHide.bundleIdentifier
           ) {
            hideBeginFields["frontmost_application_bundle_id_before_hide"] = bundleIdentifier
        }
        diagnostics.record(
            event: "panel.hide.begin",
            level: .notice,
            subsystem: "panel",
            trace: trace,
            fields: hideBeginFields
        )

        diagnostics.record(
            event: "panel.hide.focus.decision",
            level: .info,
            subsystem: "panel",
            trace: trace,
            fields: [
                "reason": .string(focusDecision.reason.rawValue),
                "pinned": .bool(isPinnedBeforeHide),
                "application_active": .bool(applicationActiveBeforeHide),
                "frontmost_process_identifier":
                    frontmostProcessIdentifierBeforeHide.map { .integer(Int64($0)) } ?? .null,
                "float_tabs_owns_foreground": .bool(floatTabsOwnsForeground),
                "display_relationship": .string(displayRelationship.rawValue),
                "initial_shell_display_id":
                    initialShellDisplayID.map { .integer(Int64($0)) } ?? .null,
                "current_shell_display_id":
                    currentShellDisplayID.map { .integer(Int64($0)) } ?? .null,
                "explicit_cross_display_move": .bool(
                    presentationDisplayMovement.didMoveAcrossDisplays
                ),
                "previous_application_available": .bool(previousApplicationAvailable),
                "allow_application_deactivation": .bool(
                    focusDecision.shouldDeactivateApplication
                ),
                "allow_previous_application_activation": .bool(
                    focusDecision.shouldActivatePreviousApplication
                )
            ]
        )
        diagnostics.record(
            event: "panel.dismiss.focus-release.decision",
            level: .info,
            subsystem: "panel",
            trace: trace,
            fields: [
                "pinned": .bool(isPinnedBeforeHide),
                "panel_moved_across_displays": .bool(
                    presentationDisplayMovement.didMoveAcrossDisplays
                ),
                "application_deactivation_requested": .bool(
                    focusDecision.shouldDeactivateApplication
                ),
                "previous_application_activation_allowed": .bool(
                    focusDecision.shouldActivatePreviousApplication
                ),
                "reason": .string(focusDecision.reason.rawValue),
                "shell_key_before_hide": .bool(shellKeyBeforeHide),
                "source_key_before_hide": .bool(sourceKeyBeforeHide)
            ]
        )
        finishPendingRestoreObservationAsSuperseded()
        recordDismissBegin(
            trace: trace,
            source: dismissSource,
            wasVisible: wasVisible
        )
        let cancelledPresentationTrace = self.presentationTrace
        if presentationNativeFocusPending || presentationWebFocusPending {
            diagnostics.record(
                event: "presentation_focus.cancelled",
                level: .notice,
                subsystem: "panel",
                trace: cancelledPresentationTrace,
                fields: [
                    "focus_generation": .integer(Int64(presentationFocusGeneration)),
                    "focus_owner": .string(presentationWebFocusOwner.rawValue),
                    "reason": .string("presentation_dismissed")
                ]
            )
        }
        fullscreenExperimentLog(
            "HIDE_REQUEST requestedBefore=\(wasVisible) "
                + "session=\(sourceHostController.sessionState.rawValue) "
                + "panelVisible=\(panel.isVisible)"
        )
        updateRequestedVisibility(false)
        if wasVisible { onPanelBecameHidden?() }
        presentationFocusTask?.cancel()
        presentationFocusTask = nil
        presentationWebFocusTask?.cancel()
        presentationWebFocusTask = nil
        self.presentationTrace = nil
        presentationWebFocusOwner = .standardPresentation
        presentationActivationConfirmedGeneration = nil
        presentationNativeFocusPending = false
        presentationNativeFocusTransferState.reset()
        presentationWebFocusPending = false
        cancelPendingRuntimeMaterialization(reason: "panel_dismissed")
        addressOverlayView.dismiss()
        persistPanelFrame()
        panel.orderOut(nil)
        recordHideObservation(
            event: "panel.hide.shell.orderOut.completed",
            trace: trace
        )

        guard !sessionLockedBeforeHide else {
            fullscreenVisibilityIntent.dismissPresentation()
            tearDownFullscreenCompanion(
                pauseInactiveMedia: true,
                hidePanel: true
            )
            recordHideObservation(
                event: "panel.hide.source.orderOut.completed",
                trace: trace,
                fields: ["source_order_out_path": .string("fullscreen_guard")]
            )
            completeHideObservation(
                trace: trace,
                wasVisible: wasVisible,
                source: dismissSource,
                generation: observationGeneration
            )
            return
        }

        sourceHostController.orderOutIfSafe()
        recordHideObservation(
            event: "panel.hide.source.orderOut.completed",
            trace: trace
        )
        slotLifecycleCoordinator.setPanelVisible(false, activeProfile: tabStore.activeProfile)

        if focusDecision.shouldDeactivateApplication {
            NSApp.deactivate()
        } else {
            diagnostics.record(
                event: "app.deactivation.skipped",
                level: .notice,
                subsystem: "app",
                trace: trace,
                fields: ["reason": .string(focusDecision.reason.rawValue)]
            )
        }

        previousApplicationContext = nil
        guard let previousApplication else {
            diagnostics.record(
                event: "previous_app.restore.decision",
                level: .info,
                subsystem: "panel",
                trace: trace,
                fields: ["has_context": .bool(false)]
            )
            diagnostics.record(
                event: "previous_app.restore.skipped",
                level: .notice,
                subsystem: "panel",
                trace: trace,
                fields: ["reason": .string("no_context")]
            )
            completeHideObservation(
                trace: trace,
                wasVisible: wasVisible,
                source: dismissSource,
                generation: observationGeneration
            )
            return
        }

        diagnostics.record(
            event: "previous_app.restore.decision",
            level: .info,
            subsystem: "panel",
            trace: trace,
            fields: [
                "has_context": .bool(true),
                "previous_application_available": .bool(previousApplicationAvailable),
                "panel_moved_across_displays": .bool(
                    presentationDisplayMovement.didMoveAcrossDisplays
                ),
                "display_relationship": .string(displayRelationship.rawValue),
                "explicit_activation_allowed": .bool(
                    focusDecision.shouldActivatePreviousApplication
                )
            ]
        )
        guard focusDecision.shouldActivatePreviousApplication,
              previousApplicationAvailable else {
            let reason = !previousApplicationAvailable
                ? "previous_application_unavailable"
                : focusDecision.reason.rawValue
            diagnostics.record(
                event: "previous_app.restore.skipped",
                level: .notice,
                subsystem: "panel",
                trace: trace,
                fields: [
                    "reason": .string(reason),
                    "previous_display_id": .integer(Int64(previousApplication.displayID ?? 0)),
                    "current_display_id": currentShellDisplayID.map {
                        .integer(Int64($0))
                    } ?? .null
                ]
            )
            completeHideObservation(
                trace: trace,
                wasVisible: wasVisible,
                source: dismissSource,
                generation: observationGeneration
            )
            return
        }
        var restoredFields: [String: RuntimeDiagnosticValue] = [
            "previous_display_id": .integer(Int64(previousApplication.displayID ?? 0)),
            "current_display_id": currentShellDisplayID.map {
                .integer(Int64($0))
            } ?? .null
        ]
        if let bundleIdentifier = RuntimeDiagnosticPrivacy.safeBundleIdentifier(
            previousApplication.application.bundleIdentifier
        ) {
            restoredFields["application_bundle_id"] = bundleIdentifier
        }
        var restoreRequestFields = restoredFields
        restoreRequestFields["requested"] = .bool(true)
        diagnostics.record(
            event: "previous_app.restore.requested",
            level: .info,
            subsystem: "panel",
            trace: trace,
            fields: restoreRequestFields
        )
        let observationTicket = restoreObservationTracker.begin(trace: trace)
        pendingRestoreObservation = PendingRestoreObservation(
            ticket: observationTicket,
            application: previousApplication.application,
            capturedWindowObservation: previousApplication.windowObservation,
            requestedAtUptime: ProcessInfo.processInfo.systemUptime,
            requestAccepted: nil
        )
        let activationAccepted = previousApplication.application.activate(options: [])
        if var pendingRestoreObservation,
           pendingRestoreObservation.ticket == observationTicket {
            pendingRestoreObservation.requestAccepted = activationAccepted
            self.pendingRestoreObservation = pendingRestoreObservation
        }
        restoreRequestFields["accepted"] = .bool(activationAccepted)
        diagnostics.record(
            event: "previous_app.restore.request_result",
            level: activationAccepted ? .notice : .warning,
            subsystem: "panel",
            trace: trace,
            fields: restoreRequestFields
        )
        scheduleRestoreObservation(observationTicket)
        completeHideObservation(
            trace: trace,
            wasVisible: wasVisible,
            source: dismissSource,
            generation: observationGeneration
        )
    }

    private func invalidatePendingRestoreObservationForNewPresentation() {
        finishPendingRestoreObservationAsSuperseded()
    }

    private func finishPendingRestoreObservationAsSuperseded() {
        guard let pending = pendingRestoreObservation else {
            restoreObservationTracker.invalidate()
            return
        }
        pendingRestoreObservation = nil
        restoreObservationTracker.invalidate()
        var fields: [String: RuntimeDiagnosticValue] = [
            "observation_state": .string("terminal"),
            "terminal_outcome": .string("superseded"),
            "observation_attempt": .integer(Int64(pending.observationAttemptCount)),
            "restore_request_accepted": pending.requestAccepted.map(RuntimeDiagnosticValue.bool)
                ?? .null,
            "elapsed_uptime": .double(
                max(0, ProcessInfo.processInfo.systemUptime - pending.requestedAtUptime)
            )
        ]
        fields["requested_application_process_identifier"] = .integer(
            Int64(pending.application.processIdentifier)
        )
        if let bundleIdentifier = RuntimeDiagnosticPrivacy.safeBundleIdentifier(
            pending.application.bundleIdentifier
        ) {
            fields["requested_application_bundle_id"] = bundleIdentifier
        }
        diagnostics.record(
            event: "previous_app.restore.terminal",
            level: .notice,
            subsystem: "panel",
            trace: pending.ticket.trace,
            fields: fields
        )
    }

    private func recordDismissBegin(
        trace: RuntimeDiagnosticTrace,
        source: RuntimeDiagnosticDismissSource,
        wasVisible: Bool,
        reason: String? = nil
    ) {
        var fields = runtimeDiagnosticSnapshot().fields
        fields["requested_before"] = .bool(wasVisible)
        fields["dismiss_source"] = .string(source.rawValue)
        fields["dismiss_classification"] = .string(source.classification.rawValue)
        fields["requested_visibility_before"] = .bool(wasVisible)
        fields["shell_visible_before"] = .bool(panel.isVisible)
        fields["source_visible_before"] = .bool(sourceHostController.window.isVisible)
        fields["app_active_before"] = .bool(NSApp.isActive)
        fields["previous_app_context_exists"] = .bool(previousApplicationContext != nil)
        fields["panel_visible_before"] = .bool(panel.isVisible)
        fields["dismiss_already_hidden"] = .bool(!wasVisible && !panel.isVisible)
        if let reason {
            fields["reason"] = .string(reason)
        }
        diagnostics.record(
            event: "panel.dismiss.begin",
            level: .notice,
            subsystem: "panel",
            trace: trace,
            fields: fields
        )
    }

    private func recordDismissCompleted(
        trace: RuntimeDiagnosticTrace,
        wasVisible: Bool,
        source: RuntimeDiagnosticDismissSource
    ) {
        var fields = runtimeDiagnosticSnapshot().fields
        fields["requested_before"] = .bool(wasVisible)
        fields["dismiss_source"] = .string(source.rawValue)
        fields["dismiss_classification"] = .string(source.classification.rawValue)
        diagnostics.record(
            event: "panel.dismiss.completed",
            level: .notice,
            subsystem: "panel",
            trace: trace,
            fields: fields
        )
    }

    private func panelHideObservationFields() -> [String: RuntimeDiagnosticValue] {
        let connectedDisplayFrames = ScreenPositioning.connectedDisplayFrames()
        let connectedDisplayIDs = Set(connectedDisplayFrames.map { $0.displayID })
        let shellDisplayID = ScreenPositioning.displayID(
            forWindowFrame: panel.frame,
            displayFrames: connectedDisplayFrames
        )
        let sourceDisplayID = ScreenPositioning.displayID(
            forWindowFrame: sourceHostController.window.frame,
            displayFrames: connectedDisplayFrames
        )
        let frontmostApplication = NSWorkspace.shared.frontmostApplication

        return [
            "application_active": .bool(NSApp.isActive),
            "frontmost_process_identifier": frontmostApplication.map {
                .integer(Int64($0.processIdentifier))
            } ?? .null,
            "shell_visible": .bool(panel.isVisible),
            "source_visible": .bool(sourceHostController.window.isVisible),
            "shell_key_window": .bool(panel.isKeyWindow),
            "source_key_window": .bool(sourceHostController.window.isKeyWindow),
            "shell_display_id": shellDisplayID.map { .integer(Int64($0)) } ?? .null,
            "source_display_id": sourceDisplayID.map { .integer(Int64($0)) } ?? .null,
            "shell_display_connected": .bool(
                shellDisplayID.map { connectedDisplayIDs.contains($0) } ?? false
            ),
            "source_display_connected": .bool(
                sourceDisplayID.map { connectedDisplayIDs.contains($0) } ?? false
            ),
            "pinned": .bool(isPinned),
            "space_change_notification_count": .integer(
                Int64(hideObservationSpaceChangeCount)
            )
        ]
    }

    private func recordHideObservation(
        event: String,
        trace: RuntimeDiagnosticTrace,
        fields additionalFields: [String: RuntimeDiagnosticValue] = [:]
    ) {
        var fields = panelHideObservationFields()
        fields.merge(additionalFields) { _, newer in newer }
        diagnostics.record(
            event: event,
            level: .notice,
            subsystem: "panel",
            trace: trace,
            fields: fields
        )
    }

    private func completeHideObservation(
        trace: RuntimeDiagnosticTrace,
        wasVisible: Bool,
        source: RuntimeDiagnosticDismissSource,
        generation: UInt64
    ) {
        recordHideObservation(event: "panel.hide.completed", trace: trace)
        recordDismissCompleted(trace: trace, wasVisible: wasVisible, source: source)
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.hideObservationGeneration == generation else {
                return
            }
            self.recordHideObservation(
                event: "panel.hide.next_main_turn",
                trace: trace
            )
            self.hideObservationTrace = nil
            self.hideObservationSpaceChangeCount = 0
        }
    }

    func prepareForTermination(trace: RuntimeDiagnosticTrace? = nil) {
        diagnostics.record(
            event: "app.termination.panel-preparation",
            level: .notice,
            subsystem: "app",
            trace: trace
        )
        cancelPendingRuntimeMaterialization(reason: "app_terminating")
        persistPanelFrame()
    }

    func storedWebAppStateSnapshot() -> StoredWebAppState {
        tabStore.storedStateSnapshot()
    }

    func websiteCacheCleanupCoordinator(
        preferencesStore: AppPreferencesStore,
        usageStore: WebsiteCacheUsageStore,
        sizeMeasurer: WebsiteCacheSizeMeasurer? = nil
    ) -> WebsiteCacheCleanupCoordinator {
        websiteCacheUsageStore = usageStore
        tabStore.onUserProfileUse = { [weak usageStore] browserProfileID, date in
            usageStore?.recordUse(
                of: BrowserProfileIdentity(browserProfileID: browserProfileID),
                at: date
            )
        }

        let service = WebsiteCacheCleanupService(
            dataStoreResolver: { [weak self] identity in
                guard let self else {
                    throw WebsiteCacheCleanupServiceError.dataStoreUnavailable
                }
                return try self.webViewPool.websiteDataStore(for: identity)
            }
        )

        let resolvedSizeMeasurer = sizeMeasurer ?? WebsiteCacheSizeMeasurer(
            profileIdentifiersProvider: { [weak self] in
                Set(self?.tabStore.browserProfiles.map(\.id) ?? [])
            }
        )

        let coordinator = WebsiteCacheCleanupCoordinator(
            preferencesStore: preferencesStore,
            usageStore: usageStore,
            service: service,
            sizeMeasurer: resolvedSizeMeasurer,
            profilesProvider: { [weak self, weak usageStore] in
                self?.websiteCacheProfileSnapshots(usageStore: usageStore) ?? []
            },
            activeIdentityProvider: { [weak self] in
                guard let activeProfile = self?.tabStore.activeProfile else { return nil }
                return BrowserProfileIdentity(browserProfileID: activeProfile.browserProfileID)
            },
            panelVisibilityProvider: { [weak self] in self?.isVisible ?? false },
            prepareRuntime: { [weak self] identity, allowActive in
                guard let self else {
                    throw WebsiteCacheManagementError.runtimeStillInUse
                }
                try self.prepareForWebsiteCacheCleanup(
                    identity: identity,
                    allowActive: allowActive
                )
            },
            restoreRuntime: { [weak self] in
                self?.restoreAfterWebsiteCacheCleanup()
            }
        )
        websiteCacheCleanupCoordinator = coordinator
        return coordinator
    }

    func websiteDataStore(for identity: BrowserProfileIdentity) throws -> WKWebsiteDataStore {
        try webViewPool.websiteDataStore(for: identity)
    }

    private func websiteCacheProfileSnapshots(
        usageStore: WebsiteCacheUsageStore?
    ) -> [WebsiteCacheProfileSnapshot] {
        var lastUsedByIdentity: [BrowserProfileIdentity: Date] = [:]
        var residencyByIdentity: [BrowserProfileIdentity: SlotResidencyPolicy] = [:]
        var identities = Set<BrowserProfileIdentity>([.default])

        for profile in tabStore.profiles {
            let identity = BrowserProfileIdentity(browserProfileID: profile.browserProfileID)
            identities.insert(identity)
            lastUsedByIdentity[identity] = max(
                lastUsedByIdentity[identity] ?? .distantPast,
                profile.lastUsedAt
            )
            let existingResidency = residencyByIdentity[identity] ?? .cold
            residencyByIdentity[identity] = SlotResidencyPolicy.mostProtective(
                existingResidency,
                profile.residencyPolicy
            )
        }
        for browserProfile in tabStore.browserProfiles {
            identities.insert(.custom(browserProfile.id))
        }
        usageStore?.prune(keeping: identities)

        let activeIdentity = tabStore.activeProfile.map {
            BrowserProfileIdentity(browserProfileID: $0.browserProfileID)
        }
        return identities.map { identity in
            let entry = usageStore?.entry(for: identity) ?? .empty
            return WebsiteCacheProfileSnapshot(
                identity: identity,
                lastUsedAt: lastUsedByIdentity[identity]
                    ?? entry.lastUsedAt
                    ?? .distantPast,
                useCount: entry.useCount30Days,
                isActive: identity == activeIdentity,
                residencyPolicy: residencyByIdentity[identity] ?? .warm
            )
        }
    }

    private func prepareForWebsiteCacheCleanup(
        identity: BrowserProfileIdentity,
        allowActive: Bool
    ) throws {
        guard !sourceHostController.isSessionLocked else {
            throw WebsiteCacheManagementError.runtimeStillInUse
        }

        let activeIdentity = tabStore.activeProfile.map {
            BrowserProfileIdentity(browserProfileID: $0.browserProfileID)
        }
        if activeIdentity == identity,
           isVisible,
           !allowActive {
            throw WebsiteCacheManagementError.activeProfileProtected
        }

        for slotID in webViewPool.residentSlotIDs(using: identity) {
            slotLifecycleCoordinator.remove(slotID: slotID)
            webViewPool.release(slotID: slotID)
        }
        guard webViewPool.residentSlotIDs(using: identity).isEmpty else {
            throw WebsiteCacheManagementError.runtimeStillInUse
        }
    }

    private func restoreAfterWebsiteCacheCleanup() {
        guard !sourceHostController.isSessionLocked else { return }
        synchronizeSlotState()
    }

    func browserProfileManagementClient(
        usageStore: WebsiteCacheUsageStore? = nil
    ) -> BrowserProfileManagementClient {
        BrowserProfileManagementClient(
            snapshot: { [weak self] in
                self?.browserProfileManagementSnapshot()
                    ?? BrowserProfileManagementSnapshot(
                        customProfiles: [],
                        referencedProfileIDs: [],
                        customProfilesSupported: false
                    )
            },
            create: { [weak self] name in
                guard let self else { throw BrowserProfileManagementError.notFound }
                return try self.createBrowserProfile(name: name)
            },
            rename: { [weak self] id, name in
                guard let self else { throw BrowserProfileManagementError.notFound }
                try self.renameBrowserProfile(id: id, name: name)
            },
            delete: { [weak self] id in
                guard let self else { throw BrowserProfileManagementError.notFound }
                try await self.deleteBrowserProfile(id: id, usageStore: usageStore)
            }
        )
    }

    func browserProfileManagementSnapshot() -> BrowserProfileManagementSnapshot {
        var referencingWebAppNamesByProfileID: [UUID: [String]] = [:]
        for profile in tabStore.profiles {
            guard let browserProfileID = profile.browserProfileID else { continue }
            referencingWebAppNamesByProfileID[browserProfileID, default: []].append(profile.name)
        }
        return BrowserProfileManagementSnapshot(
            customProfiles: tabStore.browserProfiles,
            defaultProfilePresentation: tabStore.defaultBrowserProfilePresentation,
            referencedProfileIDs: Set(referencingWebAppNamesByProfileID.keys),
            referencingWebAppNamesByProfileID: referencingWebAppNamesByProfileID,
            customProfilesSupported: webViewPool.customBrowserProfilesSupported
        )
    }

    static func canRequestBrowserProfileSwitch(
        currentProfileID: UUID?,
        targetProfileID: UUID?,
        targetExists: Bool,
        customProfilesSupported: Bool,
        sessionIsLocked: Bool
    ) -> Bool {
        guard targetProfileID == nil || targetExists else { return false }
        guard currentProfileID != targetProfileID else { return true }
        guard !sessionIsLocked else { return false }
        guard targetProfileID == nil || customProfilesSupported else { return false }
        return true
    }

    @discardableResult
    func requestBrowserProfileSwitch(
        slotID: UUID,
        targetProfileID: UUID?
    ) -> Bool {
        guard let sourceProfile = tabStore.profiles.first(where: { $0.id == slotID }) else {
            NSSound.beep()
            return false
        }

        let targetProfile = targetProfileID.flatMap { targetID in
            tabStore.browserProfiles.first(where: { $0.id == targetID })
        }
        let targetExists = targetProfileID == nil || targetProfile != nil
        guard Self.canRequestBrowserProfileSwitch(
            currentProfileID: sourceProfile.browserProfileID,
            targetProfileID: targetProfileID,
            targetExists: targetExists,
            customProfilesSupported: webViewPool.customBrowserProfilesSupported,
            sessionIsLocked: sourceHostController.isSessionLocked
        ) else {
            NSSound.beep()
            return false
        }

        guard sourceProfile.browserProfileID != targetProfileID else {
            return true
        }

        if attentionCoordinator.isAttentionProtected(slotID),
           !confirmBrowserProfileSwitch(
                sourceProfile,
                targetProfile,
                tabStore.defaultBrowserProfilePresentation.name
           ) {
            return false
        }

        guard let currentProfile = tabStore.profiles.first(where: { $0.id == slotID }) else {
            NSSound.beep()
            return false
        }
        let currentTargetProfile = targetProfileID.flatMap { targetID in
            tabStore.browserProfiles.first(where: { $0.id == targetID })
        }
        let currentTargetExists = targetProfileID == nil || currentTargetProfile != nil
        guard Self.canRequestBrowserProfileSwitch(
            currentProfileID: currentProfile.browserProfileID,
            targetProfileID: targetProfileID,
            targetExists: currentTargetExists,
            customProfilesSupported: webViewPool.customBrowserProfilesSupported,
            sessionIsLocked: sourceHostController.isSessionLocked
        ) else {
            NSSound.beep()
            return false
        }
        guard currentProfile.browserProfileID != targetProfileID else {
            return true
        }

        guard tabStore.setBrowserProfile(
            slotID: slotID,
            profileID: targetProfileID,
            notifyOnSuccess: false
        ) else {
            return false
        }

        slotLifecycleCoordinator.remove(slotID: slotID)
        webViewPool.release(slotID: slotID)
        attentionCoordinator.removeSlot(slotID)
        synchronizeSlotState()
        return true
    }

    static func canRequestOpenInNewTabWithBrowserProfile(
        sourceExists: Bool,
        targetProfileID: UUID?,
        targetExists: Bool,
        customProfilesSupported: Bool,
        sessionIsLocked: Bool
    ) -> Bool {
        guard sourceExists,
              targetProfileID == nil || targetExists else {
            return false
        }
        guard !sessionIsLocked else { return false }
        guard targetProfileID == nil || customProfilesSupported else { return false }
        return true
    }

    @discardableResult
    func requestOpenInNewTabWithBrowserProfile(
        sourceSlotID: UUID,
        targetProfileID: UUID?
    ) -> WebAppProfile? {
        let sourceExists = tabStore.profiles.contains(where: { $0.id == sourceSlotID })
        let targetExists = targetProfileID == nil
            || tabStore.browserProfiles.contains(where: { $0.id == targetProfileID })
        guard Self.canRequestOpenInNewTabWithBrowserProfile(
            sourceExists: sourceExists,
            targetProfileID: targetProfileID,
            targetExists: targetExists,
            customProfilesSupported: webViewPool.customBrowserProfilesSupported,
            sessionIsLocked: sourceHostController.isSessionLocked
        ) else {
            NSSound.beep()
            return nil
        }

        return tabStore.duplicateSlot(
            sourceID: sourceSlotID,
            targetBrowserProfileID: targetProfileID
        )
    }

    static func defaultBrowserProfileSwitchConfirmation(
        sourceProfile: WebAppProfile,
        targetProfile: BrowserProfile?,
        defaultProfileName: String
    ) -> Bool {
        let targetName = targetProfile?.name ?? defaultProfileName
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Switch Browser Profile?"
        alert.informativeText = "Switching \(sourceProfile.name) to \(targetName) replaces the current page runtime. Ongoing or unseen ChatGPT work may be discarded. To keep both identities live, use “Open in New Tab with Profile” instead."
        alert.addButton(withTitle: "Switch Profile")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    func createBrowserProfile(name: String) throws -> BrowserProfile {
        guard webViewPool.customBrowserProfilesSupported else {
            throw BrowserProfileManagementError.unsupported
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw BrowserProfileManagementError.invalidName
        }
        let allNames = [tabStore.defaultBrowserProfilePresentation.name]
            + tabStore.browserProfiles.map(\.name)
        guard !allNames.contains(where: { $0.caseInsensitiveCompare(trimmedName) == .orderedSame }) else {
            throw BrowserProfileManagementError.duplicateName
        }

        guard let created = tabStore.createBrowserProfile(name: trimmedName) else {
            throw BrowserProfileManagementError.metadataPersistenceFailed
        }
        return created
    }

    func renameBrowserProfile(id: UUID?, name: String) throws {
        if id == nil {
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty else {
                throw BrowserProfileManagementError.invalidName
            }
            guard !tabStore.browserProfiles.contains(where: {
                $0.name.caseInsensitiveCompare(trimmedName) == .orderedSame
            }) else {
                throw BrowserProfileManagementError.duplicateName
            }
            guard tabStore.renameDefaultBrowserProfile(name: trimmedName) else {
                throw BrowserProfileManagementError.metadataPersistenceFailed
            }
            return
        }

        guard let id else { throw BrowserProfileManagementError.notFound }
        guard tabStore.browserProfiles.contains(where: { $0.id == id }) else {
            throw BrowserProfileManagementError.notFound
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw BrowserProfileManagementError.invalidName
        }
        guard tabStore.defaultBrowserProfilePresentation.name.caseInsensitiveCompare(trimmedName) != .orderedSame,
              !tabStore.browserProfiles.contains(where: {
                  $0.id != id && $0.name.caseInsensitiveCompare(trimmedName) == .orderedSame
              }) else {
            throw BrowserProfileManagementError.duplicateName
        }

        guard tabStore.renameBrowserProfile(id: id, name: trimmedName) else {
            throw BrowserProfileManagementError.metadataPersistenceFailed
        }
    }

    func deleteBrowserProfile(
        id: UUID,
        usageStore: WebsiteCacheUsageStore? = nil
    ) async throws {
        guard tabStore.browserProfiles.contains(where: { $0.id == id }) else {
            throw BrowserProfileManagementError.notFound
        }
        guard !tabStore.profiles.contains(where: { $0.browserProfileID == id }) else {
            throw BrowserProfileManagementError.referenced
        }

        let identity = BrowserProfileIdentity.custom(id)
        let staleSlotIDs = webViewPool.residentSlotIDs(using: identity)
        for slotID in staleSlotIDs {
            slotLifecycleCoordinator.remove(slotID: slotID)
        }
        webViewPool.releaseRuntimes(using: identity)
        guard webViewPool.residentSlotIDs(using: identity).isEmpty else {
            throw BrowserProfileManagementError.runtimeStillResident
        }

        try await webViewPool.removeCustomBrowserProfileDataStore(id: id)
        guard tabStore.deleteBrowserProfileMetadata(id: id) else {
            throw BrowserProfileManagementError.metadataPersistenceFailed
        }
        (usageStore ?? websiteCacheUsageStore)?.removeEntry(for: identity)
    }

    func applyRestoredRailCollapse(_ collapsed: Bool) {
        setTabRailCollapsed(collapsed, animated: false)
    }

    @discardableResult
    func restoreStoredWebAppState(_ state: StoredWebAppState) -> Bool {
        guard !sourceHostController.isSessionLocked else { return false }

        let existingIDs = Set(tabStore.profiles.map(\.id))
        guard tabStore.replaceStoredState(state, notifyOnSuccess: false) else {
            return false
        }

        slotLifecycleCoordinator.reset(slotIDs: existingIDs)
        let unreadBeforeReplacement = unreadResponseCoordinator.unreadSlotIDs
        for slotID in existingIDs {
            webViewPool.release(slotID: slotID)
            attentionCoordinator.removeSlot(slotID)
            unreadResponseCoordinator.removeSlot(slotID: slotID)
            if unreadBeforeReplacement.contains(slotID),
               !unreadResponseCoordinator.unreadSlotIDs.contains(slotID) {
                recordUnreadDiagnostic(event: "unread.removed", fields: [
                    "slot_id": .string(slotID.uuidString),
                    "reason": .string("stored_state_replaced")
                ])
            }
        }
        lastSynchronizedActiveID = nil
        lastSynchronizedActiveProfile = nil
        synchronizeSlotState()
        return true
    }

    static func shouldAutoHide(panelIsVisible: Bool, isPinned: Bool) -> Bool {
        panelIsVisible && !isPinned
    }

    static func shouldPersistManualViewportToActiveTab(
        windowSizeMode: PanelWindowSizeMode
    ) -> Bool {
        windowSizeMode == .perWebApp
    }

    private func togglePinnedState() {
        isPinned.toggle()
        rootView.externalControlZoneView.setPinned(isPinned)
        synchronizePinnedPresentation()
        if isPinned, sourceHostController.sessionState == .fullscreen {
            updateRequestedVisibility(true)
            fullscreenVisibilityIntent.requestPresentation()
            showFullscreenCompanionIfReady()
        }
    }

    private func synchronizePinnedPresentation() {
        panel.setPinnedPresentation(isPinned)
        sourceHostController.setPinnedPresentation(isPinned)
    }

    static func shouldAutoHideForActivatedApplication(
        panelIsVisible: Bool,
        isPinned: Bool,
        activatedProcessIdentifier: pid_t,
        ownProcessIdentifier: pid_t
    ) -> Bool {
        panelIsVisible
            && !isPinned
            && activatedProcessIdentifier != ownProcessIdentifier
    }

    static func shouldAutoHideForExternalMouseDown(
        panelIsVisible: Bool,
        isPinned: Bool
    ) -> Bool {
        shouldAutoHide(panelIsVisible: panelIsVisible, isPinned: isPinned)
    }

    static func externalMouseDownIsInsideVisiblePresentation(
        mouseLocation: NSPoint,
        shellFrame: NSRect,
        shellIsVisible: Bool,
        sourceFrame: NSRect,
        sourceIsVisibleAndIdle: Bool
    ) -> Bool {
        (shellIsVisible && shellFrame.contains(mouseLocation))
            || (sourceIsVisibleAndIdle && sourceFrame.contains(mouseLocation))
    }

    private func handleExternalMouseDown(
        eventTimestamp: TimeInterval,
        mouseLocation: NSPoint
    ) {
        guard requestedVisibility || panel.isVisible else { return }
        let trace = presentationTrace ?? diagnostics.beginTrace(root: "panel.auto-hide")
        let staleEvent = eventTimestamp < lastPresentationUptime
        let insidePresentation = Self.externalMouseDownIsInsideVisiblePresentation(
            mouseLocation: mouseLocation,
            shellFrame: panel.frame,
            shellIsVisible: panel.isVisible,
            sourceFrame: sourceHostController.window.frame,
            sourceIsVisibleAndIdle: sourceHostController.window.isVisible
                && !sourceHostController.isSessionLocked
        )
        let decision = RuntimeDiagnosticAutoHideObservationDecision.globalMouse(
            panelVisible: requestedVisibility,
            pinned: isPinned,
            insidePresentation: insidePresentation,
            staleEvent: staleEvent
        )
        recordAutoHideDecision(
            trigger: .globalMouse,
            trace: trace,
            candidateApplication: nil,
            frontmostApplication: NSWorkspace.shared.frontmostApplication,
            decision: decision,
            suppressionActive: false,
            presentationFocusPending: presentationFocusTask != nil,
            frontmostMatches: nil,
            staleEvent: staleEvent,
            insidePresentation: insidePresentation
        )
        guard !staleEvent else { return }
        if insidePresentation {
            fullscreenExperimentLog(
                "GLOBAL_MOUSE_IGNORED reason=insidePresentation "
                    + "mouse=\(NSStringFromPoint(mouseLocation))"
            )
            return
        }
        guard Self.shouldAutoHideForExternalMouseDown(
                  panelIsVisible: requestedVisibility,
                  isPinned: isPinned
              ) else { return }
        fullscreenExperimentLog(
            "AUTO_HIDE reason=globalMouse event=\(eventTimestamp) "
                + "shown=\(lastPresentationUptime) mouse=\(NSStringFromPoint(mouseLocation))"
        )
        autoHideAfterApplicationDeactivation(
            source: .globalMouse,
            trace: trace,
            reason: "global_mouse"
        )
    }

    private func recordAutoHideDecision(
        trigger: RuntimeDiagnosticDismissSource,
        trace: RuntimeDiagnosticTrace,
        candidateApplication: NSRunningApplication?,
        frontmostApplication: NSRunningApplication?,
        decision: RuntimeDiagnosticAutoHideObservationDecision,
        suppressionActive: Bool,
        presentationFocusPending: Bool,
        frontmostMatches: Bool?,
        staleEvent: Bool = false,
        insidePresentation: Bool = false
    ) {
        if case let .ignore(reason) = decision {
            let signature = [
                trigger.rawValue,
                reason.rawValue,
                requestedVisibility ? "visible" : "hidden",
                isPinned ? "pinned" : "unpinned",
                suppressionActive ? "suppressed" : "unsuppressed",
                presentationFocusPending ? "focus_pending" : "focus_ready",
                staleEvent ? "stale" : "fresh",
                insidePresentation ? "inside" : "outside",
                frontmostMatches.map(String.init) ?? "unknown"
            ].joined(separator: "|")
            let now = ProcessInfo.processInfo.systemUptime
            if let previous = autoHideIgnoreLastRecordedAt[signature], now - previous < 1 {
                return
            }
            autoHideIgnoreLastRecordedAt[signature] = now
            if autoHideIgnoreLastRecordedAt.count > 32 {
                let oldest = autoHideIgnoreLastRecordedAt.min { $0.value < $1.value }?.key
                if let oldest { autoHideIgnoreLastRecordedAt.removeValue(forKey: oldest) }
            }
        }
        var fields: [String: RuntimeDiagnosticValue] = [
            "trigger": .string(trigger.rawValue),
            "decision": .string(decision.result),
            "panel_visible": .bool(requestedVisibility),
            "shell_visible": .bool(panel.isVisible),
            "pinned": .bool(isPinned),
            "suppression_grace_active": .bool(suppressionActive),
            "presentation_focus_pending": .bool(presentationFocusPending),
            "stale_mouse_event": .bool(staleEvent),
            "inside_presentation": .bool(insidePresentation),
            "frontmost_application_match": frontmostMatches.map(RuntimeDiagnosticValue.bool)
                ?? .null,
            "ignore_reason": decision.ignoreReason.map {
                .string($0.rawValue)
            } ?? .null
        ]
        if let candidateApplication {
            fields["candidate_process_identifier"] = .integer(
                Int64(candidateApplication.processIdentifier)
            )
            if let bundleIdentifier = RuntimeDiagnosticPrivacy.safeBundleIdentifier(
                candidateApplication.bundleIdentifier
            ) {
                fields["candidate_application_bundle_id"] = bundleIdentifier
            }
        }
        if let frontmostApplication {
            fields["frontmost_process_identifier"] = .integer(
                Int64(frontmostApplication.processIdentifier)
            )
            if let bundleIdentifier = RuntimeDiagnosticPrivacy.safeBundleIdentifier(
                frontmostApplication.bundleIdentifier
            ) {
                fields["frontmost_application_bundle_id"] = bundleIdentifier
            }
        }

        diagnostics.record(
            event: "panel.auto_hide.decision",
            level: .info,
            subsystem: "panel",
            trace: trace,
            fields: fields
        )
    }

    @objc private func workspaceDidActivateApplication(_ notification: Notification) {
        guard requestedVisibility || panel.isVisible else { return }
        guard let activatedApplication = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication else {
            let trace = presentationTrace ?? diagnostics.beginTrace(root: "panel.auto-hide")
            recordAutoHideDecision(
                trigger: .workspaceActivation,
                trace: trace,
                candidateApplication: nil,
                frontmostApplication: NSWorkspace.shared.frontmostApplication,
                decision: .ignore(reason: .missingApplication),
                suppressionActive: false,
                presentationFocusPending: presentationFocusTask != nil,
                frontmostMatches: false
            )
            return
        }

        if activatedApplication.processIdentifier
            == ProcessInfo.processInfo.processIdentifier {
            let trace = presentationTrace ?? diagnostics.beginTrace(root: "panel.auto-hide")
            recordAutoHideDecision(
                trigger: .workspaceActivation,
                trace: trace,
                candidateApplication: activatedApplication,
                frontmostApplication: NSWorkspace.shared.frontmostApplication,
                decision: .ignore(reason: .ownApplication),
                suppressionActive: false,
                presentationFocusPending: presentationFocusTask != nil,
                frontmostMatches: true
            )
            acknowledgeActiveAttentionIfActuallyPresented()
            return
        }

        let suppressionActive = workspaceAutoHideSuppression.suppressesAutoHide(
            nowUptime: ProcessInfo.processInfo.systemUptime
        )
        let presentationFocusPending = presentationFocusTask != nil
        let frontmostApplication = NSWorkspace.shared.frontmostApplication
        let frontmostMatches = frontmostApplication?.processIdentifier
            == activatedApplication.processIdentifier
        let shouldAutoHide = Self.shouldAutoHideForActivatedApplication(
            panelIsVisible: requestedVisibility,
            isPinned: isPinned,
            activatedProcessIdentifier: activatedApplication.processIdentifier,
            ownProcessIdentifier: ProcessInfo.processInfo.processIdentifier
        )
        let decision = RuntimeDiagnosticAutoHideObservationDecision.workspace(
            panelVisible: requestedVisibility,
            pinned: isPinned,
            suppressionActive: suppressionActive,
            presentationFocusPending: presentationFocusPending,
            frontmostMatches: frontmostMatches
        )
        let trace = presentationTrace ?? diagnostics.beginTrace(root: "panel.auto-hide")
        recordAutoHideDecision(
            trigger: .workspaceActivation,
            trace: trace,
            candidateApplication: activatedApplication,
            frontmostApplication: frontmostApplication,
            decision: decision,
            suppressionActive: suppressionActive,
            presentationFocusPending: presentationFocusPending,
            frontmostMatches: frontmostMatches
        )
        guard !suppressionActive,
              !presentationFocusPending,
              frontmostMatches,
              shouldAutoHide else {
            return
        }
        fullscreenExperimentLog(
            "AUTO_HIDE reason=workspace app=\(activatedApplication.bundleIdentifier ?? "unknown") "
                + "pid=\(activatedApplication.processIdentifier)"
        )
        autoHideAfterApplicationDeactivation(
            source: .workspaceActivation,
            trace: trace
        )
    }

    @objc private func workspaceDidChangeActiveSpace(_ notification: Notification) {
        if let hideObservationTrace {
            hideObservationSpaceChangeCount += 1
            recordHideObservation(
                event: "panel.hide.space_change",
                trace: hideObservationTrace,
                fields: ["active_space_change_notification": .bool(true)]
            )
        }

        guard requestedVisibility,
              !sourceHostController.isSessionLocked else {
            return
        }

        let delays: [TimeInterval] = [0, 0.2]
        for delay in delays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self,
                      self.requestedVisibility,
                      !self.sourceHostController.isSessionLocked else {
                    return
                }
                self.sourceHostController.reconcileVisiblePresentationAfterSpaceChange()
            }
        }
    }

    private func autoHideAfterApplicationDeactivation(
        source: RuntimeDiagnosticDismissSource,
        trace: RuntimeDiagnosticTrace? = nil,
        reason: String = "application_deactivated"
    ) {
        defer { presentationDisplayMovement.reset() }
        let trace = trace ?? presentationTrace ?? diagnostics.beginTrace(root: "panel.dismiss")
        let wasVisible = requestedVisibility
        recordDismissBegin(
            trace: trace,
            source: source,
            wasVisible: wasVisible,
            reason: reason
        )
        if presentationNativeFocusPending || presentationWebFocusPending {
            diagnostics.record(
                event: "presentation_focus.cancelled",
                level: .notice,
                subsystem: "panel",
                trace: trace,
                fields: [
                    "focus_generation": .integer(Int64(presentationFocusGeneration)),
                    "focus_owner": .string(presentationWebFocusOwner.rawValue),
                    "reason": .string("application_deactivated")
                ]
            )
        }
        updateRequestedVisibility(false)
        presentationFocusTask?.cancel()
        presentationFocusTask = nil
        presentationWebFocusTask?.cancel()
        presentationWebFocusTask = nil
        presentationNativeFocusPending = false
        presentationNativeFocusTransferState.reset()
        presentationWebFocusPending = false
        presentationWebFocusOwner = .standardPresentation
        addressOverlayView.dismiss()
        persistPanelFrame()
        panel.orderOut(nil)
        guard !sourceHostController.isSessionLocked else {
            fullscreenVisibilityIntent.dismissPresentation()
            tearDownFullscreenCompanion(
                pauseInactiveMedia: true,
                hidePanel: true
            )
            previousApplicationContext = nil
            self.presentationTrace = nil
            presentationActivationConfirmedGeneration = nil
            recordDismissCompleted(
                trace: trace,
                wasVisible: wasVisible,
                source: source
            )
            return
        }
        sourceHostController.orderOutIfSafe()
        slotLifecycleCoordinator.setPanelVisible(false, activeProfile: tabStore.activeProfile)
        previousApplicationContext = nil
        self.presentationTrace = nil
        presentationActivationConfirmedGeneration = nil
        recordDismissCompleted(
            trace: trace,
            wasVisible: wasVisible,
            source: source
        )
    }

#if DEBUG
    func benchmarkControlSnapshot() -> [String: Any] {
        let profiles: [[String: Any]] = tabStore.orderedProfiles.map { profile in
            [
                "id": profile.id.uuidString,
                "order": profile.order,
                "name": profile.name,
                "runtime_retention": profile.runtimeRetentionPreference.rawValue,
                "residency": profile.residencyPolicy.rawValue,
                "background_media": profile.backgroundMediaPolicy.rawValue,
                "website_mode": profile.renderingProfile.websiteMode.rawValue,
                "viewport_width": Double(profile.renderingProfile.viewportWidth),
                "viewport_height": Double(profile.renderingProfile.viewportHeight),
                "zoom": Double(profile.renderingProfile.zoom),
            ]
        }
        var snapshot: [String: Any] = [
            "visible": isVisible,
            "shell_visible": panel.isVisible,
            "shell_screen": fullscreenExperimentScreenID(panel.screen),
            "source_visible": sourceHostController.window.isVisible,
            "source_screen": fullscreenExperimentScreenID(sourceHostController.window.screen),
            "source_parented_to_shell": sourceHostController.window.parent === panel,
            "source_key": sourceHostController.window.isKeyWindow,
            "pinned": isPinned,
            "profiles": profiles,
            "resident_slot_count": webViewPool.count,
            "resident_slot_ids": webViewPool.residentSlotIDs.map(\.uuidString).sorted(),
            "pending_cold_release_count": slotLifecycleCoordinator.pendingColdReleaseCount,
            "pending_warm_release_count": slotLifecycleCoordinator.pendingWarmReleaseCount,
            "media_protected_slot_ids": slotLifecycleCoordinator.mediaProtectedIDs.map(\.uuidString).sorted(),
            "hidden_active_grace_pending": slotLifecycleCoordinator.isHiddenActiveGracePending,
            "fullscreen_source_state": sourceHostController.sessionState.rawValue,
        ]
        snapshot["active_slot_id"] = tabStore.activeTabID?.uuidString ?? NSNull()

        return snapshot
    }

    func debugIsProjectingUnreadResponse(slotID: UUID) -> Bool {
        rootView.externalControlZoneView
            .tabView(for: slotID)?.isShowingUnreadResponse ?? false
    }

    func debugSetPresentationFactOverride(
        slotID: UUID,
        presentationFact: Bool
    ) {
        debugPresentationFactOverrides[slotID] = presentationFact
    }

    func debugClearPresentationFactOverride(slotID: UUID) {
        debugPresentationFactOverrides.removeValue(forKey: slotID)
    }

    @discardableResult
    func debugRemoveConfirmedSlot(slotID: UUID) -> Bool {
        removeConfirmedSlot(slotID: slotID)
    }

    @discardableResult
    func debugWithPresentationFact<Result>(
        slotID: UUID,
        presentationFact: Bool,
        operation: () -> Result
    ) -> Result {
        debugPresentationFactOverrides[slotID] = presentationFact
        defer { debugPresentationFactOverrides.removeValue(forKey: slotID) }
        return operation()
    }

    @discardableResult
    func debugWithPresentationFacts<Result>(
        slotID: UUID,
        presentationFact: Bool,
        interactionSurfacePresented: Bool,
        operation: () -> Result
    ) -> Result {
        debugPresentationFactOverrides[slotID] = presentationFact
        debugInteractionSurfaceFactOverrides[slotID] = interactionSurfacePresented
        defer {
            debugPresentationFactOverrides.removeValue(forKey: slotID)
            debugInteractionSurfaceFactOverrides.removeValue(forKey: slotID)
        }
        return operation()
    }

    @discardableResult
    func debugInvokeRailSelection(slotID: UUID) -> Bool {
        rootView.externalControlZoneView.onSelect?(slotID)
        return tabStore.activeTabID == slotID
    }

    @discardableResult
    func debugInvokeRailSelection(
        slotID: UUID,
        presentationFact: Bool
    ) -> Bool {
        debugPresentationFactOverrides[slotID] = presentationFact
        defer { debugPresentationFactOverrides.removeValue(forKey: slotID) }
        return debugInvokeRailSelection(slotID: slotID)
    }

    @discardableResult
    func debugInvokeOverflowSelection(slotID: UUID) -> Bool {
        guard rootView.externalControlZoneView
            .debugInvokeOverflowSelection(slotID: slotID) else {
            return false
        }
        return tabStore.activeTabID == slotID
    }

    @discardableResult
    func debugInvokeOverflowSelection(
        slotID: UUID,
        presentationFact: Bool
    ) -> Bool {
        debugPresentationFactOverrides[slotID] = presentationFact
        defer { debugPresentationFactOverrides.removeValue(forKey: slotID) }
        return debugInvokeOverflowSelection(slotID: slotID)
    }

    @discardableResult
    func debugSetCurrentPageAsHome() -> Bool {
        setCurrentPageAsHome()
    }

    var debugOverflowSlotIDs: [UUID] {
        rootView.externalControlZoneView.layoutSubtreeIfNeeded()
        return rootView.externalControlZoneView.overflowTabIDs
    }

    var debugPendingColdReleaseCount: Int {
        slotLifecycleCoordinator.pendingColdReleaseCount
    }

    var debugIsShowingRestoringState: Bool {
        rootView.webPanelContainerView.isShowingRestoringState
    }

    var debugIsFullscreenCompanionShowingRestoringState: Bool {
        sourceHostController.companionContainer.isShowingRestoringState
    }

    func debugSynchronizeFullscreenCompanionSlotState() {
        synchronizeFullscreenCompanionSlotState()
    }

#if DEBUG
    /// Test seam for driving the observed source Runtime through the same
    /// fullscreen lock/state callbacks used by its public KVO observer.
    @discardableResult
    func debugTransitionFullscreenSession(
        to webKitState: WKWebView.FullscreenState
    ) -> Bool {
        guard let webView = sourceHostController.diagnosticObservedWebView else {
            return false
        }
        sourceHostController.debugTransitionFullscreenState(
            of: webView,
            to: webKitState
        )
        return sourceHostController.isSessionLocked
    }
#endif

    var debugFullscreenCompanionWebView: WKWebView? {
        sourceHostController.companionContainer.currentWebView
    }

    var debugIsShowingLoadFailure: Bool {
        rootView.webPanelContainerView.isShowingLoadFailure
    }

    func debugTriggerLoadFailureRetry() {
        rootView.webPanelContainerView.debugTriggerLoadFailureRetry()
    }

    var debugPanelFrame: NSRect {
        panel.frame
    }

    var debugPresentedWebView: WKWebView? {
        rootView.webPanelContainerView.currentWebView
    }

    var debugCurrentWebFocusWebView: WKWebView? {
        webFocusRouter.currentWebView
    }

    var debugRuntimeReadiness: String? {
        guard let activeSlotID = tabStore.activeTabID else { return nil }
        return runtimeReadinessState(for: activeSlotID)?.rawValue ?? "unknown"
    }

    func debugRuntimeReadiness(for slotID: UUID) -> String {
        runtimeReadinessState(for: slotID)?.rawValue ?? "unknown"
    }

    var debugPendingWarmReleaseCount: Int {
        slotLifecycleCoordinator.pendingWarmReleaseCount
    }

    var debugIsHiddenActiveGracePending: Bool {
        slotLifecycleCoordinator.isHiddenActiveGracePending
    }

    func debugInactivePlanToken(slotID: UUID) -> UUID? {
        slotLifecycleCoordinator.debugInactivePlanToken(slotID: slotID)
    }

    func benchmarkSetResourcePolicy(
        slotIDStrings: [String],
        residencyRawValue: String?,
        backgroundMediaRawValue: String?
    ) -> Bool {
        let ids = slotIDStrings.compactMap(UUID.init(uuidString:))
        guard ids.count == slotIDStrings.count, !ids.isEmpty else { return false }
        let validIDs = Set(tabStore.profiles.map(\.id))
        guard ids.allSatisfy(validIDs.contains) else { return false }

        let residency = residencyRawValue.flatMap(SlotResidencyPolicy.init(rawValue:))
        let media = backgroundMediaRawValue.flatMap(BackgroundMediaPolicy.init(rawValue:))
        if residencyRawValue != nil, residency == nil { return false }
        if backgroundMediaRawValue != nil, media == nil { return false }
        guard residency != nil || media != nil else { return false }

        for id in ids {
            guard tabStore.updateResourcePolicy(
                id: id,
                residencyPolicy: residency,
                backgroundMediaPolicy: media
            ) else {
                return false
            }
        }
        return true
    }

    func benchmarkSelect(slotIDString: String) -> Bool {
        guard let id = UUID(uuidString: slotIDString) else { return false }
        return tabStore.select(id: id)
    }

    func benchmarkConfigureChatGPTMeasurement(
        slotIDString: String,
        enabled: Bool?,
        reset: Bool
    ) async -> [String: Any] {
        guard let slotID = UUID(uuidString: slotIDString) else {
            return ["status": "unavailable", "reason": "invalid_slot_id"]
        }
        return await webViewPool.configureChatGPTBenchmarkMeasurement(
            slotID: slotID,
            enabled: enabled,
            reset: reset
        )
    }

    func benchmarkCaptureChatGPTSnapshot(slotIDString: String) async -> [String: Any] {
        guard let slotID = UUID(uuidString: slotIDString) else {
            return ["status": "unavailable", "reason": "invalid_slot_id"]
        }
        return await webViewPool.captureChatGPTBenchmarkSnapshot(slotID: slotID)
    }
#endif

    @discardableResult
    func selectSlot(
        relativeOffset: Int,
        trace: RuntimeDiagnosticTrace? = nil
    ) -> Bool {
        let trace = trace ?? diagnostics.beginTrace(root: "tab.selection")
        guard let selected = tabStore.selectRelative(by: relativeOffset, trace: trace) else {
            return false
        }
        acknowledgeUnreadAfterExplicitSelection(slotID: selected.id, trace: trace)
        return true
    }

    func handle(_ command: AppCommand, trace: RuntimeDiagnosticTrace? = nil) {
        if let trace, command == .togglePrimaryFocus {
            diagnostics.record(
                event: "web_focus.toggle.requested",
                level: .info,
                subsystem: "focus",
                trace: trace
            )
        }
        switch command {
        case let .selectSlot(index):
            guard let slot = tabStore.slotByKeyboardIndex(index) else { return }
            _ = selectSlotFromExplicitUserAction(slot.id, trace: trace)

        case .nextSlot:
            _ = selectSlot(relativeOffset: 1, trace: trace)

        case .previousSlot:
            _ = selectSlot(relativeOffset: -1, trace: trace)

        case .addWebApp:
            presentAddWebAppEditor()

        case .zoomIn:
            changeActiveZoom(larger: true)

        case .zoomOut:
            changeActiveZoom(larger: false)

        case .resetZoom:
            setActiveZoom(1.0)

        case .addressBar:
            presentAddressBar()

        case .returnHome:
            returnActiveSlotHome()

        case .reload:
            reloadActiveSlot()

        case .togglePrimaryFocus:
            togglePrimaryWebFocus(trace: trace)

        case .settings:
            onOpenGlobalSettings?()

        case .togglePin:
            togglePinnedState()

        case let .setResidency(policy):
            _ = setActiveResidency(policy)
        }
    }

    private func configureTransientUI() {
        addressOverlayView.translatesAutoresizingMaskIntoConstraints = false
        statusHUDView.translatesAutoresizingMaskIntoConstraints = false
        installTransientUI(
            in: sourceHostController.transientUIContainerView,
            viewport: sourceHostController.transientUIContainerView
        )

        addressOverlayView.onCommit = { [weak self] rawValue in
            self?.commitAddress(rawValue) ?? false
        }
        addressOverlayView.onCopy = { [weak self] rawValue in
            self?.copyAddressToPasteboard(rawValue) ?? false
        }
        addressOverlayView.onSetHome = { [weak self] in
            self?.setCurrentPageAsHome() ?? false
        }
        addressOverlayView.onCreateWebApp = { [weak self] in
            self?.presentDerivedWebAppFromCurrentPage()
        }
        addressOverlayView.onDismiss = { [weak self] in
            self?.focusActiveWebViewIfAvailable()
        }
    }

    private func installTransientUI(in host: NSView, viewport: NSView) {
        guard addressOverlayView.superview !== host || statusHUDView.superview !== host else {
            return
        }

        NSLayoutConstraint.deactivate(transientUIConstraints)
        transientUIConstraints.removeAll()
        addressOverlayView.removeFromSuperview()
        statusHUDView.removeFromSuperview()
        host.addSubview(addressOverlayView)
        host.addSubview(statusHUDView)

        transientUIConstraints = [
            addressOverlayView.leadingAnchor.constraint(
                equalTo: viewport.leadingAnchor,
                constant: 22
            ),
            addressOverlayView.trailingAnchor.constraint(
                equalTo: viewport.trailingAnchor,
                constant: -22
            ),
            addressOverlayView.topAnchor.constraint(
                equalTo: viewport.topAnchor,
                constant: 22
            ),
            addressOverlayView.heightAnchor.constraint(equalToConstant: 52),

            statusHUDView.centerXAnchor.constraint(
                equalTo: viewport.centerXAnchor
            ),
            statusHUDView.bottomAnchor.constraint(
                equalTo: viewport.bottomAnchor,
                constant: -28
            ),
            statusHUDView.widthAnchor.constraint(greaterThanOrEqualToConstant: 140),
            statusHUDView.heightAnchor.constraint(equalToConstant: 34),
        ]
        NSLayoutConstraint.activate(transientUIConstraints)
    }

    private func synchronizeTransientUIHost() {
        if sourceHostController.isSessionLocked {
            installTransientUI(
                in: rootView,
                viewport: rootView.webViewportLayoutView
            )
        } else {
            installTransientUI(
                in: sourceHostController.transientUIContainerView,
                viewport: sourceHostController.transientUIContainerView
            )
        }
    }

    private func configurePreferenceObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appearancePreferenceDidChange(_:)),
            name: .floatTabsAppearanceDidChange,
            object: preferencesStore
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(borderPreferenceDidChange(_:)),
            name: .floatTabsBorderPreferenceDidChange,
            object: preferencesStore
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowSizeModeDidChange(_:)),
            name: .floatTabsWindowSizeModeDidChange,
            object: preferencesStore
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(fixedWindowSizeDidChange(_:)),
            name: .floatTabsFixedWindowSizeDidChange,
            object: preferencesStore
        )
    }

    @objc private func appearancePreferenceDidChange(_ notification: Notification) {
        synchronizeAppearance()
    }

    private func synchronizeAppearance() {
        let appearance = preferencesStore.appearanceMode.appKitAppearance
        panel.appearance = appearance
        sourceHostController.window.appearance = appearance
        rootView.externalControlZoneView.refreshAppearance()
        synchronizeBorderTheme()
        rootView.needsDisplay = true
    }

    @objc private func borderPreferenceDidChange(_ notification: Notification) {
        synchronizeBorderTheme()
    }

    @objc private func windowSizeModeDidChange(_ notification: Notification) {
        synchronizeWindowSizeMode()
        switch preferencesStore.windowSizeMode {
        case .perWebApp:
            if let active = tabStore.activeProfile {
                applyPreferredViewport(active.renderingProfile.viewportSize)
            }
        case .fixed:
            guard hasPositionedPanel else { return }
            if preferencesStore.hasStoredFixedViewportSize {
                applySharedFixedViewport(preferencesStore.fixedViewportSize, animated: panel.isVisible)
            } else {
                let viewport = PanelMetrics.viewportSize(forPanelSize: panel.frame.size)
                preferencesStore.fixedViewportSize = viewport
            }
        }
    }

    @objc private func fixedWindowSizeDidChange(_ notification: Notification) {
        guard preferencesStore.windowSizeMode == .fixed else { return }
        applySharedFixedViewport(preferencesStore.fixedViewportSize, animated: panel.isVisible)
    }


    private func synchronizePreferencePresentation() {
        synchronizeAppearance()
        synchronizeBorderTheme()
        synchronizeWindowSizeMode()
    }

    private func synchronizeBorderTheme() {
        rootView.interactionBorderView.apply(
            theme: preferencesStore.borderTheme,
            customColor: preferencesStore.customBorderColor
        )
        sourceHostController.railFoldControl.apply(
            theme: preferencesStore.borderTheme,
            customColor: preferencesStore.customBorderColor
        )
        rootView.companionRailFoldControlView.apply(
            theme: preferencesStore.borderTheme,
            customColor: preferencesStore.customBorderColor
        )
    }

    private func synchronizeWindowSizeMode() {
        rootView.externalControlZoneView.setWindowSizeEditingEnabled(
            preferencesStore.windowSizeMode == .perWebApp
        )
    }

    private func configureSlotInteractions() {
        let rail = rootView.externalControlZoneView

        rail.onSelect = { [weak self] id in
            _ = self?.selectSlotFromExplicitUserAction(id)
        }
        rail.onReturnHome = { [weak self] id in
            self?.returnSlotHome(id: id)
        }
        rail.onReload = { [weak self] id in
            self?.reloadSlot(id: id)
        }
        rail.onAdd = { [weak self] in
            self?.presentAddWebAppEditor()
        }
        rail.onEdit = { [weak self] id in
            self?.presentEditWebAppEditor(id: id)
        }
        rail.onRemove = { [weak self] id in
            self?.presentRemoveConfirmation(id: id)
        }
        rail.onSetWebsiteMode = { [weak self] id, mode in
            guard let self,
                  let profile = self.tabStore.profiles.first(where: { $0.id == id }) else { return }
            _ = self.tabStore.updateRenderingProfile(
                id: id,
                renderingProfile: profile.renderingProfile.settingWebsiteMode(mode)
            )
        }
        rail.onSetWindowSize = { [weak self] id, preset in
            guard let self,
                  self.preferencesStore.windowSizeMode == .perWebApp,
                  let profile = self.tabStore.profiles.first(where: { $0.id == id }),
                  let size = preset.size,
                  self.tabStore.updateRenderingProfile(
                    id: id,
                    renderingProfile: profile.renderingProfile.settingSimplePreset(preset)
                  ) else { return }
            if self.tabStore.activeTabID == id {
                self.applyPreferredViewport(size)
            }
        }
        rail.onSetZoom = { [weak self] id, zoom in
            _ = self?.tabStore.updateZoom(id: id, zoom: zoom)
        }
        rail.onSetRuntimeRetention = { [weak self] id, preference in
            _ = self?.tabStore.updateRuntimeRetentionPreference(
                id: id,
                preference: preference
            )
        }
        rail.onSetBackgroundMedia = { [weak self] id, policy in
            _ = self?.tabStore.updateResourcePolicy(id: id, backgroundMediaPolicy: policy)
        }
        rail.onSetBrowserProfile = { [weak self] id, profileID in
            _ = self?.requestBrowserProfileSwitch(
                slotID: id,
                targetProfileID: profileID
            )
        }
        rail.onOpenInNewTabWithBrowserProfile = { [weak self] id, profileID in
            _ = self?.requestOpenInNewTabWithBrowserProfile(
                sourceSlotID: id,
                targetProfileID: profileID
            )
        }
        rail.onManageBrowserProfiles = { [weak self] in
            self?.onOpenGlobalSettings?()
        }
        rail.onReorder = { [weak self] id, destination in
            _ = self?.tabStore.move(id: id, toIndex: destination)
        }
        rail.onSettings = { [weak self] in
            self?.onOpenGlobalSettings?()
        }
        rail.onTogglePin = { [weak self] in
            self?.togglePinnedState()
        }
        let toggleRail: () -> Void = { [weak self] in
            guard let self else { return }
            guard !self.sourceHostController.isSessionLocked else {
                NSSound.beep()
                return
            }
            self.setTabRailCollapsed(
                !self.rootView.externalControlZoneView.isRailCollapsed,
                animated: true
            )
        }
        sourceHostController.railFoldControl.onActivate = toggleRail
        rootView.companionRailFoldControlView.onActivate = toggleRail
        setTabRailCollapsed(preferencesStore.isTabRailCollapsed, animated: false)
    }

    private func setTabRailCollapsed(_ collapsed: Bool, animated: Bool) {
        guard !sourceHostController.isSessionLocked else { return }
        preferencesStore.isTabRailCollapsed = collapsed
        sourceHostController.railLeadingInset = collapsed
            ? PanelMetrics.collapsedRailLeadingInset
            : PanelMetrics.externalControlZoneWidth
        rootView.setTabRailCollapsed(collapsed, animated: animated)
        sourceHostController.railFoldControl.setExpanded(!collapsed, animated: animated)
        rootView.companionRailFoldControlView.setExpanded(
            !collapsed,
            animated: animated
        )
        synchronizeSourceHostFrame(display: true, animated: animated)
    }

    private func synchronizeSlotState() {
        let selectedSlotID = tabStore.activeTabID
        for slotID in Array(manualFaviconReloadIntentsBySlot.keys)
            where slotID != selectedSlotID {
            manualFaviconReloadIntentsBySlot.removeValue(forKey: slotID)
        }
        for slotID in Array(faviconDOMReadBySlot.keys)
            where slotID != selectedSlotID
                && faviconDOMReadBySlot[slotID]?.isManualReloadRefresh == true {
            faviconDOMReadBySlot.removeValue(forKey: slotID)
        }
        if let pending = pendingRuntimeMaterialization,
           pending.slotID != tabStore.activeTabID {
            cancelPendingRuntimeMaterialization(reason: "active_slot_changed")
        }
        synchronizeBrowserProfileMenuPresentation()
        let orderedProfiles = tabStore.orderedProfiles
        let validSlotIDs = Set(orderedProfiles.map(\.id))
        pruneRuntimeReadiness(validSlotIDs: validSlotIDs)
        let unreadBeforePrune = unreadResponseCoordinator.unreadSlotIDs
        unreadResponseCoordinator.prune(
            validSlotIDs: validSlotIDs
        )
        let suppressedIDs = unreadPruneDiagnosticSuppressionIDs
        for slotID in unreadBeforePrune.subtracting(
            unreadResponseCoordinator.unreadSlotIDs
        ).subtracting(suppressedIDs) {
            recordUnreadDiagnostic(event: "unread.pruned", fields: [
                "slot_id": .string(slotID.uuidString),
                "reason": .string("invalid_slot_identity")
            ])
        }
        synchronizeDurableUnreadPresentation()
        guard !sourceHostController.isSessionLocked else {
            pendingSlotSynchronization = true
            synchronizeFullscreenCompanionSlotState()
            return
        }
        pendingSlotSynchronization = false

        rootView.externalControlZoneView.apply(
            profiles: orderedProfiles,
            activeTabID: tabStore.activeTabID
        )
        synchronizeDurableUnreadPresentation()
        synchronizeResidentIndicators()
        slotLifecycleCoordinator.reconcile(profiles: orderedProfiles)
        pruneRuntimeReadiness(validSlotIDs: validSlotIDs)

        guard let activeProfile = tabStore.activeProfile else {
            pendingColdUnreadAcknowledgement = nil
            if let previous = lastSynchronizedActiveProfile {
                slotLifecycleCoordinator.deactivate(profile: previous)
            }
            lastSynchronizedActiveID = nil
            lastSynchronizedActiveProfile = nil
            webFocusRouter.setCurrentWebView(nil)
            rootView.webPanelContainerView.showEmptyState()
            synchronizeResidentIndicators()
            onSelectedSlotPresentationChange?(nil, nil)
            return
        }

        let activeChanged = lastSynchronizedActiveID != activeProfile.id
        if activeChanged,
           let previous = lastSynchronizedActiveProfile,
           previous.id != activeProfile.id {
            slotLifecycleCoordinator.deactivate(profile: previous)
        }

        if activeChanged, hasPositionedPanel, preferencesStore.followPreferredSize {
            applyPreferredViewport(activeProfile.renderingProfile.viewportSize)
        }

        if let pending = pendingRuntimeMaterialization,
           pending.slotID == activeProfile.id {
            synchronizePendingRuntimeMaterialization(
                for: activeProfile,
                request: pending
            )
            return
        }

        if runtimeReadinessState(for: activeProfile.id) == .failed {
            slotLifecycleCoordinator.activate(profile: activeProfile)
            webFocusRouter.setCurrentWebView(nil)
            rootView.webPanelContainerView.showLoadFailure(
                retryEnabled: canRetrySelectedSlot(activeProfile)
            )
            lastSynchronizedActiveID = activeProfile.id
            lastSynchronizedActiveProfile = activeProfile
            onSelectedSlotPresentationChange?(
                activeProfile.name,
                faviconURL(for: activeProfile)
            )
            synchronizeResidentIndicators()
            return
        }

        if webViewPool.existingWebView(for: activeProfile.id) == nil,
           requestedVisibility || panel.isVisible {
            beginDeferredRuntimeMaterialization(for: activeProfile)
            return
        }

        if webViewPool.existingWebView(for: activeProfile.id) != nil,
           runtimeReadinessState(for: activeProfile.id) != .ready {
            if requestedVisibility || panel.isVisible {
                beginDeferredRuntimeMaterialization(for: activeProfile)
            } else {
                rootView.webPanelContainerView.showRestoringState()
                webFocusRouter.setCurrentWebView(nil)
                slotLifecycleCoordinator.activate(profile: activeProfile)
                lastSynchronizedActiveID = activeProfile.id
                lastSynchronizedActiveProfile = activeProfile
                onSelectedSlotPresentationChange?(
                    activeProfile.name,
                    faviconURL(for: activeProfile)
                )
            }
            return
        }

        if (requestedVisibility || panel.isVisible),
           webViewPool.requiresWebViewRebuild(for: activeProfile) {
            // Website Mode / Browser Profile replacement is synchronous inside
            // WebViewPool. Establish the selected Slot's native restore owner
            // and revoke old Web focus before allowing that replacement.
            beginDeferredRuntimeMaterialization(for: activeProfile)
            return
        }

        let webView: WKWebView
        do {
            webView = try webViewForPanelController(activeProfile)
        } catch {
            webFocusRouter.setCurrentWebView(nil)
            if let profileName = Self.unsupportedBrowserProfileName(
                for: activeProfile,
                error: error,
                browserProfiles: tabStore.browserProfiles
            ) {
                rootView.webPanelContainerView.showUnsupportedBrowserProfile(
                    profileName: profileName,
                    defaultProfileName: tabStore.defaultBrowserProfilePresentation.name
                )
            } else {
                rootView.webPanelContainerView.showLoadFailure(
                    retryEnabled: canRetrySelectedSlot(activeProfile)
                )
            }
            synchronizeResidentIndicators()
            return
        }
        guard runtimeReadinessState(for: activeProfile.id) == .ready else {
            if requestedVisibility || panel.isVisible {
                beginDeferredRuntimeMaterialization(for: activeProfile)
            } else {
                rootView.webPanelContainerView.showRestoringState()
                webFocusRouter.setCurrentWebView(nil)
                slotLifecycleCoordinator.activate(profile: activeProfile)
                lastSynchronizedActiveID = activeProfile.id
                lastSynchronizedActiveProfile = activeProfile
                onSelectedSlotPresentationChange?(
                    activeProfile.name,
                    faviconURL(for: activeProfile)
                )
                synchronizeResidentIndicators()
            }
            return
        }
        if let identity = webViewPool.runtimeDiagnosticIdentity(for: activeProfile.id),
           let generation = runtimeReadinessBySlot[activeProfile.id]?.navigationGeneration {
            readFaviconDOMCandidatesIfCurrent(
                slotID: activeProfile.id,
                runtimeIdentity: identity,
                navigationGeneration: generation
            )
        }
        if pendingRuntimeMaterialization?.slotID == activeProfile.id {
            cancelPendingRuntimeMaterialization(reason: "resident_presentation")
        }
        rootView.webPanelContainerView.show(
            webView: webView,
            slotID: activeProfile.id,
            residencyPolicy: activeProfile.residencyPolicy
        )
        rootView.webPanelContainerView.hideRestoringState()
        webFocusRouter.setCurrentWebView(webView)
        slotLifecycleCoordinator.activate(profile: activeProfile)
        WebViewFactory.configureHiddenScrollers(in: webView)
        sourceHostController.observeFullscreenState(of: webView)
        lastSynchronizedActiveID = activeProfile.id
        lastSynchronizedActiveProfile = activeProfile
        synchronizeResidentIndicators()
        onSelectedSlotPresentationChange?(
            activeProfile.name,
            faviconURL(for: activeProfile)
        )

        acknowledgeAttentionIfActuallyVisible(slotID: activeProfile.id)

        if panel.isVisible,
           panel.isKeyWindow || sourceHostController.window.isKeyWindow {
            sourceHostController.orderFrontAndFocus(webView)
        }
    }

    private func faviconURL(for profile: WebAppProfile) -> URL? {
        webViewPool.committedURL(for: profile.id) ?? profile.homeURL
    }

    static func runtimeMaterializationRequestIsValid(
        requestGenerationMatches: Bool,
        requestSlotID: UUID?,
        activeSlotID: UUID?,
        presentationRequested: Bool,
        sessionLocked: Bool
    ) -> Bool {
        guard requestGenerationMatches,
              let requestSlotID,
              requestSlotID == activeSlotID,
              presentationRequested,
              !sessionLocked else {
            return false
        }
        return true
    }

    private func container(for surface: RuntimePresentationSurface) -> WebPanelContainerView {
        switch surface {
        case .standard:
            return rootView.webPanelContainerView
        case .fullscreenCompanion:
            return sourceHostController.companionContainer
        }
    }

    private func runtimeReadinessState(for slotID: UUID) -> RuntimeReadinessState? {
        guard let currentIdentity = webViewPool.runtimeDiagnosticIdentity(for: slotID) else {
            runtimeReadinessBySlot.removeValue(forKey: slotID)
            return nil
        }
        guard let record = runtimeReadinessBySlot[slotID],
              record.identity == currentIdentity else {
            runtimeReadinessBySlot.removeValue(forKey: slotID)
            return nil
        }
        return record.state
    }

    private func pruneRuntimeReadiness(validSlotIDs: Set<UUID>) {
        for slotID in Array(runtimeReadinessBySlot.keys) {
            guard let record = runtimeReadinessBySlot[slotID],
                  validSlotIDs.contains(slotID),
                  webViewPool.runtimeDiagnosticIdentity(for: slotID) == record.identity else {
                runtimeReadinessBySlot.removeValue(forKey: slotID)
                continue
            }
        }
        for slotID in Array(faviconDOMReadBySlot.keys) {
            guard validSlotIDs.contains(slotID),
                  let read = faviconDOMReadBySlot[slotID],
                  webViewPool.runtimeDiagnosticIdentity(for: slotID) == read.identity else {
                faviconDOMReadBySlot.removeValue(forKey: slotID)
                continue
            }
        }
        for slotID in Array(manualFaviconReloadIntentsBySlot.keys) {
            guard validSlotIDs.contains(slotID),
                  let intent = manualFaviconReloadIntentsBySlot[slotID],
                  webViewPool.runtimeDiagnosticIdentity(for: slotID) == intent.runtimeIdentity else {
                manualFaviconReloadIntentsBySlot.removeValue(forKey: slotID)
                continue
            }
        }
    }

    private func webViewForPanelController(_ profile: WebAppProfile) throws -> WKWebView {
        let previousIdentity = webViewPool.runtimeDiagnosticIdentity(for: profile.id)
        let webView = try webViewPool.webView(for: profile)
        guard let currentIdentity = webViewPool.runtimeDiagnosticIdentity(for: profile.id),
              webViewPool.existingWebView(for: profile.id) === webView else {
            runtimeReadinessBySlot.removeValue(forKey: profile.id)
            return webView
        }

        if previousIdentity != currentIdentity {
            runtimeReadinessBySlot[profile.id] = RuntimeReadinessRecord(
                identity: currentIdentity,
                state: .loading,
                navigationGeneration: nil
            )
        } else if runtimeReadinessBySlot[profile.id]?.identity != currentIdentity {
            // An already resident Runtime without controller-owned provenance
            // remains unknown until its exact navigation callback arrives.
            runtimeReadinessBySlot.removeValue(forKey: profile.id)
        }
        return webView
    }

    private func exactReadyWebView(for slotID: UUID) -> WKWebView? {
        guard runtimeReadinessState(for: slotID) == .ready,
              let webView = webViewPool.existingWebView(for: slotID),
              webViewPool.runtimeDiagnosticIdentity(for: slotID)
                == runtimeReadinessBySlot[slotID]?.identity else {
            return nil
        }
        return webView
    }

    private func isPendingRuntimeMaterializationCurrent(
        _ request: PendingRuntimeMaterialization
    ) -> Bool {
        guard pendingRuntimeMaterialization?.generation == request.generation,
              request.slotID == tabStore.activeTabID,
              requestedVisibility || panel.isVisible else {
            return false
        }
        switch request.surface {
        case .standard:
            return !sourceHostController.isSessionLocked
        case .fullscreenCompanion:
            return sourceHostController.isSessionLocked
                && sourceHostController.sessionState == .fullscreen
        }
    }

    private func beginDeferredRuntimeMaterialization(
        for profile: WebAppProfile,
        surface: RuntimePresentationSurface = .standard
    ) {
        if let pending = pendingRuntimeMaterialization,
           pending.slotID == profile.id,
           pending.surface == surface {
            synchronizePendingRuntimeMaterialization(
                for: profile,
                request: pending
            )
            return
        }
        if pendingRuntimeMaterialization != nil {
            cancelPendingRuntimeMaterialization(reason: "presentation_surface_replaced")
        }

        runtimeMaterializationGeneration += 1
        let request = PendingRuntimeMaterialization(
            generation: runtimeMaterializationGeneration,
            slotID: profile.id,
            surface: surface
        )
        pendingRuntimeMaterialization = request
        pendingRuntimeMaterializationIdentity = nil
        onSelectedSlotPresentationChange?(
            profile.name,
            faviconURL(for: profile)
        )
        if surface == .fullscreenCompanion {
            rootView.installFullscreenCompanionContainer(
                sourceHostController.companionContainer
            )
            companionActiveProfile = profile
            slotLifecycleCoordinator.beginSupplementalVisibility(profile: profile)
        } else {
            // The selected Runtime becomes active when this presentation
            // generation is established, before deferred WebKit work. This
            // cancels only its existing inactive plan; it does not reclaim or
            // recreate a resident Runtime.
            slotLifecycleCoordinator.activate(profile: profile)
        }
        container(for: surface).showRestoringState()
        // Restoring is a native-only interaction boundary. The previous Slot
        // must not remain the canonical focus target while a reclaimed Runtime
        // is being materialized under the overlay.
        webFocusRouter.setCurrentWebView(nil)
        lastSynchronizedActiveID = profile.id
        lastSynchronizedActiveProfile = profile
        diagnostics.record(
            event: "panel.materialization.deferred",
            level: .notice,
            subsystem: "panel",
            fields: [
                "slot_id": .string(profile.id.uuidString),
                "materialization_generation": .integer(Int64(request.generation))
            ]
        )
        recordRestoringSurfaceWindowVisibilityIfNeeded()
        DispatchQueue.main.async { [weak self] in
            self?.performDeferredRuntimeMaterialization(request)
        }
    }

    private func synchronizePendingRuntimeMaterialization(
        for profile: WebAppProfile,
        request: PendingRuntimeMaterialization
    ) {
        guard pendingRuntimeMaterialization?.generation == request.generation,
              request.slotID == profile.id else {
            return
        }

        container(for: request.surface).showRestoringState()
        webFocusRouter.setCurrentWebView(nil)
        recordRestoringSurfaceWindowVisibilityIfNeeded()
        let selectedViewportPanelSize = PanelMetrics.clampedPanelSize(
            PanelMetrics.panelSize(
                forViewport: NSSize(
                    width: profile.renderingProfile.viewportSize.width,
                    height: profile.renderingProfile.viewportSize.height
                )
            )
        )
        if request.surface == .standard,
           preferencesStore.windowSizeMode == .perWebApp,
           preferredPanelSize != selectedViewportPanelSize {
            applyPreferredViewport(profile.renderingProfile.viewportSize)
        }

        guard isPendingRuntimeMaterializationCurrent(request),
              webViewPool.existingWebView(for: profile.id) != nil else {
            return
        }

        let requiresRebuild = webViewPool.requiresWebViewRebuild(for: profile)
        if requiresRebuild,
           !makeRestoringSurfaceActuallyVisible(for: request) {
            return
        }

        do {
            // Going through the Pool also applies compatible rendering changes
            // to an existing Runtime; the read-only check above keeps an
            // incompatible synchronous replacement behind visible Restoring.
            let webView = try webViewForPanelController(profile)
            guard isPendingRuntimeMaterializationCurrent(request),
                  pendingRuntimeMaterialization?.generation == request.generation,
                  webViewPool.existingWebView(for: profile.id) === webView,
                  let identity = webViewPool.runtimeDiagnosticIdentity(for: profile.id) else {
                return
            }

            if container(for: request.surface).currentWebView === webView,
               runtimeReadinessState(for: profile.id) == .ready {
                // A same-turn rendering change can return to the exact ready
                // Runtime that was visible before this deferred transaction.
                // Keep Restoring/focus protection through the current model
                // notification; the already-queued transaction will converge
                // and complete presentation on the next main-queue turn.
                pendingRuntimeMaterializationIdentity = identity
                return
            }

            if pendingRuntimeMaterializationIdentity != identity
                || container(for: request.surface).currentWebView !== webView {
                attachDeferredRuntime(
                    webView: webView,
                    profile: profile,
                    request: request
                )
            }
        } catch {
            finishPendingRuntimeMaterializationAsFailed(
                profile: profile,
                error: error
            )
        }
    }

    /// Records when the restoring surface is attached to the currently visible
    /// window that owns its container. This is a presentation boundary, not
    /// proof that pixels have reached the display compositor.
    private func recordRestoringSurfaceWindowVisibilityIfNeeded() {
        guard let currentRequest = pendingRuntimeMaterialization else { return }
        let surface = container(for: currentRequest.surface)
        let surfaceWindow = surface.window
        guard var request = pendingRuntimeMaterialization,
              !request.didRecordRestoringSurfaceWindowVisibility,
              surface.isShowingRestoringState,
              let surfaceWindow,
              surfaceWindow.isVisible,
              !surfaceWindow.isMiniaturized else {
            return
        }

        request.didRecordRestoringSurfaceWindowVisibility = true
        pendingRuntimeMaterialization = request
        let surfaceWindowRole = surfaceWindow === panel
            ? "panel"
            : surfaceWindow === sourceHostController.window ? "source" : "other"
        diagnostics.record(
            event: "panel.restoring_surface.window_visible",
            level: .notice,
            subsystem: "panel",
            fields: [
                "slot_id": .string(request.slotID.uuidString),
                "materialization_generation": .integer(Int64(request.generation)),
                "panel_window_visible": .bool(panel.isVisible),
                "panel_window_key": .bool(panel.isKeyWindow),
                "surface_window_role": .string(surfaceWindowRole),
                "surface_window_visible": .bool(surfaceWindow.isVisible),
                "surface_window_key": .bool(surfaceWindow.isKeyWindow)
            ]
        )
    }

    private func performDeferredRuntimeMaterialization(
        _ request: PendingRuntimeMaterialization
    ) {
        guard isPendingRuntimeMaterializationCurrent(request),
              let profile = tabStore.profiles.first(where: { $0.id == request.slotID }) else {
            cancelStaleRuntimeMaterialization(request, reason: "stale_before_materialization")
            return
        }

        guard makeRestoringSurfaceActuallyVisible(for: request) else {
            cancelStaleRuntimeMaterialization(
                request,
                reason: "restoring_surface_not_visible"
            )
            return
        }

        let webView: WKWebView
        do {
            webView = try webViewForPanelController(profile)
        } catch {
            finishPendingRuntimeMaterializationAsFailed(
                profile: profile,
                error: error
            )
            return
        }

        guard isPendingRuntimeMaterializationCurrent(request),
              webViewPool.existingWebView(for: request.slotID) === webView else {
            cancelStaleRuntimeMaterialization(request, reason: "stale_before_attach")
            return
        }

        attachDeferredRuntime(webView: webView, profile: profile, request: request)
    }

    /// The cold presentation transaction must own a visible native restoring
    /// surface before WebKit creates or restores the target Runtime. The
    /// source window's Web container is the existing presentation surface;
    /// ordering it without a WebView does not transfer focus or expose a
    /// not-yet-ready page.
    private func makeRestoringSurfaceActuallyVisible(
        for request: PendingRuntimeMaterialization
    ) -> Bool {
        guard isPendingRuntimeMaterializationCurrent(request),
              pendingRuntimeMaterialization?.generation == request.generation,
              container(for: request.surface).isShowingRestoringState else {
            return false
        }

        switch request.surface {
        case .standard:
            sourceHostController.orderFrontAndFocus(nil)
        case .fullscreenCompanion:
            panel.orderFrontRegardless()
        }
        recordRestoringSurfaceWindowVisibilityIfNeeded()

        let surface = container(for: request.surface)
        guard let surfaceWindow = surface.window else {
            return false
        }
        return surface.isShowingRestoringState
            && surfaceWindow.isVisible
            && !surfaceWindow.isMiniaturized
    }

    private func attachDeferredRuntime(
        webView: WKWebView,
        profile: WebAppProfile,
        request: PendingRuntimeMaterialization
    ) {
        container(for: request.surface).show(
            webView: webView,
            slotID: profile.id,
            residencyPolicy: profile.residencyPolicy
        )
        pendingRuntimeMaterializationIdentity = webViewPool.runtimeDiagnosticIdentity(
            for: profile.id
        )
        // Attachment is not readiness. Keep focus/input and Attention closed
        // until the exact current Runtime emits the accepted Outcome-A finish.
        WebViewFactory.configureHiddenScrollers(in: webView)
        sourceHostController.observeFullscreenState(of: webView)

        var fields: [String: RuntimeDiagnosticValue] = [
            "slot_id": .string(profile.id.uuidString),
            "materialization_generation": .integer(Int64(request.generation))
        ]
        fields.merge(
            pendingRuntimeMaterializationIdentity?.fields ?? [:]
        ) { _, new in new }
        diagnostics.record(
            event: "panel.materialization.attached",
            level: .notice,
            subsystem: "panel",
            fields: fields
        )
        if runtimeReadinessState(for: profile.id) == .ready,
           let runtimeIdentity = pendingRuntimeMaterializationIdentity
                ?? webViewPool.runtimeDiagnosticIdentity(for: profile.id) {
            completePendingRuntimeMaterialization(
                request,
                runtimeIdentity: runtimeIdentity
            )
        }
    }

    private func cancelPendingRuntimeMaterialization(reason: String) {
        guard let pending = pendingRuntimeMaterialization else { return }
        clearPendingColdUnreadAcknowledgement(for: pending)
        pendingRuntimeMaterialization = nil
        pendingRuntimeMaterializationIdentity = nil
        container(for: pending.surface).hideRestoringState()
        diagnostics.record(
            event: "panel.materialization.cancelled",
            level: .notice,
            subsystem: "panel",
            fields: [
                "slot_id": .string(pending.slotID.uuidString),
                "materialization_generation": .integer(Int64(pending.generation)),
                "reason": .string(reason)
            ]
        )
    }

    private func cancelStaleRuntimeMaterialization(
        _ request: PendingRuntimeMaterialization,
        reason: String
    ) {
        let currentGeneration = pendingRuntimeMaterialization?.generation
        if currentGeneration == request.generation {
            clearPendingColdUnreadAcknowledgement(for: request)
            pendingRuntimeMaterialization = nil
            pendingRuntimeMaterializationIdentity = nil
            container(for: request.surface).hideRestoringState()
        }
        diagnostics.record(
            event: "panel.materialization.cancelled",
            level: .notice,
            subsystem: "panel",
            fields: [
                "slot_id": .string(request.slotID.uuidString),
                "materialization_generation": .integer(Int64(request.generation)),
                "reason": .string(reason),
                "replaced_by_newer_request": .bool(
                    currentGeneration != nil && currentGeneration != request.generation
                )
            ]
        )
    }

    private func clearPendingColdUnreadAcknowledgement(
        for materialization: PendingRuntimeMaterialization
    ) {
        guard let intent = pendingColdUnreadAcknowledgement,
              intent.slotID == materialization.slotID,
              intent.materializationGeneration == materialization.generation else {
            return
        }
        pendingColdUnreadAcknowledgement = nil
    }

    private func finishPendingRuntimeMaterializationAsFailed(
        profile: WebAppProfile,
        error: Error
    ) {
        let pending = pendingRuntimeMaterialization.flatMap {
            $0.slotID == profile.id ? $0 : nil
        }
        if let pending {
            clearPendingColdUnreadAcknowledgement(for: pending)
        }
        pendingRuntimeMaterialization = nil
        pendingRuntimeMaterializationIdentity = nil
        webFocusRouter.setCurrentWebView(nil)
        let presentationContainer = pending.map { container(for: $0.surface) }
            ?? rootView.webPanelContainerView
        if let profileName = Self.unsupportedBrowserProfileName(
            for: profile,
            error: error,
            browserProfiles: tabStore.browserProfiles
        ) {
            presentationContainer.showUnsupportedBrowserProfile(
                profileName: profileName,
                defaultProfileName: tabStore.defaultBrowserProfilePresentation.name
            )
        } else {
            presentationContainer.showLoadFailure(
                retryEnabled: canRetrySelectedSlot(profile)
            )
        }
        diagnostics.record(
            event: "panel.materialization.failed",
            level: .warning,
            subsystem: "panel",
            fields: [
                "slot_id": .string(profile.id.uuidString),
                "materialization_generation": .integer(
                    Int64(runtimeMaterializationGeneration)
                )
            ].merging(RuntimeDiagnosticPrivacy.sanitizedErrorCategory(error)) {
                current, _ in current
            }
        )
    }

    func handleSlotNavigationStart(
        slotID: UUID,
        runtimeIdentity: WebRuntimeDiagnosticIdentity,
        navigationGeneration: UInt64
    ) {
        guard navigationGeneration > 0,
              webViewPool.runtimeDiagnosticIdentity(for: slotID) == runtimeIdentity,
              webViewPool.existingWebView(for: slotID) != nil else {
            return
        }
        if let existing = runtimeReadinessBySlot[slotID],
           existing.identity == runtimeIdentity,
           let currentGeneration = existing.navigationGeneration,
           navigationGeneration <= currentGeneration {
            return
        }
        runtimeReadinessBySlot[slotID] = RuntimeReadinessRecord(
            identity: runtimeIdentity,
            state: .loading,
            navigationGeneration: navigationGeneration
        )
        if var intent = manualFaviconReloadIntentsBySlot[slotID] {
            switch intent.recordNavigationStart(
                runtimeIdentity: runtimeIdentity,
                navigationGeneration: navigationGeneration
            ) {
            case .captured, .ignored:
                manualFaviconReloadIntentsBySlot[slotID] = intent
            case .invalidated:
                manualFaviconReloadIntentsBySlot.removeValue(forKey: slotID)
            }
        }
        guard tabStore.activeTabID == slotID,
              requestedVisibility || panel.isVisible,
              let profile = tabStore.profiles.first(where: { $0.id == slotID }) else {
            return
        }
        let surface: RuntimePresentationSurface?
        if sourceHostController.isSessionLocked,
           sourceHostController.companionContainer.isShowingLoadFailure {
            surface = .fullscreenCompanion
        } else if !sourceHostController.isSessionLocked,
                  rootView.webPanelContainerView.isShowingLoadFailure {
            surface = .standard
        } else {
            surface = nil
        }
        if let surface {
            beginDeferredRuntimeMaterialization(for: profile, surface: surface)
        }
    }

    private func handleRuntimeRecoveryStart(
        slotID: UUID,
        runtimeIdentity: WebRuntimeDiagnosticIdentity
    ) {
        guard webViewPool.runtimeDiagnosticIdentity(for: slotID) == runtimeIdentity,
              let webView = webViewPool.existingWebView(for: slotID) else {
            return
        }
        let currentRecord = runtimeReadinessBySlot[slotID].flatMap {
            $0.identity == runtimeIdentity ? $0 : nil
        }
        runtimeReadinessBySlot[slotID] = RuntimeReadinessRecord(
            identity: runtimeIdentity,
            state: .loading,
            navigationGeneration: currentRecord?.navigationGeneration
        )

        guard tabStore.activeTabID == slotID else { return }
        if webFocusRouter.currentWebView === webView {
            webFocusRouter.setCurrentWebView(nil)
        }
        guard requestedVisibility || panel.isVisible else { return }

        let surface: RuntimePresentationSurface = sourceHostController.isSessionLocked
            ? .fullscreenCompanion
            : .standard
        if let pending = pendingRuntimeMaterialization,
           pending.slotID == slotID,
           pending.surface == surface {
            container(for: surface).showRestoringState()
            return
        }
        guard let profile = tabStore.profiles.first(where: { $0.id == slotID }) else {
            return
        }
        beginDeferredRuntimeMaterialization(for: profile, surface: surface)
    }

    private func handleRuntimeRecoveryUnavailable(
        slotID: UUID,
        runtimeIdentity: WebRuntimeDiagnosticIdentity
    ) {
        guard webViewPool.runtimeDiagnosticIdentity(for: slotID) == runtimeIdentity,
              webViewPool.existingWebView(for: slotID) != nil else {
            return
        }
        let currentRecord = runtimeReadinessBySlot[slotID].flatMap {
            $0.identity == runtimeIdentity ? $0 : nil
        }
        runtimeReadinessBySlot[slotID] = RuntimeReadinessRecord(
            identity: runtimeIdentity,
            state: .failed,
            navigationGeneration: currentRecord?.navigationGeneration
        )
        guard tabStore.activeTabID == slotID,
              let profile = tabStore.profiles.first(where: { $0.id == slotID }) else {
            return
        }

        webFocusRouter.setCurrentWebView(nil)
        if pendingRuntimeMaterialization?.slotID == slotID {
            cancelPendingRuntimeMaterialization(reason: "recovery_url_unavailable")
        }
        let surface: RuntimePresentationSurface = sourceHostController.isSessionLocked
            ? .fullscreenCompanion
            : .standard
        if surface == .fullscreenCompanion {
            rootView.installFullscreenCompanionContainer(
                sourceHostController.companionContainer
            )
        }
        container(for: surface).showLoadFailure(
            retryEnabled: canRetrySelectedSlot(profile)
        )
        var fields: [String: RuntimeDiagnosticValue] = [
            "slot_id": .string(slotID.uuidString),
            "presentation_state": .string("failed"),
            "failure_reason": .string("recovery_url_unavailable")
        ]
        fields.merge(runtimeIdentity.fields) { current, _ in current }
        diagnostics.record(
            event: "panel.materialization.recovery_unavailable",
            level: .warning,
            subsystem: "panel",
            fields: fields
        )
    }

    func handleSlotNavigationFinish(
        slotID: UUID,
        runtimeIdentity: WebRuntimeDiagnosticIdentity,
        navigationGeneration: UInt64? = nil
    ) {
        guard webViewPool.runtimeDiagnosticIdentity(for: slotID) == runtimeIdentity,
              webViewPool.existingWebView(for: slotID) != nil else {
            return
        }
        let currentRecord = runtimeReadinessBySlot[slotID].flatMap {
            $0.identity == runtimeIdentity ? $0 : nil
        }
        if let currentGeneration = currentRecord?.navigationGeneration,
           navigationGeneration != currentGeneration {
            return
        }
        if let navigationGeneration, navigationGeneration == 0 { return }
        runtimeReadinessBySlot[slotID] = RuntimeReadinessRecord(
            identity: runtimeIdentity,
            state: .ready,
            navigationGeneration: navigationGeneration ?? currentRecord?.navigationGeneration
        )

        let isManualReloadRefresh: Bool
        if let navigationGeneration,
           var intent = manualFaviconReloadIntentsBySlot[slotID],
           intent.consumeNavigationFinish(
               runtimeIdentity: runtimeIdentity,
               navigationGeneration: navigationGeneration
           ) {
            manualFaviconReloadIntentsBySlot.removeValue(forKey: slotID)
            isManualReloadRefresh = true
        } else {
            isManualReloadRefresh = false
            if manualFaviconReloadIntentsBySlot[slotID]?.runtimeIdentity != runtimeIdentity {
                manualFaviconReloadIntentsBySlot.removeValue(forKey: slotID)
            }
        }

        if let navigationGeneration {
            readFaviconDOMCandidatesIfCurrent(
                slotID: slotID,
                runtimeIdentity: runtimeIdentity,
                navigationGeneration: navigationGeneration,
                isManualReloadRefresh: isManualReloadRefresh
            )
        }

        guard let pending = pendingRuntimeMaterialization,
              pending.slotID == slotID,
              isPendingRuntimeMaterializationCurrent(pending) else {
            return
        }
        if pendingRuntimeMaterializationIdentity == nil {
            pendingRuntimeMaterializationIdentity = runtimeIdentity
            return
        }
        guard pendingRuntimeMaterializationIdentity == runtimeIdentity else { return }
        completePendingRuntimeMaterialization(pending, runtimeIdentity: runtimeIdentity)
    }

    private func readFaviconDOMCandidatesIfCurrent(
        slotID: UUID,
        runtimeIdentity: WebRuntimeDiagnosticIdentity,
        navigationGeneration: UInt64,
        isManualReloadRefresh: Bool = false
    ) {
        guard navigationGeneration > 0,
              tabStore.activeTabID == slotID,
              runtimeReadinessBySlot[slotID]?.identity == runtimeIdentity,
              runtimeReadinessBySlot[slotID]?.navigationGeneration == navigationGeneration,
              webViewPool.runtimeDiagnosticIdentity(for: slotID) == runtimeIdentity,
              let webView = webViewPool.existingWebView(for: slotID),
              let committedURL = webViewPool.committedURL(for: slotID) else {
            return
        }
        if let existing = faviconDOMReadBySlot[slotID],
           existing.identity == runtimeIdentity,
           existing.navigationGeneration == navigationGeneration,
           existing.committedURL == committedURL {
            if existing.isManualReloadRefresh || !isManualReloadRefresh { return }
        }
        let read = FaviconDOMReadRecord(
            identity: runtimeIdentity,
            navigationGeneration: navigationGeneration,
            committedURL: committedURL,
            isManualReloadRefresh: isManualReloadRefresh
        )
        faviconDOMReadBySlot[slotID] = read

        WebsiteFaviconProvider.readDOMFaviconCandidates(from: webView) { [weak self, weak webView] result in
            guard let self,
                  let webView,
                  self.tabStore.activeTabID == slotID,
                  self.webViewPool.existingWebView(for: slotID) === webView,
                  self.webViewPool.runtimeDiagnosticIdentity(for: slotID) == runtimeIdentity,
                  self.webViewPool.committedURL(for: slotID) == committedURL,
                  self.runtimeReadinessBySlot[slotID]?.identity == runtimeIdentity,
                  self.runtimeReadinessBySlot[slotID]?.navigationGeneration == navigationGeneration,
                  self.faviconDOMReadBySlot[slotID] == read,
                  let activeProfile = self.tabStore.profiles.first(where: { $0.id == slotID }) else {
                if let current = self?.faviconDOMReadBySlot[slotID],
                   current == read {
                    self?.faviconDOMReadBySlot.removeValue(forKey: slotID)
                }
                return
            }
            var fields = runtimeIdentity.fields
            fields["slot_id"] = .string(slotID.uuidString)
            fields["navigation_generation"] = .integer(Int64(navigationGeneration))
            switch result {
            case let .candidates(candidates):
                fields["result"] = .string("candidates_found")
                fields["candidate_count"] = .integer(Int64(candidates.count))
                self.diagnostics.record(
                    event: "favicon.dom_candidates",
                    level: .info,
                    subsystem: "favicon",
                    fields: fields
                )
                if read.isManualReloadRefresh {
                    WebsiteFaviconProvider.shared.refreshAfterManualReload(
                        candidateReadResult: .candidates(candidates),
                        committedURL: committedURL,
                        for: [committedURL, activeProfile.homeURL]
                    )
                } else {
                    WebsiteFaviconProvider.shared.setDOMCandidates(candidates, for: committedURL)
                }
            case .noCandidates:
                fields["result"] = .string("no_candidates")
                fields["candidate_count"] = .integer(0)
                self.diagnostics.record(
                    event: "favicon.dom_candidates",
                    level: .notice,
                    subsystem: "favicon",
                    fields: fields
                )
                let provider = WebsiteFaviconProvider.shared
                if read.isManualReloadRefresh {
                    provider.refreshAfterManualReload(
                        candidateReadResult: .noCandidates,
                        committedURL: committedURL,
                        for: [committedURL, activeProfile.homeURL]
                    )
                } else {
                    provider.setDOMCandidates(
                        [WebsiteFaviconProvider.Candidate](),
                        for: committedURL
                    )
                }
            case .readFailed:
                fields["result"] = .string("read_failed")
                self.diagnostics.record(
                    event: "favicon.dom_candidates",
                    level: .warning,
                    subsystem: "favicon",
                    fields: fields
                )
                if read.isManualReloadRefresh {
                    WebsiteFaviconProvider.shared.refreshAfterManualReload(
                        candidateReadResult: .readFailed,
                        committedURL: committedURL,
                        for: [committedURL, activeProfile.homeURL]
                    )
                }
            }
        }
    }

    private func completePendingRuntimeMaterialization(
        _ pending: PendingRuntimeMaterialization,
        runtimeIdentity: WebRuntimeDiagnosticIdentity
    ) {
        guard isPendingRuntimeMaterializationCurrent(pending),
              pendingRuntimeMaterialization?.generation == pending.generation,
              pendingRuntimeMaterializationIdentity == runtimeIdentity,
              webViewPool.runtimeDiagnosticIdentity(for: pending.slotID) == runtimeIdentity,
              runtimeReadinessState(for: pending.slotID) == .ready,
              let readyWebView = webViewPool.existingWebView(for: pending.slotID),
              container(for: pending.surface).currentWebView === readyWebView else {
            return
        }
        let coldUnreadIntent = pendingColdUnreadAcknowledgement.flatMap { intent in
            intent.slotID == pending.slotID
                && intent.materializationGeneration == pending.generation
                ? intent
                : nil
        }
        pendingColdUnreadAcknowledgement = nil

        let focusTrace = presentationTrace
        let focusOwner = presentationWebFocusOwner
        pendingRuntimeMaterialization = nil
        pendingRuntimeMaterializationIdentity = nil
        container(for: pending.surface).hideRestoringState()
        var revealFields: [String: RuntimeDiagnosticValue] = [
            "slot_id": .string(pending.slotID.uuidString),
            "materialization_generation": .integer(Int64(pending.generation)),
            "readiness_source": .string("navigation_finished"),
            "panel_window_visible": .bool(panel.isVisible),
            "panel_window_key": .bool(panel.isKeyWindow)
        ]
        revealFields.merge(runtimeIdentity.fields) { _, new in new }
        diagnostics.record(
            event: "panel.materialization.web_content_reveal_requested",
            level: .notice,
            subsystem: "panel",
            fields: revealFields
        )
        webFocusRouter.setCurrentWebView(readyWebView)
        acknowledgeAttentionIfActuallyVisible(slotID: pending.slotID)
        beginPresentationFocusHandshake(
            trace: focusTrace,
            webFocusOwner: focusOwner
        )
        if let coldUnreadIntent {
            acknowledgePresentedSelectionIfNeeded(
                slotID: pending.slotID,
                source: .explicitSelectionDeferred,
                trace: coldUnreadIntent.trace
            )
        }
        var fields: [String: RuntimeDiagnosticValue] = [
            "slot_id": .string(pending.slotID.uuidString),
            "materialization_generation": .integer(Int64(pending.generation)),
            "readiness_source": .string("navigation_finished")
        ]
        fields.merge(runtimeIdentity.fields) { _, new in new }
        diagnostics.record(
            event: "panel.materialization.readiness_completed",
            level: .notice,
            subsystem: "panel",
            fields: fields
        )
    }

    func handleSlotNavigationFailure(
        slotID: UUID,
        runtimeIdentity: WebRuntimeDiagnosticIdentity,
        navigationGeneration: UInt64? = nil
    ) {
        guard webViewPool.runtimeDiagnosticIdentity(for: slotID) == runtimeIdentity,
              webViewPool.existingWebView(for: slotID) != nil else {
            return
        }
        let currentRecord = runtimeReadinessBySlot[slotID].flatMap {
            $0.identity == runtimeIdentity ? $0 : nil
        }
        if let currentGeneration = currentRecord?.navigationGeneration,
           navigationGeneration != currentGeneration {
            return
        }
        if let navigationGeneration, navigationGeneration == 0 { return }
        runtimeReadinessBySlot[slotID] = RuntimeReadinessRecord(
            identity: runtimeIdentity,
            state: .failed,
            navigationGeneration: navigationGeneration ?? currentRecord?.navigationGeneration
        )
        if let intent = manualFaviconReloadIntentsBySlot[slotID],
           intent.matchesNavigationFailure(
               runtimeIdentity: runtimeIdentity,
               navigationGeneration: navigationGeneration
           ) {
            manualFaviconReloadIntentsBySlot.removeValue(forKey: slotID)
        }
        if let read = faviconDOMReadBySlot[slotID],
           read.isManualReloadRefresh,
           read.identity == runtimeIdentity,
           read.navigationGeneration == navigationGeneration {
            faviconDOMReadBySlot.removeValue(forKey: slotID)
        }

        let pending = pendingRuntimeMaterialization.flatMap { request in
            request.slotID == slotID
                && isPendingRuntimeMaterializationCurrent(request)
                && (pendingRuntimeMaterializationIdentity == nil
                    || pendingRuntimeMaterializationIdentity == runtimeIdentity)
                ? request
                : nil
        }
        let standardOwnsRuntime = pending == nil
            && pendingRuntimeMaterialization == nil
            && tabStore.activeTabID == slotID
            && rootView.webPanelContainerView.currentWebView
                === webViewPool.existingWebView(for: slotID)
        let companionOwnsRuntime = pending == nil
            && pendingRuntimeMaterialization == nil
            && tabStore.activeTabID == slotID
            && sourceHostController.companionContainer.currentWebView
                === webViewPool.existingWebView(for: slotID)
        guard pending != nil || standardOwnsRuntime || companionOwnsRuntime else { return }

        if let pending {
            clearPendingColdUnreadAcknowledgement(for: pending)
            pendingRuntimeMaterialization = nil
            pendingRuntimeMaterializationIdentity = nil
            container(for: pending.surface).showLoadFailure(
                retryEnabled: canRetrySelectedSlot(
                    tabStore.profiles.first(where: { $0.id == slotID })
                        ?? tabStore.activeProfile
                )
            )
        } else if standardOwnsRuntime {
            if let profile = tabStore.profiles.first(where: { $0.id == slotID }) {
                rootView.webPanelContainerView.showLoadFailure(
                    retryEnabled: canRetrySelectedSlot(profile)
                )
            }
        } else {
            if let profile = tabStore.profiles.first(where: { $0.id == slotID }) {
                sourceHostController.companionContainer.showLoadFailure(
                    retryEnabled: canRetrySelectedSlot(profile)
                )
            }
            companionActiveProfile = nil
        }
        webFocusRouter.setCurrentWebView(nil)
        var fields: [String: RuntimeDiagnosticValue] = [
            "slot_id": .string(slotID.uuidString),
            "readiness_source": .string("navigation_failed"),
            "failure_presentation": .string("native_retry_state")
        ]
        if let pending {
            fields["materialization_generation"] = .integer(Int64(pending.generation))
        }
        fields.merge(runtimeIdentity.fields) { _, new in new }
        diagnostics.record(
            event: "panel.materialization.readiness_failed",
            level: .warning,
            subsystem: "panel",
            fields: fields
        )
    }

    private func canRetrySelectedSlot(_ profile: WebAppProfile?) -> Bool {
        guard let profile else { return false }
        if webViewPool.existingWebView(for: profile.id) != nil {
            return webViewPool.canRetryNavigation(slotID: profile.id)
        }
        return [profile.currentURL, profile.homeURL].contains { candidate in
            guard let candidate else { return false }
            return WebAppURL.isSafe(candidate)
        }
    }

    private func retryFailedSelectedSlot(in surface: RuntimePresentationSurface) {
        let presentationContainer = container(for: surface)
        guard presentationContainer.isShowingLoadFailure,
              let profile = tabStore.activeProfile,
              canRetrySelectedSlot(profile) else {
            return
        }
        switch surface {
        case .standard where sourceHostController.isSessionLocked:
            return
        case .fullscreenCompanion where !sourceHostController.isSessionLocked:
            return
        default:
            break
        }

        if webViewPool.existingWebView(for: profile.id) != nil {
            guard let identity = webViewPool.runtimeDiagnosticIdentity(for: profile.id),
                  runtimeReadinessBySlot[profile.id]?.identity == identity,
                  runtimeReadinessBySlot[profile.id]?.state == .failed,
                  webViewPool.canRetryNavigation(slotID: profile.id) else {
                return
            }
        }

        let needsCompatibleRuntimeReplacement =
            webViewPool.existingWebView(for: profile.id) != nil
                && webViewPool.requiresWebViewRebuild(for: profile)
        beginDeferredRuntimeMaterialization(for: profile, surface: surface)
        if needsCompatibleRuntimeReplacement {
            // The explicit action owns this replacement. Let deferred
            // materialization create one Runtime from the latest Slot config;
            // do not first navigate the failed, incompatible WebView.
            webFocusRouter.setCurrentWebView(nil)
            return
        }
        if webViewPool.existingWebView(for: profile.id) != nil,
           !webViewPool.retryNavigation(slotID: profile.id) {
            cancelPendingRuntimeMaterialization(reason: "explicit_retry_unavailable")
            presentationContainer.showLoadFailure(
                retryEnabled: canRetrySelectedSlot(profile)
            )
        }
        webFocusRouter.setCurrentWebView(nil)
    }

    private func handleCommittedURLChange(slotID: UUID, url: URL) {
        guard tabStore.activeTabID == slotID,
              let activeProfile = tabStore.activeProfile,
              activeProfile.id == slotID else {
            return
        }
        onSelectedSlotPresentationChange?(activeProfile.name, url)
        if let webView = selectedPresentationWebView() {
            Task { @MainActor [weak self, weak webView] in
                guard let self, let webView else { return }
                await self.webFocusRouter.refreshRecognition(for: webView)
            }
            if requestedVisibility,
               presentationWebFocusPending,
               presentationWebFocusOwner == .standardPresentation {
                schedulePresentationWebInputFocus(afterNanoseconds: 200_000_000)
            }
        }
    }

    private func synchronizeResidentIndicators() {
        rootView.externalControlZoneView.setResidentSlotIDs(webViewPool.residentSlotIDs)
    }

    private func synchronizeBrowserProfileMenuPresentation() {
        let options = [BrowserProfileMenuOption.defaultProfile(
            name: tabStore.defaultBrowserProfilePresentation.name,
            color: tabStore.defaultBrowserProfilePresentation.color
        )]
            + tabStore.browserProfiles.map {
                BrowserProfileMenuOption(
                    id: $0.id,
                    name: $0.name,
                    color: $0.color,
                    isEnabled: webViewPool.customBrowserProfilesSupported
                )
            }
        rootView.externalControlZoneView.setBrowserProfileMenuSnapshot(
            options: options,
            assignmentEnabled: !sourceHostController.isSessionLocked,
            duplicationEnabled: !sourceHostController.isSessionLocked
        )
    }

    private func synchronizeAttentionPresentation() {
        onAttentionPresentationChange?(
            unreadResponseCoordinator.unreadSlotIDs.count,
            requestedVisibility
        )
    }

    private func synchronizeUnreadIndicators() {
        rootView.externalControlZoneView.setUnreadSlotIDs(
            unreadResponseCoordinator.unreadSlotIDs
        )
    }

    private func synchronizeDurableUnreadPresentation() {
        synchronizeAttentionPresentation()
        synchronizeUnreadIndicators()
    }

    private func updateRequestedVisibility(_ visible: Bool) {
        requestedVisibility = visible
        onAttentionPresentationChange?(
            unreadResponseCoordinator.unreadSlotIDs.count,
            requestedVisibility
        )
    }

    private func handleAttentionEvent(
        slotID: UUID,
        event: ChatGPTAttentionEvent
    ) {
        let observation = event.observation
        let attentionStateBefore = attentionCoordinator.state(for: slotID)
        let isValidGenerationCompletion = observation == .generationFinished
            && attentionStateBefore == .generating
        let userVisibleAtCompletion = isValidGenerationCompletion
            ? isAttentionUserVisible(slotID: slotID)
            : false
        let completionTrace = observation == .generationFinished
            ? diagnostics.beginTrace(root: "unread.completion")
            : nil
        let completionFacts = unreadPresentationFacts(slotID: slotID)
        let unreadBefore = unreadResponseCoordinator.unreadSlotIDs.contains(slotID)
        if observation == .generationFinished {
            recordUnreadDiagnostic(
                event: "unread.completion_observed",
                trace: completionTrace,
                fields: [
                    "slot_id": .string(slotID.uuidString),
                    "completion_valid": .bool(isValidGenerationCompletion),
                    "presentation_visible": .bool(completionFacts.presentationVisible),
                    "web_window_key": .bool(completionFacts.webWindowKey),
                    "unread_before": .bool(unreadBefore),
                    "attention_state_before": .string(attentionStateBefore.diagnosticName),
                    "session_locked": .bool(completionFacts.sessionLocked),
                    "panel_visible": .bool(completionFacts.panelVisible)
                ]
            )
        }
        let wasProtected = attentionCoordinator.isAttentionProtected(slotID)

        attentionRouter.handle(observation, for: slotID)
        let completionResult = unreadResponseCoordinator.handle(
            event,
            for: slotID,
            isValidGenerationCompletion: isValidGenerationCompletion,
            userVisible: userVisibleAtCompletion
        )
        synchronizeDurableUnreadPresentation()

        if observation == .generationFinished {
            let unreadAfter = unreadResponseCoordinator.unreadSlotIDs.contains(slotID)
            let reason: UnreadDiagnosticSkipReason?
            if !isValidGenerationCompletion {
                reason = .invalidCompletion
            } else if userVisibleAtCompletion {
                reason = .visibleCompletion
            } else {
                switch completionResult {
                case .alreadyHandled:
                    reason = .alreadyHandledResponse
                case .marked, .visibleHandled:
                    reason = userVisibleAtCompletion ? .visibleCompletion : (unreadBefore ? .alreadyUnread : nil)
                case .ignored:
                    reason = nil
                }
            }
            if let reason {
                recordUnreadDiagnostic(
                    event: "unread.mark_skipped",
                    trace: completionTrace,
                    fields: [
                        "slot_id": .string(slotID.uuidString),
                        "reason": .string(reason.rawValue),
                        "presentation_visible": .bool(completionFacts.presentationVisible),
                        "web_window_key": .bool(completionFacts.webWindowKey)
                    ]
                )
            } else if !unreadBefore && unreadAfter {
                recordUnreadDiagnostic(
                    event: "unread.marked",
                    trace: completionTrace,
                    fields: [
                        "slot_id": .string(slotID.uuidString),
                        "reason": .string("completion_unseen"),
                        "presentation_visible": .bool(completionFacts.presentationVisible),
                        "web_window_key": .bool(completionFacts.webWindowKey)
                    ]
                )
            }
        }

        if observation == .generationStarted {
            acknowledgeUnreadAfterTrustedPageInteraction(
                slotID: slotID,
                source: .generationStarted
            )
        }
        if case .marked = completionResult {
            projectCompletionNotification(slotID: slotID)
        }
        if isValidGenerationCompletion {
            onChatGPTGenerationCompleted?(slotID)
        }

        let isProtected = attentionCoordinator.isAttentionProtected(slotID)
        guard wasProtected,
              !isProtected,
              let profile = tabStore.profiles.first(where: { $0.id == slotID }) else {
            return
        }

        slotLifecycleCoordinator.restartAfterAttentionProtectionEnded(
            profile: profile
        )
    }

    func isAttentionUserVisible(slotID: UUID) -> Bool {
        isSlotActuallyPresented(slotID: slotID)
    }

    private func attentionPresentationFacts(slotID: UUID) -> AttentionPresentation.Facts {
        let pooledWebView = webViewPool.existingWebView(for: slotID)
        let runtimeIsReady = runtimeReadinessState(for: slotID) == .ready
        let normalRestoreBlocked = rootView.webPanelContainerView.isShowingRestoringState
            && tabStore.activeTabID == slotID
        let companionRestoreBlocked = sourceHostController.companionContainer.isShowingRestoringState
            && tabStore.activeTabID == slotID
        return AttentionPresentation.Facts(
            slotID: slotID,
            sessionIsLocked: sourceHostController.isSessionLocked,
            pooledWebViewExists: pooledWebView != nil,
            normalCurrentWebViewIsSlotWebView: runtimeIsReady && !normalRestoreBlocked && (pooledWebView.map { webView in
                rootView.webPanelContainerView.currentWebView === webView
            } ?? false),
            sourceWindowIsVisible: sourceHostController.window.isVisible,
            webPresentationOwnsActiveInteraction: runtimeIsReady && !normalRestoreBlocked && !companionRestoreBlocked && (pooledWebView.map(
                ownsActiveInteraction(of:)
            ) ?? false),
            fullscreenSourceSlotID: fullscreenProfile?.id,
            panelIsVisible: panel.isVisible,
            companionSlotID: companionActiveProfile?.id,
            companionCurrentWebViewIsSlotWebView: runtimeIsReady && !companionRestoreBlocked && (pooledWebView.map { webView in
                sourceHostController.companionContainer.currentWebView === webView
            } ?? false)
        )
    }

    private func isSlotActuallyPresented(slotID: UUID) -> Bool {
        userVisiblePresentation(
            slotID: slotID,
            facts: attentionPresentationFacts(slotID: slotID)
        )
    }

    private func isInteractionSurfacePresented(slotID: UUID) -> Bool {
        interactionSurfacePresentation(
            slotID: slotID,
            facts: attentionPresentationFacts(slotID: slotID)
        )
    }

    private func userVisiblePresentation(
        slotID: UUID,
        facts: AttentionPresentation.Facts
    ) -> Bool {
        guard runtimeReadinessState(for: slotID) == .ready else { return false }
#if DEBUG
        if let override = debugPresentationFactOverrides[slotID] {
            return override
        }
#endif
        return AttentionPresentation.isUserVisible(facts)
    }

    private func interactionSurfacePresentation(
        slotID: UUID,
        facts: AttentionPresentation.Facts
    ) -> Bool {
        guard runtimeReadinessState(for: slotID) == .ready else { return false }
#if DEBUG
        if let override = debugInteractionSurfaceFactOverrides[slotID] {
            return override
        }
        if let override = debugPresentationFactOverrides[slotID] {
            return override
        }
#endif
        return AttentionPresentation.isInteractionSurfacePresented(facts)
    }

    private func ownsActiveInteraction(of webView: WKWebView) -> Bool {
        webView.window?.isKeyWindow == true
    }

    func acknowledgeAttentionIfActuallyVisible(slotID: UUID) {
        attentionCoordinator.acknowledge(
            slotID: slotID,
            userVisible: isAttentionUserVisible(slotID: slotID)
        )
        synchronizeAttentionPresentation()
    }

    private func acknowledgeActiveAttentionIfActuallyPresented() {
        guard let activeSlotID = tabStore.activeTabID else { return }
        acknowledgeAttentionIfActuallyVisible(slotID: activeSlotID)
    }

    private func selectSlotFromExplicitUserAction(
        _ slotID: UUID,
        trace: RuntimeDiagnosticTrace? = nil
    ) -> Bool {
        let trace = trace ?? diagnostics.beginTrace(root: "tab.selection")
        guard tabStore.select(id: slotID, trace: trace) else { return false }
        acknowledgeUnreadAfterExplicitSelection(slotID: slotID, trace: trace)
        return true
    }

    func presentSlotFromCompletionNotification(
        _ slotID: UUID,
        trace: RuntimeDiagnosticTrace? = nil
    ) -> Bool {
        let trace = trace ?? diagnostics.beginTrace(root: "notification.route")
        diagnostics.record(
            event: "notification.route.received",
            level: .info,
            subsystem: "notification",
            trace: trace,
            fields: ["slot_id": .string(slotID.uuidString)]
        )
        suppressTabStoreSynchronization = true
        let selected = tabStore.select(id: slotID, trace: trace)
        suppressTabStoreSynchronization = false
        guard selected else {
            diagnostics.record(
                event: "notification.route.unavailable",
                level: .warning,
                subsystem: "notification",
                trace: trace,
                fields: ["slot_id": .string(slotID.uuidString)]
            )
            return false
        }
        // A visible panel needs the target synchronized now. A hidden panel
        // reaches the same gate from showFloatTabs after requested visibility
        // is established, avoiding eager Runtime creation during selection.
        if panel.isVisible {
            synchronizeSlotState()
        }
        presentFloatTabs(trace: trace)
        acknowledgeUnreadAfterExplicitSelection(slotID: slotID, trace: trace)
        return true
    }

    private func acknowledgeUnreadAfterExplicitSelection(
        slotID: UUID,
        trace: RuntimeDiagnosticTrace? = nil
    ) {
        if let pending = pendingRuntimeMaterialization,
           pending.slotID == slotID,
           isPendingRuntimeMaterializationCurrent(pending) {
            if unreadResponseCoordinator.unreadSlotIDs.contains(slotID) {
                pendingColdUnreadAcknowledgement = PendingColdUnreadAcknowledgement(
                    slotID: slotID,
                    materializationGeneration: pending.generation,
                    trace: trace ?? diagnostics.beginTrace(root: "unread.explicit_selection")
                )
            } else if pendingColdUnreadAcknowledgement?.slotID == slotID,
                      pendingColdUnreadAcknowledgement?.materializationGeneration
                        == pending.generation {
                pendingColdUnreadAcknowledgement = nil
            }
            return
        }

        let facts = unreadPresentationFacts(slotID: slotID)
        guard facts.activeSlotMatches else {
            finishUnreadSelectionAttemptIfNeeded(
                slotID: slotID,
                source: .explicitSelection,
                trace: trace,
                skippedReason: .notActiveSlot
            )
            return
        }
        guard facts.presentationVisible else {
            if unreadResponseCoordinator.unreadSlotIDs.contains(slotID) {
                _ = beginUnreadAcknowledgement(
                    slotID: slotID,
                    source: .explicitSelection,
                    trace: trace
                )
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let deferredFacts = self.unreadPresentationFacts(slotID: slotID)
                guard deferredFacts.activeSlotMatches else {
                    self.finishUnreadSelectionAttemptIfNeeded(
                        slotID: slotID,
                        source: .explicitSelectionDeferred,
                        trace: trace,
                        skippedReason: .notActiveSlot
                    )
                    return
                }
                guard deferredFacts.presentationVisible else {
                    self.finishUnreadSelectionAttemptIfNeeded(
                        slotID: slotID,
                        source: .explicitSelectionDeferred,
                        trace: trace,
                        skippedReason: .presentationNotReady
                    )
                    return
                }
                self.acknowledgePresentedSelectionIfNeeded(
                    slotID: slotID,
                    source: .explicitSelectionDeferred,
                    trace: trace
                )
            }
            return
        }

        acknowledgePresentedSelectionIfNeeded(
            slotID: slotID,
            source: .explicitSelection,
            trace: trace
        )
    }

    private func acknowledgePresentedSelectionIfNeeded(
        slotID: UUID,
        source: UnreadDiagnosticSource,
        trace: RuntimeDiagnosticTrace?
    ) {
        if let attempt = beginUnreadAcknowledgement(
            slotID: slotID,
            source: source,
            trace: trace
        ) {
            guard attempt.facts.activeSlotMatches else {
                finishUnreadAcknowledgement(
                    attempt,
                    skippedReason: .notActiveSlot
                )
                return
            }
            guard attempt.facts.presentationVisible else {
                finishUnreadAcknowledgement(
                    attempt,
                    skippedReason: .presentationNotReady
                )
                return
            }
            unreadResponseCoordinator.acknowledge(slotID: slotID)
            synchronizeDurableUnreadPresentation()
            finishUnreadAcknowledgement(attempt, skippedReason: .stateUnchanged)
        }
        requestLatestResponseHandledSnapshot(slotID: slotID, source: source)
    }

    private func finishUnreadSelectionAttemptIfNeeded(
        slotID: UUID,
        source: UnreadDiagnosticSource,
        trace: RuntimeDiagnosticTrace?,
        skippedReason: UnreadDiagnosticSkipReason
    ) {
        guard let attempt = beginUnreadAcknowledgement(
            slotID: slotID,
            source: source,
            trace: trace
        ) else {
            return
        }
        finishUnreadAcknowledgement(attempt, skippedReason: skippedReason)
    }

    private func handleTrustedInteraction(
        slotID: UUID,
        event: ChatGPTTrustedInteractionEvent
    ) {
        let source: UnreadDiagnosticSource = event.kind == .assistantPointer
            ? .trustedAssistantPointer
            : .trustedManualScroll
        guard let attempt = beginUnreadAcknowledgement(
            slotID: slotID,
            source: source
        ) else {
            return
        }
        let interactionPresented = attempt.facts.interactionSurfacePresented
        guard interactionPresented else {
            finishUnreadAcknowledgement(
                attempt,
                skippedReason: .notActuallyPresented
            )
            return
        }

        if let responseIdentity = event.responseIdentity,
           event.responseComplete {
            unreadResponseCoordinator.recordHandled(
                slotID: slotID,
                responseIdentity: responseIdentity
            )
            let result = unreadResponseCoordinator.acknowledge(
                slotID: slotID,
                responseIdentity: responseIdentity
            )
            if result == .preservedIdentityMismatch {
                finishUnreadAcknowledgement(
                    attempt,
                    skippedReason: .responseIdentityMismatch
                )
                return
            }
        } else {
            unreadResponseCoordinator.acknowledge(slotID: slotID)
        }
        synchronizeDurableUnreadPresentation()
        finishUnreadAcknowledgement(attempt, skippedReason: .stateUnchanged)
    }

    private func acknowledgeUnreadAfterTrustedPageInteraction(
        slotID: UUID,
        source: UnreadDiagnosticSource = .trustedManualScroll,
        responseIdentity: ChatGPTResponseIdentity? = nil,
        responseComplete: Bool = false
    ) {
        guard let attempt = beginUnreadAcknowledgement(
            slotID: slotID,
            source: source
        ) else {
            return
        }
        let interactionPresented: Bool
        switch source {
        case .generationStarted:
            interactionPresented = attempt.facts.presentationVisible
        default:
            interactionPresented = attempt.facts.interactionSurfacePresented
        }
        guard interactionPresented else {
            finishUnreadAcknowledgement(
                attempt,
                skippedReason: .notActuallyPresented
            )
            return
        }
        if let responseIdentity, responseComplete {
            unreadResponseCoordinator.recordHandled(
                slotID: slotID,
                responseIdentity: responseIdentity
            )
            let result = unreadResponseCoordinator.acknowledge(
                slotID: slotID,
                responseIdentity: responseIdentity
            )
            if result == .preservedIdentityMismatch {
                finishUnreadAcknowledgement(
                    attempt,
                    skippedReason: .responseIdentityMismatch
                )
                return
            }
        } else {
            unreadResponseCoordinator.acknowledge(slotID: slotID)
        }
        synchronizeDurableUnreadPresentation()
        finishUnreadAcknowledgement(attempt, skippedReason: .stateUnchanged)
    }

    private func unreadPresentationFacts(slotID: UUID) -> UnreadPresentationFacts {
        let webView = webViewPool.existingWebView(for: slotID)
        let presentationFacts = attentionPresentationFacts(slotID: slotID)
        return UnreadPresentationFacts(
            presentationVisible: userVisiblePresentation(
                slotID: slotID,
                facts: presentationFacts
            ),
            interactionSurfacePresented: interactionSurfacePresentation(
                slotID: slotID,
                facts: presentationFacts
            ),
            webWindowKey: webView?.window?.isKeyWindow == true,
            activeSlotMatches: tabStore.activeTabID == slotID,
            sessionLocked: sourceHostController.isSessionLocked,
            panelVisible: panel.isVisible
        )
    }

    private func beginUnreadAcknowledgement(
        slotID: UUID,
        source: UnreadDiagnosticSource,
        trace: RuntimeDiagnosticTrace? = nil
    ) -> UnreadAcknowledgementAttempt? {
        guard unreadResponseCoordinator.unreadSlotIDs.contains(slotID) else {
            return nil
        }
        let facts = unreadPresentationFacts(slotID: slotID)
        let attempt = UnreadAcknowledgementAttempt(
            slotID: slotID,
            source: source,
            facts: facts,
            trace: trace ?? diagnostics.beginTrace(root: "unread.interaction")
        )
        recordUnreadDiagnostic(
            event: "unread.acknowledge_attempt",
            trace: attempt.trace,
            fields: [
                "slot_id": .string(slotID.uuidString),
                "source": .string(source.rawValue),
                "presentation_visible": .bool(facts.presentationVisible),
                "web_window_key": .bool(facts.webWindowKey),
                "interaction_surface_presented": .bool(facts.interactionSurfacePresented),
                "active_slot_matches": .bool(facts.activeSlotMatches),
                "unread_before": .bool(unreadResponseCoordinator.unreadSlotIDs.contains(slotID))
            ]
        )
        return attempt
    }

    /// Resolves bounded notification projection input for one newly `.marked`
    /// hidden completion: the persistent Slot display name and an optional
    /// one-shot assistant-response preview. The preview is best-effort — a
    /// missing bridge, reclaimed Runtime, replaced document or generating
    /// state simply yields no preview. Exactly one projection callback fires
    /// per `.marked` completion; neither name nor preview is persisted here.
    private func projectCompletionNotification(slotID: UUID) {
        let displayName = tabStore.profiles.first(where: { $0.id == slotID })?.name
        guard let responseBridge = webViewPool.responseBridge(for: slotID) else {
            onChatGPTUnreadCompletionMarked?(slotID, displayName, nil)
            return
        }
        responseBridge.previewLatestAssistantResponse { [weak self] snapshot in
            guard let self else { return }
            self.onChatGPTUnreadCompletionMarked?(
                slotID,
                displayName,
                snapshot?.previewText
            )
        }
    }

    private func requestLatestResponseHandledSnapshot(
        slotID: UUID,
        source: UnreadDiagnosticSource
    ) {
        guard let responseBridge = webViewPool.responseBridge(for: slotID) else {
            return
        }
        responseBridge.snapshotLatestResponseStatus { [weak self] snapshot in
            guard let self,
                  let snapshot,
                  !snapshot.generating,
                  let responseIdentity = snapshot.responseIdentity else {
                return
            }
            let reconciliation = self.unreadResponseCoordinator.reconcileHandledSnapshot(
                slotID: slotID,
                responseIdentity: responseIdentity
            )
            guard reconciliation == .cleared else { return }
            self.synchronizeDurableUnreadPresentation()
            self.recordUnreadDiagnostic(
                event: "unread.late_completion_reconciled",
                fields: [
                    "slot_id": .string(slotID.uuidString),
                    "source": .string(source.rawValue),
                    "identity_match": .bool(true),
                    "unread_before": .bool(true),
                    "unread_after": .bool(false)
                ]
            )
        }
    }

    private func finishUnreadAcknowledgement(
        _ attempt: UnreadAcknowledgementAttempt,
        skippedReason: UnreadDiagnosticSkipReason
    ) {
        let unreadAfter = unreadResponseCoordinator.unreadSlotIDs.contains(attempt.slotID)
        guard !unreadAfter else {
            recordUnreadDiagnostic(
                event: "unread.acknowledge_skipped",
                trace: attempt.trace,
                fields: [
                    "slot_id": .string(attempt.slotID.uuidString),
                    "source": .string(attempt.source.rawValue),
                    "reason": .string(skippedReason.rawValue),
                    "presentation_visible": .bool(attempt.facts.presentationVisible),
                    "web_window_key": .bool(attempt.facts.webWindowKey),
                    "interaction_surface_presented": .bool(attempt.facts.interactionSurfacePresented),
                    "unread_before": .bool(true),
                    "unread_after": .bool(true)
                ]
            )
            return
        }
        recordUnreadDiagnostic(
            event: "unread.acknowledged",
            trace: attempt.trace,
            fields: [
                "slot_id": .string(attempt.slotID.uuidString),
                "source": .string(attempt.source.rawValue),
                "presentation_visible": .bool(attempt.facts.presentationVisible),
                "web_window_key": .bool(attempt.facts.webWindowKey),
                "interaction_surface_presented": .bool(attempt.facts.interactionSurfacePresented)
            ]
        )
    }

    private func recordUnreadDiagnostic(
        event: String,
        trace: RuntimeDiagnosticTrace? = nil,
        fields: [String: RuntimeDiagnosticValue]
    ) {
        diagnostics.record(
            event: event,
            level: .info,
            subsystem: "unread",
            trace: trace,
            fields: fields
        )
    }

    private func focusActiveWebViewIfAvailable(makeSourceWindowMain: Bool = false) {
        guard requestedVisibility,
              !addressOverlayView.isPresented,
              let activeSlotID = tabStore.activeTabID,
              let webView = exactReadyWebView(for: activeSlotID) else { return }
        if sourceHostController.isSessionLocked {
            guard sourceHostController.companionContainer.currentWebView === webView,
                  !sourceHostController.companionContainer.isShowingRestoringState else { return }
            WebViewFocus.focus(webView, in: panel)
            return
        }
        guard rootView.webPanelContainerView.currentWebView === webView,
              !rootView.webPanelContainerView.isShowingRestoringState else { return }
        sourceHostController.orderFrontAndFocus(
            webView,
            makeSourceWindowMain: makeSourceWindowMain
        )
    }

    private func togglePrimaryWebFocus(trace: RuntimeDiagnosticTrace? = nil) {
        presentationWebFocusTask?.cancel()
        presentationWebFocusTask = nil

        activateFloatTabs(trace: trace)

        guard let webView = selectedPresentationWebView() else {
            Task { @MainActor [weak self] in
                _ = await self?.webFocusRouter.togglePrimaryFocus(trace: trace)
            }
            return
        }

        webFocusRouter.setCurrentWebView(webView)
        if sourceHostController.isSessionLocked {
            panel.makeKeyAndOrderFront(nil)
            WebViewFocus.focus(webView, in: panel)
        } else {
            sourceHostController.orderFrontAndFocus(webView)
        }

        Task { @MainActor [weak self, weak webView] in
            guard let self, let webView,
                  self.webFocusRouter.currentWebView === webView else { return }
            _ = await self.webFocusRouter.togglePrimaryFocus(trace: trace)
        }
    }

    private func returnActiveSlotHome() {
        guard let id = tabStore.activeTabID else { return }
        returnSlotHome(id: id)
    }

    private func reloadActiveSlot() {
        guard let id = tabStore.activeTabID else { return }
        reloadSlot(id: id)
    }

    private func reloadSlot(id: UUID) {
        let manualIntent: ManualFaviconReloadIntent? = {
            guard tabStore.activeTabID == id,
                  let identity = webViewPool.runtimeDiagnosticIdentity(for: id),
                  webViewPool.existingWebView(for: id) != nil,
                  let readiness = runtimeReadinessBySlot[id],
                  readiness.identity == identity,
                  let baselineGeneration = readiness.navigationGeneration,
                  baselineGeneration > 0 else {
                return nil
            }
            return ManualFaviconReloadIntent(
                runtimeIdentity: identity,
                baselineNavigationGeneration: baselineGeneration
            )
        }()
        if let manualIntent {
            manualFaviconReloadIntentsBySlot[id] = manualIntent
        }
        guard webViewPool.reload(slotID: id) else {
            if let manualIntent,
               manualFaviconReloadIntentsBySlot[id] == manualIntent {
                manualFaviconReloadIntentsBySlot.removeValue(forKey: id)
            }
            return
        }
        if tabStore.activeTabID == id {
            focusActiveWebViewIfAvailable()
        }
    }

    private func returnSlotHome(id: UUID) {
        guard let profile = tabStore.profiles.first(where: { $0.id == id }),
              WebAppURL.isSafe(profile.homeURL) else {
            return
        }

        tabStore.updateCurrentURL(id: id, url: profile.homeURL)
        if webViewPool.contains(slotID: id) {
            webViewPool.navigate(
                slotID: id,
                to: profile.homeURL,
                allowHTTPEntryFallback: profile.homeURLSchemeWasInferred
            )
        }

        if tabStore.activeTabID == id {
            focusActiveWebViewIfAvailable()
        }
    }

    private func presentAddWebAppEditor() {
        guard let modalHost = modalPresentationHostWindow(),
              modalHost.attachedSheet == nil else {
            return
        }
        beginRailModalInteraction()
        rootView.externalControlZoneView.setAddEditorOpen(true)

        WebAppEditorController.presentAdd(
            browserProfiles: tabStore.browserProfiles,
            defaultProfileName: tabStore.defaultBrowserProfilePresentation.name,
            customProfilesSupported: webViewPool.customBrowserProfilesSupported,
            allowsWindowSizeEditing: preferencesStore.windowSizeMode == .perWebApp,
            attachedTo: modalHost
        ) { [weak self] value in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.endRailModalInteraction()
                self.rootView.externalControlZoneView.setAddEditorOpen(false)
                guard let value,
                      value.browserProfileID == nil || self.webViewPool.customBrowserProfilesSupported,
                      let added = self.tabStore.add(
                        name: value.name,
                        homeURL: value.url,
                        homeURLSchemeWasInferred: value.homeURLSchemeWasInferred,
                        renderingProfile: value.renderingProfile,
                        browserProfileID: value.browserProfileID
                      ) else {
                    return
                }

                if self.preferencesStore.windowSizeMode == .perWebApp {
                    self.applyPreferredViewport(added.renderingProfile.viewportSize)
                }
            }
        }
        if modalHost.attachedSheet == nil {
            endRailModalInteraction()
            rootView.externalControlZoneView.setAddEditorOpen(false)
        }
    }

    private func presentEditWebAppEditor(id: UUID) {
        guard let modalHost = modalPresentationHostWindow(),
              modalHost.attachedSheet == nil,
              let profile = tabStore.profiles.first(where: { $0.id == id }) else {
            return
        }

        beginRailModalInteraction()
        WebAppEditorController.presentEdit(
            profile: profile,
            allowsWindowSizeEditing: preferencesStore.windowSizeMode == .perWebApp,
            attachedTo: modalHost
        ) { [weak self] value in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.endRailModalInteraction()
                guard let value else { return }
                let oldHomeURL = self.tabStore.profiles.first(where: { $0.id == id })?.homeURL
                guard self.tabStore.update(
                    id: id,
                    name: value.name,
                    homeURL: value.url,
                    homeURLSchemeWasInferred: value.homeURLSchemeWasInferred,
                    renderingProfile: value.renderingProfile
                ) else {
                    return
                }
                if oldHomeURL != value.url {
                    self.webViewPool.navigate(
                        slotID: id,
                        to: value.url,
                        allowHTTPEntryFallback: value.homeURLSchemeWasInferred
                    )
                }
                if self.tabStore.activeTabID == id,
                   self.preferencesStore.windowSizeMode == .perWebApp {
                    self.applyPreferredViewport(value.renderingProfile.viewportSize)
                }
            }
        }
        if modalHost.attachedSheet == nil {
            endRailModalInteraction()
        }
    }

    @discardableResult
    private func removeConfirmedSlot(slotID id: UUID) -> Bool {
        let wasUnread = unreadResponseCoordinator.unreadSlotIDs.contains(id)
        if wasUnread {
            unreadPruneDiagnosticSuppressionIDs.insert(id)
        }
        guard tabStore.remove(id: id) else {
            unreadPruneDiagnosticSuppressionIDs.remove(id)
            return false
        }
        slotLifecycleCoordinator.remove(slotID: id)
        webViewPool.remove(slotID: id)
        attentionCoordinator.removeSlot(id)
        unreadResponseCoordinator.removeSlot(slotID: id)
        synchronizeDurableUnreadPresentation()
        if wasUnread {
            recordUnreadDiagnostic(event: "unread.removed", fields: [
                "slot_id": .string(id.uuidString),
                "reason": .string("slot_deleted")
            ])
        }
        unreadPruneDiagnosticSuppressionIDs.remove(id)
        return true
    }

    private func presentRemoveConfirmation(id: UUID) {
        guard Self.canRemoveSlotDuringFullscreen(
            slotID: id,
            fullscreenSourceSlotID: fullscreenProfile?.id,
            sessionIsLocked: sourceHostController.isSessionLocked
        ) else {
            NSSound.beep()
            return
        }
        guard let modalHost = modalPresentationHostWindow(),
              modalHost.attachedSheet == nil,
              let profile = tabStore.profiles.first(where: { $0.id == id }) else {
            return
        }

        beginRailModalInteraction()
        WebAppEditorController.confirmRemove(profile: profile, attachedTo: modalHost) { [weak self] confirmed in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.endRailModalInteraction()
                guard confirmed else { return }
                _ = self.removeConfirmedSlot(slotID: id)
            }
        }
        if modalHost.attachedSheet == nil {
            endRailModalInteraction()
        }
    }

    private func changeActiveZoom(larger: Bool) {
        guard let profile = tabStore.activeProfile else { return }
        let current = profile.renderingProfile.zoom
        let target = larger
            ? ZoomSteps.nextLarger(after: current)
            : ZoomSteps.nextSmaller(before: current)
        setActiveZoom(target)
    }

    private func setActiveZoom(_ zoom: CGFloat) {
        guard let id = tabStore.activeTabID else { return }
        let normalized = ZoomSteps.nearest(to: zoom)
        guard tabStore.updateZoom(id: id, zoom: normalized) else { return }
        synchronizeTransientUIHost()
        statusHUDView.show(zoom: normalized)
    }

    @discardableResult
    func setResidency(_ policy: SlotResidencyPolicy, for id: UUID) -> Bool {
        // Legacy IPC/test adapter only. The canonical product state is
        // Automatic / Keep Loaded and no current UI projects legacy labels.
        guard tabStore.updateResourcePolicy(id: id, residencyPolicy: policy) else {
            return false
        }
        if tabStore.activeTabID == id {
            synchronizeTransientUIHost()
        }
        return true
    }

    @discardableResult
    func setActiveResidency(_ policy: SlotResidencyPolicy) -> Bool {
        guard let id = tabStore.activeTabID else { return false }
        return setResidency(policy, for: id)
    }

    private func presentAddressBar() {
        guard let url = currentAddressURL() else { return }
        synchronizeTransientUIHost()
        let hostWindow = sourceHostController.isSessionLocked
            ? panel
            : sourceHostController.window
        hostWindow.makeKeyAndOrderFront(nil)
        addressOverlayView.present(url: url, in: hostWindow)
    }

    private func currentActualPageURL() -> URL? {
        guard let id = tabStore.activeTabID else { return nil }
        return webViewPool.committedURL(for: id)
    }

    private func currentAddressURL() -> URL? {
        if let actualURL = currentActualPageURL() { return actualURL }
        if let webURL = selectedPresentationWebView()?.url,
           WebAppURL.isSafe(webURL) {
            return webURL
        }
        guard let profile = tabStore.activeProfile else { return nil }
        if let currentURL = profile.currentURL, WebAppURL.isSafe(currentURL) {
            return currentURL
        }
        return WebAppURL.isSafe(profile.homeURL) ? profile.homeURL : nil
    }

    private func setCurrentPageAsHome() -> Bool {
        guard let id = tabStore.activeTabID,
              let currentURL = currentActualPageURL() else {
            return false
        }
        guard tabStore.updateHomeURL(id: id, homeURL: currentURL) else {
            return false
        }

        addressOverlayView.dismiss()
        focusActiveWebViewIfAvailable()
        return true
    }

    private func selectedPresentationWebView() -> WKWebView? {
        guard let activeSlotID = tabStore.activeTabID,
              let readyWebView = exactReadyWebView(for: activeSlotID) else {
            return nil
        }
        let presentationContainer = sourceHostController.isSessionLocked
            ? sourceHostController.companionContainer
            : rootView.webPanelContainerView
        guard !presentationContainer.isShowingRestoringState,
              presentationContainer.currentWebView === readyWebView else {
            return nil
        }
        return readyWebView
    }

    static func canRemoveSlotDuringFullscreen(
        slotID: UUID,
        fullscreenSourceSlotID: UUID?,
        sessionIsLocked: Bool
    ) -> Bool {
        !sessionIsLocked || slotID != fullscreenSourceSlotID
    }

    enum ModalPresentationHost: Equatable {
        case sourceWindow
        case shellWindow
    }

    static func modalPresentationHost(
        sessionState: FullscreenSourceSessionState,
        sourceWindowIsVisible: Bool,
        sourceWindowHasScreen: Bool,
        shellWindowIsVisible: Bool,
        fullscreenCompanionIsReady: Bool
    ) -> ModalPresentationHost? {
        switch sessionState {
        case .idle:
            guard sourceWindowIsVisible, sourceWindowHasScreen else {
                return nil
            }
            return .sourceWindow

        case .fullscreen:
            guard shellWindowIsVisible, fullscreenCompanionIsReady else {
                return nil
            }
            return .shellWindow

        case .entering, .exiting, .restoring:
            return nil
        }
    }

    private func modalPresentationHostWindow() -> NSWindow? {
        switch Self.modalPresentationHost(
            sessionState: sourceHostController.sessionState,
            sourceWindowIsVisible: sourceHostController.window.isVisible,
            sourceWindowHasScreen: sourceHostController.window.screen != nil,
            shellWindowIsVisible: panel.isVisible,
            fullscreenCompanionIsReady: panel.isFullscreenCompanionPresentationReady
        ) {
        case .sourceWindow:
            return sourceHostController.window
        case .shellWindow:
            return panel
        case nil:
            return nil
        }
    }

    private func commitAddress(_ rawValue: String) -> Bool {
        guard let id = tabStore.activeTabID,
              let normalized = WebAppURL.normalizedEntry(from: rawValue) else {
            NSSound.beep()
            addressOverlayView.markInvalid()
            return false
        }

        tabStore.updateCurrentURL(id: id, url: normalized.url)
        webViewPool.navigate(
            slotID: id,
            to: normalized.url,
            allowHTTPEntryFallback: normalized.schemeWasInferred
        )
        addressOverlayView.dismiss()
        focusActiveWebViewIfAvailable()
        return true
    }

    private func copyAddressToPasteboard(_ rawValue: String) -> Bool {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(value, forType: .string)
    }

    private func presentDerivedWebAppFromCurrentPage() {
        guard let modalHost = modalPresentationHostWindow(),
              modalHost.attachedSheet == nil,
              let source = tabStore.activeProfile,
              let currentURL = currentAddressURL() else {
            return
        }

        let sourceID = source.id
        beginRailModalInteraction()
        addressOverlayView.dismiss()
        WebAppEditorController.presentDerivedAdd(
            sourceProfile: source,
            currentURL: currentURL,
            attachedTo: modalHost
        ) { [weak self] name in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.endRailModalInteraction()
                defer { self.focusActiveWebViewIfAvailable() }
                guard let name else { return }
                _ = self.tabStore.addDerived(
                    from: sourceID,
                    name: name,
                    homeURL: currentURL
                )
            }
        }
        if modalHost.attachedSheet == nil {
            endRailModalInteraction()
        }
    }

    private func beginRailModalInteraction() {
        rootView.externalControlZoneView.setModalPresentationActive(true)
    }

    private func endRailModalInteraction() {
        rootView.externalControlZoneView.setModalPresentationActive(false)
    }

    private func handleManualResizeEnded() {
        clampPanelToConnectedScreens(preservingPreferredSize: false)
        let viewport = PanelMetrics.viewportSize(forPanelSize: panel.frame.size)

        switch preferencesStore.windowSizeMode {
        case .perWebApp:
            if let active = tabStore.activeProfile {
                let previousViewport = active.renderingProfile.viewportSize
                if !tabStore.updatePreferredViewport(
                    id: active.id,
                    size: CGSize(width: viewport.width, height: viewport.height)
                ) {
                    applyViewportSize(previousViewport, animated: false)
                    return
                }
            }
        case .fixed:
            preferencesStore.fixedViewportSize = viewport
        }
        preferredPanelSize = panel.frame.size
        persistPanelFrame()
    }

    private func applyPreferredViewport(_ viewportSize: CGSize) {
        guard preferencesStore.windowSizeMode == .perWebApp,
              hasPositionedPanel else { return }
        applyViewportSize(viewportSize, animated: true)
    }

    private func applySharedFixedViewport(_ viewportSize: CGSize, animated: Bool) {
        guard preferencesStore.windowSizeMode == .fixed,
              hasPositionedPanel else { return }
        applyViewportSize(viewportSize, animated: animated)
    }

    private func applyViewportSize(_ viewportSize: CGSize, animated: Bool) {
        preferredPanelSize = PanelMetrics.clampedPanelSize(
            PanelMetrics.panelSize(forViewport: NSSize(
                width: viewportSize.width,
                height: viewportSize.height
            ))
        )
        let visibleFrame = panel.screen?.visibleFrame
            ?? ScreenPositioning.targetScreen()?.visibleFrame
        guard let visibleFrame else { return }

        let target = ScreenPositioning.frameFollowingPreferredViewport(
            currentFrame: panel.frame,
            preferredViewportSize: NSSize(
                width: viewportSize.width,
                height: viewportSize.height
            ),
            followPreferredSize: true,
            visibleFrame: visibleFrame
        )
        if target != panel.frame {
            panel.setFrame(target, display: true, animate: animated)
            synchronizeSourceHostFrame(display: true)
        }
        persistPanelFrame()
    }

    private func synchronizeFixedViewportAfterPositioning() {
        guard preferencesStore.windowSizeMode == .fixed,
              hasPositionedPanel else { return }
        if preferencesStore.hasStoredFixedViewportSize {
            applySharedFixedViewport(preferencesStore.fixedViewportSize, animated: false)
        } else {
            let viewport = PanelMetrics.viewportSize(forPanelSize: panel.frame.size)
            preferencesStore.fixedViewportSize = viewport
        }
    }

    private func activateFloatTabs(trace: RuntimeDiagnosticTrace? = nil) {
        invalidatePendingRestoreObservationForNewPresentation()
        diagnostics.record(
            event: "app.activation.requested",
            level: .info,
            subsystem: "app",
            trace: trace,
            fields: [
                "activate_all_windows": .bool(true),
                "ignoring_other_apps": .bool(true)
            ]
        )
        _ = NSRunningApplication.current.activate(
            options: [.activateAllWindows, .activateIgnoringOtherApps]
        )
        NSApp.activate(ignoringOtherApps: true)
    }

    private func beginPresentationFocusHandshake(
        trace: RuntimeDiagnosticTrace? = nil,
        webFocusOwner: PresentationWebFocusOwner = .standardPresentation
    ) {
        let previousGeneration = presentationFocusGeneration
        let previousTrace = presentationTrace
        if presentationNativeFocusPending || presentationWebFocusPending {
            diagnostics.record(
                event: "presentation_focus.stale_generation",
                level: .notice,
                subsystem: "panel",
                trace: previousTrace,
                fields: [
                    "focus_generation": .integer(Int64(previousGeneration)),
                    "replacement_generation": .integer(Int64(previousGeneration &+ 1)),
                    "reason": .string("request_replaced")
                ]
            )
        }
        presentationFocusGeneration &+= 1
        presentationTrace = trace
        presentationWebFocusOwner = webFocusOwner
        presentationActivationConfirmedGeneration = nil
        presentationNativeFocusTransferState.beginGeneration()
        presentationNativeFocusPending = true
        presentationWebFocusPending = true

        diagnostics.record(
            event: "presentation_focus.begin",
            level: .info,
            subsystem: "panel",
            trace: trace,
            fields: [
                "focus_generation": .integer(Int64(presentationFocusGeneration)),
                "focus_owner": .string(webFocusOwner.rawValue)
            ]
        )
        diagnostics.record(
            event: "presentation_focus.native.pending",
            level: .info,
            subsystem: "panel",
            trace: trace,
            fields: [
                "focus_generation": .integer(Int64(presentationFocusGeneration)),
                "focus_owner": .string(webFocusOwner.rawValue)
            ]
        )
        diagnostics.record(
            event: "presentation_focus.web.pending",
            level: .info,
            subsystem: "panel",
            trace: trace,
            fields: [
                "focus_generation": .integer(Int64(presentationFocusGeneration)),
                "focus_owner": .string(webFocusOwner.rawValue)
            ]
        )

        presentationFocusTask?.cancel()
        presentationFocusTask = nil
        presentationWebFocusTask?.cancel()
        presentationWebFocusTask = nil

        completePresentationFocusIfReady()
    }

    private func isCurrentPresentationFocusRequest(_ generation: UInt64) -> Bool {
        requestedVisibility && generation == presentationFocusGeneration
    }

    private func completePresentationFocusIfReady() {
        let readiness = presentationFocusReadinessProvider?() ?? (
            applicationActive: NSApp.isActive,
            windowKey: PresentationNativeFocusPolicy.isNativeWindowReady(
                owner: presentationWebFocusOwner,
                applicationActive: NSApp.isActive,
                shellWindowIsKey: panel.isKeyWindow,
                sourceWindowIsKey: sourceHostController.window.isKeyWindow,
                sourceSessionLocked: sourceHostController.isSessionLocked
            )
        )
        guard requestedVisibility, readiness.applicationActive else { return }
        if (presentationNativeFocusPending || presentationWebFocusPending),
           presentationActivationConfirmedGeneration != presentationFocusGeneration {
            presentationActivationConfirmedGeneration = presentationFocusGeneration
            diagnostics.record(
                event: "app.activation.confirmed",
                level: .info,
                subsystem: "app",
                trace: presentationTrace,
                fields: [
                    "app_active": .bool(true),
                    "source": .string("focus_handshake_precondition")
                ]
            )
        }
        var nativeWindowReady = readiness.windowKey
        if presentationWebFocusOwner == .externalVoice,
           !sourceHostController.isSessionLocked {
            switch presentationNativeFocusTransferState.action(
                sourceWindowIsKey: sourceHostController.window.isKeyWindow
            ) {
            case .sourceAlreadyKey:
                presentationNativeFocusPending = false
                nativeWindowReady = true
            case .issueSourceKeyTransfer:
                diagnostics.record(
                    event: "presentation_focus.native.transfer_issued",
                    level: .info,
                    subsystem: "panel",
                    trace: presentationTrace,
                    fields: [
                        "focus_generation": .integer(Int64(presentationFocusGeneration)),
                        "focus_owner": .string(presentationWebFocusOwner.rawValue),
                        "source_key_before": .bool(false),
                        "make_source_window_main": .bool(false)
                    ]
                )
                focusActiveWebViewIfAvailable(makeSourceWindowMain: false)
                return
            case .waitForSourceKey:
                return
            case .alreadyConsumed:
                nativeWindowReady = true
            }
        }
        guard nativeWindowReady else { return }

        if presentationNativeFocusPending {
            presentationNativeFocusPending = false
            focusActiveWebViewIfAvailable(
                makeSourceWindowMain: PresentationNativeFocusPolicy.shouldMakeSourceWindowMain(
                    owner: presentationWebFocusOwner,
                    sourceSessionLocked: sourceHostController.isSessionLocked
                )
            )
            diagnostics.record(
                event: "presentation_focus.native.ready",
                level: .info,
                subsystem: "panel",
                trace: presentationTrace,
                fields: [
                    "focus_generation": .integer(Int64(presentationFocusGeneration)),
                    "focus_owner": .string(presentationWebFocusOwner.rawValue),
                    "shell_key": .bool(panel.isKeyWindow),
                    "source_key": .bool(sourceHostController.window.isKeyWindow)
                ]
            )
            schedulePresentationFocusSettle()
        }

        if presentationWebFocusPending,
           presentationWebFocusOwner == .standardPresentation,
           presentationWebFocusTask == nil {
            schedulePresentationWebInputFocus()
        }
        acknowledgeActiveAttentionIfActuallyPresented()

        guard !presentationNativeFocusPending,
              !presentationWebFocusPending,
              let trace = presentationTrace else {
            return
        }

        let focusGeneration = presentationFocusGeneration
        let focusOwner = presentationWebFocusOwner
        diagnostics.record(
            event: "presentation_focus.completed",
            level: .notice,
            subsystem: "panel",
            trace: trace,
            fields: [
                "focus_generation": .integer(Int64(focusGeneration)),
                "focus_owner": .string(focusOwner.rawValue),
                "shell_key": .bool(panel.isKeyWindow),
                "source_key": .bool(sourceHostController.window.isKeyWindow)
            ]
        )
        diagnostics.record(
            event: "panel.presentation.completed",
            level: .notice,
            subsystem: "panel",
            trace: trace,
            fields: [
                "focus_generation": .integer(Int64(focusGeneration)),
                "focus_owner": .string(focusOwner.rawValue),
                "shell_key": .bool(panel.isKeyWindow),
                "source_key": .bool(sourceHostController.window.isKeyWindow),
                "active_slot_id": tabStore.activeTabID.map { .string($0.uuidString) } ?? .null
            ]
        )
        presentationTrace = nil
    }

    private func schedulePresentationFocusSettle() {
        guard presentationFocusTask == nil else { return }
        presentationFocusTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard let self, !Task.isCancelled else { return }
            defer { self.presentationFocusTask = nil }
            guard self.requestedVisibility, NSApp.isActive else { return }

            if PresentationNativeFocusPolicy.shouldRefocusDuringSettle(
                owner: self.presentationWebFocusOwner
            ),
               !self.sourceHostController.window.isKeyWindow {
                self.focusActiveWebViewIfAvailable(makeSourceWindowMain: true)
            }
            self.completePresentationFocusIfReady()
        }
    }

    private func settlePresentationWebFocus(
        generation: UInt64,
        owner: PresentationWebFocusOwner,
        trace: RuntimeDiagnosticTrace?,
        focused: Bool
    ) {
        guard isCurrentPresentationFocusRequest(generation),
              presentationWebFocusOwner == owner else {
            if requestedVisibility {
                diagnostics.record(
                    event: "presentation_focus.stale_generation",
                    level: .notice,
                    subsystem: "panel",
                    trace: trace,
                    fields: [
                        "focus_generation": .integer(Int64(generation)),
                        "replacement_generation": .integer(Int64(presentationFocusGeneration)),
                        "focus_owner": .string(owner.rawValue),
                        "reason": .string("async_result_replaced")
                    ]
                )
            }
            return
        }

        guard focused else {
            if owner == .externalVoice {
                presentationWebFocusPending = false
            }
            var failureFields: [String: RuntimeDiagnosticValue] = [
                "focus_generation": .integer(Int64(generation)),
                "focus_owner": .string(owner.rawValue),
                "reason": .string("dom_input_unavailable")
            ]
            failureFields.merge(presentationFocusFailureDiagnosticFields()) {
                current, _ in current
            }
            diagnostics.record(
                event: "presentation_focus.failed",
                level: .warning,
                subsystem: "panel",
                trace: trace,
                fields: failureFields
            )
            return
        }

        presentationWebFocusPending = false
        diagnostics.record(
            event: "presentation_focus.web.ready",
            level: .info,
            subsystem: "panel",
            trace: trace,
            fields: [
                "focus_generation": .integer(Int64(generation)),
                "focus_owner": .string(owner.rawValue),
                "active_slot_id": tabStore.activeTabID.map { .string($0.uuidString) } ?? .null
            ]
        )
        completePresentationFocusIfReady()
    }

    func presentationFocusFailureDiagnosticFields() -> [String: RuntimeDiagnosticValue] {
        let activeSlotID = tabStore.activeTabID
        var fields: [String: RuntimeDiagnosticValue] = [
            "active_slot_exists": .bool(activeSlotID != nil),
            "active_slot_id": activeSlotID.map { .string($0.uuidString) } ?? .null
        ]

        guard let activeSlotID else {
            fields["resident_runtime_exists"] = .bool(false)
            fields["focus_runtime_availability"] = .string("no_active_slot")
            return fields
        }

        guard webViewPool.existingWebView(for: activeSlotID) != nil else {
            fields["resident_runtime_exists"] = .bool(false)
            fields["focus_runtime_availability"] = .string("no_resident_runtime")
            return fields
        }

        fields["resident_runtime_exists"] = .bool(true)
        fields["focus_runtime_availability"] = .string("resident")
        let runtimeFields = webViewPool.diagnosticSnapshotFields(for: activeSlotID)
        for key in [
            "runtime_generation",
            "webview_instance_id",
            "navigation_generation",
            "navigation_phase"
        ] {
            if let value = runtimeFields[key] {
                fields[key] = value
            }
        }
        return fields
    }

    private func schedulePresentationWebInputFocus(
        afterNanoseconds delay: UInt64 = 0
    ) {
        guard requestedVisibility,
              presentationWebFocusPending,
              presentationWebFocusOwner == .standardPresentation else { return }
        presentationWebFocusTask?.cancel()
        let request = RuntimeDiagnosticPresentationFocusRequest(
            generation: presentationFocusGeneration,
            trace: presentationTrace
        )
        presentationWebFocusTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.presentationFocusGeneration == request.generation {
                    self.presentationWebFocusTask = nil
                }
            }

            if delay > 0 {
                try? await Task.sleep(nanoseconds: delay)
                guard !Task.isCancelled else { return }
            }
            guard self.isCurrentPresentationFocusRequest(request.generation),
                  let webView = self.selectedPresentationWebView(),
                  !webView.isLoading else {
                return
            }

            if self.webFocusRouter.currentWebView !== webView {
                self.webFocusRouter.setCurrentWebView(webView)
            }
            let focused = await self.webFocusRouter.focusInputForPresentation(
                trace: request.trace
            )
            self.settlePresentationWebFocus(
                generation: request.generation,
                owner: .standardPresentation,
                trace: request.trace,
                focused: focused
            )
        }
    }

    @objc private func applicationDidBecomeActive(_ notification: Notification) {
        guard requestedVisibility else { return }
        diagnostics.record(
            event: "app.activation.observed",
            level: .info,
            subsystem: "app",
            trace: presentationTrace,
            fields: ["app_active": .bool(NSApp.isActive)]
        )
        RunLoop.main.perform(inModes: [.default]) { [weak self] in
            Task { @MainActor [weak self] in
                self?.finishFocusAfterApplicationActivation()
            }
        }
    }

    private func finishFocusAfterApplicationActivation() {
        completePresentationFocusIfReady()
    }

    @objc func windowDidBecomeKey(_ notification: Notification) {
        if let window = notification.object as? NSWindow,
           window === panel || window === sourceHostController.window {
            let role = window === panel ? "shell" : "source"
            var fields: [String: RuntimeDiagnosticValue] = [
                "window_role": .string(role),
                "window_number": .integer(Int64(window.windowNumber)),
                "screen_id": .null
            ]
            if let screenID = ScreenPositioning.displayID(for: window.screen) {
                fields["screen_id"] = .integer(Int64(screenID))
            }
            diagnostics.record(
                event: "window.key.observed",
                level: .info,
                subsystem: "app",
                trace: presentationTrace,
                fields: fields
            )
            completePresentationFocusIfReady()
        }
        acknowledgeActiveAttentionIfActuallyPresented()
    }

    private func capturePreviousApplication(trace: RuntimeDiagnosticTrace? = nil) {
        guard let frontmost = NSWorkspace.shared.frontmostApplication else { return }
        guard frontmost.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        let context = PreviousApplicationContext(
            application: frontmost,
            displayID: ScreenPositioning.displayID(for: NSScreen.main),
            windowObservation: observeExternalWindow(for: frontmost)
        )
        previousApplicationContext = context
        var fields: [String: RuntimeDiagnosticValue] = [
            "display_id": .integer(Int64(context.displayID ?? 0)),
            "process_identifier": .integer(Int64(frontmost.processIdentifier))
        ]
        if let bundleIdentifier = RuntimeDiagnosticPrivacy.safeBundleIdentifier(frontmost.bundleIdentifier) {
            fields["application_bundle_id"] = bundleIdentifier
        }
        appendWindowObservationFields(
            context.windowObservation,
            prefix: "window",
            to: &fields
        )
        diagnostics.record(
            event: "previous_app.capture",
            level: .info,
            subsystem: "panel",
            trace: trace,
            fields: fields
        )
    }

    private func appendWindowObservationFields(
        _ observation: RuntimeDiagnosticExternalWindowObservation?,
        prefix: String,
        to fields: inout [String: RuntimeDiagnosticValue]
    ) {
        fields["\(prefix)_observation_quality"] = .string(
            observation?.quality.rawValue
                ?? RuntimeDiagnosticWindowObservationQuality.unavailable.rawValue
        )
        guard let observation else { return }
        fields["\(prefix)_process_identifier"] = .integer(observation.processIdentifier)
        if let windowNumber = observation.windowNumber {
            fields["\(prefix)_number"] = .integer(windowNumber)
        }
        if let displayID = observation.displayID {
            fields["\(prefix)_display_id"] = .integer(displayID)
        }
        if let bounds = observation.bounds {
            fields["\(prefix)_bounds_x"] = .double(bounds.x)
            fields["\(prefix)_bounds_y"] = .double(bounds.y)
            fields["\(prefix)_bounds_width"] = .double(bounds.width)
            fields["\(prefix)_bounds_height"] = .double(bounds.height)
        }
    }

    private func observeExternalWindow(
        for application: NSRunningApplication
    ) -> RuntimeDiagnosticExternalWindowObservation? {
        guard let rawWindowInfo = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return nil
        }

        for info in rawWindowInfo {
            guard let ownerPID = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int64Value,
                  ownerPID == Int64(application.processIdentifier),
                  let windowNumber = (info[kCGWindowNumber as String] as? NSNumber)?.int64Value else {
                continue
            }
            let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
            guard layer == 0 else { continue }
            let isOnscreen = (info[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? true
            guard isOnscreen else { continue }

            var cgBounds = CGRect.zero
            let bounds = (info[kCGWindowBounds as String] as? NSDictionary).flatMap {
                CGRectMakeWithDictionaryRepresentation($0 as CFDictionary, &cgBounds)
                    ? RuntimeDiagnosticWindowBounds(
                        x: Double(cgBounds.origin.x),
                        y: Double(cgBounds.origin.y),
                        width: Double(cgBounds.size.width),
                        height: Double(cgBounds.size.height)
                    )
                    : nil
            }
            return RuntimeDiagnosticExternalWindowObservation(
                processIdentifier: ownerPID,
                windowNumber: windowNumber,
                displayID: bounds.flatMap { displayIDForWindowBounds($0) },
                bounds: bounds,
                quality: .frontmostCandidate
            )
        }
        return nil
    }

    private func displayIDForWindowBounds(
        _ bounds: RuntimeDiagnosticWindowBounds
    ) -> Int64? {
        var displayCount: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &displayCount) == .success,
              displayCount > 0 else {
            return nil
        }
        var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        guard CGGetActiveDisplayList(displayCount, &displayIDs, &displayCount) == .success else {
            return nil
        }

        let windowRect = CGRect(
            x: bounds.x,
            y: bounds.y,
            width: bounds.width,
            height: bounds.height
        )
        let bestDisplay = displayIDs
            .compactMap { displayID -> (CGDirectDisplayID, CGFloat)? in
                let intersection = windowRect.intersection(CGDisplayBounds(displayID))
                guard !intersection.isNull else { return nil }
                return (displayID, intersection.width * intersection.height)
            }
            .max(by: { lhs, rhs in lhs.1 < rhs.1 })
        return bestDisplay.map { Int64($0.0) }
    }

    private func scheduleRestoreObservation(
        _ ticket: RuntimeDiagnosticRestoreObservationTicket,
        attempt: Int = 1
    ) {
        guard restoreObservationTracker.accepts(ticket) else { return }
        RunLoop.main.perform(inModes: [.default]) { [weak self] in
            Task { @MainActor [weak self] in
                self?.observePendingRestore(ticket: ticket, attempt: attempt)
            }
        }
    }

    private func observePendingRestore(
        ticket: RuntimeDiagnosticRestoreObservationTicket,
        attempt: Int
    ) {
        guard restoreObservationTracker.accepts(ticket),
              let pendingObservation = pendingRestoreObservation,
              pendingObservation.ticket == ticket else {
            return
        }

        var pending = pendingObservation
        pending.observationAttemptCount = max(pending.observationAttemptCount, attempt)
        pendingRestoreObservation = pending

        let observedApplication = NSWorkspace.shared.frontmostApplication
        let observedWindow = observedApplication.flatMap {
            observeExternalWindow(for: $0)
        }
        let applicationMatch = observedApplication?.processIdentifier
            == pending.application.processIdentifier
        if attempt == 1 && (!applicationMatch || observedWindow == nil) {
            scheduleRestoreObservation(ticket, attempt: 2)
            return
        }

        guard restoreObservationTracker.consume(ticket) != nil else { return }
        pendingRestoreObservation = nil

        let windowMatch = RuntimeDiagnosticExternalWindowObservation.windowMatch(
            applicationMatches: applicationMatch,
            capturedWindowNumber: pending.capturedWindowObservation?.windowNumber,
            observedWindowNumber: observedWindow?.windowNumber
        )
        let terminalOutcome: String
        if !applicationMatch {
            terminalOutcome = "application_not_frontmost"
        } else if observedWindow == nil {
            terminalOutcome = "window_unavailable"
        } else if windowMatch == .mismatched {
            terminalOutcome = "window_mismatch"
        } else {
            terminalOutcome = "restored"
        }
        var fields: [String: RuntimeDiagnosticValue] = [
            "observation_state": .string("observed"),
            "terminal_outcome": .string(terminalOutcome),
            "observation_attempt": .integer(Int64(attempt)),
            "requested_application_process_identifier": .integer(
                Int64(pending.application.processIdentifier)
            ),
            "restore_request_accepted": pending.requestAccepted.map(RuntimeDiagnosticValue.bool)
                ?? .null,
            "application_match": .bool(applicationMatch),
            "window_match": .string(windowMatch.rawValue),
            "elapsed_uptime": .double(
                max(0, ProcessInfo.processInfo.systemUptime - pending.requestedAtUptime)
            )
        ]
        if let bundleIdentifier = RuntimeDiagnosticPrivacy.safeBundleIdentifier(
            pending.application.bundleIdentifier
        ) {
            fields["requested_application_bundle_id"] = bundleIdentifier
            fields["captured_application_bundle_id"] = bundleIdentifier
        }
        if let observedApplication {
            fields["observed_frontmost_process_identifier"] = .integer(
                Int64(observedApplication.processIdentifier)
            )
            if let bundleIdentifier = RuntimeDiagnosticPrivacy.safeBundleIdentifier(
                observedApplication.bundleIdentifier
            ) {
                fields["observed_frontmost_application_bundle_id"] = bundleIdentifier
            }
        }
        appendWindowObservationFields(
            pending.capturedWindowObservation,
            prefix: "captured_window",
            to: &fields
        )
        appendWindowObservationFields(
            observedWindow,
            prefix: "observed_window",
            to: &fields
        )
        diagnostics.record(
            event: "previous_app.restore.observed",
            level: .notice,
            subsystem: "panel",
            trace: ticket.trace,
            fields: fields
        )
        var terminalFields = fields
        terminalFields["observation_state"] = .string("terminal")
        diagnostics.record(
            event: "previous_app.restore.terminal",
            level: terminalOutcome == "restored" ? .notice : .warning,
            subsystem: "panel",
            trace: ticket.trace,
            fields: terminalFields
        )
    }

    private func positionPanelForCurrentScreens(
        trace: RuntimeDiagnosticTrace? = nil,
        reason: ScreenPlacementReason
    ) {
        let screens = NSScreen.screens
        guard let targetScreen = ScreenPositioning.targetScreen(screens: screens) else { return }
        let targetVisibleFrame: NSRect
#if DEBUG
        if reason == .explicitSummon, let debugTargetVisibleFrameOverride {
            targetVisibleFrame = debugTargetVisibleFrameOverride
        } else {
            targetVisibleFrame = targetScreen.visibleFrame
        }
#else
        targetVisibleFrame = targetScreen.visibleFrame
#endif

        var targetFields: [String: RuntimeDiagnosticValue] = [
            "screen_count": .integer(Int64(screens.count)),
            "screen_id": .null
        ]
        if let screenID = ScreenPositioning.displayID(for: targetScreen) {
            targetFields["screen_id"] = .integer(Int64(screenID))
        }
        diagnostics.record(
            event: "screen.target.resolved",
            level: .info,
            subsystem: "panel",
            trace: trace,
            fields: targetFields
        )

        refreshPreferredPanelSizeFromModel()

        let targetFrame: NSRect

        if let startingFrame = hasPositionedPanel ? panel.frame : restoredFrame {
            let frame = frameWithPreferredSize(startingFrame)
            if reason == .explicitSummon {
                targetFrame = ScreenPositioning.frameForExplicitSummon(
                    frame,
                    on: targetVisibleFrame
                )
            } else {
                targetFrame = ScreenPositioning.relocatedFrame(
                    frame,
                    visibleFrames: screens.map(\.visibleFrame),
                    fallbackVisibleFrame: targetVisibleFrame
                )
            }
        } else {
            targetFrame = ScreenPositioning.centeredFrame(
                size: PanelMetrics.defaultPanelSize,
                in: targetVisibleFrame
            )
        }

        panel.setFrame(targetFrame, display: false)
        synchronizeSourceHostFrame(display: false)
        restoredFrame = nil
        hasPositionedPanel = true
    }

    private func clampPanelToConnectedScreens(preservingPreferredSize: Bool = true) {
        let screens = NSScreen.screens
        guard let fallbackScreen = ScreenPositioning.targetScreen(screens: screens) else { return }

        refreshPreferredPanelSizeFromModel()
        let clamped: NSRect
        if preservingPreferredSize {
            clamped = ScreenPositioning.relocatedFrame(
                frameWithPreferredSize(panel.frame),
                visibleFrames: screens.map(\.visibleFrame),
                fallbackVisibleFrame: fallbackScreen.visibleFrame
            )
        } else {
            clamped = ScreenPositioning.restoredFrame(
                panel.frame,
                visibleFrames: screens.map(\.visibleFrame),
                fallbackVisibleFrame: fallbackScreen.visibleFrame
            )
        }

        if clamped != panel.frame {
            panel.setFrame(clamped, display: true)
            synchronizeSourceHostFrame(display: true)
        }
    }

    @objc private func screenParametersDidChange(_ notification: Notification) {
        guard !sourceHostController.isSessionLocked else {
            shouldClampAfterFullscreen = true
            return
        }
        clampPanelToConnectedScreens()
    }

    private func persistPanelFrame() {
        guard hasPositionedPanel else { return }
        frameStore.saveFrame(frameWithPreferredSize(panel.frame))
    }

    private func frameWithPreferredSize(_ frame: NSRect) -> NSRect {
        guard let preferredPanelSize else { return frame }
        var result = frame
        result.size = PanelMetrics.clampedPanelSize(preferredPanelSize)
        return result
    }

    private func refreshPreferredPanelSizeFromModel() {
        switch preferencesStore.windowSizeMode {
        case .fixed:
            guard preferencesStore.hasStoredFixedViewportSize else { return }
            preferredPanelSize = PanelMetrics.panelSize(
                forViewport: NSSize(
                    width: preferencesStore.fixedViewportSize.width,
                    height: preferencesStore.fixedViewportSize.height
                )
            )
        case .perWebApp:
            guard let activeProfile = tabStore.activeProfile else { return }
            preferredPanelSize = PanelMetrics.panelSize(
                forViewport: NSSize(
                    width: activeProfile.renderingProfile.viewportSize.width,
                    height: activeProfile.renderingProfile.viewportSize.height
                )
            )
        }
    }

    func windowDidMove(_ notification: Notification) {
        if requestedVisibility {
            presentationDisplayMovement.observe(
                displayID: ScreenPositioning.displayID(forWindowFrame: panel.frame)
            )
        }
        synchronizeSourceHostFrame(display: false)
    }

    func windowWillClose(_ notification: Notification) {
        guard notification.object as? NSWindow === panel else { return }
        endRailModalInteraction()
    }

    func windowDidResize(_ notification: Notification) {
        synchronizeSourceHostFrame(display: true)
    }

    private func synchronizeSourceHostFrame(display: Bool, animated: Bool = false) {
        sourceHostController.synchronizeFrame(with: panel, display: display, animated: animated)
    }

    private func handleSourceSessionLockChange(isLocked: Bool) {
        rootView.externalControlZoneView.setBrowserProfileAssignmentEnabled(!isLocked)
        rootView.externalControlZoneView.setBrowserProfileDuplicationEnabled(!isLocked)
        if isLocked {
            let fullscreenDismissTrace: RuntimeDiagnosticTrace? =
                requestedVisibility && !isPinned
                    ? diagnostics.beginTrace(root: "panel.dismiss")
                    : nil
            if let fullscreenDismissTrace {
                recordDismissBegin(
                    trace: fullscreenDismissTrace,
                    source: .fullscreen,
                    wasVisible: true,
                    reason: "fullscreen"
                )
            }
            fullscreenVisibilityIntent.begin(wasVisible: requestedVisibility)
            fullscreenProfile = lastSynchronizedActiveProfile ?? tabStore.activeProfile
            if let fullscreenProfile {
                slotLifecycleCoordinator.beginFullscreenSourceVisibility(
                    profile: fullscreenProfile
                )
                acknowledgeAttentionIfActuallyVisible(slotID: fullscreenProfile.id)
            }
            companionActiveProfile = nil
            pendingSlotSynchronization = false
            addressOverlayView.dismiss()
            synchronizeTransientUIHost()
            panel.orderOut(nil)
            rootView.removeFullscreenCompanionContainer(
                sourceHostController.companionContainer
            )
            rootView.removeFullscreenExitPlaceholder()
            updateRequestedVisibility(isPinned)
            if let fullscreenDismissTrace {
                recordDismissCompleted(
                    trace: fullscreenDismissTrace,
                    wasVisible: true,
                    source: .fullscreen
                )
            }
            return
        }

        if let fullscreenProfile {
            slotLifecycleCoordinator.endFullscreenSourceVisibility(
                profile: fullscreenProfile
            )
        }

        synchronizeTransientUIHost()
        synchronizePinnedPresentation()

        updateRequestedVisibility(
            fullscreenVisibilityIntent.consumeRestore(
                currentVisibility: requestedVisibility
            )
        )
        let shouldKeepShellVisible = requestedVisibility
        let shouldPauseCompanion = !shouldKeepShellVisible
        if shouldKeepShellVisible {
            panel.orderOut(nil)
        }
        tearDownFullscreenCompanion(
            pauseInactiveMedia: shouldPauseCompanion,
            hidePanel: !shouldKeepShellVisible
        )
        fullscreenProfile = nil
        panel.setFullscreenCompanionPresentation(false)
        pendingSlotSynchronization = true

        if shouldClampAfterFullscreen {
            shouldClampAfterFullscreen = false
            clampPanelToConnectedScreens()
        }

        if pendingSlotSynchronization {
            synchronizeSlotState()
        }

        guard requestedVisibility else {
            sourceHostController.orderOutIfSafe()
            slotLifecycleCoordinator.setPanelVisible(
                false,
                activeProfile: tabStore.activeProfile
            )
            return
        }

        synchronizeSourceHostFrame(display: false)
        slotLifecycleCoordinator.setPanelVisible(true, activeProfile: tabStore.activeProfile)
        synchronizeSlotState()
        let restoreUptime = ProcessInfo.processInfo.systemUptime
        lastPresentationUptime = restoreUptime
        workspaceAutoHideSuppression.arm(atUptime: restoreUptime)
        panel.makeKeyAndOrderFront(nil)
        focusActiveWebViewIfAvailable()
        acknowledgeActiveAttentionIfActuallyPresented()
        fullscreenExperimentLog(
            "RESTORE_PRESENTED shell=\(panel.windowNumber) "
                + "source=\(sourceHostController.window.windowNumber) "
                + "shellScreen=\(fullscreenExperimentScreenID(panel.screen)) "
                + "sourceScreen=\(fullscreenExperimentScreenID(sourceHostController.window.screen)) "
                + "shellVisible=\(panel.isVisible) "
                + "sourceVisible=\(sourceHostController.window.isVisible)"
        )
    }

    private func rebuildFullscreenSourceAfterRestoreTimeout() {
        guard let sourceID = fullscreenProfile?.id else { return }
        slotLifecycleCoordinator.remove(slotID: sourceID)
        webViewPool.release(slotID: sourceID)
        if lastSynchronizedActiveID == sourceID {
            lastSynchronizedActiveID = nil
            lastSynchronizedActiveProfile = nil
        }
        pendingSlotSynchronization = true
    }

    private func handleSourceSessionStateChange(_ state: FullscreenSourceSessionState) {
        fullscreenExperimentLog(
            "SESSION state=\(state.rawValue) requested=\(requestedVisibility) "
                + "shellVisible=\(panel.isVisible) "
                + "shellScreen=\(fullscreenExperimentScreenID(panel.screen))"
        )
        switch state {
        case .fullscreen:
            showFullscreenCompanionIfReady()
        case .exiting, .restoring:
            if !requestedVisibility {
                panel.orderOut(nil)
            }
        case .idle, .entering:
            break
        }
    }

    private func showFullscreenCompanionIfReady() {
        guard requestedVisibility,
              sourceHostController.sessionState == .fullscreen else {
            return
        }

        invalidatePendingRestoreObservationForNewPresentation()
        capturePreviousApplication()
        panel.orderOut(nil)
        rootView.removeFullscreenCompanionContainer(
            sourceHostController.companionContainer
        )
        positionPanelForCurrentScreens(reason: .fullscreenCompanion)
        panel.setFullscreenCompanionPresentation(true)
        rootView.companionRailFoldControlView.isHidden = false
        synchronizeFullscreenCompanionSlotState()
        panel.orderFrontRegardless()
        activateFloatTabs()
        panel.makeKeyAndOrderFront(nil)

        if let companionSlotID = tabStore.activeTabID,
           runtimeReadinessState(for: companionSlotID) == .ready,
           let webView = exactReadyWebView(for: companionSlotID),
           sourceHostController.companionContainer.currentWebView === webView,
           !sourceHostController.companionContainer.isShowingRestoringState {
            WebViewFocus.focus(webView, in: panel)
        }
        if let companionSlotID = companionActiveProfile?.id {
            acknowledgeAttentionIfActuallyVisible(slotID: companionSlotID)
        }
    }

    private func synchronizeFullscreenCompanionSlotState() {
        let orderedProfiles = tabStore.orderedProfiles
        rootView.externalControlZoneView.apply(
            profiles: orderedProfiles,
            activeTabID: tabStore.activeTabID
        )
        synchronizeDurableUnreadPresentation()
        synchronizeResidentIndicators()

        guard let activeProfile = tabStore.activeProfile else {
            deactivateCompanionProfile(pauseInactiveMedia: true)
            webFocusRouter.setCurrentWebView(nil)
            sourceHostController.companionContainer.showEmptyState()
            rootView.removeFullscreenCompanionContainer(
                sourceHostController.companionContainer
            )
            rootView.removeFullscreenExitPlaceholder()
            onSelectedSlotPresentationChange?(nil, nil)
            return
        }

        onSelectedSlotPresentationChange?(
            activeProfile.name,
            faviconURL(for: activeProfile)
        )

        guard activeProfile.id != fullscreenProfile?.id else {
            deactivateCompanionProfile(pauseInactiveMedia: true)
            webFocusRouter.setCurrentWebView(nil)
            sourceHostController.companionContainer.showEmptyState()
            rootView.removeFullscreenCompanionContainer(
                sourceHostController.companionContainer
            )
            rootView.installFullscreenExitPlaceholder()
            return
        }

        let activeChanged = companionActiveProfile?.id != activeProfile.id
        if activeChanged {
            deactivateCompanionProfile(pauseInactiveMedia: true)
            if preferencesStore.followPreferredSize {
                applyPreferredViewport(activeProfile.renderingProfile.viewportSize)
            }
        }

        if runtimeReadinessState(for: activeProfile.id) == .failed {
            webFocusRouter.setCurrentWebView(nil)
            rootView.installFullscreenCompanionContainer(
                sourceHostController.companionContainer
            )
            sourceHostController.companionContainer.showLoadFailure(
                retryEnabled: canRetrySelectedSlot(activeProfile)
            )
            companionActiveProfile = nil
            synchronizeResidentIndicators()
            return
        }

        if runtimeReadinessState(for: activeProfile.id) == .ready,
           webViewPool.requiresWebViewRebuild(for: activeProfile) {
            // Pool replacement is synchronous. Establish the companion's
            // native restoring owner and revoke Web focus before asking the
            // Pool to materialize a Runtime for the latest rendering profile.
            beginDeferredRuntimeMaterialization(
                for: activeProfile,
                surface: .fullscreenCompanion
            )
            return
        }

        if runtimeReadinessState(for: activeProfile.id) != .ready {
            beginDeferredRuntimeMaterialization(
                for: activeProfile,
                surface: .fullscreenCompanion
            )
            return
        }

        let webView: WKWebView
        do {
            webView = try webViewForPanelController(activeProfile)
        } catch {
            webFocusRouter.setCurrentWebView(nil)
            if let profileName = Self.unsupportedBrowserProfileName(
                for: activeProfile,
                error: error,
                browserProfiles: tabStore.browserProfiles
            ) {
                rootView.installFullscreenCompanionContainer(
                    sourceHostController.companionContainer
                )
                sourceHostController.companionContainer.showUnsupportedBrowserProfile(
                    profileName: profileName,
                    defaultProfileName: tabStore.defaultBrowserProfilePresentation.name
                )
            } else {
                rootView.installFullscreenCompanionContainer(
                    sourceHostController.companionContainer
                )
                sourceHostController.companionContainer.showLoadFailure(
                    retryEnabled: canRetrySelectedSlot(activeProfile)
                )
            }
            companionActiveProfile = nil
            synchronizeResidentIndicators()
            return
        }
        guard runtimeReadinessState(for: activeProfile.id) == .ready else {
            beginDeferredRuntimeMaterialization(
                for: activeProfile,
                surface: .fullscreenCompanion
            )
            return
        }
        rootView.installFullscreenCompanionContainer(
            sourceHostController.companionContainer
        )
        sourceHostController.companionContainer.show(
            webView: webView,
            slotID: activeProfile.id,
            residencyPolicy: activeProfile.residencyPolicy
        )
        sourceHostController.companionContainer.hideRestoringState()
        webFocusRouter.setCurrentWebView(webView)
        slotLifecycleCoordinator.beginSupplementalVisibility(profile: activeProfile)
        WebViewFactory.configureHiddenScrollers(in: webView)
        companionActiveProfile = activeProfile
        guard requestedVisibility,
              sourceHostController.sessionState == .fullscreen else { return }
        WebViewFocus.focus(webView, in: panel)
        acknowledgeAttentionIfActuallyVisible(slotID: activeProfile.id)
    }

    private func hideFullscreenCompanion(pauseInactiveMedia: Bool) {
        panel.orderOut(nil)
        if pauseInactiveMedia,
           let profile = companionActiveProfile,
           profile.backgroundMediaPolicy == .pauseWhenInactive {
            webViewPool.pauseMediaPlayback(slotID: profile.id)
        }
    }

    private func tearDownFullscreenCompanion(
        pauseInactiveMedia: Bool,
        hidePanel: Bool
    ) {
        rootView.companionRailFoldControlView.isHidden = true
        if hidePanel {
            hideFullscreenCompanion(pauseInactiveMedia: pauseInactiveMedia)
        }
        deactivateCompanionProfile(pauseInactiveMedia: pauseInactiveMedia)
        sourceHostController.companionContainer.showEmptyState()
        rootView.removeFullscreenCompanionContainer(
            sourceHostController.companionContainer
        )
        rootView.removeFullscreenExitPlaceholder()
    }

    private func deactivateCompanionProfile(pauseInactiveMedia: Bool) {
        guard let profile = companionActiveProfile else { return }
        if pauseInactiveMedia,
           profile.backgroundMediaPolicy == .pauseWhenInactive {
            webViewPool.pauseMediaPlayback(slotID: profile.id)
        }
        sourceHostController.companionContainer.deactivate(
            slotID: profile.id,
            residencyPolicy: profile.residencyPolicy
        )
        slotLifecycleCoordinator.endSupplementalVisibility(
            profile: profile,
            prepareAsInactive: pauseInactiveMedia
        )
        companionActiveProfile = nil
    }
}

@MainActor
final class AddressOverlayView: NSVisualEffectView, NSTextFieldDelegate {
    var onCommit: ((String) -> Bool)?
    var onCopy: ((String) -> Bool)?
    var onSetHome: (() -> Bool)?
    var onCreateWebApp: (() -> Void)?
    var onDismiss: (() -> Void)?

    let field = NSTextField()
    private let copyButton = NSButton()
    private let setHomeButton = NSButton(title: "Set Home", target: nil, action: nil)
    private let createButton = NSButton(title: "New App", target: nil, action: nil)
    private var copyFeedbackWorkItem: DispatchWorkItem?
    private(set) var isPresented = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.masksToBounds = true

        field.translatesAutoresizingMaskIntoConstraints = false
        field.font = .systemFont(ofSize: 14, weight: .medium)
        field.placeholderString = "https://example.com"
        field.focusRingType = .none
        field.delegate = self

        copyButton.image = NSImage(
            systemSymbolName: "doc.on.doc",
            accessibilityDescription: "Copy URL"
        )
        copyButton.toolTip = "Copy URL"
        copyButton.bezelStyle = .inline
        copyButton.isBordered = false
        copyButton.translatesAutoresizingMaskIntoConstraints = false
        copyButton.target = self
        copyButton.action = #selector(copyPressed(_:))

        setHomeButton.toolTip = "Set the current page as this Tab's Home"
        setHomeButton.bezelStyle = .rounded
        setHomeButton.controlSize = .small
        setHomeButton.translatesAutoresizingMaskIntoConstraints = false
        setHomeButton.target = self
        setHomeButton.action = #selector(setHomePressed(_:))

        createButton.toolTip = "Create a new Web App from the current page"
        createButton.bezelStyle = .rounded
        createButton.controlSize = .small
        createButton.translatesAutoresizingMaskIntoConstraints = false
        createButton.target = self
        createButton.action = #selector(createPressed(_:))

        addSubview(field)
        addSubview(copyButton)
        addSubview(setHomeButton)
        addSubview(createButton)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            field.centerYAnchor.constraint(equalTo: centerYAnchor),

            copyButton.leadingAnchor.constraint(equalTo: field.trailingAnchor, constant: 8),
            copyButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            copyButton.widthAnchor.constraint(equalToConstant: 26),
            copyButton.heightAnchor.constraint(equalToConstant: 26),

            setHomeButton.leadingAnchor.constraint(equalTo: copyButton.trailingAnchor, constant: 6),
            setHomeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            setHomeButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 70),

            createButton.leadingAnchor.constraint(equalTo: setHomeButton.trailingAnchor, constant: 6),
            createButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            createButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            createButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 66),
        ])

        isHidden = true
    }

    convenience init() {
        self.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present(url: URL, in window: NSWindow) {
        copyFeedbackWorkItem?.cancel()
        restoreCopyIcon()
        field.textColor = .labelColor
        field.stringValue = url.absoluteString
        isHidden = false
        isPresented = true
        window.makeFirstResponder(field)
        field.selectText(nil)
    }

    func dismiss() {
        copyFeedbackWorkItem?.cancel()
        restoreCopyIcon()
        isHidden = true
        isPresented = false
        field.textColor = .labelColor
    }

    func markInvalid() {
        field.textColor = .systemRed
        field.selectText(nil)
    }

    func control(
        _ control: NSControl,
        textView: NSTextView,
        doCommandBy commandSelector: Selector
    ) -> Bool {
        let commandName = NSStringFromSelector(commandSelector)
        if commandSelector == #selector(NSResponder.insertNewline(_:))
            || commandName == "insertNewlineIgnoringFieldEditor:" {
            _ = onCommit?(field.stringValue)
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            dismiss()
            onDismiss?()
            return true
        }
        return false
    }

    @objc private func copyPressed(_ sender: NSButton) {
        guard onCopy?(field.stringValue) == true else { return }
        copyFeedbackWorkItem?.cancel()
        copyButton.image = NSImage(
            systemSymbolName: "checkmark",
            accessibilityDescription: "Copied"
        )
        let workItem = DispatchWorkItem { [weak self] in
            self?.restoreCopyIcon()
        }
        copyFeedbackWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: workItem)
    }

    @objc private func setHomePressed(_ sender: NSButton) {
        _ = onSetHome?()
    }

    @objc private func createPressed(_ sender: NSButton) {
        onCreateWebApp?()
    }

    private func restoreCopyIcon() {
        copyButton.image = NSImage(
            systemSymbolName: "doc.on.doc",
            accessibilityDescription: "Copy URL"
        )
    }
}

@MainActor
final class StatusHUDView: NSView {
    private let label = NSTextField(labelWithString: "100%")
    private var hideWorkItem: DispatchWorkItem?

    var displayedText: String { label.stringValue }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 9
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.72).cgColor

        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        label.textColor = .white
        label.alignment = .center
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        isHidden = true
    }

    convenience init() {
        self.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func show(zoom: CGFloat) {
        show(message: ZoomSteps.percentageText(for: zoom))
    }

    func show(residency: SlotResidencyPolicy) {
        show(message: "Mode: \(residency.displayName)")
    }

    func show(message: String) {
        hideWorkItem?.cancel()
        label.stringValue = message
        isHidden = false

        let item = DispatchWorkItem { [weak self] in
            self?.isHidden = true
        }
        hideWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.85, execute: item)
    }
}
