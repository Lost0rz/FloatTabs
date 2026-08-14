import Dispatch
import Foundation
import WebKit

private func floatTabsRuntimeDiagnostic(_ message: String) {
    NSLog("[FloatTabsRuntimeDiag] %@", message)
}

private func floatTabsDiagnosticSlotID(_ id: UUID?) -> String {
    guard let id else { return "nil" }
    return String(id.uuidString.prefix(8))
}

private func floatTabsDiagnosticWebViewID(_ webView: WKWebView?) -> String {
    guard let webView else { return "nil" }
    return String(describing: ObjectIdentifier(webView))
}

private func floatTabsDiagnosticSuperview(_ webView: WKWebView?) -> String {
    guard let superview = webView?.superview else { return "nil" }
    return String(describing: type(of: superview))
}

enum SlotMemoryPressureLevel {
    case warning
    case critical
}

@MainActor
final class SlotLifecycleCoordinator {
    nonisolated static let defaultColdReleaseDelay: TimeInterval = 30
    nonisolated static let defaultWarmReleaseDelay: TimeInterval = 120
    nonisolated static let defaultHiddenActiveGraceDelay: TimeInterval = 120
    nonisolated static let defaultMediaProtectionPollDelay: TimeInterval = 10
    nonisolated static let defaultWarmResidentLimit = 2

    typealias MediaPlayingQuery = (UUID, @escaping (Bool) -> Void) -> Void
    typealias MediaPauseAction = (UUID) -> Void

    private struct InactivePlan {
        let token: UUID
        let residencyPolicy: SlotResidencyPolicy
        let backgroundMediaPolicy: BackgroundMediaPolicy
    }

    private let webViewPool: WebViewPool
    private unowned let container: WebPanelContainerView
    private let coldReleaseDelay: TimeInterval
    private let warmReleaseDelay: TimeInterval
    private let hiddenActiveGraceDelay: TimeInterval
    private let mediaProtectionPollDelay: TimeInterval
    private let warmResidentLimit: Int
    private let mediaPlayingQuery: MediaPlayingQuery
    private let mediaPauseAction: MediaPauseAction

    private var inactivePlans: [UUID: InactivePlan] = [:]
    private var mediaProtectedSlotIDs = Set<UUID>()
    private var inactiveWarmRecency: [UUID: UInt64] = [:]
    private var warmRecencyCounter: UInt64 = 0
    private var hiddenActiveToken: UUID?
    private var activeSlotID: UUID?
    private var fullscreenSourceProfile: WebAppProfile?
    private var supplementalVisibleProfile: WebAppProfile?
    private var panelIsVisible = false
    private var memoryPressureSource: DispatchSourceMemoryPressure?

    init(
        webViewPool: WebViewPool,
        container: WebPanelContainerView,
        coldReleaseDelay: TimeInterval = SlotLifecycleCoordinator.defaultColdReleaseDelay,
        warmReleaseDelay: TimeInterval = SlotLifecycleCoordinator.defaultWarmReleaseDelay,
        hiddenActiveGraceDelay: TimeInterval = SlotLifecycleCoordinator.defaultHiddenActiveGraceDelay,
        mediaProtectionPollDelay: TimeInterval = SlotLifecycleCoordinator.defaultMediaProtectionPollDelay,
        warmResidentLimit: Int = SlotLifecycleCoordinator.defaultWarmResidentLimit,
        mediaPlayingQuery: MediaPlayingQuery? = nil,
        mediaPauseAction: MediaPauseAction? = nil,
        installsMemoryPressureSource: Bool = true
    ) {
        self.webViewPool = webViewPool
        self.container = container
        self.coldReleaseDelay = max(coldReleaseDelay, 0)
        self.warmReleaseDelay = max(warmReleaseDelay, 0)
        self.hiddenActiveGraceDelay = max(hiddenActiveGraceDelay, 0)
        self.mediaProtectionPollDelay = max(mediaProtectionPollDelay, 0.01)
        self.warmResidentLimit = max(warmResidentLimit, 0)
        self.mediaPlayingQuery = mediaPlayingQuery ?? { [weak webViewPool] slotID, completion in
            guard let webViewPool else {
                completion(false)
                return
            }
            webViewPool.isMediaPlaying(slotID: slotID, completion: completion)
        }
        self.mediaPauseAction = mediaPauseAction ?? { [weak webViewPool] slotID in
            webViewPool?.pauseMediaPlayback(slotID: slotID)
        }

        floatTabsRuntimeDiagnostic(
            "LIFECYCLE_INIT cold=\(self.coldReleaseDelay) warm=\(self.warmReleaseDelay) hidden=\(self.hiddenActiveGraceDelay) mediaPoll=\(self.mediaProtectionPollDelay) warmLimit=\(self.warmResidentLimit)"
        )

        if installsMemoryPressureSource {
            configureMemoryPressureSource()
        }
    }

