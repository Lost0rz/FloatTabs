import AppKit
import Dispatch
import Foundation

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
    typealias AttentionProtectionQuery = @MainActor (UUID) -> Bool

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
    private let attentionProtectionQuery: AttentionProtectionQuery

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
        attentionProtectionQuery: @escaping AttentionProtectionQuery = { _ in false },
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
        self.attentionProtectionQuery = attentionProtectionQuery

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
            guard fullscreenSourceProfile?.id != activeProfile.id else { return }
            if activeProfile.backgroundMediaPolicy == .pauseWhenInactive {
                mediaPauseAction(activeProfile.id)
            }
            scheduleHiddenActiveTransition(profile: activeProfile)
        }
    }

    func activate(profile: WebAppProfile) {
        activeSlotID = profile.id
        cancelInactivePlan(slotID: profile.id)
        hiddenActiveToken = nil

        if !panelIsVisible {
            scheduleHiddenActiveTransition(profile: profile)
        }
    }

    func deactivate(profile: WebAppProfile) {
        guard fullscreenSourceProfile?.id != profile.id else { return }
        if activeSlotID == profile.id {
            activeSlotID = nil
        }
        hiddenActiveToken = nil
        container.deactivate(slotID: profile.id, residencyPolicy: profile.residencyPolicy)
        prepareInactive(profile: profile, resetWarmRecency: true)
    }

    /// Restarts normal Warm/Cold handling after an attention runtime reset
    /// removed protection from an already lifecycle-inactive Slot. A reset can
    /// arrive after the old release timer has fired and been skipped, so this
    /// deliberately creates a new plan rather than reusing the old deadline.
    func restartAfterAttentionProtectionEnded(profile: WebAppProfile) {
        let slotID = profile.id
        guard let existingPlan = inactivePlans[slotID],
              existingPlan.residencyPolicy == profile.residencyPolicy,
              existingPlan.backgroundMediaPolicy == profile.backgroundMediaPolicy,
              profile.residencyPolicy == .warm || profile.residencyPolicy == .cold,
              webViewPool.contains(slotID: slotID),
              !isVisibleSlot(slotID),
              !attentionProtectionQuery(slotID) else {
            return
        }

        // Keep the media authority intact while the fresh plan re-checks it.
        // The new media result will either continue protection or start a full
        // policy delay from that result's observation time.
        let preserveMediaProtection = mediaProtectedSlotIDs.contains(slotID)
        cancelInactivePlan(
            slotID: slotID,
            preservingMediaProtection: preserveMediaProtection
        )
        createInactivePlan(for: profile, resetWarmRecency: true)
    }

    /// Explicitly protects the WebView WebKit is presenting in element
    /// fullscreen. This is independent from shell visibility and active Tab
    /// selection so a hidden shell can never pause or evict visible content.
    func beginFullscreenSourceVisibility(profile: WebAppProfile) {
        fullscreenSourceProfile = profile
        cancelInactivePlan(slotID: profile.id)
        if hiddenActiveToken != nil, activeSlotID == profile.id {
            hiddenActiveToken = nil
        }
    }

    func endFullscreenSourceVisibility(profile: WebAppProfile) {
        guard fullscreenSourceProfile?.id == profile.id else { return }
        fullscreenSourceProfile = nil
    }

    /// Protects a second foreground WebView while WebKit exclusively owns the
    /// normal active WebView for element fullscreen. This preserves the existing
    /// one-active-Slot contract while preventing a visible companion from being
    /// evicted by an older inactive timer or memory-pressure pass.
    func beginSupplementalVisibility(profile: WebAppProfile) {
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
        supplementalVisibleProfile = nil
        guard prepareAsInactive, activeSlotID != profile.id else { return }
        prepareInactive(profile: profile, resetWarmRecency: true)
    }

    func remove(slotID: UUID) {
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
        createInactivePlan(for: profile, resetWarmRecency: resetWarmRecency)
    }

    private func createInactivePlan(
        for profile: WebAppProfile,
        resetWarmRecency: Bool
    ) {
        let plan = InactivePlan(
            token: UUID(),
            residencyPolicy: profile.residencyPolicy,
            backgroundMediaPolicy: profile.backgroundMediaPolicy
        )
        inactivePlans[profile.id] = plan

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

            if isPlaying {
                self.mediaProtectedSlotIDs.insert(profile.id)
                self.scheduleMediaProtectionRecheck(for: profile, plan: plan)
            } else {
                let wasProtected = self.mediaProtectedSlotIDs.remove(profile.id) != nil
                if wasProtected, profile.residencyPolicy == .warm {
                    self.markWarmAsMostRecent(profile.id)
                }
                guard !self.attentionProtectionQuery(profile.id) else {
                    return
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

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self,
                  self.planMatches(plan, slotID: profile.id),
                  !self.isVisibleSlot(profile.id),
                  self.webViewPool.contains(slotID: profile.id) else {
                return
            }

            // This callback may have been queued before generation began.
            // Attention is a live protection condition, not a plan snapshot.
            guard !self.isProactivelyProtected(slotID: profile.id) else {
                return
            }

            if profile.backgroundMediaPolicy == .allowBackgroundAudio {
                self.mediaPlayingQuery(profile.id) { [weak self] isPlaying in
                    guard let self,
                          self.planMatches(plan, slotID: profile.id),
                          !self.isVisibleSlot(profile.id),
                          !self.isProactivelyProtected(slotID: profile.id) else {
                        return
                    }
                    if isPlaying {
                        self.mediaProtectedSlotIDs.insert(profile.id)
                        self.scheduleMediaProtectionRecheck(for: profile, plan: plan)
                    } else {
                        self.releaseInactiveSlot(
                            slotID: profile.id,
                            expectedPlan: plan
                        )
                    }
                }
            } else {
                self.releaseInactiveSlot(
                    slotID: profile.id,
                    expectedPlan: plan
                )
            }
        }
    }

    private func scheduleHiddenActiveTransition(profile: WebAppProfile) {
        let token = UUID()
        hiddenActiveToken = token

        DispatchQueue.main.asyncAfter(deadline: .now() + hiddenActiveGraceDelay) { [weak self] in
            guard let self,
                  self.hiddenActiveToken == token,
                  !self.panelIsVisible,
                  self.activeSlotID == profile.id else {
                return
            }

            // The lifecycle Boolean is an intent signal, not proof that the
            // Web surface is off-screen. WebKit fullscreen restoration can
            // reorder the source window independently, so never detach the
            // selected page while its real host window is still presented.
            guard self.container.window?.isVisible != true else {
                self.hiddenActiveToken = nil
                return
            }

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
                    && !attentionProtectionQuery(slotID)
                    && webViewPool.contains(slotID: slotID)
                    && inactivePlans[slotID]?.residencyPolicy == .warm
            }
            .sorted { $0.value < $1.value }

        let excess = max(candidates.count - target, 0)
        guard excess > 0 else { return }
        for candidate in candidates.prefix(excess) {
            guard let plan = inactivePlans[candidate.key] else { continue }
            releaseInactiveSlot(
                slotID: candidate.key,
                expectedPlan: plan
            )
        }
    }

    private func markWarmAsMostRecent(_ slotID: UUID) {
        warmRecencyCounter &+= 1
        inactiveWarmRecency[slotID] = warmRecencyCounter
    }

    private func releaseInactiveSlot(
        slotID: UUID,
        expectedPlan: InactivePlan? = nil
    ) {
        guard let currentPlan = inactivePlans[slotID],
              expectedPlan.map({ $0.token == currentPlan.token }) ?? true,
              !isVisibleSlot(slotID),
              !isProactivelyProtected(slotID: slotID),
              webViewPool.contains(slotID: slotID) else {
            return
        }
        container.removeSlot(slotID)
        webViewPool.release(slotID: slotID)
        cancelInactivePlan(slotID: slotID)
    }

    private func cancelInactivePlan(
        slotID: UUID,
        preservingMediaProtection: Bool = false
    ) {
        inactivePlans.removeValue(forKey: slotID)
        if !preservingMediaProtection {
            mediaProtectedSlotIDs.remove(slotID)
        }
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

    /// Composes independent lifecycle authorities at the eviction boundary.
    /// Attention state remains owned by WebAttentionCoordinator and media state
    /// remains owned by this coordinator's existing media query/storage.
    private func isProactivelyProtected(slotID: UUID) -> Bool {
        mediaProtectedSlotIDs.contains(slotID)
            || attentionProtectionQuery(slotID)
    }
}
