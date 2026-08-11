import Dispatch
import Foundation

enum SlotMemoryPressureLevel {
    case warning
    case critical
}

@MainActor
final class SlotLifecycleCoordinator {
    static let defaultColdReleaseDelay: TimeInterval = 30
    static let defaultWarmReleaseDelay: TimeInterval = 120
    static let defaultHiddenActiveGraceDelay: TimeInterval = 120
    static let defaultMediaProtectionPollDelay: TimeInterval = 10
    static let defaultWarmResidentLimit = 2

    typealias MediaPlayingQuery = (UUID, @escaping (Bool) -> Void) -> Void
    typealias ElementFullscreenQuery = (UUID) -> Bool

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
    private let elementFullscreenQuery: ElementFullscreenQuery

    private var inactivePlans: [UUID: InactivePlan] = [:]
    private var mediaProtectedSlotIDs = Set<UUID>()
    private var fullscreenProtectedSlotIDs = Set<UUID>()
    private var fullscreenProtectionTokens: [UUID: UUID] = [:]
    private var inactiveWarmRecency: [UUID: UInt64] = [:]
    private var warmRecencyCounter: UInt64 = 0
    private var hiddenActiveToken: UUID?
    private var activeSlotID: UUID?
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
        elementFullscreenQuery: ElementFullscreenQuery? = nil,
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
        self.elementFullscreenQuery = elementFullscreenQuery ?? { [weak webViewPool] slotID in
            webViewPool?.isPresentingElementFullscreen(slotID: slotID) ?? false
        }

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
        for slotID in Array(fullscreenProtectionTokens.keys) where
            !validIDs.contains(slotID) || !webViewPool.contains(slotID: slotID) {
            cancelFullscreenProtection(slotID: slotID)
        }

        for profile in profiles {
            if elementFullscreenQuery(profile.id) {
                cancelInactivePlan(slotID: profile.id)
                fullscreenProtectedSlotIDs.insert(profile.id)
                if profile.id != activeSlotID {
                    ensureFullscreenInactiveProtection(for: profile)
                }
                continue
            }

            if fullscreenProtectedSlotIDs.contains(profile.id) {
                cancelFullscreenProtection(slotID: profile.id)
            }

            if profile.id == activeSlotID {
                cancelInactivePlan(slotID: profile.id)
                continue
            }
            guard webViewPool.contains(slotID: profile.id) else {
                cancelInactivePlan(slotID: profile.id)
                continue
            }

            if profile.backgroundMediaPolicy == .pauseWhenInactive {
                webViewPool.pauseMediaPlayback(slotID: profile.id)
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
            if !elementFullscreenQuery(activeProfile.id) {
                cancelFullscreenProtection(slotID: activeProfile.id)
            }
        } else if activeSlotID == activeProfile.id {
            scheduleHiddenActiveTransition(profile: activeProfile)
        }
    }

    func activate(profile: WebAppProfile) {
        activeSlotID = profile.id
        cancelInactivePlan(slotID: profile.id)
        hiddenActiveToken = nil

        if elementFullscreenQuery(profile.id) {
            fullscreenProtectedSlotIDs.insert(profile.id)
        } else {
            cancelFullscreenProtection(slotID: profile.id)
        }

        if !panelIsVisible {
            scheduleHiddenActiveTransition(profile: profile)
        }
    }

    func deactivate(profile: WebAppProfile) {
        if activeSlotID == profile.id {
            activeSlotID = nil
        }
        hiddenActiveToken = nil

        // Shell selection and fullscreen ownership are independent. A fullscreen
        // Slot is not inactive merely because the user selected ChatGPT in the
        // FloatTabs shell. Do not pause media, detach its view, or start an
        // eviction plan until WebKit actually exits fullscreen.
        if elementFullscreenQuery(profile.id) {
            cancelInactivePlan(slotID: profile.id)
            fullscreenProtectedSlotIDs.insert(profile.id)
            ensureFullscreenInactiveProtection(for: profile)
            return
        }

        cancelFullscreenProtection(slotID: profile.id)
        container.deactivate(slotID: profile.id, residencyPolicy: profile.residencyPolicy)
        prepareInactive(profile: profile, resetWarmRecency: true)
    }