    func reconcile(profiles: [WebAppProfile]) {
        let validIDs = Set(profiles.map(\.id))
        let hotIDs = Set(profiles.filter { $0.residencyPolicy == .hot }.map(\.id))

        if let activeSlotID, !validIDs.contains(activeSlotID) {
            self.activeSlotID = nil
        }

        container.retainHotSlots(hotIDs)

        for slotID in Array(inactivePlans.keys) where
            !validIDs.contains(slotID) || !webViewPool.contains(slotID: slotID) {
            cancelInactivePlan(slotID: slotID)
        }

        for profile in profiles {
            if isVisibleSlot(profile.id) {
                cancelInactivePlan(slotID: profile.id)
                continue
            }
            guard webViewPool.contains(slotID: profile.id) else {
                cancelInactivePlan(slotID: profile.id)
                continue
            }

            if profile.backgroundMediaPolicy == .pauseWhenInactive {
                mediaPauseAction(profile.id)
            }

            switch profile.residencyPolicy {
            case .hot:
                cancelInactivePlan(slotID: profile.id)
            case .warm, .cold:
                ensureInactivePlan(for: profile, resetWarmRecency: false)
            }
        }

        enforceWarmResidentLimit()
    }

    func setPanelVisible(_ visible: Bool, activeProfile: WebAppProfile?) {
        floatTabsRuntimeDiagnostic(
            "PANEL_VISIBLE value=\(visible) slot=\(floatTabsDiagnosticSlotID(activeProfile?.id)) active=\(floatTabsDiagnosticSlotID(activeSlotID)) fullscreen=\(floatTabsDiagnosticSlotID(fullscreenSourceProfile?.id))"
        )
        panelIsVisible = visible
        hiddenActiveToken = nil

        guard let activeProfile else { return }
        if visible {
            activeSlotID = activeProfile.id
            cancelInactivePlan(slotID: activeProfile.id)
        } else if activeSlotID == activeProfile.id {
            // Element fullscreen remains foreground content even when the
            // FloatTabs shell is hidden. Never pause it or start the hidden
            // active eviction chain while WebKit owns the fullscreen source.
            guard fullscreenSourceProfile?.id != activeProfile.id else {
                floatTabsRuntimeDiagnostic(
                    "PANEL_HIDE_PROTECTED_FULLSCREEN slot=\(floatTabsDiagnosticSlotID(activeProfile.id))"
                )
                return
            }
            if activeProfile.backgroundMediaPolicy == .pauseWhenInactive {
                mediaPauseAction(activeProfile.id)
            }
            scheduleHiddenActiveTransition(profile: activeProfile)
        }
    }

    func activate(profile: WebAppProfile) {
        floatTabsRuntimeDiagnostic(
            "ACTIVATE slot=\(floatTabsDiagnosticSlotID(profile.id)) policy=\(profile.residencyPolicy.rawValue) panelVisible=\(panelIsVisible) previousActive=\(floatTabsDiagnosticSlotID(activeSlotID)) web=\(floatTabsDiagnosticWebViewID(webViewPool.existingWebView(for: profile.id))) super=\(floatTabsDiagnosticSuperview(webViewPool.existingWebView(for: profile.id)))"
        )
        activeSlotID = profile.id
        cancelInactivePlan(slotID: profile.id)
        hiddenActiveToken = nil

        if !panelIsVisible {
            scheduleHiddenActiveTransition(profile: profile)
        }
    }

    func deactivate(profile: WebAppProfile) {
        guard fullscreenSourceProfile?.id != profile.id else {
            floatTabsRuntimeDiagnostic(
                "DEACTIVATE_SKIPPED_FULLSCREEN slot=\(floatTabsDiagnosticSlotID(profile.id))"
            )
            return
        }
        let targetWebView = webViewPool.existingWebView(for: profile.id)
        let currentWebView = container.currentWebView
        floatTabsRuntimeDiagnostic(
            "DEACTIVATE slot=\(floatTabsDiagnosticSlotID(profile.id)) policy=\(profile.residencyPolicy.rawValue) active=\(floatTabsDiagnosticSlotID(activeSlotID)) targetWeb=\(floatTabsDiagnosticWebViewID(targetWebView)) currentWeb=\(floatTabsDiagnosticWebViewID(currentWebView)) same=\(targetWebView === currentWebView) targetSuper=\(floatTabsDiagnosticSuperview(targetWebView)) currentSuper=\(floatTabsDiagnosticSuperview(currentWebView))"
        )
        if activeSlotID == profile.id {
            activeSlotID = nil
        }
        hiddenActiveToken = nil
        container.deactivate(slotID: profile.id, residencyPolicy: profile.residencyPolicy)
        prepareInactive(profile: profile, resetWarmRecency: true)
    }

    /// Explicitly protects the WebView WebKit is presenting in element
    /// fullscreen. This is independent from shell visibility and active Tab
    /// selection so a hidden shell can never pause or evict visible content.
    func beginFullscreenSourceVisibility(profile: WebAppProfile) {
        floatTabsRuntimeDiagnostic(
            "FULLSCREEN_BEGIN slot=\(floatTabsDiagnosticSlotID(profile.id)) active=\(floatTabsDiagnosticSlotID(activeSlotID)) web=\(floatTabsDiagnosticWebViewID(webViewPool.existingWebView(for: profile.id)))"
        )
        fullscreenSourceProfile = profile
        cancelInactivePlan(slotID: profile.id)
        if hiddenActiveToken != nil, activeSlotID == profile.id {
            hiddenActiveToken = nil
        }
    }

    func endFullscreenSourceVisibility(profile: WebAppProfile) {
        guard fullscreenSourceProfile?.id == profile.id else { return }
        floatTabsRuntimeDiagnostic(
            "FULLSCREEN_END slot=\(floatTabsDiagnosticSlotID(profile.id)) active=\(floatTabsDiagnosticSlotID(activeSlotID))"
        )
        fullscreenSourceProfile = nil
    }

    /// Protects a second foreground WebView while WebKit exclusively owns the
    /// normal active WebView for element fullscreen. This preserves the existing
    /// one-active-Slot contract while preventing a visible companion from being
    /// evicted by an older inactive timer or memory-pressure pass.
    func beginSupplementalVisibility(profile: WebAppProfile) {
        floatTabsRuntimeDiagnostic(
            "SUPPLEMENTAL_BEGIN slot=\(floatTabsDiagnosticSlotID(profile.id)) previous=\(floatTabsDiagnosticSlotID(supplementalVisibleProfile?.id))"
        )
        if let previous = supplementalVisibleProfile,
           previous.id != profile.id {
            endSupplementalVisibility(profile: previous, prepareAsInactive: true)
        }
        supplementalVisibleProfile = profile
        cancelInactivePlan(slotID: profile.id)
    }

    func endSupplementalVisibility(
        profile: WebAppProfile,
        prepareAsInactive: Bool
    ) {
        guard supplementalVisibleProfile?.id == profile.id else { return }
        floatTabsRuntimeDiagnostic(
            "SUPPLEMENTAL_END slot=\(floatTabsDiagnosticSlotID(profile.id)) prepareInactive=\(prepareAsInactive) active=\(floatTabsDiagnosticSlotID(activeSlotID))"
        )
        supplementalVisibleProfile = nil
        guard prepareAsInactive, activeSlotID != profile.id else { return }
        prepareInactive(profile: profile, resetWarmRecency: true)
    }

    func remove(slotID: UUID) {
        floatTabsRuntimeDiagnostic(
            "REMOVE_SLOT slot=\(floatTabsDiagnosticSlotID(slotID)) active=\(floatTabsDiagnosticSlotID(activeSlotID))"
        )
        if activeSlotID == slotID {
            activeSlotID = nil
        }
        if fullscreenSourceProfile?.id == slotID {
            fullscreenSourceProfile = nil
        }
        if supplementalVisibleProfile?.id == slotID {
            supplementalVisibleProfile = nil
        }
        cancelInactivePlan(slotID: slotID)
        container.removeSlot(slotID)
    }

    func reset(slotIDs: Set<UUID>) {
        floatTabsRuntimeDiagnostic("RESET slots=\(slotIDs.count)")
        hiddenActiveToken = nil
        activeSlotID = nil
        fullscreenSourceProfile = nil
        supplementalVisibleProfile = nil
        inactivePlans.removeAll()
        mediaProtectedSlotIDs.removeAll()
        inactiveWarmRecency.removeAll()
        warmRecencyCounter = 0
        for slotID in slotIDs {
            container.removeSlot(slotID)
        }
    }