    func remove(slotID: UUID) {
        if activeSlotID == slotID {
            activeSlotID = nil
        }
        cancelInactivePlan(slotID: slotID)
        cancelFullscreenProtection(slotID: slotID)
        container.removeSlot(slotID)
    }

    func reset(slotIDs: Set<UUID>) {
        hiddenActiveToken = nil
        activeSlotID = nil
        inactivePlans.removeAll()
        mediaProtectedSlotIDs.removeAll()
        fullscreenProtectedSlotIDs.removeAll()
        fullscreenProtectionTokens.removeAll()
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
        mediaProtectedSlotIDs.union(fullscreenProtectedSlotIDs)
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
            cancelFullscreenProtection(slotID: profile.id)
            return
        }

        if elementFullscreenQuery(profile.id) {
            cancelInactivePlan(slotID: profile.id)
            fullscreenProtectedSlotIDs.insert(profile.id)
            ensureFullscreenInactiveProtection(for: profile)
            return
        }

        cancelFullscreenProtection(slotID: profile.id)

        if profile.backgroundMediaPolicy == .pauseWhenInactive {
            webViewPool.pauseMediaPlayback(slotID: profile.id)
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
        if elementFullscreenQuery(profile.id) {
            fullscreenProtectedSlotIDs.insert(profile.id)
            ensureFullscreenInactiveProtection(for: profile)
            return
        }

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
                  self.activeSlotID != profile.id,
                  self.webViewPool.contains(slotID: profile.id) else {
                return
            }

            if self.elementFullscreenQuery(profile.id) {
                self.cancelInactivePlan(slotID: profile.id)
                self.fullscreenProtectedSlotIDs.insert(profile.id)
                self.ensureFullscreenInactiveProtection(for: profile)
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
                  self.activeSlotID != profile.id else {
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
                  self.activeSlotID != profile.id,
                  self.webViewPool.contains(slotID: profile.id) else {
                return
            }

            if self.elementFullscreenQuery(profile.id) {
                self.cancelInactivePlan(slotID: profile.id)
                self.fullscreenProtectedSlotIDs.insert(profile.id)
                self.ensureFullscreenInactiveProtection(for: profile)
                return
            }

            if profile.backgroundMediaPolicy == .allowBackgroundAudio {
                self.mediaPlayingQuery(profile.id) { [weak self] isPlaying in
                    guard let self,
                          self.planMatches(plan, slotID: profile.id),
                          self.activeSlotID != profile.id else {
                        return
                    }
                    if self.elementFullscreenQuery(profile.id) {
                        self.cancelInactivePlan(slotID: profile.id)
                        self.fullscreenProtectedSlotIDs.insert(profile.id)
                        self.ensureFullscreenInactiveProtection(for: profile)
                    } else if isPlaying {
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

        DispatchQueue.main.asyncAfter(deadline: .now() + hiddenActiveGraceDelay) { [weak self] in
            guard let self,
                  self.hiddenActiveToken == token,
                  !self.panelIsVisible,
                  self.activeSlotID == profile.id else {
                return
            }

            if self.elementFullscreenQuery(profile.id) {
                self.scheduleHiddenFullscreenProtectionRecheck(profile: profile)
                return
            }

            self.finishHiddenActiveTransition(profile: profile)
        }
    }

    /// While WebKit owns an element-fullscreen presentation it has temporarily
    /// reparented the live WKWebView out of the FloatTabs container. Keep the Slot
    /// active and resident, then start a fresh hidden-active grace period only
    /// after fullscreen actually ends.
    private func scheduleHiddenFullscreenProtectionRecheck(profile: WebAppProfile) {
        let token = UUID()
        hiddenActiveToken = token
        fullscreenProtectedSlotIDs.insert(profile.id)

        DispatchQueue.main.asyncAfter(deadline: .now() + mediaProtectionPollDelay) { [weak self] in
            guard let self,
                  self.hiddenActiveToken == token,
                  !self.panelIsVisible,
                  self.activeSlotID == profile.id else {
                return
            }

            if self.elementFullscreenQuery(profile.id) {
                self.scheduleHiddenFullscreenProtectionRecheck(profile: profile)
            } else {
                self.fullscreenProtectedSlotIDs.remove(profile.id)
                self.scheduleHiddenActiveTransition(profile: profile)
            }
        }
    }

    private func finishHiddenActiveTransition(profile: WebAppProfile) {
        hiddenActiveToken = nil
        activeSlotID = nil
        container.deactivate(
            slotID: profile.id,
            residencyPolicy: profile.residencyPolicy
        )
        prepareInactive(profile: profile, resetWarmRecency: true)
    }

    /// A fullscreen Slot can remain protected after the shell selects another
    /// Slot. Poll until WebKit returns the live view, then only at that point run
    /// ordinary inactive handling. This is the explicit separation between
    /// fullscreen owner and shell-active Slot.
    private func ensureFullscreenInactiveProtection(for profile: WebAppProfile) {
        guard activeSlotID != profile.id,
              webViewPool.contains(slotID: profile.id) else {
            return
        }
        guard fullscreenProtectionTokens[profile.id] == nil else { return }

        let token = UUID()
        fullscreenProtectionTokens[profile.id] = token
        fullscreenProtectedSlotIDs.insert(profile.id)

        DispatchQueue.main.asyncAfter(deadline: .now() + mediaProtectionPollDelay) { [weak self] in
            guard let self,
                  self.fullscreenProtectionTokens[profile.id] == token,
                  self.activeSlotID != profile.id,
                  self.webViewPool.contains(slotID: profile.id) else {
                return
            }

            if self.elementFullscreenQuery(profile.id) {
                self.fullscreenProtectionTokens.removeValue(forKey: profile.id)
                self.ensureFullscreenInactiveProtection(for: profile)
                return
            }

            self.fullscreenProtectionTokens.removeValue(forKey: profile.id)
            self.fullscreenProtectedSlotIDs.remove(profile.id)
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
                activeSlotID != slotID
                    && !mediaProtectedSlotIDs.contains(slotID)
                    && !fullscreenProtectedSlotIDs.contains(slotID)
                    && !elementFullscreenQuery(slotID)
                    && webViewPool.contains(slotID: slotID)
                    && inactivePlans[slotID]?.residencyPolicy == .warm
            }
            .sorted { $0.value < $1.value }

        let excess = max(candidates.count - target, 0)
        guard excess > 0 else { return }
        for candidate in candidates.prefix(excess) {
            releaseInactiveSlot(slotID: candidate.key)
        }
    }

    private func markWarmAsMostRecent(_ slotID: UUID) {
        warmRecencyCounter &+= 1
        inactiveWarmRecency[slotID] = warmRecencyCounter
    }

    private func releaseInactiveSlot(slotID: UUID) {
        guard activeSlotID != slotID else { return }
        if elementFullscreenQuery(slotID) {
            fullscreenProtectedSlotIDs.insert(slotID)
            cancelInactivePlan(slotID: slotID)
            return
        }
        container.removeSlot(slotID)
        webViewPool.release(slotID: slotID)
        cancelInactivePlan(slotID: slotID)
        cancelFullscreenProtection(slotID: slotID)
    }

    private func cancelInactivePlan(slotID: UUID) {
        inactivePlans.removeValue(forKey: slotID)
        mediaProtectedSlotIDs.remove(slotID)
        inactiveWarmRecency.removeValue(forKey: slotID)
    }

    private func cancelFullscreenProtection(slotID: UUID) {
        fullscreenProtectionTokens.removeValue(forKey: slotID)
        fullscreenProtectedSlotIDs.remove(slotID)
    }

    private func planMatches(_ plan: InactivePlan, slotID: UUID) -> Bool {
        inactivePlans[slotID]?.token == plan.token
    }
}