    func handleMemoryPressure(_ level: SlotMemoryPressureLevel) {
        floatTabsRuntimeDiagnostic(
            "MEMORY_PRESSURE level=\(String(describing: level)) active=\(floatTabsDiagnosticSlotID(activeSlotID)) resident=\(webViewPool.count)"
        )
        switch level {
        case .warning:
            evictInactiveWarmUntilResidentLimit(min(1, warmResidentLimit))
        case .critical:
            evictInactiveWarmUntilResidentLimit(0)
        }
    }

    var pendingColdReleaseCount: Int {
        inactivePlans.values.filter { $0.residencyPolicy == .cold }.count
    }

    var pendingWarmReleaseCount: Int {
        inactivePlans.values.filter { $0.residencyPolicy == .warm }.count
    }

    var mediaProtectedIDs: Set<UUID> {
        mediaProtectedSlotIDs
    }

    var isHiddenActiveGracePending: Bool {
        hiddenActiveToken != nil
    }

    private func configureMemoryPressureSource() {
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .main
        )
        memoryPressureSource = source
        source.setEventHandler { [weak self] in
            guard let self,
                  let data = self.memoryPressureSource?.data else { return }
            if data.contains(.critical) {
                self.handleMemoryPressure(.critical)
            } else if data.contains(.warning) {
                self.handleMemoryPressure(.warning)
            }
        }
        source.resume()
    }

    private func prepareInactive(profile: WebAppProfile, resetWarmRecency: Bool) {
        guard webViewPool.contains(slotID: profile.id) else {
            cancelInactivePlan(slotID: profile.id)
            return
        }

        if profile.backgroundMediaPolicy == .pauseWhenInactive {
            mediaPauseAction(profile.id)
        }

        switch profile.residencyPolicy {
        case .hot:
            cancelInactivePlan(slotID: profile.id)
        case .warm, .cold:
            ensureInactivePlan(for: profile, resetWarmRecency: resetWarmRecency)
        }
    }

    private func ensureInactivePlan(
        for profile: WebAppProfile,
        resetWarmRecency: Bool
    ) {
        if let existing = inactivePlans[profile.id],
           existing.residencyPolicy == profile.residencyPolicy,
           existing.backgroundMediaPolicy == profile.backgroundMediaPolicy {
            return
        }

        cancelInactivePlan(slotID: profile.id)
        let plan = InactivePlan(
            token: UUID(),
            residencyPolicy: profile.residencyPolicy,
            backgroundMediaPolicy: profile.backgroundMediaPolicy
        )
        inactivePlans[profile.id] = plan
        floatTabsRuntimeDiagnostic(
            "PLAN_CREATE slot=\(floatTabsDiagnosticSlotID(profile.id)) policy=\(profile.residencyPolicy.rawValue) media=\(profile.backgroundMediaPolicy.rawValue) token=\(String(plan.token.uuidString.prefix(8))) active=\(floatTabsDiagnosticSlotID(activeSlotID)) panelVisible=\(panelIsVisible)"
        )

        if profile.residencyPolicy == .warm {
            if resetWarmRecency || inactiveWarmRecency[profile.id] == nil {
                markWarmAsMostRecent(profile.id)
            }
        } else {
            inactiveWarmRecency.removeValue(forKey: profile.id)
        }

        if profile.backgroundMediaPolicy == .allowBackgroundAudio {
            evaluateMediaProtection(for: profile, plan: plan)
        } else {
            scheduleRelease(for: profile, plan: plan)
        }
    }

    private func evaluateMediaProtection(
        for profile: WebAppProfile,
        plan: InactivePlan
    ) {
        mediaPlayingQuery(profile.id) { [weak self] isPlaying in
            guard let self,
                  self.planMatches(plan, slotID: profile.id),
                  !self.isVisibleSlot(profile.id),
                  self.webViewPool.contains(slotID: profile.id) else {
                return
            }

            floatTabsRuntimeDiagnostic(
                "MEDIA_STATE slot=\(floatTabsDiagnosticSlotID(profile.id)) playing=\(isPlaying) policy=\(profile.residencyPolicy.rawValue)"
            )
            if isPlaying {
                self.mediaProtectedSlotIDs.insert(profile.id)
                self.scheduleMediaProtectionRecheck(for: profile, plan: plan)
            } else {
                let wasProtected = self.mediaProtectedSlotIDs.remove(profile.id) != nil
                if wasProtected, profile.residencyPolicy == .warm {
                    self.markWarmAsMostRecent(profile.id)
                }
                self.scheduleRelease(for: profile, plan: plan)
            }
        }
    }

    private func scheduleMediaProtectionRecheck(
        for profile: WebAppProfile,
        plan: InactivePlan
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + mediaProtectionPollDelay) { [weak self] in
            guard let self,
                  self.planMatches(plan, slotID: profile.id),
                  !self.isVisibleSlot(profile.id) else {
                return
            }
            self.evaluateMediaProtection(for: profile, plan: plan)
        }
    }

    private func scheduleRelease(
        for profile: WebAppProfile,
        plan: InactivePlan
    ) {
        guard planMatches(plan, slotID: profile.id) else { return }
        mediaProtectedSlotIDs.remove(profile.id)

        let delay: TimeInterval
        switch profile.residencyPolicy {
        case .hot:
            return
        case .warm:
            delay = warmReleaseDelay
        case .cold:
            delay = coldReleaseDelay
        }

        if profile.residencyPolicy == .warm {
            enforceWarmResidentLimit()
            guard planMatches(plan, slotID: profile.id) else { return }
        }

        floatTabsRuntimeDiagnostic(
            "RELEASE_SCHEDULE slot=\(floatTabsDiagnosticSlotID(profile.id)) policy=\(profile.residencyPolicy.rawValue) delay=\(delay) token=\(String(plan.token.uuidString.prefix(8))) active=\(floatTabsDiagnosticSlotID(activeSlotID))"
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            let matches = self.planMatches(plan, slotID: profile.id)
            let visible = self.isVisibleSlot(profile.id)
            let resident = self.webViewPool.contains(slotID: profile.id)
            floatTabsRuntimeDiagnostic(
                "RELEASE_TIMER_WAKE slot=\(floatTabsDiagnosticSlotID(profile.id)) policy=\(profile.residencyPolicy.rawValue) matches=\(matches) visible=\(visible) resident=\(resident) active=\(floatTabsDiagnosticSlotID(self.activeSlotID)) fullscreen=\(floatTabsDiagnosticSlotID(self.fullscreenSourceProfile?.id)) supplemental=\(floatTabsDiagnosticSlotID(self.supplementalVisibleProfile?.id))"
            )
            guard matches, !visible, resident else { return }

            if profile.backgroundMediaPolicy == .allowBackgroundAudio {
                self.mediaPlayingQuery(profile.id) { [weak self] isPlaying in
                    guard let self,
                          self.planMatches(plan, slotID: profile.id),
                          !self.isVisibleSlot(profile.id) else {
                        return
                    }
                    floatTabsRuntimeDiagnostic(
                        "RELEASE_MEDIA_CHECK slot=\(floatTabsDiagnosticSlotID(profile.id)) playing=\(isPlaying)"
                    )
                    if isPlaying {
                        self.mediaProtectedSlotIDs.insert(profile.id)
                        self.scheduleMediaProtectionRecheck(for: profile, plan: plan)
                    } else {
                        self.releaseInactiveSlot(slotID: profile.id)
                    }
                }
            } else {
                self.releaseInactiveSlot(slotID: profile.id)
            }
        }
    }

    private func scheduleHiddenActiveTransition(profile: WebAppProfile) {
        let token = UUID()
        hiddenActiveToken = token
        floatTabsRuntimeDiagnostic(
            "HIDDEN_ACTIVE_SCHEDULE slot=\(floatTabsDiagnosticSlotID(profile.id)) delay=\(hiddenActiveGraceDelay) token=\(String(token.uuidString.prefix(8))) policy=\(profile.residencyPolicy.rawValue)"
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + hiddenActiveGraceDelay) { [weak self] in
            guard let self else { return }
            let tokenMatches = self.hiddenActiveToken == token
            let isActive = self.activeSlotID == profile.id
            floatTabsRuntimeDiagnostic(
                "HIDDEN_ACTIVE_WAKE slot=\(floatTabsDiagnosticSlotID(profile.id)) tokenMatches=\(tokenMatches) panelVisible=\(self.panelIsVisible) activeMatches=\(isActive) active=\(floatTabsDiagnosticSlotID(self.activeSlotID))"
            )
            guard tokenMatches, !self.panelIsVisible, isActive else { return }

            self.hiddenActiveToken = nil
            self.activeSlotID = nil
            self.container.deactivate(
                slotID: profile.id,
                residencyPolicy: profile.residencyPolicy
            )
            self.prepareInactive(profile: profile, resetWarmRecency: true)
        }
    }

    private func enforceWarmResidentLimit() {
        evictInactiveWarmUntilResidentLimit(warmResidentLimit)
    }

    private func evictInactiveWarmUntilResidentLimit(_ targetLimit: Int) {
        let target = max(targetLimit, 0)
        let candidates = inactiveWarmRecency
            .filter { slotID, _ in
                !isVisibleSlot(slotID)
                    && !mediaProtectedSlotIDs.contains(slotID)
                    && webViewPool.contains(slotID: slotID)
                    && inactivePlans[slotID]?.residencyPolicy == .warm
            }
            .sorted { $0.value < $1.value }

        let excess = max(candidates.count - target, 0)
        guard excess > 0 else { return }
        for candidate in candidates.prefix(excess) {
            floatTabsRuntimeDiagnostic(
                "LRU_EVICT slot=\(floatTabsDiagnosticSlotID(candidate.key)) active=\(floatTabsDiagnosticSlotID(activeSlotID)) targetLimit=\(target)"
            )
            releaseInactiveSlot(slotID: candidate.key)
        }
    }

    private func markWarmAsMostRecent(_ slotID: UUID) {
        warmRecencyCounter &+= 1
        inactiveWarmRecency[slotID] = warmRecencyCounter
    }

    private func releaseInactiveSlot(slotID: UUID) {
        let visible = isVisibleSlot(slotID)
        let targetWebView = webViewPool.existingWebView(for: slotID)
        let currentWebView = container.currentWebView
        floatTabsRuntimeDiagnostic(
            "RELEASE_BEGIN slot=\(floatTabsDiagnosticSlotID(slotID)) visible=\(visible) active=\(floatTabsDiagnosticSlotID(activeSlotID)) fullscreen=\(floatTabsDiagnosticSlotID(fullscreenSourceProfile?.id)) supplemental=\(floatTabsDiagnosticSlotID(supplementalVisibleProfile?.id)) targetWeb=\(floatTabsDiagnosticWebViewID(targetWebView)) currentWeb=\(floatTabsDiagnosticWebViewID(currentWebView)) same=\(targetWebView === currentWebView) targetSuper=\(floatTabsDiagnosticSuperview(targetWebView)) currentSuper=\(floatTabsDiagnosticSuperview(currentWebView)) residentCount=\(webViewPool.count)"
        )
        guard !visible else {
            floatTabsRuntimeDiagnostic("RELEASE_ABORT_VISIBLE slot=\(floatTabsDiagnosticSlotID(slotID))")
            return
        }
        container.removeSlot(slotID)
        webViewPool.release(slotID: slotID)
        cancelInactivePlan(slotID: slotID)
        let currentAfter = container.currentWebView
        floatTabsRuntimeDiagnostic(
            "RELEASE_END slot=\(floatTabsDiagnosticSlotID(slotID)) active=\(floatTabsDiagnosticSlotID(activeSlotID)) currentWeb=\(floatTabsDiagnosticWebViewID(currentAfter)) currentSuper=\(floatTabsDiagnosticSuperview(currentAfter)) residentCount=\(webViewPool.count)"
        )
    }

    private func cancelInactivePlan(slotID: UUID) {
        if let plan = inactivePlans[slotID] {
            floatTabsRuntimeDiagnostic(
                "PLAN_CANCEL slot=\(floatTabsDiagnosticSlotID(slotID)) policy=\(plan.residencyPolicy.rawValue) token=\(String(plan.token.uuidString.prefix(8))) active=\(floatTabsDiagnosticSlotID(activeSlotID))"
            )
        }
        inactivePlans.removeValue(forKey: slotID)
        mediaProtectedSlotIDs.remove(slotID)
        inactiveWarmRecency.removeValue(forKey: slotID)
    }

    private func planMatches(_ plan: InactivePlan, slotID: UUID) -> Bool {
        inactivePlans[slotID]?.token == plan.token
    }

    private func isVisibleSlot(_ slotID: UUID) -> Bool {
        activeSlotID == slotID
            || fullscreenSourceProfile?.id == slotID
            || supplementalVisibleProfile?.id == slotID
    }
}
